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
  readonly property string askPath: workDir + "/ask.json"
  readonly property int agentIdleMs: 600000          // keep agy warm for 10 min

  // ── Window state ────────────────────────────────────────────────────────
  property bool open: false

  property var turns: []                             // [{question, answer}] settled
  property string pendingQuestion: ""
  property string streamed: ""
  property string draft: ""
  property string note: ""
  property string status: ""
  // What agent-guard is holding: {id, tool, title, detail}. The hook blocks
  // inside the agent's tool call until an answer file appears, so this is a
  // real stop, not a notice after the fact.
  property var confirmRequest: null
  // A turn that ends with nothing to say after a refusal ended that way
  // because of the refusal -- say so instead of "No answer."
  property string deniedTitle: ""
  property bool thinking: false

  // A turn that is still running when the card closes keeps running -- agy has
  // no cheap way to abort one, and killing the process would throw away the
  // session. So the turn is abandoned instead: its events are ignored once the
  // generation moves on, and `thinking` is cleared right away. Without that the
  // flag stayed set, and send() returns early while it is, so ↵ silently did
  // nothing for the rest of the session.
  property int turnGeneration: 0
  property int activeTurn: -1

  // What the agent is doing right now, and for how long. With shell access a
  // single question can be a dozen tool calls -- without this the card looks
  // stuck for a minute when it is working perfectly.
  property string activity: ""
  property int elapsed: 0
  property double turnStartedAt: 0
  // Agy streams a step event for every tool call and every thought, so silence
  // this long means it is wedged rather than busy. Generous on purpose: a real
  // turn with a dozen commands in it is slow, but it is never quiet.
  readonly property int stallMs: 90000
  property double lastEventAt: 0
  // ↵ pressed while still recording: stop now, send as soon as the daemon
  // hands over the words. The turn is one gesture — speak, ↵ — with no stop
  // step in between and nothing to confirm.
  property bool sendOnArrival: false

  // The key is the whole flow: it starts the recording and it ends it, and
  // ending it sends. Henri decides where a question begins and ends -- no pause
  // detection guessing at it, and no text field in between to confirm.
  function toggle() {
    if (!open) {
      openCard()
    } else if (listening) {
      sendOnArrival = true
      stopDictation()
    } else if (!transcribing) {
      startDictation()
    }
  }

  function openCard() {
    turns = []
    pendingQuestion = ""
    streamed = ""
    draft = ""
    note = ""
    sendOnArrival = false
    abandonTurn()
    open = true
    agentIdle.stop()
    startDictation()
  }

  function close() {
    if (listening || transcribing) Quickshell.execDetached(["voxtype", "record", "cancel"])
    sendOnArrival = false
    // A turn still running when the card closes is work nobody will read, and
    // with shell access it is work that keeps running commands. Closing means
    // stop -- the session is worth less than a wedged agent.
    if (confirmRequest) answerConfirm(false)   // closing is a no, not a maybe
    if (thinking) stopAgent()
    abandonTurn()
    open = false
    agentIdle.restart()
  }

  // Take the agent down, and the tools it started with it: killing only agy
  // would leave a `run_command` child behind holding the terminal it spawned.
  // The next question starts a fresh process -- 6 s cold instead of 1.6 s warm,
  // which is the right price for never being stuck.
  function stopAgent() {
    if (!agent.running) return
    if (agent.processId) Quickshell.execDetached(["pkill", "-TERM", "-P", String(agent.processId)])
    agent.running = false
  }

  // Stop waiting on whatever the agent is doing: the answer, if it still
  // arrives, belongs to a card that is gone.
  function abandonTurn() {
    turnGeneration++
    thinking = false
    activity = ""
    pendingQuestion = ""
    streamed = ""
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

  // agent-guard writes the request atomically (tmp + rename), so the file is
  // either absent or complete -- there is no half-read state to guard against.
  FileView {
    path: root.askPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoadFailed: root.confirmRequest = null
    onLoaded: {
      var raw = (text() || "").trim()
      if (raw.length === 0) { root.confirmRequest = null; return }
      try {
        root.confirmRequest = JSON.parse(raw)
      } catch (e) {
        root.confirmRequest = null
        return
      }
      // A confirmation nobody can see is no confirmation: if the card was
      // closed while the agent worked, it comes back for this.
      if (!root.open) root.open = true
    }
  }

  // agent-guard drops this when a command's job is to open something. The card
  // is then in front of whatever just appeared, so it leaves.
  FileView {
    path: root.workDir + "/launched"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      Quickshell.execDetached(["rm", "-f", root.workDir + "/launched"])
      if (root.open && !root.listening && !root.transcribing) root.close()
    }
  }

  function answerConfirm(allowed) {
    if (!root.confirmRequest) return
    if (!allowed) root.deniedTitle = root.confirmRequest.title || "that"
    var suffix = allowed ? ".allow" : ".deny"
    Quickshell.execDetached(["touch", root.workDir + "/ask-" + root.confirmRequest.id + suffix])
    root.confirmRequest = null
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

  Timer {
    running: root.thinking
    interval: 1000
    repeat: true
    onTriggered: {
      root.elapsed = Math.floor((Date.now() - root.turnStartedAt) / 1000)
      if (Date.now() - root.lastEventAt > root.stallMs) {
        root.stopAgent()
        root.thinking = false
        root.activity = ""
        root.finishTurn("", "The agent stopped responding and was terminated.")
      }
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

  // Sent once per agy process, glued in front of the first question. The agent
  // otherwise arrives with nothing: it does not know the question was spoken
  // rather than typed, that its answer lands in a small card instead of a
  // terminal, or that starting a session on a given workspace has a script
  // that already solves the part that is awkward to get right.
  //
  // Not in agy's own knowledge directory on purpose -- that would apply to
  // every agy session, including the ones Henri starts by hand in a terminal,
  // where none of this is true.
  property bool preambleSent: false

  readonly property string preamble:
    "You are Henri's voice assistant on his Arch Linux / Omarchy desktop (Hyprland, Wayland).\n\n" +
    "The question reached you as dictation through Parakeet, so proper nouns, paths and " +
    "command names may be misheard. Prefer the reading that makes sense on this machine, " +
    "act on it, and say what you assumed — do not ask a clarifying question unless acting " +
    "on the wrong reading would be destructive.\n\n" +
    "Your answer is drawn in a small card on screen, not in a terminal: a few sentences or " +
    "a short list. No preamble, no restating the question. Answer in the language it was " +
    "asked in.\n\n" +
    "You may run commands. Two things to know:\n\n" +
    "1. To open a coding agent in a terminal, use `agent-session` rather than assembling a " +
    "terminal command yourself — putting one on a given Hyprland workspace with a given " +
    "working directory does not work straightforwardly through Omarchy's Lua dispatch, and " +
    "this script already handles it:\n" +
    "     agent-session [--agent claude|codex|agy] [--dir <path>] [--workspace <n>] [--prompt <text>]\n" +
    "   e.g. agent-session --dir ~/Projects/rtl-lab --workspace 5 --prompt \"bau mir eine app\"\n\n" +
    "2. Desktop settings go through the `omarchy` CLI, live window-manager state through " +
    "`hyprctl`. Config lives in ~/.config/omarchy/ and ~/.config/hypr/. Several files there " +
    "are symlinks into ~/Projects/dotfiles, so edit them in place — never with `sed -i`, " +
    "which replaces the symlink and silently unlinks the file from the repo.\n\n" +
    "Act directly. A guard sits in front of every tool: anything that could write, delete " +
    "or change stops and asks Henri in a window on screen, and you get the result back as " +
    "the tool either running or failing. Do not ask for confirmation in your answer as " +
    "well — that is a second round for nothing, and he has already said yes or no by then. " +
    "If a tool comes back denied, say so in one line and stop; do not look for another way " +
    "round it."

  Process {
    id: agent
    command: ["agy", "--input-format", "stream-json", "--output-format", "stream-json", "-p="]
    running: false
    stdinEnabled: true
    // agent-guard reads this: it gates the voice session and leaves the agy
    // sessions Henri starts in a terminal to their own interactive review.
    environment: ({ "HENRI_VOICE": "1" })

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

    onRunningChanged: {
      if (running) root.preambleSent = false
      if (!running && root.thinking) {
        root.thinking = false
        root.finishTurn("", "The agent stopped before answering.")
      }
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

    // Events from a turn the card stopped waiting on. The agent keeps working
    // -- its answer just has nowhere to go, and must not leak into whatever is
    // on screen now.
    if (root.activeTurn !== root.turnGeneration) return
    root.lastEventAt = Date.now()

    if (msg.event === "step_update") {
      var step = msg.step_update || {}
      if (step.tool_name) {
        root.activity = step.state === "ACTIVE" ? root.toolLabel(step.tool_name) : ""
      }
      if (step.text_delta) root.streamed += step.text_delta
    } else if (msg.event === "result") {
      var r = msg.result || {}
      root.thinking = false
      root.activity = ""
      root.finishTurn((r.response || root.streamed || "").trim(),
        r.status === "SUCCESS" ? "" : (r.error || "The turn failed."))
    }
  }

  // The raw tool names are the agent's vocabulary, not Henri's.
  function toolLabel(name) {
    switch (name) {
      case "run_command":
      case "command_status":
      case "send_command_input":      return "running a command"
      case "view_file":
      case "read_resource":           return "reading a file"
      case "list_dir":                return "looking through a folder"
      case "grep_search":
      case "find_by_name":            return "searching"
      case "search_web":              return "searching the web"
      case "read_url_content":
      case "open_browser_url":        return "opening a page"
      case "write_to_file":
      case "replace_file_content":
      case "multi_replace_file_content":
      case "sed_file":                return "editing a file"
      case "invoke_subagent":
      case "define_subagent":         return "delegating"
      default:                        return name.replace(/_/g, " ")
    }
  }

  // Settle the in-flight turn into the list. An empty answer is the tool
  // auto-deny case, so the stderr line is what the card shows instead.
  function finishTurn(answer, failure) {
    if (!root.open) return                 // the card it belonged to is gone
    var text = answer
    var why = ""
    if (text.length === 0) {
      why = root.deniedTitle.length > 0
        ? "Stopped — you did not allow: " + root.deniedTitle
        : (failure.length > 0 ? failure
          : (root.lastError.length > 0 ? root.lastError : "No answer."))
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
    root.deniedTitle = ""
    root.note = ""
    root.streamed = ""
    root.pendingQuestion = q
    root.draft = ""
    root.thinking = true
    root.turnGeneration++
    root.activeTurn = root.turnGeneration
    root.activity = ""
    root.elapsed = 0
    root.turnStartedAt = Date.now()
    root.lastEventAt = Date.now()
    if (!agent.running) agent.running = true
    var content = q
    if (!root.preambleSent) {
      content = root.preamble + "\n\n———\n\n" + q
      root.preambleSent = true
    }
    agent.write(JSON.stringify({
      event: "user",
      message: { role: "user", content: content }
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

  // ── Permission window ───────────────────────────────────────────────────
  HUi.SpringValue { id: sheetPop; preset: Motion.gentle; to: root.confirmRequest ? 1 : Motion.exitToScale }

  PanelWindow {
    id: guardWin
    anchors { top: true; bottom: true; left: true; right: true }
    visible: sheet.opacity > 0.001 || root.confirmRequest !== null
    color: "transparent"

    WlrLayershell.namespace: "henri-assistant-confirm"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.confirmRequest ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // Scrim: everything behind it is out of play until this is answered.
    Rectangle {
      anchors.fill: parent
      color: "black"
      opacity: root.confirmRequest ? 0.35 : 0
      Behavior on opacity {
        NumberAnimation {
          duration: root.confirmRequest ? Motion.slow : Motion.exit(Motion.slow)
          easing.type: Easing.BezierSpline
          easing.bezierCurve: root.confirmRequest ? Motion.easeOut : Motion.easeExit
        }
      }
    }

    Confirm {
      id: sheet
      anchors.centerIn: parent
      request: root.confirmRequest
      onAllowed: root.answerConfirm(true)
      onCancelled: root.answerConfirm(false)

      focus: true
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.answerConfirm(true)
          event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
          root.answerConfirm(false)
          event.accepted = true
        }
      }

      transformOrigin: Item.Center
      scale: Motion.reduceMotion ? 1 : sheetPop.value
      opacity: root.confirmRequest ? 1 : 0
      Behavior on opacity {
        NumberAnimation {
          duration: root.confirmRequest ? Motion.slow : Motion.exit(Motion.slow)
          easing.type: Easing.BezierSpline
          easing.bezierCurve: root.confirmRequest ? Motion.easeOut : Motion.easeExit
        }
      }
    }
  }

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
    // The permission window takes the keyboard while it is up, so the card
    // gives it back -- two exclusive layers at once is one too many.
    WlrLayershell.keyboardFocus: (root.open && !root.confirmRequest)
      ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Panel {
      id: card
      turns: root.turns
      pendingQuestion: root.pendingQuestion
      streamed: root.streamed
      note: root.note
      status: root.status
      listening: root.listening
      transcribing: root.transcribing
      thinking: root.thinking
      activity: root.activity
      elapsed: root.elapsed
      levels: root.levels
      barCount: root.barCount
      sweep: root.sweep

      confirming: root.confirmRequest !== null
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
