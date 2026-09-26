import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "Apple.js" as Apple

// Runde Icon-Kachel (64 pt) der Icon-Reihen. Nur Glyphe, deshalb trägt sie
// ihren Namen als Accessible.name. `on` färbt sie wie einen Badge.
Tile {
  id: it
  property string glyph: ""
  property string glyphFont: Apple.symbolFont
  property real glyphSize: Style.spaceReal(24)
  property bool on: false
  property string name: ""
  width: Style.space(Apple.circle)
  height: width
  radius: width / 2
  interactive: true
  color: on ? m.badgeOn : (interactive && hovered ? m.tileHover : m.tile)
  readonly property bool hovered: hover.hovered
  HoverHandler { id: hover }
  Accessible.role: Accessible.Button
  Accessible.name: it.name
  HUi.CrossfadeText {
    anchors.centerIn: parent
    horizontalAlignment: Text.AlignHCenter
    text: it.glyph
    fontFamily: it.glyphFont
    fontSize: it.glyphSize
    color: it.on ? m.badgeOnGlyph : m.ink
    Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
  }
}
