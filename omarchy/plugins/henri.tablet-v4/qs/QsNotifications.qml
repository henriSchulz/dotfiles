import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// The notifications column of the split shade (lab QsPages.jsx Notifications): the shell's history, newest
// first; a card follows a sideways finger and goes past surface.material.qs.notif.dismiss of the column's
// width (it only hides here — the history files stay), Clear all hides every card. The cards live in a
// ListModel kept in step with the backend, so a card that goes leaves the others in place and they move up
// (displaced: translation only); nothing is rebuilt on a poll.
Item {
  id: col
  property var backend: null
  property real maxHeight: 0
  property real now: Date.now()
  readonly property var k: Theme.core.surface.material.qs
  readonly property int count: model.count
  implicitHeight: count ? Math.min(maxHeight, list.contentHeight + k.notif.gap + clear.height) : empty.height

  ListModel { id: model }
  function sync() {
    const want = backend ? backend.notificationsShown : []
    const ids = want.map(n => n.id)
    for (let i = model.count - 1; i >= 0; i--) if (ids.indexOf(model.get(i).nid) < 0) model.remove(i)
    for (let j = 0; j < want.length; j++) {
      if (j < model.count && model.get(j).nid === want[j].id) continue
      let at = -1
      for (let i = j; i < model.count; i++) if (model.get(i).nid === want[j].id) { at = i; break }
      const n = want[j]
      if (at >= 0) model.move(at, j, 1)
      else model.insert(j, { nid: n.id, napp: n.app, nsummary: n.summary, nbody: n.body, ntime: n.time })
    }
  }
  Connections { target: col.backend; function onNotificationsShownChanged() { col.sync() } }
  Component.onCompleted: sync()

  function ago(t) {
    const m = Math.round((col.now - t) / 60000)
    return m < 1 ? "now" : m < 60 ? m + " min" : m < 1440 ? Math.round(m / 60) + " h" : Math.round(m / 1440) + " d"
  }

  Column {
    id: empty
    visible: col.count === 0
    width: col.width
    topPadding: col.k.header.gap
    bottomPadding: col.k.header.gap
    spacing: col.k.header.gap
    VIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "notification"; size: col.k.header.icon; color: Theme.r.popover.inkSecondary }
    MText { anchors.horizontalCenter: parent.horizontalCenter; text: "No notifications"; tone: "secondary" }
  }

  ListView {
    id: list
    visible: col.count > 0
    width: col.width
    height: Math.min(contentHeight, col.maxHeight - col.k.notif.gap - clear.height)
    model: model
    spacing: col.k.notif.gap
    clip: true
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds
    displaced: Transition { NumberAnimation { property: "y"; duration: Theme.dur("base"); easing.bezierCurve: Theme.curve("out") } }
    delegate: Item {
      id: card
      required property string nid
      required property string napp
      required property string nsummary
      required property string nbody
      required property real ntime
      objectName: "card-" + index
      required property int index
      width: list.width
      height: body.height + 2 * col.k.notif.pad
      readonly property real dx: drag.active ? drag.lastDx : fling.value
      property real away: 0
      Spring { id: fling; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: card.away
        onValueChanged: if (card.away !== 0 && Math.abs(value) >= card.width && col.backend) col.backend.hide(card.nid) }
      Rectangle {
        width: parent.width; height: parent.height
        radius: col.k.notif.radius
        color: Qt.alpha(Theme.r.popover.ink, col.k.notif.alpha)
        transform: Translate { x: card.dx }
        opacity: 1 - Math.min(col.k.notif.fadeMax, Math.abs(card.dx) / col.width)
        Column {
          id: body
          x: col.k.notif.pad; y: col.k.notif.pad
          width: parent.width - 2 * col.k.notif.pad
          MText { width: parent.width; size: "caption"; tone: "secondary"; text: card.napp + " · " + col.ago(card.ntime) }
          MText { width: parent.width; medium: true; text: card.nsummary }
          MText { width: parent.width; visible: card.nbody !== ""; tone: "secondary"; text: card.nbody; wrapMode: Text.WordWrap; maximumLineCount: 4 }
        }
      }
      DragHandler {
        id: drag
        target: null
        yAxis.enabled: false
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        property real lastDx: 0              // translation is reset when the handler lets go
        onTranslationChanged: if (active) lastDx = translation.x
        onActiveChanged: {
          if (active) { lastDx = 0; return }
          const x = lastDx
          if (Math.abs(x) > col.width * col.k.notif.dismiss) card.away = (x < 0 ? -1 : 1) * card.width * 2
          fling.from(x)
        }
      }
    }
  }

  // Clear all: a capsule at the end of the column
  Item {
    id: clear
    objectName: "clear"
    visible: col.count > 0
    anchors.right: parent.right
    y: list.y + list.height + col.k.notif.gap
    width: clearLabel.width + 2 * col.k.notif.clearPad
    height: col.k.notif.clearH
    Rectangle { anchors.fill: parent; radius: height / 2; color: Qt.alpha(Theme.r.popover.ink, col.k.notif.clearAlpha) }
    Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.r.popover.ink; opacity: clearArea.pressed ? Theme.core.alpha.pressed : 0 }
    MText { id: clearLabel; anchors.centerIn: parent; medium: true; text: "Clear all" }
    TapHandler { id: clearArea; onTapped: if (col.backend) col.backend.hideAll() }
  }
}
