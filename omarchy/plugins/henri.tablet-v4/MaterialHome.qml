import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import "file:///home/henri/.local/share/velum/qml/Velum"
import "HomeModel.js" as HM
import "MaterialModel.js" as MM
import "Resample.js" as Resample
import "widgets"
import "widgets/Widgets.js" as W

// The home screen of tablet mode v4: the Material lab (lab/mui-material/src/Launcher.jsx) native.
// An Android/Pixel launcher (AOSP Launcher3's behaviour) on a configured Material theme with Velum's
// influences: pages of icons with Roboto names, page dots (MobileStepper), the hotseat without a
// plate lined up with the grid's columns, a Material 3 search bar; a long press opens the app's
// menu (MaterialMenu: header, its actions, New window / App info as tonal tiles) and the icon can
// be pulled away at once — no edit mode, no jiggle; while an item is in the hand, Remove and
// Uninstall come in at the top; resting on an icon makes a folder, resting elsewhere makes room,
// resting at a side turns the page (a new one past the last); the hotseat takes up to six; Remove
// can be undone from a snackbar; a long press on the wallpaper opens the home menu.
// Drawn twice with the same values, as v3's HomeScreen: on the bottom layer of an empty workspace
// (interactive) and behind the cards of the home gesture. Home.qml owns the layout and saves it;
// this item proposes changes (`arranged`, `removeRequested`, `renamed`) and draws what it gets.
// Only transform and opacity move per frame; blur only from a cached wallpaper copy.
Item {
  id: hs

  readonly property var mt: Theme.core.surface.material
  readonly property var hm: Theme.core.surface.tablet.home
  readonly property var tt: Theme.core.surface.tablet
  readonly property var mg: mt.grid
  // ---- from Home.qml
  property var tiles: []          // grid tiles: [{ key, id, name, icon, folder?, items?, widget? }] (not the hotseat's)
  property var hotApps: []        // the hotseat's apps [{ id, name, icon }]
  property var layout: ({ order: [], folders: {}, hotseat: [] })
  property var entries: ({})      // app id → { id, name, icon, cats, actions }
  property var menuFor: function (id, where) { return null }   // → { header, rows, tiles }
  property var nameFolder: function (ids) { return "Folder" }
  property string openFolder: ""
  property var snack: null        // { text, undo }
  property var confirm: null      // { id, name, plan }
  property real pageX: 0
  property int page: 0
  property bool interactive: false
  property real gridOpacity: 1
  property real gridScale: 1
  property real gridBlur: 0
  property real gridBlurMax: 0
  property real dockShift: 0      // the hotseat and the search bar below their place by this much
  property string wallSource: ""
  property rect wallRect: Qt.rect(0, 0, width, height)
  property bool folderBackdrop: true
  property var running: ({})
  // ---- to Home.qml
  signal tapped(string id)
  signal widgetTapped(string id, string item)
  signal pageMoved(real x, real t)
  signal pageReleased(real velocity)
  signal turnPage(int dir)
  signal arranged(var next)                      // { order, folders, hotseat }
  signal removeRequested(var ids, string name)   // hide these (Home keeps the layout before for Undo)
  signal folderRequested(string id)
  signal renamed(string key, string name)
  signal menuChosen(string id, string key)
  signal searchRequested()
  signal drawerDrag(real travel)                 // a finger up on the grid: All apps follow it (px up)
  signal drawerRelease(real velocityUp)          // it let go (px/s, up positive)
  signal uninstallRequested(string id, string name)
  signal confirmed(bool ok)
  signal undoRequested()
  signal snackClosed()

  readonly property var geo: MM.geometry(width, height, mt)
  // the travel the hotseat and search bar take in from below (the shell's entrance, the home gesture)
  readonly property real dockTravel: height - geo.dotsY

  // ---- palette: MUI's roles for the appearance, primary = the variant's accent
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }   // lint-ok: a role at a token's opacity
  QtObject {
    id: pal
    readonly property bool dk: Theme.dark
    readonly property var c: hs.mt.color
    readonly property color primary: Theme.r.accent.base
    readonly property color text: dk ? c.textDark : c.textLight
    readonly property color text2: dk ? c.text2Dark : c.text2Light
    readonly property color action: dk ? c.actionDark : c.actionLight
    readonly property color divider: dk ? c.dividerDark : c.dividerLight
    readonly property color error: dk ? c.errorDark : c.errorLight
    readonly property color dot: dk ? c.dotDark : c.dotLight
    readonly property color paper: dk ? c.paperDark : c.paperLight
    readonly property color rim: dk ? c.rimDark : c.rimLight
    readonly property color tint: hs.alpha(primary, dk ? c.tintDark : c.tintLight)
    readonly property color press: hs.alpha(primary, dk ? c.pressDark : c.pressLight)
    readonly property color snack: dk ? c.snackDark : c.snackLight
    readonly property color onSnack: dk ? c.onSnackDark : c.onSnackLight
  }

  // ---- what shows where
  readonly property var tileMap: { var o = {}; for (var i = 0; i < tiles.length; i++) o[tiles[i].id] = tiles[i]; return o }
  readonly property var appMap: { var o = {}; for (var i = 0; i < hotApps.length; i++) o[hotApps[i].id] = hotApps[i]; for (var k in tileMap) o[k] = tileMap[k]; return o }
  function shows(id) { return HM.isBreak(id) || !!hs.appMap[id] || id === hs.dragId }
  // a widget's span by its kind (surface.material.widgets.cells), an app or folder one cell
  function spanOf(id) { return HM.isWidget(id) ? W.span(hs.mt.widgets.cells, id.slice(7)) : [1, 1] }
  readonly property bool dragging: dragId !== ""
  readonly property var shownOrder: (dragging ? dragOrder : layout.order).filter(shows)
  readonly property var shownHot: (dragging ? dragHot : layout.hotseat).filter(function (id) { return !!hs.appMap[id] || !!hs.entries[id] && id === hs.dragId })
  readonly property var cells: HM.place(shownOrder, spanOf, geo.cols, geo.rows)
  readonly property int pages: HM.pageCount(cells)
  function nameOf(id) {
    if (HM.isFolder(id)) { var f = layout.folders[HM.folderKey(id)]; return f ? f.name : "Folder" }
    var t = appMap[id] || entries[id]
    return t ? t.name : id
  }
  function iconOf(id) { var t = appMap[id] || entries[id]; return t ? t.icon || "" : "" }
  function folderItems(id) {
    var f = layout.folders[HM.folderKey(id)]
    return f ? f.items.map(function (a) { return hs.entries[a] }).filter(Boolean) : []
  }
  // the last page emptied: back to the one before
  onPagesChanged: if (interactive && !dragging && page > pages - 1) turnPage(pages - 1 - page)
  onInteractiveChanged: if (!interactive) { menuOpen = false; finger.cancel() }

  // an item's settled rect on page p (screen coordinates of this item): the icon, or a widget's card
  function tileRect(id, p) {
    var i = shownOrder.indexOf(id), c = i >= 0 ? cells[i] : null
    if (!c || c.brk) return null
    var wide = HM.isWidget(id), q = p === undefined ? page : p
    return { x: MM.cellX(c, geo) - q * width + geo.iconX, y: MM.cellY(c, geo) + geo.iconY,
             w: wide ? c.w * geo.cellW - 2 * geo.iconX : geo.icon, h: wide ? c.h * geo.cellH - 2 * geo.iconY : geo.icon, page: c.page }
  }
  function hotRect(id) {
    var i = shownHot.indexOf(id)
    return i < 0 ? null : { x: MM.hotseatX(i, shownHot.length, geo), y: geo.hotseatY, w: geo.icon, h: geo.icon }
  }

  // ================================================================ the pages
  Item {
    id: zoom
    width: hs.width
    height: hs.height
    opacity: hs.gridOpacity * (1 - Math.min(1, hs.fv))
    visible: opacity > 0.002
    scale: hs.gridScale
    transformOrigin: Item.Center
    layer.enabled: hs.gridBlur > 0.002
    layer.effect: MultiEffect { blurEnabled: true; blur: Math.min(1, hs.gridBlur); blurMax: hs.gridBlurMax }
    Item {
      id: track
      x: hs.pageX
      width: hs.width * Math.max(1, hs.pages)
      height: hs.height
      Repeater {
        id: grid
        model: ScriptModel { values: hs.tiles; objectProp: "key" }
        Item {
          id: tile
          required property var modelData
          readonly property string appId: modelData.id
          readonly property bool isFolder: !!modelData.folder
          readonly property bool isWidget: !!modelData.widget
          readonly property var span: hs.spanOf(appId)
          readonly property int slot: hs.shownOrder.indexOf(appId)
          readonly property var cell: slot >= 0 ? hs.cells[slot] : null
          readonly property bool placed: !!cell && !cell.brk
          readonly property int pageOf: placed ? cell.page : -1
          readonly property bool held: hs.dragId === appId
          readonly property bool aimed: hs.aimId === appId && hs.aimArmed
          property alias face: face
          Spring { id: sx; reduced: Theme.reduceMotion || !VBoot.chrome; preset: Theme.spring("snappy"); target: tile.placed ? MM.cellX(tile.cell, hs.geo) : 0 }
          Spring { id: sy; reduced: Theme.reduceMotion || !VBoot.chrome; preset: Theme.spring("snappy"); target: tile.placed ? MM.cellY(tile.cell, hs.geo) : 0 }
          Component.onCompleted: { sx.snap(sx.target); sy.snap(sy.target) }
          x: sx.value
          y: sy.value
          width: hs.geo.cellW * span[0]
          height: hs.geo.cellH * span[1]
          visible: placed
          z: sx.moving || sy.moving ? 1 : 0
          // pressed: MUI's ripple wash over the icon and its name
          Rectangle {
            x: (parent.width - width) / 2
            y: hs.geo.iconY - hs.mg.tilePad
            width: tile.isWidget ? face.width + 2 * hs.mg.tilePad : Math.min(hs.geo.cellW, Math.max(hs.geo.icon, label.paintedWidth) + 2 * hs.mg.tilePad)
            height: tile.isWidget ? face.height + 2 * hs.mg.tilePad : hs.geo.icon + hs.mg.labelGap + hs.geo.labelH + 2 * hs.mg.tilePad
            radius: hs.mg.pressRadius
            color: hs.mt.color.rippleOnWall
            opacity: hs.pressedId === tile.appId && !tile.held ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: hs.pressedId === tile.appId ? hs.mt.motion.enter : hs.mt.motion.exit } }
          }
          Item {
            id: face
            x: tile.isWidget ? hs.geo.iconX : (parent.width - width) / 2
            y: hs.geo.iconY
            width: tile.isWidget ? parent.width - 2 * hs.geo.iconX : hs.geo.icon
            height: tile.isWidget ? parent.height - 2 * hs.geo.iconY : hs.geo.icon
            opacity: tile.held && !hs.heldCopy ? 0 : 1
            // armed as a folder target: the v3 plate grows behind the icon, the icon shrinks into it
            Spring { id: aim; reduced: Theme.reduceMotion; preset: Theme.spring("snappy"); target: tile.aimed ? 1 : 0 }
            // the widget by its kind (widgets/: Photos, Battery, Clock, Tablet), loaded only for widget tiles
            Loader {
              anchors.fill: parent
              active: tile.isWidget
              sourceComponent: HomeWidget { kind: tile.modelData.widget || "" }
            }
            FolderPlate {
              anchors.centerIn: parent
              size: parent.width * Theme.core.surface.appIcon.content
              visible: tile.isFolder || aim.value > 0.01
              opacity: tile.isFolder ? 1 : Math.min(1, aim.value)
              scale: 1 + (hs.hm.folder.mergeScale - 1) * aim.value
              apps: tile.isFolder ? HM.miniApps(tile.modelData.items, hs.hm.folder.miniCols) : []
              cfg: hs.hm.folder
              iconRadius: hs.hm.iconRadius
              wallSource: tile.isFolder ? hs.wallSource : ""
              wallRect: hs.wallRect
              blurMax: hs.hm.dock.blurMax
              saturation: hs.hm.dock.saturation
              // where the plate sits once its page shows (static: a pan does not re-blur it every frame)
              origin: Qt.point(tile.x - Math.max(0, tile.pageOf) * hs.width + face.x + (face.width - width) / 2, tile.y + face.y + (face.height - height) / 2)
            }
            Image {
              visible: !tile.isFolder && !tile.isWidget
              anchors.fill: parent
              source: tile.isFolder || tile.isWidget ? "" : tile.modelData.icon || ""
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              asynchronous: true
              scale: VIconMetrics.scale(source) * (1 - (1 - 1 / hs.hm.folder.mergeScale) * aim.value)
            }
          }
          WallLabel {
            id: label
            visible: !tile.isWidget
            y: face.y + face.height + hs.mg.labelGap
            height: hs.geo.labelH
            width: hs.geo.cellW - hs.mg.labelInset
            x: (parent.width - width) / 2
            text: tile.modelData.name || ""
            opacity: tile.held ? 0 : 1
          }
        }
      }
    }
  }
  // ---- page dots (MobileStepper)
  Row {
    id: dots
    anchors.horizontalCenter: parent.horizontalCenter
    y: hs.geo.dotsY + (hs.mg.dotsBand - hs.mt.stepper.dot) / 2 + hs.dockShift
    spacing: hs.mt.stepper.gap
    visible: hs.pages > 1 && opacity > 0.002
    opacity: hs.gridOpacity * (1 - Math.min(1, hs.fv))
    Repeater {
      model: hs.pages
      Rectangle {
        required property int index
        width: hs.mt.stepper.dot
        height: width
        radius: width / 2
        color: index === hs.page ? pal.primary : pal.dot
      }
    }
  }

  // ---- the hotseat: no plate, one grid column per icon, centred
  Item {
    id: hotseat
    width: hs.width
    height: hs.height
    y: hs.dockShift
    opacity: 1 - Math.min(1, hs.fv)
    visible: opacity > 0.002
    Repeater {
      id: hotRep
      model: ScriptModel { values: hs.hotApps; objectProp: "id" }
      Item {
        id: hot
        required property var modelData
        readonly property string appId: modelData.id
        readonly property int at: hs.shownHot.indexOf(appId)
        readonly property bool held: hs.dragId === appId
        property alias face: hface
        Spring { id: hsx; reduced: Theme.reduceMotion || !VBoot.chrome; preset: Theme.spring("snappy"); target: hot.at >= 0 ? MM.hotseatX(hot.at, hs.shownHot.length, hs.geo) : 0 }
        Component.onCompleted: hsx.snap(hsx.target)
        x: hsx.value
        y: hs.geo.hotseatY
        width: hs.geo.icon
        height: width
        visible: at >= 0
        Rectangle {
          anchors.centerIn: parent
          width: parent.width + 2 * hs.mg.tilePad
          height: width
          radius: width / 2
          color: hs.mt.color.rippleOnWall
          opacity: hs.pressedId === hot.appId && !hot.held ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: hs.pressedId === hot.appId ? hs.mt.motion.enter : hs.mt.motion.exit } }
        }
        Image {
          id: hface
          anchors.fill: parent
          opacity: hot.held ? 0 : 1
          source: hot.modelData.icon || ""
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          asynchronous: true
          scale: VIconMetrics.scale(source)
        }
      }
    }
  }

  // ---- the Material 3 search bar (phase 1: a tap opens Spotlight)
  Rectangle {
    id: searchBar
    x: hs.geo.search.x
    y: hs.geo.search.y + hs.dockShift
    width: hs.geo.search.w
    height: hs.geo.search.h
    radius: height / 2
    color: hs.alpha(pal.paper, hs.mt.color.searchAlpha)
    opacity: hs.gridOpacity * (1 - Math.min(1, hs.fv))
    visible: opacity > 0.002
    VIcon {
      x: hs.mt.search.padX
      anchors.verticalCenter: parent.verticalCenter
      name: "search"
      size: hs.mt.search.icon
      color: pal.action
    }
    MText {
      x: hs.mt.search.padX + hs.mt.search.icon + hs.mt.search.gap
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x - 2 * hs.mt.search.padX - hs.mt.search.icon - hs.mt.search.gap
      text: "Search"
      font.pixelSize: hs.mt.type.body1
      color: pal.text2
    }
    VIcon {
      x: parent.width - hs.mt.search.padX - width
      anchors.verticalCenter: parent.verticalCenter
      name: "mic"
      size: hs.mt.search.icon
      color: pal.action
    }
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      color: pal.dk ? hs.mt.color.rippleOnWall : hs.mt.color.rippleLight
      opacity: finger.kind === "search" && finger.down0 ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: hs.mt.motion.exit } }
    }
  }

  // ---- the drop targets (Launcher3 DropTargetBar): Remove, Uninstall
  readonly property var targets: dragging ? MM.dropTargets(dragKind, dragFrom) : []
  Row {
    id: dropBar
    anchors.horizontalCenter: parent.horizontalCenter
    y: (hs.geo.top - hs.mt.drop.button) / 2
    spacing: hs.mt.drop.gap
    opacity: hs.dragging && !hs.landing ? 1 : 0
    visible: opacity > 0.002
    Behavior on opacity { NumberAnimation { duration: hs.dragging && !hs.landing ? hs.mt.motion.enter : hs.mt.motion.exit } }
    Repeater {
      model: hs.targets
      Item {
        id: dt
        required property string modelData
        required property int index
        readonly property bool hot: hs.dropTarget === modelData
        readonly property real pad: hot ? hs.mt.drop.padX : hs.mt.drop.textPadX
        width: 2 * hs.mt.drop.padX + hs.mt.drop.icon + hs.mt.drop.iconGap + dtText.implicitWidth
        height: hs.mt.drop.button
        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: pal.error
          opacity: dt.hot ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: hs.mt.motion.exit } }
        }
        Row {
          anchors.centerIn: parent
          spacing: hs.mt.drop.iconGap
          VIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: dt.modelData === "remove" ? "close" : "trash"
            size: hs.mt.drop.icon
            color: dt.hot ? hs.mt.color.onError : hs.mt.color.onWall
          }
          MText {
            id: dtText
            anchors.verticalCenter: parent.verticalCenter
            text: dt.modelData === "remove" ? "Remove" : "Uninstall"
            font.pixelSize: hs.mt.type.button
            font.weight: Font.Medium
            color: dt.hot ? hs.mt.color.onError : hs.mt.color.onWall
          }
        }
      }
    }
  }

  // ================================================================ the open folder
  // a Material panel on the glass grows out of the folder's tile (MUI Grow); the wallpaper behind it
  // blurs under a scrim in Home.qml's backdrop window (here only for the gesture's copy)
  property string folderShownId: ""   // kept while it closes
  property var folderFrom: ({ x: 0, y: 0 })
  property real fv: 0
  NumberAnimation { id: fGrow; target: hs; property: "fv" }
  onOpenFolderChanged: {
    fGrow.stop()
    if (openFolder) {
      keysHeld = true
      folderShownId = openFolder
      var r = tileRect(openFolder)
      folderFrom = r ? { x: r.x + r.w / 2, y: r.y + r.h / 2 } : { x: width / 2, y: height / 2 }
      fGrow.to = 1; fGrow.duration = Theme.reduceMotion ? 0 : mt.motion.enter; fGrow.easing.type = Easing.BezierSpline; fGrow.easing.bezierCurve = mt.motion.easeOut
    } else {
      if (nameField.activeFocus) commitName()
      fGrow.to = 0; fGrow.duration = Theme.reduceMotion ? 0 : mt.motion.exit; fGrow.easing.type = Easing.BezierSpline; fGrow.easing.bezierCurve = mt.motion.sharp
      releaseKeys()
    }
    fGrow.start()
  }
  readonly property real folderShown: fv
  readonly property var fItemsShown: {
    if (!folderShownId) return []
    var all = folderItems(folderShownId)
    if (dragging && dragFrom === "folder" && fOrder.length) {
      var byId = {}
      for (var i = 0; i < all.length; i++) byId[all[i].id] = all[i]
      return fOrder.map(function (id) { return byId[id] || hs.entries[id] }).filter(Boolean)
    }
    return all
  }
  readonly property var panel: MM.folderPanel(Math.max(1, fItemsShown.length), geo, mt)
  // the window takes the keyboard on demand while a folder is open — and keeps asking until the finger
  // lifts: changing it under a held pointer makes the compositor end the pointer's grab (the app
  // carried out of a folder fell from the hand)
  property bool keysHeld: false
  readonly property bool wantsKeys: openFolder !== "" || keysHeld
  function releaseKeys() { if (!openFolder && !finger.down0) keysHeld = false }
  FolderBackdrop {
    x: hs.wallRect.x; y: hs.wallRect.y; width: hs.wallRect.width; height: hs.wallRect.height
    visible: hs.folderBackdrop && opacity > 0.002
    opacity: Math.min(1, hs.folderShown)
    wallSource: hs.wallSource
    wallRect: Qt.rect(0, 0, width, height)
    tint: hs.mt.color.scrim
  }
  Item {
    id: folderPanel
    x: hs.panel.x
    y: hs.panel.y
    width: hs.panel.w
    height: hs.panel.h
    visible: hs.fv > 0.002
    opacity: Math.min(1, hs.fv)
    readonly property real s: Theme.reduceMotion ? 1 : hs.mt.motion.growFrom + (1 - hs.mt.motion.growFrom) * hs.fv
    transform: Scale { origin.x: hs.folderFrom.x - hs.panel.x; origin.y: hs.folderFrom.y - hs.panel.y; xScale: folderPanel.s; yScale: folderPanel.s * folderPanel.s }
    Glass {
      anchors.fill: parent
      radius: hs.mt.glass.dialogRadius
      rim: pal.rim
      wallSource: hs.wallSource
      wallRect: hs.wallRect
      origin: Qt.point(hs.panel.x, hs.panel.y)
    }
    TextInput {
      id: nameField
      x: hs.mt.folder.pad
      y: hs.mt.folder.nameTop
      width: parent.width - 2 * hs.mt.folder.pad
      horizontalAlignment: TextInput.AlignHCenter
      font.family: "Roboto"
      font.pixelSize: hs.mt.type.h6
      font.weight: Font.Medium
      color: pal.text
      selectionColor: pal.press
      selectedTextColor: pal.text
      clip: true
      text: hs.folderShownId ? hs.nameOf(hs.folderShownId) : ""
      onAccepted: hs.commitName()
      onActiveFocusChanged: if (!activeFocus) hs.commitName()
    }
    Repeater {
      id: folderGrid
      model: ScriptModel { values: hs.fItemsShown; objectProp: "id" }
      Item {
        id: fcell
        required property var modelData
        required property int index
        readonly property string appId: modelData.id
        readonly property bool held: hs.dragId === appId
        property alias face: fimg
        Spring { id: fx; reduced: Theme.reduceMotion; preset: Theme.spring("snappy"); target: hs.mt.folder.pad + (fcell.index % hs.panel.cols) * hs.geo.cellW }
        Spring { id: fy; reduced: Theme.reduceMotion; preset: Theme.spring("snappy"); target: hs.mt.folder.titleH + Math.floor(fcell.index / hs.panel.cols) * hs.geo.cellH }
        Component.onCompleted: { fx.snap(fx.target); fy.snap(fy.target) }
        x: fx.value
        y: fy.value
        width: hs.geo.cellW
        height: hs.geo.cellH
        Rectangle {
          x: (parent.width - width) / 2
          y: hs.geo.iconY - hs.mg.tilePad
          width: Math.min(hs.geo.cellW, Math.max(hs.geo.icon, fname.paintedWidth) + 2 * hs.mg.tilePad)
          height: hs.geo.icon + hs.mg.labelGap + hs.geo.labelH + 2 * hs.mg.tilePad
          radius: hs.mg.pressRadius
          color: pal.dk ? hs.mt.color.rippleOnWall : hs.mt.color.rippleLight
          opacity: hs.pressedId === fcell.appId && !fcell.held ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: hs.pressedId === fcell.appId ? hs.mt.motion.enter : hs.mt.motion.exit } }
        }
        Image {
          id: fimg
          x: (parent.width - width) / 2
          y: hs.geo.iconY
          width: hs.geo.icon
          height: width
          opacity: fcell.held ? 0 : 1
          source: fcell.modelData.icon || ""
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          asynchronous: true
          scale: VIconMetrics.scale(source)
        }
        MText {
          id: fname
          y: fimg.y + fimg.height + hs.mg.labelGap
          width: hs.geo.cellW - hs.mg.labelInset
          height: hs.geo.labelH
          x: (parent.width - width) / 2
          horizontalAlignment: Text.AlignHCenter
          text: fcell.modelData.name || ""
          color: pal.text
          opacity: fcell.held ? 0 : 1
        }
      }
    }
  }
  function commitName() {
    if (!folderShownId) return
    var key = HM.folderKey(folderShownId), name = nameField.text.trim() || "Folder"
    var f = layout.folders[key]
    if (f && f.name !== name) renamed(key, name)
    if (nameField.activeFocus) nameField.focus = false
  }
  // Rename (the folder's menu) and the IPC: the name field takes the keyboard, all of it selected
  function renameFocus() {
    if (!openFolder) return
    nameField.forceActiveFocus()
    nameField.selectAll()
  }
  function nameRect() { return { x: panel.x + nameField.x, y: panel.y + nameField.y, w: nameField.width, h: nameField.height } }

  // ================================================================ the item in the hand
  property string dragId: ""
  property string dragKind: ""       // app | folder | widget
  property string dragFrom: ""       // grid | dock | folder
  property var dragOrder: []
  property var dragHot: []
  property var fOrder: []
  property string aimId: ""
  property bool aimArmed: false
  property string dropTarget: ""
  property bool landing: false
  property bool landFade: false
  property real heldW: 0
  property real heldH: 0
  property string heldIcon: ""
  property bool heldCopy: false      // a folder or widget: a snapshot of its face goes into the hand
  Spring { id: hx; reduced: Theme.reduceMotion; preset: Theme.spring("snappy") }
  Spring { id: hy; reduced: Theme.reduceMotion; preset: Theme.spring("snappy") }
  Spring { id: hScale; reduced: Theme.reduceMotion; preset: Theme.spring("snappy"); target: hs.landing ? (hs.landFade ? hs.mg.landScale : 1) : hs.mg.dragScale }
  function placeHeld(x, y) { hx.target = x; hx.snap(x); hy.target = y; hy.snap(y) }
  Item {
    id: heldItem
    x: hx.value
    y: hy.value
    width: hs.heldW
    height: hs.heldH
    visible: hs.dragging
    scale: hScale.value
    opacity: hs.landing && hs.landFade ? 0 : 1
    Behavior on opacity { NumberAnimation { duration: hs.mt.motion.exit } }
    RectangularShadow {
      anchors.fill: parent
      visible: !hs.heldCopy || hs.dragKind === "folder"
      anchors.margins: hs.dragKind === "folder" ? parent.width * (1 - Theme.core.surface.appIcon.content) / 2 : parent.width * (1 - VIconMetrics.scale(heldImg.source)) / 2
      offset.y: hs.mg.tilePad
      blur: 2 * hs.mg.tilePad
      radius: width * hs.hm.iconRadius
      color: hs.mt.color.dragShadow
    }
    Image {
      id: heldImg
      anchors.fill: parent
      visible: !hs.heldCopy
      source: hs.heldIcon
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      scale: VIconMetrics.scale(source)
    }
    ShaderEffectSource {
      id: heldShot
      anchors.fill: parent
      visible: hs.heldCopy
      live: false
      hideSource: hs.heldCopy && hs.dragging
    }
  }
  Timer {
    id: landTimer
    interval: hs.mt.time.land
    onTriggered: hs.endDrag()
  }
  function endDrag() {
    landTimer.stop()
    heldShot.sourceItem = null
    dragId = ""; dragKind = ""; dragFrom = ""; dragOrder = []; dragHot = []; fOrder = []
    aimId = ""; aimArmed = false; dropTarget = ""; landing = false; landFade = false; heldCopy = false
  }
  function land(r, fade) {
    landFade = !!fade
    landing = true
    if (r) { hx.target = r.x + (r.w - heldW) / 2; hy.target = r.y + (r.h - heldH) / 2 }
    landTimer.restart()
  }

  // ================================================================ menus
  property bool menuOpen: false
  property string menuKind: ""       // app | folder | home
  property string menuId: ""
  property string menuWhere: ""
  MaterialMenu {
    id: menu
    anchors.fill: parent
    pal: pal
    open: hs.menuOpen
    wallSource: hs.wallSource
    wallRect: hs.wallRect
    onChosen: function (key) { hs.choose(key) }
  }
  function openMenu(kind, id, where, rect, x, y) {
    var spec = kind === "home" ? menuFor("", "home") : menuFor(id, where)
    if (!spec) return false
    menu.header = spec.header || null
    menu.rows = spec.rows || []
    menu.tiles = spec.tiles || []
    menu.anchor = rect ? { x: rect.x, y: rect.y, w: rect.w, h: rect.h } : { x: x, y: y }
    menuKind = kind; menuId = id; menuWhere = where
    menuOpen = true
    return true
  }
  function choose(key) {
    var kind = menuKind, id = menuId
    menuOpen = false
    if (!key) return
    if (key === "rename") { folderRequested(id); renameLater.restart(); return }
    if (key === "removeFolder") {
      removeRequested([id].concat(folderItems(id).map(function (a) { return a.id })), nameOf(id))
      return
    }
    menuChosen(kind === "home" ? "" : id, key)
  }
  Timer { id: renameLater; interval: 0; onTriggered: hs.renameFocus() }

  // ================================================================ one finger, one gesture
  property string pressedId: ""
  function hitAt(x, y) {
    if (openFolder) {
      var items = fItemsShown
      for (var i = 0; i < items.length; i++) {
        var r = MM.folderItem(i, panel, geo, mt)
        if (x >= r.x - geo.iconX && x <= r.x + geo.icon + geo.iconX && y >= r.y && y <= r.y + geo.icon + mg.labelGap + geo.labelH)
          return { id: items[i].id, where: "folder", kind: "app", rect: { x: r.x, y: r.y, w: geo.icon, h: geo.icon } }
      }
      return null
    }
    for (var j = 0; j < shownOrder.length; j++) {
      var id = shownOrder[j]
      if (HM.isBreak(id)) continue
      var t = tileRect(id)
      if (!t || t.page !== page) continue
      var wide = HM.isWidget(id), ex = wide ? 0 : geo.iconX
      if (x >= t.x - ex && x <= t.x + t.w + ex && y >= t.y && y <= t.y + t.h + (wide ? 0 : mg.labelGap + geo.labelH))
        return { id: id, where: "grid", kind: HM.isFolder(id) ? "folder" : wide ? "widget" : "app", rect: t }
    }
    for (var k = 0; k < shownHot.length; k++) {
      var h = hotRect(shownHot[k])
      if (x >= h.x - geo.iconX && x <= h.x + h.w + geo.iconX && y >= geo.hotseatTop && y <= geo.hotseatTop + geo.hotseatH)
        return { id: shownHot[k], where: "dock", kind: "app", rect: h }
    }
    return null
  }
  // the face of an item on screen (its delegate's), for the snapshot in the hand
  function faceOf(id, where) {
    var rep = where === "dock" ? hotRep : where === "folder" ? folderGrid : grid
    for (var i = 0; i < rep.count; i++) { var d = rep.itemAt(i); if (d && d.appId === id) return d.face }
    return null
  }
  function startDrag(t) {
    hold.stop()
    menuOpen = false
    pressedId = ""
    finger.kind = "drag"
    finger.grabX = finger.x0 - t.rect.x
    finger.grabY = finger.y0 - t.rect.y
    finger.want = ""
    finger.edge = 0
    heldW = t.rect.w; heldH = t.rect.h
    heldIcon = t.kind === "app" ? iconOf(t.id) : ""
    heldCopy = t.kind !== "app"
    if (heldCopy) { heldShot.sourceItem = faceOf(t.id, t.where); heldShot.scheduleUpdate() }
    placeHeld(t.rect.x, t.rect.y)
    landing = false
    dragOrder = layout.order.slice()
    dragHot = layout.hotseat.slice()
    fOrder = t.where === "folder" ? fItemsShown.map(function (a) { return a.id }) : []
    dragKind = t.kind
    dragFrom = t.where
    dropTarget = ""
    aimId = ""; aimArmed = false
    dragId = t.id
  }
  function dragMove(x, y) {
    placeHeld(x - finger.grabX, y - finger.grabY)
    var t = MM.targetAt(targets, x, y, geo)
    if (t !== dropTarget) dropTarget = t
    if (t) { reorder.stop(); merge.stop(); edgeTimer.stop(); finger.edge = 0; finger.want = ""; aimId = ""; aimArmed = false; return }
    if (dragFrom === "folder") {
      if (MM.inRect(panel, x, y)) {
        var fi = MM.folderSlot(x, y, fOrder.length, panel, geo, mt)
        if ("f" + fi !== finger.want) { finger.want = "f" + fi; reorder.kind = "folder"; reorder.idx = fi; reorder.restart() }
        return
      }
      // out of the folder: it closes, the app stays in the hand (a folder of one becomes that app)
      reorder.stop()
      finger.want = ""
      var r = MM.takeOut({ order: layout.order, folders: layout.folders, hotseat: layout.hotseat }, dragId)
      dragFrom = "grid"
      dragOrder = MM.moveTo(r.layout.order, dragId, r.at)
      dragHot = r.layout.hotseat
      fOrder = []
      arranged(r.layout)
      folderRequested("")
      return
    }
    var cx = hx.value + heldW / 2, cy = hy.value + heldH / 2
    var inDock = dragKind === "app" && MM.overHotseat(y, geo, mg.tilePad)
    var edge = inDock ? 0 : x < width * mg.edgeZone ? -1 : x > width * (1 - mg.edgeZone) ? 1 : 0
    if (edge !== finger.edge) { finger.edge = edge; edgeTimer.stop(); if (edge) edgeTimer.start() }
    if (inDock) {
      if (aimId) { merge.stop(); aimId = ""; aimArmed = false }
      if (!MM.hotseatRoom(dragHot, dragId, mg.hotseatMax)) return
      var w = "dock:" + MM.hotseatSlot(dragHot, dragId, x, geo)
      if (w !== finger.want) { finger.want = w; reorder.kind = "dock"; reorder.restart() }
      return
    }
    // over another icon: a folder (apps only, never onto a widget)
    var aim = ""
    if (dragKind === "app") {
      for (var i = 0; i < shownOrder.length && !aim; i++) {
        var id = shownOrder[i]
        if (id === dragId || HM.isBreak(id) || HM.isWidget(id)) continue
        var q = tileRect(id)
        if (q && q.page === page && Math.hypot(cx - q.x - q.w / 2, cy - q.y - q.h / 2) < mg.folderZone * geo.icon) aim = id
      }
    }
    if (aim) {
      reorder.stop()
      finger.want = ""
      if (aimId !== aim) { aimId = aim; aimArmed = false; merge.restart() }
      return
    }
    if (aimId) { merge.stop(); aimId = ""; aimArmed = false }
    var shown = dragOrder.filter(function (o) { return hs.shows(o) })
    var idx = HM.dropAt(shown, dragId, cx, cy, page, spanOf, geo, geo.cellW, geo.cellH)
    var want = "grid:" + page + ":" + idx
    if (want !== finger.want) { finger.want = want; reorder.kind = "grid"; reorder.idx = idx; reorder.restart() }
  }
  Timer {
    id: reorder
    property string kind: ""
    property int idx: 0
    interval: hs.mt.time.reorderDwell
    onTriggered: {
      if (!hs.dragging) return
      var id = hs.dragId
      if (kind === "folder") hs.fOrder = MM.moveTo(hs.fOrder, id, idx)
      else if (kind === "dock") {
        var slot = MM.hotseatSlot(hs.dragHot, id, finger.x, hs.geo)
        hs.dragOrder = HM.normalizeBreaks(hs.dragOrder.filter(function (x) { return x !== id }))
        hs.dragHot = MM.moveTo(hs.dragHot.filter(function (x) { return x !== id }), id, slot)
      } else {
        hs.dragOrder = HM.normalizeBreaks(MM.insertAt(hs.dragOrder, id, idx, hs.shows))
        hs.dragHot = hs.dragHot.filter(function (x) { return x !== id })
      }
    }
  }
  Timer { id: merge; interval: hs.mt.time.folderDwell; onTriggered: if (hs.dragging && hs.aimId) hs.aimArmed = true }
  Timer {
    id: edgeTimer
    interval: hs.mt.time.edgeDwell
    repeat: true
    onTriggered: hs.edgeTurn(finger.edge)
  }
  function edgeTurn(dir) {
    if (!dragging || !dir) return
    if (dir > 0 && page === pages - 1) {
      // past the last page: a new one (Launcher3 adds an empty screen while dragging) — not when the
      // held item is all the last page has
      var rest = dragOrder.filter(function (x) { return x !== hs.dragId && hs.shows(x) })
      if (HM.pageCount(HM.place(rest, spanOf, geo.cols, geo.rows)) < pages) return
      var id = dragId
      dragOrder = dragOrder.filter(function (x) { return x !== id }).concat([HM.PAGE_BREAK, id])
      dragHot = dragHot.filter(function (x) { return x !== id })
      turnPage(1)
      return
    }
    var next = Math.max(0, Math.min(pages - 1, page + dir))
    if (next !== page) turnPage(next - page)
  }
  // a page turned under a held item: the slot under it is on the new page
  onPageChanged: if (dragging && finger.kind === "drag") Qt.callLater(function () { if (hs.dragging && finger.kind === "drag") { finger.want = ""; hs.dragMove(finger.x, finger.y) } })
  function drop() {
    reorder.stop(); merge.stop(); edgeTimer.stop(); finger.edge = 0
    if (!dragging) return
    var id = dragId
    if (dropTarget === "remove") {
      var ids = HM.isFolder(id) ? [id].concat(folderItems(id).map(function (a) { return a.id })) : [id]
      removeRequested(ids, nameOf(id))
      land(null, true)
      return
    }
    if (dropTarget === "uninstall") {
      uninstallRequested(id, nameOf(id))
      endDrag()
      return
    }
    if (dragFrom === "folder") {
      var key = HM.folderKey(folderShownId), f = layout.folders[key]
      var all = f ? f.items : []
      var nextItems = fOrder.concat(all.filter(function (x) { return hs.fOrder.indexOf(x) < 0 }))
      var folders = {}
      for (var k in layout.folders) folders[k] = { name: layout.folders[k].name, items: k === key ? nextItems : layout.folders[k].items.slice() }
      var at = fOrder.indexOf(id)
      arranged({ order: layout.order.slice(), folders: folders, hotseat: layout.hotseat.slice() })
      var fr = MM.folderItem(Math.max(0, at), panel, geo, mt)
      land({ x: fr.x, y: fr.y, w: geo.icon, h: geo.icon }, false)
      return
    }
    if (aimArmed && aimId) {
      var target = aimId, tr = tileRect(target)
      var ids2 = HM.isFolder(target) ? folderItems(target).map(function (a) { return a.id }).concat([id]) : [target, id]
      arranged(MM.fold({ order: dragOrder, folders: layout.folders, hotseat: dragHot }, id, target, nameFolder(ids2)))
      land(tr, true)
      return
    }
    var o, dk
    if (dragKind === "app" && MM.overHotseat(finger.y, geo, mg.tilePad) && MM.hotseatRoom(dragHot, id, mg.hotseatMax)) {
      o = HM.normalizeBreaks(dragOrder.filter(function (x) { return x !== id }))
      dk = MM.moveTo(dragHot.filter(function (x) { return x !== id }), id, MM.hotseatSlot(dragHot, id, finger.x, geo))
    } else {
      var shown = dragOrder.filter(function (x) { return hs.shows(x) })
      o = HM.normalizeBreaks(MM.insertAt(dragOrder, id, HM.dropAt(shown, id, hx.value + heldW / 2, hy.value + heldH / 2, page, spanOf, geo, geo.cellW, geo.cellH), shows))
      dk = dragHot.filter(function (x) { return x !== id })
    }
    dragOrder = o
    dragHot = dk
    dropTarget = ""
    arranged({ order: o, folders: layout.folders, hotseat: dk })
    if (dk.indexOf(id) >= 0) {
      var vis = dk.filter(function (x) { return !!hs.appMap[x] || x === id })
      land({ x: MM.hotseatX(vis.indexOf(id), vis.length, geo), y: geo.hotseatY + dockShift, w: geo.icon, h: geo.icon }, false)
      return
    }
    var vo = o.filter(function (x) { return hs.shows(x) })
    var c = HM.place(vo, spanOf, geo.cols, geo.rows)[vo.indexOf(id)]
    if (c && c.page !== page) turnPage(c.page - page)
    var wide = HM.isWidget(id)
    land(c ? { x: MM.cellX(c, geo) - c.page * width + geo.iconX, y: MM.cellY(c, geo) + geo.iconY, w: heldW, h: heldH } : null, !c)
  }

  Timer {
    id: hold
    interval: hs.mt.time.longPress
    onTriggered: {
      if (finger.kind !== "" || !finger.down0) return
      finger.held = true
      var t = finger.target
      if (!t) { finger.kind = "done"; hs.openMenu("home", "", "home", null, finger.x0, finger.y0); return }
      if (t.kind === "app" || t.kind === "folder") {
        hs.pressedId = ""
        if (hs.openMenu(t.kind, t.id, t.where, t.rect)) { finger.kind = "held"; return }
      }
      hs.startDrag(t)   // a widget goes straight into the hand
      hs.dragMove(finger.x, finger.y)
    }
  }
  QtObject {
    id: finger
    property real x0: 0
    property real y0: 0
    property real x: 0
    property real y: 0
    property bool down0: false
    property bool held: false
    property string kind: ""         // "" undecided | held | done | drag | pan | none | menu | swallow | beside | search | name
    property var target: null
    property var samples: []
    property real grabX: 0
    property real grabY: 0
    property string want: ""
    property int edge: 0
    // touches from the iPad cast come in steps (~44 ms): moves are resampled to one per frame
    // (Resample.js, fed by fingerFeed); the real last point goes in before the lift
    property var rs: null
    property real fx: 0
    property real fy: 0
    property real rx: 0
    property real ry: 0
    function move(px, py) { if (!down0 || !rs) return; rx = px; ry = py; rs.push(Date.now(), px, py) }
    function feed() {
      var a = rs ? rs.at(Date.now()) : null
      if (a && (a.x !== fx || a.y !== fy)) { fx = a.x; fy = a.y; moveNow(a.x, a.y) }
    }
    function down(px, py) {
      rs = Resample.create(hs.tt.cast.resampleMinGap, hs.tt.cast.resampleMaxGap)
      rs.push(Date.now(), px, py); fx = px; fy = py; rx = px; ry = py
      x0 = px; y0 = py; x = px; y = py; down0 = true; held = false; target = null; samples = [[Date.now(), px, py]]
      kind = ""
      if (hs.landing) hs.endDrag()
      if (hs.menuOpen) {
        if (menu.contains(px, py)) { kind = "menu"; menu.hot = menu.keyAt(px, py) }
        else { kind = "swallow"; hs.menuOpen = false }    // a tap beside the menu closes it
        return
      }
      if (hs.openFolder && MM.inRect(hs.nameRect(), px, py)) { kind = "name"; return }
      if (nameField.activeFocus) hs.commitName()
      if (!hs.openFolder && MM.inRect(hs.geo.search, px, py)) { kind = "search"; return }
      if (hs.openFolder && !MM.inRect(hs.panel, px, py)) { kind = "beside"; return }
      target = hs.hitAt(px, py)
      hs.pressedId = target ? target.id : ""
      hold.restart()
    }
    function moveNow(px, py) {
      if (!down0) return
      x = px; y = py
      var t = Date.now(), list = samples.concat([[t, px, py]])
      while (list.length > 2 && t - list[0][0] > hs.mt.time.sampleWindow) list.shift()
      samples = list
      var far = Math.hypot(px - x0, py - y0) > hs.mt.time.slop
      if (kind === "drag") { hs.dragMove(px, py); return }
      if (kind === "menu") { menu.hot = menu.keyAt(px, py); return }
      if (kind === "held" && far) { hs.startDrag(target); hs.dragMove(px, py); return }
      if (kind === "pan") { hs.pageMoved(px - x0, t); return }
      if (kind === "drawer") { hs.drawerDrag(Math.max(0, y0 - py)); return }
      if ((kind === "search" || kind === "name") && far) { kind = "none"; return }
      if (kind === "" && far) {
        hold.stop()
        hs.pressedId = ""
        // up on the home screen (not in a folder): All apps come with the finger (the lab's swipe up)
        kind = hs.openFolder ? "none" : y0 - py > Math.abs(px - x0) ? "drawer" : Math.abs(px - x0) > Math.abs(py - y0) ? "pan" : "none"
        if (kind === "pan") hs.pageMoved(px - x0, t)
        if (kind === "drawer") hs.drawerDrag(Math.max(0, y0 - py))
      }
    }
    function up() {
      if (!down0) return
      if (rx !== fx || ry !== fy) moveNow(rx, ry)
      down0 = false
      hold.stop()
      Qt.callLater(hs.releaseKeys)
      var k = kind, t = target
      kind = ""
      hs.pressedId = ""
      if (k === "drag") { hs.drop(); return }
      if (k === "pan") { hs.pageReleased(MM.speed(samples, Date.now(), hs.mt.time.sampleWindow)); return }
      if (k === "drawer") { hs.drawerRelease(-MM.speedY(samples, Date.now(), hs.mt.time.sampleWindow)); return }
      if (k === "menu") { var key = menu.keyAt(x, y); menu.hot = ""; if (key) hs.choose(key); return }
      if (k === "beside") { hs.folderRequested(""); return }
      if (k === "search") { hs.searchRequested(); return }
      if (k === "name") { hs.renameFocus(); return }
      if (k !== "" || !t) return
      if (t.kind === "folder") { hs.folderRequested(t.id); return }
      if (t.kind === "widget") { hs.widgetTapped(t.id, ""); return }
      hs.tapped(t.id)
    }
    function cancel() {
      hold.stop()
      if (!down0) return
      down0 = false
      Qt.callLater(hs.releaseKeys)
      var k = kind
      kind = ""
      hs.pressedId = ""
      menu.hot = ""
      if (k === "drag") hs.drop()
      else if (k === "pan") hs.pageReleased(0)
      else if (k === "drawer") hs.drawerRelease(0)
    }
  }
  FrameAnimation { id: fingerFeed; running: finger.down0; onTriggered: finger.feed() }
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

  // ================================================================ snackbar (Undo)
  property var snackShown: null
  property real snackV: 0
  NumberAnimation { id: snackAnim; target: hs; property: "snackV" }
  onSnackChanged: {
    snackAnim.stop()
    if (snack) { snackShown = snack; snackAnim.to = 1; snackAnim.duration = Theme.reduceMotion ? 0 : mt.motion.enter; snackAnim.easing.type = Easing.BezierSpline; snackAnim.easing.bezierCurve = mt.motion.easeOut }
    else { snackAnim.to = 0; snackAnim.duration = Theme.reduceMotion ? 0 : mt.motion.exit; snackAnim.easing.type = Easing.BezierSpline; snackAnim.easing.bezierCurve = mt.motion.sharp }
    snackAnim.start()
  }
  Item {
    id: snackBar
    visible: hs.interactive && hs.snackV > 0.002
    opacity: Math.min(1, hs.snackV)
    width: Math.min(hs.width - 2 * hs.mg.edge, Math.max(hs.mt.snack.minWidth, snackText.implicitWidth + 2 * hs.mt.snack.padX + (undoBtn.visible ? undoBtn.width + hs.mt.snack.gap : 0)))
    height: hs.mt.snack.height
    x: hs.mt.snack.left
    y: hs.height - hs.mt.snack.bottom - height
    readonly property real s: Theme.reduceMotion ? 1 : hs.mt.motion.growFrom + (1 - hs.mt.motion.growFrom) * hs.snackV
    transform: Scale { origin.x: snackBar.width / 2; origin.y: snackBar.height / 2; xScale: snackBar.s; yScale: snackBar.s }
    VShadow { layers: Theme.r.popover.shadow; radius: hs.mt.glass.snackRadius }
    Rectangle { anchors.fill: parent; radius: hs.mt.glass.snackRadius; color: pal.snack }
    MText {
      id: snackText
      x: hs.mt.snack.padX
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x - hs.mt.snack.padX - (undoBtn.visible ? undoBtn.width + hs.mt.snack.gap : 0)
      text: hs.snackShown ? hs.snackShown.text : ""
      color: pal.onSnack
    }
    Item {
      id: undoBtn
      visible: !!(hs.snackShown && hs.snackShown.undo)
      width: undoText.implicitWidth + 2 * hs.mt.drop.textPadX
      height: hs.mt.drop.button
      x: parent.width - width - hs.mt.drop.textPadX
      anchors.verticalCenter: parent.verticalCenter
      Rectangle { anchors.fill: parent; radius: height / 2; color: pal.tint; opacity: undoArea.pressed ? 1 : 0 }
      MText {
        id: undoText
        anchors.centerIn: parent
        text: "Undo"
        font.pixelSize: hs.mt.type.button
        font.weight: Font.Medium
        color: pal.primary
      }
      MouseArea { id: undoArea; anchors.fill: parent; anchors.margins: -hs.mg.tilePad; onClicked: hs.undoRequested() }
    }
  }
  function undoPoint() { return undoBtn.visible && snackBar.visible ? { x: snackBar.x + undoBtn.x + undoBtn.width / 2, y: snackBar.y + undoBtn.y + undoBtn.height / 2 } : null }

  // ================================================================ the Uninstall dialog
  property var confirmShown: null
  property real dialogV: 0
  NumberAnimation { id: dialogAnim; target: hs; property: "dialogV" }
  onConfirmChanged: {
    dialogAnim.stop()
    if (confirm) { confirmShown = confirm; dialogAnim.to = 1; dialogAnim.duration = Theme.reduceMotion ? 0 : mt.motion.enter }
    else { dialogAnim.to = 0; dialogAnim.duration = Theme.reduceMotion ? 0 : mt.motion.exit }
    dialogAnim.easing.type = Easing.BezierSpline
    dialogAnim.easing.bezierCurve = confirm ? mt.motion.easeOut : mt.motion.sharp
    dialogAnim.start()
  }
  Item {
    id: dialog
    anchors.fill: parent
    visible: hs.interactive && hs.dialogV > 0.002
    Rectangle { anchors.fill: parent; color: hs.mt.color.scrim; opacity: Math.min(1, hs.dialogV) }
    MouseArea { anchors.fill: parent; enabled: !!hs.confirm; onClicked: hs.confirmed(false) }
    Item {
      id: paperD
      readonly property real w: Math.max(hs.mt.dialog.minWidth, Math.min(hs.mt.dialog.maxWidth, hs.width - 2 * hs.mt.dialog.margin, Math.max(dBody.implicitWidth, dPlan.implicitWidth) + 2 * hs.mt.dialog.padX))
      width: w
      height: dCol.height + hs.mt.dialog.titleY + hs.mt.dialog.textBottom + dActions.height + 2 * hs.mt.dialog.actionsPad
      x: (hs.width - width) / 2
      y: (hs.height - height) / 2
      opacity: Math.min(1, hs.dialogV)
      Glass {
        anchors.fill: parent
        radius: hs.mt.glass.dialogRadius
        rim: pal.rim
        wallSource: hs.wallSource
        wallRect: hs.wallRect
        origin: Qt.point(paperD.x, paperD.y)
      }
      MouseArea { anchors.fill: parent }   // a tap on the dialog is not a tap beside it
      Column {
        id: dCol
        x: hs.mt.dialog.padX
        y: hs.mt.dialog.titleY
        width: parent.width - 2 * hs.mt.dialog.padX
        spacing: hs.mt.dialog.titleY
        MText {
          width: parent.width
          text: hs.confirmShown ? hs.confirmShown.name : ""
          font.pixelSize: hs.mt.type.h6
          font.weight: Font.Medium
          color: pal.text
        }
        MText {
          id: dBody
          width: parent.width
          text: "Do you want to uninstall this app?"
          font.pixelSize: hs.mt.type.body1
          wrapMode: Text.WordWrap
          color: pal.text2
        }
        MText {
          id: dPlan
          width: parent.width
          text: hs.confirmShown ? "Phase 1 runs nothing. It would run: " + (hs.confirmShown.plan || "…") : ""
          font.pixelSize: hs.mt.type.caption
          wrapMode: Text.WordWrap
          elide: Text.ElideNone
          color: pal.text2
        }
      }
      Row {
        id: dActions
        x: parent.width - width - hs.mt.dialog.actionsPad
        y: parent.height - height - hs.mt.dialog.actionsPad
        spacing: hs.mt.dialog.actionsPad
        Repeater {
          model: [{ key: "cancel", text: "Cancel" }, { key: "ok", text: "OK" }]
          Item {
            id: db
            required property var modelData
            width: dbText.implicitWidth + 2 * hs.mt.drop.textPadX
            height: hs.mt.drop.button
            Rectangle { anchors.fill: parent; radius: height / 2; color: pal.press; opacity: dbArea.pressed ? 1 : 0 }
            MText {
              id: dbText
              anchors.centerIn: parent
              text: db.modelData.text
              font.pixelSize: hs.mt.type.button
              font.weight: Font.Medium
              color: pal.primary
            }
            MouseArea { id: dbArea; anchors.fill: parent; onClicked: hs.confirmed(db.modelData.key === "ok") }
          }
        }
      }
    }
  }
  function dialogPoint(which) {
    if (!dialog.visible) return null
    var b = null
    for (var i = 0; i < dActions.children.length; i++) { var c = dActions.children[i]; if (c.modelData && c.modelData.key === which) b = c }
    if (!b) return null
    var p = b.mapToItem(hs, b.width / 2, b.height / 2)
    return { x: p.x, y: p.y }
  }

  // ================================================================ for Home.qml and the tests
  // where an app's icon sits once the home screen has settled, in `item`'s coordinates: the open
  // folder's, the hotseat's, this page's — an app in a closed folder: the folder's plate
  function iconRect(id, item) {
    var r = null
    if (openFolder) {
      var items = fItemsShown
      for (var i = 0; i < items.length; i++) if (items[i].id === id) { var f = MM.folderItem(i, panel, geo, mt); r = { x: f.x, y: f.y, w: geo.icon } }
    }
    if (!r) { var h = hotRect(id); if (h && !openFolder) r = { x: h.x, y: h.y, w: geo.icon } }
    if (!r) {
      var t = tileRect(id)
      if (t && t.page === page) r = HM.isWidget(id) ? { x: t.x, y: t.y, w: Math.min(t.w, t.h) } : { x: t.x, y: t.y, w: geo.icon }
    }
    if (!r) {
      for (var k in layout.folders) {
        if (layout.folders[k].items.indexOf(id) < 0) continue
        var ft = tileRect("folder:" + k), pw = geo.icon * Theme.core.surface.appIcon.content
        if (ft && ft.page === page) r = { x: ft.x + (geo.icon - pw) / 2, y: ft.y + (geo.icon - pw) / 2, w: pw }
      }
    }
    if (!r) return null
    if (r.w === geo.icon && !HM.isWidget(id)) {
      // the icon's visible body (its measured scale)
      var s = VIconMetrics.scale(iconOf(id)), bw = geo.icon * s
      r = { x: r.x + (geo.icon - bw) / 2, y: r.y + (geo.icon - bw) / 2, w: bw }
    }
    var p = hs.mapToItem(item, r.x, r.y)
    return { x: p.x, y: p.y, w: r.w }
  }
  // a named point on this screen (tests): menu:<key|text>, drop:remove|uninstall, snack:undo,
  // dialog:ok|cancel, folder:name, search, hotseat:<i> (a slot's centre), tile:<id>
  function pointOf(what) {
    var s = String(what), i = s.indexOf(":"), kind = i < 0 ? s : s.slice(0, i), arg = i < 0 ? "" : s.slice(i + 1)
    if (kind === "menu") return menu.open ? menu.pointOf(arg) : null
    if (kind === "drop") {
      var n = targets.length, at = targets.indexOf(arg)
      if (at < 0) return arg === "remove" ? { x: width / 4, y: geo.top / 2 } : { x: width * 3 / 4, y: geo.top / 2 }
      return { x: n === 1 ? width / 2 : at === 0 ? width / 4 : width * 3 / 4, y: geo.top / 2 }
    }
    if (kind === "snack") return undoPoint()
    if (kind === "dialog") return dialogPoint(arg)
    if (kind === "folder") { var nr = nameRect(); return openFolder ? { x: nr.x + nr.w / 2, y: nr.y + nr.h / 2 } : null }
    if (kind === "search") return { x: geo.search.x + geo.search.w / 2, y: geo.search.y + geo.search.h / 2 }
    if (kind === "hotseat") { var k = Number(arg) || 0, nn = Math.max(1, shownHot.length + 1); return { x: MM.hotseatX(Math.min(k, nn - 1), nn, geo) + geo.icon / 2, y: geo.hotseatY + geo.icon / 2 } }
    if (kind === "tile") { var t = tileRect(arg); return t ? { x: t.x + t.w / 2, y: t.y + t.h / 2, page: t.page } : null }
    return null
  }
  function probe() {
    return {
      page: page, pages: pages, order: shownOrder, hotseat: shownHot,
      menu: { open: menuOpen, kind: menuKind, id: menuId, keys: (menu.rows || []).concat(menu.tiles || []).map(function (r) { return r.key || "" }).filter(Boolean) },
      drag: { id: dragId, kind: dragKind, from: dragFrom, target: dropTarget, aim: aimId, armed: aimArmed, landing: landing, targets: targets },
      dropBar: dropBar.opacity, snack: snack, dialog: confirm, folder: { open: openFolder, name: nameField.text, focus: nameField.activeFocus, items: fItemsShown.map(function (a) { return a.id }), shown: fv },
      geo: { cols: geo.cols, rows: geo.rows, cellW: geo.cellW, cellH: geo.cellH, top: geo.top, hotseatTop: geo.hotseatTop }
    }
  }
}
