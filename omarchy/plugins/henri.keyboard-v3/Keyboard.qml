import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "file:///home/henri/.local/share/velum/qml/Velum"
import "file:///home/henri/.local/share/velum/qml/Velum/KeyboardLayout.js" as KeyboardLayout

// The on-screen keyboard: German keys as on an iPad along the bottom edge of the screen the tablet's
// fingers are on (the cast screen). It never takes the keyboard focus, so the text field keeps it.
//
// It opens only when asked: the keyboard button of the window bar (henri.tablet-v3 sends the custom
// event "velum-keyboard toggle SCREEN"); its hide key closes it, and so does the first real key, as on
// an iPad with a keyboard attached. Opening by itself whenever a text field had the focus brought it
// back after every tap on a terminal, even the tap that had just closed it (Henri, 2026-10-25).
//
// fcitx5 holds the seat's input method; the keyboard talks to it through velum-osk (bridge/, built to
// ~/.local/lib/velum/velum-osk), which puts fcitx5 into on-screen-keyboard mode on open. Keys go to
// the text field through fcitx5 (wtype where no field of an input method has the focus).
//
// It floats as an island above the bottom edge (design 2 of lab/web/keyboard.html) and reserves its
// height while it is up (exclusive zone), so the app moves its text above it. Its command key opens
// the shortcuts page; combos go to velum-osk as "combo MODS KEY" (wtype, the only path that keeps
// the modifiers).
//
// Its mic key dictates (voxtype record start / stop; lit while voxtype records or transcribes). voxtype
// pastes with wtype, which fcitx5 takes for a real key: while any dictation runs (also one from the
// window bar or the hotkey) the bridge is told "hold on", so that key does not close the keyboard.
//
// A long press (custom event "velum-hold SCREEN X Y touch|pointer" from velum-touchd or ipadcast) in a
// focused text field opens the edit menu (EditMenu.qml, iPadOS's): Cut, Copy, Paste (when the clipboard
// has something), Select All — a terminal gets Copy and Paste with Shift. The bridge says whether a text
// field has the focus ("field" → "field N", fcitx5). A real finger in an app with a long-press menu of
// its own (Chromium, GTK, Firefox: ownMenu) is left to that app; a pointer hold (the iPad's viewer) is not.
// IPC: omarchy.keyboard toggle | open | close | state | hold SCREEN X Y KIND FIELD | menuState | menuTap LABEL
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var ks: Theme.core.surface.keyboard
  // the window: the island, the margin under it and room above for its shadow; it reserves less
  readonly property real kbHeight: ks.shadowRoom + KeyboardLayout.height(ks) + ks.islandMargin
  readonly property real kbReserve: KeyboardLayout.height(ks) + ks.islandMargin

  // a terminal copies and pastes with Shift added; the shortcuts page follows the focused app
  readonly property string appId: ToplevelManager.activeToplevel ? String(ToplevelManager.activeToplevel.appId || "") : ""
  readonly property bool terminal: /^(foot|footclient|kitty|Alacritty|com\.mitchellh\.ghostty|org\.wezfurlong\.wezterm)$/.test(appId)

  property bool shown: false
  property string screenName: ""      // where the last finger was; else the first screen
  property var board: null            // the VKeyboard on the screen it is on

  // ---- the bridge --------------------------------------------------------------------------------
  readonly property string bridgePath: Quickshell.env("HOME") + "/.local/lib/velum/velum-osk"
  // a test shell never talks to the session's fcitx5: what it would send is only noted
  readonly property bool inRig: !!Quickshell.env("VELUM_SHELL_RIG")
  property var sent: []
  property string layoutName: ""
  property string variantName: ""
  Process {
    id: layoutQuery
    running: true
    command: ["sh", "-c", "hyprctl getoption input:kb_layout -j; hyprctl getoption input:kb_variant -j"]
    stdout: StdioCollector {
      onStreamFinished: {
        var parts = String(text).split(/\}\s*\{/)
        try {
          var a = JSON.parse(parts.length > 1 ? parts[0] + "}" : text)
          root.layoutName = String(a.str || "de").split(",")[0]
          if (parts.length > 1) root.variantName = String(JSON.parse("{" + parts[1]).str || "").split(",")[0]
        } catch (e) { root.layoutName = "de" }
        bridge.running = !root.inRig
      }
    }
  }
  Process {
    id: bridge
    command: [root.bridgePath, root.layoutName || "de", root.variantName]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function (line) {
        if (line === "show") root.open(false)
        else if (line === "hide") root.close(false)
        else if (line.indexOf("field ") === 0) root.fieldAnswer(parseInt(line.slice(6)))
      }
    }
    onExited: function (code) { if (code !== 0) console.warn("henri.keyboard: velum-osk exited", code) }
  }
  // ---- dictation --------------------------------------------------------------------------------
  // the rig never records the real microphone (tests/voxtype-stub, its state in the fake HOME)
  readonly property string voxtype: root.inRig ? Qt.resolvedUrl("tests/voxtype-stub").toString().replace(/^[a-z]+:\/\//, "") : "voxtype"
  property string voxState: ""        // voxtype's alt: idle | recording | transcribing | stopped ("" = not known)
  readonly property bool dictating: voxState === "recording" || voxState === "transcribing"
  // the mic key only where a voxtype daemon runs (the tablet has it switched off: "stopped")
  readonly property bool canDictate: voxState === "idle" || dictating
  function dictate() {
    Quickshell.execDetached([root.voxtype, "record", root.dictating ? "stop" : "start"])
  }
  onDictatingChanged: root.send(root.dictating ? "hold on" : "hold off")
  Process {
    id: voxFollow
    running: true
    command: [root.voxtype, "status", "--follow", "--format", "json"]
    stdout: SplitParser {
      onRead: function (line) {
        var o = null
        try { o = JSON.parse(line) } catch (e) { return }
        root.voxState = String(o.alt || "")
      }
    }
    // no voxtype daemon (or it went away): try again later, never in a tight loop
    onExited: { root.voxState = ""; voxRetry.restart() }
  }
  Timer { id: voxRetry; interval: Theme.delay("hudHold") * 10; onTriggered: voxFollow.running = true }

  // ---- the edit menu ------------------------------------------------------------------------------
  // apps whose text fields answer a finger held on them with a menu of their own
  readonly property var ownMenu: /^(chromium|google-chrome|brave-browser|chrome-.*|firefox|org\.gnome\..*|code|code-oss|electron.*|obsidian|signal)$/i
  property var menuAt: null           // { screen, x, y } of the menu, kept while it fades out
  property bool menuOpen: false
  property var pendingHold: null      // a hold waiting for the clipboard and the bridge's answer
  property bool clipboardFull: false
  property int rigField: 0            // the rig has no bridge: hold() says what it would answer
  readonly property var menuItems: {
    var t = root.terminal, m = t ? ["ctrl", "shift"] : ["ctrl"], l = []
    if (!t) l.push({ label: "Cut", line: KeyboardLayout.comboLine(m, "x") })
    l.push({ label: "Copy", line: KeyboardLayout.comboLine(m, "c") })
    if (root.clipboardFull) l.push({ label: "Paste", line: KeyboardLayout.comboLine(m, "v") })
    if (!t) l.push({ label: "Select All", line: KeyboardLayout.comboLine(["ctrl"], "a") })
    return l
  }
  function holdAt(screen, x, y, kind) {
    if (kind === "touch" && root.ownMenu.test(root.appId)) return
    root.pendingHold = { screen: screen, x: x, y: y }
    clip.running = true                 // first the clipboard, so the words are known when it opens
  }
  Process {
    id: clip
    command: ["wl-paste", "--list-types"]
    stdout: StdioCollector {}
    onExited: function (code) {
      root.clipboardFull = code === 0 && String(clip.stdout.text).trim() !== ""
      if (!root.pendingHold) return
      if (root.inRig) root.fieldAnswer(root.rigField)
      else if (bridge.running) root.send("field")
      else root.pendingHold = null
    }
  }
  function fieldAnswer(n) {
    var h = root.pendingHold
    root.pendingHold = null
    if (!h || n <= 0) return
    root.menuOpen = false
    root.menuAt = h
    root.menuOpen = true
  }
  function menuChosen(item) {
    root.menuOpen = false
    if (item && item.line) root.send(item.line)
  }
  // another app took the focus: the menu was for the old one
  onAppIdChanged: root.menuOpen = false

  // the dock gives way while the keyboard is up (as on an iPad): "velum-keyboard shown|hidden SCREEN"
  function announce() {
    var e = "velum-keyboard " + (root.shown ? "shown " : "hidden ") + (root.screenName || (Quickshell.screens[0] ? Quickshell.screens[0].name : ""))
    Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.event(\"" + e + "\")" : "event " + e)
  }
  onShownChanged: { announce(); fitFullscreen() }

  // a fullscreen window ignores the exclusive zone, so the island would cover its last lines: while
  // the keyboard is up such a window on its screen is maximized (which keeps clear of the zone), and
  // made fullscreen again when the keyboard goes, if it is still that window and still maximized.
  // Hyprland.dispatch wraps the string in hl.dispatch(...), hence the function that returns a dispatcher.
  function fitFullscreen() {
    if (!Hyprland.usingLua || root.inRig) return
    var mon = root.screenName || (Quickshell.screens[0] ? Quickshell.screens[0].name : "")
    if (root.shown)
      Hyprland.dispatch("(function() local w = hl.get_active_window(); "
        + "if w and w.fullscreen == 2 and w.monitor and w.monitor.name == \"" + mon + "\" then "
        + "_G.velum_kb_demoted = w.address; "
        + "return hl.dsp.window.fullscreen({ mode = \"maximized\", window = \"address:\" .. w.address }) end; "
        + "return hl.dsp.event(\"velum-keyboard fit\") end)()")
    else
      Hyprland.dispatch("(function() local a = _G.velum_kb_demoted; _G.velum_kb_demoted = nil; "
        + "for _, w in ipairs(hl.get_windows()) do if a and w.address == a and w.fullscreen == 1 then "
        + "return hl.dsp.window.fullscreen({ mode = \"fullscreen\", window = \"address:\" .. a }) end end; "
        + "return hl.dsp.event(\"velum-keyboard fit\") end)()")
  }
  onScreenNameChanged: if (root.shown) announce()

  function send(line) {
    if (root.inRig) { var l = root.sent.slice(-19); l.push(line); root.sent = l }
    else if (bridge.running) bridge.write(line + "\n")
  }

  function open(byHand) {
    if (byHand) send("open")
    if (root.board) root.board.reset()
    root.shown = true
  }
  // the board is reset on the next open, not here: the island slides away from where it is (also
  // from where the grabber pulled it)
  function close(byHand) {
    if (byHand) send("close")
    root.shown = false
  }

  Connections {
    target: Hyprland
    // "velum-touch SCREEN" from ipadcast: a finger was lifted there — the screen the keyboard goes to.
    // "velum-keyboard toggle SCREEN": the window bar's keyboard button.
    // "velum-keyboard open SCREEN": open only (the window bar's search button, beside Spotlight).
    function onRawEvent(event) {
      if (event.name !== "custom") return
      var d = String(event.data)
      if (d.length > 64) return
      var name = ""
      if (d.indexOf("velum-hold ") === 0) {
        var a = d.slice(11).trim().split(" ")
        if (a.length === 4 && /^[A-Za-z0-9_-]+$/.test(a[0]) && isFinite(a[1]) && isFinite(a[2]))
          root.holdAt(a[0], Number(a[1]), Number(a[2]), a[3])
        return
      }
      if (d.indexOf("velum-touch ") === 0) name = d.slice(12).trim()
      else if (d.indexOf("velum-keyboard toggle ") === 0) name = d.slice(22).trim()
      else if (d.indexOf("velum-keyboard open ") === 0) name = d.slice(20).trim()
      else return
      if (/^[A-Za-z0-9_-]+$/.test(name)) root.screenName = name
      if (d.indexOf("velum-keyboard toggle ") === 0) { if (root.shown) root.close(true); else root.open(true) }
      else if (d.indexOf("velum-keyboard open ") === 0 && !root.shown) root.open(true)
    }
  }

  IpcHandler {
    target: "omarchy.keyboard"
    function toggle(): void { if (root.shown) root.close(true); else root.open(true) }
    function open(): void { root.open(true) }
    function close(): void { root.close(true) }
    // rig: press the key that types `label` (or names `act`) as a finger would
    function tap(label: string): void { if (root.board) root.board.tap(label) }
    // rig: a long press at X, Y as a source would send it; FIELD = the bridge's answer (0: no text field)
    function hold(screen: string, x: real, y: real, kind: string, field: int): void { root.rigField = field; root.holdAt(screen, x, y, kind) }
    function menuState(): string { return JSON.stringify({ open: root.menuOpen, at: root.menuAt, items: root.menuItems.map(function (i) { return i.label }), app: root.appId }) }
    function menuTap(label: string): bool {
      var w = menuWins.instances.length ? menuWins.instances[0] : null
      if (!w) return false
      for (var i = 0; i < root.menuItems.length; i++) if (root.menuItems[i].label === label) { w.choose(i); return true }
      return false
    }
    function state(): string { var b = root.board || {}; return JSON.stringify({ shown: root.shown, page: b.page, shift: b.shift, caps: b.caps, mods: b.mods, terminal: root.terminal, screen: root.screenName, bridge: bridge.running, sent: root.sent, voxState: root.voxState }) }
  }

  Variants {
    id: menuWins
    model: root.menuAt ? Quickshell.screens.filter(function (s) { return s.name === root.menuAt.screen }) : []
    EditMenu {
      required property var modelData
      screen: modelData
      items: root.menuItems
      px: root.menuAt ? root.menuAt.x : 0
      py: root.menuAt ? root.menuAt.y : 0
      open: root.menuOpen
      onChosen: function (item) { root.menuChosen(item) }
      onDismissed: root.menuOpen = false
      onGone: if (!root.menuOpen) root.menuAt = null
    }
  }

  // ---- the surface ------------------------------------------------------------------------------
  Variants {
    model: Quickshell.screens.filter(function (s) { return root.screenName ? s.name === root.screenName : s === Quickshell.screens[0] })

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      anchors { bottom: true; left: true; right: true }
      implicitHeight: root.kbHeight
      visible: root.shown || slide.running || slideY.value < root.kbHeight
      exclusionMode: ExclusionMode.Normal
      exclusiveZone: root.shown ? root.kbReserve : 0
      // only the island takes fingers; beside it and in its shadow room they reach the app
      // (by numbers, not `item`: the item's region is taken with the slide's transform at that moment
      // and was not taken again when it ended, so the first taps missed every key)
      mask: Region { x: keys.card.x; y: keys.card.y; width: keys.card.width; height: keys.card.height }
      color: "transparent"
      WlrLayershell.namespace: "velum-surface"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // up from the bottom edge; going away is quicker than coming
      property real target: root.shown ? 0 : root.kbHeight
      QtObject { id: slideY; property real value: root.kbHeight }
      NumberAnimation {
        id: slide
        target: slideY; property: "value"
        duration: Theme.reduceMotion ? 0 : root.shown ? Theme.dur("base") : Theme.exit(Theme.dur("base"))
        easing.type: Easing.BezierSpline
        easing.bezierCurve: root.shown ? Theme.curve("out") : Theme.curve("exit")
      }
      // `to` is set here, not bound: the handler may run before a binding would follow
      function slideTo() { slide.stop(); slide.to = win.target; slide.start() }
      onTargetChanged: slideTo()
      Component.onCompleted: if (slideY.value !== win.target) slideTo()

      // everything slides as one; under reduced motion it only fades
      Item {
        id: sheet
        anchors.fill: parent
        transform: Translate { y: Theme.reduceMotion ? 0 : slideY.value }
        opacity: Theme.reduceMotion ? 1 - slideY.value / root.kbHeight : 1

        VKeyboard {
          id: keys
          anchors.fill: parent
          Component.onCompleted: root.board = keys
          Component.onDestruction: if (root.board === keys) root.board = null
          onTyped: function (text) { root.send("text " + text) }
          onKeyPressed: function (key) { root.send("key " + key) }
          onComboPressed: function (line) { root.send(line) }
          shortcuts: true
          terminal: root.terminal
          onHideRequested: root.close(true)
          dictation: root.canDictate
          dictating: root.dictating
          onDictateRequested: root.dictate()
        }
      }
    }
  }
}
