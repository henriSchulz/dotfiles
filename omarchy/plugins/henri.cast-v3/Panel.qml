import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "file:///home/henri/.local/share/velum/qml/Velum"

// The tablet that shows this Mac (mac-cast on the tablet, ipadcast here) in the menu bar:
// its symbol and battery, only while it is connected. A click grows the right island into
// what it reports — battery, draw, latency, connection — and what the stream does, with a
// brightness slider for its panel (the tablet follows this Mac's backlight while casting).
// What it knows lives in CastService.qml, the page in CastPages.qml: the Control Center in tablet
// mode (henri.control-center-v3 FullCenter.qml) loads both too, so both always look the same.
Panel {
  id: root
  moduleName: "henri.cast"
  ipcTarget: "henri.cast"
  manageIpc: false

  // ---- what the tablet and the stream report (CastService), its page (CastPages)
  CastService { id: svc; opened: root.opened }
  CastPages { id: pages; svc: svc }
  readonly property bool connected: svc.connected
  readonly property string pctText: svc.pctText

  IpcHandler {
    target: "henri.cast"
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function state(): string { return JSON.stringify({ connected: root.connected, opened: root.opened, depth: stack.depth,
                                                       height: content.height, pulling: panel.pulling,
                                                       from: [panel.from.x, panel.from.y, panel.from.width, panel.from.height], info: svc.info }) }
  }

  onConnectedChanged: if (!connected) close()
  onOpenedChanged: if (opened && !connected) close()
  visible: connected
  implicitWidth: connected ? button.implicitWidth : 0
  implicitHeight: connected ? button.implicitHeight : 0

  // ============================================================ bar button
  readonly property real iconSize: Style.spaceReal(15)
  readonly property real barContentWidth: pctMetrics.advanceWidth + Style.spaceReal(5) + iconSize
  readonly property real openPanelIndicatorWidth: !button.vertical ? barContentWidth : 0
  TextMetrics { id: pctMetrics; font.family: root.bar ? root.bar.fontFamily : Theme.font; font.pixelSize: Style.font.body; text: root.pctText }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Math.max(Style.bar.iconSlot, Math.ceil(root.barContentWidth + Style.space(12)))
    iconComponent: Component {
      Item {
        Row {
          anchors.centerIn: parent
          spacing: Style.spaceReal(5)
          VIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "tablet"
            size: root.iconSize
            color: button ? button.foreground : Color.foreground
          }
          VCrossfadeText {
            anchors.verticalCenter: parent.verticalCenter
            width: implicitWidth
            text: root.pctText
            color: button ? button.foreground : Color.foreground
            pixelSize: Style.font.body
          }
        }
      }
    }
    tooltipText: ""
    onPressed: function (b) { if (root.connected) root.toggle() }
  }

  // a finger pulls this panel down from the top edge above its item (tablet mode, cast screen)
  VPullZone { surface: "cast"; item: button; island: panel; opened: root.opened; onCommit: root.open() }

  // ================================================================= island
  VIslandWindow {
    id: panel
    anchorItem: button
    bar: root.bar
    namespace: "velum-surface"   // Hyprland: blur with ignore_alpha 0.6 (only the material, never the shadow), no layer animation
    align: "right"
    open: root.opened && root.connected
    toWidth: Theme.layout.module.width
    contentHeight: content.height
    onDismissed: root.close()
    onReopenRequested: root.open()

    onEscapePressed: root.goBack()
    // every open starts on the first page: back to it once the island has shrunk
    onShownChanged: if (!shown) stack.reset()

    Item {
      id: content
      width: Theme.layout.module.width - 2 * panel.pad
      height: stack.implicitHeight
      VPageStack { id: stack; width: parent.width; initial: pages.page("tablet") }
    }
  }

  function goBack() { if (stack.depth > 1) stack.pop(); else root.close() }
}
