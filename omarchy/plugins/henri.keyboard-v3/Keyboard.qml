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
// It opens when asked (the keyboard button of the window bar: henri.tablet-v3 sends the custom event
// "velum-keyboard toggle SCREEN") and, in tablet mode, by itself when a finger taps into a text field:
// fcitx5 reports the focus ("focus in", through the bridge) and a finger was lifted ("velum-touch")
// within autoPair of it — never in a terminal (it focuses again on every tap; opening on any focus
// brought the keyboard back after every tap on one, even the tap that had just closed it, Henri
// 2026-10-25), and not again in the window where it was put away by hand until another window has
// the focus. Its hide key closes it, and so does the first real key, as on an iPad with a keyboard
// attached. That key also ends fcitx5's on-screen-keyboard mode (no focus reports); the next finger
// lift arms it again, and the bridge counts a field focused at that moment as that tap's
// (a mouse click never opens it: no finger).
// It goes by itself when what it typed into goes (Henri, 2026-11-08: it stayed up and was in the way):
// another window takes the focus, its screen shows another workspace (the home gesture too),
// Spotlight closes when it came with Spotlight (the window bar's search; "velum-menu hidden"), or —
// when it opened by itself — the text field lost the focus and none took it within refocus.
//
// fcitx5 holds the seat's input method; the keyboard talks to it through velum-osk (bridge/, built to
// ~/.local/lib/velum/velum-osk), which puts fcitx5 into on-screen-keyboard mode on open. Keys go to
// the text field through fcitx5 (wtype where no field of an input method has the focus).
//
// It lies full width along the bottom edge OVER the app (VKeyboard `dock`, concept A · Morph of
// lab/web/typing.html with the full layout, Henri 2026-11-12: "lieber wie auf iPad einfach obendrüber"):
// it reserves nothing, so the app keeps its size and a fullscreen app stays fullscreen. When the caret
// would end up under the board the app's picture slides up as far as needed and back when the board
// goes — the hyprcaret plugin does it (`hyprctl caretlift LINE MARGIN` / `caretlift off`), as it knows
// the caret; without the plugin the board simply lies over the app. The window bar's Keyboard button
// sends "velum-keyboard morph SCREEN X Y W H" (its plate in screen px): the plate is drawn on here and
// grows into the board's toolbar while the keys slide up under it. Its toolbar's ⌘ opens the shortcuts
// page; combos go to velum-osk as "combo MODS KEY" (wtype, the only path that keeps the modifiers).
//
// Its mic key dictates (voxtype record start / stop; lit while voxtype records or transcribes). voxtype
// pastes with wtype, which fcitx5 takes for a real key: while any dictation runs (also one from the
// window bar or the hotkey) the bridge is told "hold on", so that key does not close the keyboard.
//
// A long press (custom event "velum-hold SCREEN X Y touch|pointer" from velum-touchd or ipadcast) in a
// focused text field opens the edit menu (EditMenu.qml, iPadOS's): Cut, Copy, Paste (when the clipboard
// has something), Select All — a terminal gets Copy and Paste with Shift. The bridge says whether a text
// field has the focus ("field" → "field N", fcitx5), and the hyprcaret plugin (~/Projects/hyprcaret,
// `hyprctl -j caret`) where its caret is: the finger has to be near it (surface.editMenu.reachX/Y), not
// anywhere in that window (Henri 2026-11-09: it opened beside the text). Without the plugin (not built
// for this Hyprland) only the window counts. A real finger in an app with a long-press menu of its own
// (Chromium, GTK, Firefox, mdview: ownMenu) is left to that app; a pointer hold (the iPad's viewer) is not.
// IPC: omarchy.keyboard toggle | open | close | state | hold SCREEN X Y KIND FIELD | menuState | menuTap LABEL
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var ks: Theme.core.surface.keyboard
  readonly property var kd: ks.dock
  // the window: the docked board, toolbar and keys
  readonly property real kbHeight: kd.toolbar + KeyboardLayout.dockHeight(kd)

  // a terminal copies and pastes with Shift added; the shortcuts page follows the focused app
  readonly property string appId: ToplevelManager.activeToplevel ? String(ToplevelManager.activeToplevel.appId || "") : ""
  readonly property bool terminal: /^(foot|footclient|kitty|Alacritty|com\.mitchellh\.ghostty|org\.wezfurlong\.wezterm)$/.test(appId)
  // the app's name in the toolbar: its desktop entry's, else its id
  readonly property string appTitle: {
    var e = null
    try { e = root.appId ? (DesktopEntries.byId(root.appId) || DesktopEntries.heuristicLookup(root.appId)) : null } catch (err) {}
    return e && e.name ? e.name : root.appId
  }

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
        if (root.inRig) root.arm()      // noted only: the rig has no bridge to start
      }
    }
  }
  Process {
    id: bridge
    command: [root.bridgePath, root.layoutName || "de", root.variantName]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function (line) {
        root.bridgeLine(line)
      }
    }
    onStarted: root.arm()
    onExited: function (code) { if (code !== 0) console.warn("henri.keyboard: velum-osk exited", code) }
  }
  function bridgeLine(line) {
    if (line === "show") root.open(false)
    else if (line === "hide") root.close(false)
    else if (line === "focus in") root.focusIn()
    else if (line === "focus out") root.focusOut()
    else if (line === "mode osk" || line === "mode physical") root.oskMode = line === "mode osk"
    else if (line.indexOf("field ") === 0) root.fieldAnswer(parseInt(line.slice(6)))
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
  // apps whose text fields answer a finger held on them with a menu of their own (mdview: WebKit2GTK
  // tells the compositor its caret only with the next focus change, so hyprcaret cannot follow it)
  readonly property var ownMenu: /^(chromium|google-chrome|brave-browser|chrome-.*|firefox|org\.gnome\..*|code|code-oss|electron.*|obsidian|signal|dev\.henri\.MdView)$/i
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
    if (where.running || clip.running) return
    root.pendingHold = { screen: screen, x: x, y: y }
    where.running = true                // first: is the finger on the focused app's window at all
  }
  // fcitx5 keeps the last text field focused when the screen shows no window (the tablet's home
  // screen, an empty workspace) or the finger is on the bar: the menu opens only on the focused
  // window, on the workspace its screen shows (Henri 2026-11-01: only on text), near its caret
  Process {
    id: where
    command: ["sh", "-c", "hyprctl -j monitors; echo; echo --; hyprctl -j activewindow; echo; echo --; hyprctl -j caret"]
    stdout: StdioCollector {}
    onExited: function (code) {
      if (root.pendingHold && root.onFocusedWindow(String(where.stdout.text), root.pendingHold)) clip.running = true
      else root.pendingHold = null
    }
  }
  function onFocusedWindow(text, h) {
    var parts = text.split("\n--\n"), mons = [], w = null
    try { mons = JSON.parse(parts[0]); w = JSON.parse(parts[1]) } catch (e) { return false }
    var m = mons.filter(function (o) { return o.name === h.screen })[0]
    if (!m || !w || !w.address || w.monitor !== m.id || !w.workspace) return false
    var shown = w.workspace.id === m.activeWorkspace.id || (m.specialWorkspace && w.workspace.id === m.specialWorkspace.id)
    if (!shown) return false
    var gx = m.x + h.x, gy = m.y + h.y
    if (!(gx >= w.at[0] && gx <= w.at[0] + w.size[0] && gy >= w.at[1] && gy <= w.at[1] + w.size[1])) return false
    return root.nearCaret(parts[2], gx, gy)
  }
  // the caret of the focused text field (layout px) against the finger; no answer = no plugin = yes
  function nearCaret(text, gx, gy) {
    var c = null
    try { c = JSON.parse(text) } catch (e) { return true }
    if (!c || c.enabled === undefined) return true
    if (!c.enabled || !c.rect) return false
    var es = Theme.core.surface.editMenu
    return gx >= c.x - es.reachX && gx <= c.x + c.w + es.reachX && gy >= c.y - es.reachY && gy <= c.y + c.h + es.reachY
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
  onShownChanged: {
    announce(); lift()
    if (root.shown) { root.lastWorkspace = root.screenWorkspace; root.lastScreen = root.ownScreen }
  }

  // The caret stays in sight: hyprcaret moves the focused window's picture (and where its input lands)
  // up while the caret would be under the board, LINE = the board's top edge in layout px. Without the
  // plugin hyprctl only says it does not know the command.
  property var lifts: []              // for tests: the caretlift lines sent
  function lift() {
    var a = ["off"]
    var sc = Quickshell.screens.filter(function (s) { return s.name === root.ownScreen })[0]
    if (root.shown && sc) a = [String(Math.round(sc.y + sc.height - root.kbHeight)), String(root.kd.caretMargin)]
    var l = root.lifts.slice(-9); l.push(a.join(" ")); root.lifts = l
    Quickshell.execDetached(["hyprctl", "caretlift"].concat(a))
  }
  onScreenNameChanged: if (root.shown) { announce(); lift() }

  function send(line) {
    if (root.inRig) { var l = root.sent.slice(-19); l.push(line); root.sent = l }
    else if (bridge.running) bridge.write(line + "\n")
  }

  // the window bar's plate, when the board grows out of it ({ x, y, w, h } in screen px), else null
  property var morphFrom: null
  function open(byHand, from) {
    if (!byHand && root.shown) return   // the bridge's "show" after our own "open"
    root.morphFrom = from && !root.shown && !Theme.reduceMotion ? from : null
    if (byHand) send("open")
    if (root.board) root.board.reset()
    root.withMenu = false
    root.autoOpened = false
    root.shown = true
  }
  // the board is reset on the next open, not here: the island slides away from where it is (also
  // from where the grabber pulled it)
  function close(byHand) {
    if (byHand) send("close")
    root.withMenu = false
    root.autoOpened = false
    refocusWait.stop()
    root.shown = false
  }
  // put away by hand (hide key, grabber, its button): not again by itself in this window
  function dismiss() {
    if (root.shown) root.dismissedWindow = root.activeWindow
    root.close(true)
  }

  // ---- coming by itself (tablet mode) ----------------------------------------------------------------
  property bool oskMode: false        // fcitx5 in on-screen-keyboard mode: it reports text fields' focus
  property bool autoOpened: false     // this time it came by itself: it goes with the field
  property var dismissedWindow: null
  property real touchAt: 0            // when a finger was last lifted, when a field last took the focus
  property real focusAt: 0
  // tablet mode: fcitx5 into on-screen-keyboard mode, so a tap into a field can be told
  function arm() { if (Theme.touch) root.send("arm") }
  Connections { target: Theme; function onTouchChanged() { root.arm() } }
  function focusIn() {
    refocusWait.stop()
    root.focusAt = Date.now()
    root.autoOpen()
  }
  function focusOut() { if (root.shown && root.autoOpened) refocusWait.restart() }
  Timer { id: refocusWait; interval: root.ks.refocus; onTriggered: if (root.shown && root.autoOpened) root.close(true) }
  // Opening by itself on a tapped text field is off (Henri 2026-11-10): the keyboard comes only from
  // the window bar's keyboard button. The iPhone's screen view sends real touches too, and a tap
  // into a field there kept bringing it up on the cast.
  readonly property bool autoShow: false
  function autoOpen() {
    if (!root.autoShow) return
    if (root.shown || !Theme.touch || root.terminal) return
    if (root.dismissedWindow && root.activeWindow === root.dismissedWindow) return
    if (Math.abs(root.focusAt - root.touchAt) > root.ks.autoPair) return
    root.open(true)
    root.autoOpened = true
  }

  // ---- going by itself ------------------------------------------------------------------------------
  property bool withMenu: false       // opened beside Spotlight: it closes with it
  // the focused window: another one (another app, or a window of the same app) closes the keyboard.
  // A surface with the keyboard focus (Spotlight) leaves no window active for a moment; coming back
  // to the same window is no change.
  property var lastWindow: null
  readonly property var activeWindow: ToplevelManager.activeToplevel
  onActiveWindowChanged: {
    if (!root.activeWindow) return
    if (root.lastWindow && root.activeWindow !== root.lastWindow) {
      if (root.shown) root.close(true)
      root.dismissedWindow = null
    }
    root.lastWindow = root.activeWindow
  }
  // another workspace on the keyboard's screen (also the home gesture's empty one); focus going to
  // another screen and back is no change
  readonly property string ownScreen: root.screenName || (Quickshell.screens[0] ? Quickshell.screens[0].name : "")
  readonly property var ownMonitor: Hyprland.monitors.values.filter(function (m) { return m.name === root.ownScreen })[0] || null
  readonly property int screenWorkspace: root.ownMonitor && root.ownMonitor.activeWorkspace ? root.ownMonitor.activeWorkspace.id : -1
  property int lastWorkspace: -1
  property string lastScreen: ""      // the screen lastWorkspace was on: following the finger elsewhere is no change
  onScreenWorkspaceChanged: {
    if (root.screenWorkspace === -1) return
    if (root.shown && root.lastScreen === root.ownScreen && root.lastWorkspace !== -1
        && root.screenWorkspace !== root.lastWorkspace) root.close(true)
    root.lastWorkspace = root.screenWorkspace
    root.lastScreen = root.ownScreen
  }

  Connections {
    target: Hyprland
    // "velum-touch SCREEN" from ipadcast: a finger was lifted there — the screen the keyboard goes to.
    // "velum-keyboard toggle SCREEN": the window bar's keyboard button.
    // "velum-keyboard open SCREEN": ignored — the keyboard never comes by itself, only from its own
    //   button (toggle) (Henri 2026-11-12: not with the search bar, nowhere).
    // "velum-menu hidden": Spotlight closed (henri.menu-v3).
    function onRawEvent(event) {
      if (event.name !== "custom") return
      var d = String(event.data)
      if (d.length > 96) return
      var name = ""
      if (d.indexOf("velum-hold ") === 0) {
        var a = d.slice(11).trim().split(" ")
        if (a.length === 4 && /^[A-Za-z0-9_-]+$/.test(a[0]) && isFinite(a[1]) && isFinite(a[2]))
          root.holdAt(a[0], Number(a[1]), Number(a[2]), a[3])
        return
      }
      if (d === "velum-menu hidden") { if (root.shown && root.withMenu) root.close(true); return }
      // the window bar's Keyboard button: "velum-keyboard morph SCREEN X Y W H", its plate grows into the toolbar
      if (d.indexOf("velum-keyboard morph ") === 0) {
        var mo = d.slice(21).trim().split(" ")
        if (mo.length !== 5 || !/^[A-Za-z0-9_-]+$/.test(mo[0]) || !mo.slice(1).every(function (v) { return isFinite(v) && v !== "" })) return
        root.screenName = mo[0]
        if (!root.shown) root.open(true, { x: Number(mo[1]), y: Number(mo[2]), w: Number(mo[3]), h: Number(mo[4]) })
        return
      }
      if (d.indexOf("velum-touch ") === 0) {
        name = d.slice(12).trim()
        root.touchAt = Date.now()
        // a real key (also voxtype's paste) ended fcitx5's on-screen-keyboard mode, which reports no
        // focus then: a finger takes it back (the M1's own keyboard is always there, so "a keyboard is
        // attached" cannot mean "never by itself" here; Henri 2026-11-09: it never opened)
        if (!root.oskMode && Theme.touch && !root.shown) root.send("arm")
      }
      else if (d.indexOf("velum-keyboard toggle ") === 0) name = d.slice(22).trim()
      else return
      if (/^[A-Za-z0-9_-]+$/.test(name)) root.screenName = name
      if (d.indexOf("velum-keyboard toggle ") === 0) { if (root.shown) root.dismiss(); else root.open(true) }
      else if (d.indexOf("velum-touch ") === 0 && root.focusAt) root.autoOpen()   // the lift after the field took the focus
    }
  }

  IpcHandler {
    target: "omarchy.keyboard"
    function toggle(): void { if (root.shown) root.dismiss(); else root.open(true) }
    function open(): void { root.open(true) }
    // rig: the window bar's morph as its event brings it
    function morph(screen: string, x: real, y: real, w: real, h: real): void { root.screenName = screen; if (!root.shown) root.open(true, { x: x, y: y, w: w, h: h }) }
    // rig: a toolbar button by name (esc, tab, ctrl, shortcuts, left, up, down, right, undo, redo, paste, mic, hide)
    function tool(name: string): bool { return root.board ? root.board.tool(name) : false }
    function lifts(): string { return JSON.stringify(root.lifts) }
    function close(): void { root.dismiss() }
    // rig: a line as the bridge would print it ("focus in", "focus out", "mode physical" …)
    function bridgeSays(line: string): void { root.bridgeLine(line) }
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
    function state(): string { var b = root.board || {}; return JSON.stringify({ shown: root.shown, page: b.page, shift: b.shift, caps: b.caps, mods: b.mods, terminal: root.terminal, screen: root.screenName, bridge: bridge.running, sent: root.sent, voxState: root.voxState, auto: root.autoOpened, osk: root.oskMode, dismissed: !!root.dismissedWindow, height: root.kbHeight, title: root.appTitle, morph: !!root.morphFrom }) }
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
  // one window per screen; the board shows on the screen the last finger was on (ownScreen). In tablet
  // mode the windows stay mapped, empty and without input while the board is away: mapping one costs
  // 100–200 ms, and the window bar's plate must be drawn on in the very next frame.
  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      readonly property bool mine: modelData.name === root.ownScreen
      readonly property bool up: mine && root.shown
      onMineChanged: if (mine) root.board = keys
      anchors { bottom: true; left: true; right: true }
      implicitHeight: root.kbHeight
      visible: Theme.touch || up || slide.running || slideY.value < root.kbHeight
      // over the app: it reserves nothing (the caret is kept in sight by caretlift)
      exclusionMode: ExclusionMode.Ignore
      // the whole board takes fingers while it is there, nothing while it is away (by numbers, not
      // `item`: the item's region is taken with the slide's transform at that moment and was not
      // taken again when it ended)
      mask: Region { x: 0; y: 0; width: win.up || slide.running ? win.width : 0; height: root.kbHeight }
      color: "transparent"
      WlrLayershell.namespace: "velum-surface"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // up from the bottom edge; going away is quicker than coming
      property real target: win.up ? 0 : root.kbHeight
      QtObject { id: slideY; property real value: root.kbHeight }
      NumberAnimation {
        id: slide
        target: slideY; property: "value"
        duration: Theme.reduceMotion ? 0 : win.up ? root.kd.slide : Theme.exit(root.kd.slide)
        easing.type: Easing.BezierSpline
        easing.bezierCurve: win.up ? Theme.curve("out") : Theme.curve("exit")
      }
      // `to` is set here, not bound: the handler may run before a binding would follow
      function slideTo() { slide.stop(); slide.to = win.target; slide.start(); if (win.up && root.morphFrom) plate.land() }
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
          dock: true
          title: root.appTitle
          // the toolbar's buttons come only once the plate has landed (and are out while the board is away)
          toolsShown: win.up && !plate.visible && !root.morphFrom
          Component.onCompleted: if (win.mine) root.board = keys
          Component.onDestruction: if (root.board === keys) root.board = null
          onTyped: function (text) { root.send("text " + text) }
          onKeyPressed: function (key) { root.send("key " + key) }
          onComboPressed: function (line) { root.send(line) }
          shortcuts: true
          terminal: root.terminal
          onHideRequested: root.dismiss()
          dictation: root.canDictate
          dictating: root.dictating
          onDictateRequested: root.dictate()
        }
      }

      // the window bar's plate (A · Morph): drawn where the bar stood, it widens into the toolbar on the
      // slide's own timing; it waits where the bar was until the rising board reaches it and then rides
      // on the board's top edge. Then it fades and the toolbar's buttons come in. Outside the sliding
      // sheet, so it travels by itself.
      Rectangle {
        id: plate
        property real y0: 0
        visible: false
        y: Math.min(y0, Theme.reduceMotion ? 0 : slideY.value)
        color: Theme.reduceTransparency ? Theme.r.popover.bgOpaque : Theme.r.popover.bg
        border.width: 1 / Screen.devicePixelRatio
        border.color: Theme.r.line.rim
        function land() {
          var f = root.morphFrom
          grow.stop(); fade.stop()
          x = f.x; y0 = f.y - (win.modelData.height - root.kbHeight); width = f.w; height = f.h
          var wb = Theme.core.surface.tablet.windowBar
          radius = Math.min(f.h / 2, wb.buttonRadius + wb.pad)   // the bar's own corner
          opacity = 1
          visible = true
          root.morphFrom = null      // after `visible`: the toolbar's buttons stay out in between
          grow.start()
        }
        ParallelAnimation {
          id: grow
          readonly property int ms: slide.duration
          readonly property var curve: Theme.curve("out")
          NumberAnimation { target: plate; property: "x"; to: 0; duration: grow.ms; easing.type: Easing.BezierSpline; easing.bezierCurve: grow.curve }
          NumberAnimation { target: plate; property: "width"; to: win.width; duration: grow.ms; easing.type: Easing.BezierSpline; easing.bezierCurve: grow.curve }
          NumberAnimation { target: plate; property: "height"; to: root.kd.toolbar; duration: grow.ms; easing.type: Easing.BezierSpline; easing.bezierCurve: grow.curve }
          NumberAnimation { target: plate; property: "radius"; to: root.kd.radius; duration: grow.ms; easing.type: Easing.BezierSpline; easing.bezierCurve: grow.curve }
          onFinished: fade.start()
        }
        NumberAnimation { id: fade; target: plate; property: "opacity"; to: 0; duration: Theme.dur("fast"); onFinished: plate.visible = false }
        Connections { target: win; function onUpChanged() { if (!win.up) { grow.stop(); fade.stop(); plate.visible = false } } }
      }
    }
  }
}
