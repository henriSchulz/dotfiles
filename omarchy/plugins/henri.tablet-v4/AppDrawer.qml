import QtQuick
import QtQuick.Effects
import "file:///home/henri/.local/share/velum/qml/Velum"
import "SearchScore.js" as SS

// All apps (phase 3 of docs/TABLET-V4-PLAN.md; Android's app drawer, lab/mui-material/src/AppDrawer.jsx):
// a sheet that a swipe up on the home screen brings, following the finger. Every app the launcher
// shows, A–Z, a search field on top (names containing it, categories starting with it); a tap opens
// the app, a long press shows the action menu (DrawerMenu.qml: Add to Home, App info). A swipe down on
// the handle area takes the sheet with it and closes it past the commit share or on a fling; Escape
// closes the menu, then the sheet. Glass = a downscaled, blurred copy of the screen taken once when the
// sheet starts to show (never a live blur), clipped to the sheet, under Velum's popover material.
// Per frame only the sheet's translation and opacity change. Tokens: surface.material.drawer.
//
// It launches nothing — the owner (the home) does, on the signals, and decides whether the sheet
// closes then. It fills its parent; the window must give it the keyboard while it is up.
//
// API
//   apps: same shape as SearchView's (array or map; launcherHidden left out)
//   homeIds: { id: true } or [id]   apps on the home screen (header "On the Home screen", full-ink name)
//   columns: int                    the grid's columns (the home grid's; token default 6)
//   topInset (default the status bar), bottomInset
//   backdropSource: Item            what lies under the sheet (same window, not containing it); null =
//                                   the material alone
//   progress: real 0..1, dragging: bool   the owner's finger: while dragging the sheet sits at progress
//                                   (1 = open) 1:1. ASSIGN them (no binding: the handle swipe writes them
//                                   too). End a drag with release(velocityUp px/s, upward positive):
//                                   SearchScore.settleOpen decides, the sheet springs there carrying the speed.
//   open(), close()                 settle open/closed on the spring
//   readonly position               where the sheet is shown (0..1); readonly active: on screen
//   query: string                   the search field
//   signals: openApp(id), addToHome(id), appInfo(id), closed() (after it settled at 0)
Item {
  id: drawer
  anchors.fill: parent

  property var apps: []
  property var homeIds: ({})
  property int columns: cfg.columns
  property real topInset: cfg.statusBar
  property real bottomInset: 0
  property Item backdropSource: null
  property real progress: 0
  property bool dragging: false
  property string query: ""
  readonly property real position: dragging ? clamp(progress) : clamp(settle.value)
  readonly property bool active: visible
  readonly property var list: _list
  readonly property bool menuOpen: menuLoader.item !== null && menuLoader.item.shown

  signal openApp(string id)
  signal addToHome(string id)
  signal appInfo(string id)
  signal closed()

  readonly property var cfg: Theme.core.surface.material.drawer
  property var _list: []
  property real _goal: 0
  property bool _releasing: false
  // for tests: the last thing chosen ("open:ID", "add:ID", "info:ID")
  property string lastActivated: ""

  // Roboto: the plugin's one FontLoader set (Home.qml, fonts/) registers it for the whole shell
  readonly property string family: Theme.core.surface.material.widgets.font[0]
  readonly property color ink: Theme.r.popover.ink
  readonly property color inkSecondary: Theme.r.popover.inkSecondary

  function clamp(v) { return Math.max(0, Math.min(1, v)) }
  function onHome(id) {
    if (Array.isArray(homeIds)) return homeIds.indexOf(id) >= 0
    return !!(homeIds && homeIds[id])
  }

  // ---- the sheet's position: the finger 1:1, else a Velum Spring to the goal
  Spring {
    id: settle
    preset: drawer._goal > 0 ? ({ response: drawer.cfg.openResponse * Theme.speed, dampingRatio: drawer.cfg.openDamping })
      : ({ response: drawer.cfg.openResponse * Theme.speed * Theme.core.motion.exitFactor, dampingRatio: drawer.cfg.openDamping })
    target: drawer._goal
    reduced: Theme.reduceMotion
  }
  Connections {
    target: settle
    function onMovingChanged() { if (!settle.moving) drawer._settled() }
  }
  visible: dragging || settle.value > 0 || _goal > 0
  onDraggingChanged: {
    if (dragging) { _prepare(); return }
    if (!_releasing) release(0)
  }
  onProgressChanged: if (dragging) _prepare()

  function _prepare() {
    if (_wasShown) return
    _wasShown = true
    _snapRect = backdropSource ? backdropSource.mapToItem(drawer, 0, 0, backdropSource.width, backdropSource.height) : Qt.rect(0, 0, 0, 0)
    refresh()
  }
  property bool _wasShown: false
  property rect _snapRect: Qt.rect(0, 0, 0, 0)

  function release(velocityUp) {
    var p = clamp(progress)
    var open = SS.settleOpen(p, velocityUp || 0, cfg.flick, cfg.commit)
    _releasing = true
    dragging = false
    _releasing = false
    progress = open ? 1 : 0
    _goal = progress
    settle.from(p)
    var travel = height * cfg.travel
    if (travel > 0 && !Theme.reduceMotion && settle.moving) settle.velocity = (velocityUp || 0) / travel
    if (!open) _leaving()
    else Qt.callLater(function () { if (drawer._goal > 0) field.forceActiveFocus() })
  }
  function open() {
    _prepare()
    progress = 1
    _goal = 1
    settle.from(settle.value)
    Qt.callLater(function () { if (drawer._goal > 0) field.forceActiveFocus() })
  }
  function close() {
    if (menuLoader.item) menuLoader.item.close()
    progress = 0
    _goal = 0
    if (!dragging) settle.from(settle.value)
    _leaving()
  }
  function _leaving() {
    field.focus = false
    if (!settle.moving) _settled()
  }
  function _settled() {
    if (dragging || _goal > 0 || settle.value > 0) return
    _wasShown = false
    query = ""
    if (menuLoader.item) menuLoader.item.close()
    menuLoader.active = false
    closed()
  }
  // Escape: the menu first, then the sheet
  function back() {
    if (menuOpen) menuLoader.item.close()
    else close()
  }

  // ---- the list: filtered on a change of the query or the apps, only while it is up
  function refresh() {
    if (!visible && !_wasShown) return
    _list = SS.drawer(apps, query)
  }
  onQueryChanged: { if (field.text !== query) field.text = query; refresh() }
  onAppsChanged: refresh()

  // ---- the long press: the action menu over the sheet
  function showMenu(app, item) {
    var r = item.mapToItem(drawer, 0, 0, item.width, item.height)
    menuLoader.active = true
    var m = menuLoader.item
    m.app = app
    m.anchor = r
    m.onHome = onHome(app.id)
    m.open()
  }
  function openId(id) { lastActivated = "open:" + id; openApp(id) }

  // ---- the sheet
  readonly property real offset: (1 - position) * height * cfg.travel
  Item {
    id: sheet
    property string velumSurface: "popover"
    width: drawer.width
    height: drawer.height
    y: drawer.offset
    opacity: drawer.position
    clip: true

    // the screen under it, blurred once; it stays where it is on screen while the sheet moves
    Loader {
      y: -sheet.y
      width: drawer.width
      height: drawer.height
      active: drawer.visible && drawer.backdropSource !== null && !Theme.userReduceTransparency
      sourceComponent: Item {
        ShaderEffectSource {
          id: snap
          x: drawer._snapRect.x; y: drawer._snapRect.y; width: drawer._snapRect.width; height: drawer._snapRect.height
          sourceItem: drawer.backdropSource
          live: false
          hideSource: false
          visible: false
          textureSize: Qt.size(Math.max(1, Math.round(width / Theme.core.surface.material.search.blurDownscale)), Math.max(1, Math.round(height / Theme.core.surface.material.search.blurDownscale)))
        }
        MultiEffect {
          x: snap.x; y: snap.y; width: snap.width; height: snap.height
          source: snap
          autoPaddingEnabled: false
          blurEnabled: true
          blur: 1
          blurMax: Theme.core.surface.material.search.blur
        }
      }
    }
    Rectangle {
      anchors.fill: parent
      color: Theme.userReduceTransparency ? Theme.r.popover.bgOpaque : Theme.r.popover.bg
    }

    // head: the handle (a swipe down there takes the sheet along) and the search field
    Item {
      id: head
      width: parent.width
      height: drawer.topInset + drawer.cfg.handleHeight + drawer.cfg.headGap + drawer.cfg.fieldHeight + drawer.cfg.headBottom

      MouseArea {
        id: handleDrag
        anchors.fill: parent
        preventStealing: true
        property real y0: 0
        property real p0: 1
        property bool moved: false
        property var samples: []
        function at(mouse) { return mapToItem(drawer, mouse.x, mouse.y).y }
        onPressed: function (mouse) {
          y0 = at(mouse); p0 = drawer.position; moved = false
          samples = [[Date.now(), y0]]
        }
        onPositionChanged: function (mouse) {
          var y = at(mouse)
          var now = Date.now(); var s = samples.filter(function (t) { return now - t[0] <= drawer.cfg.sampleWindow * 2 }); s.push([now, y]); samples = s
          if (!moved && Math.abs(y - y0) < drawer.cfg.slop) return
          if (!moved) { moved = true; drawer.progress = drawer.position; drawer.dragging = true }
          drawer.progress = drawer.clamp(p0 - (y - y0) / (drawer.height * drawer.cfg.travel))
        }
        onReleased: function (mouse) {
          if (!moved) return
          moved = false
          drawer.release(-SS.velocity(samples, drawer.cfg.sampleWindow))
        }
        onCanceled: if (moved) { moved = false; drawer.release(0) }
      }
      Rectangle {
        y: drawer.topInset
        anchors.horizontalCenter: parent.horizontalCenter
        width: drawer.cfg.handleWidth
        height: drawer.cfg.handleHeight
        radius: height / 2
        color: drawer.ink
        opacity: drawer.cfg.handleAlpha
      }
      Item {
        id: fieldBox
        y: drawer.topInset + drawer.cfg.handleHeight + drawer.cfg.headGap
        width: Math.max(drawer.cfg.fieldHeight, Math.min(drawer.width - 2 * drawer.cfg.edge, Theme.core.surface.material.search.maxWidth))
        height: drawer.cfg.fieldHeight
        anchors.horizontalCenter: parent.horizontalCenter
        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: drawer.ink
          opacity: drawer.cfg.fieldAlpha
        }
        // a press on the field focuses it and never drags the sheet
        MouseArea { anchors.fill: parent; onPressed: field.forceActiveFocus() }
        Text {
          id: searchGlyph
          x: drawer.cfg.fieldPadX
          anchors.verticalCenter: parent.verticalCenter
          font.family: Theme.iconFamily("bold")
          font.pixelSize: Theme.core.surface.material.search.glyph
          text: Theme.glyph("magnifying-glass", "bold")
          color: drawer.inkSecondary
        }
        TextInput {
          id: field
          x: searchGlyph.x + searchGlyph.width + drawer.cfg.fieldGap
          width: parent.width - x - drawer.cfg.fieldPadX
          anchors.verticalCenter: parent.verticalCenter
          font.family: drawer.family
          font.pixelSize: Theme.core.surface.material.search.inputSize
          color: drawer.ink
          selectionColor: Qt.alpha(Theme.r.accent.base, Theme.core.surface.material.search.firstTint)
          selectedTextColor: drawer.ink
          clip: true
          onTextEdited: drawer.query = text
          Keys.onEscapePressed: drawer.back()
          Keys.onReturnPressed: if (drawer._list.length) drawer.openId(drawer._list[0].id)
          Keys.onEnterPressed: if (drawer._list.length) drawer.openId(drawer._list[0].id)
          Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: field.text === "" && field.preeditText === ""
            text: "Search apps"
            font: field.font
            color: drawer.inkSecondary
            elide: Text.ElideRight
          }
        }
      }
    }

    // the grid, A–Z
    GridView {
      id: grid
      readonly property real cell: Math.floor((Math.min(drawer.width, drawer.cfg.maxWidth) - 2 * drawer.cfg.edge) / Math.max(1, drawer.columns))
      y: head.height
      width: cell * Math.max(1, drawer.columns)
      height: parent.height - head.height - drawer.bottomInset
      anchors.horizontalCenter: parent.horizontalCenter
      cellWidth: cell
      cellHeight: drawer.cfg.cellPadY * 2 + drawer.cfg.icon + drawer.cfg.labelGap + labelLine.implicitHeight
      bottomMargin: drawer.cfg.bottomPad
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickDeceleration: Theme.core.motion.scroll.flickDeceleration
      maximumFlickVelocity: Theme.core.motion.scroll.maximumFlickVelocity
      interactive: !drawer.dragging
      model: drawer._list
      delegate: Item {
        id: cellItem
        required property var modelData
        required property int index
        width: grid.cellWidth
        height: grid.cellHeight
        Rectangle {
          anchors.fill: parent
          radius: drawer.cfg.cellRadius
          color: drawer.ink
          opacity: press.pressed ? Theme.core.alpha.pressed : 0
          Behavior on opacity { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
        }
        Image {
          y: drawer.cfg.cellPadY
          anchors.horizontalCenter: parent.horizontalCenter
          width: drawer.cfg.icon; height: drawer.cfg.icon
          sourceSize.width: drawer.cfg.icon; sourceSize.height: drawer.cfg.icon
          source: cellItem.modelData.icon || ""
          asynchronous: true
          smooth: true
        }
        Text {
          y: drawer.cfg.cellPadY + drawer.cfg.icon + drawer.cfg.labelGap
          x: drawer.cfg.labelPadX
          width: parent.width - 2 * drawer.cfg.labelPadX
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          text: cellItem.modelData.name
          font.family: drawer.family
          font.pixelSize: drawer.cfg.labelSize
          color: drawer.ink
          opacity: drawer.onHome(cellItem.modelData.id) ? 1 : drawer.cfg.offHome
        }
        MouseArea {
          id: press
          anchors.fill: parent
          pressAndHoldInterval: drawer.cfg.longPress
          // a click after a long press is never sent (pressAndHold is handled); the menu's own guard too
          onClicked: if (!drawer.menuOpen) drawer.openId(cellItem.modelData.id)
          onPressAndHold: drawer.showMenu(cellItem.modelData, cellItem)
        }
      }
      Text {
        id: labelLine
        visible: false
        text: "Ag"
        font.family: drawer.family
        font.pixelSize: drawer.cfg.labelSize
      }
    }
    Text {
      visible: drawer._list.length === 0 && drawer.query !== ""
      y: head.height
      width: parent.width
      topPadding: drawer.cfg.emptyPadY
      horizontalAlignment: Text.AlignHCenter
      text: "No apps match."
      font.family: drawer.family
      font.pixelSize: Theme.core.surface.material.search.inputSize
      color: drawer.inkSecondary
    }
  }

  // ---- the menu, only while a long press made one
  Loader {
    id: menuLoader
    anchors.fill: parent
    active: false
    sourceComponent: DrawerMenu {
      family: drawer.family
      onChosen: function (key) {
        var id = app ? app.id : ""
        if (!id) return
        if (key === "add") { drawer.lastActivated = "add:" + id; drawer.addToHome(id) }
        else if (key === "info") { drawer.lastActivated = "info:" + id; drawer.appInfo(id) }
      }
    }
  }
}
