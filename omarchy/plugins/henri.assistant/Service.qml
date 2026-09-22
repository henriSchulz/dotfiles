// Speak a prompt into a Claude Code session.
//
// SUPER+A opens the card and starts listening. The same key ends the
// recording; the transcript goes straight into a new Claude Code session in a
// terminal and the card closes. Esc cancels without starting anything.
//
// It used to run an Antigravity agent inside the card and answer there, with a
// conversation, thinking dots and a permission window in front of every tool.
// That is deliberately gone: the card hands over and gets out of the way, and
// Claude Code does what it is good at in its own window. `agent-guard` and its
// hook are still installed but dormant -- nothing sets HENRI_VOICE any more, so
// the guard allows everything and a terminal session reviews itself, the way it
// always did.
//
// The transcript never goes through the keyboard or the clipboard: the
// recording runs as `voxtype record start --file=… --no-osd`, so the daemon
// writes the text to a file this plugin reads, and henri.dictation's pill stays
// out of the way because it honours the same marker.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000"
  readonly property string workDir: runtimeDir + "/henri-assistant"
  readonly property string transcriptPath: workDir + "/turn.txt"

  // Where a spoken session lands. Home rather than a guess at a project: the
  // sentence is the prompt, not a path, and Claude Code can be pointed
  // somewhere else from inside it.
  readonly property string sessionDir: Quickshell.env("HOME") || "/home/henri"

  property bool open: false
  property string status: ""

  // ── Daemon state ────────────────────────────────────────────────────────
  property string phase: "idle"
  property bool mine: false                  // this plugin started the recording

  readonly property bool listening: mine && (phase === "recording" || phase === "streaming")
  readonly property bool transcribing: mine && phase === "transcribing"

  FileView {
    path: root.runtimeDir + "/voxtype/state"
    watchChanges: true
    printErrors: false
    onLoaded: root.phase = (text() || "idle").trim()
    onLoadFailed: root.phase = "idle"
    onFileChanged: reload()
  }

  // The daemon writes the transcript once, so the file appearing *is* the
  // event. It is removed after reading: a second turn with the same words would
  // otherwise rewrite identical content and never register as a change.
  FileView {
    path: root.transcriptPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var said = (text() || "").trim()
      Quickshell.execDetached(["rm", "-f", root.transcriptPath])
      if (!root.mine) return
      root.mine = false
      if (said.length === 0) return
      root.handOver(said)
    }
  }

  // voxtype writes this sidecar for every finished recording; chars 0 means it
  // heard nothing. Without it a silent recording leaves the card looking dead.
  FileView {
    path: root.transcriptPath + ".done"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var raw = (text() || "").trim()
      Quickshell.execDetached(["rm", "-f", root.transcriptPath + ".done"])
      if (raw.length === 0 || !root.mine) return
      var done
      try { done = JSON.parse(raw) } catch (e) { return }
      if ((done.chars || 0) > 0) return       // the transcript watcher has it
      root.mine = false
      root.status = "Nothing heard"
      closeSoon.restart()
    }
  }

  // ── Hand over ───────────────────────────────────────────────────────────
  function handOver(prompt) {
    root.status = "Opening Claude Code…"
    // agent-session rather than a terminal command put together here: placing
    // a session with a working directory does not go through Omarchy's Lua
    // dispatch straightforwardly, and that script already solves it. The
    // prompt travels as one argv element, never as a shell string.
    Quickshell.execDetached(["agent-session", "--agent", "claude",
      "--dir", root.sessionDir, "--prompt", prompt])
    closeSoon.restart()
  }

  // Long enough to read what it says, short enough not to sit in front of the
  // terminal that is about to appear.
  Timer {
    id: closeSoon
    interval: Motion.hudHold
    onTriggered: root.close()
  }

  // ── Card control ────────────────────────────────────────────────────────
  // The key is the whole flow: it starts the recording and it ends it, and
  // ending it hands over. Henri decides where a prompt begins and ends.
  function toggle() {
    if (!open) openCard()
    else if (listening) stopDictation()
    else if (!transcribing) startDictation()
  }

  function openCard() {
    status = ""
    closeSoon.stop()
    open = true
    startDictation()
  }

  function close() {
    if (listening || transcribing) Quickshell.execDetached(["voxtype", "record", "cancel"])
    closeSoon.stop()
    mine = false
    open = false
  }

  function startDictation() {
    mine = true
    status = ""
    Quickshell.execDetached(["voxtype", "record", "start",
      "--file=" + root.transcriptPath, "--no-osd"])
  }

  function stopDictation() {
    Quickshell.execDetached(["voxtype", "record", "stop"])
  }

  // ── Levels ──────────────────────────────────────────────────────────────
  readonly property int barCount: 34
  readonly property int tickMs: 35           // 34 bars x 35 ms = 1.2 s of history

  property var levels: new Array(34).fill(0)
  property real pendingPeak: 0

  // Room tone on this mic sits at peak 0.008-0.037, so anything under the floor
  // is silence and has to read as a flat line. The square root opens up the
  // quiet half of the range, the way the brightness HUD does.
  readonly property real noiseFloor: 0.04
  readonly property real loudPeak: 0.55

  function shape(peak) {
    var v = (peak - noiseFloor) / (loudPeak - noiseFloor)
    return Math.max(0, Math.min(1, Math.sqrt(Math.max(0, v))))
  }

  Process {
    id: bridge
    command: ["voxtype-audio-bridge"]
    running: false
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (line) {
        var t = (line || "").trim()
        if (t.length === 0 || t.charAt(0) !== "{") return
        var frame
        try { frame = JSON.parse(t) } catch (e) { return }
        if (typeof frame.peak !== "number") return
        root.pendingPeak = Math.max(root.pendingPeak, frame.peak)
      }
    }
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

  // ── Sweep ───────────────────────────────────────────────────────────────
  property real sweep: 0
  NumberAnimation {
    target: root; property: "sweep"
    running: root.transcribing
    from: -0.35
    to: 1.35
    duration: Motion.slower
    loops: Animation.Infinite
  }

  // ── Wiring ──────────────────────────────────────────────────────────────
  // A fork in the first frames of the open animation costs visible frame rate,
  // so the directory and the bridge wait for the card to settle.
  Timer {
    id: warmup
    interval: Motion.settleDelay
    onTriggered: {
      Quickshell.execDetached(["mkdir", "-p", root.workDir])
      bridge.running = true
    }
  }

  onOpenChanged: {
    if (open) {
      warmup.restart()
      card.forceActiveFocus()
    } else {
      bridge.running = false
      levels = new Array(barCount).fill(0)
      pendingPeak = 0
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "custom") return
      var data = String(event.data)
      if (data.indexOf("assistant") !== 0) return
      var what = data.slice(9).trim()
      if (what === "close") root.close()
      else if (what === "open") { if (!root.open) root.openCard() }
      else root.toggle()
    }
  }

  IpcHandler {
    target: "henri-assistant"
    function toggle(): string { root.toggle(); return "ok" }
    function open(): string { if (!root.open) root.openCard(); return "ok" }
    function close(): string { root.close(); return "ok" }
    // Hand a prompt over without the microphone, for scripts and for testing.
    function ask(prompt: string): string { root.handOver(prompt); return "ok" }
    function ping(): string { return "ok" }
  }

  // ── Card ────────────────────────────────────────────────────────────────
  HUi.SpringValue { id: pop; preset: Motion.gentle; to: root.open ? 1 : Motion.exitToScale }

  PanelWindow {
    id: win
    // No anchor on any edge: the surface sits in the middle of the screen.
    visible: card.opacity > 0.001 || root.open
    implicitWidth: card.width
    implicitHeight: card.height
    color: "transparent"

    WlrLayershell.namespace: "henri-assistant"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Panel {
      id: card
      listening: root.listening
      working: root.transcribing
      levels: root.levels
      barCount: root.barCount
      sweep: root.sweep
      status: root.status !== "" ? root.status
        : root.listening ? root.elapsed
        : root.transcribing ? "…"
        : "Super A  talk"

      onDismissed: root.close()

      transformOrigin: Item.Center
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
