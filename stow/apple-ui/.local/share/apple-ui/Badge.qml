import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "Apple.js" as Apple

// Runder Icon-Badge (36 pt) in Wi-Fi/Bluetooth-Kacheln. `on`: weißer Kreis mit
// Akzent-Glyphe (dunkles Glas) bzw. Akzent-Kreis mit weißer Glyphe (hell).
// Klick schaltet; Zustandswechsel poppt kurz (snappy), Farbe crossfadet.
Rectangle {
  id: badge
  readonly property var m: Apple.material(badge)
  property bool on: false
  property string glyph: ""
  property string glyphFont: Apple.symbolFont
  property real glyphSize: Style.spaceReal(18)
  property bool squircle: false
  property bool clickable: true
  signal clicked()

  width: Style.space(Apple.badge)
  height: width
  radius: squircle ? width * 0.28 : width / 2
  color: on ? m.badgeOn : m.badgeOff
  antialiasing: true
  Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }

  scale: press.value
  HUi.SpringValue { id: press; preset: Motion.snappy; to: mouse.pressed && !Motion.reduceMotion ? Motion.pressScale : 1 }
  transform: Scale {
    origin.x: badge.width / 2; origin.y: badge.height / 2
    xScale: pop.value; yScale: pop.value
  }
  HUi.SpringValue { id: pop; preset: Motion.snappy; to: 1 }
  onOnChanged: pop.snap(Motion.pressScale)

  Rectangle {
    anchors.fill: parent
    radius: parent.radius
    color: Qt.rgba(m.ink.r, m.ink.g, m.ink.b, mouse.pressed ? Motion.pressedAlpha : mouse.containsMouse ? Motion.hoverAlpha : 0)
    Behavior on color {
      ColorAnimation {
        duration: mouse.containsMouse || mouse.pressed ? Motion.instant : Motion.fast
        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
      }
    }
  }
  HUi.CrossfadeText {
    anchors.centerIn: parent
    horizontalAlignment: Text.AlignHCenter
    text: badge.glyph
    fontFamily: badge.glyphFont
    fontSize: badge.glyphSize
    color: badge.on ? m.badgeOnGlyph : m.badgeOffGlyph
    Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: badge.clickable
    hoverEnabled: badge.clickable
    cursorShape: Qt.PointingHandCursor
    onClicked: badge.clicked()
  }
}
