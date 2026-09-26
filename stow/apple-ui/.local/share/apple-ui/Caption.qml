import QtQuick
import qs.Commons
import "Apple.js" as Apple

// Erklärtext/Fußnote: subheadline 11 pt, gedämpft, umbrechend.
Text {
  readonly property var m: Apple.material(this)
  font.family: Apple.uiFont
  font.pixelSize: Style.space(Apple.subheadline)
  color: m.inkMuted
  wrapMode: Text.WordWrap
}
