// Pure helpers for the omafan panel: parse `nbfc status -a` and decide what
// the panel shows. Kept free of QML so test/model.test.js runs them under node.

// `nbfc status -a` prints "Key : Value" lines, a service block first, then one
// block per fan separated by blank lines. Only the keys below are read; the
// rest are ignored so a newer nbfc that adds fields still parses.
function parseStatus(raw) {
  var result = { config: "", readOnly: false, fans: [] }
  var blocks = String(raw || "").split(/\n\s*\n/)
  for (var b = 0; b < blocks.length; b++) {
    var fields = {}
    var lines = blocks[b].split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = /^\s*([^:]+?)\s*:\s*(.*?)\s*$/.exec(lines[i])
      if (match) fields[match[1]] = match[2]
    }
    if (fields["Selected Config Name"] !== undefined) {
      result.config = clip(fields["Selected Config Name"], 80)
      result.readOnly = fields["Read-only"] === "true"
    }
    if (fields["Fan Display Name"] !== undefined && result.fans.length < 8) {
      result.fans.push({
        name: clip(fields["Fan Display Name"], 60),
        temperature: number(fields["Temperature"]),
        auto: fields["Auto Control Enabled"] === "true",
        critical: fields["Critical Mode Enabled"] === "true",
        current: percent(fields["Current Fan Speed"]),
        target: percent(fields["Target Fan Speed"])
      })
    }
  }
  return result
}

function clip(text, length) {
  return String(text || "").slice(0, length)
}

function number(text) {
  var value = parseFloat(text)
  return isFinite(value) ? value : NaN
}

function percent(text) {
  var value = number(text)
  return isFinite(value) ? Math.max(0, Math.min(100, value)) : NaN
}

// One mode for all fans: "auto", "manual" (every fan pinned to the same
// speed), "mixed", or "none" before the first reading.
function mode(fans) {
  if (!fans || fans.length === 0) return { kind: "none", speed: NaN }
  // Critical mode overrides whatever was asked: nbfc runs the fan at full
  // speed until it cools down, so no preset is the active one.
  if (fans.some(function(f) { return f.critical })) return { kind: "critical", speed: 100 }
  var allAuto = fans.every(function(f) { return f.auto })
  if (allAuto) return { kind: "auto", speed: NaN }
  var anyAuto = fans.some(function(f) { return f.auto })
  var first = Math.round(fans[0].target)
  var same = fans.every(function(f) { return Math.round(f.target) === first })
  if (!anyAuto && same) return { kind: "manual", speed: first }
  return { kind: "mixed", speed: NaN }
}

function hottest(fans) {
  var max = NaN
  for (var i = 0; i < (fans || []).length; i++) {
    var t = fans[i].temperature
    if (isFinite(t) && (!isFinite(max) || t > max)) max = t
  }
  return max
}

// Heat bands for the temperature color: calm, warm, hot.
function heat(temperature) {
  if (!isFinite(temperature)) return "calm"
  if (temperature >= 85) return "hot"
  if (temperature >= 70) return "warm"
  return "calm"
}

// The preset chips: value "auto" or a fixed percentage; "0" stops the fan.
// Stopping is safe to offer because nbfc's critical mode still runs the fan
// at full speed once the config's critical temperature is reached.
var presets = ["auto", "0", "50", "75", "100"]

function presetForMode(m) {
  if (m.kind === "auto") return "auto"
  if (m.kind === "manual" && presets.indexOf(String(m.speed)) !== -1) return String(m.speed)
  return ""
}

// The nbfc command for a preset or speed. Speeds are clamped and rounded so
// nothing but a whole percentage ever reaches the argument list.
// A fanIndex of -1 (or none) sets every fan; otherwise only that one.
function setCommand(value, fanIndex) {
  var command
  if (value === "auto") {
    command = ["nbfc", "set", "-a"]
  } else {
    var speed = Math.round(Number(value))
    if (!isFinite(speed)) return null
    command = ["nbfc", "set", "-s", String(Math.max(0, Math.min(100, speed)))]
  }
  var index = Number(fanIndex)
  if (Number.isInteger(index) && index >= 0 && index < 8) command.push("-f", String(index))
  return command
}

// The fans a control acts on: all of them, or the one picked.
function targetFans(fans, fanIndex) {
  if (fanIndex >= 0 && fanIndex < (fans || []).length) return [fans[fanIndex]]
  return fans || []
}

// A short chip label for a fan from its nbfc display name: GPU or CPU when
// the name gives it away, otherwise "Fan N" (the caller translates the kind).
function fanKind(name, index) {
  var text = String(name || "")
  if (/nvidia|geforce|radeon|\bgpu\b|\brtx\b|\bgtx\b|arc a/i.test(text)) return { kind: "gpu", number: index + 1 }
  if (/ryzen|intel|core|\bcpu\b|processor/i.test(text)) return { kind: "cpu", number: index + 1 }
  return { kind: "fan", number: index + 1 }
}

// Digit shortcuts: 1–9 pin 10–90 %, 0 pins 100 %.
function speedForDigit(text) {
  if (!/^[0-9]$/.test(text)) return NaN
  var digit = Number(text)
  return digit === 0 ? 100 : digit * 10
}

// Silent mode lives in silence.sh next to this file, as a user systemd
// service. `silence.sh status` prints "silent=on|off tuned=yes|no".
function parseSilence(raw) {
  var text = String(raw || "")
  return { silent: /\bsilent=on\b/.test(text), tuned: /\btuned=yes\b/.test(text) }
}

// A file:// URL from Qt.resolvedUrl to a plain path for the argument list.
function localPath(url) {
  var text = String(url || "")
  if (text.indexOf("file://") !== 0) return ""
  return decodeURIComponent(text.slice("file://".length))
}

// The command that turns silent mode on ("install") or off ("remove").
function silenceCommand(action, scriptPath) {
  if (["install", "remove", "status"].indexOf(action) === -1 || !scriptPath) return null
  return ["bash", scriptPath, action]
}

if (typeof module !== "undefined") {
  module.exports = { parseStatus, mode, targetFans, fanKind, hottest, heat, presets, presetForMode, setCommand, speedForDigit, parseSilence, localPath, silenceCommand }
}
