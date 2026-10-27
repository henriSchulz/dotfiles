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
// IPC: omarchy.keyboard toggle | open | close | state
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
      }
    }
    onExited: function (code) { if (code !== 0) console.warn("henri.keyboard: velum-osk exited", code) }
  }
  // the dock gives way while the keyboard is up (as on an iPad): "velum-keyboard shown|hidden SCREEN"
  function announce() {
    var e = "velum-keyboard " + (root.shown ? "shown " : "hidden ") + (root.screenName || (Quickshell.screens[0] ? Quickshell.screens[0].name : ""))
    Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.event(\"" + e + "\")" : "event " + e)
  }
  onShownChanged: announce()
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
    function state(): string { var b = root.board || {}; return JSON.stringify({ shown: root.shown, page: b.page, shift: b.shift, caps: b.caps, mods: b.mods, terminal: root.terminal, screen: root.screenName, bridge: bridge.running, sent: root.sent }) }
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
        }
      }
    }
  }
}
