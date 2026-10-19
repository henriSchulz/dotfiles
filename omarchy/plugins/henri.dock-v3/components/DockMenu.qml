import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"
import "../Look.js" as Look
import qs.Commons

// Context menu over a tile (spec §10): glass bubble with an arrow at the
// tile, MenuList inside (instant highlight, blink, keyboard), one level
// of submenus opening beside the row. The dock freezes magnification while
// it is open; Esc and a click anywhere else close it (Reveal).
Item {
  id: menu
  property var dock
  property bool open: false
  property var model: []
  property real anchorMain: 0
  property real anchorCross: 0
  signal activated(var entry)
  signal dismissRequested()

  readonly property bool shown: open || reveal.opacity > 0.001
  readonly property var pal: dock.palette
  readonly property real cardW: Math.max(Theme.m.menu.minWidth, list.implicitWidth + Theme.m.menu.pad * 2)
  readonly property real cardH: list.implicitHeight + Theme.m.menu.pad * 2
  readonly property var r: dock.rectFor(anchorMain, anchorCross,
      dock.horizontal ? cardW : cardH + Style.space(Look.dock.labelArrowH),
      dock.horizontal ? cardH + Style.space(Look.dock.labelArrowH) : cardW)
  readonly property real cx: Math.max(Style.space(6), Math.min(dock.planeWidth - r.w - Style.space(6), r.x))
  readonly property real cy: Math.max(Style.space(6), Math.min(dock.planeHeight - r.h - Style.space(6), r.y))
  x: dock.horizontal ? cx : r.x
  y: dock.horizontal ? r.y : cy
  width: r.w
  height: r.h
  visible: shown

  property int submenuIndex: -1
  property var submenuModel: []
  property real submenuY: 0

  function closeSubmenu() { submenuIndex = -1; list.lockedIndex = -1 }
  onOpenChanged: if (!open) closeSubmenu()

  Reveal {
    id: reveal
    anchors.fill: parent
    kind: "menu"
    open: menu.open
    origin: dock.position === "bottom" ? Item.Bottom : dock.position === "left" ? Item.Left : Item.Right
    fromY: 0
    insideWindows: dock.insideWindows
    closeOnOutsideClick: !dock.testNoGrab
    onDismissRequested: menu.dismissRequested()

    Bubble {
      anchors.fill: parent
      palette: menu.pal
      fill: menu.pal.menu
      radius: Theme.m.radius.menu
      arrowSide: dock.position
      padX: Theme.m.menu.pad
      padY: Theme.m.menu.pad
      arrowAt: dock.horizontal ? (menu.r.x + menu.r.w / 2 - menu.cx) / Math.max(1, menu.r.w)
                               : (menu.r.y + menu.r.h / 2 - menu.cy) / Math.max(1, menu.r.h)
      MenuList {
        id: list
        width: menu.cardW - Theme.m.menu.pad * 2
        model: menu.model
        r: dock.roles
        focus: menu.open
        minWidth: Theme.m.menu.minWidth - Theme.m.menu.pad * 2
        onActivated: function (index, entry) { menu.activated(entry) }
        onSubmenuRequested: function (index, entry, row) {
          menu.submenuModel = entry.submenu
          menu.submenuY = row ? row.y : 0
          menu.submenuIndex = index
          list.lockedIndex = index
        }
        onCurrentIndexChanged: if (currentIndex >= 0 && currentIndex !== menu.submenuIndex && menu.submenuIndex >= 0 && !sub.hovered) menu.closeSubmenu()
        Keys.onLeftPressed: function (e) { if (menu.submenuIndex >= 0) { menu.closeSubmenu(); e.accepted = true } }
      }
    }
  }

  // Submenu beside the parent row (to the right, or left when there is no room)
  Item {
    id: sub
    visible: menu.submenuIndex >= 0 && menu.shown
    readonly property real w: Math.max(Theme.m.menu.minWidth, subList.implicitWidth + Theme.m.menu.pad * 2)
    readonly property real h: subList.implicitHeight + Theme.m.menu.pad * 2
    readonly property bool onRight: menu.x + menu.width + w + Style.space(6) <= dock.planeWidth
    readonly property bool hovered: subHover.hovered
    x: onRight ? menu.width - Style.space(4) : -w + Style.space(4)
    y: Math.max(-menu.y + Style.space(6), Math.min(dock.planeHeight - menu.y - h - Style.space(6), menu.submenuY))
    width: w
    height: h
    opacity: visible ? 1 : 0
    HoverHandler { id: subHover }
    Rectangle {
      anchors.fill: parent
      anchors.topMargin: Style.space(2)
      radius: Theme.m.radius.menu
      color: menu.pal.shadow
      opacity: 0.6
    }
    Rectangle {
      anchors.fill: parent
      radius: Theme.m.radius.menu
      color: !Theme.reduceTransparency ? menu.pal.menu : menu.pal.opaque
      border.width: 1
      border.color: menu.pal.hairline
      antialiasing: true
      MenuList {
        id: subList
        x: Theme.m.menu.pad; y: Theme.m.menu.pad
        width: sub.w - Theme.m.menu.pad * 2
        model: menu.submenuModel
        r: dock.roles
        minWidth: Theme.m.menu.minWidth - Theme.m.menu.pad * 2
        focus: sub.visible
        onActivated: function (index, entry) { menu.activated(entry) }
        Keys.onLeftPressed: function (e) { menu.closeSubmenu(); list.forceActiveFocus(); e.accepted = true }
      }
    }
  }
}
