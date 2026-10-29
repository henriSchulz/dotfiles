import QtQuick
import Quickshell
import Quickshell.Wayland
import "file:///home/henri/.local/share/velum/qml/Velum"

// The edit menu of a long press in a text field (iPadOS's edit menu): one row of words on the menu
// material above the finger, below it when there is no room. It opens with no transition, as every
// Velum menu; a chosen word flashes (off, on), then `chosen` fires and it fades out (menu.close).
// A tap anywhere else closes it and is swallowed (VDismissArea). Never takes the keyboard focus: the
// text field keeps it, so the combos land there.
//
//   items  [{ label, line }]   line = what velum-osk takes ("combo ctrl c")
//   px, py                     the finger, in logical px of the screen
PanelWindow {
  id: win

  property var items: []
  property real px: 0
  property real py: 0
  property bool open: false
  signal chosen(var item)             // the owner closes it (open: false) and it fades out
  signal dismissed()
  signal gone()                       // faded out: the window can go

  readonly property var es: Theme.core.surface.editMenu
  readonly property real hair: 1 / Math.max(1, win.screen ? win.screen.devicePixelRatio : 1)

  anchors { top: true; bottom: true; left: true; right: true }
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"
  visible: win.open || fade.running
  WlrLayershell.namespace: "velum-surface"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  property int lit: -1
  property bool flashOff: false
  property bool busy: false
  onOpenChanged: {
    if (open) { fade.stop(); bar.opacity = 1; win.lit = -1; win.flashOff = false; win.busy = false }
    else fade.restart()
  }
  function choose(i) {
    if (win.busy) return
    win.busy = true; win.lit = i; win.flashOff = true
    flash.phase = 0; flash.restart()
  }
  Timer {
    id: flash
    property int phase: 0
    interval: Theme.dur("flash")
    onTriggered: {
      if (phase === 0) { win.flashOff = false; phase = 1; restart() }
      else win.chosen(win.items[win.lit])
    }
  }
  NumberAnimation {
    id: fade
    target: bar; property: "opacity"; to: 0
    duration: Theme.exit(Theme.transitionMs("menu.close"))
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Theme.motion("menu.close").curve
    onFinished: win.gone()
  }

  VDismissArea { active: win.open && !win.busy; onDismiss: win.dismissed() }

  Item {
    id: bar
    z: 1001   // lint-ok: above the dismiss area, not a size
    width: row.implicitWidth
    height: win.es.height
    // above the finger, centred on it, kept off the edges; below it when the top is too near
    x: Math.round(Math.max(win.es.margin, Math.min(win.width - win.es.margin - width, win.px - width / 2)))
    y: Math.round(win.py - win.es.lift - height >= win.es.margin ? win.py - win.es.lift - height
                  : Math.min(win.height - win.es.margin - height, win.py + win.es.lift))
    readonly property var hairline: (Theme.r.menu.shadow || []).filter(function (l) { return !l.inset && l.blur === 0 })[0]

    VShadow { layers: Theme.r.menu.shadow; radius: win.es.radius }
    Rectangle {
      anchors.fill: parent
      radius: win.es.radius
      color: Theme.reduceTransparency ? Theme.r.menu.bgOpaque : Theme.r.menu.bg
      border.width: bar.hairline ? bar.hairline.spread : 0
      border.color: bar.hairline ? bar.hairline.color : "transparent"
    }
    // the chosen word's highlight follows the bar's rounded ends
    Item {
      anchors.fill: parent
      Row {
        id: row
        height: parent.height
        Repeater {
          model: win.items
          Item {
            id: word
            required property int index
            required property var modelData
            readonly property bool hot: (index === win.lit && !win.flashOff) || (tap.pressed && !win.busy)
            width: label.implicitWidth + 2 * win.es.padX
            height: row.height
            Rectangle {
              visible: word.hot
              anchors.fill: parent
              anchors.margins: bar.hairline ? bar.hairline.spread : 0
              readonly property real outer: win.es.radius - anchors.margins
              topLeftRadius: word.index === 0 ? outer : 0
              bottomLeftRadius: word.index === 0 ? outer : 0
              topRightRadius: word.index === win.items.length - 1 ? outer : 0
              bottomRightRadius: word.index === win.items.length - 1 ? outer : 0
              gradient: Gradient {
                GradientStop { position: 0; color: Theme.r.menu.highlightTop }
                GradientStop { position: 1; color: Theme.r.menu.highlight }
              }
            }
            Rectangle {
              visible: word.index > 0
              width: win.hair
              height: parent.height
              color: Theme.r.menu.line
            }
            Text {
              id: label
              anchors.centerIn: parent
              text: word.modelData.label
              font.family: Theme.font
              font.pixelSize: win.es.font
              font.weight: Theme.m.menu.weight
              color: word.hot ? Theme.r.menu.highlightInk : Theme.r.menu.ink
            }
            TapHandler { id: tap; onTapped: win.choose(word.index) }
          }
        }
      }
    }
  }
}
