import QtQuick
import QtQuick.Effects
import Quickshell
import "file:///home/henri/.local/share/velum/qml/Velum"

// Android's status bar along the top of the tablet (lab/mui-material QuickSettings.jsx StatusBar): the clock
// left; Do Not Disturb, Wi-Fi (or airplane), Bluetooth, the battery's percentage and Velum's battery glyph
// right — white with a soft drop shadow on the wallpaper. No input: a pull from it belongs to the owner, which
// hands it to QuickSettings. The owner lays it over the top edge (height = surface.material.qs.status.height)
// and hides it while the shade is fully open:
//
//   StatusBar { backend: qsb; width: parent.width; shown: shade.progress < 1 }
//
// Everything it shows changes by itself (UPower, NetworkManager, BlueZ, the DND file): no polling.
Item {
  id: bar
  property var backend: null
  property bool shown: true
  readonly property var k: Theme.core.surface.material.qs
  readonly property string family: k.font.family[0]
  implicitHeight: k.status.height
  height: implicitHeight
  opacity: fade.value
  visible: opacity > 0
  Spring { id: fade; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion; target: bar.shown ? 1 : 0 }

  SystemClock { id: clock; precision: SystemClock.Minutes }
  // for tests: what the right-hand row holds
  function probe() { const out = []; for (let i = 0; i < symbols.children.length; i++) { const c = symbols.children[i]; out.push([c.visible, Math.round(c.x), Math.round(c.width), Math.round(c.height)]) } return out }

  Item {
    id: content
    anchors.fill: parent
    anchors.leftMargin: bar.k.status.edge
    anchors.rightMargin: bar.k.status.edge
    // the drop shadow: one cached layer, redrawn only when the content changes (the minute, a symbol)
    layer.enabled: true
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: bar.k.status.shadow
      shadowVerticalOffset: bar.k.status.shadowY
      shadowHorizontalOffset: 0
      shadowBlur: 1
      blurMax: bar.k.status.shadowBlur * 2
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: Qt.formatTime(clock.date, "HH:mm")
      color: bar.k.status.ink
      font.family: bar.family
      font.weight: bar.k.font.medium
      font.pixelSize: bar.k.type.body
    }
    Row {
      id: symbols
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: bar.k.status.gap
      VIcon {
        visible: !!bar.backend && bar.backend.dnd
        anchors.verticalCenter: parent.verticalCenter
        name: "minus.circle"; weight: "fill"; size: bar.k.status.icon; color: bar.k.status.ink
      }
      VIcon {
        visible: !!bar.backend && (bar.backend.airplane || bar.backend.wifiOn)
        anchors.verticalCenter: parent.verticalCenter
        name: bar.backend && bar.backend.airplane ? "airplane" : "wifi"; weight: "fill"; size: bar.k.status.icon; color: bar.k.status.ink
      }
      VIcon {
        visible: !!bar.backend && bar.backend.btOn && !bar.backend.airplane
        anchors.verticalCenter: parent.verticalCenter
        name: "bluetooth"; weight: "fill"; size: bar.k.status.icon; color: bar.k.status.ink
      }
      Text {
        visible: !!bar.backend && bar.backend.hasBattery
        anchors.verticalCenter: parent.verticalCenter
        text: bar.backend ? Math.round(bar.backend.level * 100) + "%" : ""
        color: bar.k.status.ink
        font.family: bar.family
        font.weight: bar.k.font.medium
        font.pixelSize: bar.k.type.caption
      }
      VBattery {
        visible: !!bar.backend && bar.backend.hasBattery
        anchors.verticalCenter: parent.verticalCenter
        height: bar.k.status.battery
        level: bar.backend ? bar.backend.level : 1
        charging: !!bar.backend && bar.backend.charging
        plugged: !!bar.backend && bar.backend.plugged
        ink: bar.k.status.ink
      }
    }
  }
}
