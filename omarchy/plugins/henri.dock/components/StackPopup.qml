import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "file:///home/henri/.local/share/apple-ui/Apple.js" as Apple

// Folder stack over the dock (spec §11): fan (entries fly out of the tile on
// a slight arc), grid (glass panel scaling up from the tile) or list. The
// HUi.Reveal only provides Esc / click-outside; the choreography is the
// spec's own, so it runs unanimated.
Item {
  id: stack
  property var dock
  property bool open: false
  property var folder: null          // dock item of kind "folder"
  property var entries: []           // sorted entries
  property string view: "fan"
  property real anchorMain: 0
  property real anchorCross: 0
  signal dismissRequested()
  signal openEntry(var entry)
  signal openFolder()

  readonly property var pal: dock.palette
  readonly property bool horizontal: dock.horizontal
  property real progress: 0
  readonly property bool shown: open || progress > 0.001
  visible: shown
  anchors.fill: parent

  onOpenChanged: {
    openAnim.stop(); closeAnim.stop()
    if (open) openAnim.restart(); else closeAnim.restart()
  }
  NumberAnimation { id: openAnim; target: stack; property: "progress"; to: 1; duration: stack.view === "fan" ? Motion.dock.fan + Motion.stagger(stack.fanCount) : Motion.dock.grid; easing.type: Easing.Linear }
  NumberAnimation { id: closeAnim; target: stack; property: "progress"; to: 0; duration: Motion.exit(Motion.dock.fan); easing.type: Easing.Linear }

  HUi.Reveal {
    anchors.fill: parent
    animated: false
    open: stack.open
    insideWindows: dock.insideWindows
    closeOnOutsideClick: !dock.testNoGrab
    onDismissRequested: stack.dismissRequested()
  }

  function bez(t, c) {
    // Cubic bezier evaluated by bisection on x (small, only for the fan).
    var lo = 0, hi = 1
    for (var i = 0; i < 16; i++) {
      var m = (lo + hi) / 2
      var x = 3 * (1 - m) * (1 - m) * m * c[0] + 3 * (1 - m) * m * m * c[2] + m * m * m
      if (x < t) lo = m; else hi = m
    }
    var u = (lo + hi) / 2
    return 3 * (1 - u) * (1 - u) * u * c[1] + 3 * (1 - u) * u * u * c[3] + u * u * u
  }

  // ---------------------------------------------------------------- fan
  readonly property int fanMax: Apple.dock.fanMax
  readonly property var fanEntries: entries.length > fanMax ? entries.slice(0, fanMax - 1) : entries
  readonly property int fanCount: fanEntries.length + (entries.length > fanMax ? 1 : 0)
  readonly property real pillH: Style.space(Apple.dock.fanPill)
  readonly property real fanIcon: Style.space(Apple.dock.fanIcon)
  readonly property real fanPitch: fanIcon + Style.space(Apple.dock.fanGap)

  Repeater {
    model: stack.view === "fan" ? stack.fanCount : 0
    delegate: Item {
      id: fe
      required property int index
      readonly property bool more: index >= stack.fanEntries.length
      readonly property var entry: more ? null : stack.fanEntries[index]
      readonly property int n: stack.fanCount
      // Per-entry progress: staggered by Motion.stagger while opening, all together while closing.
      readonly property real total: Motion.dock.fan + Motion.stagger(n)
      readonly property real rawP: stack.open ? Math.max(0, Math.min(1, (stack.progress * total - Motion.stagger(index)) / Motion.dock.fan)) : stack.progress
      readonly property real p: stack.bez(rawP, stack.open ? Motion.easeOut : Motion.easeExit)
      readonly property real t: n > 1 ? index / (n - 1) : 0
      readonly property real angle: Apple.dock.fanAngle * t * t
      readonly property real finalCross: stack.anchorCross + Style.space(Apple.dock.fanGap) + index * stack.fanPitch
      readonly property real cross: stack.anchorCross + (finalCross - stack.anchorCross) * p
      readonly property real mainOff: dock.tileSize * 1.4 * t * t * p
      readonly property var r: dock.rectFor(stack.anchorMain + mainOff, cross, stack.fanIcon, stack.fanIcon)
      x: r.x; y: r.y; width: r.w; height: r.h
      opacity: p
      rotation: angle * p
      transformOrigin: Item.Bottom

      Image {
        anchors.fill: parent
        visible: !fe.more
        source: fe.entry ? dock.iconFor(fe.entry.icon) : ""
        sourceSize: Qt.size(128, 128)
        fillMode: Image.PreserveAspectFit
        smooth: true; mipmap: true; asynchronous: true
      }
      Rectangle {
        // "More in File Manager" tile
        visible: fe.more
        anchors.fill: parent
        radius: width * 0.22
        color: stack.pal.pill
        border.width: 1; border.color: stack.pal.hairline
        Text { anchors.centerIn: parent; text: "…"; color: stack.pal.pillText; font.family: Apple.uiFont; font.pixelSize: parent.height * 0.5 }
      }
      Rectangle {
        // Name pill, left of the icon
        id: pill
        anchors.right: parent.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        width: pillText.implicitWidth + Style.space(12) * 2
        height: stack.pillH
        radius: height / 2
        color: Motion.glass ? stack.pal.pill : stack.pal.opaque
        border.width: 1; border.color: stack.pal.hairline
        Text {
          id: pillText
          anchors.centerIn: parent
          text: fe.more ? "Show more in File Manager" : (fe.entry ? fe.entry.name : "")
          color: stack.pal.pillText
          font.family: Apple.uiFont
          font.pixelSize: Style.space(Apple.dock.labelFont)
          elide: Text.ElideMiddle
          width: Math.min(implicitWidth, Style.space(260))
        }
      }
      HoverHandler { id: feHover; enabled: stack.open }
      Rectangle { anchors.fill: parent; anchors.margins: -Style.space(3); radius: Style.space(8); color: dock.accent; opacity: feHover.hovered ? 0.18 : 0; z: -1
        Behavior on opacity { NumberAnimation { duration: Motion.instant } } }
      Rectangle { anchors.fill: pill; radius: pill.radius; color: dock.accent; opacity: feHover.hovered ? 0.18 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.instant } } }
      TapHandler {
        enabled: stack.open
        onTapped: { if (fe.more) stack.openFolder(); else stack.openEntry(fe.entry) }
      }
    }
  }

  // ---------------------------------------------------------------- grid / list
  readonly property bool panelView: view === "grid" || view === "list"
  readonly property int cols: Math.max(1, Math.min(Apple.dock.gridColumns, entries.length))
  readonly property real cell: Style.space(Apple.dock.gridCell)
  readonly property real cellH: Style.space(Apple.dock.gridIcon) + Style.space(Apple.dock.gridFont) * 2.6 + Style.space(8)
  readonly property real listRow: Style.space(Apple.dock.listRow)
  readonly property real panelW: view === "grid" ? cols * cell + Style.space(Apple.dock.gridPad) * 2 : Math.max(Style.space(Apple.dock.menuMinWidth), listCol.implicitWidth + Style.space(Apple.dock.menuPad) * 2)
  readonly property real panelBodyH: view === "grid"
      ? Math.min(Math.ceil(entries.length / cols) * cellH, cellH * 4) + Style.space(Apple.dock.gridPad) * 2
      : Math.min(listCol.implicitHeight, listRow * 18) + Style.space(Apple.dock.menuPad) * 2
  readonly property real panelH: panelBodyH + footer.height
  readonly property var pr: dock.rectFor(anchorMain, anchorCross + Style.space(Apple.dock.labelGap),
      horizontal ? panelW : panelH + Style.space(Apple.dock.labelArrowH),
      horizontal ? panelH + Style.space(Apple.dock.labelArrowH) : panelW)
  readonly property real px: Math.max(Style.space(6), Math.min(dock.planeWidth - pr.w - Style.space(6), pr.x))
  readonly property real py: Math.max(Style.space(6), Math.min(dock.planeHeight - pr.h - Style.space(6), pr.y))

  HUi.SpringValue { id: panelScale; to: stack.open && stack.panelView ? 1 : Motion.dock.gridFromScale; preset: Motion.smooth; epsilon: 0.002 }

  Bubble {
    id: gridPanel
    visible: stack.panelView
    x: stack.horizontal ? stack.px : stack.pr.x
    y: stack.horizontal ? stack.pr.y : stack.py
    width: stack.pr.w
    height: stack.pr.h
    palette: stack.pal
    fill: stack.pal.menu
    radius: Style.space(Apple.dock.gridRadius)
    arrowSide: dock.position
    arrowAt: stack.horizontal ? (stack.pr.x + stack.pr.w / 2 - stack.px) / Math.max(1, stack.pr.w)
                              : (stack.pr.y + stack.pr.h / 2 - stack.py) / Math.max(1, stack.pr.h)
    padX: 0; padY: 0
    opacity: stack.progress
    scale: Motion.reduceMotion ? 1 : panelScale.value
    transformOrigin: dock.position === "bottom" ? Item.Bottom : dock.position === "left" ? Item.Left : Item.Right

    Item {
      width: stack.panelW
      height: stack.panelH

      // Grid of icons with names
      GridView {
        visible: stack.view === "grid"
        x: Style.space(Apple.dock.gridPad); y: Style.space(Apple.dock.gridPad)
        width: stack.cols * stack.cell
        height: stack.panelBodyH - Style.space(Apple.dock.gridPad) * 2
        clip: true
        cellWidth: stack.cell
        cellHeight: stack.cellH
        model: stack.view === "grid" ? stack.entries : []
        boundsBehavior: Flickable.DragAndOvershootBounds
        flickDeceleration: Motion.flickDeceleration
        maximumFlickVelocity: Motion.maximumFlickVelocity
        delegate: Item {
          id: ge
          required property var modelData
          width: stack.cell; height: stack.cellH
          HoverHandler { id: geHover }
          Rectangle { anchors.fill: parent; anchors.margins: Style.space(2); radius: Style.space(8); color: dock.accent; opacity: geHover.hovered ? 0.18 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.instant } } }
          Image {
            id: gIcon
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.space(4)
            width: Style.space(Apple.dock.gridIcon); height: width
            source: dock.iconFor(ge.modelData.icon)
            sourceSize: Qt.size(128, 128)
            fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; asynchronous: true
          }
          Text {
            anchors.top: gIcon.bottom
            anchors.topMargin: Style.space(4)
            x: Style.space(4); width: parent.width - Style.space(8)
            text: ge.modelData.name
            color: stack.pal.menuText
            font.family: Apple.uiFont
            font.pixelSize: Style.space(Apple.dock.gridFont)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }
          TapHandler { onTapped: stack.openEntry(ge.modelData) }
        }
      }

      // Menu-like list
      Flickable {
        visible: stack.view === "list"
        x: Style.space(Apple.dock.menuPad); y: Style.space(Apple.dock.menuPad)
        width: stack.panelW - Style.space(Apple.dock.menuPad) * 2
        height: stack.panelBodyH - Style.space(Apple.dock.menuPad) * 2
        contentHeight: listCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        flickDeceleration: Motion.flickDeceleration
        maximumFlickVelocity: Motion.maximumFlickVelocity
        Column {
          id: listCol
          width: parent.width
          Repeater {
            model: stack.view === "list" ? stack.entries : []
            delegate: Rectangle {
              id: le
              required property var modelData
              width: listCol.width
              implicitWidth: lText.implicitWidth + Style.space(Apple.dock.listIcon) + Style.space(30)
              height: stack.listRow
              radius: Style.space(Apple.dock.menuHighlightRadius)
              color: leHover.hovered ? dock.accent : "transparent"
              HoverHandler { id: leHover }
              Image {
                x: Style.space(6); anchors.verticalCenter: parent.verticalCenter
                width: Style.space(Apple.dock.listIcon); height: width
                source: dock.iconFor(le.modelData.icon)
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; asynchronous: true
              }
              Text {
                id: lText
                x: Style.space(6) + Style.space(Apple.dock.listIcon) + Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - Style.space(20)
                text: le.modelData.name
                color: leHover.hovered ? "#ffffffff" : stack.pal.menuText
                font.family: Apple.uiFont
                font.pixelSize: Style.space(Apple.dock.menuFont)
                elide: Text.ElideMiddle
              }
              Text {
                visible: le.modelData.isDir
                anchors.right: parent.right; anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: lText.color
                font.family: Apple.uiFont
                font.pixelSize: Style.space(Apple.dock.menuFont)
              }
              TapHandler { onTapped: stack.openEntry(le.modelData) }
            }
          }
        }
      }

      // Footer: open the folder itself
      Rectangle {
        id: footer
        anchors.bottom: parent.bottom
        width: parent.width
        height: stack.listRow + Style.space(8)
        color: "transparent"
        Rectangle { anchors.top: parent.top; x: Style.space(8); width: parent.width - Style.space(16); height: 1; color: stack.pal.menuHairline }
        Rectangle {
          x: Style.space(Apple.dock.menuPad); anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(Apple.dock.menuPad) * 2
          height: stack.listRow
          radius: Style.space(Apple.dock.menuHighlightRadius)
          color: fHover.hovered ? dock.accent : "transparent"
          HoverHandler { id: fHover }
          Text {
            anchors.centerIn: parent
            text: stack.entries.length + (stack.entries.length === 1 ? " item" : " items") + " — Open in File Manager"
            color: fHover.hovered ? "#ffffffff" : stack.pal.menuText
            font.family: Apple.uiFont
            font.pixelSize: Style.space(Apple.dock.menuFont)
          }
          TapHandler { onTapped: stack.openFolder() }
        }
      }
    }
  }
}
