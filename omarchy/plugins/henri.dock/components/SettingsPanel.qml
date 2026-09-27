import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "file:///home/henri/.local/share/apple-ui/Apple.js" as Apple
import "file:///home/henri/.local/share/apple-ui" as AUi

// Dock settings (spec §19): every option live, sliders for size and
// magnification. A popover over the dock's centre on apple-ui components.
Item {
  id: panel
  property var dock
  property bool open: false
  signal dismissRequested()

  readonly property bool shown: open || reveal.opacity > 0.001
  readonly property var pal: dock.palette
  readonly property var s: dock.settings
  readonly property real cardW: Style.space(Apple.dock.settingsWidth)
  readonly property real maxBody: Math.max(Style.space(200), dock.planeHeight * 0.7)
  readonly property real cardH: Math.min(maxBody, body.implicitHeight + Style.space(12) * 2)
  readonly property var r: dock.rectFor(dock.mainLength / 2, dock.dockBaseline + dock.tileSize + Style.space(Apple.dock.labelGap),
      dock.horizontal ? cardW : cardH + Style.space(Apple.dock.labelArrowH),
      dock.horizontal ? cardH + Style.space(Apple.dock.labelArrowH) : cardW)
  x: Math.max(Style.space(6), Math.min(dock.planeWidth - r.w - Style.space(6), r.x))
  y: Math.max(Style.space(6), Math.min(dock.planeHeight - r.h - Style.space(6), r.y))
  width: r.w
  height: r.h
  visible: shown

  AUi.Material { id: mat; dark: dock.dark }

  HUi.Reveal {
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
      radius: Style.space(Apple.dock.gridRadius)
      arrowSide: dock.position
      padX: 0; padY: 0

      Flickable {
        id: flick
        property var appleMaterial: mat
        width: panel.cardW
        height: panel.cardH
        contentHeight: body.implicitHeight + Style.space(12) * 2
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        flickDeceleration: Motion.flickDeceleration
        maximumFlickVelocity: Motion.maximumFlickVelocity

        Column {
          id: body
          x: Style.space(12); y: Style.space(12)
          width: parent.width - Style.space(24)
          spacing: Style.space(6)

          AUi.Title { text: "Dock" }

          Item { width: parent.width; height: Style.space(4) }
          AUi.Caption { text: "Size  " + Math.round(sizeSlider.liveValue) + " px" }
          AUi.Slider {
            id: sizeSlider
            width: parent.width
            minimum: Apple.dock.tileMin; maximum: Apple.dock.tileMax; step: 1
            value: panel.s.tileSize
            onMoved: function (v) { dock.setSetting("tileSize", Math.round(v)) }
          }
          AUi.SwitchRow {
            width: parent.width
            title: "Magnification"
            checked: panel.s.magnification
            onToggled: function (on) { dock.setSetting("magnification", on) }
          }
          AUi.Caption { text: "Magnified size  " + Math.round(magSlider.liveValue) + " px"; opacity: panel.s.magnification ? 1 : Motion.disabledOpacity }
          AUi.Slider {
            id: magSlider
            width: parent.width
            enabled: panel.s.magnification
            minimum: panel.s.tileSize; maximum: Apple.dock.tileMax; step: 1
            value: Math.max(panel.s.tileSize, panel.s.magnifiedSize)
            onMoved: function (v) { dock.setSetting("magnifiedSize", Math.round(v)) }
          }

          AUi.SectionLabel { text: "Position on screen" }
          Row {
            spacing: Style.space(6)
            Repeater {
              model: [["left", "Left"], ["bottom", "Bottom"], ["right", "Right"]]
              delegate: AUi.Capsule {
                required property var modelData
                label: modelData[1]
                selected: panel.s.position === modelData[0]
                onClicked: dock.setSetting("position", modelData[0])
              }
            }
          }

          AUi.SectionLabel { text: "Minimize windows using" }
          Row {
            spacing: Style.space(6)
            Repeater {
              model: [["genie", "Genie effect"], ["scale", "Scale effect"]]
              delegate: AUi.Capsule {
                required property var modelData
                label: modelData[1]
                selected: panel.s.minimizeEffect === modelData[0]
                onClicked: dock.setSetting("minimizeEffect", modelData[0])
              }
            }
          }

          AUi.SwitchRow { width: parent.width; title: "Minimize windows into application icon"; checked: panel.s.minimizeToAppIcon; onToggled: function (on) { dock.setSetting("minimizeToAppIcon", on) } }
          AUi.SwitchRow { width: parent.width; title: "Animate opening applications"; checked: panel.s.animateOpeningApps; onToggled: function (on) { dock.setSetting("animateOpeningApps", on) } }
          AUi.SwitchRow { width: parent.width; title: "Automatically hide and show the Dock"; checked: panel.s.autoHide; onToggled: function (on) { dock.setSetting("autoHide", on) } }
          AUi.SwitchRow { width: parent.width; title: "Show indicators for open applications"; checked: panel.s.showIndicators; onToggled: function (on) { dock.setSetting("showIndicators", on) } }
          AUi.SwitchRow { width: parent.width; title: "Show recent applications in Dock"; checked: panel.s.showRecentApps; onToggled: function (on) { dock.setSetting("showRecentApps", on) } }

          AUi.SectionLabel { text: "Appearance" }
          Row {
            spacing: Style.space(6)
            Repeater {
              model: [["system", "Wallpaper"], ["light", "Light"], ["dark", "Dark"]]
              delegate: AUi.Capsule {
                required property var modelData
                label: modelData[1]
                selected: panel.s.theme === modelData[0]
                onClicked: dock.setSetting("theme", modelData[0])
              }
            }
          }

          AUi.SectionLabel { text: "Motion" }
          Row {
            spacing: Style.space(6)
            Repeater {
              model: [["system", "System"], ["off", "Full"], ["on", "Reduced"]]
              delegate: AUi.Capsule {
                required property var modelData
                label: modelData[1]
                selected: String(panel.s.reduceMotion) === modelData[0]
                onClicked: dock.setSetting("reduceMotion", modelData[0])
              }
            }
          }
          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }
}
