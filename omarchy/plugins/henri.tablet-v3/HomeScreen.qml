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
  property var apps: []          // grid apps: [{ id, name, icon }]
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

  signal tapped(string id)
  signal pageMoved(real x, real t)
  signal pageReleased(real velocity)

  readonly property var g: HM.grid(width, height, cfg)
  readonly property int pages: Math.max(1, Math.ceil(apps.length / g.perPage))
  readonly property real cellW: (width - 2 * g.side) / g.cols
  readonly property real cellH: (height - g.top - g.bottom) / g.rows
  readonly property var lp: Theme.core.surface.launchpad

  // where an app's icon sits once the home screen has settled, in `item`'s coordinates (the dock
  // first, then the page on screen) — not where it is mid-animation: the grid may still be zoomed
  // and the dock still sliding in
  function iconRect(id, item) {
    for (var i = 0; i < dockRow.children.length; i++) {
      var d = dockRow.children[i]
      if (d.appId === id) { var p = d.mapToItem(item, 0, 0); return { x: p.x, y: p.y - hs.dockShift, w: d.width } }
    }
    for (var j = 0; j < grid.count; j++) {
      var t = grid.itemAt(j)
      if (t && t.appId === id && t.pageOf === hs.page) {
        var q = hs.mapToItem(item, -hs.page * hs.width + t.x + t.icon.x, t.y + t.icon.y)
        return { x: q.x, y: q.y, w: t.icon.width }
      }
    }
    return null
  }

  // ---- pages
  Item {
    id: track
    x: hs.pageX
    opacity: hs.gridOpacity
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
        readonly property int pageOf: Math.floor(index / hs.g.perPage)
        readonly property int at: index % hs.g.perPage
        property alias icon: img
        x: pageOf * hs.width + hs.g.side + (at % hs.g.cols) * hs.cellW
        y: hs.g.top + Math.floor(at / hs.g.cols) * hs.cellH
        width: hs.cellW
        height: hs.cellH
        Image {
          id: img
          anchors.horizontalCenter: parent.horizontalCenter
          y: (parent.height - height - hs.cfg.labelGap - name.height) / 2
          width: hs.g.icon
          height: width
          source: tile.modelData.icon
          sourceSize.width: width * 2
          sourceSize.height: height * 2
          asynchronous: true
          scale: hs.pressedId === tile.appId ? hs.cfg.pressScale : 1
          opacity: hs.pressedId === tile.appId ? hs.lp.press : 1
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
    opacity: hs.gridOpacity
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
            scale: hs.pressedId !== "" && hs.pressedId === parent.appId ? hs.cfg.pressScale : 1
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

  // ---- fingers (touch reaches a MouseArea as a synthesized mouse): a tap opens, a drag turns pages
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
  MouseArea {
    anchors.fill: parent
    enabled: hs.interactive
    preventStealing: true
    property real x0: 0
    property real y0: 0
    property bool moved: false
    property var samples: []
    onPressed: function (m) { x0 = m.x; y0 = m.y; moved = false; samples = [[Date.now(), m.x]]; hs.pressedId = hs.appAt(m.x, m.y) }
    onPositionChanged: function (m) {
      var t = Date.now(), list = samples.concat([[t, m.x]])
      while (list.length > 2 && t - list[0][0] > Theme.core.surface.tablet.sampleWindow) list.shift()
      samples = list
      if (!moved && Math.hypot(m.x - x0, m.y - y0) > Theme.core.surface.tablet.slop) { moved = true; hs.pressedId = "" }
      if (moved) hs.pageMoved(m.x - x0, t)
    }
    onReleased: function (m) {
      var id = hs.pressedId
      hs.pressedId = ""
      if (!moved) { if (id) hs.tapped(id); return }
      var a = samples[0], b = samples[samples.length - 1]
      hs.pageReleased(b[0] > a[0] ? (b[1] - a[1]) * 1000 / (b[0] - a[0]) : 0)
    }
    onCanceled: { hs.pressedId = ""; if (moved) hs.pageReleased(0) }
  }
}
