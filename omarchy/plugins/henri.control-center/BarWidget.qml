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
    // Opens straight onto a detail page: wifi, wifi-advanced, bluetooth or sound.
    function page(name: string): void {
      if (!panelLoader.item) return
      // "wifi-advanced" opens the Wi-Fi page with its advanced options expanded.
      panelLoader.item.page = name === "wifi-advanced" ? "wifi" : name
      panelLoader.item.open()
      if (name === "wifi-advanced") panelLoader.item.wifiAdvanced = true
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The macOS Control Center mark: two stacked toggle capsules, knob left
    // on the top one and right on the bottom one. No Nerd Font glyph matches
    // it, so it is drawn.
    iconComponent: Component {
      Item {
        readonly property color ink: button.foreground
        readonly property real stroke: Math.max(1.1, Style.spaceReal(1.2))
        readonly property real pillW: Style.spaceReal(13)
        readonly property real pillH: Style.spaceReal(6)
        readonly property real pillGap: Style.spaceReal(1.8)

        Repeater {
          model: 2
          Item {
            id: capsule
            required property int index
            x: Math.round((parent.width - parent.pillW) / 2)
            y: Math.round((parent.height - parent.pillH * 2 - parent.pillGap) / 2 + index * (parent.pillH + parent.pillGap))
            width: parent.pillW
            height: parent.pillH

            Rectangle {
              anchors.fill: parent
              radius: height / 2
              color: "transparent"
              border.width: parent.parent.stroke
              border.color: parent.parent.ink
              antialiasing: true
            }
            Rectangle {
              readonly property real inset: 0
              width: parent.height - inset * 2
              height: width
              radius: width / 2
              y: inset
              // The knobs trade sides while the Control Center is open.
              x: (capsule.index === 0) !== root.opened ? inset : parent.width - width - inset
              color: parent.parent.ink
              antialiasing: true
              Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }
            }
          }
        }
      }
    }
    tooltipText: root.opened ? "" : "Kontrollzentrum"
    onPressed: function(b) { root.togglePanel() }
  }
}
