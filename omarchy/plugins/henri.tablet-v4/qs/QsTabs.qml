import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// Material's fixed tabs (MUI Tabs fullWidth, lab QuickSettings.jsx): equal tabs, the current one in the accent
// with a line under it. `position` is the page shown (a fraction while a finger turns it), so the line follows
// the finger; it moves by transform only.
Item {
  id: tabs
  property var model: []                  // ["Controls", …]
  property int current: 0
  property real position: current
  signal chosen(int index)
  readonly property var k: Theme.core.surface.material.qs
  readonly property real w: model.length ? width / model.length : 0
  implicitHeight: k.tabs.height
  Repeater {
    model: tabs.model
    Item {
      required property string modelData
      required property int index
      objectName: "tab-" + index
      x: index * tabs.w; width: tabs.w; height: tabs.height
      Rectangle { anchors.fill: parent; color: Theme.r.popover.ink; opacity: tap.pressed ? Theme.core.alpha.pressed : 0 }
      MText { anchors.centerIn: parent; medium: true; text: parent.modelData
        color: Math.round(tabs.position) === parent.index ? Theme.r.accent.text : Theme.r.popover.inkSecondary }
      TapHandler { id: tap; onTapped: tabs.chosen(parent.index) }
    }
  }
  Rectangle {
    y: tabs.height - height
    width: tabs.w; height: tabs.k.tabs.indicator
    color: Theme.r.accent.base
    transform: Translate { x: tabs.position * tabs.w }
  }
}
