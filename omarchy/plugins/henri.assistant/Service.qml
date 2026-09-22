// Voice assistant -- the dictation pill, grown into a conversation.
//
// SUPER + right Ctrl opens the card and starts listening at once. The same key
// stops the recording; the transcript lands in the composer, where it can be
// corrected before ↵ sends it. Antigravity answers into the card, and the key
// dictates the next turn. Esc closes.
//
// The transcript never goes through the keyboard or the clipboard: the
// recording runs as `voxtype record start --file=… --no-osd`, so the daemon
// writes the text to a file this plugin reads, and voxtype's own overlay --
// and henri.dictation's, which honours the same marker -- stay out of the way.
//
// The agent is one long-lived `agy --input-format stream-json` process: a turn
// is one NDJSON line in, a stream of events out, and the conversation id stays
// the same, so follow-ups keep their context. Measured on this machine: 6 s
// for the first turn of a session, 1.6 s for a follow-up -- which is why the
// process is started when the card opens (while Henri is still speaking) and
// kept warm for `agentIdleMs` after it closes, instead of per turn.
//
// Tools are auto-denied in this headless mode -- agy says so on stderr and
// returns an empty answer. That note is shown in the card rather than leaving
// it blank; allowing tools is a `permissions.allow` entry in
// ~/.gemini/antigravity-cli/settings.json and deliberately not done here.

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
  readonly property int agentIdleMs: 600000          // keep agy warm for 10 min

  // ── Window state ────────────────────────────────────────────────────────
  property bool open: false

  property var turns: []                             // [{question, answer}] settled
  property string pendingQuestion: ""
  property string streamed: ""
  property string draft: ""
  property string note: ""
  property string status: ""
  property bool thinking: false
  // ↵ pressed while still recording: stop now, send as soon as the daemon
  // hands over the words. The turn is one gesture — speak, ↵ — with no stop
  // step in between and nothing to confirm.
  property bool sendOnArrival: false

  function toggle() {
    if (!open) openCard()
    else if (listening) stopDictation()
    else startDictation()
  }

  // ↵ from the card. Recording: end it and let the transcript go straight out.
  // Otherwise: send what is in the composer.
  function submit() {
    if (listening) {
      sendOnArrival = true
      stopDictation()
    } else if (!transcribing) {
      send()
    }
  }

  function openCard() {
    turns = []
    pendingQuestion = ""
    streamed = ""
    draft = ""
    note = ""
    sendOnArrival = false
    open = true
    agentIdle.stop()
    startDictation()
  }

  function close() {
    if (listening || transcribing) Quickshell.execDetached(["voxtype", "record", "cancel"])
    sendOnArrival = false
    open = false
    agentIdle.restart()
  }

  // ── Dictation ───────────────────────────────────────────────────────────
  property string phase: "idle"                      // voxtype daemon state
  property bool mine: false                          // this plugin started it
  readonly property bool listening: mine && (phase === "recording" || phase === "streaming")
  readonly property bool transcribing: mine && phase === "transcribing"

  function startDictation() {
    mine = true
    status = ""
    Quickshell.execDetached(["voxtype", "record", "start",
      "--file=" + root.transcriptPath, "--no-osd"])
  }

  function stopDictation() {
    Quickshell.execDetached(["voxtype", "record", "stop"])
  }

  FileView {
    path: root.runtimeDir + "/voxtype/state"
    watchChanges: true
    printErrors: false
    onLoaded: root.phase = (text() || "idle").trim()
    onLoadFailed: root.phase = "idle"
    onFileChanged: reload()
  }

  // The daemon writes the transcript here once, so the file appearing *is* the
  // event. It is removed after reading: otherwise a second turn with the same
  // words would rewrite identical content and never register as a change.
  FileView {
    id: transcript
    path: root.transcriptPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var said = (text() || "").trim()
      Quickshell.execDetached(["rm", "-f", root.transcriptPath])
      if (said.length === 0 || !root.mine) return
      root.mine = false
      root.draft = root.draft.length > 0 ? root.draft + " " + said : said
      card.caretToEnd()
      if (root.sendOnArrival) {
        root.sendOnArrival = false
        root.send()
      }
    }
  }

  // voxtype writes a sidecar next to the transcript for every finished
  // recording: {"status":"empty","chars":0} when it heard nothing. Without
  // watching it a silent recording leaves the card looking dead, which is
  // exactly what hid the double-toggle bug in the first place.
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
      if ((done.chars || 0) > 0) return      // the transcript watcher has it
      root.mine = false
      root.sendOnArrival = false
      root.status = "Nothing heard — Super A to try again"
    }
  }

  // ── Levels ──────────────────────────────────────────────────────────────
  readonly property int barCount: 34
  readonly property int tickMs: 35
  property var levels: new Array(34).fill(0)
  property real pendingPeak: 0

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
      root.levels = next
    }
  }

  // ── Sweep ───────────────────────────────────────────────────────────────
  property real sweep: 0
  NumberAnimation {
    target: root; property: "sweep"
    running: root.transcribing || root.thinking
    from: -0.35; to: 1.35
    duration: Motion.slower
    loops: Animation.Infinite
  }

  // ── Agent ───────────────────────────────────────────────────────────────
  property string lastError: ""

  Process {
    id: agent
    command: ["agy", "--input-format", "stream-json", "--output-format", "stream-json", "-p="]
    running: false
    stdinEnabled: true

    stdout: SplitParser {
      splitMarker: "\n"
      onRead: function (line) { root.handleAgentLine(line) }
    }
    stderr: SplitParser {
      splitMarker: "\n"
      onRead: function (line) {
        var t = (line || "").trim()
        if (t.length > 0) root.lastError = t
      }
    }

    onRunningChanged: if (!running && root.thinking) {
      root.thinking = false
      root.finishTurn("", "The agent stopped before answering.")
    }
  }

  Timer {
    id: agentIdle
    interval: root.agentIdleMs
    onTriggered: agent.running = false
  }

  function handleAgentLine(line) {
    var t = (line || "").trim()
    if (t.length === 0 || t.charAt(0) !== "{") return
    var msg
    try { msg = JSON.parse(t) } catch (e) { return }

    if (msg.event === "step_update") {
      var d = msg.step_update ? msg.step_update.text_delta : ""
      if (d) root.streamed += d
    } else if (msg.event === "result") {
      var r = msg.result || {}
      root.thinking = false
      root.finishTurn((r.response || root.streamed || "").trim(),
        r.status === "SUCCESS" ? "" : (r.error || "The turn failed."))
    }
  }

  // Settle the in-flight turn into the list. An empty answer is the tool
  // auto-deny case, so the stderr line is what the card shows instead.
  function finishTurn(answer, failure) {
    var text = answer
    var why = ""
    if (text.length === 0) {
      why = failure.length > 0 ? failure
        : (root.lastError.length > 0 ? root.lastError : "No answer.")
    }
    if (root.pendingQuestion.length > 0 && text.length > 0) {
      var next = root.turns.slice()
      next.push({ question: root.pendingQuestion, answer: text })
      root.turns = next
      root.pendingQuestion = ""
      root.streamed = ""
      root.note = ""
    } else {
      root.note = why
      root.streamed = ""
    }
  }

  function send() {
    var q = root.draft.trim()
    if (q.length === 0 || root.thinking) return
    root.lastError = ""
    root.note = ""
    root.streamed = ""
    root.pendingQuestion = q
    root.draft = ""
    root.thinking = true
    if (!agent.running) agent.running = true
    agent.write(JSON.stringify({
      event: "user",
      message: { role: "user", content: q }
    }) + "\n")
  }

  // ── Wiring ──────────────────────────────────────────────────────────────
  // A fork in the first frames of the open animation costs visible frame rate,
  // so the directory, the bridge and the agent all wait for the card to settle.
  Timer {
    id: warmup
    interval: Motion.settleDelay
    onTriggered: {
      Quickshell.execDetached(["mkdir", "-p", root.workDir])
      bridge.running = true
      if (!agent.running) agent.running = true
    }
  }

  onOpenChanged: {
    if (open) {
      warmup.restart()
      card.focusInput()
    } else {
      bridge.running = false
      levels = new Array(barCount).fill(0)
      pendingPeak = 0
      mine = false
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
    // Ask without the microphone: opens the card on a typed question, so a
    // script can reach the assistant and so the agent path can be exercised
    // without speaking into it.
    function ask(question: string): string {
      if (!root.open) {
        root.turns = []
        root.pendingQuestion = ""
        root.streamed = ""
        root.note = ""
        root.open = true
      } else if (root.listening) {
        Quickshell.execDetached(["voxtype", "record", "cancel"])
      }
      root.draft = question
      root.send()
      return "ok"
    }
    function ping(): string { return "ok" }
  }

  // ── Card ────────────────────────────────────────────────────────────────
  HUi.SpringValue { id: pop; preset: Motion.gentle; to: root.open ? 1 : Motion.exitToScale }

  PanelWindow {
    id: win
    // No anchor on any edge: the surface sits in the middle of the screen.
    // It is the thing being used now, not a status readout in a corner.
    visible: card.opacity > 0.001 || root.open
    implicitWidth: card.width
    implicitHeight: card.height
    color: "transparent"

    WlrLayershell.namespace: "henri-assistant"
    WlrLayershell.layer: WlrLayer.Overlay
    // A launcher-style surface: it exists to be typed into, so it takes the
    // keyboard while it is up and gives it straight back on Esc.
    WlrLayershell.keyboardFocus: root.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Panel {
      id: card
      turns: root.turns
      pendingQuestion: root.pendingQuestion
      streamed: root.streamed
      draft: root.draft
      note: root.note
      status: root.status
      listening: root.listening
      transcribing: root.transcribing
      thinking: root.thinking
      levels: root.levels
      barCount: root.barCount
      sweep: root.sweep

      onSubmitted: root.submit()
      onDismissed: root.close()
      onDraftEdited: function (text) { root.draft = text }

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
