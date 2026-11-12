import QtQuick
import Quickshell.Services.UPower
import "file:///home/henri/.local/share/velum/qml/Velum"

// The Battery widget (lab Widgets.jsx Battery): this machine's charge as a ring with the number in
// it (a bolt while charging), and a line under it. From UPower's display device, live.
// API: width, height (from the home grid; 2 × 2 cells by default).
WidgetCard {
  id: bw
  readonly property var w: Theme.core.surface.material.widgets
  readonly property string family: w.font[0]
  readonly property var device: UPower.displayDevice
  readonly property bool present: !!(device && device.isPresent)
  readonly property int capacity: present ? Math.round(Math.max(0, Math.min(1, device.percentage)) * 100) : 0
  readonly property bool charging: present && device.state === UPowerDeviceState.Charging
  readonly property string status: charging ? "charging" : UPower.onBattery ? "on battery" : "plugged in"

  Column {
    anchors.centerIn: parent
    spacing: bw.w.gap
    Ring {
      anchors.horizontalCenter: parent.horizontalCenter
      size: Math.min(bw.width, bw.height) * bw.w.ringShare
      value: bw.capacity / 100
      VIcon {
        anchors.centerIn: parent
        visible: bw.charging
        name: "bolt"
        weight: "fill"
        size: bw.w.type.icon
        color: Theme.r.accent.base
      }
      Text {
        anchors.centerIn: parent
        visible: !bw.charging
        text: bw.present ? String(bw.capacity) : "—"
        color: Theme.dark ? bw.w.inkDark : bw.w.inkLight
        font.family: bw.family
        font.pixelSize: bw.w.type.title
        font.weight: bw.w.weight.medium
      }
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: bw.present ? bw.capacity + "% · " + bw.status : "Battery"
      color: Theme.dark ? bw.w.inkDark : bw.w.inkLight
      font.family: bw.family
      font.pixelSize: bw.w.type.body
      font.weight: bw.w.weight.medium
    }
  }
}
