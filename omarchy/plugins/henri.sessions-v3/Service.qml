// The running Claude Code sessions for the menu bar, and a notification when one needs Henri.
//
// Data: ~/Projects/sessions/bin/sessions-backend (the Sessions app's read-only backend over
// ~/.claude): `live` every surface.sessions.liveInterval, `index` every bar.titleInterval for the
// titles (live entries carry only short names). The rows go to
// $XDG_RUNTIME_DIR/henri-sessions-<Hyprland instance>.json, which the bar glyph (Panel.qml, one per
// screen) reads — one poller, however many bars; per instance, so a nested test shell never writes
// the live file.
//
// Notifications (Sessions.js `decide`): a session turning `blocked` (a question, a permission) at
// once; a turn longer than bar.notifyAfter that ends ("Your turn"). Never for the session whose
// terminal is the focused window. Posted with notify-send (the shell's own notification server),
// the action "Open" opens the Sessions window on that session.
//
// Test shell (VELUM_SHELL_RIG set): nothing is posted; the notices it would post are kept for
// IPC `henri-sessions notices`, and `henri-sessions feed JSON` runs the rule on a made-up snapshot.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "file:///home/henri/.local/share/velum/qml/Velum"
import "Sessions.js" as S

Item {
  id: root
  property var shell: null
  readonly property bool inRig: (Quickshell.env("VELUM_SHELL_RIG") || "") !== ""
  readonly property var s: Theme.core.surface.sessions
  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string app: home + "/Projects/sessions/bin/sessions"
  readonly property string backend: app + "-backend"

  property var live: []
  property var titles: ({})
  property var prev: null
  property var notices: []          // the rig: what would have been posted
  property string activeWindow: ""
  property bool paused: false       // the rig: polling stops while `feed` drives the rule

  // ---- live state, every liveInterval
  Process {
    id: liveProc
    command: [root.backend, "live"]
    stdout: StdioCollector {
      onStreamFinished: {
        var d
        try { d = JSON.parse(text) } catch (e) { return }
        root.live = d.live || []
        root.judge(Date.now())
      }
    }
  }
  Timer { interval: root.s.liveInterval; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!liveProc.running && !root.paused) liveProc.running = true }

  // ---- titles, every titleInterval (incremental after the first run)
  Process {
    id: indexProc
    command: [root.backend, "index"]
    stdout: StdioCollector {
      onStreamFinished: {
        var d
        try { d = JSON.parse(text) } catch (e) { return }
        var names = {}, t = {}
        for (var i = 0; i < (d.folders || []).length; i++) names[d.folders[i].path] = d.folders[i].name
        for (var j = 0; j < (d.sessions || []).length; j++) {
          var x = d.sessions[j]
          t[x.id] = { title: x.title, folder: names[x.group] || S.baseName(x.group) }
        }
        root.titles = t
      }
    }
  }
  Timer { interval: root.s.bar.titleInterval; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!indexProc.running) indexProc.running = true }
  // a session the index has not seen yet brings it along (its title comes with its first prompt)
  onLiveChanged: {
    for (var i = 0; i < live.length; i++)
      if (!titles[live[i].sessionId] && S.statusOf(live[i])) { if (!indexProc.running) indexProc.running = true; break }
  }

  // ---- the rows for the bars
  readonly property var rows: S.rows(live, titles, home)
  readonly property string rowsText: JSON.stringify({ rows: rows, at: Date.now() })
  onRowsTextChanged: writeTimer.restart()
  Timer { id: writeTimer; interval: Theme.dur("instant"); onTriggered: stateFile.setText(root.rowsText + "\n") }
  FileView {
    id: stateFile
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/henri-sessions-" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + ".json"
    printErrors: false
  }

  // ---- notifications
  Process {
    id: activeProc
    command: ["hyprctl", "activewindow", "-j"]
    property var pending: []
    stdout: StdioCollector {
      onStreamFinished: {
        var a = ""
        try { a = JSON.parse(text).address || "" } catch (e) {}
        root.activeWindow = a
        root.post(activeProc.pending)
      }
    }
  }
  // The rule runs on every snapshot; only when it finds something is the focused window asked
  // for (one process, not one per poll), and the rule runs again with it.
  function judge(now) {
    var r = S.decide(prev, live, now, s.bar.notifyAfter, activeWindow)
    var first = prev === null
    prev = r.next
    if (first || !r.notices.length) return []
    activeProc.pending = activeProc.running ? activeProc.pending.concat(r.notices) : r.notices
    if (!activeProc.running) activeProc.running = true
    return r.notices
  }
  function post(list) {
    for (var i = 0; i < list.length; i++) {
      var n = list[i]
      var l = null
      for (var k = 0; k < live.length; k++) if (live[k].sessionId === n.id) l = live[k]
      if (l && l.window && l.window === activeWindow) continue
      var t = titles[n.id] || {}
      var title = n.kind === "blocked" ? "Waiting for you" : "Your turn"
      var body = (t.title || (l && l.name) || "Claude Code") + (t.folder ? " · " + t.folder : "")
      if (inRig) { notices = notices.concat([{ id: n.id, kind: n.kind, title: title, body: body }]); continue }
      notifier.createObject(root, { sessionId: n.id, command: ["notify-send", "-a", "Sessions", "-i", "utilities-terminal", "-A", "open=Open", title, body] })
    }
  }
  // notify-send waits while the notification is up and prints the action that was taken
  Component {
    id: notifier
    Process {
      id: p
      property string sessionId: ""
      running: true
      stdout: StdioCollector { onStreamFinished: if (text.trim() === "open") root.open(p.sessionId) }
      onExited: p.destroy()
    }
  }
  function open(id) {
    if (inRig) return
    Quickshell.execDetached(["bash", "-c", "\"$1\" select \"$2\" && \"$1\" present", "bash", app, id])
  }

  IpcHandler {
    target: "henri-sessions"
    function state(): string { return JSON.stringify({ rows: root.rows, notices: root.notices.length, rig: root.inRig }) }
    function notices(): string { return JSON.stringify(root.notices) }
    // the rig: run the rule on a made-up snapshot {"live": [...]} at a given time (ms) — an object,
    // since `qs ipc call` splits an argument that starts with "[" into several
    function feed(json: string, now: real): string {
      var d = []
      try { d = JSON.parse(json).live || [] } catch (e) { return "bad json" }
      root.live = d
      // what the rule found now; what was posted (after the focused-window check) comes with `notices`
      return JSON.stringify(root.judge(now))
    }
    // the rig: dark or light without writing the shared Velum settings file (the bar owns that)
    function dark(on: bool): string { if (!root.inRig) return "rig only"; Theme.dark = on; return "ok" }
    function pause(on: bool): void { root.paused = on; if (on) root.prev = null }
    function open(id: string): void { root.open(id) }
    // the bar popup on the focused monitor (Panel.qml listens for the custom event)
    function toggle(): void { Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.event(\"henri-sessions toggle\")" : "event henri-sessions toggle") }
  }
}
