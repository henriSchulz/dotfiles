import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "file:///home/henri/.local/share/velum/qml/Velum"


// Battery menu on Velum (Pearl, SF Symbols; v3 of henri.power). Fork of io.github.nipsen.dell-power
// (MIT, see LICENSE): the backend (UPower, omarchy tools, the root helper
// /usr/local/bin/dell-charge-limit) is unchanged; the popup is rebuilt.
// It opens on the overview — charge, battery size, time left, cycles and
// the current flow — and everything else sits under a collapsed "Advanced"
// disclosure: fans, power flow, charge mode, USB. The power profile sits on
// the overview itself.
Panel {
  id: root
  moduleName: "henri.power"
  ipcTarget: "henri.power"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the togglePercentage method below.
  manageIpc: false
  property var batteryInfo: ({})
  property var systemInfo: ({})
  property var profiles: []
  property string activeProfile: ""
  property int profileIndex: 0
  property bool cursorActive: false
  property var dellStatus: null
  property bool dellBusy: false
  property bool dellProbed: false
  property bool setupCopied: false
  property string dellError: ""
  property string dellActionOutput: ""
  property string dellActionError: ""
  property var dellActionArgs: []
  property bool dellTriedPkexec: false
  property bool dellActionHandled: false
  property var powerChain: null
  // Battery history from the akku-aufzeichnung logger (one CSV per day).
  // Kept across opens, so the section never starts empty after the first load.
  // Which drill-in page is showing (VPageStack): "main" (the overview),
  // "history" or "advanced".
  property string pageName: "main"
  readonly property bool historyShown: pageName === "history"
  readonly property bool advancedOpen: pageName === "advanced"
  // The History page's range menu (a VMenu over the page, under its button).
  property bool rangeOpen: false
  property var historyPoints: []
  property var historyStats: null
  property var historyBars: []
  property real historyNow: 0
  // The daily CSVs the window touches (Model.historyDays), oldest first, and
  // their text by file name. Parsed samples are cached per file and text
  // length, so the 30 s refresh only re-parses the file that grew.
  property var historyFiles: []
  property var historyTexts: ({})
  property var historyParsed: ({})
  readonly property var historyRanges: Model.HISTORY_RANGES
  // A plain value, synced from the settings in a handler: a binding here fed
  // the graph's time axis straight from the settings object and looped.
  // `historyHours` (6/12/24) is the older setting; it still picks the range.
  property var historyRange: Model.historyRange(Model.HISTORY_DEFAULT_RANGE)
  readonly property real historyHours: historyRange.hours
  readonly property int historyBarCount: historyRange.bars
  // What the bars show: charge, power, voltage or current. A plain key, synced
  // in the handler for the same reason the range is (a binding on the settings
  // object looped through the graph).
  property string historyMetricKey: Model.HISTORY_DEFAULT_METRIC
  readonly property var historyMetric: Model.historyMetric(historyMetricKey)
    || Model.historyMetric(Model.HISTORY_DEFAULT_METRIC)
  readonly property var historyMetricKeys: Model.HISTORY_METRICS.map(function (m) { return m.key })
  readonly property var historyMetricLabels: Model.HISTORY_METRICS.map(function (m) { return m.label })
  function syncHistorySettings() {
    var r = Model.historyRange(setting("historyRange", "")) || Model.historyRange(setting("historyHours", ""))
      || Model.historyRange(Model.HISTORY_DEFAULT_RANGE)
    if (r !== historyRange) historyRange = r
    var m = Model.historyMetric(setting("historyMetric", Model.HISTORY_DEFAULT_METRIC))
      || Model.historyMetric(Model.HISTORY_DEFAULT_METRIC)
    if (m.key !== historyMetricKey) historyMetricKey = m.key
  }
  onSettingsChanged: syncHistorySettings()
  // data are there before the first open, so the popup never changes height while it comes up
  Component.onCompleted: { syncHistorySettings(); Qt.callLater(refresh) }
  readonly property bool showHistory: setting("showHistory", true) === true
  readonly property string historyDir: {
    var d = String(setting("historyDir", "") || "")
    return d !== "" ? d : Quickshell.env("HOME") + "/Projects/akku-test/verlauf"
  }
  // Every spawned process runs with absolute executables and a closed,
  // minimal environment: a shadowed binary earlier in the shell PATH must
  // never get code execution (or impersonate the privilege UI) on routine
  // plugin activity. The helper is only ever invoked by its fixed installed
  // path. (The omarchy tools call each other internally, hence their dir.)
  readonly property string helperPath: "/usr/local/bin/dell-charge-limit"
  readonly property var procEnv: ({ "PATH": "/usr/share/omarchy/bin:/usr/bin:/bin" })
  readonly property int chargeLimitStep: {
    var s = Number(setting("chargeLimitStep", 5))
    return (isFinite(s) && s > 0) ? Math.min(60, Math.round(s)) : 5
  }
  readonly property bool dellSupported: dellStatus !== null && dellStatus.ok === true && dellStatus.dell === true
  readonly property bool dellThresholdsReady: dellSupported && dellStatus.hasThresholds
  readonly property bool dellWmiReady: dellSupported && dellStatus.hasWmi
  readonly property bool usbPowerShareReady: dellWmiReady && dellStatus.usbPowerShare !== ""
  readonly property bool typeCPowerReady: dellWmiReady && dellStatus.typeCPower !== ""
  // Alienware laptops (and any whose helper reports them): the fans and
  // temperatures the EC reports. The firmware's own thermal modes are not
  // offered — the power profile is the single place to pick one.
  readonly property string brand: dellStatus !== null ? dellStatus.brand : "Dell"
  readonly property var thermal: dellStatus !== null ? dellStatus.thermal : null
  readonly property var fans: dellStatus !== null ? dellStatus.fans : []
  readonly property var fanNames: Model.fanNames(fans)
  readonly property var temps: dellStatus !== null ? dellStatus.temps : []
  readonly property bool sensorsReady: fans.length > 0 || temps.length > 0
  readonly property bool fanBoostAvailable: Model.groupBoost(fans, "cpu") !== null || Model.groupBoost(fans, "gpu") !== null
  // Before the system helper is installed the status poll fails, so
  // dellStatus stays null once probed. A non-Dell machine with the helper
  // installed answers {dell:false} instead — no hint there.
  readonly property bool helperMissing: dellProbed && dellStatus === null
  // The installer authenticates its privileged core against the upstream
  // git checkout, so setup runs from a fresh clone of the original repo.
  readonly property string setupCommand: "git clone https://github.com/NIPSEN/omarchy-dell-power /tmp/dell-power && /tmp/dell-power/install-system.sh"
  property bool draggingStart: false
  property bool draggingStop: false
  property int previewStart: -1
  property int previewEnd: -1
  readonly property bool showPercentage: setting("showPercentage", false) === true
  // With the percentage shown the button paints a text block wider than an
  // icon, so the open-panel mark takes the painted width instead of the
  // icon-sized fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: !button.vertical ? barContentWidth : 0
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  // ---- Look: Velum roles of the popover surface (variant, appearance and
  //      icons follow ~/.local/state/velum/settings.json — the shell's
  //      VelumSettings, held by the Control Center v3 island, applies them)
  readonly property color fg: Theme.r.popover.ink
  readonly property color dimText: Theme.r.popover.inkSecondary
  readonly property color wash: Theme.r.popover.tile
  readonly property color washHover: Theme.r.popover.fillHover
  readonly property color trackColor: Theme.r.popover.switchOff
  readonly property color hairline: Theme.r.popover.line
  readonly property color accent: Theme.r.accent.base
  readonly property color urgent: Theme.r.danger
  readonly property string uiFont: Theme.font
  readonly property int panelWidth: Theme.layout.module.width - 6 * Theme.layout.module.pad
  readonly property int blockGap: Theme.layout.module.gap
  // Type scale (Velum text styles)
  readonly property int fCaption: Theme.m.type.small
  readonly property int fSmall: Theme.core.type.callout
  readonly property int fBody: Theme.m.type.body
  readonly property int fSub: Theme.core.type.headline
  readonly property int fTitle: Theme.core.type.title3
  readonly property int fDisplay: Theme.core.type.title1

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
  }

  // History is a drill-in page: it slides in from the right over the
  // overview, so the popup keeps the overview's height instead of growing.
  function showHistoryPage() {
    if (!showHistory || historyShown) return
    cursorActive = false
    if (historyStats === null) refreshHistory()
    pages.push(historyPage)
    pageName = "history"
  }

  function closeHistoryPage() {
    if (historyShown) pages.pop()
  }

  // Advanced is a drill-in page too; it scrolls when it is taller than the
  // screen allows.
  function showAdvancedPage() {
    if (pages.depth > 1) return
    cursorActive = false
    pages.push(advancedPage)
    pageName = "advanced"
  }

  function closeSubPage() {
    cursorActive = false
    rangeOpen = false
    if (pages.depth > 1) { pages.pop(); pageName = "main" }
  }

  function selectProfileByDelta(delta) {
    profileIndex = Model.selectProfileIndex(profileIndex, delta, profiles)
  }

  function activateSelectedProfile() {
    if (profileIndex < 0 || profileIndex >= profiles.length) return
    setProfile(profiles[profileIndex])
  }

  function modeLabel() {
    var device = UPower.displayDevice
    return Model.modeLabel(device, root.discharging, upowerStates())
  }

  // "power-saver" → "Power Saver"
  function profileLabel(name) {
    return String(name).split("-").map(function (w) {
      return w.charAt(0).toUpperCase() + w.slice(1)
    }).join(" ")
  }

  readonly property bool fullyCharged: {
    var device = UPower.displayDevice
    return device && device.isPresent && device.state === UPowerDeviceState.FullyCharged && !root.chargeThresholdActive
  }
  readonly property bool discharging: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent && UPower.onBattery)
  }
  readonly property bool chargeThresholdActive: {
    var device = UPower.displayDevice
    return Model.chargeThresholdActive(device, root.discharging, upowerStates())
  }
  readonly property bool batteryFull: fullyCharged || (!root.discharging && batteryFraction >= 1)
  readonly property bool batteryFlowIdle: batteryFull || chargeThresholdActive

  // 0..1 charge level, used by the glyph and the charge bar.
  readonly property real batteryFraction: {
    var d = UPower.displayDevice
    return Model.batteryFraction(d)
  }

  readonly property bool charging: {
    var d = UPower.displayDevice
    return d && d.isPresent && !UPower.onBattery && !root.batteryFlowIdle
  }

  // Status line under the title, rotated while current is flowing so the
  // panel feels alive. Changes crossfade (Fade below).
  readonly property var chargingPhrases: [
    "Pumping power",
    "Injecting electrons",
    "Pouring juice",
    "Amassing watts",
    "Hoarding joules",
    "Sucking volts",
    "Topping reserves",
    "Soaking amps",
    "Inhaling kilowatts"
  ]
  readonly property var onBatteryPhrases: [
    "Slurping power",
    "Spending joules",
    "Draining watts",
    "Burning electrons",
    "Sipping juice",
    "Spending coulombs",
    "Bleeding amps",
    "Guzzling volts",
    "Munching reserves"
  ]
  property int phraseIndex: 0

  readonly property var activePhrases: {
    if (fullyCharged) return []
    if (charging) return chargingPhrases
    if (discharging) return onBatteryPhrases
    return []
  }
  readonly property bool rotatingPhrases: activePhrases.length > 0

  readonly property string heroStatusText: {
    if (fullyCharged) return "Fully charged"
    if (rotatingPhrases) return activePhrases[phraseIndex % activePhrases.length]
    return modeLabel()
  }

  // ---- Overview values (always visible)
  readonly property string sizeText: {
    var s = root.batteryInfo.size || ""
    if (s === "") return "—"
    return s + (root.powerChain && root.powerChain.nominalWh !== null ? " / " + root.powerChain.nominalWh + "Wh" : "")
  }
  readonly property string timeLabel: root.chargeThresholdActive ? "Charge limit"
    : (root.discharging ? "Time left"
      : (root.charging && root.timeToLimitText() !== "" ? "Time to limit" : "Time to full"))
  readonly property string timeText: root.chargeThresholdActive
    ? (root.dellThresholdsReady
      ? (root.dellStatus.start + "–" + root.dellStatus.end + " %")
      : (root.batteryInfo.threshold || "—"))
    : (root.batteryFlowIdle ? "—"
      : (root.charging && root.timeToLimitText() !== ""
        ? root.timeToLimitText()
        : (root.batteryInfo.time || "—")))
  readonly property string flowLabel: root.chargeThresholdActive ? "Battery state" : (root.discharging ? "Discharging" : "Charging")
  readonly property string flowText: root.chargeThresholdActive ? "Holding"
    : (root.batteryFull ? "—"
      : (root.powerChain && root.powerChain.batteryW !== null
        ? root.signedWatt(root.powerChain.batteryW)
        : (root.batteryInfo.rate || "—")))

  function refresh() {
    if (!batteryPresent) return

    if (!batteryProc.running) batteryProc.running = true
    if (!profilesProc.running) profilesProc.running = true
    if (!systemProc.running) systemProc.running = true
  }

  function updateKeyValue(raw, targetName) {
    var next = Model.parseKeyValue(raw)
    // Keep last known good data if a refresh briefly returns nothing — happens
    // around AC plug/unplug events. Avoids the section collapsing mid-transition.
    if (Object.keys(next).length === 0) return
    if (targetName === "battery") batteryInfo = next
    else systemInfo = next
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw, profileIndex)
    // Same guard as battery: preserve the last known profile list across
    // transient empty payloads so the buttons don't blink out.
    if (parsed.profiles.length === 0) return
    profiles = parsed.profiles
    activeProfile = parsed.activeProfile
    profileIndex = parsed.profileIndex
    if (opened && !cursorActive) {
      var idx = profiles.indexOf(activeProfile)
      if (idx >= 0) profileIndex = idx
    }
  }

  function setProfile(profile) {
    if (!profile || actionProc.running) return
    // Optimistic: the segment glides at once, the poll confirms it.
    activeProfile = profile
    actionProc.command = ["/usr/bin/timeout", "-k", "5", "15", "/usr/share/omarchy/bin/omarchy-powerprofiles-set", root.discharging ? "battery" : "ac", profile]
    actionProc.running = true
  }

  function togglePercentage() {
    root.settings = Object.assign({}, root.settings, { showPercentage: !root.showPercentage })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  // ---------- Dell charge controls ----------

  function refreshDell() {
    if (!dellProc.running && !dellBusy) dellProc.running = true
  }

  function updateDellStatus(raw) {
    var parsed = Model.parseDellStatus(raw)
    if (!parsed) return
    dellStatus = parsed
  }

  function dellRun(args) {
    if (dellBusy) return
    dellError = ""
    dellActionOutput = ""
    dellActionError = ""
    dellActionArgs = args
    dellTriedPkexec = false
    dellActionHandled = false
    dellBusy = true
    // Primary path: sudo -n (silent thanks to the sudoers rule
    // installed by install-system.sh). If it fails (missing rule),
    // onDellActionFinished retries ONCE with pkexec (dialog).
    dellActionProc.command = ["/usr/bin/timeout", "-k", "5", "120", "/usr/bin/sudo", "-n", root.helperPath].concat(args)
    dellActionProc.running = true
  }

  function onDellActionFinished() {
    if (dellActionHandled) return
    dellActionHandled = true
    if (String(dellActionOutput).trim() === "") {
      // sudo -n failed without output: fall back to pkexec, once only.
      if (!dellTriedPkexec) {
        dellTriedPkexec = true
        dellActionHandled = false
        dellActionOutput = ""
        dellActionError = ""
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
      if (rawObj && rawObj.applied === false) {
        dellError = "Refused by the firmware (read back: " + String(rawObj.readback || "") + ")"
      }
      refreshDell()
      return
    }
    var msg = ""
    try {
      var obj = JSON.parse(dellActionOutput)
      // The helper reports failures as a bare JSON string ("..."), not an
      // object — handle both shapes so the message actually reaches the UI.
      msg = typeof obj === "string" ? obj : String(obj.error || "")
    } catch (e) {
      msg = ""
    }
    dellError = msg !== "" ? msg : "Privileged action failed"
    refreshDell()
  }

  // A released threshold marker keeps its preview until the helper has
  // answered, so it does not flick back to the old value in between.
  onDellBusyChanged: {
    if (dellBusy) return
    if (!draggingStart) previewStart = -1
    if (!draggingStop) previewEnd = -1
  }

  function setDellMode(mode) {
    if (!dellWmiReady || mode === dellStatus.mode) return
    dellRun(["wmi", "PrimaryBattChargeCfg", mode])
  }

  function setUsbPowerShare() {
    if (!dellWmiReady) return
    var current = String(dellStatus.usbPowerShare || "")
    var next = current === "Enabled" ? "Disabled" : "Enabled"
    dellRun(["wmi", "UsbPowerShare", next])
  }

  function setDellTypeCPower(value) {
    if (!dellWmiReady || value === dellStatus.typeCPower) return
    dellRun(["wmi", "TypeCPower", value])
  }

  // ---------- Fan boost ----------

  // The slider speaks percent; the kernel takes 0-255 per fan.
  function setFanBoost(group, percent) {
    var value = Math.round(Math.max(0, Math.min(100, Number(percent))) / 100 * 255)
    if (value === Model.groupBoost(fans, group)) return
    dellRun(["fan-boost", group, String(value)])
  }

  // ---------- Charge thresholds on the battery bar ----------

  function effStart() {
    return previewStart >= 0 ? previewStart : (dellThresholdsReady ? dellStatus.start : 50)
  }

  function effEnd() {
    return previewEnd >= 0 ? previewEnd : (dellThresholdsReady ? dellStatus.end : 80)
  }

  readonly property bool thresholdsLive: dellStatus !== null && dellStatus.mode === "Custom"

  function applyDellStart(value) {
    dellRun(["set-start", String(value)])
  }

  function applyDellEnd(value) {
    dellRun(["set-end", String(value)])
  }

  function thresholdTickText() {
    var txt = "Charge limit: " + effStart() + " % → " + effEnd() + " %"
    if (!thresholdsLive) {
      txt += " — inactive (mode " + (dellStatus ? dellStatus.mode : "?") + "). Drag a marker to apply."
    }
    return txt
  }

  // "Time to limit" instead of "Time to full" when a Custom stop threshold
  // is active and the battery is charging towards it.
  function timeToLimitText() {
    if (!dellThresholdsReady || dellStatus === null || dellStatus.mode !== "Custom") return ""
    var rate = powerChain && powerChain.batteryW !== null
      ? powerChain.batteryW
      : parseFloat(batteryInfo.rate || "")
    return Model.timeToThresholdText(dellStatus.end, batteryFraction, parseFloat(batteryInfo.size || ""), rate)
  }

  // ---------- Power flow chain ----------

  function refreshPowerChain() {
    if (!powerChainProc.running) powerChainProc.running = true
  }

  function updatePowerChain(raw) {
    var parsed = Model.parsePowerChain(raw)
    if (parsed) powerChain = parsed
  }

  function sourceIcon() {
    if (powerChain && powerChain.source === "typec") return ""
    return ""
  }

  function signedWatt(w) {
    if (w === null || w === undefined || !isFinite(w)) return "—"
    var abs = Math.abs(w)
    if (abs < 0.05) return "0.0 W"
    return (w > 0 ? "+" : "−") + abs.toFixed(1) + " W"
  }

  function plainWatt(w) {
    if (w === null || w === undefined || !isFinite(w)) return "—"
    return w.toFixed(1) + " W"
  }

  // Battery node sub-line: pack voltage and current (+ in, − out, same
  // convention as signedWatt).
  function batterySubText() {
    if (!powerChain) return ""
    var parts = []
    if (powerChain.packV !== null) parts.push(powerChain.packV.toFixed(2) + " V")
    if (powerChain.packA !== null) {
      var a = powerChain.packA
      var sign = a > 0.005 ? "+" : (a < -0.005 ? "−" : "")
      parts.push(sign + Math.abs(a).toFixed(1) + " A")
    }
    return parts.join(" · ")
  }

  function sourceFlowDir() {
    if (!powerChain) return "none"
    return powerChain.source === "battery" ? "none" : "right"
  }

  function batteryFlowDir() {
    if (!powerChain || powerChain.batteryW === null) return "none"
    if (powerChain.batteryW > 0.5) return "right"
    if (powerChain.batteryW < -0.5) return "left"
    return "none"
  }

  // Points at the daily files the window touches; their FileViews load on
  // creation, a reload() of the two newest picks up the lines added since
  // (older days no longer change).
  function refreshHistory() {
    if (!root.showHistory) return
    var days = Model.historyDays(new Date(), historyHours)
    var names = days.map(function (d) { return d.name }).join(",")
    if (names !== historyFiles.map(function (d) { return d.name }).join(",")) {
      historyFiles = days
      return
    }
    for (var i = Math.max(0, historyFileViews.count - 2); i < historyFileViews.count; i++) {
      var fv = historyFileViews.objectAt(i)
      if (fv) fv.reload()
    }
  }

  function setHistoryText(name, text) {
    var t = Object.assign({}, historyTexts)
    t[name] = text
    historyTexts = t
    Qt.callLater(rebuildHistory)
  }

  function rebuildHistory() {
    var now = new Date()
    var samples = []
    var cache = {}
    for (var i = 0; i < historyFiles.length; i++) {
      var f = historyFiles[i]
      var text = historyTexts[f.name] || ""
      var c = historyParsed[f.name]
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

  // Remembered like the bar percentage: written back into the bar entry.
  function saveHistorySetting(key, value) {
    var patch = {}
    patch[key] = value
    root.settings = Object.assign({}, root.settings, patch)
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  function setHistoryRange(key) {
    var r = Model.historyRange(key)
    if (!r || r === historyRange) return
    saveHistorySetting("historyRange", r.key)
  }

  function setHistoryMetric(key) {
    var m = Model.historyMetric(key)
    if (!m || m.key === historyMetricKey) return
    saveHistorySetting("historyMetric", m.key)
  }

  // A longer range may need older files first; refreshHistory rebuilds
  // once they are in (a shorter one rebuilds straight from what is loaded).
  onHistoryRangeChanged: {
    if (historyStats !== null) refreshHistory()
    Qt.callLater(rebuildHistory)
  }

  function historyWatt(w) {
    return w === null || w === undefined || !isFinite(w) ? "—" : w.toFixed(1) + " W"
  }

  // A bucket's value in the metric now on show, e.g. "9.2 W" or "7.53 V".
  function historyValue(v, m) {
    if (v === null || v === undefined || !isFinite(v)) return "—"
    return v.toFixed(m.decimals) + " " + m.unit
  }

  // The same value on an axis, carrying only the decimals it needs, so the
  // gridlines read "20 W", "2.5 W", "7.5 V" rather than "20.0 W".
  function historyAxisLabel(v, m) {
    if (v === null || v === undefined || !isFinite(v)) return "—"
    var txt = Math.abs(v - Math.round(v)) < 1e-6 ? String(Math.round(v))
      : v.toFixed(m.decimals).replace(/0+$/, "").replace(/\.$/, "")
    return txt + " " + m.unit
  }

  function historyWh(wh) {
    return wh === null || wh === undefined || !isFinite(wh) ? "—" : wh.toFixed(1) + " Wh"
  }

  function clockText(t) {
    return Qt.formatTime(new Date(t), "HH:mm")
  }

  readonly property string historyDischargeText: {
    var st = root.historyStats
    if (!st || !st.discharging || st.cycleWh === null || st.cycleStart === null) return ""
    return "This discharge: " + root.historyWh(st.cycleWh) + " since " + root.clockText(st.cycleStart)
  }

  readonly property string historyChargeText: {
    var st = root.historyStats
    if (!st || !st.samples) return ""
    var parts = []
    if (st.chargingH > 0) parts.push("Charged " + root.historyWh(st.chargedWh) + " in " + Model.durationText(st.chargingH))
    return parts.join(" · ")
  }

  IpcHandler {
    target: "henri.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
    // Opens the popup straight on the History section / the Advanced page.
    function history() { root.open(); root.showHistoryPage() }
    function advanced() { root.open(); root.showAdvancedPage() }
    // History range (15m 30m 1h 3h 6h 12h 24h 3d 7d) and what the bars show
    // (percent watts volts amps, or charge power voltage current).
    function historyRange(key: string): void { root.setHistoryRange(key) }
    function historyMetric(metric: string): void { root.setHistoryMetric(metric) }
    // The History page's range menu (for tests and keyboard users): true opens it.
    function rangeMenu(open: bool): void { if (open) { root.open(); root.showHistoryPage() } root.rangeOpen = open }
    // What the popup shows, for the rig.
    function state(): string { return JSON.stringify({ opened: root.opened, page: root.pageName, depth: pages.depth, rangeOpen: root.rangeOpen, profile: root.activeProfile, width: content.width, height: content.height }) }
  }

  onOpenedChanged: {
    popupSettled = false; if (opened) settleTimer.restart()
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

      focusLater.restart()
      refresh()
      refreshDell()
      refreshPowerChain()
      if (dellStatus === null || !dellWmiReady) dellRootRefreshProc.running = true
      var idx = profiles.indexOf(activeProfile)
      profileIndex = idx >= 0 ? idx : 0
      cursorActive = false
      // Reading and parsing a day of samples waits until the popup has
      // settled, so it never costs a frame of the opening animation.
      historySettleTimer.restart()
    }
  }

  onBatteryPresentChanged: if (!batteryPresent) close()

  visible: batteryPresent
  implicitWidth: batteryPresent ? button.implicitWidth : 0
  implicitHeight: batteryPresent ? button.implicitHeight : 0

  Process {
    id: batteryProc
    clearEnvironment: true
    environment: root.procEnv
    command: ["/usr/bin/timeout", "-k", "5", "15", "/usr/share/omarchy/bin/omarchy-battery-status", "--shell"]
    stdout: CappedCollector { proc: batteryProc; onFinished: t => root.updateKeyValue(t, "battery") }
  }

  Process {
    id: profilesProc
    clearEnvironment: true
    environment: root.procEnv
    command: ["/usr/bin/timeout", "-k", "5", "15", "/usr/share/omarchy/bin/omarchy-powerprofiles-list", "--active-state"]
    stdout: CappedCollector { proc: profilesProc; onFinished: t => root.updateProfiles(t) }
  }

  Process {
    id: systemProc
    clearEnvironment: true
    environment: root.procEnv
    command: ["/usr/bin/timeout", "-k", "5", "15", "/usr/share/omarchy/bin/omarchy-system-stats"]
    stdout: CappedCollector { proc: systemProc; onFinished: t => root.updateKeyValue(t, "system") }
  }

  Process {
    id: actionProc
    clearEnvironment: true
    environment: root.procEnv
    onExited: root.refresh()
  }

  Process {
    id: dellProc
    clearEnvironment: true
    environment: root.procEnv
    // The timeout wrapper keeps the probe observable: with the helper not
    // installed the command never starts (no exit, no stream end) and
    // dellProbed would stay false forever — timeout exits 127 instead.
    command: ["/usr/bin/timeout", "-k", "5", "20", root.helperPath, "status"]
    onExited: root.dellProbed = true
    stdout: CappedCollector {
      proc: dellProc
      onFinished: t => {
        root.dellProbed = true
        root.updateDellStatus(t)
      }
    }
  }

  Process {
    id: dellActionProc
    clearEnvironment: true
    environment: root.procEnv
    // The decision is made in onDellActionFinished, fired when the stdout
    // stream ends (waitForEnd). onExited may fire BEFORE the output is
    // delivered: a plain onExited would read an empty output and wrongly
    // trigger the pkexec fallback. The timer is a safety net if the stream
    // never ends (process failed to start).
    onExited: dellActionDoneTimer.start()
    stdout: CappedCollector {
      proc: dellActionProc
      onFinished: t => {
        root.dellActionOutput = t
        root.onDellActionFinished()
      }
    }
    stderr: CappedCollector { proc: dellActionProc; onFinished: t => root.dellActionError = t }
  }

  Timer {
    id: dellActionDoneTimer
    interval: 150
    onTriggered: root.onDellActionFinished()
  }

  Process {
    id: powerChainProc
    clearEnvironment: true
    environment: root.procEnv
    // The RAPL counters are root-only by kernel default, so the sampling goes
    // through the allowlisted helper as root (silent thanks to the sudoers
    // rule). No helper / no rule → the process fails and the power-flow
    // section simply stays hidden.
    command: ["/usr/bin/timeout", "-k", "5", "20", "/usr/bin/sudo", "-n", root.helperPath, "power-chain"]
    stdout: CappedCollector { proc: powerChainProc; onFinished: t => root.updatePowerChain(t) }
  }

  // Silent self-heal: if the WMI cache is stale (null values written
  // before dell-wmi-sysman was ready at boot), a root status
  // via sudo -n (NOPASSWD) refreshes it without a password prompt.
  Process {
    id: dellRootRefreshProc
    clearEnvironment: true
    environment: root.procEnv
    command: ["/usr/bin/timeout", "-k", "5", "20", "/usr/bin/sudo", "-n", root.helperPath, "status"]
    stdout: CappedCollector { proc: dellRootRefreshProc; onFinished: t => root.updateDellStatus(t) }
  }

  Process {
    id: setupCopyProc
    clearEnvironment: true
    environment: root.procEnv
    // No deadline here: wl-copy forks and must keep running to serve the
    // paste; killing it would drop the clipboard content.
    command: ["/usr/bin/wl-copy", root.setupCommand]
    onExited: {
      root.setupCopied = true
      setupCopiedTimer.restart()
    }
  }

  Timer {
    id: setupCopiedTimer
    interval: 1500
    onTriggered: root.setupCopied = false
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: { root.refresh(); root.refreshDell(); root.refreshPowerChain() } }

  // ---- Battery history files (logger writes a line every 30 s)
  Timer {
    id: historySettleTimer
    interval: Theme.dur("slow") + Theme.delay("settle")
    onTriggered: root.refreshHistory()
  }

  Timer { interval: 30000; running: root.opened && root.showHistory; repeat: true; onTriggered: root.refreshHistory() }

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

  Timer {
    interval: 2800
    running: root.opened && root.rotatingPhrases
    repeat: true
    onTriggered: {
      var n = root.activePhrases.length
      if (n > 0) root.phraseIndex = (root.phraseIndex + 1) % n
    }
  }

  // ============================================================ bar button

  // macOS menu-bar battery: "84 %" + the drawn battery (VBattery).
  readonly property bool pctInBar: root.showPercentage && !(button && button.vertical)
  readonly property string pctText: Math.round(root.batteryFraction * 100) + " %"
  readonly property real glyphH: Style.spaceReal(11.5)
  readonly property real barContentWidth: (pctInBar ? pctMetrics.advanceWidth + Style.spaceReal(5) : 0) + glyphH * 2 + Style.spaceReal(2.5)

  TextMetrics {
    id: pctMetrics
    font.family: root.bar ? root.bar.fontFamily : root.uiFont
    font.pixelSize: Style.font.body
    text: root.pctText
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Math.max(Style.bar.iconSlot, Math.ceil(root.barContentWidth + Style.space(12)))
    iconComponent: Component {
      Item {
        Row {
          anchors.centerIn: parent
          spacing: Style.spaceReal(5)
          Fade {
            visible: root.pctInBar
            anchors.verticalCenter: parent.verticalCenter
            text: root.pctText
            color: button ? button.foreground : Color.foreground
            font.pixelSize: Style.font.body
            font.family: button ? button.fontFamily : root.uiFont
          }
          VBattery {
            anchors.verticalCenter: parent.verticalCenter
            height: root.glyphH
            level: root.batteryFraction
            charging: root.charging
            plugged: !root.discharging && !root.charging
            ink: button ? button.foreground : Color.foreground
          }
        }
      }
    }
    tooltipText: ""
    onPressed: function(b) {
      if (!root.batteryPresent) return
      if (b === Qt.RightButton) root.togglePercentage()
      else root.toggle()
    }
  }

  // ================================================================= popup
  // true once the popup has finished growing in; folds inside animate only from then on
  property bool popupSettled: false
  Timer { id: settleTimer; interval: Theme.dur("slow"); onTriggered: root.popupSettled = true }

  VBarPopup {
    id: panel
    anchorItem: button
    bar: root.bar
    namespace: "velum-surface"   // Hyprland: blur with ignore_alpha 0.6 (only the material, never the shadow), no layer animation
    open: root.opened && root.batteryPresent
    pad: Theme.layout.module.pad
    radius: Theme.m.radius.panel
    kind: "panel"
    onDismissed: root.close()
    onEscapePressed: root.goBack()

    // Every open starts on the overview: back to it once the popup is gone.
    onVisibleChanged: {
      if (visible) return
      root.cursorActive = false
      root.rangeOpen = false
      pages.reset()
      root.pageName = "main"
    }

    Item {
      id: content
      width: root.panelWidth
      height: pages.implicitHeight

      VPageStack {
        id: pages
        width: parent.width
        initial: mainPage
      }

      // Range picker: a menu dropping out of the History header's button.
      // Clicks beside it close it and go nowhere else.
      MouseArea {
        anchors.fill: parent
        z: 9
        enabled: root.rangeOpen
        visible: enabled
        acceptedButtons: Qt.AllButtons
        onPressed: root.rangeOpen = false
      }
      VMenu {
        id: rangeMenu
        z: 10
        open: root.rangeOpen && root.historyShown
        x: parent.width - width
        y: Theme.layout.module.head
        model: {
          var cur = root.historyRange
          var out = []
          var list = root.historyRanges
          for (var i = 0; i < list.length; i++) {
            // Minutes, hours, days — a separator between the groups.
            if (i > 0 && list[i].hours >= 1 !== list[i - 1].hours >= 1
                || i > 0 && list[i].hours > 24 !== list[i - 1].hours > 24)
              out.push({ separator: true })
            out.push({ text: list[i].label, rangeKey: list[i].key, key: list[i] === cur ? "Current" : "" })
          }
          return out
        }
        onOpenChanged: if (open) {
          for (var i = 0; i < model.length; i++) if (model[i].rangeKey === root.historyRange.key) highlighted = i
        }
        onTriggered: function(index) {
          root.rangeOpen = false
          root.setHistoryRange(model[index].rangeKey)
        }
      }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        z: -1
        // Overview: ←/→ walk the power profiles and ⏎ applies the one under the
        // cursor; ↑ opens History, ↓ opens Advanced. History: ← goes back,
        // ⏎ opens the range menu (↑ ↓ ⏎ Esc while open).
        // Esc goes back one page, and closes on the overview.
        onMoveRequested: function(dx, dy) {
          if (root.historyShown) {
            if (root.rangeOpen) { if (dy !== 0) rangeMenu.step(dy); return }
            if (dx < 0) root.closeSubPage()
            return
          }
          if (root.advancedOpen) return
          if (dx !== 0) {
            if (root.profiles.length === 0) return
            if (!root.cursorActive) { root.cursorActive = true; return }
            root.selectProfileByDelta(dx)
            return
          }
          if (dy < 0 && root.showHistory) root.showHistoryPage()
          else if (dy > 0) root.showAdvancedPage()
        }
        onActivateRequested: {
          if (root.historyShown) {
            if (root.rangeOpen) { if (rangeMenu.highlighted >= 0) rangeMenu.choose(rangeMenu.highlighted) }
            else root.rangeOpen = true
            return
          }
          if (root.advancedOpen) return
          if (root.cursorActive) root.activateSelectedProfile()
          else root.showAdvancedPage()
        }
        onCloseRequested: root.goBack()
        onTabRequested: function(direction) { root.switchPanel(direction) }
      }
    }
  }
  // The key catcher takes the keys once the popup holds the keyboard.
  Timer { id: focusLater; interval: Theme.dur("fast"); onTriggered: if (root.opened) keyCatcher.forceActiveFocus() }

  function goBack() {
    if (rangeOpen) rangeOpen = false
    else if (pages.depth > 1) closeSubPage()
    else close()
  }

  // ---------- Page 1: overview ----------
  Component {
    id: mainPage
    Column {
      spacing: 0

      // ---------- Header: battery · title/status · percentage ----------
      Item {
        width: parent.width
        implicitHeight: Math.max(heroGlyph.height, heroLabels.implicitHeight, heroPercent.implicitHeight)

        VBattery {
          id: heroGlyph
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          height: Theme.layout.icon.regular
          level: root.batteryFraction
          charging: root.charging
          plugged: !root.discharging && !root.charging
          ink: root.fg
        }
        Column {
          id: heroLabels
          anchors.left: heroGlyph.right
          anchors.leftMargin: Theme.layout.module.pad
          anchors.right: heroPercent.left
          anchors.rightMargin: Theme.layout.list.gap
          anchors.verticalCenter: parent.verticalCenter
          VText { width: parent.width; text: "Battery"; elide: Text.ElideRight; color: root.fg; font.weight: Font.DemiBold }
          Fade { width: parent.width; text: root.heroStatusText; color: root.dimText; elide: Text.ElideRight; font.pixelSize: root.fCaption }
        }
        Fade {
          id: heroPercent
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          text: root.pctText
          color: root.fg
          font.pixelSize: root.fDisplay
          font.weight: Font.DemiBold
        }
      }

      Item { width: 1; height: root.blockGap }
      ChargeBar { width: parent.width }

      Collapse {
        width: parent.width
        expanded: root.dellError !== ""
        VText {
          width: parent.width
          topPadding: Theme.layout.list.gap
          textFormat: Text.PlainText
          text: root.dellError
          color: root.urgent
          wrapMode: Text.WordWrap
          font.pixelSize: root.fCaption
        }
      }

      // ---------- Overview: size, time, cycles, flow ----------
      // Only gated by "we've ever loaded data", so the block never folds
      // mid-transition (UPower briefly reports FullyCharged on plug-in).
      Collapse {
        width: parent.width
        expanded: root.batteryInfo.percentage !== undefined
        Grid {
          id: statGrid
          width: parent.width
          topPadding: root.blockGap
          columns: 2
          spacing: Theme.layout.list.gap
          readonly property real cellWidth: (width - spacing) / 2
          StatTile { width: statGrid.cellWidth; label: "Battery size"; value: root.sizeText }
          StatTile { width: statGrid.cellWidth; label: root.timeLabel; value: root.timeText }
          StatTile { width: statGrid.cellWidth; label: "Charge cycles"; value: root.batteryInfo.cycles || "—" }
          StatTile { width: statGrid.cellWidth; label: root.flowLabel; value: root.flowText }
        }
      }

      // ---------- Power profile: the one control worth reaching without a drill-in ----------
      Collapse {
        width: parent.width
        expanded: root.profiles.length > 0
        Column {
          width: parent.width
          topPadding: root.blockGap
          spacing: Theme.layout.list.gap
          SectionLabel { text: "Power Profile" }
          Segmented {
            width: parent.width
            options: root.profiles
            labels: root.profiles.map(function (p) { return root.profileLabel(p) })
            // with the keyboard cursor out, the plate shows the one ⏎ would pick
            current: root.cursorActive && root.profileIndex >= 0 ? (root.profiles[root.profileIndex] || "") : root.activeProfile
            onPicked: function(value) { root.cursorActive = false; root.setProfile(value) }
          }
        }
      }

      // ---------- Drill-ins ----------
      Item { width: 1; height: root.blockGap }
      VModuleSep { width: parent.width }
      DrillRow { visible: root.showHistory; text: "History"; onClicked: root.showHistoryPage() }
      DrillRow { text: "Advanced"; onClicked: root.showAdvancedPage() }
    }
  }

  // ---------- Page 3: advanced (drill-in) ----------
  Component {
    id: advancedPage
    Item {
      // Taller than the screen allows → the body scrolls under the header.
      readonly property real maxBody: Math.max(Theme.layout.module.width / 2,
        panel.screenH - panel.barStrip - panel.gap - 2 * panel.margin - 2 * panel.pad - advancedHeader.implicitHeight)
      implicitHeight: advancedHeader.implicitHeight + Math.min(advancedBody.implicitHeight, maxBody)

      VPageHead { id: advancedHeader; width: parent.width; title: "Advanced"; onBack: root.closeSubPage() }

      Flickable {
        id: advancedFlick
        y: advancedHeader.height
        width: parent.width
        height: parent.height - y
        contentHeight: advancedBody.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.DragAndOvershootBounds

        Item {
          id: advancedBody
          width: advancedFlick.width
          implicitHeight: advancedCol.implicitHeight
          Column {
            id: advancedCol
            width: parent.width
            spacing: 0

            // ---------- Fans and temperatures ----------
            Collapse {
              width: parent.width
              expanded: root.sensorsReady
              Column {
                width: parent.width
                spacing: Theme.layout.list.gap
                SectionLabel { text: "Fans & Temperatures" }
                // Counted rather than listed: the status poll hands a new array every
                // few seconds, and a listed model would rebuild every row.
                Repeater {
                  model: root.fans.length
                  FanRow {
                    required property int index
                    width: parent.width
                    fan: root.fans[index] || null
                    name: root.fanNames[index] || ""
                  }
                }
                Row {
                  id: tempRow
                  width: parent.width
                  spacing: Theme.layout.list.gap
                  visible: root.temps.length > 0
                  Repeater {
                    model: root.temps.length
                    TempTile {
                      required property int index
                      width: (tempRow.width - tempRow.spacing * Math.max(0, root.temps.length - 1)) / Math.max(1, root.temps.length)
                      reading: root.temps[index] || null
                    }
                  }
                }
                Collapse {
                  width: parent.width
                  expanded: root.fanBoostAvailable && root.thermal !== null && root.thermal.profile === "custom"
                  Column {
                    width: parent.width
                    spacing: Theme.layout.list.gap
                    BoostSlider { group: "cpu"; title: "CPU fans boost" }
                    BoostSlider { group: "gpu"; title: "GPU fans boost" }
                  }
                }
              }
            }

            // ---------- Power flow chain ----------
            Collapse {
              width: parent.width
              expanded: root.powerChain !== null
              Column {
                width: parent.width
                topPadding: root.sensorsReady ? root.blockGap : 0
                spacing: Theme.layout.list.gap
                SectionLabel { text: "Power Flow" }
                Row {
                  id: flowRow
                  width: parent.width
                  spacing: Theme.layout.module.tileInset
                  readonly property real arrowWidth: Theme.layout.icon.small
                  readonly property real nodeWidth: (width - arrowWidth * 2 - spacing * 4) / 3
                  readonly property real nodeHeight: Math.max(sourceNode.implicitHeight, componentsNode.implicitHeight, batteryNode.implicitHeight)

                  // Source: the power the adapter provides (psys + battery charge).
                  FlowNode {
                    id: sourceNode
                    width: flowRow.nodeWidth
                    height: flowRow.nodeHeight
                    dimmed: !!root.powerChain && root.powerChain.source === "battery"
                    icon: root.powerChain && root.powerChain.source === "typec" ? "link" : "energy"
                    title: root.powerChain && root.powerChain.source === "typec" ? "USB-C" : "AC"
                    value: root.powerChain && root.powerChain.source !== "battery" ? root.plainWatt(root.powerChain.adapterW) : "Unplugged"
                  }
                  FlowArrow { dir: root.sourceFlowDir(); height: flowRow.nodeHeight }
                  // Components: total, breakdown behind the chevron.
                  FlowNode {
                    id: componentsNode
                    width: flowRow.nodeWidth
                    height: flowRow.nodeHeight
                    icon: "cpu"
                    title: "Components"
                    value: root.powerChain ? root.plainWatt(root.powerChain.componentsW) : "—"
                    collapsible: true
                    // RAM only where the CPU reports it (RAPL dram); elsewhere it is part of "Other".
                    rows: {
                      var list = [
                        {
                          label: "CPU",
                          value: root.powerChain && root.powerChain.cpuW !== null && root.powerChain.igpuW !== null
                            ? root.plainWatt(root.powerChain.cpuW - root.powerChain.igpuW) : "—"
                        },
                        { label: "iGPU", value: root.powerChain ? root.plainWatt(root.powerChain.igpuW) : "—" }
                      ]
                      if (root.powerChain && root.powerChain.ramW !== null)
                        list.push({ label: "RAM", value: root.plainWatt(root.powerChain.ramW) })
                      list.push({ label: "Other", value: root.powerChain ? root.plainWatt(root.powerChain.screenW) : "—" })
                      return list
                    }
                  }
                  FlowArrow { dir: root.batteryFlowDir(); height: flowRow.nodeHeight }
                  // Battery: + in, − out.
                  FlowNode {
                    id: batteryNode
                    width: flowRow.nodeWidth
                    height: flowRow.nodeHeight
                    icon: "battery"
                    title: "Battery"
                    value: root.powerChain ? root.signedWatt(root.powerChain.batteryW) : "—"
                    sub: root.batterySubText()
                  }
                }
              }
            }

            // ---------- Charge mode ----------
            Collapse {
              width: parent.width
              expanded: root.dellWmiReady
              Column {
                width: parent.width
                topPadding: root.blockGap
                spacing: Theme.layout.list.gap
                SectionLabel { text: "Charge Mode" }
                Segmented {
                  width: parent.width
                  options: Model.DELL_MODES
                  labels: Model.DELL_MODES.map(function (m) { return String(m) === "PrimAcUse" ? "AC" : String(m) })
                  current: root.dellStatus !== null ? root.dellStatus.mode : ""
                  busy: root.dellBusy
                  onPicked: function(value) { root.setDellMode(value) }
                }
                Caption { text: root.dellStatus !== null ? (Model.DELL_MODE_INFO[String(root.dellStatus.mode)] || "") : "" }
              }
            }

            // ---------- USB ports ----------
            Collapse {
              width: parent.width
              expanded: root.usbPowerShareReady || root.typeCPowerReady
              Column {
                width: parent.width
                topPadding: root.blockGap
                spacing: Theme.layout.list.gap
                SectionLabel { text: "USB Ports" }
                Item {
                  width: parent.width
                  height: Math.max(usbText.implicitHeight, usbToggle.height)
                  visible: root.usbPowerShareReady
                  Column {
                    id: usbText
                    anchors.left: parent.left
                    anchors.right: usbToggle.left
                    anchors.rightMargin: Theme.layout.module.pad
                    anchors.verticalCenter: parent.verticalCenter
                    VText { text: "USB PowerShare"; color: root.fg }
                    Caption { text: "Keeps the USB-A port powered while the laptop sleeps" }
                  }
                  VSwitch {
                    id: usbToggle
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    surface: "popover"
                    enabled: !root.dellBusy
                    onToggled: root.setUsbPowerShare()
                  }
                  // The switch flips at once; the helper's answer settles it.
                  Binding {
                    target: usbToggle
                    property: "checked"
                    value: root.dellStatus !== null && root.dellStatus.usbPowerShare === "Enabled"
                    when: !root.dellBusy
                    restoreMode: Binding.RestoreNone
                  }
                }
                Column {
                  width: parent.width
                  spacing: Theme.layout.list.gap
                  visible: root.typeCPowerReady
                  VText { text: "USB-C output"; color: root.fg }
                  Segmented {
                    width: parent.width
                    options: ["7.5W", "15W"]
                    labels: ["7.5 W", "15 W"]
                    current: root.dellStatus !== null ? root.dellStatus.typeCPower : ""
                    busy: root.dellBusy
                    onPicked: function(value) { root.setDellTypeCPower(value) }
                  }
                }
              }
            }

            // ---------- Setup hint (helper not installed yet) ----------
            Collapse {
              width: parent.width
              expanded: root.helperMissing
              Column {
                width: parent.width
                topPadding: root.powerChain !== null || root.sensorsReady ? root.blockGap : 0
                spacing: Theme.layout.list.gap
                SectionLabel { text: root.brand + " Setup" }
                VText {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                  text: "Charge modes, thresholds, USB options and power flow need the system helper. Click to copy the command, then run it once in a terminal:"
                  color: root.dimText
                  font.pixelSize: root.fCaption
                }
                VTile {
                  width: parent.width
                  height: Theme.m.control.height
                  radius: Theme.m.radius.control
                  color: setupMouse.containsMouse ? root.washHover : root.wash
                  Fade {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: Theme.layout.menu.itemPadX
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideMiddle
                    text: root.setupCopied ? "Copied — paste it in a terminal" : root.setupCommand
                    color: root.fg
                    font.pixelSize: root.fCaption
                    font.family: Theme.core.font.mono[0]
                  }
                  MouseArea { id: setupMouse; anchors.fill: parent; hoverEnabled: true; onClicked: if (!setupCopyProc.running) setupCopyProc.running = true }
                }
              }
            }

            Item { width: 1; height: Theme.layout.module.tileInset }
          }
        }
      }
    }
  }

  // ---------- Page 2: battery history (drill-in) ----------
  Component {
    id: historyPage
    Item {
      implicitHeight: historyHeader.implicitHeight + historyCol.implicitHeight

      VPageHead {
        id: historyHeader
        width: parent.width
        title: "Battery History"
        onBack: root.closeSubPage()
        PopUpButton {
          text: root.historyRange.short
          open: root.rangeOpen
          Accessible.name: "Time range"
          onClicked: root.rangeOpen = !root.rangeOpen
        }
      }

      Column {
        id: historyCol
        y: historyHeader.height
        width: parent.width
        bottomPadding: Theme.layout.module.tileInset
        spacing: Theme.layout.list.gap

        Item {
          width: parent.width
          height: Math.max(historyTitle.implicitHeight, historyReadout.implicitHeight)
          // What the bars show: charge, power, voltage or current.
          Segmented {
            id: historyTitle
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: implicitWidth
            options: root.historyMetricKeys
            labels: root.historyMetricLabels
            current: root.historyMetric.key
            onPicked: function(value) { root.setHistoryMetric(value) }
          }
          Fade {
            id: historyReadout
            anchors.right: parent.right
            anchors.left: historyTitle.right
            anchors.leftMargin: Theme.layout.list.gap
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            text: historyGraph.readout
            color: root.fg
            font.pixelSize: root.fCaption
            font.weight: Font.Medium
          }
        }

        HistoryGraph { id: historyGraph; width: parent.width }

        Grid {
          id: historyGrid
          width: parent.width
          columns: 2
          spacing: Theme.layout.list.gap
          visible: root.historyStats !== null && root.historyStats.samples
          readonly property real cellWidth: (width - spacing) / 2
          StatTile { width: historyGrid.cellWidth; label: "Time on battery"; value: root.historyStats ? Model.durationText(root.historyStats.onBatteryH) : "—" }
          StatTile { width: historyGrid.cellWidth; label: "Used on battery"; value: root.historyStats ? root.historyWh(root.historyStats.usedWh) : "—" }
          StatTile { width: historyGrid.cellWidth; label: "Average draw"; value: root.historyStats ? root.historyWatt(root.historyStats.avgDrawW) : "—" }
          StatTile {
            width: historyGrid.cellWidth
            label: "A full charge lasts"
            value: root.historyStats && root.historyStats.runtimeH !== null ? "≈ " + Model.durationText(root.historyStats.runtimeH) : "—"
          }
        }

        Caption {
          visible: text !== ""
          text: root.historyStats === null ? ""
            : (root.historyStats.samples ? root.historyDischargeText : "No samples in " + root.historyDir)
        }
        Caption { visible: text !== ""; text: root.historyChargeText }
      }
    }
  }

  // ============================================================ components

  // A label that crossfades its text (fast): the old one fades out while the
  // new one fades in, so live values never jump.
  component Fade: Item {
    id: fade
    property string text: ""
    property color color: root.fg
    property alias font: a.font
    property int horizontalAlignment: Text.AlignLeft
    property int elide: Text.ElideNone
    property int textFormat: Text.PlainText
    property bool showA: true
    implicitWidth: Math.max(a.implicitWidth, b.implicitWidth)
    implicitHeight: a.implicitHeight
    onTextChanged: { if (showA) b.text = text; else a.text = text; showA = !showA }
    Component.onCompleted: a.text = text
    Text {
      id: a
      width: parent.width; height: parent.height
      horizontalAlignment: fade.horizontalAlignment; verticalAlignment: Text.AlignVCenter
      elide: fade.elide; textFormat: fade.textFormat
      color: fade.color
      font.family: root.uiFont; font.pixelSize: root.fBody
      opacity: fade.showA ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
    }
    Text {
      id: b
      width: parent.width; height: parent.height
      horizontalAlignment: fade.horizontalAlignment; verticalAlignment: Text.AlignVCenter
      elide: fade.elide; textFormat: fade.textFormat
      color: fade.color
      font: a.font
      opacity: fade.showA ? 0 : 1
      Behavior on opacity { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
    }
  }

  // A section that folds open and shut: the height glides (smooth spring),
  // the content fades with it; collapsed it takes no room.
  component Collapse: Item {
    id: col
    property bool expanded: false
    default property alias body: colBody.data
    clip: true
    implicitHeight: hs.value
    visible: hs.value > 0.5
    // until the popup has finished opening, folds jump to their height: the panel grows once, as a whole
    Spring { id: hs; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion || !root.popupSettled; target: col.expanded ? colBody.childrenRect.height : 0 }
    Component.onCompleted: hs.snap(col.expanded ? colBody.childrenRect.height : 0)
    Item {
      id: colBody
      width: parent.width
      height: childrenRect.height
      opacity: col.expanded ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
    }
  }

  // The charge level on a track, with the charge thresholds drawn onto it:
  // an accent zone between start and stop, a marker at each end. Drag a
  // marker to change it — the helper switches the charge mode to Custom
  // automatically, so a dimmed (inactive) zone comes alive on first drag.
  component ChargeBar: Item {
    id: chargeBar
    readonly property real trackH: Theme.layout.list.gap
    readonly property bool low: root.batteryFraction <= 0.2 && root.discharging
    implicitHeight: trackH + Theme.layout.list.gap

    Rectangle {
      id: barTrack
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      height: chargeBar.trackH
      radius: height / 2
      color: root.trackColor
    }
    Rectangle {
      x: barTrack.width * root.effStart() / 100
      width: Math.max(0, barTrack.width * (root.effEnd() - root.effStart()) / 100)
      anchors.verticalCenter: barTrack.verticalCenter
      height: barTrack.height
      radius: barTrack.radius
      color: Theme.r.fill.selected
      opacity: !root.dellThresholdsReady ? 0 : (root.thresholdsLive ? 1 : 0.6)
      Behavior on opacity { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
    }
    // Fill: a round cap plus a full-width bar slid in from the left inside a
    // clip — only x moves per frame (transform, not width).
    Rectangle {
      anchors.verticalCenter: barTrack.verticalCenter
      width: barTrack.height
      height: barTrack.height
      radius: height / 2
      gradient: chargeBar.low ? null : fillGrad
      color: root.urgent
    }
    Gradient { id: fillGrad; orientation: Gradient.Horizontal
      GradientStop { position: 0; color: Theme.r.accent.base } GradientStop { position: 1; color: Theme.r.accent.top } }
    Item {
      x: barTrack.height / 2
      width: barTrack.width - x
      height: barTrack.height
      anchors.verticalCenter: barTrack.verticalCenter
      clip: true
      Rectangle {
        width: barTrack.width
        height: barTrack.height
        radius: height / 2
        gradient: chargeBar.low ? null : fillGrad
        color: root.urgent
        x: fillSpring.value - barTrack.width + barTrack.height / 2
      }
    }
    Spring {
      id: fillSpring
      preset: Theme.spring("smooth")
      reduced: Theme.reduceMotion
      target: Math.max(0, Math.min(1, root.batteryFraction)) * (barTrack.width - barTrack.height / 2)
    }

    ThresholdMarker { percent: root.effStart(); dragging: root.draggingStart }
    ThresholdMarker { percent: root.effEnd(); dragging: root.draggingStop }

    MouseArea {
      id: barMouse
      anchors.fill: parent
      hoverEnabled: true
      property string hoverText: ""
      property string hoverTick: ""
      readonly property real grab: Theme.layout.module.pad

      function tickNear(x) {
        if (!root.dellThresholdsReady) return ""
        var sx = barTrack.width * root.effStart() / 100
        var ex = barTrack.width * root.effEnd() / 100
        if (Math.abs(x - ex) <= grab) return "end"
        if (Math.abs(x - sx) <= grab) return "start"
        return ""
      }
      function updateHover() {
        if (root.draggingStart || root.draggingStop) {
          hoverTick = root.draggingStop ? "end" : "start"
          hoverText = root.draggingStop ? "Charge stop: " + root.effEnd() + " %" : "Charge start: " + root.effStart() + " %"
          return
        }
        if (!containsMouse) { hoverTick = ""; hoverText = ""; return }
        var t = tickNear(mouseX)
        if (t === "end") { hoverTick = "end"; hoverText = "Charge stop: " + root.effEnd() + " %" }
        else if (t === "start") { hoverTick = "start"; hoverText = "Charge start: " + root.effStart() + " %" }
        else if (root.dellThresholdsReady) { hoverTick = ""; hoverText = root.thresholdTickText() }
        else { hoverTick = ""; hoverText = "" }
      }
      cursorShape: root.dellThresholdsReady && tickNear(mouseX) !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
      onPressed: function(mouse) {
        if (root.dellBusy) return
        var t = tickNear(mouse.x)
        if (t === "end") { root.previewEnd = root.effEnd(); root.draggingStop = true }
        else if (t === "start") { root.previewStart = root.effStart(); root.draggingStart = true }
        updateHover()
      }
      onPositionChanged: function(mouse) {
        if (root.draggingStart || root.draggingStop) {
          var pct = Math.max(0, Math.min(100, mouse.x / barTrack.width * 100))
          var snapped = Math.round(pct / root.chargeLimitStep) * root.chargeLimitStep
          if (root.draggingStop) root.previewEnd = Model.dellClampEnd(snapped, root.effStart())
          else if (root.draggingStart) root.previewStart = Model.dellClampStart(Math.min(snapped, root.effEnd() - Model.DELL_GAP))
        }
        updateHover()
      }
      // The preview stays until the helper answers (onDellBusyChanged).
      onReleased: function() {
        if (root.draggingStop) {
          root.draggingStop = false
          if (root.previewEnd !== root.dellStatus.end) root.applyDellEnd(root.previewEnd)
          else root.previewEnd = -1
        }
        if (root.draggingStart) {
          root.draggingStart = false
          if (root.previewStart !== root.dellStatus.start) root.applyDellStart(root.previewStart)
          else root.previewStart = -1
        }
        updateHover()
      }
      onHoveredChanged: updateHover()
    }

    // Tooltip inside the popup (the bar's tooltips only anchor items in the
    // bar window). Fades; keeps its last text while fading out.
    Rectangle {
      id: thresholdTip
      property string shownText: ""
      readonly property bool active: barMouse.hoverText !== ""
      Connections {
        target: barMouse
        function onHoverTextChanged() { if (barMouse.hoverText !== "") thresholdTip.shownText = barMouse.hoverText }
      }
      z: 5
      y: -height - Theme.layout.module.tileInset
      x: {
        var tickPct = barMouse.hoverTick === "start" ? root.effStart()
          : barMouse.hoverTick === "end" ? root.effEnd()
          : (barMouse.containsMouse ? barMouse.mouseX / barTrack.width * 100 : 50)
        var cx = barTrack.width * tickPct / 100
        return Math.max(0, Math.min(chargeBar.width - width, cx - width / 2))
      }
      width: Math.min(chargeBar.width, tipLabel.implicitWidth + 2 * Theme.layout.tooltip.padX)
      height: tipLabel.implicitHeight + 2 * Theme.layout.tooltip.padY
      radius: Theme.m.radius.tooltip
      color: Theme.r.tooltip.bg
      border.width: Theme.layout.separator
      border.color: Theme.r.line.base
      opacity: active ? 1 : 0
      visible: opacity > 0.01
      Behavior on opacity {
        NumberAnimation {
          duration: thresholdTip.active ? Theme.dur("fast") : Theme.exit(Theme.dur("fast"))
          easing.type: Easing.BezierSpline
          easing.bezierCurve: thresholdTip.active ? Theme.curve("out") : Theme.curve("exit")
        }
      }
      Text {
        id: tipLabel
        anchors.centerIn: parent
        width: Math.min(implicitWidth, chargeBar.width - 2 * Theme.layout.tooltip.padX)
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: thresholdTip.shownText
        color: Theme.r.tooltip.ink
        font.family: root.uiFont
        font.pixelSize: root.fCaption
      }
    }
  }

  // Start/stop marker on the charge bar. Follows the pointer directly while
  // dragged, glides otherwise (e.g. when the helper reports a new value).
  component ThresholdMarker: Rectangle {
    id: marker
    property int percent: 0
    property bool dragging: false
    readonly property real track: parent.width
    width: Theme.layout.module.tileInset
    height: Theme.layout.icon.large - Theme.layout.separator * 2
    radius: width / 2
    anchors.verticalCenter: parent.verticalCenter
    color: root.accent
    x: track * percent / 100 - width / 2
    opacity: !root.dellThresholdsReady ? 0 : (root.thresholdsLive ? 1 : 0.55)
    scale: dragging ? Theme.scale("lift") : 1
    Behavior on x {
      enabled: !marker.dragging
      NumberAnimation { duration: Theme.move(Theme.dur("base")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") }
    }
    Behavior on opacity { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
    Behavior on scale { NumberAnimation { duration: Theme.dur("instant"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
  }

  // A row that drills into a page.
  component DrillRow: VModuleRow {
    width: parent ? parent.width : implicitWidth
    VIcon { name: "chevron.right"; weight: "bold"; size: Theme.layout.icon.small; color: root.dimText }
  }

  // The chosen metric over the history window as bars, like the macOS battery
  // graph: 30–84 bars over the chosen range, each at the level it ended on (or
  // its mean for the metered values) — accent on battery, pale accent while
  // plugged in, danger at 20 % and below on the charge view. Slots without
  // samples (sleep, laptop off) stay empty. Three gridlines label the axis the
  // model fitted to the metric, round clock or day ticks; hovering a bar reads
  // it out and dims the rest.
  component HistoryGraph: Item {
    id: graph
    readonly property real gutter: gutterMetrics.advanceWidth + Theme.layout.list.gap
    readonly property real plotW: Math.max(1, width - gutter)
    readonly property real plotH: Theme.layout.module.width / 5
    readonly property real from: root.historyNow - root.historyHours * 3600000
    readonly property var metric: root.historyMetric
    // The axis the bars stand on: 0–100 for charge, a round top for power and
    // current, a fitted band for voltage.
    readonly property var axis: Model.historyAxis(root.historyBars, metric.key)
    readonly property real axisSpan: Math.max(1e-9, axis.max - axis.min)
    readonly property bool multiDay: root.historyHours > 24
    function barValue(b) { return b ? b[metric.field] : null }
    function valueOf(b) {
      var v = barValue(b)
      if (v === null || v === undefined || !isFinite(v)) return 0
      return Math.max(0, Math.min(1, (v - axis.min) / axisSpan))
    }
    function stamp(t) { return multiDay ? Qt.formatDateTime(new Date(t), "ddd HH:mm") : root.clockText(t) }
    // Bars follow the built buckets, so a range switch never pairs the new
    // count with the old data for a frame.
    readonly property int barCount: Math.max(1, root.historyBars.length)
    readonly property real slotW: plotW / barCount
    readonly property real barGap: Math.max(1, Math.round(slotW * 0.3))
    readonly property color batteryInk: Theme.r.accent.base
    readonly property color pluggedInk: Theme.r.success.base
    // the bars grow out of the baseline when the page opens (the lab)
    property bool grown: false
    Component.onCompleted: Qt.callLater(function () { graph.grown = true })
    property int hoverIndex: -1
    readonly property var hoverBar: hoverIndex >= 0 ? root.historyBars[hoverIndex] || null : null
    // Only the metric on show — the bar being pointed at is what is asked.
    readonly property string readout: {
      var b = graph.hoverBar
      if (b) return graph.stamp(b.t0) + " · " + root.historyValue(graph.barValue(b), graph.metric)
      var st = root.historyStats
      if (!st || !st.samples) return ""
      if (graph.metric.key === "percent") return "Now " + Math.round(root.batteryFraction * 100) + " %"
      return "Now " + root.historyValue(
        graph.metric.key === "watts" ? st.lastW : graph.metric.key === "volts" ? st.lastV : st.lastA,
        graph.metric)
    }
    implicitHeight: plotH + timeRow.height + Theme.layout.module.pad + legend.height

    TextMetrics { id: gutterMetrics; font.family: root.uiFont; font.pixelSize: root.fCaption; text: "888 W" }

    function xOf(t) { return (t - from) / (root.historyHours * 3600000) * plotW }
    function yOf(pct) { return plotH - Math.max(0, Math.min(100, pct)) / 100 * plotH }

    // Round clock (or day) marks inside the window, at most six (seven days).
    readonly property var tickInfo: Model.historyTicks(graph.from, root.historyNow, graph.multiDay ? 7 : 6)
    readonly property var ticks: tickInfo.ticks
    // Over several days a midnight mark names the day, the others the time.
    function tickText(t) {
      var d = new Date(t)
      return graph.multiDay && d.getHours() === 0 && d.getMinutes() === 0 ? Qt.formatDate(d, "ddd") : root.clockText(t)
    }

    // Gridlines and labels on the right; the labels crossfade when the axis
    // switches between charge and power.
    Repeater {
      model: [100, 50, 0]
      Item {
        required property var modelData
        y: Math.round(graph.yOf(modelData))
        width: graph.width
        Rectangle { width: graph.plotW; height: Theme.layout.separator; color: root.hairline }
        Fade {
          x: graph.plotW + Theme.layout.list.gap / 2
          anchors.verticalCenter: parent.top
          text: root.historyAxisLabel(graph.axis.min + graph.axisSpan * modelData / 100, graph.metric)
          color: root.dimText
          font.pixelSize: root.fCaption
        }
      }
    }

    // Full-height bars scaled from the baseline: level changes and the first
    // fill animate as a transform, never as a layout change.
    Repeater {
      model: root.historyBars.length
      Rectangle {
        id: bar
        required property int index
        readonly property var bucket: root.historyBars[index] || null
        x: Math.round(index * graph.slotW + graph.barGap / 2)
        width: Math.max(1, Math.round(graph.slotW - graph.barGap))
        height: graph.plotH
        radius: Math.min(width / 2, Theme.layout.separator * 2)   // lint-ok: bar ends as the lab
        readonly property bool low: !!bucket && graph.metric.key === "percent" && bucket.pct <= 20
        color: !bucket ? "transparent" : low ? root.urgent : bucket.battery ? graph.batteryInk : graph.pluggedInk
        gradient: !bucket || low ? null : bucket.battery ? accentFill : chargeFill
        Gradient { id: accentFill; GradientStop { position: 0; color: Theme.r.accent.top } GradientStop { position: 1; color: Theme.r.accent.base } }
        Gradient { id: chargeFill; GradientStop { position: 0; color: Theme.r.success.top } GradientStop { position: 1; color: Theme.r.success.base } }
        opacity: !bucket ? 0 : (graph.hoverIndex < 0 || graph.hoverIndex === index ? 1 : 0.45)
        transform: Scale {
          origin.y: graph.plotH
          yScale: bar.bucket && graph.grown ? Math.max(0.02, graph.valueOf(bar.bucket)) : 0
          Behavior on yScale { NumberAnimation { duration: Theme.move(Theme.dur("slow")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
        }
        Behavior on opacity { NumberAnimation { duration: graph.hoverIndex >= 0 ? Theme.dur("instant") : Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
        Behavior on color { ColorAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
      }
    }

    MouseArea {
      width: graph.plotW
      height: graph.plotH
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onExited: graph.hoverIndex = -1
      onPositionChanged: function(mouse) {
        var i = Math.max(0, Math.min(graph.barCount - 1, Math.floor(mouse.x / graph.slotW)))
        graph.hoverIndex = root.historyBars[i] ? i : -1
      }
    }

    Item {
      id: timeRow
      y: graph.plotH + Theme.layout.module.tileInset
      width: graph.plotW
      height: tickMetrics.height
      TextMetrics { id: tickMetrics; font.family: root.uiFont; font.pixelSize: root.fCaption; text: "00:00" }
      Repeater {
        model: graph.ticks
        Text {
          required property var modelData
          readonly property real cx: graph.xOf(modelData)
          x: Math.max(0, Math.min(graph.plotW - width, cx - width / 2))
          text: graph.tickText(modelData)
          color: root.dimText
          font.family: root.uiFont
          font.pixelSize: root.fCaption
        }
      }
    }

    // What the two bar colours mean.
    Row {
      id: legend
      y: timeRow.y + timeRow.height + Theme.layout.list.gap
      spacing: Theme.layout.module.pad
      Repeater {
        model: [
          { ink: graph.batteryInk, text: "On battery" },
          { ink: graph.pluggedInk, text: "Plugged in" }
        ]
        Row {
          required property var modelData
          spacing: Theme.layout.list.gap / 2
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.layout.list.gap
            height: width
            radius: width / 2
            color: modelData.ink
          }
          Text {
            text: modelData.text
            color: root.dimText
            font.family: root.uiFont
            font.pixelSize: root.fCaption
          }
        }
      }
    }
  }

  // macOS pop-up button: the current value and a chevron on a soft fill;
  // `open` keeps it pressed-looking while its menu is out.
  component PopUpButton: Rectangle {
    id: pop
    property string text: ""
    property bool open: false
    // Sized for the widest value, so switching never resizes it.
    property string widest: "30 min"
    signal clicked()
    implicitWidth: widestMetrics.advanceWidth + Theme.layout.icon.small + popRow.spacing + 2 * Theme.layout.menu.itemPadX
    implicitHeight: Theme.m.control.height - Theme.layout.module.tileInset
    width: implicitWidth
    height: implicitHeight
    radius: Theme.m.radius.control
    color: popMouse.pressed || pop.open || popMouse.containsMouse ? root.washHover : root.wash
    border.width: Theme.layout.separator
    border.color: root.hairline
    Behavior on color { ColorAnimation { duration: popMouse.containsMouse ? Theme.dur("instant") : Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
    TextMetrics { id: widestMetrics; font.family: root.uiFont; font.pixelSize: root.fSmall; font.weight: Font.DemiBold; text: pop.widest }
    Row {
      id: popRow
      anchors.centerIn: parent
      spacing: Theme.layout.module.tileInset
      Fade { anchors.verticalCenter: parent.verticalCenter; text: pop.text; color: root.fg; font.pixelSize: root.fSmall; font.weight: Font.DemiBold }
      VIcon {
        anchors.verticalCenter: parent.verticalCenter
        name: "chevron.down"; weight: "bold"; size: Theme.layout.icon.small; color: root.dimText
        rotation: pop.open ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: Theme.move(Theme.dur("base")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
      }
    }
    MouseArea { id: popMouse; anchors.fill: parent; hoverEnabled: true; onClicked: pop.clicked() }
  }

  // Overview tile: small secondary label over the value.
  component StatTile: VTile {
    id: stat
    property string label: ""
    property string value: ""
    implicitHeight: statCol.implicitHeight + 2 * Theme.layout.list.gap + Theme.layout.module.tileInset
    radius: Theme.m.radius.row + Theme.layout.module.tileInset / 2
    Column {
      id: statCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Theme.layout.menu.itemPadX
      anchors.rightMargin: Theme.layout.menu.itemPadX
      anchors.verticalCenter: parent.verticalCenter
      Fade { width: parent.width; text: stat.label; color: root.dimText; elide: Text.ElideRight; font.pixelSize: root.fCaption }
      Fade { width: parent.width; text: stat.value; color: root.fg; elide: Text.ElideRight; font.pixelSize: root.fTitle; font.weight: Font.DemiBold }
    }
  }

  // Small heading of a section (as in the Control Center).
  component SectionLabel: VText {
    tone: "secondary"
    font.pixelSize: root.fCaption
    font.weight: Font.DemiBold
  }

  // Secondary one-liner under a control (what the selected mode does).
  component Caption: Fade {
    width: parent ? parent.width : 0
    color: root.dimText
    elide: Text.ElideRight
    font.pixelSize: root.fCaption
  }

  // Segmented control (VSegment): options are values, labels what they say;
  // `current` picks the plate. Busy dims it and takes no clicks.
  component Segmented: Item {
    id: seg
    property var options: []
    property var labels: []
    property string current: ""
    property bool busy: false
    signal picked(string value)
    readonly property int currentIndex: options.indexOf(current)
    implicitWidth: segCtl.implicitWidth
    implicitHeight: segCtl.implicitHeight
    opacity: busy ? Theme.core.alpha.disabled : 1
    Behavior on opacity { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
    VSegment {
      id: segCtl
      model: seg.options.map(function (o, i) { return seg.labels[i] !== undefined ? seg.labels[i] : String(o) })
      enabled: !seg.busy
      onActivated: function(i) { seg.picked(String(seg.options[i])) }
    }
    // re-applied on every change (a click inside VSegment would cut a plain binding)
    Binding { target: segCtl; property: "currentIndex"; value: Math.max(0, seg.currentIndex) }
  }

  // One fan: its name, a bar of its speed against its maximum, and its rpm.
  component FanRow: Item {
    id: fanRow
    property var fan: null
    property string name: ""
    readonly property real fraction: Math.max(0, Math.min(1, Model.fanFraction(fanRow.fan)))
    implicitHeight: Math.max(fanName.implicitHeight, fanRpm.implicitHeight)
    VText {
      id: fanName
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width / 4
      elide: Text.ElideRight
      text: fanRow.name
      tone: "secondary"
      font.pixelSize: root.fSmall
    }
    Item {
      id: fanTrack
      anchors.left: fanName.right
      anchors.leftMargin: Theme.layout.list.gap
      anchors.right: fanRpm.left
      anchors.rightMargin: Theme.layout.list.gap
      anchors.verticalCenter: parent.verticalCenter
      height: Theme.layout.module.tileInset
      clip: true
      Rectangle { anchors.fill: parent; radius: height / 2; color: root.trackColor }
      Rectangle { width: parent.width; height: parent.height; radius: height / 2; color: root.fg; x: fanSpring.value - parent.width }
      Spring { id: fanSpring; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion; target: fanRow.fraction * fanTrack.width }
    }
    Fade {
      id: fanRpm
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width / 5
      horizontalAlignment: Text.AlignRight
      text: fanRow.fan && fanRow.fan.rpm !== null ? fanRow.fan.rpm + " rpm" : "—"
      font.pixelSize: root.fSmall
    }
  }

  // One temperature: the reading, and what it is of.
  component TempTile: VTile {
    id: tempTile
    property var reading: null
    readonly property bool hot: !!tempTile.reading && tempTile.reading.c >= 90
    implicitHeight: tempBox.implicitHeight + Theme.layout.module.pad
    radius: Theme.m.radius.control
    Column {
      id: tempBox
      anchors.centerIn: parent
      width: parent.width - Theme.layout.list.gap
      Fade { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: tempTile.reading ? tempTile.reading.c + "°" : "—"
        color: tempTile.hot ? root.urgent : root.fg; font.pixelSize: root.fSmall; font.weight: Font.DemiBold }
      VText { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        text: tempTile.reading ? tempTile.reading.label : ""; tone: "secondary"; font.pixelSize: root.fCaption }
    }
  }

  // The boost shared by a group of fans (cpu or gpu), in percent of the kernel's 0-255.
  // Applied once the slider rests (VSlider follows the hand; no release signal).
  component BoostSlider: Column {
    id: boostBox
    property string group: ""
    property string title: ""
    readonly property var boost: Model.groupBoost(root.fans, group)
    property real liveValue: -1
    width: parent.width
    spacing: Theme.layout.module.tileInset
    visible: boost !== null
    Item {
      width: parent.width
      height: boostTitle.implicitHeight
      VText { id: boostTitle; text: boostBox.title; tone: "secondary"; font.pixelSize: root.fSmall }
      VText { anchors.right: parent.right; text: (boostBox.liveValue >= 0 ? Math.round(boostBox.liveValue / 5) * 5 : Model.boostPercent(boostBox.boost)) + " %"
        color: root.fg; font.pixelSize: root.fSmall }
    }
    VSlider {
      width: parent.width
      from: 0; to: 100
      value: boostBox.liveValue >= 0 ? boostBox.liveValue : Model.boostPercent(boostBox.boost)
      enabled: !root.dellBusy
      onMoved: function(v) { boostBox.liveValue = v; boostApply.restart() }
    }
    Timer {
      id: boostApply
      interval: Theme.delay("repeat")
      onTriggered: { root.setFanBoost(boostBox.group, Math.round(boostBox.liveValue / 5) * 5); boostBox.liveValue = -1 }
    }
  }

  // Three dots marching in the flow direction; each dot fades.
  component FlowArrow: Item {
    id: arrow
    property string dir: "none"
    property int phase: 0
    width: parent.arrowWidth
    function dotOpacity(index) {
      if (dir === "none") return 0.22
      var idx = dir === "left" ? (2 - index) : index
      return phase === idx ? 1.0 : 0.22
    }
    Timer {
      interval: Theme.dur("base")
      running: root.opened && arrow.dir !== "none"
      repeat: true
      onTriggered: arrow.phase = (arrow.phase + 1) % 3
    }
    Row {
      anchors.centerIn: parent
      spacing: Theme.layout.separator * 2
      Repeater {
        model: 3
        Rectangle {
          required property int index
          width: Theme.layout.separator * 3
          height: width
          radius: width / 2
          color: root.fg
          opacity: arrow.dotOpacity(index)
          Behavior on opacity { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
        }
      }
    }
  }

  component FlowNode: VTile {
    id: node
    property string icon: ""
    property string title: ""
    property string value: ""
    property string sub: ""
    property var rows: []
    property bool dimmed: false
    property bool collapsible: false
    property bool expanded: false
    implicitHeight: nodeBox.implicitHeight + Theme.layout.module.pad
    radius: Theme.m.radius.control

    Column {
      id: nodeBox
      anchors.top: parent.top
      anchors.topMargin: Theme.layout.module.pad / 2
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width - Theme.layout.list.gap
      spacing: Theme.layout.separator * 2
      opacity: node.dimmed ? Theme.core.alpha.disabled : 1
      Behavior on opacity { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }

      VIcon { visible: node.icon !== ""; anchors.horizontalCenter: parent.horizontalCenter; name: node.icon; size: Theme.layout.icon.large; color: root.fg }
      VText { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: node.title; tone: "secondary"; font.pixelSize: root.fCaption }
      // Value, plus a chevron that reveals the breakdown.
      Item {
        width: parent.width
        height: Math.max(nodeValue.implicitHeight, node.collapsible ? Theme.core.size.controlMin : 0)
        Fade {
          id: nodeValue
          anchors.verticalCenter: parent.verticalCenter
          x: node.collapsible ? (parent.width - width - chev.width) / 2 : (parent.width - width) / 2
          width: implicitWidth
          text: node.value
          color: root.fg
          font.pixelSize: root.fSmall
          font.weight: Font.DemiBold
        }
        Rectangle {
          id: chev
          visible: node.collapsible
          anchors.left: nodeValue.right
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.core.size.controlMin
          height: width
          radius: Theme.m.radius.chip
          color: chevMouse.containsMouse ? root.washHover : "transparent"
          VIcon {
            anchors.centerIn: parent
            name: "chevron.right"; weight: "bold"; size: Theme.layout.icon.small; color: root.dimText
            rotation: node.expanded ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: Theme.move(Theme.dur("base")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
          }
          MouseArea { id: chevMouse; anchors.fill: parent; hoverEnabled: true; onClicked: node.expanded = !node.expanded }
        }
      }
      VText { width: parent.width; visible: node.sub !== ""; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
        text: node.sub; tone: "secondary"; font.pixelSize: root.fCaption }
      Collapse {
        width: parent.width
        expanded: !node.collapsible || node.expanded
        Column {
          width: parent.width
          topPadding: Theme.layout.separator * 2
          Repeater {
            model: node.rows
            Item {
              required property var modelData
              width: parent.width
              height: rowLabel.implicitHeight
              VText { id: rowLabel; text: modelData.label; tone: "secondary"; font.pixelSize: root.fCaption }
              VText { anchors.right: parent.right; text: modelData.value; color: root.fg; font.pixelSize: root.fCaption; font.weight: Font.DemiBold }
            }
          }
        }
      }
    }
  }

  // StdioCollector with a live byte ceiling: past the cap the process is
  // killed and the consumer receives an empty payload (parses to null /
  // keeps last known data), so a runaway binary cannot exhaust shell memory
  // through routine refreshes.
  component CappedCollector: StdioCollector {
    id: capped
    required property Process proc
    property int cap: 262144
    property bool overflow: false
    waitForEnd: true
    signal finished(string text)
    onDataChanged: if (!overflow && data.length > cap) { overflow = true; proc.signal(9) }
    onStreamFinished: {
      // overflow implies data flowed, which guarantees the stream ends (we
      // kill the process), so resetting here is safe.
      var wasOverflow = overflow
      overflow = false
      if (wasOverflow) finished("")
      else finished(text)
    }
  }
}
