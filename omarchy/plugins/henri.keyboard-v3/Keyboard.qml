import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "file:///home/henri/.local/share/velum/qml/Velum"
import "Layout.js" as Layout

// The on-screen keyboard: German keys as on an iPad along the bottom edge of the screen the tablet's
// fingers are on (the cast screen). It never takes the keyboard focus, so the text field keeps it.
//
// fcitx5 holds the seat's input method; the keyboard talks to it through velum-osk (bridge/, built to
// ~/.local/lib/velum/velum-osk): a finger lifted on the cast screen (ipadcast's custom event
// "velum-touch SCREEN") puts fcitx5 into on-screen-keyboard mode, and from then on fcitx5 says when a
// text field gains or loses the focus — the keyboard comes and goes with it. A real key ends the
// mode and the keyboard goes, as on an iPad with a keyboard attached. Keys go to the text field
// through fcitx5 (wtype where no field of an input method has the focus).
//
// It reserves its height while it is up (exclusive zone), so the app moves its text above it.
// IPC: omarchy.keyboard toggle | open | close | state
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var ks: Theme.core.surface.keyboard
  readonly property real kbHeight: Layout.height(ks)

  property bool shown: false
  property string screenName: ""      // where the last finger was; else the first screen
  property string page: "letters"
  property bool shift: false
  property bool caps: false
  property real lastShift: 0
  property var pressedIds: ({})       // key id → true while a finger is on it

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
  function send(line) {
    if (root.inRig) { var l = root.sent.slice(-19); l.push(line); root.sent = l }
    else if (bridge.running) bridge.write(line + "\n")
  }

  function open(byHand) {
    if (byHand) send("open")
    root.page = "letters"
    root.shown = true
  }
  function close(byHand) {
    if (byHand) send("close")
    root.shown = false
    root.shift = root.caps = false
    root.pressedIds = ({})
  }

  // ---- what a key does --------------------------------------------------------------------------
  function press(k) {
    if (k.act === "shift") {
      var t = Date.now()
      if (root.shift && t - root.lastShift < root.ks.capsTap) { root.caps = true; root.shift = true }
      else if (root.caps) { root.caps = false; root.shift = false }
      else root.shift = !root.shift
      root.lastShift = t
    } else if (k.act === "page") {
      root.page = k.to
      root.shift = root.caps = false
    } else if (k.act === "hide") {
      root.close(true)
    } else if (k.key) {
      send("key " + k.key)
    } else if (k.out) {
      send("text " + Layout.text(k, root.shift))
      if (root.shift && !root.caps && k.letter) root.shift = false
    }
  }

  Connections {
    target: Hyprland
    // "velum-touch SCREEN" from ipadcast: a finger was lifted on that screen
    function onRawEvent(event) {
      if (event.name !== "custom") return
      var d = String(event.data)
      if (d.indexOf("velum-touch ") !== 0 || d.length > 64) return
      var name = d.slice(12).trim()
      if (/^[A-Za-z0-9_-]+$/.test(name)) root.screenName = name
      root.send("touch")
    }
  }

  IpcHandler {
    target: "omarchy.keyboard"
    function toggle(): void { if (root.shown) root.close(true); else root.open(true) }
    function open(): void { root.open(true) }
    function close(): void { root.close(true) }
    // rig: press the key that types `label` (or names `act`) as a finger would
    function tap(label: string): void {
      var keys = Layout.place(root.page, 1080, root.ks)
      for (var i = 0; i < keys.length; i++) if (keys[i].label === label || keys[i].act === label || keys[i].key === label) { root.press(keys[i]); return }
    }
    function state(): string { return JSON.stringify({ shown: root.shown, page: root.page, shift: root.shift, caps: root.caps, screen: root.screenName, bridge: bridge.running, sent: root.sent }) }
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
      exclusiveZone: root.shown ? root.kbHeight : 0
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

        // the material fills the whole width, the keys stay centred on it
        Rectangle {
          anchors.fill: parent
          color: Theme.reduceTransparency ? Theme.r.popover.bgOpaque : Theme.r.popover.bg
          Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 1 / Screen.devicePixelRatio
            color: Theme.r.line.rim
          }
        }

        Item {
          id: board
          width: Math.min(parent.width, root.ks.maxWidth)
          height: root.kbHeight
          anchors.horizontalCenter: parent.horizontalCenter
          readonly property var keys: Layout.place(root.page, width, root.ks)
        }

        Repeater {
          model: board.keys
          Item {
            required property var modelData
            readonly property var k: modelData
            readonly property bool down: root.pressedIds[k.id] === true
            readonly property bool lit: k.act === "shift" && root.shift
            x: board.x + k.x
            y: k.y
            width: k.w
            height: k.h

            // the darker edge under the key, then the key
            Rectangle {
              anchors.fill: parent
              anchors.topMargin: root.ks.keyDrop
              anchors.bottomMargin: -root.ks.keyDrop
              radius: root.ks.keyRadius
              color: Theme.r.line.strong
            }
            Rectangle {
              anchors.fill: parent
              radius: root.ks.keyRadius
              color: down ? Theme.r.fill.pressed
                   : lit ? Theme.r.popover.badgeOff
                   : k.fn ? Theme.r.line.strong : Theme.r.popover.tile
            }
            VText {
              anchors.centerIn: parent
              visible: !k.icon && !!k.label
              text: k.letter && root.shift ? k.label.toUpperCase() : (k.label || "")
              font.pixelSize: k.fn || (k.label || "").length > 1 ? root.ks.labelSize : root.ks.letterSize
              color: Theme.r.popover.ink
            }
            VIcon {
              anchors.centerIn: parent
              visible: !!k.icon
              name: k.act === "shift" && root.caps ? "capslock" : (k.icon || "")
              weight: lit ? "fill" : "regular"
              size: root.ks.iconSize
              color: Theme.r.popover.ink
            }
          }
        }

        // One touch area for every key: several fingers at once, each typing the key it lifts from
        // (the nearest key, so a finger between two still types). The delete key repeats while held.
        MultiPointTouchArea {
          x: board.x
          width: board.width
          height: parent.height
          mouseEnabled: true
          maximumTouchPoints: 10
          property var fingers: ({})      // point id → key id

          function mark(id, on) {
            var p = Object.assign({}, root.pressedIds)
            if (on) p[id] = true; else delete p[id]
            root.pressedIds = p
          }
          onPressed: function (points) {
            for (var i = 0; i < points.length; i++) {
              var k = Layout.keyAt(board.keys, points[i].x, points[i].y, root.ks)
              if (!k) continue
              var f = Object.assign({}, fingers); f[points[i].pointId] = k; fingers = f
              mark(k.id, true)
              if (k.act === "delete") { root.press(k); repeat.k = k; repeat.interval = Theme.delay("repeat"); repeat.restart() }
            }
          }
          onUpdated: function (points) {
            for (var i = 0; i < points.length; i++) {
              var was = fingers[points[i].pointId]
              if (!was || was.act === "delete") continue
              var k = Layout.keyAt(board.keys, points[i].x, points[i].y, root.ks)
              if (k && k.id !== was.id) { mark(was.id, false); mark(k.id, true); var f = Object.assign({}, fingers); f[points[i].pointId] = k; fingers = f }
            }
          }
          onReleased: function (points) {
            for (var i = 0; i < points.length; i++) {
              var k = fingers[points[i].pointId]
              if (!k) continue
              var f = Object.assign({}, fingers); delete f[points[i].pointId]; fingers = f
              mark(k.id, false)
              if (k.act === "delete") repeat.stop()
              else root.press(k)
            }
          }
          onCanceled: function (points) { repeat.stop(); fingers = ({}); root.pressedIds = ({}) }
        }
        Timer {
          id: repeat
          property var k: null
          repeat: true
          onTriggered: { interval = Theme.delay("repeatInterval"); if (k) root.press(k) }
        }
      }
    }
  }
}
