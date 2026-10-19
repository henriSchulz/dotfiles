import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// The head tile of a detail page: a large badge (tap toggles), a title, what it is doing; a control may stand right.
VTile {
  id: hero
  property string icon: ""
  property bool on: true
  property string title: ""
  property string subtitle: ""
  property Component glyph: null      // drawn in the badge instead of `icon`
  default property alias trailing: heroTrail.data
  signal badgeTapped()
  width: parent ? parent.width : 0
  height: Theme.layout.meter.card
  Rectangle {
    id: heroBadge
    x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter
    width: Theme.layout.module.toggle; height: width; radius: width / 2
    gradient: hero.on ? heroFill : null
    color: Theme.r.popover.badgeOff
    border.width: hero.on ? 0 : Theme.layout.separator; border.color: Theme.r.line.base
    Gradient { id: heroFill; GradientStop { position: 0; color: Theme.r.accent.top } GradientStop { position: 1; color: Theme.r.accent.base } }
    VIcon { visible: !hero.glyph; anchors.centerIn: parent; name: hero.icon; weight: hero.on ? "fill" : "regular"; size: parent.width * Theme.layout.icon.badge
      color: hero.on ? Theme.r.ink.onAccent : Theme.r.popover.ink }
    Loader { anchors.centerIn: parent; sourceComponent: hero.glyph }
    Spring { id: heroPress; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: heroMouse.pressed ? Theme.scale("press") : 1 }
    scale: heroPress.value
    MouseArea { id: heroMouse; anchors.fill: parent; onClicked: hero.badgeTapped() }
  }
  Column {
    x: heroBadge.x + heroBadge.width + Theme.layout.module.pad; width: heroTrail.x - x - Theme.layout.module.pad
    anchors.verticalCenter: parent.verticalCenter
    VText { width: parent.width; elide: Text.ElideRight; text: hero.title; color: Theme.r.popover.ink; font.pixelSize: Theme.m.type.title; font.weight: Font.DemiBold }
    VText { width: parent.width; elide: Text.ElideRight; text: hero.subtitle; tone: "secondary" }
  }
  Item { id: heroTrail; anchors.right: parent.right; anchors.rightMargin: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter
    width: childrenRect.width; height: childrenRect.height }
}