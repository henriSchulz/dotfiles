import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import QtQuick.Shapes
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

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
    function tmpCred(name: string): void { if (panelLoader.item) { panelLoader.item.wifiIdentity = ""; panelLoader.item.wifiPasswordFor = name } }
    function tmpShake(): void { if (panelLoader.item) panelLoader.item.wifiShakeTick++ }
    // Keyboard entry: toggles the Control Center on a page (wifi, bluetooth,
    // sound, display). Pressing the same shortcut again closes it; another
    // page's shortcut switches the open popup over.
    function togglePage(name: string): void {
      var p = panelLoader.item
      if (!p) return
      var target = name === "display" ? "main" : name
      var already = p.opened && p.page === target && (name !== "display" || p.displayExpanded)
      if (already) { p.close(); return }
      p.page = target
      if (name === "display") p.displayExpanded = true
      p.open()
    }
    // Opens straight onto a detail page: wifi, wifi-advanced, bluetooth, sound or airpods.
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
    // The macOS Control Center mark (SF Symbol `switch.2`), redrawn as vectors:
    // top a filled capsule with a hollow knob on the left, bottom an outlined
    // capsule with a solid knob on the right. The knobs trade sides while the
    // Control Center is open.
    iconComponent: Component {
      Item {
        id: mark
        readonly property color ink: button.foreground
        readonly property real stroke: Math.max(1, Style.spaceReal(1.0))
        readonly property real pillW: Style.spaceReal(14)
        readonly property real pillH: Style.spaceReal(5.5)
        readonly property real pillGap: Style.spaceReal(1.6)
        readonly property real left0: Math.round((width - pillW) / 2)
        readonly property real top0: Math.round((height - pillH * 2 - pillGap) / 2)
        readonly property real travel: pillW - pillH

        // 0 = closed (top knob left, bottom knob right), 1 = open (mirrored)
        HUi.SpringValue { id: flip; to: root.opened ? 1 : 0; preset: Motion.snappy }

        Shape {
          x: mark.left0; y: mark.top0
          width: mark.pillW; height: mark.pillH
          preferredRendererType: Shape.CurveRenderer
          ShapePath {
            fillColor: mark.ink
            strokeColor: "transparent"
            fillRule: ShapePath.OddEvenFill
            PathRectangle { width: mark.pillW; height: mark.pillH; radius: mark.pillH / 2 }
            PathAngleArc {
              centerX: mark.pillH / 2 + flip.value * mark.travel
              centerY: mark.pillH / 2
              radiusX: mark.pillH / 2 - mark.stroke; radiusY: radiusX
              startAngle: 0; sweepAngle: 360
              moveToStart: true
            }
          }
        }

        Rectangle {
          x: mark.left0; y: mark.top0 + mark.pillH + mark.pillGap
          width: mark.pillW; height: mark.pillH
          radius: height / 2
          color: "transparent"
          border.width: mark.stroke
          border.color: mark.ink
          antialiasing: true
          Rectangle {
            width: parent.height; height: width
            radius: width / 2
            x: (1 - flip.value) * mark.travel
            color: mark.ink
            antialiasing: true
          }
        }
      }
    }
    // No hover tooltip (Henri) — like macOS menu-bar extras, the icon speaks for itself.
    tooltipText: ""
    onPressed: function(b) { root.togglePanel() }
  }
}
