#!/usr/bin/env bash
# Adds (or removes) an "omafan" entry in the app launcher (Super + Space)
# that toggles the fan panel.
#
#   ./launcher.sh install   # add the entry (default)
#   ./launcher.sh remove    # take it out again
#
# `omarchy plugin add` never runs plugin code, so this is a separate, opt-in
# step. It only writes ~/.local/share/applications/omafan.desktop.
set -euo pipefail

id="io.github.rob-d3v.omafan"
dir="$(cd "$(dirname "$0")" && pwd)"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
file="$apps/omafan.desktop"

install_entry() {
  mkdir -p "$apps"
  local tmp
  tmp="$(mktemp "$apps/.omafan.XXXXXX")"
  cat >"$tmp" <<DESKTOP
[Desktop Entry]
Type=Application
Name=omafan
Name[pt_BR]=omafan (ventoinhas)
GenericName=Fan control
GenericName[pt_BR]=Controle das ventoinhas
Comment=CPU and GPU fan speed, like NitroSense
Comment[pt_BR]=Velocidade das ventoinhas da CPU e da GPU, como o NitroSense
Keywords=fan;fans;nitro;nitrosense;nbfc;cooler;turbo;ventoinha;ventilador;
Exec=omarchy-shell $id toggle
Icon=$dir/icon.svg
Terminal=false
Categories=Settings;HardwareSettings;
DESKTOP
  mv "$tmp" "$file"
  echo "Added omafan to the app launcher ($file)"
}

remove_entry() {
  if [[ -f $file ]]; then
    rm -f "$file"
    echo "Removed $file"
  else
    echo "No omafan launcher entry found."
  fi
}

case "${1:-install}" in
  install) install_entry ;;
  remove) remove_entry ;;
  *) echo "usage: $0 [install|remove]" >&2; exit 2 ;;
esac
