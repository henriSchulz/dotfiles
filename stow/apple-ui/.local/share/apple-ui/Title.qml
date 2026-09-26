import QtQuick
import qs.Commons
import "Apple.js" as Apple

// Kachel-Titel: headline 13 pt bold.
Text {
  readonly property var m: Apple.material(this)
  font.family: Apple.uiFont
  font.pixelSize: Style.space(Apple.headline)
  font.weight: Font.Bold
  color: m.ink
  elide: Text.ElideRight
}
