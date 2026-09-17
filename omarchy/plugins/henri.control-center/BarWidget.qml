import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar button for the Control Center. Like henri.clock, the widget in the bar
// slot is the popout identity; Panel.qml is loaded beside it and anchored to
// the button.
BarWidget {
  id: root
  moduleName: "henri.control-center"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property real openPanelIndicatorWidth: button.width * 0.55
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function openDisplay() {
    if (!panelLoader.item) return
    panelLoader.item.displayExpanded = true
    panelLoader.item.open()
  }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    injectPluginManager()
  }

  // ---- Plugin manager (omaplug), reachable only from the Control Center.
  //      omaplug is a bar widget whose popup anchors to its own bar button;
  //      it stays off the bar, so its Panel.qml is hosted here instead,
  //      anchored to the Control Center button. `pluginHost` is its popout
  //      identity, separate from ours so the bar's one-popup coordinator
  //      treats the two as different popups.
  readonly property string pluginManagerSource: Qt.resolvedUrl("../omaplug/Panel.qml")

  function injectPluginManager() {
    var target = pluginLoader.item
    if (!target) return
    target.bar = root.bar
    target.anchorItem = button
    target.hostWidget = pluginHost
  }

  function openPluginManager() {
    if (pluginLoader.item) pluginLoader.item.open()
  }

  QtObject {
    id: pluginHost
    readonly property bool opened: pluginLoader.item ? pluginLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: pluginLoader.item ? pluginLoader.item.popoutSwitchClosing === true : false
    function open() { if (pluginLoader.item) pluginLoader.item.open() }
    function close() { if (pluginLoader.item) pluginLoader.item.close() }
    function closeForPopoutSwitch() { if (pluginLoader.item) pluginLoader.item.closeForPopoutSwitch() }
  }

  Loader {
    id: pluginLoader
    active: true
    source: root.pluginManagerSource
    visible: false
    onLoaded: {
      root.injectPluginManager()
      Qt.callLater(root.injectPluginManager)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "henri.control-center"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    // Opens straight onto the expanded display settings.
    function display(): void { root.openDisplay() }
    function plugins(): void { root.openPluginManager() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰔡"
    tooltipText: root.opened ? "" : "Kontrollzentrum"
    onPressed: function(b) { root.togglePanel() }
  }
}
