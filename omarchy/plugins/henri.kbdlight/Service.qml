// Keyboard backlight -- the macOS way.
//
// One level, set in Control Center (henri.control-center-v2 reads this
// service and calls setLevel / setTimeoutSeconds). The keys stay lit while
// someone types and fade out `timeout` seconds after the last key press; the
// next press fades them back in.
//
// Key presses. Hyprland reports them from Lua (hl.on("input.keyboard.key"),
// input.lua) as `custom>>kbdlight key` on its event socket, at most once per
// second -- no /dev/input access, so no `input` group and no root. The event
// carries no device, so a press on an external keyboard counts too.
//
// The LED. PWM on /sys/class/leds/kbd_backlight, written through logind by
// one long-lived brightnessctl loop (the fade sends a value per frame, which
// must not mean a fork per frame). Perceptual curve (squared) like the screen
// backlight in henri.osd.
//
// State: ~/.local/state/henri/kbdlight.json ({ level, timeout }), machine-local.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string device: "kbd_backlight"
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/henri/kbdlight.json"

  property real maxRaw: 0
  readonly property bool available: maxRaw > 0

  // What the user set (0 = off, 1 = full) and how long the keys stay lit
  // after the last press (seconds, 0 = never turn off).
  property real level: 0.5
  property int timeout: 30
  // Lit: a key was pressed within `timeout`.
  property bool lit: true
  readonly property var timeoutChoices: [5, 30, 60, 300, 0]

  function clamp(v) { return Math.max(0, Math.min(1, v)) }
  function rawFor(l) { return l <= 0 ? 0 : Math.max(1, Math.round(maxRaw * l * l)) }

  function setLevel(v) {
    level = clamp(v)
    wake()
    save.restart()
  }
  function setTimeoutSeconds(s) {
    timeout = Math.max(0, Math.round(s))
    wake()
    save.restart()
  }
  function wake() {
    lit = true
    if (timeout > 0) idle.restart()
    else idle.stop()
  }

  Timer {
    id: idle
    interval: Math.max(1, root.timeout) * 1000
    onTriggered: root.lit = false
  }

  Process {
    running: true
    command: ["brightnessctl", "-m", "-d", root.device]
    stdout: StdioCollector {
      onStreamFinished: {
        var f = text.trim().split("\n")[0].split(",")
        if (f.length < 5) return
        root.sentRaw = parseInt(f[2], 10)
        root.maxRaw = parseInt(f[4], 10) || 0
        // Start the fade from where the LED is, not from black.
        if (root.maxRaw > 0) glow.snap(Math.sqrt(root.clamp(root.sentRaw / root.maxRaw)))
        root.wake()
      }
    }
  }

  Process {
    id: writer
    running: root.available
    stdinEnabled: true
    command: ["bash", "-c", "while read -r v; do brightnessctl -q -d " + root.device + " set \"$v\"; done"]
  }

  property int sentRaw: -1
  HUi.SpringValue {
    id: glow
    preset: Motion.gentle
    movement: false   // light fading, nothing on screen moves
    epsilon: 0.002
    to: root.lit ? root.level : 0
    onValueChanged: {
      var raw = root.rawFor(value)
      if (raw !== root.sentRaw && writer.running) { root.sentRaw = raw; writer.write(raw + "\n") }
    }
  }

  // ── State file ──────────────────────────────────────────────────────────
  FileView {
    id: stateFile
    path: root.statePath
    printErrors: false
    onLoaded: {
      try {
        var s = JSON.parse(text())
        if (typeof s.level === "number") root.level = root.clamp(s.level)
        if (typeof s.timeout === "number") root.timeout = Math.max(0, Math.round(s.timeout))
      } catch (e) {}
      root.wake()
    }
  }
  Timer {
    id: save
    interval: 500
    onTriggered: stateFile.setText(JSON.stringify({ level: Math.round(root.level * 1000) / 1000, timeout: root.timeout }) + "\n")
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "custom" && String(event.data) === "kbdlight key") root.wake()
    }
  }

  IpcHandler {
    target: "henri-kbdlight"
    function set(level: real): string { root.setLevel(level); return "ok" }
    function timeout(seconds: int): string { root.setTimeoutSeconds(seconds); return "ok" }
    function wake(): string { root.wake(); return "ok" }
    function status(): string {
      return JSON.stringify({ available: root.available, level: root.level, timeout: root.timeout, lit: root.lit, raw: root.sentRaw })
    }
  }
}
