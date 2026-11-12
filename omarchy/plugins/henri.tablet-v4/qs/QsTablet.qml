import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// The Tablet page (lab QsPages.jsx TabletPage): the tablet that shows this machine (ipadcast's cast.json) —
// its name (ipad-link's journal: QsBackend.tabletName), its battery, the link, the stream's latency / picture /
// encoder, today's history (ipad-link's CSV) and its switches (henri.cast-v3's events to ipadcast). Without a
// cast: one line.
Item {
  id: pg
  property var backend: null
  readonly property var k: Theme.core.surface.material.qs
  readonly property bool connected: !!backend && backend.castConnected
  readonly property var c: connected ? backend.cast : ({})
  implicitHeight: connected ? col.height : none.height
  readonly property var switches: [
    { key: "macInput", text: "This Mac’s keyboard and trackpad" },
    { key: "perf", text: "Performance" },
    { key: "fast", text: "Low latency" },
    { key: "mic", text: "Microphone" }]
  function isOn(key) {
    if (!backend) return false
    return key === "macInput" ? backend.shown("tablet.macInput", c.macInput !== false) : backend.tabletOn(key)
  }

  MText { id: none; visible: !pg.connected; text: "No tablet is casting."; tone: "secondary" }
  Column {
    id: col
    visible: pg.connected
    width: pg.width
    spacing: pg.k.pages.gap
    Item {
      width: pg.width
      height: Math.max(pg.k.tablet.icon, who.height)
      VIcon { id: glyph; anchors.verticalCenter: parent.verticalCenter; name: "tablet"; size: pg.k.tablet.icon; color: Theme.r.popover.ink }
      Column {
        id: who
        x: glyph.width + pg.k.pages.gap
        width: chip.x - x - pg.k.pages.gap
        anchors.verticalCenter: parent.verticalCenter
        MText { width: parent.width; text: pg.backend ? pg.backend.tabletName : ""; size: "subtitle"; medium: true }
        MText { width: parent.width; tone: "secondary"
          text: Math.round(pg.c.battery || 0) + "%" + (pg.c.state === "Charging" ? " · charging" : "") + (pg.c.mode ? " · " + pg.c.mode : "") }
      }
      Rectangle {
        id: chip
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: pg.k.tablet.chip; radius: height / 2
        width: chipRow.width + 2 * pg.k.tablet.chipPad
        color: Qt.alpha(Theme.r.popover.ink, pg.k.tablet.chipAlpha)
        Row {
          id: chipRow
          anchors.centerIn: parent
          spacing: pg.k.status.gap
          VIcon { anchors.verticalCenter: parent.verticalCenter; name: pg.c.link === "cable" ? "cable" : "wifi"; size: pg.k.tablet.chipIcon; color: Theme.r.popover.inkSecondary }
          MText { anchors.verticalCenter: parent.verticalCenter; size: "small"; text: pg.c.link === "cable" ? "Cable" : "Wi-Fi" }
        }
      }
    }
    QsBar { width: pg.width; value: (pg.c.battery || 0) / 100 }
    Row {
      width: pg.width
      QsStat { width: pg.width / pg.k.battery.stats; label: "Latency"; value: pg.c.latency !== undefined && pg.c.latency !== null ? Math.round(pg.c.latency) + " ms" : "" }
      QsStat { width: pg.width / pg.k.battery.stats; label: "Picture"; value: pg.c.size ? pg.c.size[0] + "×" + pg.c.size[1] : "" }
      QsStat { width: pg.width / pg.k.battery.stats; label: "Encoder"; value: pg.c.encoder || "" }
    }
    Column {
      width: pg.width
      MText { text: "Today"; size: "caption"; tone: "secondary" }
      QsChart { width: pg.width; points: pg.backend ? pg.backend.tabletHistory : [] }
    }
    Column {
      width: pg.width
      Repeater {
        model: pg.switches
        Item {
          required property var modelData
          width: pg.width; height: pg.k.tablet.row
          MText { anchors.verticalCenter: parent.verticalCenter; width: parent.width - sw.width; text: parent.modelData.text; medium: true }
          MSwitch {
            id: sw
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            checked: pg.isOn(parent.modelData.key)
            onToggled: on => pg.backend.setTablet(parent.modelData.key, on)
          }
          TapHandler { onTapped: point => { if (point.position.x < parent.width - sw.width) sw.toggled(!sw.checked) } }
        }
      }
    }
  }
}
