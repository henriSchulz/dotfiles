// Volume & brightness HUD -- the macOS way.
//
// Keys. Hyprland sends the media keys as `custom>>osd <volume|brightness>
// <up|down|up-fine|down-fine|mute>` on its event socket (bindings.lua). The
// stock path ran bash -> pactl (x4) -> jq -> omarchy-shell IPC for every
// press, ~150 ms before anything moved, and repeated keys queued up behind
// each other. Here a press changes the level in the same frame: volume goes
// straight to PipeWire, brightness to one long-lived brightnessctl loop.
//
// Steps. 16 per range like macOS; Alt (Option) moves a quarter step.
// Brightness runs on a perceptual curve (squared), so every step looks like
// the same change instead of the bottom steps being huge and the top ones
// invisible. The backlight itself glides between steps with the same spring
// as the bar, so the screen fades instead of jumping.
//
// HUD. A card under the bar in the top-right corner, like Control Center's
// Sound/Display module: fades in (scale from the corner), the bar glides with
// the smooth spring and stays interruptible under key repeat, the card fades
// out Motion.hudHold after the last press. Click-through, never takes focus.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property int steps: 16
  readonly property int fineSteps: 64

  // ── HUD state ───────────────────────────────────────────────────────────
  property bool open: false
  property string kind: "volume"          // volume | brightness
  property real level: 0                  // target 0…1 shown by the bar

  readonly property string symbolFont: ".SF Symbols Fallback"
  function sf(cp) { return String.fromCodePoint(cp) }

  readonly property color fg: Color.popups.text
  readonly property color dimText: Util.alpha(fg, Motion.secondaryTextAlpha)
  readonly property color trackColor: Util.alpha(fg, 0.14)

  readonly property string heading: kind === "volume" ? "Sound" : "Display"
  readonly property string detail: kind === "volume" ? outputName(controlSink) : ""
  // Short output name like macOS ("Speakers", "HDMI 1", "AirPods Pro"): the
  // ALSA description is the whole chipset ("500 Series Chipset Family …"),
  // its nick is the port; Bluetooth devices carry their own name.
  function outputName(n) {
    if (!n) return ""
    if (String(n.name).indexOf("alsa_output.") === 0 && n.nickname)
      return n.nickname === "Speaker" ? "Speakers" : n.nickname
    return n.description || n.nickname || ""
  }
  readonly property string icon: {
    if (kind === "brightness") return sf(level < 0.5 ? 0x1001AC : 0x1001AE)
    if (muted || level <= 0) return sf(0x1002A3)
    if (level < 0.34) return sf(0x1002A5)
    if (level < 0.67) return sf(0x1002A7)
    return sf(0x1002A9)
  }

  function clamp(v) { return Math.max(0, Math.min(1, v)) }

  // Next grid point in the direction of travel. A level between two points
  // (set elsewhere) first lands on the grid instead of skipping a step.
  function stepped(cur, n, dir) {
    var k = cur * n
    var next = dir > 0 ? Math.floor(k + 0.001) + 1 : Math.ceil(k - 0.001) - 1
    return clamp(next / n)
  }

  function show(what, from) {
    if (!open || kind !== what) fill.snap(from)
    kind = what
    open = true
    hold.restart()
  }

  Timer { id: hold; interval: Motion.hudHold; onTriggered: root.open = false }

  // ── Volume (PipeWire) ───────────────────────────────────────────────────
  // A DSP sink (speaker tuning, EasyEffects) can be the default without being
  // where loudness lives; like omarchy-audio-output-volume, follow it down to
  // the physical sink. Resolved once per default-sink change, never per key.
  readonly property var defaultSink: Pipewire.defaultAudioSink
  property string resolvedName: ""
  readonly property var controlSink: {
    if (!defaultSink) return null
    if (!resolvedName || resolvedName === defaultSink.name) return defaultSink
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++)
      if (nodes[i].name === resolvedName) return nodes[i]
    return defaultSink
  }
  readonly property bool muted: kind === "volume" && controlSink && controlSink.audio
    ? controlSink.audio.muted : false

  PwObjectTracker { objects: root.controlSink ? [root.controlSink] : [] }

  onDefaultSinkChanged: {
    resolvedName = ""
    if (defaultSink && defaultSink.name && defaultSink.name.indexOf("alsa_output.") !== 0)
      sinkResolver.running = true
  }
  Process {
    id: sinkResolver
    command: ["omarchy-audio-output-sink"]
    stdout: StdioCollector { onStreamFinished: root.resolvedName = text.trim() }
  }

  function volumeKey(action) {
    var s = controlSink
    if (!s || !s.audio) return
    var cur = s.audio.muted ? 0 : clamp(s.audio.volume)
    if (action === "mute") {
      show("volume", cur)
      s.audio.muted = !s.audio.muted
      level = s.audio.muted ? 0 : clamp(s.audio.volume)
      return
    }
    var dir = action.indexOf("up") === 0 ? 1 : -1
    var n = action.indexOf("fine") > 0 ? fineSteps : steps
    // Muted: any volume key unmutes and moves on from the real level.
    var base = clamp(s.audio.volume)
    show("volume", cur)
    var next = stepped(base, n, dir)
    s.audio.volume = next
    if (s.audio.muted) s.audio.muted = false
    level = next
  }

  // ── Brightness (internal panel) ─────────────────────────────────────────
  property string backlight: ""
  property real maxRaw: 0
  readonly property real floorFrac: 0.01    // level 0 still lights the panel (1 %)
  function rawFor(l) { return Math.round(maxRaw * (floorFrac + (1 - floorFrac) * l * l)) }
  function levelFor(raw) {
    if (maxRaw <= 0) return 0
    return Math.sqrt(clamp((raw / maxRaw - floorFrac) / (1 - floorFrac)))
  }

  Process {
    running: true
    command: ["brightnessctl", "-m", "-c", "backlight"]
    stdout: StdioCollector {
      onStreamFinished: {
        var f = text.trim().split("\n")[0].split(",")
        if (f.length < 5) return
        root.backlight = f[0]
        root.maxRaw = parseInt(f[4], 10) || 0
        root.sentRaw = parseInt(f[2], 10)
        root.brightLevel = root.levelFor(root.sentRaw)
        glow.snap(root.brightLevel)
      }
    }
  }

  // Someone else may have moved the backlight while the HUD was closed
  // (Control Center slider, idle dimming). The first press after that reads
  // the real value (one tiny `cat`, never during a key-repeat run); presses
  // that arrive meanwhile queue up and run in order once it is back.
  // (FileView can't do this: it hands back a cached sysfs value.)
  property var pending: []
  Process {
    id: reader
    command: ["cat", "/sys/class/backlight/" + root.backlight + "/actual_brightness"]
    stdout: StdioCollector {
      onStreamFinished: {
        root.resync(parseInt(text, 10))
        var queued = root.pending
        root.pending = []
        for (var i = 0; i < queued.length; i++) root.stepBrightness(queued[i])
      }
    }
  }
  function resync(raw) {
    if (isNaN(raw) || Math.abs(raw - rawFor(brightLevel)) <= maxRaw * 0.002) return
    brightLevel = levelFor(raw)
    glow.snap(brightLevel)
    sentRaw = raw
  }

  // One brightnessctl loop for the whole session: the glide sends a value per
  // frame, which must not mean a fork per frame inside the shell.
  Process {
    id: writer
    running: root.backlight !== ""
    stdinEnabled: true
    command: ["bash", "-c", "while read -r d v; do brightnessctl -q -d \"$d\" set \"$v\"; done"]
  }

  property real brightLevel: 0        // where the backlight is heading
  property int sentRaw: -1
  HUi.SpringValue {
    id: glow
    preset: Motion.smooth
    epsilon: 0.0005
    to: root.brightLevel
    onValueChanged: {
      var raw = root.rawFor(value)
      if (raw !== root.sentRaw && writer.running) { root.sentRaw = raw; writer.write(root.backlight + " " + raw + "\n") }
    }
  }

  function internalFocused() {
    var m = Hyprland.focusedMonitor
    return !m || /^(eDP|LVDS|DSI)-/.test(m.name)
  }

  function brightnessKey(action) {
    // External screens (DDC / Apple displays) keep Omarchy's own path.
    if (!internalFocused() || !backlight || maxRaw <= 0) {
      var fine = action.indexOf("fine") > 0
      var arg = action.indexOf("up") === 0 ? (fine ? "+1%" : "+5%") : (fine ? "1%-" : "5%-")
      Quickshell.execDetached(["omarchy-brightness-display", arg])
      return
    }
    if (reader.running) { pending = pending.concat([action]); return }
    if (!glow.running && !(open && kind === "brightness")) {
      pending = [action]
      reader.running = true
      return
    }
    stepBrightness(action)
  }

  function stepBrightness(action) {
    var cur = brightLevel
    var dir = action.indexOf("up") === 0 ? 1 : -1
    var n = action.indexOf("fine") > 0 ? fineSteps : steps
    show("brightness", cur)
    brightLevel = stepped(cur, n, dir)
    level = brightLevel
  }


  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "custom") return
      var data = String(event.data)
      if (data.indexOf("osd ") !== 0) return
      var parts = data.slice(4).trim().split(/\s+/)
      if (parts[0] === "volume") root.volumeKey(parts[1] || "up")
      else if (parts[0] === "brightness") root.brightnessKey(parts[1] || "up")
    }
  }

  IpcHandler {
    target: "henri-osd"
    function volume(action: string): string { root.volumeKey(action); return "ok" }
    function brightness(action: string): string { root.brightnessKey(action); return "ok" }
    function ping(): string { return "ok" }
  }

  // ── HUD surface ─────────────────────────────────────────────────────────
  HUi.SpringValue { id: fill; preset: Motion.smooth; to: root.level }
  HUi.SpringValue { id: pop; preset: Motion.smooth; to: root.open ? 1 : Motion.exitToScale }

  PanelWindow {
    id: win
    visible: card.opacity > 0.001 || root.open
    anchors { top: true; right: true }
    margins { top: Style.space(6); right: Style.space(8) }
    implicitWidth: card.width
    implicitHeight: card.height
    color: "transparent"
    WlrLayershell.namespace: "henri-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Normal
    mask: Region {}

    HUi.Surface {
      id: card
      role: "popups"
      kind: "panel"
      width: Style.space(300)
      height: column.implicitHeight + Style.space(24)
      transformOrigin: Item.TopRight
      scale: Motion.reduceMotion ? 1 : pop.value
      opacity: root.open ? 1 : 0
      Behavior on opacity {
        NumberAnimation {
          duration: root.open ? Motion.base : Motion.exit(Motion.slow)
          easing.type: Easing.BezierSpline
          easing.bezierCurve: root.open ? Motion.easeOut : Motion.easeExit
        }
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Style.space(11)
        anchors.leftMargin: Style.space(14)
        anchors.rightMargin: Style.space(16)
        spacing: Style.space(8)

        Item {
          width: parent.width
          height: title.implicitHeight
          HUi.CrossfadeText {
            id: title
            text: root.heading
            color: root.fg
            fontSize: Style.font.subtitle
            fontWeight: Font.DemiBold
          }
          HUi.CrossfadeText {
            anchors.left: title.right
            anchors.leftMargin: Style.space(12)
            anchors.right: parent.right
            anchors.verticalCenter: title.verticalCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: root.detail
            color: root.dimText
            fontSize: Style.font.bodySmall
          }
        }

        Item {
          width: parent.width
          height: Style.space(22)

          HUi.CrossfadeText {
            id: glyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(22)
            text: root.icon
            color: root.fg
            fontFamily: root.symbolFont
            fontSize: Style.font.iconLarge
          }

          Rectangle {
            id: track
            anchors.left: glyph.right
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(6)
            radius: height / 2
            color: root.trackColor

            Rectangle {
              readonly property real v: Math.max(0, Math.min(1, fill.value))
              height: parent.height
              radius: parent.radius
              width: parent.height + (parent.width - parent.height) * v
              color: root.fg
              // Below one step the capsule would only shrink to a dot: fade it
              // instead, so 0 (and mute) reads as an empty track.
              opacity: Math.min(1, v * root.steps)
            }
          }
        }
      }
    }
  }
}
