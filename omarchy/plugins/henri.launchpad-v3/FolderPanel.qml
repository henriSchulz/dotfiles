import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"
import "LayoutModel.js" as LM
import "Look.js" as Look

// The open folder: dark glass panel that grows out of the folder's tile, its
// name above it (click to rename), the apps in a folderGrid-wide grid. Hit
// tests (contains / indexAt / cellRect) are in window coordinates for the
// Launchpad's single pointer handler.
Item {
  id: panelRoot
  property var launchpad: null
  readonly property var lp: Theme.core.surface.launchpad
  readonly property string folderId: launchpad ? launchpad.openFolder : ""
  // the last open folder stays drawn while the panel shrinks away
  property string shownId: ""
  onFolderIdChanged: if (folderId !== "") shownId = folderId
  readonly property var folder: launchpad && shownId !== "" ? (launchpad.layout.folders[LM.folderKey(shownId)] || null) : null
  readonly property var items: folder ? folder.items : []

  readonly property int cols: launchpad ? launchpad.settings.folderGrid[0] : 4
  readonly property int maxRows: launchpad ? launchpad.settings.folderGrid[1] : 4
  // a folder fuller than cols × maxRows gets pages, with dots under its grid
  readonly property int perPage: cols * maxRows
  readonly property int pageCount: Math.max(1, Math.ceil(items.length / perPage))
  property int fpage: 0
  onShownIdChanged: fpage = 0
  onPageCountChanged: if (fpage >= pageCount) fpage = pageCount - 1
  function turn(d) { fpage = Math.max(0, Math.min(pageCount - 1, fpage + d)) }
  function pageOf(i) { return Math.floor(i / perPage) }
  readonly property real dotsH: pageCount > 1 ? Look.dots.hit + Look.folderPage.dotsGap : 0
  readonly property int rowCount: Math.max(1, Math.min(maxRows, Math.ceil(items.length / cols)))
  readonly property real panelW: Math.min(width * Look.folder.panelWidth, Look.folder.panelMaxWidth)
  readonly property real cellW: (panelW - 2 * Look.folder.panelPad) / cols
  readonly property real cellH: launchpad ? launchpad.cellH : cellW
  readonly property real panelH: rowCount * cellH + 2 * Look.folder.panelPad + dotsH
  readonly property real panelX: (width - panelW) / 2
  readonly property real panelY: (height - panelH) / 2

  visible: progress > 0.001
  readonly property real progress: Math.max(0, grow.value)
  Spring {
    id: grow
    preset: panelRoot.lp.folderOpen
    reduced: Theme.reduceMotion
    target: panelRoot.folderId !== "" ? 1 : 0
  }

  // ------------------------------------------------------------ hit tests
  function contains(px, py) {
    return px >= panelX && px <= panelX + panelW && py >= panelY - Look.folder.panelGap - Look.folder.titleSize * 2 && py <= panelY + panelH
  }
  function titleContains(px, py) { return py < panelY && py >= panelY - Look.folder.panelGap - Look.folder.titleSize * 2 }
  function indexAt(px, py) {
    var gx = px - panelX - Look.folder.panelPad, gy = py - panelY - Look.folder.panelPad
    if (gx < 0 || gy < 0 || gx >= cols * cellW) return -1
    var r = Math.floor(gy / cellH)
    if (r >= rowCount) return -1
    return fpage * perPage + r * cols + Math.floor(gx / cellW)
  }
  // the page dot under the pointer, or -1
  function dotAt(px, py) {
    if (pageCount < 2) return -1
    var y0 = panelY + panelH - Look.folder.panelPad / 2 - Look.dots.hit
    var x0 = (width - pageCount * (Look.dots.size + Look.dots.gap)) / 2
    if (py < y0 || py > y0 + Look.dots.hit || px < x0) return -1
    var d = Math.floor((px - x0) / (Look.dots.size + Look.dots.gap))
    return d < pageCount ? d : -1
  }
  function cellRect(i) {
    var local = i - pageOf(i) * perPage
    return { x: panelX + Look.folder.panelPad + (local % cols) * cellW, y: panelY + Look.folder.panelPad + Math.floor(local / cols) * cellH }
  }

  // ---------------------------------------------------------------- rename
  function startRename() {
    title.readOnly = false
    title.forceActiveFocus()
    title.selectAll()
  }
  function commitTitle() {
    if (title.readOnly || !launchpad || folderId === "") return
    title.readOnly = true
    if (title.text.trim() !== "" && folder && title.text !== folder.name)
      launchpad.commit(LM.styleFolder(launchpad.layout, folderId, { name: title.text }))
  }

  // the panel grows from the tile rect (launchpad.folderFrom) to its place
  Item {
    id: body
    readonly property var from: panelRoot.launchpad ? panelRoot.launchpad.folderFrom : ({ x: 0, y: 0, w: 1, h: 1 })
    readonly property real p: Theme.reduceMotion ? 1 : panelRoot.progress
    x: panelRoot.panelX; y: panelRoot.panelY
    width: panelRoot.panelW; height: panelRoot.panelH
    opacity: panelRoot.progress
    transform: [
      Scale {
        xScale: body.p + (1 - body.p) * body.from.w / body.width
        yScale: body.p + (1 - body.p) * body.from.h / body.height
      },
      Translate {
        x: (1 - body.p) * (body.from.x - panelRoot.panelX)
        y: (1 - body.p) * (body.from.y - panelRoot.panelY)
      }
    ]

    Rectangle {
      anchors.fill: parent
      radius: Theme.m.radius.panel
      color: panelRoot.lp.folderPanel
    }

    Repeater {
      model: panelRoot.items
      AppTile {
        required property var modelData
        required property int index
        readonly property var cell: panelRoot.cellRect(index)
        x: cell.x - panelRoot.panelX; y: cell.y - panelRoot.panelY
        width: panelRoot.cellW; height: panelRoot.cellH
        visible: modelData !== panelRoot.launchpad.dragId && panelRoot.pageOf(index) === panelRoot.fpage
        title: panelRoot.launchpad.titleFor(modelData)
        iconSource: panelRoot.launchpad.iconFor(modelData)
        iconSize: panelRoot.launchpad.iconSize
        showTitle: panelRoot.launchpad.settings.showTitles
        selected: panelRoot.launchpad.query === "" && index === panelRoot.launchpad.selIndex
        pressed: panelRoot.launchpad.pressId === modelData && !panelRoot.launchpad.editing
        editing: panelRoot.launchpad.editing
        jiggle: panelRoot.launchpad.jiggleFor(modelData)
        picked: panelRoot.launchpad.picks[modelData] === true
      }
    }

    // page dots of a big folder
    Row {
      visible: panelRoot.pageCount > 1
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom; anchors.bottomMargin: Look.folder.panelPad / 2
      Repeater {
        model: panelRoot.pageCount
        Item {
          required property int index
          width: Look.dots.size + Look.dots.gap; height: Look.dots.hit
          Rectangle {
            anchors.centerIn: parent
            width: Look.dots.size; height: Look.dots.size; radius: width / 2
            color: index === panelRoot.fpage ? panelRoot.lp.dotActive : panelRoot.lp.dot
          }
        }
      }
    }
  }

  TextInput {
    id: title
    readOnly: true
    anchors.horizontalCenter: parent.horizontalCenter
    y: panelRoot.panelY - Look.folder.panelGap - height
    width: panelRoot.panelW
    opacity: panelRoot.progress
    horizontalAlignment: TextInput.AlignHCenter
    text: panelRoot.folder ? panelRoot.folder.name : ""
    color: panelRoot.lp.folderTitle
    selectionColor: panelRoot.lp.selection
    font.family: Theme.font
    font.pixelSize: Look.folder.titleSize
    font.weight: Font.DemiBold
    maximumLength: 64
    onAccepted: { panelRoot.commitTitle(); panelRoot.launchpad.closeFolderFocus() }
    Keys.onEscapePressed: function(event) {
      title.text = panelRoot.folder ? panelRoot.folder.name : ""
      title.readOnly = true
      panelRoot.launchpad.closeFolderFocus()
      event.accepted = true
    }
    onActiveFocusChanged: if (!activeFocus) panelRoot.commitTitle()
  }
}
