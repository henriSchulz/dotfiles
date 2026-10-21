import QtQuick
import QtQuick.Effects
import "file:///home/henri/.local/share/velum/qml/Velum"
import "Look.js" as Look

// One cell of the grid: an app icon or a folder's plate of mini icons, with
// its title. Purely visual — the Launchpad's single pointer handler does all
// hit-testing, so a drag survives a folder closing under it.
Item {
  id: tile

  // set by the grid
  property bool folder: false
  property string title: ""
  property string iconSource: ""
  property var previews: []          // icon sources of a folder's first apps
  property real iconSize: Look.grid.iconSize
  property bool showTitle: true
  property bool selected: false
  property bool pressed: false
  property bool editing: false
  property bool dragging: false
  property bool dropTarget: false
  property real jiggle: 0            // degrees, driven by the Launchpad's clock
  property string folderColor: ""    // "#rrggbb" or "" (Get Info)
  property string emoji: ""          // shown instead of the mini icons
  property bool picked: false        // Shift-click selection for a new folder
  property string cover: ""          // folder cover image (absolute path)
  property bool workflow: false      // a workflow tile: 2 × 2 minis + a lightning badge
  readonly property bool plate: folder || workflow
  readonly property int miniGrid: workflow ? Look.workflow.previewGrid : Look.folder.previewGrid
  property bool showBadge: editing && !folder

  readonly property var lp: Theme.core.surface.launchpad
  readonly property real body: iconSize * Look.grid.iconBody

  // icon box, relative to the tile; the hit-test uses the same numbers
  readonly property real iconX: (width - iconSize) / 2
  readonly property real iconY: 0

  Accessible.role: Accessible.Button
  Accessible.name: folder ? title + ", folder" : (workflow ? title + ", workflow" : title)

  scale: dragging ? lp.dragScale : (dropTarget ? lp.folderTarget : (pressed ? Look.grid.pressedScale : 1))
  Behavior on scale { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
  opacity: dragging ? lp.dragOpacity : 1
  transformOrigin: Item.Top

  // the keyboard selection plate behind icon and title
  Rectangle {
    visible: tile.selected && !tile.dragging
    x: tile.iconX - Look.folder.previewGap * tile.iconSize * 2
    y: -Look.folder.previewGap * tile.iconSize * 2
    width: tile.iconSize + Look.folder.previewGap * tile.iconSize * 4
    height: tile.iconSize + (tile.showTitle ? Look.grid.labelGap + label.height : 0) + Look.folder.previewGap * tile.iconSize * 4
    radius: Theme.m.radius.panel
    color: tile.lp.selection
  }

  Item {
    id: art
    x: tile.iconX; y: tile.iconY
    width: tile.iconSize; height: tile.iconSize
    rotation: tile.jiggle

    // app icon
    Image {
      visible: !tile.plate
      anchors.centerIn: parent
      width: tile.body; height: tile.body
      sourceSize.width: Math.ceil(tile.body * 2); sourceSize.height: Math.ceil(tile.body * 2)
      source: tile.plate ? "" : tile.iconSource
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      smooth: true; mipmap: true
      layer.enabled: tile.pressed
      layer.effect: MultiEffect { brightness: tile.lp.press - 1 }
    }

    // folder: plate + 3 × 3 mini icons
    Rectangle {
      id: plateRect
      visible: tile.plate
      anchors.centerIn: parent
      width: tile.body; height: tile.body
      radius: tile.iconSize * Look.folder.tileRadius
      // "#rrggbb" + the tint as alpha → "#aarrggbb"
      color: tile.folderColor !== "" ? "#" + ("0" + Math.round(tile.lp.folderTint * 255).toString(16)).slice(-2) + tile.folderColor.slice(1) : tile.lp.folderTile
      // cover image, clipped to the plate's rounded shape
      Image {
        id: coverImg
        visible: tile.cover !== ""
        anchors.fill: parent
        source: tile.cover !== "" ? "file://" + tile.cover : ""
        sourceSize.width: Math.ceil(tile.body * 2); sourceSize.height: Math.ceil(tile.body * 2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        layer.enabled: visible
        layer.effect: MultiEffect { maskEnabled: true; maskSource: coverMask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
      }
      Rectangle { id: coverMask; anchors.fill: parent; radius: parent.radius; visible: false; layer.enabled: true }
      Text {
        visible: tile.emoji !== "" && tile.cover === ""
        anchors.centerIn: parent
        text: tile.emoji
        font.pixelSize: tile.body * Look.folder.emojiSize
      }
      Grid {
        visible: tile.emoji === "" && tile.cover === ""
        anchors.centerIn: parent
        columns: tile.miniGrid
        spacing: tile.iconSize * Look.folder.previewGap
        readonly property real cell: (tile.body - 2 * tile.iconSize * Look.folder.tileInset
                                      - (tile.miniGrid - 1) * spacing) / tile.miniGrid
        Repeater {
          model: tile.plate ? tile.previews.slice(0, tile.miniGrid * tile.miniGrid) : []
          Image {
            required property var modelData
            width: parent.cell; height: parent.cell
            sourceSize.width: Math.ceil(parent.cell * 2); sourceSize.height: Math.ceil(parent.cell * 2)
            source: modelData
            fillMode: Image.PreserveAspectFit
            asynchronous: true; smooth: true; mipmap: true
          }
        }
      }
    }

    // workflow: a lightning badge on the bottom-right corner
    Rectangle {
      visible: tile.workflow && !tile.picked
      x: tile.iconSize - Look.badge.size - (tile.iconSize - tile.body) / 2 - tile.iconSize * Look.badge.offset
      y: tile.iconSize - Look.badge.size - (tile.iconSize - tile.body) / 2 - tile.iconSize * Look.badge.offset
      width: Look.badge.size; height: Look.badge.size
      radius: width / 2
      color: tile.lp.pick
      VIcon { anchors.centerIn: parent; name: "workflow"; weight: "fill"; size: Look.badge.glyph; color: tile.lp.badgeInk }
    }

    // Shift-click pick: a check on the bottom-right corner
    Rectangle {
      visible: tile.picked && !tile.dragging
      x: tile.iconSize - Look.badge.size - (tile.iconSize - tile.body) / 2 - tile.iconSize * Look.badge.offset
      y: tile.iconSize - Look.badge.size - (tile.iconSize - tile.body) / 2 - tile.iconSize * Look.badge.offset
      width: Look.badge.size; height: Look.badge.size
      radius: width / 2
      color: tile.lp.pick
      VIcon { anchors.centerIn: parent; name: "check"; weight: "bold"; size: Look.badge.glyph; color: tile.lp.badgeInk }
    }

    // edit mode: the round "hide" badge on the top-left corner
    Rectangle {
      visible: tile.showBadge && !tile.dragging
      x: tile.iconSize * Look.badge.offset + (tile.iconSize - tile.body) / 2
      y: tile.iconSize * Look.badge.offset + (tile.iconSize - tile.body) / 2
      width: Look.badge.size; height: Look.badge.size
      radius: width / 2
      color: tile.lp.badge
      VIcon { anchors.centerIn: parent; name: "minus"; weight: "bold"; size: Look.badge.glyph; color: tile.lp.badgeInk }
    }
  }

  Text {
    id: label
    visible: tile.showTitle && !tile.dragging
    anchors.horizontalCenter: parent.horizontalCenter
    y: tile.iconSize + Look.grid.labelGap
    width: Math.min(tile.width, tile.iconSize * Look.grid.labelMaxFactor)
    horizontalAlignment: Text.AlignHCenter
    elide: Text.ElideRight
    maximumLineCount: Look.grid.labelLines
    text: tile.title
    color: tile.lp.label
    font.family: Theme.font
    font.pixelSize: Theme.core.type.callout
    font.weight: Font.Medium
    layer.enabled: true
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: tile.lp.labelShadow[0].color
      shadowVerticalOffset: tile.lp.labelShadow[0].offsetY
      shadowHorizontalOffset: tile.lp.labelShadow[0].offsetX
      // shadowBlur is a fraction of blurMax: 2 × the token's blur radius at 0.5 = the radius
      blurMax: Math.max(1, Math.round(2 * tile.lp.labelShadow[0].blur))
      shadowBlur: 0.5
    }
  }
}
