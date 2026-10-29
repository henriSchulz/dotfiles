import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "file:///home/henri/.local/share/velum/qml/Velum"

// The battery in the menu bar (Velum, v3 of henri.power): "84 %" + the drawn battery.
// A click grows the right island of the bar into the battery menu — the very pages
// of the Control Center (henri.control-center-v3: PowerService.qml + PowerPages.qml,
// loaded from there), so both always look and work the same. Right click shows or
// hides the percentage. Everything the menu knows lives in PowerService.
Panel {
  id: root
  moduleName: "henri.power"
  ipcTarget: "henri.power"
  // owns the single IpcHandler the target permits (for togglePercentage and the pages)
  manageIpc: false

  // ---- the Control Center's battery menu, loaded from its plugin
  readonly property url ccDir: Qt.resolvedUrl("../henri.control-center-v3/")
  Loader {
    id: svcLoader
    source: root.ccDir + "PowerService.qml"
    onLoaded: item.opened = Qt.binding(function () { return root.opened && root.batteryPresent })
  }
  readonly property var svc: svcLoader.item
  Loader {
    id: pagesLoader
    active: svcLoader.status === Loader.Ready
    source: root.ccDir + "PowerPages.qml"
    onLoaded: {
      item.svc = root.svc
      item.standalone = true
      item.pushRequested.connect(function (n) { root.push(n) })
      item.backRequested.connect(function () { root.goBack() })
    }
  }
  readonly property var pages: pagesLoader.item
  property var names: []
  readonly property string current: names.length ? names[names.length - 1] : "battery"

  // the bar glyph works without the Control Center plugin too (plain UPower)
  readonly property var device: UPower.displayDevice
  readonly property bool batteryPresent: !!(device && device.isPresent)
  readonly property real batteryFraction: svc ? svc.batteryFraction : device ? Math.max(0, Math.min(1, device.percentage)) : 0
  readonly property bool charging: svc ? svc.charging : !!(device && device.state === UPowerDeviceState.Charging)
  readonly property bool plugged: svc ? svc.plugged : UPower.onBattery === false && !charging

  readonly property bool showPercentage: setting("showPercentage", false) === true
  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function push(name) {
    if (!pages || !pages.page(name)) return
    stack.push(pages.page(name)); names = names.concat([name])
  }
  function goBack() {
    if (pages && pages.rangeOpen) pages.rangeOpen = false
    else if (stack.depth > 1) { stack.pop(); names = names.slice(0, -1) }
    else close()
  }
  function openOn(name) {
    open()
    if (current === name) return
    stack.reset(); names = []
    if (name !== "battery") push(name)
  }

  IpcHandler {
    target: "henri.power"
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
    // straight onto History
    function history() { root.openOn("battery-history") }
    // history range (15m 30m 1h 3h 6h 12h 24h 3d 7d) and metric (percent watts volts amps)
    function historyRange(key: string): void { if (root.svc) root.svc.setHistoryRange(key) }
    function historyMetric(metric: string): void { if (root.svc) root.svc.setHistoryMetric(metric) }
    function rangeMenu(open: bool): void { if (open) root.openOn("battery-history"); if (root.pages) root.pages.rangeOpen = open }
    function state(): string {
      return JSON.stringify({ opened: root.opened, page: root.current, depth: stack.depth, loaded: !!root.pages,
                              profile: root.svc ? root.svc.activeProfile : "", width: content.width, height: content.height })
    }
  }

  onOpenedChanged: {
    if (!opened) return
    if (!batteryPresent) { close(); return }
    focusLater.restart()
  }
  onBatteryPresentChanged: if (!batteryPresent) close()
  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  // ============================================================ bar button
  readonly property bool pctInBar: root.showPercentage && !(button && button.vertical)
  readonly property string pctText: Math.round(root.batteryFraction * 100) + " %"
  readonly property real glyphH: Style.spaceReal(11.5)
  readonly property real barContentWidth: (pctInBar ? pctMetrics.advanceWidth + Style.spaceReal(5) : 0) + glyphH * 2 + Style.spaceReal(2.5)
  // with the percentage shown the button paints a wider block than an icon
  readonly property real openPanelIndicatorWidth: !button.vertical ? barContentWidth : 0
  TextMetrics { id: pctMetrics; font.family: root.bar ? root.bar.fontFamily : Theme.font; font.pixelSize: Theme.core.surface.menubar.font.size; font.weight: Theme.core.surface.menubar.font.weight; text: root.pctText }

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
          VCrossfadeText {
            visible: root.pctInBar
            anchors.verticalCenter: parent.verticalCenter
            width: implicitWidth
            text: root.pctText
            color: button ? button.foreground : Color.foreground
            pixelSize: Theme.core.surface.menubar.font.size
            weight: Theme.core.surface.menubar.font.weight
          }
          VBattery {
            anchors.verticalCenter: parent.verticalCenter
            height: root.glyphH
            level: root.batteryFraction
            charging: root.charging
            plugged: root.plugged
            ink: button ? button.foreground : Color.foreground
          }
        }
      }
    }
    tooltipText: ""
    onPressed: function (b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }

  // a finger pulls the battery menu down from the top edge above this item (tablet mode, cast screen)
  VPullZone { surface: "battery"; item: button; island: panel; opened: root.opened; onCommit: root.open() }

  // ================================================================= popup
  // A Dynamic Island: the right island of the bar grows into the battery menu (keeps its
  // right and top edge), as the Control Center grows out of the centre one.
  VIslandWindow {
    id: panel
    anchorItem: button
    bar: root.bar
    namespace: "velum-surface"   // Hyprland: blur with ignore_alpha 0.6 (only the material, never the shadow), no layer animation
    align: "right"
    open: root.opened && root.batteryPresent
    toWidth: Theme.layout.module.width
    contentHeight: content.height
    onDismissed: root.close()
    onReopenRequested: root.open()
    onEscapePressed: root.goBack()
    // every open starts on the overview: back to it once the island has shrunk
    onShownChanged: if (!shown) { if (root.pages) root.pages.rangeOpen = false; stack.reset(); root.names = [] }

    Item {
      id: content
      width: Theme.layout.module.width - 2 * panel.pad
      height: stack.implicitHeight
      VPageStack {
        id: stack
        width: parent.width
        initial: root.pages ? root.pages.page("battery") : null
      }
      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        z: -1
        // overview: ↑ History; ← back; Esc back one page, closes on the overview
        onMoveRequested: function (dx, dy) {
          if (root.current === "battery") { if (dy < 0) root.push("battery-history") }
          else if (dx < 0) root.goBack()
        }
        onCloseRequested: root.goBack()
        onTabRequested: function (direction) { root.switchPanel(direction) }
      }
    }
  }
  // the key catcher takes the keys once the popup holds the keyboard
  Timer { id: focusLater; interval: Theme.dur("fast"); onTriggered: if (root.opened) keyCatcher.forceActiveFocus() }
}
