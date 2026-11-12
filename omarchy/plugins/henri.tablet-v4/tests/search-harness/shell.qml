import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "file:///home/henri/.local/share/velum/qml/Velum"

// A standalone harness for SearchView.qml and AppDrawer.qml (tests/search-rig.sh stages it beside
// copies of the components and starts it in its own nested Hyprland). A stand-in home screen —
// the wallpaper, a few icons, a Material search bar — is the backdrop both blur. Apps come from
// DesktopEntries; launching is only recorded. IPC target "search-harness".
ShellRoot {
  id: root

  // Roboto as the plugin registers it (Home.qml's FontLoaders; search-rig.sh stages fonts/ beside this)
  FontLoader { source: Qt.resolvedUrl("fonts/Roboto-Regular.ttf") }
  FontLoader { source: Qt.resolvedUrl("fonts/Roboto-Medium.ttf") }

  // ---- apps (the shape the home hands over)
  property var apps: []
  readonly property var hiddenIds: ["foot-server", "org.codeberg.dnkl.foot-server", "footclient"]
  function iconOf(value) {
    value = String(value || "")
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return "file://" + value
    return (value ? Quickshell.iconPath(value, true) : "") || Quickshell.iconPath("application-x-executable", true)
  }
  function scanApps() {
    var values = []
    try { values = DesktopEntries.applications.values || [] } catch (e) {}
    var seen = {}, list = []
    for (var i = 0; i < values.length; i++) {
      var e = values[i]
      if (!e || e.noDisplay) continue
      var id = String(e.id || "").replace(/\.desktop$/, "")
      if (!id || seen[id]) continue
      seen[id] = true
      var cats = [], acts = []
      try { cats = (e.categories || []).map(String) } catch (err) {}
      try { acts = (e.actions || []).map(function (a) { return { id: String(a.id || ""), name: String(a.name || a.id || ""), command: (a.command || []).map(String) } }) } catch (err) {}
      list.push({ id: id, name: String(e.name || id), icon: iconOf(e.icon), cats: cats, actions: acts, launcherHidden: hiddenIds.indexOf(id) >= 0 })
    }
    apps = list
  }
  Connections { target: DesktopEntries.applications; function onValuesChanged() { root.scanApps() } }
  Component.onCompleted: scanApps()
  readonly property var homeOrder: apps.slice(0, Theme.core.surface.material.search.columns * 2).map(function (a) { return a.id })
  property var events: []
  function note(s) { var l = events.slice(-19); l.push(s); events = l }

  PanelWindow {
    id: win
    screen: {
      var want = Quickshell.env("HARNESS_OUTPUT") || ""
      var list = Quickshell.screens
      for (var i = 0; i < list.length; i++) if (list[i].name === want) return list[i]
      return list[0]
    }
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: Theme.r.bg.window
    WlrLayershell.namespace: "velum-v4-search-harness"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Item {
      id: stage
      anchors.fill: parent
      focus: true
      Keys.onPressed: function (ev) {
        if (search.shown || drawer.active) return
        if (ev.text && ev.text.length === 1 && ev.text !== " " && !(ev.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
          search.open(ev.text, home.barRect)
          ev.accepted = true
        }
      }

      // ---- the stand-in home screen (the backdrop)
      Item {
        id: home
        anchors.fill: parent
        readonly property var cfg: Theme.core.surface.material.search
        readonly property rect barRect: Qt.rect(bar.x, bar.y, bar.width, bar.height)
        Image {
          anchors.fill: parent
          source: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
          fillMode: Image.PreserveAspectCrop
          sourceSize.width: width
          sourceSize.height: height
          asynchronous: true
        }
        Grid {
          id: homeGrid
          x: home.cfg.edge
          y: home.cfg.edge * 2
          columns: home.cfg.columns
          readonly property real cell: (home.width - 2 * home.cfg.edge) / columns
          Repeater {
            model: root.homeOrder
            delegate: Item {
              required property var modelData
              readonly property var app: root.apps.find(function (a) { return a.id === modelData })
              width: homeGrid.cell
              height: homeGrid.cell * Theme.core.surface.material.drawer.travel
              Image {
                anchors.centerIn: parent
                width: Theme.core.surface.material.drawer.icon
                height: width
                sourceSize.width: width; sourceSize.height: height
                source: parent.app ? parent.app.icon : ""
              }
            }
          }
        }
        // the Material search bar the view grows out of
        Rectangle {
          id: bar
          width: Math.min(home.width - 2 * home.cfg.edge, home.cfg.maxWidth)
          height: home.cfg.barHeight
          radius: height / 2
          x: (home.width - width) / 2
          y: home.height - home.cfg.edge - height
          color: Theme.r.popover.bgOpaque
          Text {
            x: home.cfg.pad * 2
            anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.iconFamily("bold")
            font.pixelSize: home.cfg.glyph
            text: Theme.glyph("magnifying-glass", "bold")
            color: Theme.r.popover.inkSecondary
          }
          Text {
            x: home.cfg.pad * 2 + home.cfg.glyph + home.cfg.pad * 2
            anchors.verticalCenter: parent.verticalCenter
            text: "Search"
            font.pixelSize: home.cfg.inputSize
            color: Theme.r.popover.inkSecondary
          }
          TapHandler { onTapped: search.open("", home.barRect) }
        }
        // a swipe up on the home screen brings the drawer (the owner's finger)
        MouseArea {
          anchors.fill: parent
          z: -1
          property real y0: 0
          property var samples: []
          onPressed: function (m) { y0 = m.y; samples = [[Date.now(), m.y]] }
          onPositionChanged: function (m) {
            var now = Date.now(); var s = samples.filter(function (t) { return now - t[0] <= Theme.core.surface.material.drawer.sampleWindow * 2 }); s.push([now, m.y]); samples = s
            if (!drawer.dragging && y0 - m.y < Theme.core.surface.material.drawer.slop) return
            if (!drawer.dragging) drawer.dragging = true
            drawer.progress = Math.max(0, Math.min(1, (y0 - m.y) / (home.height * Theme.core.surface.material.drawer.travel)))
          }
          onReleased: function (m) {
            if (!drawer.dragging) return
            // velocity sampled like the drawer's own handle (SearchScore.velocity, down positive)
            var last = samples[samples.length - 1], i = samples.length - 1
            while (i > 0 && last[0] - samples[i - 1][0] <= Theme.core.surface.material.drawer.sampleWindow) i--
            var dt = last[0] - samples[i][0]
            drawer.release(dt > 0 ? -(last[1] - samples[i][1]) / dt * 1000 : 0)
          }
        }
      }

      AppDrawer {
        id: drawer
        apps: root.apps
        homeIds: root.homeOrder
        backdropSource: home
        onOpenApp: function (id) { root.note("drawer open " + id) }
        onAddToHome: function (id) { root.note("drawer add " + id) }
        onAppInfo: function (id) { root.note("drawer info " + id) }
        onClosed: root.note("drawer closed")
      }

      SearchView {
        id: search
        apps: root.apps
        suggested: root.homeOrder.slice(0, Theme.core.surface.material.search.columns)
        backdropSource: home
        onOpenApp: function (id) { root.note("search open " + id) }
        onRunAction: function (id, action) { root.note("search action " + id + " " + action.id) }
        onWebSearch: function (text) { root.note("search web " + text) }
        onVoiceSearch: root.note("search voice")
        onClosed: { root.note("search closed"); stage.forceActiveFocus() }
      }
    }
  }

  function searchSummary() {
    var r = search.results
    return { shown: search.shown, active: search.active, text: search.text, value: +search.fade.toFixed(3),
      apps: r.apps.map(function (a) { return a.id }), actions: r.actions.map(function (x) { return x.app.id + ":" + x.action.id }),
      first: r.first ? r.first.kind + ":" + (r.first.app ? r.first.app.id : r.first.text) : null, last: search.lastActivated,
      bar: root.rectJson(home.barRect), view: [search.viewX, search.viewY, search.viewW, Math.round(search.panelH)] }
  }
  function drawerSummary() {
    var m = drawer.menuOpen
    return { active: drawer.active, position: +drawer.position.toFixed(3), dragging: drawer.dragging, progress: +drawer.progress.toFixed(3),
      query: drawer.query, count: drawer.list.length, first: drawer.list.slice(0, 6).map(function (a) { return a.id }),
      menu: m, last: drawer.lastActivated }
  }
  function findChild(it, test) {
    var kids = it.children || []
    for (var i = 0; i < kids.length; i++) {
      if (test(kids[i])) return kids[i]
      var f = findChild(kids[i], test)
      if (f) return f
    }
    // a Loader's item is its child too, a Flickable's content sits under contentItem
    if (it.contentItem && kids.indexOf(it.contentItem) < 0) return findChild(it.contentItem, test)
    return null
  }
  function rectJson(r) { return [Math.round(r.x), Math.round(r.y), Math.round(r.width), Math.round(r.height)] }
  IpcHandler {
    target: "search-harness"
    function dark(on: bool): string { Theme.dark = on; return "dark " + Theme.dark }
    function variant(v: string): string { Theme.variant = v; return Theme.variant }
    function reduceMotion(on: bool): string { Theme.reduceMotion = on; return "reduceMotion " + on }
    function speed(s: real): string { Theme.speed = s; return "speed " + Theme.speed }
    function events(): string { return JSON.stringify(root.events) }
    function clearEvents(): string { root.events = []; return "ok" }
    function apps(): string { return JSON.stringify({ count: root.apps.length, hidden: root.apps.filter(function (a) { return a.launcherHidden }).map(function (a) { return a.id }), withActions: root.apps.filter(function (a) { return a.actions.length }).map(function (a) { return a.id + ":" + a.actions.map(function (x) { return x.name }).join("|") }) }) }
    // search
    function searchOpen(text: string): string { search.open(text, home.barRect); return "ok" }
    function searchType(text: string): string { search.text = text; return JSON.stringify(root.searchSummary()) }
    function searchSubmit(): string { search.submit(); return search.lastActivated }
    function searchClose(): string { search.close(); return "ok" }
    function searchState(): string { return JSON.stringify(root.searchSummary()) }
    // drawer
    function drawerOpen(): string { drawer.open(); return "ok" }
    function drawerClose(): string { drawer.close(); return "ok" }
    function drawerBack(): string { drawer.back(); return "ok" }
    function drawerDrag(p: real): string { drawer.dragging = true; drawer.progress = p; return JSON.stringify(root.drawerSummary()) }
    function drawerRelease(v: real): string { drawer.release(v); return JSON.stringify(root.drawerSummary()) }
    function drawerQuery(q: string): string { drawer.query = q; return JSON.stringify(root.drawerSummary()) }
    function drawerState(): string { return JSON.stringify(root.drawerSummary()) }
    // the n-th app result of the search view in window pixels: "X Y ID"
    function searchTile(n: int): string {
      var g = root.findChild(search, function (c) { return c.tileW !== undefined })
      if (!g || n >= search.results.apps.length) return "none"
      var x = (n % g.columns) * (g.tileW + g.columnSpacing) + g.tileW / 2
      var rows = Math.ceil(search.results.apps.length / g.columns)
      var h = (g.height - (rows - 1) * g.rowSpacing) / rows
      var y = Math.floor(n / g.columns) * (h + g.rowSpacing) + h / 2
      var p = g.mapToItem(stage, x, y)
      return Math.round(p.x) + " " + Math.round(p.y) + " " + search.results.apps[n].id
    }
    // the last row of the view (the web row while a query is typed): "X Y"
    function searchLastRow(): string {
      return Math.round(search.viewX + search.viewW / 2) + " " + Math.round(search.viewY + search.panelH - Theme.core.surface.material.search.pad - Theme.core.surface.material.search.rowOne / 2)
    }
    // the drawer menu's i-th tile: "X Y KEY"
    function menuTile(i: int): string {
      var m = root.findChild(drawer, function (c) { return c.cardX !== undefined && c.tiles !== undefined })
      if (!m || !m.shown) return "none"
      var c = Theme.core.surface.material.drawer.menu
      var w = (m.cardW - 2 * c.pad - (m.tiles.length - 1) * c.tileGap) / m.tiles.length
      return Math.round(m.cardX + c.pad + i * (w + c.tileGap) + w / 2) + " " + Math.round(m.cardY + m.cardH - c.pad - c.tile / 2) + " " + m.tiles[i].key
    }
    // the n-th cell of the drawer's grid in window pixels (for the virtual pointer)
    function drawerCell(n: int): string {
      var g = null
      function find(it) { for (var i = 0; i < it.children.length; i++) { var c = it.children[i]; if (c.cellWidth !== undefined) return c; var f = find(c); if (f) return f } return null }
      g = find(drawer)
      if (!g) return "none"
      var cols = Math.max(1, drawer.columns)
      var x = (n % cols) * g.cellWidth + g.cellWidth / 2, y = Math.floor(n / cols) * g.cellHeight + g.cellHeight / 2 - g.contentY
      var p = g.mapToItem(stage, x, y)
      return Math.round(p.x) + " " + Math.round(p.y) + " " + drawer.list[n].id
    }
  }
}
