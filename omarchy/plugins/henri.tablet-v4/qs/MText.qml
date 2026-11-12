import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// Text on the Quick Settings panels: Material's type scale (surface.material.qs.type) in Roboto, the panel's
// inks (Velum's popover roles). size: h3 | h4 | subtitle | body | caption | small; tone: primary | secondary.
Text {
  id: t
  property string size: "body"
  property bool medium: false
  property string tone: "primary"
  readonly property var k: Theme.core.surface.material.qs
  font.family: k.font.family[0]
  font.pixelSize: k.type[size]
  font.weight: medium ? k.font.medium : k.font.regular
  lineHeightMode: Text.ProportionalHeight
  lineHeight: k.lineHeight[size]
  color: tone === "secondary" ? Theme.r.popover.inkSecondary : Theme.r.popover.ink
  elide: Text.ElideRight
  maximumLineCount: 1
}
