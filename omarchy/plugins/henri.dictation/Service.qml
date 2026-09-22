// Dictation panel -- the macOS way.
//
// Replaces voxtype's own OSD (`osd.enabled = false`), which is a separate GTK4
// process with its own palette and its own idea of motion. Living inside the
// Omarchy shell instead buys the theme tokens, the henri-ui components and one
// place for this to grow into: the assistant panel is this same card with pages
// in it, so it has to be built out of the same material from the start.
//
// State comes from the daemon, not from the key: `$XDG_RUNTIME_DIR/voxtype/state`
// holds one of idle/recording/streaming/transcribing and is rewritten on every
// transition, so the panel is right no matter what started the recording -- the
// right Ctrl key, `voxtype record toggle` from a script, or Keystroke.
//
// Levels come from `voxtype-audio-bridge`, the sidecar that reads the daemon's
// audio socket and prints one NDJSON frame per chunk. It stays running: the
// socket is silent while idle (measured: one `connected` line in three seconds,
// nothing else), so there is nothing to save by starting it per recording --
// and starting it there would fork in the first frames of the open animation,
// which costs visible frame rate.
//
// Waveform. The daemon sends ~95 frames/s, far denser than the panel should
// scroll. Frames accumulate into a peak and a tick moves one new value into a
// ring buffer every `tickMs`, so the bars never move -- the values travel
// through them.
//
// Click-through, never takes focus: it appears while Henri is typing into
// something else, so it must not swallow a single key.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

Item {
  id: root

  property var shell: null
  property var manifest: null

  // ── Daemon state ────────────────────────────────────────────────────────
  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000"

  // Not `state`: Item already has one, and assigning a free-form value to it
  // makes Qt look for a State of that name and warn on every transition.
  property string phase: "idle"
  property bool suppressed: false           // a `record start --no-osd` is in flight

  readonly property bool listening: phase === "recording" || phase === "streaming"
  readonly property bool working: phase === "transcribing"
  readonly property bool open: (listening || working) && !suppressed

  FileView {
    path: root.runtimeDir + "/voxtype/state"
    watchChanges: true
    printErrors: false
    onLoaded: root.phase = (text() || "idle").trim()
    onLoadFailed: root.phase = "idle"
    onFileChanged: reload()
  }

  // The marker is created and deleted rather than rewritten, so its absence
  // carries the meaning "draw normally" -- hence the failure path setting false.
  FileView {
    path: root.runtimeDir + "/voxtype/osd_suppressed"
    watchChanges: true
    printErrors: false
    onLoaded: root.suppressed = true
    onLoadFailed: root.suppressed = false
    onFileChanged: reload()
  }

  // ── Levels ──────────────────────────────────────────────────────────────
  readonly property int barCount: 34
  readonly property int tickMs: 35          // 34 bars x 35 ms = 1.2 s of history

  property var levels: new Array(34).fill(0)
  property real pendingPeak: 0

  // Room tone on this mic sits at peak 0.008-0.037, so anything under the floor
  // is silence and has to read as a flat line, not as signal. The square root
  // opens up the quiet half of the range, the way the brightness HUD does --
  // linear amplitude spends most of the bar on the loudest sounds.
  readonly property real noiseFloor: 0.04
  readonly property real loudPeak: 0.55

  function shape(peak) {
    var v = (peak - noiseFloor) / (loudPeak - noiseFloor)
    return Math.max(0, Math.min(1, Math.sqrt(Math.max(0, v))))
  }

  Process {
    id: bridge
    command: ["voxtype-audio-bridge"]
    running: true

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (line) {
        var trimmed = (line || "").trim()
        if (trimmed.length === 0 || trimmed.charAt(0) !== "{") return
        var frame
        try {
          frame = JSON.parse(trimmed)
        } catch (e) {
          return                             // a stray log line must not kill the panel
        }
        if (typeof frame.peak !== "number") return
        root.pendingPeak = Math.max(root.pendingPeak, frame.peak)
      }
    }

    // `running: true` respawns instantly; the delay keeps a crash-looping
    // binary from pegging a core while still healing in about a second.
    onRunningChanged: if (!running) bridgeRestart.restart()
  }

  Timer {
    id: bridgeRestart
    interval: 1000
    onTriggered: if (!bridge.running) bridge.running = true
  }

  Timer {
    running: root.open
    interval: root.tickMs
    repeat: true
    onTriggered: {
      var next = root.levels.slice(1)
      next.push(root.listening ? root.shape(root.pendingPeak) : 0)
      root.pendingPeak = 0
      root.levels = next                     // reassign: in-place edits do not notify
    }
  }

  // Leftover levels would flash on the next recording before the first tick.
  onOpenChanged: if (!open) {
    levels = new Array(barCount).fill(0)
    pendingPeak = 0
  }

  // ── Elapsed ─────────────────────────────────────────────────────────────
  property double startedAt: 0
  property string elapsed: "0:00"

  onListeningChanged: if (listening) {
    startedAt = Date.now()
    elapsed = "0:00"
  }

  Timer {
    running: root.listening
    interval: 250
    repeat: true
    onTriggered: {
      var s = Math.floor((Date.now() - root.startedAt) / 1000)
      root.elapsed = Math.floor(s / 60) + ":" + (s % 60 < 10 ? "0" : "") + (s % 60)
    }
  }

  // ── Sweep (transcribing) ────────────────────────────────────────────────
  // One animated number the bars read; nothing is built or laid out per frame.
  property real sweep: 0
  NumberAnimation on sweep {
    running: root.working
    from: -0.35
    to: 1.35
    duration: Motion.slower
    loops: Animation.Infinite
  }

  // ── Panel ───────────────────────────────────────────────────────────────
  HUi.SpringValue { id: pop; preset: Motion.gentle; to: root.open ? 1 : Motion.exitToScale }

  PanelWindow {
    id: win
    // Anchoring one edge only centres the window on the other axis.
    anchors { bottom: true }
    margins { bottom: Style.space(48) }
    visible: card.opacity > 0.001 || root.open
    implicitWidth: card.width
    implicitHeight: card.height
    color: "transparent"

    WlrLayershell.namespace: "henri-dictation"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}                          // click-through; the dock still reveals under it

    Panel {
      id: card
      listening: root.listening
      working: root.working
      levels: root.levels
      barCount: root.barCount
      sweep: root.sweep
      readoutText: root.working ? "Transcribing…" : root.elapsed

      transformOrigin: Item.Bottom
      scale: Motion.reduceMotion ? 1 : pop.value
      opacity: root.open ? 1 : 0
      Behavior on opacity {
        NumberAnimation {
          duration: root.open ? Motion.slow : Motion.exit(Motion.slow)
          easing.type: Easing.BezierSpline
          easing.bezierCurve: root.open ? Motion.easeOut : Motion.easeExit
        }
      }
    }
  }
}
