import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// The Sound details (the Sound tile's chevron or a long press on it; rows as QsDetail draws them, lab QsPages.jsx
// Detail): back, "Sound" and its switch (on = not muted), the volume slider, the outputs — a tap makes one the
// default and the apps that play move along (control-center-v3's omarchy-audio-output-set-default; the casting
// iPad's speakers are one of them) — the inputs (pactl set-default-source), and below the list "Sound settings"
// (System Settings on its Sound page; the shade closes). What changes the system goes through the backend: logged
// only unless it is live. The list takes no finger itself: the shade's finger scrolls it (`scroller`,
// QuickSettings); it is as tall as the room the details have (`maxHeight`), so on a tall screen nothing scrolls.
Item {
  id: d
  property var backend: null
  property real maxHeight: 0              // the room below the header (QuickSettings); 0: the details' five rows
  signal back()
  signal settingsRequested()
  readonly property var k: Theme.core.surface.material.qs
  readonly property alias scroller: list
  readonly property bool on: !!backend && backend.hasSink && !backend.muted
  readonly property var outputs: backend ? backend.sinkRows : []
  readonly property var inputs: backend ? backend.sourceRows : []
  implicitHeight: footer.y + footer.height
  Component.onCompleted: if (backend) backend.readSound()

  // a device row (QsDetail's look): symbol, name, kind; the default carries the accent's tint and a check
  component SoundRow: Item {
    id: r
    property string icon: ""
    property string label: ""
    property string kind: ""
    property bool current: false
    property bool chevron: false
    signal chosen()
    width: d.width
    height: d.k.detail.row
    Rectangle { anchors.fill: parent; radius: d.k.detail.rowRadius; color: Qt.alpha(Theme.r.accent.base, d.k.detail.activeAlpha); visible: r.current }
    Rectangle { anchors.fill: parent; radius: d.k.detail.rowRadius; color: Theme.r.popover.ink; opacity: tap.pressed ? Theme.core.alpha.pressed : 0 }
    Row {
      x: d.k.detail.rowPad; width: parent.width - 2 * d.k.detail.rowPad
      anchors.verticalCenter: parent.verticalCenter
      spacing: d.k.tile.iconGap
      VIcon { anchors.verticalCenter: parent.verticalCenter; name: r.icon; size: d.k.header.icon; color: Theme.r.popover.ink }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - d.k.header.icon - parent.spacing - (mark.visible ? mark.width + parent.spacing : 0)
        MText { width: parent.width; medium: true; text: r.label }
        MText { width: parent.width; visible: r.kind !== ""; size: "caption"; tone: "secondary"; text: r.kind }
      }
      VIcon {
        id: mark
        visible: r.current || r.chevron
        anchors.verticalCenter: parent.verticalCenter
        name: r.chevron ? "chevron.right" : "check"; weight: "bold"; size: d.k.detail.small
        color: r.chevron ? Theme.r.popover.inkSecondary : Theme.r.accent.base
      }
    }
    TapHandler { id: tap; onTapped: r.chosen() }
  }
  component Section: MText {
    width: d.width; height: d.k.sound.section
    leftPadding: d.k.detail.rowPad
    verticalAlignment: Text.AlignVCenter
    size: "caption"; medium: true; tone: "secondary"
  }

  Item {
    id: head
    width: d.width
    height: d.k.header.button
    MIconButton { id: backBtn; objectName: "btn-back"; icon: "arrow.left"; label: "Back"; onClicked: d.back() }
    MText { x: backBtn.width + d.k.header.gap; width: sw.x - x - d.k.header.gap; anchors.verticalCenter: parent.verticalCenter
      size: "subtitle"; medium: true; text: "Sound" }
    MSwitch {
      id: sw
      objectName: "sound-switch"
      anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      checked: d.on
      onToggled: on => { if (d.backend && d.backend.hasSink) d.backend.setMuted(!on) }
    }
  }

  QsSlider {
    id: vol
    objectName: "sound-volume"
    y: head.height + d.k.header.gap
    width: d.width
    icon: d.backend ? d.backend.volumeIcon : "sound"
    value: d.backend && !d.backend.muted ? d.backend.volume : 0
    onHeld: down => { if (d.backend) d.backend.volumeHeld = down }
    onMoved: (v, final) => { if (d.backend) d.backend.setVolume(v, final) }
  }

  Flickable {
    id: list
    y: vol.y + vol.height + d.k.slider.bottom
    width: d.width
    // the room left under the slider and above "Sound settings", at least one row
    readonly property real cap: d.maxHeight > 0 ? Math.max(d.k.detail.row, d.maxHeight - y - d.k.header.gap - d.k.detail.row)
      : d.k.detail.rows * d.k.detail.row + d.k.detail.listPad
    height: Math.min(contentHeight, cap)
    contentHeight: col.height
    clip: true
    interactive: false
    boundsBehavior: Flickable.StopAtBounds
    flickDeceleration: Theme.core.motion.scroll.flickDeceleration
    maximumFlickVelocity: Theme.core.motion.scroll.maximumFlickVelocity
    Column {
      id: col
      width: d.width
      Section { text: "Output" }
      MText { visible: d.outputs.length === 0; width: d.width; leftPadding: d.k.detail.rowPad; text: "No output devices"; tone: "secondary" }
      Repeater {
        model: d.outputs
        SoundRow {
          required property var modelData
          objectName: "output-" + modelData.name
          icon: modelData.icon; label: modelData.label; kind: modelData.kind; current: modelData.active
          onChosen: if (d.backend) d.backend.setSink(modelData)
        }
      }
      Section { visible: d.inputs.length > 0; text: "Input" }
      Repeater {
        model: d.inputs
        SoundRow {
          required property var modelData
          objectName: "input-" + modelData.name
          icon: modelData.icon; label: modelData.label; kind: modelData.kind; current: modelData.active
          onChosen: if (d.backend) d.backend.setSource(modelData)
        }
      }
    }
  }

  SoundRow {
    id: footer
    objectName: "sound-settings"
    y: list.y + list.height + d.k.header.gap
    icon: "settings"; label: "Sound settings"; chevron: true
    onChosen: d.settingsRequested()
  }
}
