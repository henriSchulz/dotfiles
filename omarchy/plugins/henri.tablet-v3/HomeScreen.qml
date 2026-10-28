import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import "file:///home/henri/.local/share/velum/qml/Velum"
import "HomeModel.js" as HM

// The home screen of tablet mode (Home.qml): pages of app icons, the page dots and the dock on
// Velum's popover material. Drawn twice with the same values — on the bottom layer of an empty
// workspace (interactive) and behind the cards of the home gesture — so one hands over to the
// other unseen. Only the interactive one takes fingers; it reports them, Home.qml decides.
Item {
  id: hs

  property var cfg: Theme.core.surface.tablet.home
  property var apps: []          // grid tiles: [{ id, name, icon }] or a folder [{ id: "folder:…", name, folder: true, items: [apps] }]
  property var dockApps: []      // pinned
  property var recentApps: []    // running, not pinned (right of the divider)
  property real pageX: 0
  property int page: 0
  property bool interactive: false
  property string pressedId: ""
  property real gridOpacity: 1     // the pages and dots (the home gesture shows only the dock at first)
  property real gridScale: 1
  property real dockShift: 0       // the dock below its place by this much
  // the wallpaper as the compositor draws it, in this item's coordinates (the dock's glass blurs it)
  property string wallSource: ""
  property rect wallRect: Qt.rect(0, 0, width, height)
  property var running: ({})       // app id → true: a dot under its dock icon
  readonly property var dk: cfg.dock
  // edit mode (iPadOS: touch and hold): `order` places the grid apps (ids), `apps` stays as it is,
  // so a new order only moves tiles and never rebuilds them
  property var order: apps.map(function (a) { return a.id })
  property bool editing: false
  readonly property var ed: cfg.edit
  property string dragId: ""       // the icon under the finger in edit mode
  property real dragX: 0           // its top left corner, in this item's coordinates
  property real dragY: 0
  property int dropIndex: -1       // where it would land
  readonly property var shown: dragId && dropIndex >= 0 ? HM.moveTo(order, dragId, dropIndex) : order
  // folders: the open one (its id, from Home.qml), the icon a held one would make a folder with
  readonly property var fc: cfg.folder
  property string openFolder: ""
  property string mergeAim: ""     // under the held icon's centre, waiting for mergeDwell
  property string mergeId: ""      // armed: a drop makes or fills a folder
  readonly property var openTile: { for (var i = 0; i < apps.length; i++) if (apps[i].id === openFolder) return apps[i]; return null }

  signal tapped(string id)
  signal pageMoved(real x, real t)
  signal pageReleased(real velocity)
  signal editRequested(bool on)      // touch and hold an icon / Done or a tap on an empty spot
  signal reordered(var ids)          // a dropped icon: the grid's new order
  signal turnPage(int dir)           // a held icon rests at a side
  signal folded(string id, string target)   // a held icon dropped on an armed icon or folder
  signal unfolded(string id)         // an app dragged out of the open folder (edit mode)
  signal folderRequested(string id)  // open ("folder:…") or close ("") a folder

  function slotOf(id) { var i = hs.shown.indexOf(id); return i < 0 ? 0 : i }
  // cells: a widget spans several, icons flow around it (HM.place)
  readonly property var wc: cfg.widget
  function spanOf(id) { return HM.isWidget(id) ? [hs.wc.cols, hs.wc.rows] : [1, 1] }
  readonly property var cells: HM.place(shown, spanOf, g.cols, g.rows)
  function slotX(i) { var e = hs.cells[i]; return e ? e.page * hs.width + hs.g.side + e.col * hs.cellW : 0 }
  function slotY(i) { var e = hs.cells[i]; return e ? hs.g.top + e.row * hs.cellH : 0 }

  readonly property var g: HM.grid(width, height, cfg)
  readonly property int pages: HM.pageCount(HM.place(order, spanOf, g.cols, g.rows))
  readonly property real cellW: (width - 2 * g.side) / g.cols
  readonly property real cellH: (height - g.top - g.bottom) / g.rows
  readonly property var lp: Theme.core.surface.launchpad

  // where an app's icon sits once the home screen has settled, in `item`'s coordinates (the dock
  // first, then the page on screen) — not where it is mid-animation: the grid may still be zoomed
  // and the dock still sliding in
  function iconRect(id, item) {
    // in the open folder: its icon there (the dock is faded out under it)
    if (hs.openFolder) {
      for (var f = 0; f < folderGrid.count; f++) {
        var fi = folderGrid.itemAt(f)
        if (!fi || fi.appId !== id) continue
        var fp = fi.icon.mapToItem(item, 0, 0), fs = VIconMetrics.scale(fi.icon.source) * folderPanel.scale, fw = fi.icon.width * fs
        return { x: fp.x + (fi.icon.width * folderPanel.scale - fw) / 2, y: fp.y + (fi.icon.width * folderPanel.scale - fw) / 2, w: fw }
      }
    }
    for (var i = 0; !hs.openFolder && i < dockRow.children.length; i++) {
      var d = dockRow.children[i]
      if (d.appId === id) {
        var p = d.mapToItem(item, 0, 0), ds = VIconMetrics.scale(d.modelData.icon), dw = d.width * ds
        return { x: p.x + (d.width - dw) / 2, y: p.y - hs.dockShift + (d.width - dw) / 2, w: dw }
      }
    }
    for (var j = 0; j < grid.count; j++) {
      var t = grid.itemAt(j)
      // an app in a closed folder: the folder's tile (iPadOS flies back into the folder)
      if (t && (t.appId === id || t.holds(id)) && t.pageOf === hs.page) {
        var q = hs.mapToItem(item, -hs.page * hs.width + t.x + t.icon.x, t.y + t.icon.y)
        var tw = t.icon.width * t.body
        return { x: q.x + (t.icon.width - tw) / 2, y: q.y + (t.icon.width - tw) / 2, w: tw }
      }
    }
    return null
  }

  // ---- pages
  Item {
    id: track
    x: hs.pageX
    opacity: hs.gridOpacity * (1 - Math.min(1, hs.fv))
    visible: opacity > 0.002
    scale: hs.gridScale
    transformOrigin: Item.Center
    width: hs.width * hs.pages
    height: hs.height
    Repeater {
      id: grid
      model: hs.apps
      Item {
        id: tile
        required property var modelData
        required property int index
        readonly property string appId: modelData.id
        readonly property int slot: hs.slotOf(appId)
        readonly property int pageOf: hs.cells[slot] ? hs.cells[slot].page : 0
        readonly property bool isWidget: !!modelData.widget
        readonly property var span: hs.spanOf(appId)
        readonly property bool held: hs.dragId === appId
        readonly property bool isFolder: !!modelData.folder
        function holds(id) { return isFolder && modelData.items.some(function (a) { return a.id === id }) }
        // the visible body's share of the icon box: a measured icon's scale, a folder's plate
        readonly property real body: isFolder ? Theme.core.surface.appIcon.content : isWidget ? 1 : VIconMetrics.scale(img.source)
        property alias icon: img
        // its slot on a spring while the order changes under a held icon; the held one is the finger's
        Spring { id: sx; reduced: Theme.reduceMotion; preset: Theme.spring("snappy"); target: hs.slotX(tile.slot) }
        Spring { id: sy; reduced: Theme.reduceMotion; preset: Theme.spring("snappy"); target: hs.slotY(tile.slot) }
        Spring { id: lift; reduced: Theme.reduceMotion; preset: Theme.spring("snappy"); target: tile.held ? Theme.scale("lift") : 1 }
        // lands from where the finger let go
        onHeldChanged: if (!held) { sx.from(hs.dragX - hs.pageX); sy.from(hs.dragY) }
        Component.onCompleted: { sx.snap(sx.target); sy.snap(sy.target) }
        x: held ? hs.dragX - hs.pageX : sx.value
        y: held ? hs.dragY : sy.value
        z: held ? 2 : (sx.moving || sy.moving ? 1 : 0)
        width: hs.cellW * span[0]
        height: hs.cellH * span[1]
        scale: lift.value
        // the jiggle: every icon swings, neighbours the other way round (iPadOS)
        property real wobble: 0
        rotation: wobble * hs.ed.jiggleAngle * (index % 2 ? 1 : -1)
        SequentialAnimation on wobble {
          running: hs.editing && !tile.held && !Theme.reduceMotion
          loops: Animation.Infinite
          NumberAnimation { to: 1; duration: Theme.ambient("jiggle") / 2; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") }
          NumberAnimation { to: -1; duration: Theme.ambient("jiggle") / 2; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") }
          onRunningChanged: if (!running) tile.wobble = 0
        }
        Item {
          id: img
          readonly property string source: tile.isFolder || tile.isWidget ? "" : tile.modelData.icon
          anchors.horizontalCenter: parent.horizontalCenter
          y: (parent.height - height - hs.cfg.labelGap - name.height) / 2
          // a widget reaches from its first icon's top edge to its last one's bottom edge, square
          // (iPadOS), centred over its columns
          width: tile.isWidget ? height : hs.g.icon
          height: hs.g.icon + (tile.span[1] - 1) * hs.cellH
          scale: hs.pressedId === tile.appId && !hs.editing ? hs.cfg.pressScale : 1
          opacity: hs.pressedId === tile.appId && !hs.editing ? hs.lp.press : 1
          // armed as a folder target: a plate grows behind the icon (or the folder's own grows)
          Spring { id: aim; reduced: Theme.reduceMotion; preset: Theme.spring("snappy"); target: hs.mergeId === tile.appId ? 1 : 0 }
          PhotoWidget {
            anchors.fill: parent
            visible: tile.isWidget
            cfg: hs.wc
            radius: hs.g.icon * hs.cfg.iconRadius
          }
          FolderPlate {
            anchors.centerIn: parent
            size: img.width * Theme.core.surface.appIcon.content
            visible: tile.isFolder || aim.value > 0.01
            opacity: tile.isFolder ? 1 : Math.min(1, aim.value)
            scale: 1 + (hs.fc.mergeScale - 1) * aim.value
            apps: tile.isFolder ? HM.miniApps(tile.modelData.items, hs.fc.miniCols) : []
            cfg: hs.fc
            iconRadius: hs.cfg.iconRadius
            wallSource: tile.isFolder ? hs.wallSource : ""
            wallRect: hs.wallRect
            blurMax: hs.dk.blurMax
            saturation: hs.dk.saturation
            // where the plate sits on the home screen (jiggle and lift left out: too small to see)
            origin: Qt.point(hs.pageX + tile.x + img.x + (img.width - width) / 2, tile.y + img.y + (img.height - height) / 2)
          }
          Image {
            visible: !tile.isFolder && !tile.isWidget
            anchors.fill: parent
            source: img.source
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            asynchronous: true
            scale: VIconMetrics.scale(source) * (1 - (1 - 1 / hs.fc.mergeScale) * aim.value)
          }
        }
        VText {
          id: name
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.top: img.bottom
          anchors.topMargin: hs.cfg.labelGap
          width: Math.min(implicitWidth, hs.cellW - hs.cfg.labelGap)
          horizontalAlignment: Text.AlignHCenter
          text: tile.modelData.name
          font.pixelSize: Theme.m.type.small
          font.weight: Font.Medium
          color: hs.lp.label
          style: Text.Raised
          styleColor: hs.cfg.labelShade
        }
      }
    }
  }

  // ---- page dots
  Row {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: dock.top
    anchors.bottomMargin: hs.cfg.dotsAbove
    spacing: hs.cfg.dot + hs.cfg.labelGap
    visible: hs.pages > 1 && hs.gridOpacity > 0.002
    opacity: hs.gridOpacity * (1 - Math.min(1, hs.fv))
    Repeater {
      model: hs.pages
      Rectangle {
        required property int index
        width: hs.cfg.dot
        height: width
        radius: width / 2
        color: index === hs.page ? hs.lp.dotActive : hs.lp.dot
      }
    }
  }

  // ---- the dock: pinned apps, a divider, recent ones
  Item {
    id: dock
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: hs.g.dockGap - hs.dockShift
    width: dockRow.width + 2 * hs.g.dockPad
    height: hs.g.dockH
    opacity: 1 - Math.min(1, hs.fv)
    visible: opacity > 0.002
    readonly property real radius: hs.g.dockIcon * hs.cfg.iconRadius + hs.g.dockPad
    // design 3 "Smoke" (lab/web/dock.html): dark tinted glass over the blurred wallpaper, a light
    // hairline. The blur is a small copy of the wallpaper blurred into a cached layer: free per frame
    VShadow { layers: hs.dk.shadow; radius: dock.radius }
    Item {
      anchors.fill: parent
      layer.enabled: true
      layer.effect: MultiEffect { maskEnabled: true; maskSource: dockMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
      Image {
        id: dockWall
        x: hs.wallRect.x - dock.x
        y: hs.wallRect.y - dock.y
        width: hs.wallRect.width
        height: hs.wallRect.height
        source: hs.wallSource
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: hs.wallRect.width / hs.cfg.blurDownscale
        sourceSize.height: hs.wallRect.height / hs.cfg.blurDownscale
        visible: false
        cache: true
      }
      MultiEffect {
        x: dockWall.x; y: dockWall.y; width: dockWall.width; height: dockWall.height
        source: dockWall
        visible: !Theme.reduceTransparency && hs.wallSource !== ""
        blurEnabled: true
        blur: 1
        blurMax: hs.dk.blurMax
        saturation: hs.dk.saturation
      }
      Rectangle {
        anchors.fill: parent
        color: Theme.reduceTransparency ? Theme.r.popover.bgOpaque : hs.dk.tint
      }
    }
    Item {
      id: dockMask
      anchors.fill: parent
      layer.enabled: true
      visible: false
      Rectangle { anchors.fill: parent; radius: dock.radius; color: Theme.core.surface.tablet.indicator.onLight }
    }
    Rectangle {
      anchors.fill: parent
      radius: dock.radius
      color: "transparent"   // lint-ok: the rim only
      border.width: 1 / Screen.devicePixelRatio
      border.color: hs.dk.rim
    }
    Row {
      id: dockRow
      anchors.centerIn: parent
      spacing: hs.g.dockSpace
      Repeater {
        model: hs.dockApps.concat(hs.recentApps.length ? [{ id: "", sep: true }] : []).concat(hs.recentApps)
        Item {
          required property var modelData
          readonly property string appId: modelData.id || ""
          width: modelData.sep ? Theme.layout.separator : hs.g.dockIcon
          height: hs.g.dockIcon
          Rectangle {
            visible: !!parent.modelData.sep
            anchors.centerIn: parent
            width: Theme.layout.separator
            height: parent.height * hs.cfg.dividerShare
            color: hs.dk.divider
          }
          Image {
            visible: !parent.modelData.sep
            anchors.fill: parent
            source: parent.modelData.icon || ""
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            asynchronous: true
            scale: (hs.pressedId !== "" && hs.pressedId === parent.appId ? hs.cfg.pressScale : 1) * VIconMetrics.scale(source)
            opacity: hs.pressedId !== "" && hs.pressedId === parent.appId ? hs.lp.press : 1
          }
          // running: a dot under the icon
          Rectangle {
            visible: !parent.modelData.sep && hs.running[parent.appId] === true
            anchors.horizontalCenter: parent.horizontalCenter
            y: parent.height + hs.dk.dotGap
            width: hs.dk.dotSize
            height: width
            radius: width / 2
            color: hs.dk.dot
          }
        }
      }
    }
  }

  // ---- the open folder (iPadOS): the wallpaper blurs, a light panel grows out of the folder's tile
  // closing is quicker than opening (exit faster than enter)
  readonly property var folderSpring: { var p = Theme.spring("snappy"); return hs.openFolder ? p : { response: p.response * Theme.core.motion.exitFactor, dampingRatio: p.dampingRatio } }
  Spring { id: fo; reduced: Theme.reduceMotion; preset: hs.folderSpring; target: hs.openFolder ? 1 : 0 }
  property var folderTile: null      // what the panel shows: kept while it closes
  property var folderFrom: ({ x: 0, y: 0, w: 1 })   // the tile's plate when it opened (centre, width)
  onOpenTileChanged: if (openTile) folderTile = openTile
  onOpenFolderChanged: {
    if (!openFolder) return
    for (var j = 0; j < grid.count; j++) {
      var t = grid.itemAt(j)
      if (!t || t.appId !== openFolder) continue
      var c = t.icon.mapToItem(hs, t.icon.width / 2, t.icon.height / 2)
      folderFrom = { x: c.x, y: c.y, w: t.icon.width * t.body }
    }
  }
  readonly property real fv: Math.max(0, fo.value)
  readonly property real fw: width * (width >= height ? fc.panelShare : fc.panelSharePortrait)
  readonly property real fcellW: (fw - 2 * fc.panelPad) / fc.panelCols
  readonly property int fn: folderTile ? folderTile.items.length : 0
  readonly property real fh: Math.max(1, Math.ceil(fn / fc.panelCols)) * cellH + 2 * fc.panelPad
  // the blurred wallpaper behind it: here (the gesture overlay covers the screen) or in a window
  // of its own under this one (folderBackdrop false: the home screen's window ends at the bar)
  property bool folderBackdrop: true
  readonly property real folderShown: fv
  FolderBackdrop {
    x: hs.wallRect.x; y: hs.wallRect.y; width: hs.wallRect.width; height: hs.wallRect.height
    visible: hs.folderBackdrop && opacity > 0.002
    opacity: Math.min(1, hs.fv)
    wallSource: hs.wallSource
    wallRect: Qt.rect(0, 0, width, height)
  }
  VText {
    id: folderTitle
    anchors.horizontalCenter: parent.horizontalCenter
    y: folderPanel.y - height - hs.fc.titleGap
    text: hs.folderTile ? hs.folderTile.name : ""
    font.pixelSize: Theme.core.type.largeTitle
    font.weight: Font.Bold
    color: hs.lp.label
    style: Text.Raised
    styleColor: hs.cfg.labelShade
    opacity: Math.min(1, hs.fv)
    visible: opacity > 0.002
  }
  Item {
    id: folderPanel
    width: hs.fw
    height: hs.fh
    x: (hs.width - width) / 2
    y: (hs.height - hs.g.bottom - height + folderTitle.height + hs.fc.titleGap) / 2
    visible: hs.fv > 0.002
    // grows out of the tile: from the plate's width and centre to its own
    readonly property real s0: hs.folderFrom.w / width
    transform: [
      Scale { origin.x: folderPanel.width / 2; origin.y: folderPanel.height / 2
              xScale: folderPanel.s0 + (1 - folderPanel.s0) * hs.fv; yScale: xScale },
      Translate { x: (hs.folderFrom.x - hs.width / 2) * (1 - hs.fv)
                  y: (hs.folderFrom.y - folderPanel.y - folderPanel.height / 2) * (1 - hs.fv) }
    ]
    VShadow { layers: hs.dk.shadow; radius: hs.fc.panelRadius; opacity: Math.min(1, hs.fv) }
    Rectangle {
      anchors.fill: parent
      radius: hs.fc.panelRadius
      color: Theme.reduceTransparency ? Theme.r.popover.bgOpaque : hs.fc.panelTint
      border.width: 1 / Screen.devicePixelRatio
      border.color: hs.fc.panelRim
    }
    Item {
      anchors.fill: parent
      opacity: Math.max(0, Math.min(1, (hs.fv - hs.fc.contentFrom) / (1 - hs.fc.contentFrom)))
      Repeater {
        id: folderGrid
        model: hs.folderTile ? hs.folderTile.items : []
        Item {
          id: fcell
          required property var modelData
          required property int index
          readonly property string appId: modelData.id
          property alias icon: fimg
          x: hs.fc.panelPad + (index % hs.fc.panelCols) * hs.fcellW
          y: hs.fc.panelPad + Math.floor(index / hs.fc.panelCols) * hs.cellH
          width: hs.fcellW
          height: hs.cellH
          property real wobble: 0
          rotation: wobble * hs.ed.jiggleAngle * (index % 2 ? 1 : -1)
          SequentialAnimation on wobble {
            running: hs.editing && hs.openFolder !== "" && !Theme.reduceMotion
            loops: Animation.Infinite
            NumberAnimation { to: 1; duration: Theme.ambient("jiggle") / 2; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") }
            NumberAnimation { to: -1; duration: Theme.ambient("jiggle") / 2; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") }
            onRunningChanged: if (!running) fcell.wobble = 0
          }
          Image {
            id: fimg
            anchors.horizontalCenter: parent.horizontalCenter
            y: (parent.height - height - hs.cfg.labelGap - fname.height) / 2
            width: hs.g.icon
            height: width
            source: fcell.modelData.icon
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            asynchronous: true
            scale: (hs.pressedId === fcell.appId && !hs.editing ? hs.cfg.pressScale : 1) * VIconMetrics.scale(source)
            opacity: hs.pressedId === fcell.appId && !hs.editing ? hs.lp.press : 1
          }
          VText {
            id: fname
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: fimg.bottom
            anchors.topMargin: hs.cfg.labelGap
            width: Math.min(implicitWidth, hs.fcellW - hs.cfg.labelGap)
            horizontalAlignment: Text.AlignHCenter
            text: fcell.modelData.name
            font.pixelSize: Theme.m.type.small
            font.weight: Font.Medium
            color: hs.lp.label
            style: Text.Raised
            styleColor: hs.cfg.labelShade
          }
        }
      }
    }
  }
  function folderAppAt(x, y) {
    for (var j = 0; j < folderGrid.count; j++) {
      var t = folderGrid.itemAt(j)
      if (!t) continue
      var q = t.icon.mapFromItem(hs, x, y)
      if (q.x >= 0 && q.x <= t.icon.width && q.y >= 0 && q.y <= t.icon.height) return t.appId
    }
    return ""
  }
  function inPanel(x, y) {
    var q = folderPanel.mapFromItem(hs, x, y)
    return q.x >= 0 && q.y >= 0 && q.x <= folderPanel.width && q.y <= folderPanel.height
  }

  // ---- fingers: a tap opens, a drag turns pages
  function appAt(x, y) {
    var p = dockRow.mapFromItem(hs, x, y)
    for (var i = 0; i < dockRow.children.length; i++) {
      var d = dockRow.children[i]
      if (d.appId && p.x >= d.x && p.x <= d.x + d.width && p.y >= d.y && p.y <= d.y + d.height) return d.appId
    }
    for (var j = 0; j < grid.count; j++) {
      var t = grid.itemAt(j)
      if (!t || t.pageOf !== hs.page) continue
      var q = t.icon.mapFromItem(hs, x, y)
      if (q.x >= 0 && q.x <= t.icon.width && q.y >= 0 && q.y <= t.icon.height) return t.appId
    }
    return ""
  }
  function gridTileAt(x, y) {
    for (var j = 0; j < grid.count; j++) {
      var t = grid.itemAt(j)
      if (!t || t.pageOf !== hs.page) continue
      var q = t.icon.mapFromItem(hs, x, y)
      if (q.x >= 0 && q.x <= t.icon.width && q.y >= 0 && q.y <= t.icon.height) return t
    }
    return null
  }
  // a held icon: it follows the finger, the slot under it opens up
  function beginDrag(x, y) {
    var t = gridTileAt(x, y)
    if (!t) return false
    finger.grabX = x - (t.x + hs.pageX)
    finger.grabY = y - t.y
    finger.iconY = t.icon.y + t.icon.height / 2
    finger.dragFolder = t.isFolder || t.isWidget   // neither goes into a folder
    hs.dragX = t.x + hs.pageX
    hs.dragY = t.y
    hs.dropIndex = hs.order.indexOf(t.appId)
    finger.nextIndex = hs.dropIndex
    hs.dragId = t.appId
    hs.pressedId = ""
    return true
  }
  function dragTo(x, y) {
    finger.lastX = x; finger.lastY = y
    hs.dragX = x - finger.grabX
    hs.dragY = y - finger.grabY
    // over another icon's centre it aims at a folder (iPadOS) and the others stay put; else the
    // icon's centre picks the slot
    var aim = finger.dragFolder ? "" : hs.aimAt(hs.dragX + hs.cellW / 2, hs.dragY + finger.iconY)
    if (aim) {
      reorderTimer.stop()   // a wait begun on the way here must not move the target away
      if (aim !== hs.mergeAim) { hs.mergeAim = aim; hs.mergeId = ""; mergeTimer.restart() }
    } else {
      if (hs.mergeAim) { hs.mergeAim = ""; hs.mergeId = ""; mergeTimer.stop() }
      // the others make room once the finger rests a moment (every move restarts the wait), so
      // an icon passing over them on its way to a folder target does not push that target away
      finger.nextIndex = HM.dropAt(hs.order, hs.dragId, hs.dragX + hs.cellW / 2, hs.dragY + hs.cellH / 2, hs.page, hs.spanOf, hs.g, hs.cellW, hs.cellH)
      if (finger.nextIndex !== hs.dropIndex) reorderTimer.restart()
    }
    var e = HM.edgeOf(x, hs.width, hs.cfg)
    if (e !== finger.edge) { finger.edge = e; if (e) edgeTimer.restart(); else edgeTimer.stop() }
  }
  // the icon whose centre is near (x, y) on this page, at its settled slot
  function aimAt(x, y) {
    var r = hs.fc.mergeZone * hs.g.icon / 2
    for (var j = 0; j < grid.count; j++) {
      var t = grid.itemAt(j)
      if (!t || t.held || t.isWidget || t.pageOf !== hs.page) continue
      var cx = hs.slotX(t.slot) + hs.pageX + t.icon.x + t.icon.width / 2, cy = hs.slotY(t.slot) + t.icon.y + t.icon.height / 2
      if (Math.abs(x - cx) < r && Math.abs(y - cy) < r) return t.appId
    }
    return ""
  }
  Timer { id: mergeTimer; interval: hs.fc.mergeDwell; onTriggered: hs.mergeId = hs.mergeAim }
  Timer { id: reorderTimer; interval: hs.fc.reorderDwell; onTriggered: if (finger.nextIndex >= 0) hs.dropIndex = finger.nextIndex }
  function drop() {
    edgeTimer.stop(); finger.edge = 0
    var target = hs.mergeId, aimed = hs.mergeAim
    mergeTimer.stop(); reorderTimer.stop(); hs.mergeAim = ""; hs.mergeId = ""
    if (target) { var id = hs.dragId; hs.dropIndex = -1; hs.dragId = ""; finger.nextIndex = -1; hs.folded(id, target); return }
    // let go before the others made room: the slot under it all the same (not over an icon it aimed at)
    if (!aimed && finger.nextIndex >= 0) hs.dropIndex = finger.nextIndex
    finger.nextIndex = -1
    var next = hs.shown
    hs.dropIndex = -1
    hs.dragId = ""
    hs.reordered(next)
  }
  // a page turned under a held icon: the slot under it is on the new page
  onPageChanged: if (hs.dragId) hs.dragTo(finger.lastX, finger.lastY)
  Timer {
    id: edgeTimer
    interval: hs.ed.edgeDwell
    repeat: true
    onTriggered: {
      var to = hs.page + finger.edge
      if (!finger.edge || to < 0 || to >= hs.pages) return
      hs.turnPage(finger.edge)
    }
  }
  // touch and hold an icon: edit mode, and that icon is already in the hand
  Timer {
    id: hold
    interval: Theme.delay("longPress")
    onTriggered: {
      if (finger.moved || !finger.down0) return
      if (!hs.editing) hs.editRequested(true)
      if (finger.inFolder) return
      if (hs.beginDrag(finger.x0, finger.y0)) finger.dragging = true
    }
  }
  // one finger's path, from real touch (MultiPointTouchArea) or a pointer (MouseArea, the rig)
  QtObject {
    id: finger
    property real x0: 0
    property real y0: 0
    property real lastX: 0
    property real lastY: 0
    property bool moved: false
    property bool down0: false
    property bool dragging: false
    property real grabX: 0
    property real grabY: 0
    property int edge: 0
    property real iconY: 0
    property int nextIndex: -1         // the slot under a held icon, before the others make room
    property bool dragFolder: false
    property bool inFolder: false      // the press began with a folder open
    property var samples: []
    function down(x, y) {
      x0 = x; y0 = y; lastX = x; moved = false; dragging = false; down0 = true; samples = [[Date.now(), x]]
      inFolder = hs.openFolder !== ""
      if (inFolder) { hs.pressedId = hs.folderAppAt(x, y); if (hs.pressedId) hold.restart(); return }
      hs.pressedId = hs.appAt(x, y)
      if (hs.gridTileAt(x, y)) hold.restart()
    }
    function move(x, y) {
      if (dragging) { hs.dragTo(x, y); return }
      if (inFolder) {
        if (!moved && Math.hypot(x - x0, y - y0) > Theme.core.surface.tablet.slop) { moved = true; hold.stop(); if (!hs.editing) hs.pressedId = "" }
        // edit mode: an app pulled out of the panel goes back to the grid, the folder closes
        if (moved && hs.editing && hs.pressedId && !hs.inPanel(x, y)) {
          var out = hs.pressedId
          hs.pressedId = ""
          hs.unfolded(out)
          hs.folderRequested("")
        }
        return
      }
      var t = Date.now(), list = samples.concat([[t, x]])
      while (list.length > 2 && t - list[0][0] > Theme.core.surface.tablet.sampleWindow) list.shift()
      samples = list; lastX = x
      if (!moved && Math.hypot(x - x0, y - y0) > Theme.core.surface.tablet.slop) {
        // in edit mode a moving finger on an icon takes it along; elsewhere it turns pages
        if (hs.editing && hs.beginDrag(x0, y0)) { dragging = true; hold.stop(); hs.dragTo(x, y); return }
        moved = true; hs.pressedId = ""; hold.stop()
      }
      if (moved) hs.pageMoved(x - x0, t)
    }
    function up() {
      hold.stop(); down0 = false
      if (dragging) { dragging = false; hs.drop(); return }
      var id = hs.pressedId
      hs.pressedId = ""
      if (inFolder) {
        inFolder = false
        if (moved) return
        if (id) { if (!hs.editing) hs.tapped(id) }
        else if (!hs.inPanel(x0, y0)) hs.folderRequested("")   // a tap beside the panel closes it
        return
      }
      if (!moved) {
        // a folder opens with a tap, also in edit mode
        if (HM.isFolder(id) || (hs.editing && HM.isFolder(hs.appAt(x0, y0)))) { hs.folderRequested(id || hs.appAt(x0, y0)); return }
        if (hs.editing) { if (!hs.appAt(x0, y0)) hs.editRequested(false); return }
        if (id) hs.tapped(id)
        return
      }
      // the last few events' speed carries the page (a lift long after the last move: none)
      var a = samples[0], b = samples[samples.length - 1], now = Date.now()
      var fresh = now - b[0] < Theme.core.surface.tablet.sampleWindow
      hs.pageReleased(fresh && b[0] > a[0] ? (b[1] - a[1]) * 1000 / (b[0] - a[0]) : 0)
    }
    function cancel() {
      hold.stop(); down0 = false; inFolder = false
      if (dragging) { dragging = false; hs.drop(); return }
      hs.pressedId = ""; if (moved) hs.pageReleased(0)
    }
  }
  MultiPointTouchArea {
    anchors.fill: parent
    enabled: hs.interactive
    maximumTouchPoints: 1
    mouseEnabled: false
    onPressed: function (pts) { finger.down(pts[0].x, pts[0].y) }
    onUpdated: function (pts) { finger.move(pts[0].x, pts[0].y) }
    onReleased: function (pts) { finger.up() }
    onCanceled: finger.cancel()
  }
  MouseArea {
    anchors.fill: parent
    enabled: hs.interactive
    preventStealing: true
    onPressed: function (m) { finger.down(m.x, m.y) }
    onPositionChanged: function (m) { finger.move(m.x, m.y) }
    onReleased: function (m) { finger.up() }
    onCanceled: finger.cancel()
  }

  // edit mode ends with Done (iPadOS, top right), as with a tap on an empty spot
  VButton {
    visible: hs.editing && hs.interactive
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: hs.ed.doneInset
    anchors.rightMargin: hs.ed.doneInset
    text: "Done"
    kind: "primary"
    onClicked: hs.editRequested(false)
  }
}
