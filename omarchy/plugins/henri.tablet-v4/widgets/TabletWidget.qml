import QtQuick
import Quickshell
import Quickshell.Io
import "file:///home/henri/.local/share/velum/qml/Velum"

// The Tablet widget (lab Widgets.jsx Tablet): the casting iPad's charge as a ring, read from ipadcast's
// $XDG_RUNTIME_DIR/ipadcast/cast.json every `poll` (it is rewritten in place; a missing file = no tablet).
// API: width, height (from the home grid; 2 × 2 cells by default).
WidgetCard {
  id: tw
  readonly property var w: Theme.core.surface.material.widgets
  readonly property string family: w.font[0]
  property var cast: null
  readonly property bool connected: !!(cast && typeof cast.battery === "number")

  FileView {
    id: file
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/ipadcast/cast.json"
    printErrors: false
    onLoaded: { try { tw.cast = JSON.parse(text()) } catch (e) { tw.cast = null } }
    onLoadFailed: tw.cast = null
  }
  Timer { interval: tw.w.poll; repeat: true; running: tw.visible; onTriggered: file.reload() }

  Column {
    anchors.centerIn: parent
    spacing: tw.w.gap
    Ring {
      anchors.horizontalCenter: parent.horizontalCenter
      size: Math.min(tw.width, tw.height) * tw.w.ringShare
      value: tw.connected ? tw.cast.battery / 100 : 0
      VIcon {
        anchors.centerIn: parent
        name: "tablet"
        size: tw.w.type.icon
        color: Theme.dark ? tw.w.inkDark : tw.w.inkLight
      }
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: tw.connected ? "iPad Air · " + tw.cast.battery + "%" : "No tablet"
      color: Theme.dark ? tw.w.inkDark : tw.w.inkLight
      font.family: tw.family
      font.pixelSize: tw.w.type.body
      font.weight: tw.w.weight.medium
    }
  }
}
