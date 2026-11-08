#!/usr/bin/env bash
# omafan silent mode: hold the fans at a near-zero speed and re-apply it every
# second, so whatever NBFC's curve or the laptop's firmware decide, the fans go
# back to quiet. Runs as a user systemd service, so it survives logout/reboot.
#
#   ./silence.sh install        # turn silent mode on (now and at every login)
#   ./silence.sh remove         # turn it off, fans back to auto
#   ./silence.sh status         # "silent=on|off tuned=yes|no"
#   ./silence.sh run            # the loop itself (what the service runs)
#   sudo ./silence.sh tune      # optional: quieter, see tune() below
#   sudo ./silence.sh untune    # undo tune
#
# Settings (environment, read by install and baked into the service):
#   OMAFAN_SPEED     speed to hold, % (default 1; see below why not 0)
#   OMAFAN_FANS      NBFC fan indexes to hold, e.g. "0" for the CPU fan only,
#                    or "all" (default)
#   OMAFAN_INTERVAL  seconds between checks (default 1)
#   OMAFAN_MAX_C     safety: at this CPU temperature the fans go back to auto
#                    (default 95)
#   OMAFAN_RESUME_C  ...and silent mode resumes once it cools to this (default 80)
#
# Limits: NBFC's own critical mode (CriticalTemperature in the laptop config)
# still runs the fans at full speed above that temperature, and some laptop
# firmwares (the Acer Nitro EC, for one) spin the fans up on their own when
# their internal sensors run warm, whatever NBFC writes. Silent mode wins most
# of the time on a lightly loaded machine; under heavy load the firmware wins.
set -euo pipefail

unit="omafan-silence.service"
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
dir="$(cd "$(dirname "$0")" && pwd)"

MAX_C="${OMAFAN_MAX_C:-95}"
RESUME_C="${OMAFAN_RESUME_C:-80}"
INTERVAL="${OMAFAN_INTERVAL:-1}"
# 1 %, not 0: on the Acer Nitro EC a 0 write lets the firmware spin the fan up
# on its own; 1 % keeps the fan stopped and in manual mode.
SPEED="${OMAFAN_SPEED:-1}"
FANS="${OMAFAN_FANS:-all}"

fan_indexes() {
  if [[ $FANS == all ]]; then
    local n
    n="$(nbfc status -a 2>/dev/null | grep -c '^Fan Display Name' || true)"
    (( n > 0 )) && seq 0 $(( n - 1 ))
  else
    echo "$FANS"
  fi
}

cpu_temp() {
  local h
  for h in /sys/class/hwmon/hwmon*; do
    case "$(cat "$h/name" 2>/dev/null)" in
      k10temp|coretemp|zenpower)
        echo $(( $(cat "$h/temp1_input") / 1000 ))
        return
        ;;
    esac
  done
  echo 0
}

release_fans() {
  local f
  for f in $(fan_indexes); do nbfc set -a -f "$f" >/dev/null 2>&1 || true; done
}

run_loop() {
  local hot=0 t f want prev_profile=""
  want="$(printf '%.2f' "$SPEED")"
  if command -v powerprofilesctl >/dev/null; then
    prev_profile="$(powerprofilesctl get 2>/dev/null || true)"
    powerprofilesctl set power-saver 2>/dev/null || true
  fi
  trap 'release_fans
        if [[ -n $prev_profile ]]; then powerprofilesctl set "$prev_profile" 2>/dev/null || true; fi
        exit 0' INT TERM

  while :; do
    t="$(cpu_temp)"
    if (( hot == 0 && t >= MAX_C )); then
      hot=1
      echo "CPU ${t}°C >= ${MAX_C}°C: fans back to auto until ${RESUME_C}°C"
      release_fans
    elif (( hot == 1 && t <= RESUME_C )); then
      hot=0
      echo "CPU ${t}°C: silent again"
    fi
    if (( hot == 0 )); then
      # Only talk to the service when a held fan drifted off the target.
      for f in $(fan_indexes); do
        if nbfc status -f "$f" 2>/dev/null | grep -E '^Target Fan Speed' | grep -qv ": $want"; then
          nbfc set -s "$SPEED" -f "$f" >/dev/null 2>&1 || true
        fi
      done
    fi
    sleep "$INTERVAL"
  done
}

install_unit() {
  mkdir -p "$units"
  cat >"$units/$unit" <<UNIT
[Unit]
Description=omafan silent mode (fans held at ${SPEED}%%, back to auto at ${MAX_C}°C)
After=default.target

[Service]
ExecStart=/usr/bin/env bash "$dir/silence.sh" run
Environment="OMAFAN_MAX_C=${MAX_C}" "OMAFAN_RESUME_C=${RESUME_C}" "OMAFAN_INTERVAL=${INTERVAL}" "OMAFAN_SPEED=${SPEED}" "OMAFAN_FANS=${FANS}"
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
UNIT
  systemctl --user daemon-reload
  systemctl --user enable "$unit" 2>/dev/null
  systemctl --user restart "$unit"
  echo "Silent mode on. Turn it off with: $0 remove"
}

remove_unit() {
  systemctl --user disable --now "$unit" 2>/dev/null || true
  rm -f "$units/$unit"
  systemctl --user daemon-reload
  nbfc set -a >/dev/null 2>&1 || true
  echo "Silent mode off, fans back to auto."
}

config_name() {
  jq -r '.SelectedConfigId // empty' /etc/nbfc/nbfc.json 2>/dev/null
}

status() {
  local silent=off tuned=no name
  systemctl --user is-active --quiet "$unit" && silent=on
  name="$(config_name)"
  [[ -n $name && -f "/var/lib/nbfc/configs/$name.json" ]] && tuned=yes
  echo "silent=$silent tuned=$tuned"
}

boost_file() {
  if [[ -f /sys/devices/system/cpu/cpufreq/boost ]]; then
    echo "/sys/devices/system/cpu/cpufreq/boost 0 1"
  elif [[ -f /sys/devices/system/cpu/intel_pstate/no_turbo ]]; then
    echo "/sys/devices/system/cpu/intel_pstate/no_turbo 1 0"
  fi
}

# Optional, root only. Makes silent mode hold much better:
#  - a copy of the laptop's NBFC config in /var/lib/nbfc/configs (NBFC prefers
#    it, and package updates leave it alone) with the critical temperature
#    raised to OMAFAN_CRITICAL_C (default 98), a 5 °C instead of 15 °C exit
#    margin, a faster EC poll (OMAFAN_POLL_MS, default 200) and the "manual
#    mode" registers re-written on every fan write, so the firmware cannot
#    quietly take the fan back;
#  - CPU boost off, now and at every boot: the CPU runs at its base clock and
#    makes far less heat, so the firmware has less reason to spin up;
#  - optionally a max clock (OMAFAN_MAX_FREQ_KHZ, off by default).
tune() {
  [[ $EUID -eq 0 ]] || { echo "Needs root: sudo $0 tune" >&2; exit 1; }
  command -v jq >/dev/null || { echo "Needs jq: sudo pacman -S jq" >&2; exit 1; }
  local crit="${OMAFAN_CRITICAL_C:-98}" poll="${OMAFAN_POLL_MS:-200}" maxf="${OMAFAN_MAX_FREQ_KHZ:-}"
  local name src dst boost f
  name="$(config_name)"
  src="/usr/share/nbfc/configs/$name.json"
  [[ -n $name && -f $src ]] || { echo "No NBFC config selected (/etc/nbfc/nbfc.json)." >&2; exit 1; }
  dst="/var/lib/nbfc/configs/$name.json"
  mkdir -p /var/lib/nbfc/configs
  jq --argjson c "$crit" --argjson p "$poll" '
    .CriticalTemperature = $c
    | .CriticalTemperatureOffset = 5
    | .EcPollInterval = $p
    | .RegisterWriteConfigurations |= ((. // []) | map(.WriteOccasion = "OnWriteFanSpeed"))
  ' "$src" >"$dst.tmp"
  mv "$dst.tmp" "$dst"

  boost="$(boost_file)"
  : >/etc/tmpfiles.d/omafan-tune.conf
  if [[ -n $boost ]]; then
    read -r f off _ <<<"$boost"
    echo "w $f - - - - $off" >>/etc/tmpfiles.d/omafan-tune.conf
    echo "$off" >"$f" 2>/dev/null || true
  fi
  if [[ -n $maxf ]]; then
    echo "w /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq - - - - $maxf" >>/etc/tmpfiles.d/omafan-tune.conf
    for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do echo "$maxf" >"$f"; done
  fi
  systemctl restart nbfc_service
  echo "Tuned: NBFC critical at ${crit}°C, EC poll ${poll} ms, CPU boost off${maxf:+, max ${maxf} kHz}. Undo: sudo $0 untune"
}

untune() {
  [[ $EUID -eq 0 ]] || { echo "Needs root: sudo $0 untune" >&2; exit 1; }
  local name boost f on
  name="$(config_name)"
  [[ -n $name ]] && rm -f "/var/lib/nbfc/configs/$name.json"
  # omafan-noboost.conf: name used by the first versions of tune.
  rm -f /etc/tmpfiles.d/omafan-tune.conf /etc/tmpfiles.d/omafan-noboost.conf
  boost="$(boost_file)"
  if [[ -n $boost ]]; then
    read -r f _ on <<<"$boost"
    echo "$on" >"$f" 2>/dev/null || true
  fi
  for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq; do
    cat "${f%scaling_max_freq}cpuinfo_max_freq" >"$f" 2>/dev/null || true
  done
  systemctl restart nbfc_service
  echo "Back to the stock NBFC config, CPU boost on."
}

case "${1:-}" in
  install) install_unit ;;
  remove) remove_unit ;;
  status) status ;;
  run) run_loop ;;
  tune) tune ;;
  untune) untune ;;
  *) echo "usage: $0 install|remove|status|run|tune|untune" >&2; exit 2 ;;
esac
