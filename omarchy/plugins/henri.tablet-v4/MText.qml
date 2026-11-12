import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// Text in Roboto (bundled in fonts/, loaded once by Home.qml's FontLoaders) at MUI's body2 unless told
// otherwise — the Material home screen's type (surface.material.type).
Text {
  font.family: "Roboto"
  font.pixelSize: Theme.core.surface.material.type.body2
  font.weight: Font.Normal
  verticalAlignment: Text.AlignVCenter
  elide: Text.ElideRight
}
