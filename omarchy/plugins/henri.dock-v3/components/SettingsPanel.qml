import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"
import qs.Commons

// Dock settings (spec §19): every option live, sliders for size and
// magnification. A popover over the dock's centre on Velum components.
Item {
  id: panel
  property var dock
  property bool open: false
  signal dismissRequested()

  readonly property bool shown: open || reveal.opacity > 0.001
  readonly property var pal: dock.palette
  readonly property var s: dock.settings
  readonly property real cardW: Theme.layout.module.width
  readonly property real maxBody: Math.max(Style.space(200), dock.planeHeight * 0.7)
  readonly property real cardH: Math.min(maxBody, body.implicitHeight + Theme.layout.module.pad * 2)
  readonly property var r: dock.rectFor(dock.mainLength / 2, dock.dockBaseline + dock.tileSize + Style.space(Theme.core.surface.dock.shape.labelGap),
      dock.horizontal ? cardW : cardH + Style.space(Theme.core.surface.dock.shape.labelArrowH),
      dock.horizontal ? cardH + Style.space(Theme.core.surface.dock.shape.labelArrowH) : cardW)
  x: Math.max(Style.space(6), Math.min(dock.planeWidth - r.w - Style.space(6), r.x))
  y: Math.max(Style.space(6), Math.min(dock.planeHeight - r.h - Style.space(6), r.y))
  width: r.w
  height: r.h
  visible: shown

  // rows of the panel
  component SliderLine: Item {
    id: sl
    property real from: 0
    property real to: 1
    property real value: 0
    signal moved(real v)
    width: parent ? parent.width : 0; height: Theme.layout.module.row
    VSlider { x: Theme.layout.module.pad; width: parent.width - 2 * x; anchors.verticalCenter: parent.verticalCenter
      from: sl.from; to: sl.to; value: sl.value; onMoved: v => sl.moved(v) }
  }
  component SegmentLine: Item {
    id: seg
    property var keys: []
    property var labels: []
    property string current: ""
    signal picked(string key)
    width: parent ? parent.width : 0; height: Theme.m.control.height + Theme.layout.list.gap
    VSegment { x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter; model: seg.labels
      currentIndex: Math.max(0, seg.keys.indexOf(seg.current)); onActivated: i => seg.picked(seg.keys[i]) }
  }
  component SwitchLine: VModuleRow {
    id: swl
    property string key: ""
    width: parent ? parent.width : 0; clickable: false
    VSwitch { surface: "popover"; checked: !!panel.s[swl.key]; onToggled: c => dock.setSetting(swl.key, c) }
  }

  Reveal {
    id: reveal
    anchors.fill: parent
    kind: "popover"
    open: panel.open
    origin: dock.position === "bottom" ? Item.Bottom : dock.position === "left" ? Item.Left : Item.Right
    insideWindows: dock.insideWindows
    closeOnOutsideClick: !dock.testNoGrab
    onDismissRequested: panel.dismissRequested()

    Bubble {
      anchors.fill: parent
      palette: panel.pal
      fill: panel.pal.menu
      radius: Theme.m.radius.popover
      arrowSide: dock.position
      padX: 0; padY: 0

      Flickable {
        id: flick
        property string velumSurface: "popover"
        width: panel.cardW
        height: panel.cardH
        contentHeight: body.implicitHeight + Theme.layout.module.pad * 2
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        flickDeceleration: Theme.core.motion.scroll.flickDeceleration
        maximumFlickVelocity: Theme.core.motion.scroll.maximumFlickVelocity

        Column {
          id: body
          x: Theme.layout.module.tileInset; y: Theme.layout.module.pad
          width: parent.width - 2 * x

          VText { x: Theme.layout.module.pad; text: "Dock"; font.pixelSize: Theme.m.type.title; font.weight: Font.DemiBold; color: Theme.r.popover.ink
            bottomPadding: Theme.layout.list.gap }

          VModuleSection { width: parent.width; text: "Size  " + Math.round(panel.s.tileSize) + " px" }
          SliderLine { from: Theme.core.surface.dock.shape.tileMin; to: Theme.core.surface.dock.shape.tileMax; value: panel.s.tileSize
            onMoved: v => dock.setSetting("tileSize", Math.round(v)) }
          VModuleRow { width: parent.width; text: "Magnification"; clickable: false
            VSwitch { surface: "popover"; checked: panel.s.magnification; onToggled: c => dock.setSetting("magnification", c) } }
          VModuleSection { width: parent.width; text: "Magnified size  " + Math.round(Math.max(panel.s.tileSize, panel.s.magnifiedSize)) + " px"
            opacity: panel.s.magnification ? 1 : Theme.core.alpha.disabled }
          SliderLine { enabled: panel.s.magnification; opacity: enabled ? 1 : Theme.core.alpha.disabled
            from: panel.s.tileSize; to: Theme.core.surface.dock.shape.tileMax; value: Math.max(panel.s.tileSize, panel.s.magnifiedSize)
            onMoved: v => dock.setSetting("magnifiedSize", Math.round(v)) }

          VModuleSection { width: parent.width; text: "Position on Screen" }
          SegmentLine { keys: ["left", "bottom", "right"]; labels: ["Left", "Bottom", "Right"]; current: panel.s.position
            onPicked: k => dock.setSetting("position", k) }
          VModuleSection { width: parent.width; text: "Minimize Windows Using" }
          SegmentLine { keys: ["genie", "scale"]; labels: ["Genie Effect", "Scale Effect"]; current: panel.s.minimizeEffect
            onPicked: k => dock.setSetting("minimizeEffect", k) }

          VModuleSep { width: parent.width }
          SwitchLine { text: "Minimize windows into application icon"; key: "minimizeToAppIcon" }
          SwitchLine { text: "Animate opening applications"; key: "animateOpeningApps" }
          SwitchLine { text: "Automatically hide and show the Dock"; key: "autoHide" }
          SwitchLine { text: "Show indicators for open applications"; key: "showIndicators" }
          SwitchLine { text: "Show recent applications in Dock"; key: "showRecentApps" }

          VModuleSection { width: parent.width; text: "Appearance" }
          SegmentLine { keys: ["system", "light", "dark"]; labels: ["Wallpaper", "Light", "Dark"]; current: panel.s.theme
            onPicked: k => dock.setSetting("theme", k) }
          VModuleSection { width: parent.width; text: "Motion" }
          SegmentLine { keys: ["system", "on"]; labels: ["System", "Reduced"]; current: String(panel.s.reduceMotion) === "on" ? "on" : "system"
            onPicked: k => dock.setSetting("reduceMotion", k) }
        }
      }
    }
  }
}
