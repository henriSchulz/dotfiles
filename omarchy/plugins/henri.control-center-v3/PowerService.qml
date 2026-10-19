import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import "Model.js" as Model
import "file:///home/henri/.local/share/velum/qml/Velum"

// Everything the battery menu knows, without a face: UPower, the omarchy tools
// (battery status, power profiles, system stats), the root helper
// /usr/local/bin/dell-charge-limit (charge thresholds, power flow) and the
// akku-test history log. Taken over from henri.power-v3
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
  property var dellStatus: null
  property bool dellBusy: false
  property bool dellProbed: false
  property string dellError: ""
  property string dellActionOutput: ""
  property string dellActionError: ""
  property var dellActionArgs: []
  property bool dellTriedPkexec: false
  property bool dellActionHandled: false
  property var powerChain: null

  // ---- settings shared by every instance (Control Center and the bar island):
  //      ~/.local/state/velum/power.json { historyRange, historyMetric, chargeLimitStep, historyDir }
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

  // ---- history (the akku-test logger writes one CSV a day, a line every 30 s)
  property var historyPoints: []
  property var historyStats: null
  property var historyBars: []
  property real historyNow: 0
  property var historyFiles: []
  property var historyTexts: ({})
  property var historyParsed: ({})
  readonly property var historyRanges: Model.HISTORY_RANGES
  readonly property var historyRange: Model.historyRange(pref("historyRange", "")) || Model.historyRange(Model.HISTORY_DEFAULT_RANGE)
  readonly property real historyHours: historyRange.hours
  readonly property int historyBarCount: historyRange.bars
  readonly property var historyMetric: Model.historyMetric(pref("historyMetric", Model.HISTORY_DEFAULT_METRIC)) || Model.historyMetric(Model.HISTORY_DEFAULT_METRIC)
  readonly property var historyMetricKeys: Model.HISTORY_METRICS.map(function (m) { return m.key })
  readonly property var historyMetricLabels: Model.HISTORY_METRICS.map(function (m) { return m.label })
  readonly property string historyDir: String(pref("historyDir", "")) || Quickshell.env("HOME") + "/Projects/akku-test/verlauf"

  // Every spawned process runs with absolute executables and a closed, minimal
  // environment, so a shadowed binary earlier in PATH never runs; the helper
  // only by its fixed installed path.
  readonly property string helperPath: "/usr/local/bin/dell-charge-limit"
  readonly property var procEnv: ({ "PATH": "/usr/share/omarchy/bin:/usr/bin:/bin" })
  readonly property int chargeLimitStep: { var s = Number(pref("chargeLimitStep", 5)); return isFinite(s) && s > 0 ? Math.min(60, Math.round(s)) : 5 }
  readonly property bool dellSupported: dellStatus !== null && dellStatus.ok === true && dellStatus.dell === true
  readonly property bool dellThresholdsReady: dellSupported && dellStatus.hasThresholds
  readonly property bool dellWmiReady: dellSupported && dellStatus.hasWmi
  property bool draggingStart: false
  property bool draggingStop: false
  property int previewStart: -1
  property int previewEnd: -1

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
    if (s === "") return "—"
    return s + (powerChain && powerChain.nominalWh !== null ? " / " + powerChain.nominalWh + " Wh" : "")
  }
  readonly property string timeLabel: chargeThresholdActive ? "Charge Limit"
    : discharging ? "Time Left" : charging && timeToLimitText() !== "" ? "Time to Limit" : "Time to Full"
  readonly property string timeText: chargeThresholdActive
    ? (dellThresholdsReady ? dellStatus.start + "–" + dellStatus.end + " %" : (batteryInfo.threshold || "—"))
    : batteryFlowIdle ? "—" : charging && timeToLimitText() !== "" ? timeToLimitText() : (batteryInfo.time || "—")
  readonly property string flowLabel: chargeThresholdActive ? "Battery" : discharging ? "Draw" : "Charging At"
  readonly property string flowText: chargeThresholdActive ? "Holding"
    : batteryFull ? "—"
    : powerChain && powerChain.batteryW !== null ? signedWatt(powerChain.batteryW)
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

  // ---- Dell charge controls
  function refreshDell() { if (!dellProc.running && !dellBusy) dellProc.running = true }
  function updateDellStatus(raw) { var parsed = Model.parseDellStatus(raw); if (parsed) dellStatus = parsed }
  function dellRun(args) {
    if (dellBusy) return
    dellError = ""; dellActionOutput = ""; dellActionError = ""
    dellActionArgs = args; dellTriedPkexec = false; dellActionHandled = false
    dellBusy = true
    // sudo -n first (silent with the helper's sudoers rule); without the rule, pkexec once (dialog)
    dellActionProc.command = ["/usr/bin/timeout", "-k", "5", "120", "/usr/bin/sudo", "-n", root.helperPath].concat(args)
    dellActionProc.running = true
  }
  function onDellActionFinished() {
    if (dellActionHandled) return
    dellActionHandled = true
    if (String(dellActionOutput).trim() === "") {
      if (!dellTriedPkexec) {
        dellTriedPkexec = true; dellActionHandled = false; dellActionOutput = ""; dellActionError = ""
        dellActionProc.command = ["/usr/bin/timeout", "-k", "5", "300", "/usr/bin/pkexec", root.helperPath].concat(dellActionArgs)
        dellActionProc.running = true
        return
      }
      dellBusy = false
      var detail = String(dellActionError || "").trim()
      dellError = "Action cancelled" + (detail !== "" ? " — " + detail : "")
      refreshDell()
      return
    }
    dellBusy = false
    var parsed = Model.parseDellStatus(dellActionOutput)
    if (parsed) {
      dellStatus = parsed
      var rawObj = null
      try { rawObj = JSON.parse(dellActionOutput) } catch (e) { rawObj = null }
      if (rawObj && rawObj.applied === false) dellError = "Refused by the firmware (read back: " + String(rawObj.readback || "") + ")"
      refreshDell()
      return
    }
    var msg = ""
    try { var obj = JSON.parse(dellActionOutput); msg = typeof obj === "string" ? obj : String(obj.error || "") } catch (e) { msg = "" }
    dellError = msg !== "" ? msg : "Privileged action failed"
    refreshDell()
  }
  // a released threshold marker keeps its preview until the helper has answered
  onDellBusyChanged: { if (dellBusy) return; if (!draggingStart) previewStart = -1; if (!draggingStop) previewEnd = -1 }
  function effStart() { return previewStart >= 0 ? previewStart : (dellThresholdsReady ? dellStatus.start : 50) }
  function effEnd() { return previewEnd >= 0 ? previewEnd : (dellThresholdsReady ? dellStatus.end : 80) }
  readonly property bool thresholdsLive: dellStatus !== null && dellStatus.mode === "Custom"
  function applyDellStart(value) { dellRun(["set-start", String(value)]) }
  function applyDellEnd(value) { dellRun(["set-end", String(value)]) }
  function thresholdTickText() {
    var txt = "Charge limit: " + effStart() + " % → " + effEnd() + " %"
    if (!thresholdsLive) txt += " — inactive (mode " + (dellStatus ? dellStatus.mode : "?") + "). Drag a marker to apply."
    return txt
  }
  function timeToLimitText() {
    if (!dellThresholdsReady || dellStatus === null || dellStatus.mode !== "Custom") return ""
    var rate = powerChain && powerChain.batteryW !== null ? powerChain.batteryW : parseFloat(batteryInfo.rate || "")
    return Model.timeToThresholdText(dellStatus.end, batteryFraction, parseFloat(batteryInfo.size || ""), rate)
  }

  // ---- power flow
  function refreshPowerChain() { if (!powerChainProc.running) powerChainProc.running = true }
  function signedWatt(w) {
    if (w === null || w === undefined || !isFinite(w)) return "—"
    var abs = Math.abs(w)
    if (abs < 0.05) return "0.0 W"
    return (w > 0 ? "+" : "−") + abs.toFixed(1) + " W"
  }

  // ---- history
  function refreshHistory() {
    var days = Model.historyDays(new Date(), historyHours)
    var names = days.map(function (d) { return d.name }).join(",")
    if (names !== historyFiles.map(function (d) { return d.name }).join(",")) { historyFiles = days; return }
    for (var i = Math.max(0, historyFileViews.count - 2); i < historyFileViews.count; i++) {
      var fv = historyFileViews.objectAt(i)
      if (fv) fv.reload()
    }
  }
  function setHistoryText(name, text) {
    var t = Object.assign({}, historyTexts); t[name] = text; historyTexts = t
    Qt.callLater(rebuildHistory)
  }
  function rebuildHistory() {
    var now = new Date(), samples = [], cache = {}
    for (var i = 0; i < historyFiles.length; i++) {
      var f = historyFiles[i], text = historyTexts[f.name] || "", c = historyParsed[f.name]
      if (!c || c.len !== text.length) c = { len: text.length, samples: Model.parseHistoryCsv(text, f.day) }
      cache[f.name] = c
      samples = samples.concat(c.samples)
    }
    historyParsed = cache
    historyNow = now.getTime()
    historyPoints = Model.historyWindow(samples, historyNow, historyHours)
    historyStats = Model.historyStats(historyPoints)
    historyBars = Model.historyBuckets(historyPoints, historyNow, historyHours, historyBarCount)
  }
  function setHistoryRange(key) { var r = Model.historyRange(key); if (r && r !== historyRange) savePref("historyRange", r.key) }
  function setHistoryMetric(key) { var m = Model.historyMetric(key); if (m && m.key !== historyMetric.key) savePref("historyMetric", m.key) }
  // a longer range may need older files first; refreshHistory rebuilds once they are in
  onHistoryRangeChanged: { if (historyStats !== null) refreshHistory(); Qt.callLater(rebuildHistory) }
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
  readonly property string historyDischargeText: {
    var st = historyStats
    if (!st || !st.discharging || st.cycleWh === null || st.cycleStart === null) return ""
    return "This discharge: " + historyWh(st.cycleWh) + " since " + clockText(st.cycleStart)
  }
  readonly property string historyChargeText: {
    var st = historyStats
    if (!st || !st.samples || !(st.chargingH > 0)) return ""
    return "Charged " + historyWh(st.chargedWh) + " in " + Model.durationText(st.chargingH)
  }

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
    refresh(); refreshDell(); refreshPowerChain()
    if (dellStatus === null || !dellWmiReady) dellRootRefreshProc.running = true
  }
  // reading a day of samples waits until the surface has settled (never a frame of the opening)
  Timer { id: historySettle; interval: Theme.dur("slow") + Theme.delay("settle"); onTriggered: if (root.opened) root.refreshHistory() }
  Component.onCompleted: Qt.callLater(refresh)

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: { root.refresh(); root.refreshDell(); root.refreshPowerChain() } }
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
  Process {
    id: dellProc
    clearEnvironment: true; environment: root.procEnv
    // the timeout keeps the probe observable: without the helper the command never starts
    command: ["/usr/bin/timeout", "-k", "5", "20", root.helperPath, "status"]
    onExited: root.dellProbed = true
    stdout: CappedCollector { proc: dellProc; onFinished: t => { root.dellProbed = true; root.updateDellStatus(t) } }
  }
  Process {
    id: dellActionProc
    clearEnvironment: true; environment: root.procEnv
    // decided when stdout ends (onExited may come before the output); the timer is the safety net
    onExited: dellActionDoneTimer.start()
    stdout: CappedCollector { proc: dellActionProc; onFinished: t => { root.dellActionOutput = t; root.onDellActionFinished() } }
    stderr: CappedCollector { proc: dellActionProc; onFinished: t => root.dellActionError = t }
  }
  Timer { id: dellActionDoneTimer; interval: 150; onTriggered: root.onDellActionFinished() }
  Process {
    id: powerChainProc
    clearEnvironment: true; environment: root.procEnv
    // RAPL counters are root-only: through the allowlisted helper (sudo -n); without it the flow stays hidden
    command: ["/usr/bin/timeout", "-k", "5", "20", "/usr/bin/sudo", "-n", root.helperPath, "power-chain"]
    stdout: CappedCollector { proc: powerChainProc; onFinished: t => { var p = Model.parsePowerChain(t); if (p) root.powerChain = p } }
  }
  // silent self-heal of a stale WMI cache (null values written before dell-wmi-sysman was ready)
  Process {
    id: dellRootRefreshProc
    clearEnvironment: true; environment: root.procEnv
    command: ["/usr/bin/timeout", "-k", "5", "20", "/usr/bin/sudo", "-n", root.helperPath, "status"]
    stdout: CappedCollector { proc: dellRootRefreshProc; onFinished: t => root.updateDellStatus(t) }
  }
  Instantiator {
    id: historyFileViews
    model: root.historyFiles
    delegate: FileView {
      required property var modelData
      path: root.historyDir + "/" + modelData.name
      printErrors: false
      onLoaded: root.setHistoryText(modelData.name, text())
      onLoadFailed: root.setHistoryText(modelData.name, "")
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
