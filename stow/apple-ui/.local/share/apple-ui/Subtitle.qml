import QtQuick
import qs.Commons
import "Apple.js" as Apple

// Zweite Zeile unter einem Titel: callout 12 pt regular, Sekundärfarbe.
Text {
  readonly property var m: Apple.material(this)
  font.family: Apple.uiFont
  font.pixelSize: Style.space(Apple.callout)
  color: m.inkSecondary
  elide: Text.ElideRight
}
