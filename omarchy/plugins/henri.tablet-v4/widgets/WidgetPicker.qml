import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"
import "Widgets.js" as W

// The widget picker (lab Widgets.jsx WidgetPicker, a MUI bottom Drawer): a sheet from the bottom with
// every widget — the real ones, at their home size, scaled into a square of picker.preview — its name
// and its span (or "On Home screen"); a tap adds it. The sheet is Velum's popover material with its
// shadow (a lab influence), 28 px top corners (Material 3 sheet); it rises on a spring, a tap on the
// backdrop or Escape closes. Closed it is an empty Loader.
//
// API:
//   anchors.fill: <the screen's overlay>
//   open: bool                    the owner opens / closes it
//   cell: size                    one home grid cell, for a widget's home size (cells × cell)
//   sizeOf: function(kind) → { w, h }     optional: its size on the home screen (overrides cell)
//   onScreen: function(kind) → bool       optional: it is on the home screen already
//   signal add(string kind)       a widget was tapped: put it on the home screen (and close)
//   signal closed()               backdrop tap or Escape: set open false
//   info()                        state for tests: { open, shown, items: [kind, …] }
Item {
  id: wp

  property bool open: false
  property size cell: Qt.size(0, 0)
  property var sizeOf: null
  property var onScreen: null
  signal add(string kind)
  signal closed()

  readonly property var w: Theme.core.surface.material.widgets
  readonly property var pk: w.picker
  readonly property string family: w.font[0]

  Spring { id: rise; preset: wp.pk.spring; reduced: Theme.reduceMotion; target: wp.open ? 1 : 0 }
  readonly property real shown: Math.max(0, Math.min(1, rise.value))

  function homeSize(kind) {
    if (wp.sizeOf) { var s = wp.sizeOf(kind); if (s) return s }
    var c = W.span(wp.w.cells, kind)
    return { w: c[0] * wp.cell.width, h: c[1] * wp.cell.height }
  }
  function info() { return { open: wp.open, shown: wp.shown, items: W.kinds.map(function (k) { return k[0] }) } }

  Loader {
    id: body
    anchors.fill: parent
    active: wp.open || rise.moving || rise.value > 0.002
    sourceComponent: Item {
      id: root
      focus: true
      Keys.onEscapePressed: wp.closed()
      Component.onCompleted: forceActiveFocus()

      Rectangle {
        anchors.fill: parent
        color: wp.pk.backdrop
        opacity: wp.shown
      }
      // a tap above the sheet closes (only there: a handler under the sheet would take its taps too)
      Item {
        width: parent.width
        height: sheet.y
        TapHandler { onTapped: wp.closed() }
      }
      Item {
        id: sheet
        width: parent.width
        height: content.implicitHeight + wp.pk.pad + wp.pk.padBottom
        y: parent.height - height
        transform: Translate { y: (1 - wp.shown) * sheet.height }
        // the material runs past the bottom edge by its radius, so only the top corners are round
        VShadow { layers: Theme.r.popover.shadow; radius: wp.pk.radius }
        Rectangle {
          width: parent.width
          height: parent.height + wp.pk.radius
          radius: wp.pk.radius
          color: Theme.reduceTransparency ? Theme.r.popover.bgOpaque : Theme.r.popover.bg
        }
        Column {
          id: content
          x: wp.pk.pad
          y: wp.pk.pad
          width: parent.width - 2 * wp.pk.pad
          spacing: wp.pk.titleGap
          Text {
            text: "Widgets"
            color: Theme.r.popover.ink
            font.family: wp.family
            font.pixelSize: wp.w.type.title
            font.weight: wp.w.weight.medium
          }
          Flickable {
            width: parent.width
            height: items.height
            contentWidth: items.width
            contentHeight: items.height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            Row {
              id: items
              spacing: wp.pk.itemGap
              Repeater {
                model: W.kinds
                Item {
                  id: tile
                  required property var modelData
                  readonly property string kind: modelData[0]
                  readonly property var home: wp.homeSize(kind)
                  readonly property real k: wp.pk.preview / Math.max(1, home.w, home.h)
                  readonly property bool there: wp.onScreen ? !!wp.onScreen(kind) : false
                  width: col.width + 2 * wp.pk.itemPad
                  height: col.height + 2 * wp.pk.itemPad
                  Rectangle {
                    anchors.fill: parent
                    radius: wp.pk.itemRadius
                    color: Theme.r.popover.ink
                    opacity: tap.pressed ? wp.pk.itemPressed : 0
                  }
                  TapHandler { id: tap; onTapped: wp.add(tile.kind) }
                  Column {
                    id: col
                    x: wp.pk.itemPad
                    y: wp.pk.itemPad
                    spacing: wp.pk.labelGap
                    // the real widget at its home size, scaled into the square
                    Item {
                      width: wp.pk.preview
                      height: wp.pk.preview
                      Item {
                        anchors.centerIn: parent
                        width: tile.home.w * tile.k
                        height: tile.home.h * tile.k
                        HomeWidget {
                          kind: tile.kind
                          width: tile.home.w
                          height: tile.home.h
                          scale: tile.k
                          transformOrigin: Item.TopLeft
                        }
                      }
                    }
                    Text {
                      text: tile.modelData[1]
                      color: Theme.r.popover.ink
                      font.family: wp.family
                      font.pixelSize: wp.w.type.body
                      font.weight: wp.w.weight.medium
                    }
                    Text {
                      text: tile.there ? "On Home screen" : W.span(wp.w.cells, tile.kind).join(" × ")
                      color: Theme.r.popover.inkSecondary
                      font.family: wp.family
                      font.pixelSize: wp.w.type.caption
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
