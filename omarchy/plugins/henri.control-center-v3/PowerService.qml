import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "Model.js" as Model
import "file:///home/henri/.local/share/velum/qml/Velum"

// Everything the battery menu knows, without a face: UPower, the omarchy tools
// (battery status, power profiles, system stats), the kernel's battery uevent
// and the akku-test history log. Taken over from henri.power-v3
// (a fork of io.github.nipsen.dell-power, MIT); the Control Center's battery
// pages (PowerPages.qml) show it, and the right island of the bar shows the
// same pages through henri.power-v3. `opened` = a battery page is on screen:
// only then does it poll.
Item {
  id: root
  property bool opened: false

  property var batteryInfo: ({})
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""

  // ---- settings shared by every instance (Control Center and the bar island):
  //      ~/.local/state/velum/power.json { historyRange, historyMetric, historySource, historyDir }
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/velum/power.json"
  property var prefs: ({})
  FileView {
    id: prefsFile
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.prefs = JSON.parse(text()) || {} } catch (e) { root.prefs = {} } }
    onLoadFailed: root.prefs = {}
  }
  function pref(key, fallback) { return prefs[key] !== undefined ? prefs[key] : fallback }
  function savePref(key, value) {
    var p = Object.assign({}, prefs); p[key] = value; prefs = p
    prefsFile.setText(JSON.stringify(p, null, 2) + "\n")
  }

  // ---- history (the akku-test logger writes one CSV a day, a line every 30 s; ipad-link
  //      writes the casting iPad's beside it). historyPoints/Stats/Bars/Now are always this
  //      machine's (the overview's chart, FullCenter); the History page shows `historyLog`.
  HistoryLog { id: macLog; prefix: "akku"; dir: root.historyDir; hours: root.historyHours; barCount: root.historyBarCount; active: true }
  HistoryLog { id: ipadLog; prefix: "ipad"; dir: root.historyDir; hours: root.historyHours; barCount: root.historyBarCount
    active: root.opened && root.ipadLogged }
  readonly property var historyPoints: macLog.points
  readonly property var historyStats: macLog.stats
  readonly property var historyBars: macLog.bars
  readonly property real historyNow: macLog.now
  // the iPad's switch shows once ipad-link has written a file (never on a machine without the iPad)
  property bool ipadLogged: false
  readonly property var historySources: ipadLogged ? Model.HISTORY_SOURCES : []
  readonly property var historySource: (ipadLogged && Model.historySource(pref("historySource", ""))) || Model.historySource(Model.HISTORY_DEFAULT_SOURCE)
  readonly property var historyLog: historySource.key === "ipad" ? ipadLog : macLog
  function setHistorySource(key) { var src = Model.historySource(key); if (src && src.key !== historySource.key) savePref("historySource", src.key) }
  readonly property var historyRanges: Model.HISTORY_RANGES
  readonly property var historyRange: Model.historyRange(pref("historyRange", "")) || Model.historyRange(Model.HISTORY_DEFAULT_RANGE)
  readonly property real historyHours: historyRange.hours
  readonly property int historyBarCount: historyRange.bars
  readonly property var historyMetric: Model.historyMetric(pref("historyMetric", Model.HISTORY_DEFAULT_METRIC)) || Model.historyMetric(Model.HISTORY_DEFAULT_METRIC)
  readonly property var historyMetricKeys: Model.HISTORY_METRICS.map(function (m) { return m.key })
  readonly property var historyMetricLabels: Model.HISTORY_METRICS.map(function (m) { return m.label })
  readonly property string historyDir: String(pref("historyDir", "")) || Quickshell.env("HOME") + "/Projects/akku-test/verlauf"

  // Every spawned process runs with absolute executables and a closed, minimal
  // environment, so a shadowed binary earlier in PATH never runs.
  readonly property var procEnv: ({ "PATH": "/usr/share/omarchy/bin:/usr/bin:/bin" })

  readonly property var device: UPower.displayDevice
  readonly property bool batteryPresent: !!(device && device.isPresent)
  function upowerStates() {
    return { Charging: UPowerDeviceState.Charging, Discharging: UPowerDeviceState.Discharging,
             FullyCharged: UPowerDeviceState.FullyCharged, PendingCharge: UPowerDeviceState.PendingCharge }
  }
  readonly property bool discharging: !!(device && device.isPresent && UPower.onBattery)
  readonly property bool chargeThresholdActive: Model.chargeThresholdActive(device, discharging, upowerStates())
  readonly property bool fullyCharged: !!(device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !chargeThresholdActive)
  readonly property real batteryFraction: Model.batteryFraction(device)
  readonly property bool batteryFull: fullyCharged || (!discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive
  readonly property bool charging: !!(device && device.isPresent && !UPower.onBattery && !batteryFlowIdle)
  readonly property bool plugged: !discharging && !charging

  // ---- what it is doing: a phrase that rotates while current flows (crossfaded by the page)
  readonly property var chargingPhrases: ["Pumping power", "Injecting electrons", "Pouring juice", "Amassing watts", "Hoarding joules",
                                          "Sucking volts", "Topping reserves", "Soaking amps", "Inhaling kilowatts"]
  readonly property var onBatteryPhrases: ["Slurping power", "Spending joules", "Draining watts", "Burning electrons", "Sipping juice",
                                           "Spending coulombs", "Bleeding amps", "Guzzling volts", "Munching reserves"]
  property int phraseIndex: 0
  readonly property var activePhrases: fullyCharged ? [] : charging ? chargingPhrases : discharging ? onBatteryPhrases : []
  readonly property string statusText: fullyCharged ? "Fully Charged"
    : activePhrases.length ? activePhrases[phraseIndex % activePhrases.length] : Model.modeLabel(device, discharging, upowerStates())
  Timer {
    interval: 2800
    running: root.opened && root.activePhrases.length > 0
    repeat: true
    onTriggered: root.phraseIndex = (root.phraseIndex + 1) % Math.max(1, root.activePhrases.length)
  }

  // ---- overview values
  readonly property string sizeText: {
    var s = String(batteryInfo.size || "").replace(/(\d)([A-Za-z])/, "$1 $2")
    return s === "" ? "—" : s
  }
  readonly property string timeLabel: chargeThresholdActive ? "Charge Limit" : discharging ? "Time Left" : "Time to Full"
  readonly property string timeText: chargeThresholdActive ? (batteryInfo.threshold || "—")
    : batteryFlowIdle ? "—" : (batteryInfo.time || "—")
  readonly property string flowLabel: chargeThresholdActive ? "Battery" : discharging ? "Draw" : "Charging At"
  readonly property string flowText: chargeThresholdActive ? "Holding"
    : batteryFull ? "—"
    : device && Math.abs(device.changeRate) > 0.05 ? Math.abs(device.changeRate).toFixed(1) + " W" : (batteryInfo.rate || "—")

  function profileLabel(name) {
    return String(name).split("-").map(function (w) { return w.charAt(0).toUpperCase() + w.slice(1) }).join(" ")
  }
  function profileIcon(name) {
    return name === "power-saver" || name === "low-power" ? "leaf" : name === "performance" ? "energy" : "gauge"
  }

  function refresh() {
    if (!batteryPresent) return
    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
  }
  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // keep the last good data when a refresh briefly returns nothing (around plug/unplug)
    if (Object.keys(next).length === 0) return
    if (targetName === "battery") batteryInfo = next
    else systemInfo = next
  }
  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, 0)
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    if (!actionProc.running) activeProfile = parsed.activeProfile
  }
  function setProfile(profile) {
    if (!profile || actionProc.running) return
    activeProfile = profile          // optimistic: the card lights at once, the poll confirms
    actionProc.command = ["/usr/bin/timeout", "-k", "5", "15", "/usr/share/omarchy/bin/omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  // ---- history
  function refreshHistory() {
    macLog.refresh()
    if (ipadLog.active) ipadLog.refresh()
    if (!ipadProbe.running) ipadProbe.running = true
  }
  function rebuildHistory() { macLog.rebuild(); if (ipadLog.active) ipadLog.rebuild() }
  function setHistoryRange(key) { var r = Model.historyRange(key); if (r && r !== historyRange) savePref("historyRange", r.key) }
  function setHistoryMetric(key) { var m = Model.historyMetric(key); if (m && m.key !== historyMetric.key) savePref("historyMetric", m.key) }
  // a longer range may need older files first; refreshHistory rebuilds once they are in
  onHistoryRangeChanged: { if (historyStats !== null) refreshHistory(); Qt.callLater(rebuildHistory) }
  Process {
    id: ipadProbe
    command: ["/usr/bin/find", root.historyDir, "-maxdepth", "1", "-name", "ipad-*.csv", "-print", "-quit"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.ipadLogged = text.trim() !== "" }
  }
  function historyWatt(w) { return w === null || w === undefined || !isFinite(w) ? "—" : w.toFixed(1) + " W" }
  function historyValue(v, m) { return v === null || v === undefined || !isFinite(v) ? "—" : v.toFixed(m.decimals) + " " + m.unit }
  function historyAxisLabel(v, m) {
    if (v === null || v === undefined || !isFinite(v)) return "—"
    var txt = Math.abs(v - Math.round(v)) < 1e-6 ? String(Math.round(v)) : v.toFixed(m.decimals).replace(/0+$/, "").replace(/\.$/, "")
    return txt + " " + m.unit
  }
  function historyWh(wh) { return wh === null || wh === undefined || !isFinite(wh) ? "—" : wh.toFixed(1) + " Wh" }
  function clockText(t) { return Qt.formatTime(new Date(t), "HH:mm") }
  function durationText(h) { return Model.durationText(h) }
  function dischargeText(st) {
    if (!st || !st.discharging || st.cycleWh === null || st.cycleStart === null) return ""
    return "This discharge: " + historyWh(st.cycleWh) + " since " + clockText(st.cycleStart)
  }
  function chargeText(st) {
    if (!st || !st.samples || !(st.chargingH > 0)) return ""
    return "Charged " + historyWh(st.chargedWh) + " in " + Model.durationText(st.chargingH)
  }
  readonly property string historyDischargeText: dischargeText(historyStats)
  readonly property string historyChargeText: chargeText(historyStats)

  // health from the kernel (full / design capacity; UPower leaves it out on some batteries)
  property var kernelInfo: ({})
  readonly property real health: kernelInfo.full > 0 && kernelInfo.design > 0 ? Math.min(1, kernelInfo.full / kernelInfo.design)
                                 : device && device.healthSupported ? device.healthPercentage / 100 : -1
  function applyKernelInfo(raw) {
    String(raw || "").split("\n\n").forEach(function (block) {
      var x = {}
      block.split("\n").forEach(function (l) { var m = /^POWER_SUPPLY_([A-Z_]+)=(.*)$/.exec(l); if (m) x[m[1]] = m[2] })
      if (x.TYPE !== "Battery") return
      kernelInfo = { full: Number(x.ENERGY_FULL || x.CHARGE_FULL || 0), design: Number(x.ENERGY_FULL_DESIGN || x.CHARGE_FULL_DESIGN || 0) }
    })
  }
  Process {
    id: kernelProc
    command: ["/usr/bin/sh", "-c", "for f in /sys/class/power_supply/*/uevent; do /usr/bin/cat \"$f\"; echo; done"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyKernelInfo(text) }
  }

  onOpenedChanged: {
    if (!opened) return
    if (!kernelProc.running) kernelProc.running = true
    historySettle.restart()
    refresh()
  }
  // reading a day of samples waits until the surface has settled (never a frame of the opening)
  Timer { id: historySettle; interval: Theme.dur("slow") + Theme.delay("settle"); onTriggered: if (root.opened) root.refreshHistory() }
  Component.onCompleted: Qt.callLater(refresh)

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }
  Timer { interval: 30000; running: root.opened; repeat: true; onTriggered: root.refreshHistory() }

  Process {
    id: batteryProc
    clearEnvironment: true; environment: root.procEnv
    command: ["/usr/bin/timeout", "-k", "5", "15", "/usr/share/omarchy/bin/omarchy-battery-status", "--shell"]
    stdout: CappedCollector { proc: batteryProc; onFinished: t => root.updateKeyValue(t, "battery") }
  }
  Process {
    id: profilesProc
    clearEnvironment: true; environment: root.procEnv
    command: ["/usr/bin/timeout", "-k", "5", "15", "/usr/share/omarchy/bin/omarchy-powerprofiles-list", "--active-state"]
    stdout: CappedCollector { proc: profilesProc; onFinished: t => root.updateProfiles(t) }
  }
  Process {
    id: systemProc
    clearEnvironment: true; environment: root.procEnv
    command: ["/usr/bin/timeout", "-k", "5", "15", "/usr/share/omarchy/bin/omarchy-system-stats"]
    stdout: CappedCollector { proc: systemProc; onFinished: t => root.updateKeyValue(t, "system") }
  }
  Process { id: actionProc; clearEnvironment: true; environment: root.procEnv; onExited: root.refresh() }
  // One logger's daily CSVs (`prefix`-<date>.csv in `dir`), cut to the range and bucketed for the bars.
  // Inactive it reads nothing. Its last two files are read again on every refresh (today grows).
  component HistoryLog: Item {
    id: hlog
    property string prefix: "akku"
    property string dir: ""
    property real hours: 6
    property int barCount: 72
    property bool active: true
    property var points: []
    property var stats: null
    property var bars: []
    property real now: 0
    property var files: []
    property var texts: ({})
    property var parsed: ({})
    function refresh() {
      if (!active) return
      var days = Model.historyDays(new Date(), hours, prefix)
      var names = days.map(function (d) { return d.name }).join(",")
      if (names !== files.map(function (d) { return d.name }).join(",")) { files = days; return }
      for (var i = Math.max(0, views.count - 2); i < views.count; i++) {
        var fv = views.objectAt(i)
        if (fv) fv.reload()
      }
    }
    function setText(name, text) {
      var t = Object.assign({}, texts); t[name] = text; texts = t
      Qt.callLater(rebuild)
    }
    function rebuild() {
      var at = new Date(), samples = [], cache = {}
      for (var i = 0; i < files.length; i++) {
        var f = files[i], text = texts[f.name] || "", c = parsed[f.name]
        if (!c || c.len !== text.length) c = { len: text.length, samples: Model.parseHistoryCsv(text, f.day) }
        cache[f.name] = c
        samples = samples.concat(c.samples)
      }
      parsed = cache
      now = at.getTime()
      points = Model.historyWindow(samples, now, hours)
      stats = Model.historyStats(points)
      bars = Model.historyBuckets(points, now, hours, barCount)
    }
    onActiveChanged: if (active) refresh()
    Instantiator {
      id: views
      model: hlog.active ? hlog.files : []
      delegate: FileView {
        required property var modelData
        path: hlog.dir + "/" + modelData.name
        printErrors: false
        onLoaded: hlog.setText(modelData.name, text())
        onLoadFailed: hlog.setText(modelData.name, "")
      }
    }
  }

  // StdioCollector with a byte ceiling: past it the process is killed and the consumer gets ""
  // (keeps its last data), so a runaway binary cannot exhaust shell memory.
  component CappedCollector: StdioCollector {
    id: capped
    required property Process proc
    property int cap: 262144
    property bool overflow: false
    waitForEnd: true
    signal finished(string text)
    onDataChanged: if (!overflow && data.length > cap) { overflow = true; proc.signal(9) }
    onStreamFinished: { var was = overflow; overflow = false; finished(was ? "" : text) }
  }
}
