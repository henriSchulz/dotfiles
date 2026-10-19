import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// The Dock's menu body on Velum's menu roles (after henri-ui MenuList, same API):
// the highlight jumps with the pointer or the keys (↑ ↓ Home End ⏎ →), separators,
// shortcuts, disabled / danger entries, a check column when any entry has
// `checked`, submenus (`submenu: […]` shows a chevron, submenuRequested after
// a short hover), and the NSMenu blink before `activated` fires.
FocusScope {
  id: root

  property var model: []
  property int currentIndex: -1
  property real minWidth: Theme.m.menu.minWidth
  property bool flashing: false
  property int lockedIndex: -1
  // the roles to draw with (the dock hands in its own appearance)
  property var r: Theme.r

  signal activated(int index, var entry)
  signal submenuRequested(int index, var entry, Item row)
  readonly property int highlightIndex: currentIndex >= 0 ? currentIndex : lockedIndex
  property bool _blinkOff: false

  function hasSubmenu(i) { var e = entry(i); return e !== null && !!e.submenu }
  function requestSubmenu(i) {
    if (!selectable(i) || !hasSubmenu(i)) return
    currentIndex = i
    submenuRequested(i, entry(i), rep.itemAt(i))
  }
  readonly property bool hasCheckColumn: {
    for (var i = 0; i < model.length; i++) if (model[i] && model[i].checked !== undefined) return true
    return false
  }

  implicitWidth: Math.max(minWidth, col.rowsWidth)
  implicitHeight: col.implicitHeight

  function entry(i) { return i >= 0 && i < model.length ? model[i] : null }
  function selectable(i) {
    var e = entry(i)
    return e !== null && !e.separator && e.enabled !== false
  }
  function move(step) {
    var n = model.length
    if (n === 0) return
    var i = currentIndex
    for (var k = 0; k < n; k++) {
      i = (i + step + n) % n
      if (selectable(i)) { currentIndex = i; return }
    }
  }
  function activate(i) {
    if (flashing || !selectable(i)) return
    if (hasSubmenu(i)) { requestSubmenu(i); return }
    currentIndex = i
    flashing = true
    flash.restart()
  }

  SequentialAnimation {
    id: flash
    ScriptAction { script: root._blinkOff = true }
    PauseAnimation { duration: Theme.dur("flash") }
    ScriptAction { script: root._blinkOff = false }
    PauseAnimation { duration: Theme.dur("flash") }
    ScriptAction {
      script: {
        root.flashing = false
        root.activated(root.currentIndex, root.entry(root.currentIndex))
      }
    }
  }

  Keys.onUpPressed: move(-1)
  Keys.onDownPressed: move(1)
  Keys.onPressed: function(e) {
    if (e.key === Qt.Key_Home) { currentIndex = -1; move(1); e.accepted = true }
    else if (e.key === Qt.Key_End) { currentIndex = 0; move(-1); e.accepted = true }
    else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { activate(currentIndex); e.accepted = true }
    else if (e.key === Qt.Key_Right && hasSubmenu(currentIndex)) { requestSubmenu(currentIndex); e.accepted = true }
  }

  Timer {
    id: submenuHover
    interval: Theme.delay("submenu")
    onTriggered: if (root.currentIndex >= 0 && root.hasSubmenu(root.currentIndex) && root.lockedIndex !== root.currentIndex) root.requestSubmenu(root.currentIndex)
  }

  HoverHandler {
    onHoveredChanged: if (!hovered && !root.flashing && root.lockedIndex < 0) root.currentIndex = -1
  }

  // the highlight jumps (never glides)
  Rectangle {
    readonly property Item row: root.highlightIndex >= 0 ? rep.itemAt(root.highlightIndex) : null
    visible: row !== null && !root._blinkOff
    x: 0; y: row ? row.y : 0
    width: root.width; height: row ? row.height : 0
    radius: Theme.m.radius.menuRow
    gradient: Gradient {
      GradientStop { position: 0; color: root.r.menu.highlightTop }
      GradientStop { position: 1; color: root.r.menu.highlight }
    }
  }

  Column {
    id: col
    width: root.width
    readonly property real rowsWidth: {
      var w = 0
      for (var i = 0; i < rep.count; i++) { var it = rep.itemAt(i); if (it) w = Math.max(w, it.implicitWidth) }
      return w
    }

    Repeater {
      id: rep
      model: root.model

      delegate: Item {
        id: row
        required property int index
        required property var modelData
        readonly property bool isSeparator: modelData.separator === true
        readonly property bool isCurrent: root.highlightIndex === index && !root._blinkOff
        readonly property bool hasSubmenu: !!modelData.submenu
        readonly property color textColor: isCurrent ? root.r.menu.highlightInk
          : modelData.danger ? root.r.menu.danger : root.r.menu.ink
        readonly property real padX: Theme.layout.menu.itemPadX

        width: col.width
        height: isSeparator ? 2 * Theme.layout.menu.separatorGap + Theme.layout.separator : Theme.m.menu.row
        opacity: modelData.enabled === false ? Theme.core.alpha.disabled : 1
        implicitWidth: isSeparator ? 0 : content.implicitWidth + padX * 2
          + (trail.visible ? trail.implicitWidth + Theme.layout.menu.keyGap : 0)

        Rectangle {
          visible: row.isSeparator
          anchors.verticalCenter: parent.verticalCenter
          x: row.padX; width: parent.width - row.padX * 2
          height: Theme.layout.separator
          color: root.r.menu.line
        }

        Row {
          id: content
          visible: !row.isSeparator
          anchors.verticalCenter: parent.verticalCenter
          x: row.padX
          spacing: Theme.layout.menu.glyphGap
          Item {
            visible: root.hasCheckColumn
            width: Theme.layout.icon.small; height: width
            anchors.verticalCenter: parent.verticalCenter
            VIcon { anchors.centerIn: parent; visible: row.modelData.checked === true; name: "check"; weight: "bold"; size: Theme.layout.icon.small; color: row.textColor }
          }
          Text {
            text: row.modelData.text || ""
            color: row.textColor
            font.family: Theme.font
            font.pixelSize: Theme.m.menu.font
            font.weight: Theme.m.menu.weight
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        Item {
          id: trail
          visible: !row.isSeparator && (!!row.modelData.shortcut || row.hasSubmenu)
          implicitWidth: row.hasSubmenu ? Theme.layout.icon.small : key.implicitWidth
          width: implicitWidth; height: parent.height
          anchors.right: parent.right
          anchors.rightMargin: row.padX
          Text {
            id: key
            visible: !row.hasSubmenu
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            text: row.modelData.shortcut || ""
            color: row.isCurrent ? root.r.menu.highlightInk : root.r.menu.inkSecondary
            font.family: Theme.font
            font.pixelSize: Theme.m.menu.font
          }
          VIcon { visible: row.hasSubmenu; anchors.centerIn: parent; name: "chevron.right"; weight: "bold"; size: Theme.layout.icon.small
            color: row.isCurrent ? root.r.menu.highlightInk : root.r.menu.inkSecondary }
        }

        HoverHandler {
          enabled: !row.isSeparator && !root.flashing
          onHoveredChanged: if (hovered && root.selectable(row.index)) {
            root.currentIndex = row.index
            if (row.hasSubmenu) submenuHover.restart()
          }
        }
        TapHandler {
          enabled: !row.isSeparator
          onTapped: root.activate(row.index)
        }
      }
    }
  }
}
