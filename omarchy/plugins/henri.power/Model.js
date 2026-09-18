function clampIndex(index, length) {
  if (length <= 0) return 0
  return Math.max(0, Math.min(length - 1, index))
}

function selectProfileIndex(index, delta, profiles) {
  var values = Array.isArray(profiles) ? profiles : []
  if (values.length === 0) return 0
  return clampIndex(index + delta, values.length)
}

function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx <= 0) continue
    next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim()
  }
  return next
}

function parseProfiles(raw, previousIndex) {
  var lines = String(raw || "").split("\n")
  var list = []
  var active = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split("\t")
    list.push(parts[0])
    if (parts[1] === "1") active = parts[0]
  }
  return {
    profiles: list,
    activeProfile: active,
    profileIndex: clampIndex(previousIndex || 0, list.length)
  }
}

function profileIcon(name) {
  if (name === "power-saver") return "󰌪"
  if (name === "balanced") return "󰊚"
  if (name === "performance") return "󰓅"
  return "󰂄"
}

function batteryFraction(device) {
  return device && device.isPresent ? Math.max(0, Math.min(1, device.percentage)) : 0
}

function chargeThresholdActive(device, onBattery, states) {
  var d = device || {}
  var s = states || {}
  if (!(d && d.isPresent && !onBattery)) return false

  var fraction = batteryFraction(d)
  if (d.state === s.Discharging) return false
  if (d.state === s.PendingCharge) return true
  if (d.state === s.FullyCharged && fraction < 0.99) return true
  if (d.state !== s.Charging || fraction >= 0.99) return false

  return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60
}

function batteryIcon(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
  var defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
  var index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)))
  var threshold = chargeThresholdActive(d, onBattery, states)

  if (threshold) return defaultIcons[index]
  if (d.state === states.FullyCharged) return "󰂅"
  if (!onBattery) return chargingIcons[index]
  return defaultIcons[index]
}

function modeLabel(device, onBattery, states) {
  var d = device || {}
  if (!d.isPresent) return ""

  var percentage = d.isPresent ? d.percentage : 0
  if (chargeThresholdActive(d, onBattery, states)) return "Threshold"
  if (onBattery) return "On battery"
  if (!onBattery && percentage >= 1) return "Fully charged"
  return "Charging"
}

// ---- Dell charge-limit helpers -------------------------------------------
// Threshold constraints discovered on the Latitude 7390 EC (the Alienware
// x16 R2 BIOS settings CustomChargeStart/Stop report the same ranges):
//   start 50–95, end 55–100, end >= start + 5

const DELL_START_MIN = 50
const DELL_START_MAX = 95
const DELL_END_MIN = 55
const DELL_END_MAX = 100
const DELL_GAP = 5

const DELL_MODES = ["Standard", "Express", "Adaptive", "PrimAcUse", "Custom"]

const DELL_MODE_INFO = {
  Standard: "Charges to 100% at normal rate",
  Express: "Fast charge to 100%",
  Adaptive: "100% based on usage patterns (learning)",
  PrimAcUse: "Primary AC use — reduced ceiling",
  Custom: "Applies your charge thresholds (start → stop)"
}

function dellClampStart(value) {
  var v = Math.round(Number(value))
  if (!isFinite(v)) return DELL_START_MIN
  return Math.max(DELL_START_MIN, Math.min(DELL_START_MAX, v))
}

function dellClampEnd(value, start) {
  var v = Math.round(Number(value))
  if (!isFinite(v)) return DELL_END_MAX
  var floor = Math.max(DELL_END_MIN, dellClampStart(start) + DELL_GAP)
  return Math.max(floor, Math.min(DELL_END_MAX, v))
}

function dellStepStart(value, delta, step) {
  return dellClampStart(dellClampStart(value) + delta * step)
}

// Steps the end threshold while preserving end >= start + 5. Returns the
// requested stepped value clamped so that the invariant always holds.
function dellStepEnd(value, start, delta, step) {
  var cur = dellClampEnd(value, start)
  return dellClampEnd(cur + delta * step, start)
}

// Estimated time until the battery reaches the stop threshold while charging.
// Returns "" when the estimate is not meaningful (above the threshold,
// no meaningful rate, missing inputs).
function timeToThresholdText(endPercent, fraction, sizeWh, rateW) {
  var end = Number(endPercent)
  var frac = Number(fraction)
  var size = Number(sizeWh)
  var rate = Number(rateW)
  if (!isFinite(end) || !isFinite(frac) || !isFinite(size) || !isFinite(rate)) return ""
  if (frac >= end / 100) return ""
  if (rate <= 0.5) return ""
  if (size <= 0) return ""
  var minutes = Math.round((end / 100 - frac) * size / rate * 60)
  if (minutes < 1) return "<1m"
  if (minutes < 60) return minutes + "m"
  return Math.floor(minutes / 60) + "h " + (minutes % 60) + "m"
}

// end for a given start, adjusted to preserve the invariant.
function dellEndForStart(start, end) {
  return dellClampEnd(end, start)
}

// ---- Thermal profiles (platform_profile) ---------------------------------
// The kernel's platform_profile names in the order they are shown. A laptop
// lists the ones its firmware supports: Alienware laptops offer cool, quiet,
// balanced, balanced-performance, performance (G-Mode on the laptops that have
// it) and custom (the fans follow their boost values).

const THERMAL_ORDER = ["low-power", "cool", "quiet", "balanced", "balanced-performance", "performance", "custom"]

// The profiles power-profiles-daemon's three modes already reach.
const PPD_REACHABLE = ["low-power", "balanced", "performance"]

// Icons are Material Design codepoints of the Nerd Font (md-leaf, md-snowflake,
// md-weather_night, md-scale_balance, md-speedometer_medium, md-rocket_launch,
// md-fan).
const THERMAL_INFO = {
  "low-power": { label: "Low power", icon: 0xF032A, tip: "Lowest power draw and heat" },
  cool: { label: "Cool", icon: 0xF0717, tip: "Keeps the chassis cool to the touch" },
  quiet: { label: "Quiet", icon: 0xF0594, tip: "Keeps the fans as quiet as possible" },
  balanced: { label: "Balanced", icon: 0xF05D1, tip: "Balances noise, heat and performance" },
  "balanced-performance": { label: "Balanced+", icon: 0xF0F85, tip: "Balanced, leaning towards performance" },
  performance: { label: "Performance", icon: 0xF14DE, tip: "Full performance (G-Mode on Alienware laptops that have it)" },
  custom: { label: "Custom", icon: 0xF0210, tip: "The fans follow the boost values set below" }
}

const PROFILE_RE = /^[a-z-]{1,32}$/

function thermalChoices(thermal) {
  var list = thermal && Array.isArray(thermal.choices) ? thermal.choices : []
  return THERMAL_ORDER.filter(function (p) { return list.indexOf(p) >= 0 })
}

// Whether the firmware offers modes power-profiles-daemon cannot reach, which is
// when a picker of its own is worth showing.
function thermalExtended(thermal) {
  return thermalChoices(thermal).some(function (p) { return PPD_REACHABLE.indexOf(p) < 0 })
}

function thermalLabel(name) {
  var info = THERMAL_INFO[name]
  return info ? info.label : String(name || "")
}

function thermalIcon(name) {
  var info = THERMAL_INFO[name]
  return info ? String.fromCodePoint(info.icon) : ""
}

function thermalTip(name) {
  var info = THERMAL_INFO[name]
  return info ? info.tip : ""
}

function brandName(vendor) {
  return /alienware/i.test(String(vendor || "")) ? "Alienware" : "Dell"
}

function parseThermal(raw) {
  if (!raw || typeof raw !== "object") return null
  var choices = Array.isArray(raw.choices)
    ? raw.choices.filter(function (c) { return typeof c === "string" && PROFILE_RE.test(c) }).slice(0, 16)
    : []
  var profile = typeof raw.profile === "string" && PROFILE_RE.test(raw.profile) ? raw.profile : ""
  if (!profile || choices.length === 0) return null
  return {
    driver: typeof raw.driver === "string" ? raw.driver.slice(0, 64) : "",
    profile: profile,
    choices: choices
  }
}

function fanGroup(label) {
  var l = String(label || "").toLowerCase()
  if (l.indexOf("cpu") >= 0) return "cpu"
  if (l.indexOf("gpu") >= 0 || l.indexOf("video") >= 0) return "gpu"
  return ""
}

function finiteOrNull(v, lo, hi) {
  return typeof v === "number" && isFinite(v) && v >= lo && v <= hi ? v : null
}

function parseFans(sensors) {
  var list = sensors && Array.isArray(sensors.fans) ? sensors.fans : []
  return list.slice(0, 8).filter(function (f) { return f && typeof f === "object" }).map(function (f) {
    var label = typeof f.label === "string" && f.label.trim() ? f.label.trim().slice(0, 32) : "Fan"
    var max = finiteOrNull(f.max, 1, 100000)
    return {
      id: typeof f.id === "string" ? f.id.slice(0, 8) : "",
      label: label,
      group: fanGroup(label),
      rpm: finiteOrNull(f.rpm, 0, 100000),
      max: max,
      boost: finiteOrNull(f.boost, 0, 255)
    }
  })
}

function parseTemps(sensors) {
  var list = sensors && Array.isArray(sensors.temps) ? sensors.temps : []
  return list.slice(0, 8).filter(function (t) {
    return t && typeof t.label === "string" && finiteOrNull(t.c, 1, 149) !== null
  }).map(function (t) { return { label: t.label.slice(0, 16), c: Math.round(t.c) } })
}

// The fans of a group (cpu or gpu), and the boost they share: the highest one
// set, since the helper sets a whole group at once.
function groupFans(fans, group) {
  return (Array.isArray(fans) ? fans : []).filter(function (f) { return f.group === group })
}

function groupBoost(fans, group) {
  var best = null
  groupFans(fans, group).forEach(function (f) {
    if (f.boost !== null && (best === null || f.boost > best)) best = f.boost
  })
  return best
}

// Names to show for fans: a label several fans share gets a number.
function fanNames(fans) {
  var list = Array.isArray(fans) ? fans : []
  var totals = {}
  list.forEach(function (f) { totals[f.label] = (totals[f.label] || 0) + 1 })
  var seen = {}
  return list.map(function (f) {
    if (totals[f.label] < 2) return f.label
    seen[f.label] = (seen[f.label] || 0) + 1
    return f.label + " " + seen[f.label]
  })
}

// A fan's speed as a fraction of its maximum, for the little bar beside it.
function fanFraction(fan) {
  if (!fan || fan.rpm === null || fan.max === null) return 0
  return Math.max(0, Math.min(1, fan.rpm / fan.max))
}

function boostPercent(boost) {
  var b = Number(boost)
  if (!isFinite(b)) return 0
  return Math.round(Math.max(0, Math.min(255, b)) / 255 * 100)
}

function parsePowerChain(raw) {
  var text = String(raw || "").trim()
  if (!text) return null
  var obj = null
  try {
    obj = JSON.parse(text)
  } catch (e) {
    return null
  }
  if (!obj || typeof obj.source !== "string") return null
  function num(v) {
    return typeof v === "number" && isFinite(v) ? v : null
  }
  return {
    source: obj.source,
    usbType: typeof obj.usbType === "string" ? obj.usbType : "",
    batteryW: num(obj.batteryW),
    systemW: num(obj.systemW),
    adapterW: num(obj.adapterW),
    componentsW: num(obj.componentsW),
    cpuW: num(obj.cpuW),
    ramW: num(obj.ramW),
    screenW: num(obj.screenW),
    igpuW: num(obj.igpuW),
    nominalWh: num(obj.nominalWh),
    portW: num(obj.portW),
    packV: num(obj.packV),
    packA: num(obj.packA)
  }
}

function parseDellStatus(raw) {
  var text = String(raw || "").trim()
  if (!text) return null
  var obj = null
  try {
    obj = JSON.parse(text)
  } catch (e) {
    return null
  }
  if (!obj || obj.ok !== true) return null
  var wmi = obj.wmi && typeof obj.wmi === "object" ? obj.wmi : {}
  var thresholds = obj.thresholds && typeof obj.thresholds === "object" ? obj.thresholds : {}
  var hasThresholds = typeof thresholds.start === "number" && typeof thresholds.end === "number"
  var hasWmi = typeof wmi.mode === "string"
  var vendor = typeof obj.vendor === "string" ? obj.vendor.slice(0, 64) : ""
  return {
    ok: true,
    dell: obj.dell === true,
    vendor: vendor,
    brand: brandName(vendor),
    backend: obj.backend === "ec" || obj.backend === "sysman" ? obj.backend : "",
    source: String(obj.source || "cache"),
    hasThresholds: hasThresholds,
    hasWmi: hasWmi,
    start: hasThresholds ? thresholds.start : -1,
    end: hasThresholds ? thresholds.end : -1,
    mode: typeof wmi.mode === "string" ? wmi.mode : "",
    llc: typeof wmi.llc === "string" ? wmi.llc : "",
    usbPowerShare: typeof wmi.usbPowerShare === "string" ? wmi.usbPowerShare : "",
    typeCPower: typeof wmi.typeCPower === "string" ? wmi.typeCPower : "",
    peakShift: typeof wmi.peakShift === "string" ? wmi.peakShift : "",
    advBatteryCharge: typeof wmi.advBatteryCharge === "string" ? wmi.advBatteryCharge : "",
    thermal: parseThermal(obj.thermal),
    fans: parseFans(obj.sensors),
    temps: parseTemps(obj.sensors)
  }
}

// ---- Battery history (the akku-aufzeichnung logger, one CSV per day) ----
//
// Columns: zeit,status,prozent,energie_wh,leistung_w,spannung_v,strom_a,
// voll_wh,temperatur_c,zyklus_wh — a line every 30 s. A LUECKE line marks
// a sleep or a stopped service; a longer gap between two lines (the logger
// restarting at boot writes no marker) counts as one too.
var HISTORY_GAP_MS = 150 * 1000

function historyFileName(date) {
  function pad(n) { return (n < 10 ? "0" : "") + n }
  return "akku-" + date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate()) + ".csv"
}

// One day's CSV → samples. `day` is any Date on that day.
function parseHistoryCsv(raw, day) {
  var out = []
  var lines = String(raw || "").split("\n")
  var y = day.getFullYear(), m = day.getMonth(), d = day.getDate()
  function num(v) {
    if (v === undefined || v === "") return null
    var n = Number(v)
    return isFinite(n) ? n : null
  }
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].trim().split(",")
    var hms = /^(\d\d):(\d\d):(\d\d)$/.exec(f[0])
    if (!hms) continue
    var t = new Date(y, m, d, Number(hms[1]), Number(hms[2]), Number(hms[3])).getTime()
    if (f[1] === "LUECKE") {
      out.push({ t: t, gap: true })
      continue
    }
    var pct = num(f[2])
    if (pct === null) continue
    out.push({
      t: t,
      gap: false,
      status: f[1],
      pct: pct,
      wh: num(f[3]),
      w: num(f[4]),
      fullWh: num(f[7]),
      temp: num(f[8]),
      cycleWh: num(f[9])
    })
  }
  return out
}

// Samples of both days (older first), cut to the window ending at `now`.
// A time jump longer than HISTORY_GAP_MS becomes a gap marker.
function historyWindow(samples, now, hours) {
  var from = now - hours * 3600 * 1000
  var out = []
  var prev = null
  for (var i = 0; i < samples.length; i++) {
    var s = samples[i]
    if (s.t < from || s.t > now) continue
    if (s.gap) {
      if (prev && !prev.gap) out.push(s)
      prev = s
      continue
    }
    if (prev && !prev.gap && s.t - prev.t > HISTORY_GAP_MS)
      out.push({ t: prev.t + 1, gap: true })
    out.push(s)
    prev = s
  }
  return out
}

// Figures for the history section. Energy is integrated from the logged
// power over the time to the next sample, never across a gap.
function historyStats(points) {
  var onBatteryH = 0, usedWh = 0, chargedWh = 0, chargingH = 0
  var minPct = null, maxPct = null, maxTemp = null, last = null
  for (var i = 0; i < points.length; i++) {
    var a = points[i]
    if (a.gap) continue
    last = a
    if (minPct === null || a.pct < minPct) minPct = a.pct
    if (maxPct === null || a.pct > maxPct) maxPct = a.pct
    if (a.temp !== null && (maxTemp === null || a.temp > maxTemp)) maxTemp = a.temp
    var b = points[i + 1]
    if (!b || b.gap || a.w === null) continue
    var h = (b.t - a.t) / 3600000
    if (a.status === "Discharging") {
      onBatteryH += h
      usedWh += a.w * h
    } else if (a.status === "Charging") {
      chargingH += h
      chargedWh += a.w * h
    }
  }
  // Below ten minutes on battery the average is mostly noise.
  var avgDrawW = onBatteryH >= 1 / 6 ? usedWh / onBatteryH : null
  var fullWh = last ? last.fullWh : null
  var cycleStart = null
  if (last && last.status === "Discharging") {
    // The logger keeps counting zyklus_wh across a sleep, so walk back over
    // gaps too, up to the sample where the discharge began.
    for (var j = points.length - 1; j >= 0; j--) {
      if (points[j].gap) continue
      if (points[j].status !== "Discharging") break
      cycleStart = points[j].t
    }
  }
  return {
    samples: last !== null,
    onBatteryH: onBatteryH,
    usedWh: usedWh,
    chargingH: chargingH,
    chargedWh: chargedWh,
    avgDrawW: avgDrawW,
    runtimeH: avgDrawW && fullWh ? fullWh / avgDrawW : null,
    fullWh: fullWh,
    minPct: minPct,
    maxPct: maxPct,
    maxTemp: maxTemp,
    discharging: !!last && last.status === "Discharging",
    cycleWh: last && last.status === "Discharging" ? last.cycleWh : null,
    cycleStart: cycleStart
  }
}

// The window cut into `count` equal slots for the bar chart. Each slot holds
// the charge at its last sample (the level it ended on, like macOS), whether
// it was spent mostly on battery or plugged in, and the mean power; a slot
// without samples (sleep, laptop off) is null.
function historyBuckets(points, now, hours, count) {
  var span = hours * 3600 * 1000
  var from = now - span
  var slot = span / count
  var acc = []
  for (var i = 0; i < count; i++) acc.push(null)
  for (var j = 0; j < points.length; j++) {
    var p = points[j]
    if (p.gap || p.t < from || p.t > now) continue
    var k = Math.min(count - 1, Math.floor((p.t - from) / slot))
    var a = acc[k] || (acc[k] = { n: 0, battery: 0, wSum: 0, wN: 0, pct: 0, t: 0 })
    a.n++
    if (p.status === "Discharging") a.battery++
    if (p.w !== null) { a.wSum += p.w; a.wN++ }
    if (p.t >= a.t) { a.t = p.t; a.pct = p.pct }
  }
  return acc.map(function (a, idx) {
    if (!a) return null
    return {
      t0: from + idx * slot,
      t1: from + (idx + 1) * slot,
      pct: a.pct,
      battery: a.battery * 2 > a.n,
      w: a.wN > 0 ? a.wSum / a.wN : null
    }
  })
}

function durationText(hours) {
  if (hours === null || !isFinite(hours)) return "—"
  var mins = Math.round(hours * 60)
  if (mins < 60) return mins + " min"
  var h = Math.floor(mins / 60), m = mins % 60
  return h + " h" + (m > 0 ? " " + m + " min" : "")
}

if (typeof module !== "undefined") {
  module.exports = {
    HISTORY_GAP_MS: HISTORY_GAP_MS,
    historyFileName: historyFileName,
    parseHistoryCsv: parseHistoryCsv,
    historyWindow: historyWindow,
    historyStats: historyStats,
    historyBuckets: historyBuckets,
    durationText: durationText,
    clampIndex: clampIndex,
    selectProfileIndex: selectProfileIndex,
    parseKeyValue: parseKeyValue,
    parseProfiles: parseProfiles,
    profileIcon: profileIcon,
    batteryFraction: batteryFraction,
    chargeThresholdActive: chargeThresholdActive,
    batteryIcon: batteryIcon,
    modeLabel: modeLabel,
    DELL_START_MIN: DELL_START_MIN,
    DELL_START_MAX: DELL_START_MAX,
    DELL_END_MIN: DELL_END_MIN,
    DELL_END_MAX: DELL_END_MAX,
    DELL_GAP: DELL_GAP,
    DELL_MODES: DELL_MODES,
    DELL_MODE_INFO: DELL_MODE_INFO,
    dellClampStart: dellClampStart,
    dellClampEnd: dellClampEnd,
    dellStepStart: dellStepStart,
    dellStepEnd: dellStepEnd,
    timeToThresholdText: timeToThresholdText,
    dellEndForStart: dellEndForStart,
    THERMAL_ORDER: THERMAL_ORDER,
    thermalChoices: thermalChoices,
    thermalExtended: thermalExtended,
    thermalLabel: thermalLabel,
    thermalIcon: thermalIcon,
    thermalTip: thermalTip,
    brandName: brandName,
    parseThermal: parseThermal,
    fanGroup: fanGroup,
    parseFans: parseFans,
    parseTemps: parseTemps,
    groupFans: groupFans,
    groupBoost: groupBoost,
    fanNames: fanNames,
    fanFraction: fanFraction,
    boostPercent: boostPercent,
    parseDellStatus: parseDellStatus,
    parsePowerChain: parsePowerChain
  }
}
