// Tests unitaires du Model — exécuter avec : node Model.test.js
const Model = require("./Model.js")

let failures = 0

function check(name, actual, expected) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a === e) {
    console.log("ok   " + name)
  } else {
    failures++
    console.log("FAIL " + name + "\n     got:  " + a + "\n     want: " + e)
  }
}

// ---- non régression de la base ----
check("parseKeyValue tab", Model.parseKeyValue("size\t57 Wh\ncycles\t0"), { size: "57 Wh", cycles: "0" })
check("parseProfiles", Model.parseProfiles("balanced\t1\nperformance\t0", 0),
  { profiles: ["balanced", "performance"], activeProfile: "balanced", profileIndex: 0 })
check("clampIndex 5/3", Model.clampIndex(5, 3), 2)
check("clampIndex -2/3", Model.clampIndex(-2, 3), 0)

// ---- historique de la batterie ----
const day = new Date(2026, 8, 18)
check("historyFileName", Model.historyFileName(day), "akku-2026-09-18.csv")
const csv = [
  "zeit,status,prozent,energie_wh,leistung_w,spannung_v,strom_a,voll_wh,temperatur_c,zyklus_wh",
  "10:00:00,Discharging,80,26.0,10.00,7.5,1.3,33.0,34.0,0.000",
  "10:02:00,Discharging,79,25.6,10.00,7.4,1.3,33.0,35.5,0.333",
  "10:04:00,LUECKE,,,,,,,,0.333",
  "10:30:00,Discharging,70,21.0,12.00,7.4,1.6,33.0,35.0,0.333",
  "11:00:00,Charging,60,19.0,20.00,7.8,2.5,33.0,33.0,0.000",
  "11:02:00,Charging,62,20.0,20.00,7.8,2.5,33.0,33.0,0.000",
  "garbage"
].join("\n")
const parsed = Model.parseHistoryCsv(csv, day)
check("parse: count", parsed.length, 6)
check("parse: gap", parsed[2].gap, true)
check("parse: time", parsed[0].t, new Date(2026, 8, 18, 10, 0, 0).getTime())
check("parse: pct/w", [parsed[1].pct, parsed[1].w, parsed[1].fullWh], [79, 10, 33])
check("parse: volts/amps", [parsed[1].v, parsed[1].a], [7.4, 1.3])

const now = new Date(2026, 8, 18, 11, 2, 0).getTime()
const win = Model.historyWindow(parsed, now, 24)
// 10:30 → 11:00 is a jump longer than 150 s: a gap is inserted
check("window: jump becomes gap", win.map(p => p.gap), [false, false, true, false, true, false, false])
const st = Model.historyStats(win)
const near = (a, b) => Math.abs(a - b) < 1e-9
check("stats: on battery 2 min", near(st.onBatteryH, 2 / 60), true)
check("stats: used", near(st.usedWh, 10 * 2 / 60), true)
check("stats: avg needs 10 min", st.avgDrawW, null)
check("stats: charged", near(st.chargedWh, 20 * 2 / 60), true)
check("stats: min/max", [st.minPct, st.maxPct, st.maxTemp], [60, 80, 35.5])
check("stats: charging now", [st.discharging, st.cycleWh], [false, null])
check("stats: last sample", [st.lastPct, st.lastT === win[win.length - 1].t], [win[win.length - 1].pct, true])
check("window: cut", Model.historyWindow(parsed, now, 0.5).length, 2)
check("stats: empty", Model.historyStats([]).samples, false)

// une heure de décharge à 11 W, échantillons toutes les 30 s
const run = []
for (let i = 0; i <= 120; i++)
  run.push({ t: i * 30000, gap: false, status: "Discharging", pct: 90 - i / 10, w: 11, fullWh: 33, temp: 30, cycleWh: i * 11 / 120 })
const rs = Model.historyStats(run)
check("run: avg", near(rs.avgDrawW, 11), true)
check("run: runtime", near(rs.runtimeH, 3), true)
check("run: cycle", [rs.discharging, rs.cycleWh, rs.cycleStart], [true, 11, 0])

check("duration 45 min", Model.durationText(0.75), "45 min")
check("duration 2 h 50", Model.durationText(2 + 50 / 60), "2 h 50 min")
check("duration 3 h", Model.durationText(3), "3 h")
check("duration null", Model.durationText(null), "—")

// barres : 3 créneaux d'une heure
const bNow = 3 * 3600000
const bPts = [
  { t: 10 * 60000, gap: false, status: "Discharging", pct: 80, w: 10 },
  { t: 50 * 60000, gap: false, status: "Discharging", pct: 75, w: 12 },
  { t: 150 * 60000, gap: false, status: "Charging", pct: 60, w: 20 },
  { t: 170 * 60000, gap: true }
]
const bars = Model.historyBuckets(bPts, bNow, 3, 3)
check("buckets: first", [bars[0].pct, bars[0].battery, bars[0].w], [75, true, 11])
check("buckets: empty slot", bars[1], null)
check("buckets: plugged", [bars[2].pct, bars[2].battery], [60, false])

const vaPts = [
  { t: 10 * 60000, gap: false, status: "Discharging", pct: 80, w: 10, v: 7.4, a: 1.2 },
  { t: 50 * 60000, gap: false, status: "Discharging", pct: 75, w: 12, v: 7.6, a: null }
]
const vaBars = Model.historyBuckets(vaPts, bNow, 3, 3)
check("buckets: volt/amp means", [vaBars[0].v, vaBars[0].a], [7.5, 1.2])

// remplissage entre deux échantillons consécutifs (créneaux de 20 s)
const fPts = [
  { t: 0, gap: false, status: "Discharging", pct: 50, w: 8 },
  { t: 60000, gap: false, status: "Discharging", pct: 49, w: 9 }
]
const fBars = Model.historyBuckets(fPts, 60000, 1 / 60, 3)
check("buckets: filled", [fBars[1].pct, fBars[1].w], [50, 8])

check("range: key", Model.historyRange("15m").hours, 0.25)
check("range: legacy hours", Model.historyRange("12").key, "12h")
check("range: unknown", Model.historyRange("5y"), null)
const days = Model.historyDays(new Date(2026, 8, 22, 15), 72)
check("days", days.map(d => d.name), ["akku-2026-09-19.csv", "akku-2026-09-20.csv", "akku-2026-09-21.csv", "akku-2026-09-22.csv"])
check("days: iPad", Model.historyDays(new Date(2026, 8, 22, 15), 6, "ipad").map(d => d.name), ["ipad-2026-09-21.csv", "ipad-2026-09-22.csv"])
check("source: iPad", Model.historySource("iPad").prefix, "ipad")
check("source: unknown", Model.historySource("phone"), null)
check("watt scale", Model.historyWattScale([null, { w: 12.3 }, { w: null }]), 20)
check("watt scale: empty", Model.historyWattScale([]), 5)

// ---- métriques et axes ----
check("metric: alias", Model.historyMetric("current").key, "amps")
check("metric: legacy watts", Model.historyMetric("watts").label, "Power")
check("metric: unknown", Model.historyMetric("ohms"), null)
check("axis: charge", Model.historyAxis([], "percent"), { min: 0, max: 100 })
check("axis: amps", Model.historyAxis([null, { a: 1.4 }, { a: null }], "amps"), { min: 0, max: 2 })
// 7.03–8.53 V : pas de 0,5 V, un nombre pair de pas -> ligne du milieu à 8 V
check("axis: volts fits the range", Model.historyAxis([{ v: 7.033 }, { v: 8.532 }], "volts"), { min: 7, max: 9 })
check("axis: volts, no samples", Model.historyAxis([null], "volts"), { min: 7, max: 9 })
check("axis: volts, flat", Model.historyAxis([{ v: 7.5 }, { v: 7.52 }], "volts"), { min: 7.4, max: 7.6 })
const tNow = new Date(2026, 8, 22, 14, 7).getTime()
const tk = Model.historyTicks(tNow - 15 * 60000, tNow, 6)
check("ticks: 15 min", [tk.step, tk.ticks.length, new Date(tk.ticks[0]).getMinutes()], [5, 3, 55])
const tw = Model.historyTicks(tNow - 168 * 3600000, tNow, 7)
check("ticks: 7 days", [tw.step, tw.ticks.length, new Date(tw.ticks[0]).getHours()], [1440, 7, 0])

if (failures > 0) {
  console.log("\n" + failures + " échec(s)")
  process.exit(1)
}
console.log("\nTous les tests passent.")
