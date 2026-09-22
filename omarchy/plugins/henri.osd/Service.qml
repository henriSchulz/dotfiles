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
// invisible. Like volume, a press sets the new level at once (one write per
// press); only the bar in the HUD glides.
//
// Extra dim. Below the old floor (1 % backlight) sit 4 more steps, split off
// in the bar by a small gap: the backlight keeps going down toward a quarter
// of the floor and a black click-through layer over the internal screen
// darkens on top, set together with the backlight. The backlight value
// alone encodes how deep in the zone we are, so a shell restart comes back
// at the same darkness.
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
  readonly property string detail: kind === "volume" ? outputName(controlSink)
    : (level < 0 ? "Extra Dim" : "")
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
    if (kind === "brightness") return sf(level < 0 ? 0x1001BA : level < 0.5 ? 0x1001AC : 0x1001AE)
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
    if (!open || kind !== what) fill.snap(what === "brightness" ? toGrid(from) : from)
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
  // Level runs from -1 (deepest extra dim) through 0 (the normal floor, 1 %
  // backlight) to 1. Keys walk one grid over both parts: dimSteps below 0,
  // steps above, each step the same width in the bar.
  property string backlight: ""
  property real maxRaw: 0
  readonly property real floorFrac: 0.01    // level 0 still lights the panel (1 %)
  readonly property int dimSteps: 4
  readonly property real minFrac: 0.0025    // backlight at level -1
  readonly property real maxDim: 0.7        // black layer at level -1
  readonly property int gridSteps: dimSteps + steps
  function toGrid(l) { return (l < 0 ? l * dimSteps + dimSteps : dimSteps + l * steps) / gridSteps }
  function fromGrid(x) {
    var s = clamp(x) * gridSteps - dimSteps
    return s < 0 ? s / dimSteps : s / steps
  }
  function rawFor(l) {
    if (l < 0) return Math.max(1, Math.round(maxRaw * floorFrac * Math.pow(minFrac / floorFrac, -l)))
    return Math.round(maxRaw * (floorFrac + (1 - floorFrac) * l * l))
  }
  function levelFor(raw) {
    if (maxRaw <= 0) return 0
    var f = raw / maxRaw
    if (f < floorFrac - 0.5 / maxRaw)
      return -Math.min(1, Math.log(Math.max(f, 1 / maxRaw) / floorFrac) / Math.log(minFrac / floorFrac))
    return Math.sqrt(clamp((f - floorFrac) / (1 - floorFrac)))
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
    var tol = brightLevel < 0 || raw < maxRaw * floorFrac ? 1 : maxRaw * 0.002
    if (isNaN(raw) || Math.abs(raw - rawFor(brightLevel)) <= tol) return
    brightLevel = levelFor(raw)
    sentRaw = raw
  }

  // One brightnessctl loop for the whole session, so a press never forks
  // inside the shell. One brightnessctl takes ~14 ms; under key repeat the
  // loop drops values that are already stale and only sets the newest, so
  // the backlight never trails behind the keys.
  Process {
    id: writer
    running: root.backlight !== ""
    stdinEnabled: true
    command: ["bash", "-c", "while read -r d v; do while read -r -t 0 && read -r d v; do :; done; brightnessctl -q -d \"$d\" set \"$v\"; done"]
  }

  property real brightLevel: 0        // current level (-1…1)
  property int sentRaw: -1
  function setBrightness(l) {
    brightLevel = l
    var raw = rawFor(l)
    if (raw !== sentRaw && writer.running) { sentRaw = raw; writer.write(backlight + " " + raw + "\n") }
  }

  readonly property real dimAlpha: maxDim * Math.max(0, -brightLevel)

  // While extra-dimmed, notice when something else (Control Center slider,
  // idle restore) moved the backlight, so the black layer doesn't stay on a
  // bright screen.
  Timer {
    interval: 1000
    repeat: true
    running: root.brightLevel < 0 && !root.open
    onTriggered: if (!reader.running) reader.running = true
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
    if (!(open && kind === "brightness")) {
      pending = [action]
      reader.running = true
      return
    }
    stepBrightness(action)
  }

  function stepBrightness(action) {
    var cur = brightLevel
    var dir = action.indexOf("up") === 0 ? 1 : -1
    var n = action.indexOf("fine") > 0 ? gridSteps * 4 : gridSteps
    show("brightness", cur)
    setBrightness(fromGrid(stepped(toGrid(cur), n, dir)))
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
  // Volume: the level. Brightness: the grid position (dim zone + main range).
  HUi.SpringValue { id: fill; preset: Motion.smooth; to: root.split ? root.toGrid(root.level) : root.level }
  readonly property bool split: kind === "brightness"
  // The dim segment is full at 0 and empties toward -1; the main one fills 0…1.
  readonly property real dimFill: split ? clamp(fill.value * gridSteps / dimSteps) : 0
  readonly property real mainFill: split ? clamp((fill.value * gridSteps - dimSteps) / steps) : clamp(fill.value)

  readonly property var internalScreen: {
    var ss = Quickshell.screens
    for (var i = 0; i < ss.length; i++) if (/^(eDP|LVDS|DSI)-/.test(ss[i].name)) return ss[i]
    return null
  }

  // Extra-dim layer over the internal screen: click-through, only mapped
  // while it darkens something.
  PanelWindow {
    screen: root.internalScreen
    visible: root.internalScreen !== null && root.dimAlpha > 0.002
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "henri-osd-dim"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    Rectangle { anchors.fill: parent; color: "black"; opacity: root.dimAlpha }
  }
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

          // Brightness splits the bar: a short extra-dim segment, a gap, then
          // the normal range. Switching volume <-> brightness crossfades the
          // two layouts instead of resizing anything.
          Item {
            id: bar
            anchors.left: glyph.right
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(6)

            readonly property real gap: Style.space(4)
            readonly property real dimWidth: (width - gap) * root.dimSteps / root.gridSteps

            component Capsule: Rectangle {
              property real v: 0
              property int stepCount: 1
              property color fillColor: root.fg
              height: bar.height
              radius: height / 2
              color: root.trackColor
              Rectangle {
                height: parent.height
                radius: parent.radius
                width: parent.height + (parent.width - parent.height) * parent.v
                color: parent.fillColor
                // Below one step the capsule would only shrink to a dot: fade it
                // instead, so 0 (and mute) reads as an empty track.
                opacity: Math.min(1, parent.v * parent.stepCount)
              }
            }

            Capsule {
              width: parent.width
              v: root.mainFill
              stepCount: root.steps
              opacity: root.split ? 0 : 1
              Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
            }

            Item {
              anchors.fill: parent
              opacity: root.split ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
              Capsule {
                width: bar.dimWidth
                v: root.dimFill
                stepCount: root.dimSteps
                fillColor: root.dimText
              }
              Capsule {
                x: bar.dimWidth + bar.gap
                width: bar.width - x
                v: root.mainFill
                stepCount: root.steps
              }
            }
          }
        }
      }
    }
  }
}
