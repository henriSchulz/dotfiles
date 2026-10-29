import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"
import qs.Commons

// Folder stack over the dock (spec §11): fan (entries fly out of the tile on
// a slight arc), grid (glass panel scaling up from the tile) or list. The
// Reveal only provides Esc / click-outside; the choreography is the
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
  NumberAnimation { id: openAnim; target: stack; property: "progress"; to: 1; duration: stack.view === "fan" ? dock.mo.fan + dock.stagger(stack.fanCount) : dock.mo.grid; easing.type: Easing.Linear }
  NumberAnimation { id: closeAnim; target: stack; property: "progress"; to: 0; duration: Theme.exit(dock.mo.fan); easing.type: Easing.Linear }

  Reveal {
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
  readonly property int fanMax: Theme.core.surface.dock.shape.fanMax
  readonly property var fanEntries: entries.length > fanMax ? entries.slice(0, fanMax - 1) : entries
  readonly property int fanCount: fanEntries.length + (entries.length > fanMax ? 1 : 0)
  readonly property real pillH: Style.space(Theme.core.surface.dock.shape.fanPill)
  readonly property real fanIcon: Style.space(Theme.core.surface.dock.shape.fanIcon)
  readonly property real fanPitch: fanIcon + Style.space(Theme.core.surface.dock.shape.fanGap)

  Repeater {
    model: stack.view === "fan" ? stack.fanCount : 0
    delegate: Item {
      id: fe
      required property int index
      readonly property bool more: index >= stack.fanEntries.length
      readonly property var entry: more ? null : stack.fanEntries[index]
      readonly property int n: stack.fanCount
      // Per-entry progress: staggered by Motion.stagger while opening, all together while closing.
      readonly property real total: dock.mo.fan + dock.stagger(n)
      readonly property real rawP: stack.open ? Math.max(0, Math.min(1, (stack.progress * total - dock.stagger(index)) / dock.mo.fan)) : stack.progress
      readonly property real p: stack.bez(rawP, stack.open ? Theme.curve("out") : Theme.curve("exit"))
      readonly property real t: n > 1 ? index / (n - 1) : 0
      readonly property real angle: Theme.core.surface.dock.shape.fanAngle * t * t
      readonly property real finalCross: stack.anchorCross + Style.space(Theme.core.surface.dock.shape.fanGap) + index * stack.fanPitch
      // Reduce Motion: entries sit at their fanned-out place and only fade.
      readonly property real geo: dock.reduceMotion ? 1 : p
      readonly property real cross: stack.anchorCross + (finalCross - stack.anchorCross) * geo
      readonly property real mainOff: dock.tileSize * 1.4 * t * t * geo
      readonly property var r: dock.rectFor(stack.anchorMain + mainOff, cross, stack.fanIcon, stack.fanIcon)
      x: r.x; y: r.y; width: r.w; height: r.h
      opacity: p
      rotation: angle * geo
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
        Text { anchors.centerIn: parent; text: "…"; color: stack.pal.pillText; font.family: Theme.font; font.pixelSize: parent.height * 0.5 }
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
        color: !Theme.reduceTransparency ? stack.pal.pill : stack.pal.opaque
        border.width: 1; border.color: stack.pal.hairline
        Text {
          id: pillText
          anchors.centerIn: parent
          text: fe.more ? "Show more in File Manager" : (fe.entry ? fe.entry.name : "")
          color: stack.pal.pillText
          font.family: Theme.font
          font.pixelSize: Style.space(Theme.core.surface.dock.shape.labelFont)
          elide: Text.ElideMiddle
          width: Math.min(implicitWidth, Style.space(260))
        }
      }
      HoverHandler { id: feHover; enabled: stack.open }
      Rectangle { anchors.fill: parent; anchors.margins: -Style.space(3); radius: Style.space(8); color: dock.accent; opacity: feHover.hovered ? 0.18 : 0; z: -1
        Behavior on opacity { NumberAnimation { duration: Theme.dur("instant") } } }
      Rectangle { anchors.fill: pill; radius: pill.radius; color: dock.accent; opacity: feHover.hovered ? 0.18 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur("instant") } } }
      TapHandler {
        enabled: stack.open
        onTapped: { if (fe.more) stack.openFolder(); else stack.openEntry(fe.entry) }
      }
    }
  }

  // ---------------------------------------------------------------- grid / list
  readonly property bool panelView: view === "grid" || view === "list"
  readonly property int cols: Math.max(1, Math.min(Theme.core.surface.dock.shape.gridColumns, entries.length))
  readonly property real cell: Style.space(Theme.core.surface.dock.shape.gridCell)
  readonly property real cellH: Style.space(Theme.core.surface.dock.shape.gridIcon) + Style.space(Theme.core.surface.dock.shape.gridFont) * 2.6 + Style.space(8)
  readonly property real listRow: Style.space(Theme.core.surface.dock.shape.listRow)
  readonly property real panelW: view === "grid" ? cols * cell + Style.space(Theme.core.surface.dock.shape.gridPad) * 2 : Math.max(Theme.m.menu.minWidth, listCol.implicitWidth + Theme.m.menu.pad * 2)
  readonly property real panelBodyH: view === "grid"
      ? Math.min(Math.ceil(entries.length / cols) * cellH, cellH * 4) + Style.space(Theme.core.surface.dock.shape.gridPad) * 2
      : Math.min(listCol.implicitHeight, listRow * 18) + Theme.m.menu.pad * 2
  readonly property real panelH: panelBodyH + footer.height
  readonly property var pr: dock.rectFor(anchorMain, anchorCross + Style.space(Theme.core.surface.dock.shape.labelGap),
      horizontal ? panelW : panelH + Style.space(Theme.core.surface.dock.shape.labelArrowH),
      horizontal ? panelH + Style.space(Theme.core.surface.dock.shape.labelArrowH) : panelW)
  readonly property real px: Math.max(Style.space(6), Math.min(dock.planeWidth - pr.w - Style.space(6), pr.x))
  readonly property real py: Math.max(Style.space(6), Math.min(dock.planeHeight - pr.h - Style.space(6), pr.y))

  SpringValue { id: panelScale; to: stack.open && stack.panelView ? 1 : dock.mo.gridFromScale; preset: Theme.spring("smooth"); epsilon: 0.002 }

  Bubble {
    id: gridPanel
    visible: stack.panelView
    x: stack.horizontal ? stack.px : stack.pr.x
    y: stack.horizontal ? stack.pr.y : stack.py
    width: stack.pr.w
    height: stack.pr.h
    palette: stack.pal
    fill: stack.pal.menu
    radius: Theme.m.radius.popover
    arrowSide: dock.position
    arrowAt: stack.horizontal ? (stack.pr.x + stack.pr.w / 2 - stack.px) / Math.max(1, stack.pr.w)
                              : (stack.pr.y + stack.pr.h / 2 - stack.py) / Math.max(1, stack.pr.h)
    padX: 0; padY: 0
    opacity: stack.progress
    scale: dock.reduceMotion ? 1 : panelScale.value
    transformOrigin: dock.position === "bottom" ? Item.Bottom : dock.position === "left" ? Item.Left : Item.Right

    Item {
      width: stack.panelW
      height: stack.panelH

      // Grid of icons with names
      GridView {
        visible: stack.view === "grid"
        x: Style.space(Theme.core.surface.dock.shape.gridPad); y: Style.space(Theme.core.surface.dock.shape.gridPad)
        width: stack.cols * stack.cell
        height: stack.panelBodyH - Style.space(Theme.core.surface.dock.shape.gridPad) * 2
        clip: true
        cellWidth: stack.cell
        cellHeight: stack.cellH
        model: stack.view === "grid" ? stack.entries : []
        boundsBehavior: Flickable.DragAndOvershootBounds
        flickDeceleration: Theme.core.motion.scroll.flickDeceleration
        maximumFlickVelocity: Theme.core.motion.scroll.maximumFlickVelocity
        delegate: Item {
          id: ge
          required property var modelData
          width: stack.cell; height: stack.cellH
          HoverHandler { id: geHover }
          Rectangle { anchors.fill: parent; anchors.margins: Style.space(2); radius: Style.space(8); color: dock.accent; opacity: geHover.hovered ? 0.18 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.dur("instant") } } }
          Image {
            id: gIcon
            anchors.horizontalCenter: parent.horizontalCenter
            y: Style.space(4)
            width: Style.space(Theme.core.surface.dock.shape.gridIcon); height: width
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
            font.family: Theme.font
            font.pixelSize: Style.space(Theme.core.surface.dock.shape.gridFont)
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
        x: Theme.m.menu.pad; y: Theme.m.menu.pad
        width: stack.panelW - Theme.m.menu.pad * 2
        height: stack.panelBodyH - Theme.m.menu.pad * 2
        contentHeight: listCol.implicitHeight
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        flickDeceleration: Theme.core.motion.scroll.flickDeceleration
        maximumFlickVelocity: Theme.core.motion.scroll.maximumFlickVelocity
        Column {
          id: listCol
          width: parent.width
          Repeater {
            model: stack.view === "list" ? stack.entries : []
            delegate: Rectangle {
              id: le
              required property var modelData
              width: listCol.width
              implicitWidth: lText.implicitWidth + Style.space(Theme.core.surface.dock.shape.listIcon) + Style.space(30)
              height: stack.listRow
              radius: Style.space(Theme.core.surface.dock.shape.menuHighlightRadius)
              color: leHover.hovered ? dock.accent : "transparent"
              HoverHandler { id: leHover }
              Image {
                x: Style.space(6); anchors.verticalCenter: parent.verticalCenter
                width: Style.space(Theme.core.surface.dock.shape.listIcon); height: width
                source: dock.iconFor(le.modelData.icon)
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; asynchronous: true
              }
              Text {
                id: lText
                x: Style.space(6) + Style.space(Theme.core.surface.dock.shape.listIcon) + Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - Style.space(20)
                text: le.modelData.name
                color: leHover.hovered ? "#ffffffff" : stack.pal.menuText
                font.family: Theme.font
                font.pixelSize: Style.space(Theme.core.surface.dock.shape.menuFont)
                elide: Text.ElideMiddle
              }
              Text {
                visible: le.modelData.isDir
                anchors.right: parent.right; anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: lText.color
                font.family: Theme.font
                font.pixelSize: Style.space(Theme.core.surface.dock.shape.menuFont)
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
          x: Theme.m.menu.pad; anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Theme.m.menu.pad * 2
          height: stack.listRow
          radius: Style.space(Theme.core.surface.dock.shape.menuHighlightRadius)
          color: fHover.hovered ? dock.accent : "transparent"
          HoverHandler { id: fHover }
          Text {
            anchors.centerIn: parent
            text: stack.entries.length + (stack.entries.length === 1 ? " item" : " items") + " — Open in File Manager"
            color: fHover.hovered ? "#ffffffff" : stack.pal.menuText
            font.family: Theme.font
            font.pixelSize: Style.space(Theme.core.surface.dock.shape.menuFont)
          }
          TapHandler { onTapped: stack.openFolder() }
        }
      }
    }
  }
}
