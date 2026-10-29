import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "file:///home/henri/.local/share/velum/qml/Velum"

// Control Center v3 — the island in the middle of the bar (Velum). Compact it
// shows the workspace dots (scroll switches workspace) or a running activity
// (joining a network, connecting a device), and the Control Center symbol left
// of them. A click grows the island itself into the Control Center (VIslandWindow),
// which keeps the island's top edge: on the symbol the Control Center, on the dots
// only the workspace miniatures.
// Backend from v2 (Backend.qml), pages in Pages.qml.
BarWidget {
  id: root
  moduleName: "henri.control-center-v3"
  readonly property var shell: bar ? bar.shell : null

  // ---- Velum: settings file + appearance from the wallpaper under the island
  VBackdrop { id: backdrop; region: "40%x30%+0+0"; gravity: "North" }
  VelumSettings { id: velum; priority: 1; prefersDark: backdrop.dark }

  Backend {
    id: be
    shell: root.shell
    opened: island.open
    onCloseRequested: island.open = false
  }

  // ---- workspaces (as henri.workspaces: 1…5 always, more when used)
  readonly property int focusedWs: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  readonly property var wsIds: {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0 || id > 10 || ids.indexOf(id) !== -1) continue
      if (values[i].toplevels.values.length > 0 || id === focusedWs) ids.push(id)
    }
    ids.sort(function (a, b) { return a - b })
    return ids
  }
  function wsUsed(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) if (values[i].id === id) return values[i].toplevels.values.length > 0
    return false
  }
  function focusWs(id) { if (bar) bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })")) }

  // ---- what the compact island says
  readonly property string activity: {
    if (be.wifiPending !== "") return "Joining " + be.wifiPending
    for (var a in be.btPending) {
      var rows = be.btRows
      for (var i = 0; i < rows.length; i++) if (rows[i].address === a) return (be.btPending[a].indexOf("Dis") === 0 ? "Disconnecting " : "Connecting ") + rows[i].name
    }
    return ""
  }
  property bool hover: false
  readonly property real pillH: Math.max(Theme.layout.capsule.height, barSize - 2 * Theme.layout.module.tileInset - 2 * Theme.layout.separator)
  // the widget keeps the hovered width at all times: the pill grows inside it, so the bar never
  // re-centres it under the pointer (that moved it away, hover flickered and clicks were lost)
  readonly property real faceW: activity ? activityFace.implicitWidth : dots.implicitWidth
  readonly property real iconSize: Theme.layout.icon.small
  readonly property real restW: faceW + Theme.layout.list.gap + iconSize + 2 * Theme.layout.capsule.padX
  // clicks left of this (widget x) are on the symbol, right of it on the dots
  readonly property real splitX: width / 2 + (iconSize - faceW) / 2
  readonly property var smoke: Theme.core.surface.menubar
  // the variant may wear its own glass instead of Smoke (metrics.chrome.smoke 0: Opal), as the bar does
  readonly property bool smoky: !!Theme.m.chrome.smoke
  readonly property color ink: Theme.reduceTransparency || !smoky ? Theme.r.popover.ink : smoke.ink
  readonly property color inkSecondary: Theme.reduceTransparency || !smoky ? Theme.r.popover.inkSecondary : smoke.inkSecondary
  readonly property color inkTertiary: Theme.reduceTransparency || !smoky ? Theme.r.ink.tertiary : smoke.inkTertiary
  readonly property real pillW: restW + (hover ? Theme.layout.module.pad : 0)
  implicitWidth: restW + 2 * Theme.layout.module.pad
  implicitHeight: barSize
  Spring { id: pw; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: root.pillW }

  Rectangle {
    id: pill
    // whole pixels, the same as islandRect(): the surface takes over exactly where the pill is
    x: Math.round((root.width - width) / 2); y: Math.round((root.height - height) / 2)
    width: pw.value; height: root.pillH; radius: height / 2
    // at rest the island wears the menu bar's Smoke (surface.menubar); opened it grows into the
    // Control Center's own material
    color: Theme.reduceTransparency ? Theme.r.popover.bgOpaque : root.smoky ? root.smoke.tint : Theme.r.popover.bg
    border.width: Theme.layout.separator; border.color: Theme.reduceTransparency || !root.smoky ? Theme.r.line.rim : root.smoke.rim
    opacity: island.shown ? 0 : 1
    VLens { layers: Theme.r.popover.shadow; radius: pill.radius }
    Face { anchors.fill: parent }
  }
  // hover and clicks on the widget's fixed box, never on the growing pill
  MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: root.hover = containsMouse
      onClicked: function (m) { root.toggle(m.x >= root.splitX) }
      onWheel: function (w) {
        var i = root.wsIds.indexOf(root.focusedWs), n = i + (w.angleDelta.y < 0 ? 1 : -1)
        if (i >= 0 && n >= 0 && n < root.wsIds.length) root.focusWs(root.wsIds[n])
      }
  }

  // the compact face, drawn by the bar's island and by the surface while it starts to grow
  component Face: Item {
    Row {
      anchors.centerIn: parent
      spacing: Theme.layout.list.gap
      VIcon { anchors.verticalCenter: parent.verticalCenter; name: "control-center"; size: root.iconSize; surface: "popover"; color: root.ink }
      Item {
        width: root.faceW; height: root.pillH
        Row {
          id: dotsRow
          anchors.centerIn: parent
          spacing: Theme.layout.list.gap / 2 + Theme.layout.separator
          opacity: root.activity ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: Theme.dur("fast") } }
          Repeater {
            model: root.wsIds
            Rectangle {
              required property int modelData
              readonly property bool current: modelData === root.focusedWs
              width: current ? Theme.layout.capsule.padX + Theme.layout.list.gap / 2 : Theme.layout.list.gap - Theme.layout.separator
              height: Theme.layout.list.gap - Theme.layout.separator
              radius: height / 2
              anchors.verticalCenter: parent.verticalCenter
              color: current ? Theme.r.accent.base : root.wsUsed(modelData) ? root.inkSecondary : root.inkTertiary
              Behavior on width { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
            }
          }
        }
        Row {
          anchors.centerIn: parent
          spacing: Theme.layout.list.gap
          opacity: root.activity ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: Theme.dur("fast") } }
          VSpinner { anchors.verticalCenter: parent.verticalCenter; visible: root.activity !== ""; color: root.inkSecondary }
          VText { anchors.verticalCenter: parent.verticalCenter; text: root.activity; color: root.ink; font.weight: Font.Medium; font.pixelSize: Theme.m.type.small }
        }
      }
    }
  }
  // widths of the faces (measured once, outside the pill)
  Row { id: dots; visible: false; spacing: Theme.layout.list.gap / 2 + Theme.layout.separator
    Repeater { model: root.wsIds; Item { required property int modelData; width: modelData === root.focusedWs ? Theme.layout.capsule.padX + Theme.layout.list.gap / 2 : Theme.layout.list.gap - Theme.layout.separator; height: 1 } } }
  Row { id: activityFace; visible: false; spacing: Theme.layout.list.gap
    VSpinner {} VText { text: root.activity; font.weight: Font.Medium; font.pixelSize: Theme.m.type.small } }

  // ---- open / close
  // where the island rests, from the widget's fixed box (never the pill mid-spring)
  function islandRect(w) {
    var win = root.QsWindow.window
    if (!win) return Qt.rect(0, 0, 0, 0)
    var p = win.itemPosition(root), pw = w === undefined ? root.restW : w
    return Qt.rect(p.x + Math.round((root.width - pw) / 2), p.y + Math.round((root.height - root.pillH) / 2), pw, root.pillH)
  }
  // spaces: only the workspace miniatures (only when the island is not up yet)
  function open(pageName, spaces) {
    if (!island.shown) pages.spaces = spaces === true
    island.from = islandRect(pw.value)
    island.open = true
    if (pageName) pages.show(pageName)
  }
  function close() { island.from = islandRect(); island.open = false }
  function toggle(spaces) { if (island.open) close(); else open("", spaces) }
  // Tablet mode: a finger pulls the island open from the top edge (henri.bar-v3 → VGestures);
  // the island grows with it and, let go, opens or shrinks back. "spaces" (a cast screen's top
  // edge, henri.tablet-v3) pulls only the workspace miniatures.
  Connections {
    target: VGestures
    function onPull(surface, screenName, phase, travel, velocity) {
      if (surface !== "controlCenter" && surface !== "spaces") return
      var w = root.QsWindow.window
      if (!w || !w.screen || w.screen.name !== screenName) return
      var dist = Theme.core.surface.tablet.pullTravel
      if (phase === "move") {
        if (island.open) return
        if (!island.pulling) { island.from = root.islandRect(pw.value); if (!island.shown) pages.spaces = surface === "spaces" }
        island.pull = Math.max(0, travel) / dist
        return
      }
      if (!island.pulling) return
      if (phase === "end" && VGestures.commits(travel, dist, velocity)) { pages.skipReveal = island.contentShown; island.open = true }
      island.pull = -1
    }
  }
  onRestWChanged: { if (!island.shown) Qt.callLater(function () { if (!island.shown) island.from = root.islandRect() }); Qt.callLater(root.publishIsland) }
  // the rest rect, for Mission Control's Spaces island (it grows out of this pill)
  function publishIsland() {
    var win = root.QsWindow.window
    if (!win || !win.screen) return
    var r = islandRect(), all = Object.assign({}, Theme.centreIslands)
    all[win.screen.name] = { x: r.x, y: r.y, width: r.width, height: r.height }
    Theme.centreIslands = all
    // a pull from the top edge: above the symbol the pages, above the dots only the miniatures,
    // split where a click splits them (VGestures.zoneAt; tablet mode and a cast screen)
    var p = win.itemPosition(root)
    VGestures.setZone("controlCenter", win.screen.name, p.x, p.x + root.splitX)
    VGestures.setZone("spaces", win.screen.name, p.x + root.splitX, p.x + root.width)
  }
  // the bar moves the widget without telling it (a neighbour grows): look again now and then
  Timer { interval: Theme.delay("hudHold"); running: true; repeat: true; onTriggered: root.publishIsland() }
  Component.onCompleted: Qt.callLater(root.publishIsland)
  onWidthChanged: Qt.callLater(root.publishIsland)
  onXChanged: Qt.callLater(root.publishIsland)

  VIslandWindow {
    id: island
    screen: pill.QsWindow.window ? pill.QsWindow.window.screen : null
    anchorItem: pill
    bar: root.bar
    namespace: "velum-surface"   // Hyprland: blur with ignore_alpha 0.6 (only the material, never the shadow), no layer animation
    // a detail page too tall for one column takes two side by side (when the screen has the room)
    readonly property real columnWidth: Theme.layout.module.island - 2 * pad
    readonly property real wideWidth: 2 * columnWidth + Theme.layout.module.gap + 2 * pad
    toWidth: pages.wide && wideWidth <= screenW - 2 * margin ? wideWidth : Theme.layout.module.island
    contentHeight: pages.implicitHeight
    face: Component { Face {} }
    onDismissed: root.close()
    onReopenRequested: root.open()
    onEscapePressed: if (!pages.back()) root.close()
    onShownChanged: if (!shown) pages.reset()
    Pages { id: pages; be: be; velum: velum; width: parent.width; maxHeight: island.maxContentHeight; columnWidth: island.columnWidth; onCloseRequested: root.close() }
  }

  IpcHandler {
    target: "henri.control-center-v3"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    // only the workspace miniatures, as a click on the dots
    function spaces(): void { root.open("", true) }
    function toggleSpaces(): void { root.toggle(true) }
    // wifi | wifi-advanced | bluetooth | sound | airpods | display | focus | keyboard | battery | hardware | experiments
    function page(name: string): void { root.open(name) }
    function togglePage(name: string): void { if (island.open && pages.current === name) root.close(); else root.open(name) }
    function back(): void { pages.back() }
    function state(): string { return JSON.stringify({ open: island.open, shown: island.shown, page: pages.current, spaces: pages.spaces, from: island.from, variant: Theme.variant, dark: Theme.dark, sf: Theme.sfAvailable, height: pages.implicitHeight, maxHeight: island.maxContentHeight, screenH: island.screenH, wide: pages.wide, width: island.toWidth }) }
    function set(key: string, value: string): void { velum.set(key, value === "true" ? true : value === "false" ? false : value) }
  }
}
