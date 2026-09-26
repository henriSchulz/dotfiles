import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "Apple.js" as Apple

// Glas-Kachel des Control Centers: Fill + Haarlinie, Radius 22 pt. Mit
// `interactive` hebt sie sich beim Hover (instant rein / fast raus) und gibt
// Press-Feedback (snappy). `hasCursor` zeichnet den Tastatur-Ring.
// `revealIndex` ≥ 0 lässt sie beim Öffnen gestaffelt eintreten, gesteuert über
// `appleRevealed` an einem Vorfahren (oder `revealed` direkt).
Rectangle {
  id: tile
  readonly property var m: Apple.material(tile)
  property bool interactive: false
  property bool hasCursor: false
  property int revealIndex: -1
  property bool revealed: Apple.lookup(tile, "appleRevealed", true)
  signal clicked()
  signal rightClicked()

  radius: Style.space(Apple.radius)
  color: interactive && mouse.containsMouse ? m.tileHover : m.tile
  border.width: 1
  border.color: m.hairline
  antialiasing: true
  Behavior on color {
    ColorAnimation {
      duration: tile.interactive && mouse.containsMouse ? Motion.instant : Motion.fast
      easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
    }
  }

  // Eintritts-Kaskade (Motion.stagger), Exit gemeinsam mit dem Popup.
  readonly property bool shown: revealIndex < 0 || revealed
  readonly property int revealDelay: Motion.stagger(revealIndex)
  property real enterScale: shown || Motion.reduceMotion ? 1 : Motion.popoverFromScale
  opacity: shown ? 1 : 0
  scale: enterScale * press.value
  transform: Translate {
    y: tile.shown || Motion.reduceMotion ? 0 : -Style.space(10)
    Behavior on y {
      SequentialAnimation {
        PauseAnimation { duration: tile.shown ? tile.revealDelay : 0 }
        NumberAnimation { duration: tile.shown ? Motion.slow : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
      }
    }
  }
  Behavior on opacity {
    SequentialAnimation {
      PauseAnimation { duration: tile.shown ? tile.revealDelay : 0 }
      NumberAnimation { duration: tile.shown ? Motion.base : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
    }
  }
  Behavior on enterScale {
    SequentialAnimation {
      PauseAnimation { duration: tile.shown ? tile.revealDelay : 0 }
      NumberAnimation { duration: tile.shown ? Motion.slow : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
    }
  }

  HUi.SpringValue {
    id: press
    preset: Motion.snappy
    to: tile.interactive && mouse.pressed && !Motion.reduceMotion ? Motion.pressScale : 1
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: tile.interactive
    hoverEnabled: tile.interactive
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: tile.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: function(e) { if (e.button === Qt.RightButton) tile.rightClicked(); else tile.clicked() }
  }

  // Tastatur-Cursor-Ring, über allen Kindern, nie im Weg des Zeigers.
  Rectangle {
    z: 1
    anchors.fill: parent
    radius: tile.radius
    color: "transparent"
    border.width: Math.max(2, Style.space(2))
    border.color: m.cursorRing
    opacity: tile.hasCursor ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
  }
}
