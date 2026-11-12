import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// The Battery page (lab QsPages.jsx BatteryPage): this machine's level, what it draws and how long it lasts,
// today's history (akku-test), health / cycles / capacity, and the power mode (power-profiles-daemon).
Column {
  id: pg
  property var backend: null
  readonly property var k: Theme.core.surface.material.qs
  readonly property var b: backend ? backend.battery : null
  readonly property bool charging: !!b && b.status === "Charging"
  spacing: k.pages.gap

  function minutes(s) {
    if (!(s > 0)) return ""
    return s >= 3600 ? Math.floor(s / 3600) + " h " + Math.round((s % 3600) / 60) + " min" : Math.round(s / 60) + " min"
  }
  readonly property string line: {
    if (!b) return ""
    const left = charging ? minutes(b.toFull) : minutes(b.toEmpty)
    return [b.status === "Discharging" ? "On battery" : b.status,
            b.watts ? b.watts.toFixed(1) + " W" : "",
            left !== "" ? left + (charging ? " to full" : " left") : ""].filter(x => x).join(" · ")
  }

  Item {
    width: pg.width
    height: big.height
    MText { id: big; size: "h3"; text: (pg.b && pg.b.capacity !== null ? Math.round(pg.b.capacity) : "—") + "%" }
    VIcon { id: bolt; visible: pg.charging; x: big.width + pg.k.header.gap; anchors.verticalCenter: big.verticalCenter
      name: "bolt"; weight: "fill"; size: pg.k.header.icon; color: Theme.r.accent.base }
    MText {
      x: (pg.charging ? bolt.x + bolt.width : big.width) + pg.k.header.gap
      width: pg.width - x
      anchors.baseline: big.baseline
      tone: "secondary"; text: pg.line
    }
  }
  QsBar {
    width: pg.width
    value: pg.b && pg.b.capacity !== null ? pg.b.capacity / 100 : 0
    low: !!pg.b && pg.b.status === "Discharging" && pg.b.capacity / 100 <= pg.k.battery.lowShare
  }
  Column {
    width: pg.width
    MText { text: "Today"; size: "caption"; tone: "secondary" }
    QsChart { width: pg.width; points: pg.backend ? pg.backend.history : [] }
  }
  Row {
    width: pg.width
    QsStat { width: pg.width / pg.k.battery.stats; label: "Health"; value: pg.b && pg.b.health ? pg.b.health : "" }
    QsStat { width: pg.width / pg.k.battery.stats; label: "Cycles"; value: pg.b && pg.b.cycles !== null ? String(Math.round(pg.b.cycles)) : "" }
    QsStat { width: pg.width / pg.k.battery.stats; label: "Capacity"
      value: pg.b && pg.b.design > 0 ? Math.round(pg.b.energyFull / pg.b.design * 100) + " %" : "" }
  }
  Column {
    width: pg.width
    spacing: pg.k.header.dateGap
    MText { text: "Power mode"; size: "caption"; tone: "secondary" }
    QsSegments {
      width: pg.width
      model: [{ key: "saver", text: "Saver" }, { key: "balanced", text: "Balanced" }, { key: "performance", text: "Performance" }]
      current: pg.backend ? pg.backend.powerMode : ""
      onChosen: key => { if (pg.backend) pg.backend.setPowerMode(key) }
    }
  }
}
