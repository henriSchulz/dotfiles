import QtQuick
import qs.Commons
import "Apple.js" as Apple

// SF-Symbol als Text. `size` in Punkten der Shell-Skala.
Text {
  readonly property var m: Apple.material(this)
  property real size: Style.spaceReal(16)
  font.family: Apple.symbolFont
  font.pixelSize: size
  color: m.ink
}
