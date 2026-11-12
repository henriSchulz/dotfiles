import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// A tile's details (lab QsPages.jsx Detail): back, its name, its switch, and the list — the Wi-Fi networks
// or the paired Bluetooth devices. A row connects or disconnects (through the backend: logged only unless it is
// live); a new secured network asks for its password in place. Wi-Fi asks for a scan when it opens (and by the
// refresh button beside the switch): a quiet "Scanning…" there until the backend has read the list again. The
// list takes no finger itself: the shade's finger scrolls it (`scroller`, QuickSettings).
Item {
  id: d
  property var backend: null
  property string kind: "wifi"            // wifi | bluetooth
  signal back()
  readonly property var k: Theme.core.surface.material.qs
  readonly property bool isWifi: kind === "wifi"
  readonly property bool on: !backend ? false : isWifi ? backend.wifiOn && !backend.airplane : backend.btOn
  readonly property var rows: !backend || !on ? [] : isWifi ? backend.wifiRows : backend.btRows
  property string asking: ""              // the network whose password is asked for
  readonly property alias scroller: list
  readonly property bool scanning: isWifi && !!backend && backend.wifiScanning
  implicitHeight: head.height + k.header.gap + list.height
  Component.onCompleted: if (isWifi && on) backend.wifiRescan()
  onOnChanged: if (isWifi && on) backend.wifiRescan()

  function bars(s) { return s >= 75 ? "wifi" : s >= 50 ? "wifi.medium" : s >= 25 ? "wifi.low" : "wifi.none" }
  readonly property string empty: !on ? (isWifi ? "Wi-Fi is off" : "Bluetooth is off")
    : isWifi ? "Looking for networks…" : "No paired devices"

  Item {
    id: head
    width: d.width
    height: d.k.header.button
    MIconButton { id: backBtn; objectName: "btn-back"; icon: "arrow.left"; label: "Back"; onClicked: d.back() }
    MText { x: backBtn.width + d.k.header.gap; width: (d.isWifi ? scanText.x : sw.x) - x; anchors.verticalCenter: parent.verticalCenter
      size: "subtitle"; medium: true; text: d.isWifi ? "Internet" : "Bluetooth" }
    // Wi-Fi: "Scanning…" fades in over the refresh button's place while a scan runs (nothing moves)
    MText {
      id: scanText
      objectName: "scanning"
      visible: d.isWifi && opacity > 0
      anchors.right: rescanBtn.right; anchors.verticalCenter: parent.verticalCenter
      size: "caption"; tone: "secondary"; text: "Scanning…"
      opacity: d.scanning ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: d.scanning ? Theme.dur("fast") : Theme.exit(Theme.dur("fast")); easing.bezierCurve: Theme.curve("out") } }
    }
    MIconButton {
      id: rescanBtn
      objectName: "btn-rescan"
      visible: d.isWifi && d.on
      anchors.right: sw.left; anchors.rightMargin: d.k.header.gap; anchors.verticalCenter: parent.verticalCenter
      icon: "refresh"; label: "Scan for networks"
      opacity: d.scanning ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: d.scanning ? Theme.exit(Theme.dur("fast")) : Theme.dur("fast"); easing.bezierCurve: Theme.curve("out") } }
      onClicked: if (!d.scanning) d.backend.wifiRescan()
    }
    MSwitch {
      id: sw
      anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      checked: d.on
      onToggled: on => { if (!d.backend) return; if (d.isWifi) d.backend.setWifi(on); else d.backend.setBluetooth(on) }
    }
  }

  Flickable {
    id: list
    y: head.height + d.k.header.gap
    width: d.width
    height: Math.min(contentHeight, d.k.detail.rows * d.k.detail.row + d.k.detail.listPad)
    contentHeight: d.rows.length ? rowsCol.height : emptyText.height + 2 * d.k.detail.rowPad
    clip: true
    interactive: false
    boundsBehavior: Flickable.StopAtBounds
    flickDeceleration: Theme.core.motion.scroll.flickDeceleration
    maximumFlickVelocity: Theme.core.motion.scroll.maximumFlickVelocity
    MText { id: emptyText; visible: d.rows.length === 0; x: d.k.detail.rowPad; y: d.k.detail.rowPad; text: d.empty; tone: "secondary" }
    Column {
      id: rowsCol
      width: d.width
      Repeater {
        model: d.rows
        Column {
          id: rowItem
          required property var modelData
          width: d.width
          readonly property bool active: modelData.connected
          readonly property bool pending: d.backend && (d.isWifi ? d.backend.wifiPending === modelData.name : d.backend.btPending === modelData.address)
          Item {
            width: d.width; height: d.k.detail.row
            Rectangle { anchors.fill: parent; radius: d.k.detail.rowRadius; color: Qt.alpha(Theme.r.accent.base, d.k.detail.activeAlpha); visible: rowItem.active }
            Rectangle { anchors.fill: parent; radius: d.k.detail.rowRadius; color: Theme.r.popover.ink; opacity: rowArea.pressed ? Theme.core.alpha.pressed : 0 }
            Row {
              x: d.k.detail.rowPad; width: parent.width - 2 * d.k.detail.rowPad
              anchors.verticalCenter: parent.verticalCenter
              spacing: d.k.tile.iconGap
              VIcon { anchors.verticalCenter: parent.verticalCenter; size: d.k.header.icon; color: Theme.r.popover.ink
                name: d.isWifi ? d.bars(rowItem.modelData.signal) : d.backend.btIcon(rowItem.modelData.icon) }
              Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - d.k.header.icon - parent.spacing - (lock.visible ? lock.width + parent.spacing : 0)
                MText { width: parent.width; medium: true; text: rowItem.modelData.name }
                MText { width: parent.width; size: "caption"; tone: "secondary"
                  text: rowItem.pending ? (rowItem.active ? "Disconnecting…" : "Connecting…")
                    : rowItem.active ? "Connected" : d.isWifi ? (rowItem.modelData.known ? "Saved" : rowItem.modelData.secure ? "Secured" : "Open") : "Paired" }
              }
              VIcon { id: lock; visible: d.isWifi && rowItem.modelData.secure; anchors.verticalCenter: parent.verticalCenter
                name: "lock"; size: d.k.detail.small; color: Theme.r.popover.inkSecondary }
            }
            TapHandler {
              id: rowArea
              onTapped: {
                const r = rowItem.modelData
                if (!d.backend) return
                if (!d.isWifi) { d.backend.btActivate(r); return }
                if (!r.connected && !r.known && r.secure) { d.asking = d.asking === r.name ? "" : r.name; if (d.asking) pw.forceActiveFocus(); return }
                d.asking = ""
                d.backend.wifiActivate(r, "")
              }
            }
          }
          // a new secured network: its password, Return joins
          Item {
            visible: d.asking === rowItem.modelData.name
            width: d.width; height: visible ? d.k.detail.field + d.k.header.gap : 0
            Rectangle {
              x: d.k.detail.rowPad; width: parent.width - 2 * d.k.detail.rowPad; height: d.k.detail.field
              radius: height / 2
              color: Qt.alpha(Theme.r.popover.ink, d.k.tile.offAlpha)
              TextInput {
                id: pw
                anchors.fill: parent
                anchors.leftMargin: d.k.tile.padX; anchors.rightMargin: d.k.tile.padX
                verticalAlignment: TextInput.AlignVCenter
                echoMode: TextInput.Password
                color: Theme.r.popover.ink
                font.family: d.k.font.family[0]
                font.pixelSize: d.k.type.body
                onAccepted: { d.backend.wifiActivate(rowItem.modelData, text); text = ""; d.asking = "" }
                MText { visible: pw.text === ""; anchors.verticalCenter: parent.verticalCenter; text: "Password"; tone: "secondary" }
              }
            }
          }
        }
      }
    }
  }
}
