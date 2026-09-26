import QtQuick
import qs.Commons
import "Apple.js" as Apple

// Kleine Versal-Überschrift über Listen/Gruppen ("NETWORKS", "OUTPUT").
Text {
  readonly property var m: Apple.material(this)
  leftPadding: Style.space(6)
  topPadding: Style.space(4)
  color: m.inkMuted
  font.family: Apple.uiFont
  font.pixelSize: Style.space(Apple.footnote)
  font.capitalization: Font.AllUppercase
  font.letterSpacing: 0.6
}
