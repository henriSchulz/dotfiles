import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "file:///home/henri/.local/share/apple-ui/Apple.js" as Apple
import "file:///home/henri/.local/share/apple-ui" as AUi

// Battery menu in the apple-ui style (measured macOS look; motion from henri-ui). Fork of io.github.nipsen.dell-power
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
  // True while the History drill-in page is shown (HUi.PageStack depth 2).
  // Which drill-in page is showing (HUi.PageStack): the overview, History
  // or Advanced.
  readonly property bool historyShown: pages.currentItem === historyPage
  readonly property bool advancedOpen: pages.currentItem === advancedPage
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
  Component.onCompleted: syncHistorySettings()
  readonly property bool showHistory: setting("showHistory", true) === true
  readonly property string historyDir: {
    var d = String(setting("historyDir", "") || "")
    return d !== "" ? d : Quickshell.env("HOME") + "/Documents/akku-test/verlauf"
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

  // ---- Look (apple-ui: measured macOS material, dark or light glass after
  //      the wallpaper under the panel; motion tokens stay henri-ui)
  AUi.Backdrop { id: backdrop }
  AUi.Material { id: mat; dark: backdrop.dark }
  readonly property var m: mat
  function pt(v) { return Style.space(v) }
  readonly property color fg: mat.ink
  readonly property color dimText: mat.inkMuted
  readonly property color wash: mat.tile
  readonly property color washHover: mat.tileHover
  readonly property color trackColor: mat.sliderTrack
  readonly property color hairline: mat.hairline
  readonly property color accent: mat.accent
  readonly property color urgent: mat.urgent
  readonly property string iconFont: bar ? bar.fontFamily : root.uiFont
  readonly property string uiFont: Apple.uiFont
  readonly property string symbolFont: Apple.symbolFont
  readonly property int panelWidth: Style.space(340)
  readonly property int blockGap: Style.space(14)
  // Type scale (Apple pointSizes through the shell scale)
  readonly property int fCaption: pt(Apple.footnote)
  readonly property int fSmall: pt(Apple.subheadline)
  readonly property int fBody: pt(Apple.callout)
  readonly property int fSub: pt(Apple.headline)
  readonly property int fTitle: pt(Apple.title3)
  readonly property int fDisplay: pt(Apple.largeTitle)
  // The page stack clips; it reaches this far past the content on each side
  // so the rows' hover fills (which overhang the text) are not cut off.
  readonly property int pageInset: Style.space(8)

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
  }

  function closeHistoryPage() {
    if (historyShown) pages.pop()
  }

  // Advanced is a drill-in page too; it scrolls when it is taller than the
  // screen allows.
  function showAdvancedPage() {
    if (pages.depth > 1) return
    cursorActive = false
    advancedFlick.contentY = 0
    pages.push(advancedPage)
  }

  function closeSubPage() {
    cursorActive = false
    rangeMenu.open = false
    if (pages.depth > 1) pages.pop()
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
  // panel feels alive. Changes crossfade (HUi.CrossfadeText).
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
  }

  onOpenedChanged: {
    if (opened) {
      if (!batteryPresent) {
        close()
        return
      }

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
    interval: Motion.firstFrameTimeout + Motion.slow
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

  // macOS menu-bar battery: "84 %" + the drawn battery (HUi.BatteryGlyph).
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
          HUi.CrossfadeText {
            visible: root.pctInBar
            anchors.verticalCenter: parent.verticalCenter
            text: root.pctText
            color: button ? button.foreground : Color.foreground
            fontSize: Style.font.body
            fontFamily: button ? button.fontFamily : root.uiFont
          }
          HUi.BatteryGlyph {
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

  HUi.PopupPanel {
    id: panel
    kind: "panel"
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    padding: root.pt(Apple.padding)
    cardColor: root.m.sheet
    borderSpec: Border.flat(root.m.hairline, 1)
    contentWidth: panel.fittedContentWidth(root.panelWidth + padding * 2)
    // Follows the column, whose Collapse sections glide with the smooth spring.
    // Follows the page stack, whose height glides between the two pages.
    contentHeight: panel.fittedContentHeight(pages.implicitHeight)

    // Every open starts on the overview: go back to it once the popup is
    // fully gone, without animating it.
    onVisibleChanged: {
      if (visible) return
      root.cursorActive = false
      rangeMenu.open = false
      pages.pop(null, QQC.StackView.Immediate)
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // apple-ui components under the page stack find their palette here.
      property var appleMaterial: mat
      // Overview: ←/→ walk the power profiles and ⏎ applies the one under the
      // cursor; ↑ opens History, ↓ opens Advanced. History: ← goes back,
      // ⏎ opens the range menu (its own ↑ ↓ ⏎ Esc while open).
      // Esc goes back one page, and closes on the overview.
      onMoveRequested: function(dx, dy) {
        if (root.historyShown) {
          if (rangeMenu.open) return
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
          // After this key event: opened inside it, the menu took focus
          // mid-delivery and the same ⏎ picked an entry.
          if (!rangeMenu.open) Qt.callLater(rangeMenu.show)
          return
        }
        if (root.advancedOpen) return
        if (root.cursorActive) root.activateSelectedProfile()
        else root.showAdvancedPage()
      }
      onCloseRequested: rangeMenu.open ? rangeMenu.dismiss()
        : pages.depth > 1 ? root.closeSubPage() : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      HUi.PageStack {
        id: pages
        x: -root.pageInset
        width: parent.width + root.pageInset * 2
        initialItem: mainPage
      }

      // ---------- Page 1: overview ----------
      Item {
        id: mainPage
        implicitHeight: column.implicitHeight

      Column {
        id: column
        x: root.pageInset
        width: parent.width - root.pageInset * 2
        spacing: 0

        // ---------- Header: glyph · title/status · percentage ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroGlyph.height, heroLabels.implicitHeight, heroPercent.implicitHeight)

          HUi.BatteryGlyph {
            id: heroGlyph
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(20)
            level: root.batteryFraction
            charging: root.charging
            plugged: !root.discharging && !root.charging
            ink: root.fg
          }

          Column {
            id: heroLabels
            anchors.left: heroGlyph.right
            anchors.leftMargin: Style.space(12)
            anchors.right: heroPercent.left
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(1)

            Text {
              width: parent.width
              text: "Battery"
              color: root.fg
              elide: Text.ElideRight
              font.family: root.uiFont
              font.pixelSize: root.fSub
              font.weight: Font.DemiBold
            }

            HUi.CrossfadeText {
              fontFamily: root.uiFont
              width: parent.width
              text: root.heroStatusText
              color: root.dimText
              elide: Text.ElideRight
              fontSize: root.fSmall
            }
          }

          HUi.CrossfadeText {
            fontFamily: root.uiFont
            id: heroPercent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: root.pctText
            color: root.fg
            fontSize: root.fDisplay
            fontWeight: Font.Bold
          }
        }

        Item { width: 1; height: root.blockGap }

        ChargeBar { width: parent.width }

        HUi.Collapse {
          width: parent.width
          expanded: root.dellError !== ""
          Text {
            width: parent.width
            topPadding: Style.space(8)
            textFormat: Text.PlainText
            text: root.dellError
            color: root.urgent
            wrapMode: Text.WordWrap
            font.family: root.uiFont
            font.pixelSize: root.fCaption
          }
        }

        // ---------- Overview: size, time, cycles, flow ----------
        // Only gated by "we've ever loaded data", so the block never folds
        // mid-transition (UPower briefly reports FullyCharged on plug-in).
        HUi.Collapse {
          width: parent.width
          expanded: root.batteryInfo.percentage !== undefined
          Grid {
            id: statGrid
            width: parent.width
            topPadding: root.blockGap
            columns: 2
            spacing: Style.space(8)
            readonly property real cellWidth: (width - spacing) / 2

            StatTile { width: statGrid.cellWidth; label: "Battery size"; value: root.sizeText }
            StatTile { width: statGrid.cellWidth; label: root.timeLabel; value: root.timeText }
            StatTile { width: statGrid.cellWidth; label: "Charge cycles"; value: root.batteryInfo.cycles || "—" }
            StatTile { width: statGrid.cellWidth; label: root.flowLabel; value: root.flowText }
          }
        }

        // ---------- Power profile: the one control worth reaching without a drill-in ----------
        HUi.Collapse {
          width: parent.width
          expanded: root.profiles.length > 0
          Column {
            width: parent.width
            topPadding: root.blockGap
            spacing: Style.space(6)
            SectionLabel { text: "Power profile" }
            Segmented {
              width: parent.width
              options: root.profiles
              labels: root.profiles.map(function (p) { return root.profileLabel(p) })
              current: root.activeProfile
              cursorIndex: root.cursorActive ? root.profileIndex : -1
              onPicked: function(value) { root.setProfile(value) }
            }
          }
        }

        // ---------- Disclosures ----------
        Item { width: 1; height: Style.space(12) }
        Rectangle { width: parent.width; height: 1; color: root.hairline }
        Item { width: 1; height: Style.space(6) }

        // ---------- History: drill-in to its own page ----------
        DisclosureRow {
          visible: root.showHistory
          text: "History"
          drill: true
          onToggled: root.showHistoryPage()
        }

        // ---------- Advanced: drill-in to its own page ----------
        DisclosureRow {
          text: "Advanced"
          drill: true
          onToggled: root.showAdvancedPage()
        }

      }
      }

      // ---------- Page 3: advanced (drill-in) ----------
      Item {
        id: advancedPage
        visible: false
        // Taller than the screen allows → the body scrolls under the header.
        readonly property real maxBody: Math.max(Style.space(120),
          panel.availableCardHeight - panel.verticalContentInset - advancedHeader.implicitHeight)
        implicitHeight: advancedHeader.implicitHeight + Math.min(advancedBody.implicitHeight, maxBody)

        AUi.PageHeader {
          id: advancedHeader
          x: root.pageInset
          width: parent.width - root.pageInset * 2
          title: "Advanced"
          onBack: root.closeSubPage()
        }

        Flickable {
          id: advancedFlick
          x: root.pageInset
          y: advancedHeader.height
          width: parent.width - root.pageInset * 2
          height: parent.height - y
          contentHeight: advancedBody.implicitHeight
          clip: true
          interactive: contentHeight > height
          boundsBehavior: Flickable.DragAndOvershootBounds
          flickDeceleration: Motion.flickDeceleration
          maximumFlickVelocity: Motion.maximumFlickVelocity

          Item {
            id: advancedBody
            width: advancedFlick.width
            implicitHeight: advancedCol.implicitHeight
          Column {
            id: advancedCol
            width: parent.width
            spacing: 0

            // ---------- Fans and temperatures ----------
            HUi.Collapse {
              width: parent.width
              expanded: root.sensorsReady
              Column {
                width: parent.width
                topPadding: Style.space(8)
                spacing: Style.space(8)
                SectionLabel { text: "Fans & temperatures" }

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
                  spacing: Style.space(6)
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

                HUi.Collapse {
                  width: parent.width
                  expanded: root.fanBoostAvailable && root.thermal !== null && root.thermal.profile === "custom"
                  Column {
                    width: parent.width
                    spacing: Style.space(6)
                    BoostSlider { group: "cpu"; title: "CPU fans boost" }
                    BoostSlider { group: "gpu"; title: "GPU fans boost" }
                  }
                }
              }
            }

            // ---------- Power flow chain ----------
            HUi.Collapse {
              width: parent.width
              expanded: root.powerChain !== null
              Column {
                width: parent.width
                topPadding: root.blockGap
                spacing: Style.space(6)
                SectionLabel { text: "Power flow" }

                Row {
                  id: flowRow
                  width: parent.width
                  spacing: Style.space(4)

                  readonly property real arrowWidth: Style.space(14)
                  readonly property real nodeWidth: (width - arrowWidth * 2 - spacing * 4) / 3
                  readonly property real nodeHeight: Math.max(sourceNode.implicitHeight, componentsNode.implicitHeight, batteryNode.implicitHeight)

                  // Source: the power the adapter provides (psys + battery charge).
                  FlowNode {
                    id: sourceNode
                    width: flowRow.nodeWidth
                    height: flowRow.nodeHeight
                    dimmed: !!root.powerChain && root.powerChain.source === "battery"
                    iconText: root.sourceIcon()
                    title: root.powerChain && root.powerChain.source === "typec" ? "USB-C" : "AC"
                    value: root.powerChain && root.powerChain.source !== "battery"
                      ? root.plainWatt(root.powerChain.adapterW)
                      : "Unplugged"
                  }

                  FlowArrow { dir: root.sourceFlowDir(); height: flowRow.nodeHeight }

                  // Components: total, breakdown behind the chevron.
                  FlowNode {
                    id: componentsNode
                    width: flowRow.nodeWidth
                    height: flowRow.nodeHeight
                    iconText: ""
                    title: "Components"
                    value: root.powerChain ? root.plainWatt(root.powerChain.componentsW) : "—"
                    collapsible: true
                    // RAM only where the CPU reports it (RAPL dram); elsewhere it is part of "Other".
                    rows: {
                      var list = [
                        {
                          label: "CPU",
                          value: root.powerChain && root.powerChain.cpuW !== null && root.powerChain.igpuW !== null
                            ? root.plainWatt(root.powerChain.cpuW - root.powerChain.igpuW)
                            : "—"
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
                    iconText: ""
                    title: "Battery"
                    value: root.powerChain ? root.signedWatt(root.powerChain.batteryW) : "—"
                    sub: root.batterySubText()
                  }
                }
              }
            }

            // ---------- Charge mode ----------
            HUi.Collapse {
              width: parent.width
              expanded: root.dellWmiReady
              Column {
                width: parent.width
                topPadding: root.blockGap
                spacing: Style.space(6)
                SectionLabel { text: "Charge mode" }
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
            HUi.Collapse {
              width: parent.width
              expanded: root.usbPowerShareReady || root.typeCPowerReady
              Column {
                width: parent.width
                topPadding: root.blockGap
                spacing: Style.space(8)
                SectionLabel { text: "USB ports" }

                Item {
                  width: parent.width
                  height: Math.max(usbText.implicitHeight, usbToggle.height)
                  visible: root.usbPowerShareReady

                  Column {
                    id: usbText
                    anchors.left: parent.left
                    anchors.right: usbToggle.left
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(1)
                    Text {
                      text: "USB PowerShare"
                      color: root.fg
                      font.family: root.uiFont
                      font.pixelSize: root.fBody
                    }
                    Caption { text: "Keeps the USB-A port powered while the laptop sleeps" }
                  }

                  AUi.Switch {
                    id: usbToggle
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
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
                  spacing: Style.space(6)
                  visible: root.typeCPowerReady
                  Text {
                    text: "USB-C output"
                    color: root.fg
                    font.family: root.uiFont
                    font.pixelSize: root.fBody
                  }
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
            HUi.Collapse {
              width: parent.width
              expanded: root.helperMissing
              Column {
                width: parent.width
                topPadding: root.blockGap
                spacing: Style.space(6)
                SectionLabel { text: root.brand + " setup" }
                Text {
                  width: parent.width
                  wrapMode: Text.WordWrap
                  textFormat: Text.PlainText
                  text: "Charge modes, thresholds, USB options and power flow need the system helper. Click to copy the command, then run it once in a terminal:"
                  color: root.dimText
                  font.family: root.uiFont
                  font.pixelSize: root.fCaption
                }
                HUi.Pressable {
                  width: parent.width
                  height: Style.space(Motion.controlHeight)
                  tint: root.fg
                  activeFocusOnTab: false
                  onClicked: if (!setupCopyProc.running) setupCopyProc.running = true

                  Rectangle {
                    anchors.fill: parent
                    radius: Style.space(Motion.radiusControl)
                    color: root.wash
                  }
                  HUi.CrossfadeText {
                    fontFamily: root.uiFont
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideMiddle
                    text: root.setupCopied ? "Copied — paste it in a terminal" : root.setupCommand
                    color: root.fg
                    fontSize: root.fCaption
                  }
                }
              }
            }

            Item { width: 1; height: Style.space(4) }
          }
          }
        }
      }

      // ---------- Page 2: battery history (drill-in) ----------
      Item {
        id: historyPage
        visible: false
        implicitHeight: historyHeader.implicitHeight + historyBody.implicitHeight

        AUi.PageHeader {
          id: historyHeader
          x: root.pageInset
          width: parent.width - root.pageInset * 2
          title: "Battery History"
          onBack: root.closeSubPage()

          PopUpButton {
            id: rangeButton
            text: root.historyRange.short
            open: rangeMenu.open
            Accessible.name: "Time range"
            onClicked: rangeMenu.open ? rangeMenu.dismiss() : rangeMenu.show()
          }
        }

        Item {
          id: historyBody
          x: root.pageInset
          y: historyHeader.height
          width: parent.width - root.pageInset * 2
          implicitHeight: historyCol.implicitHeight
          Column {
            id: historyCol
            width: parent.width
            topPadding: Style.space(6)
            bottomPadding: Style.space(4)
            spacing: Style.space(8)

            Item {
              width: parent.width
              height: Math.max(historyTitle.implicitHeight, historyReadout.implicitHeight)
              // What the bars show: charge, power, voltage or current.
              Segmented {
                id: historyTitle
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(212)
                options: root.historyMetricKeys
                labels: root.historyMetricLabels
                current: root.historyMetric.key
                onPicked: function(value) { root.setHistoryMetric(value) }
              }
              HUi.CrossfadeText {
                fontFamily: root.uiFont
                id: historyReadout
                anchors.right: parent.right
                anchors.left: historyTitle.right
                anchors.leftMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
                text: historyGraph.readout
                color: root.fg
                fontSize: root.fCaption
                fontWeight: Font.Medium
              }
            }

            HistoryGraph {
              id: historyGraph
              width: parent.width
            }

            Grid {
              id: historyGrid
              width: parent.width
              columns: 2
              spacing: Style.space(8)
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

        // Clicks beside the open range menu close it and go nowhere else
        // (the popup's own outside-click handling covers other windows).
        MouseArea {
          anchors.fill: parent
          z: 9
          enabled: rangeMenu.open
          visible: enabled
          acceptedButtons: Qt.AllButtons
          onPressed: rangeMenu.dismiss()
        }

        // Range picker: a menu dropping out of the header button. Its own
        // outside-click grab stays off — a second focus grab on the popup
        // window would clear the popup's grab and close the whole panel.
        HUi.Reveal {
          id: rangeMenu
          kind: "menu"
          origin: Item.TopRight
          closeOnOutsideClick: false
          z: 10
          x: parent.width - root.pageInset - width + Style.space(4)
          y: historyHeader.y + historyHeader.height / 2 + rangeButton.height / 2 + Style.space(4)
          width: rangeSurface.implicitWidth
          height: rangeSurface.implicitHeight

          function show() {
            var m = rangeList.model
            for (var i = 0; i < m.length; i++) if (m[i].checked === true) rangeList.currentIndex = i
            open = true
          }
          function dismiss() {
            open = false
            keyCatcher.forceActiveFocus()
          }
          onDismissRequested: dismiss()

          HUi.Surface {
            id: rangeSurface
            anchors.fill: parent
            role: "menu"
            kind: "menu"
            padding: Style.space(5)
            implicitWidth: rangeList.implicitWidth + padding * 2
            implicitHeight: rangeList.implicitHeight + padding * 2
            HUi.MenuList {
              id: rangeList
              x: rangeSurface.contentLeftInset
              y: rangeSurface.contentTopInset
              width: parent.width - rangeSurface.contentLeftInset - rangeSurface.contentRightInset
              minWidth: Style.space(140)
              focus: rangeMenu.open
              model: {
                var cur = root.historyRange
                var out = []
                var list = root.historyRanges
                for (var i = 0; i < list.length; i++) {
                  // Minutes, hours, days — a separator between the groups.
                  if (i > 0 && list[i].hours >= 1 !== list[i - 1].hours >= 1
                      || i > 0 && list[i].hours > 24 !== list[i - 1].hours > 24)
                    out.push({ separator: true })
                  out.push({ text: list[i].label, checked: list[i] === cur, key: list[i].key })
                }
                return out
              }
              onActivated: function(index, entry) {
                rangeMenu.dismiss()
                root.setHistoryRange(entry.key)
              }
            }
          }
        }
      }
    }
  }

  // ============================================================ components

  // The charge level on a track, with the charge thresholds drawn onto it:
  // an accent zone between start and stop, a marker at each end. Drag a
  // marker to change it — the helper switches the charge mode to Custom
  // automatically, so a dimmed (inactive) zone comes alive on first drag.
  component ChargeBar: Item {
    id: chargeBar
    readonly property real trackH: Style.space(8)
    readonly property bool low: root.batteryFraction <= 0.2 && root.discharging
    implicitHeight: trackH + Style.space(8)

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
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
      opacity: !root.dellThresholdsReady ? 0 : (root.thresholdsLive ? 1 : 0.6)
      Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    }

    // Fill: a round cap plus a full-width bar slid in from the left inside a
    // clip — only x moves per frame (henri-ui: transform, not width).
    Rectangle {
      id: fillCap
      anchors.verticalCenter: barTrack.verticalCenter
      width: barTrack.height
      height: barTrack.height
      radius: height / 2
      color: fillBar.color
    }
    Item {
      x: barTrack.height / 2
      width: barTrack.width - x
      height: barTrack.height
      anchors.verticalCenter: barTrack.verticalCenter
      clip: true
      Rectangle {
        id: fillBar
        width: barTrack.width
        height: barTrack.height
        radius: height / 2
        color: chargeBar.low ? root.urgent : root.m.sliderFill
        x: fillSpring.value - barTrack.width + barTrack.height / 2
        Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      }
    }
    HUi.SpringValue {
      id: fillSpring
      to: Math.max(0, Math.min(1, root.batteryFraction)) * (barTrack.width - barTrack.height / 2)
      epsilon: 0.5
    }

    ThresholdMarker { percent: root.effStart(); dragging: root.draggingStart }
    ThresholdMarker { percent: root.effEnd(); dragging: root.draggingStop }

    MouseArea {
      id: barMouse
      anchors.fill: parent
      hoverEnabled: true
      property string hoverText: ""
      property string hoverTick: ""

      function tickNear(x) {
        if (!root.dellThresholdsReady) return ""
        var sx = barTrack.width * root.effStart() / 100
        var ex = barTrack.width * root.effEnd() / 100
        if (Math.abs(x - ex) <= Style.space(12)) return "end"
        if (Math.abs(x - sx) <= Style.space(12)) return "start"
        return ""
      }

      function updateHover() {
        if (root.draggingStart || root.draggingStop) {
          hoverTick = root.draggingStop ? "end" : "start"
          hoverText = root.draggingStop
            ? "Charge stop: " + root.effEnd() + " %"
            : "Charge start: " + root.effStart() + " %"
          return
        }
        if (!containsMouse) {
          hoverTick = ""
          hoverText = ""
          return
        }
        var t = tickNear(mouseX)
        if (t === "end") {
          hoverTick = "end"
          hoverText = "Charge stop: " + root.effEnd() + " %"
        } else if (t === "start") {
          hoverTick = "start"
          hoverText = "Charge start: " + root.effStart() + " %"
        } else if (root.dellThresholdsReady) {
          hoverTick = ""
          hoverText = root.thresholdTickText()
        } else {
          hoverTick = ""
          hoverText = ""
        }
      }

      cursorShape: root.dellThresholdsReady && tickNear(mouseX) !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor

      onPressed: function(mouse) {
        if (root.dellBusy) return
        var t = tickNear(mouse.x)
        if (t === "end") {
          root.previewEnd = root.effEnd()
          root.draggingStop = true
        } else if (t === "start") {
          root.previewStart = root.effStart()
          root.draggingStart = true
        }
        updateHover()
      }

      onPositionChanged: function(mouse) {
        if (root.draggingStart || root.draggingStop) {
          var pct = Math.max(0, Math.min(100, mouse.x / barTrack.width * 100))
          var snapped = Math.round(pct / root.chargeLimitStep) * root.chargeLimitStep
          if (root.draggingStop) {
            root.previewEnd = Model.dellClampEnd(snapped, root.effStart())
          } else if (root.draggingStart) {
            root.previewStart = Model.dellClampStart(Math.min(snapped, root.effEnd() - Model.DELL_GAP))
          }
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

    // Tooltip inside the panel (the bar's tooltip system only anchors items
    // in the bar window). Fades; keeps its last text while fading out.
    Rectangle {
      id: thresholdTip
      property string shownText: ""
      readonly property bool active: barMouse.hoverText !== ""
      Connections {
        target: barMouse
        function onHoverTextChanged() { if (barMouse.hoverText !== "") thresholdTip.shownText = barMouse.hoverText }
      }
      z: 5
      y: -height - Style.space(4)
      x: {
        var tickPct = barMouse.hoverTick === "start" ? root.effStart()
          : barMouse.hoverTick === "end" ? root.effEnd()
          : (barMouse.containsMouse ? barMouse.mouseX / barTrack.width * 100 : 50)
        var cx = barTrack.width * tickPct / 100
        return Math.max(0, Math.min(chargeBar.width - width, cx - width / 2))
      }
      width: Math.min(chargeBar.width, tipLabel.implicitWidth + Style.space(14))
      height: tipLabel.implicitHeight + Style.space(8)
      radius: Style.space(Motion.radiusChip)
      color: Color.tooltip.background
      border.width: 1
      border.color: Color.tooltip.border
      opacity: active ? 1 : 0
      visible: opacity > 0.01
      Behavior on opacity {
        NumberAnimation {
          duration: thresholdTip.active ? Motion.fast : Motion.exit(Motion.fast)
          easing.type: Easing.BezierSpline
          easing.bezierCurve: thresholdTip.active ? Motion.easeOut : Motion.easeExit
        }
      }

      Text {
        id: tipLabel
        anchors.centerIn: parent
        width: Math.min(implicitWidth, chargeBar.width - Style.space(14))
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: thresholdTip.shownText
        color: Color.tooltip.text
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
    width: Style.space(4)
    height: Style.space(18)
    radius: width / 2
    anchors.verticalCenter: parent.verticalCenter
    color: root.accent
    x: track * percent / 100 - width / 2
    opacity: !root.dellThresholdsReady ? 0 : (root.thresholdsLive ? 1 : 0.55)
    scale: dragging && !Motion.reduceMotion ? 1.15 : 1
    Behavior on x {
      enabled: !marker.dragging
      NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
    }
    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    Behavior on scale { NumberAnimation { duration: Motion.instant; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
  }

  // A row that folds a section open, chevron turning like a macOS disclosure.
  component DisclosureRow: Item {
    id: disc
    property string text: ""
    property bool expanded: false
    // Drill-in row: the chevron stays pointing right and nudges on hover.
    property bool drill: false
    signal toggled()
    width: parent.width
    height: visible ? Style.space(Motion.controlHeight) : 0

    HUi.Pressable {
      id: discPress
      // Hover fill reaches a little past the text, like a macOS row.
      x: -Style.space(6)
      width: parent.width + Style.space(12)
      height: parent.height
      radius: Style.space(Motion.radiusRow)
      tint: root.fg
      pressScaleEnabled: false
      activeFocusOnTab: false
      onClicked: disc.toggled()

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        text: disc.text
        color: root.fg
        font.family: root.uiFont
        font.pixelSize: root.fBody
        font.weight: Font.Medium
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: Apple.sf(0x10018A)
        rotation: disc.expanded && !disc.drill ? 90 : 0
        transform: Translate {
          x: disc.drill && discPress.hovered && !Motion.reduceMotion ? Style.space(3) : 0
          Behavior on x {
            NumberAnimation {
              duration: discPress.hovered ? Motion.instant : Motion.fast
              easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
            }
          }
        }
        color: root.dimText
        font.family: root.symbolFont
        font.pixelSize: root.fBody
        Behavior on rotation {
          NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
        }
      }
    }
  }

  // The chosen metric over the history window as bars, like the macOS battery
  // graph: 30–84 bars over the chosen range, each at the level it ended on (or
  // its mean for the metered values) — accent on battery, pale accent while
  // plugged in, urgent at 20 % and below on the charge view. Slots without
  // samples (sleep, laptop off) stay empty. Three gridlines label the axis the
  // model fitted to the metric, round clock or day ticks; hovering a bar reads
  // it out and dims the rest.
  component HistoryGraph: Item {
    id: graph
    readonly property real gutter: gutterMetrics.advanceWidth + Style.space(8)
    readonly property real plotW: Math.max(1, width - gutter)
    readonly property real plotH: Style.space(88)
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
    readonly property color batteryInk: root.accent
    readonly property color pluggedInk: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.35)
    property int hoverIndex: -1
    readonly property var hoverBar: hoverIndex >= 0 ? root.historyBars[hoverIndex] || null : null
    // Only the metric on show — four of them side by side would not fit next
    // to the switcher, and the bar being pointed at is what is being asked.
    readonly property string readout: {
      var b = graph.hoverBar
      // The slot's start, not its span: four labels leave the readout about
      // 120 px, and the axis already says how wide a slot is.
      if (b) return graph.stamp(b.t0) + " · " + root.historyValue(graph.barValue(b), graph.metric)
      var st = root.historyStats
      if (!st || !st.samples) return ""
      if (graph.metric.key === "percent") return "Now " + Math.round(root.batteryFraction * 100) + " %"
      return "Now " + root.historyValue(
        graph.metric.key === "watts" ? st.lastW : graph.metric.key === "volts" ? st.lastV : st.lastA,
        graph.metric)
    }
    implicitHeight: plotH + timeRow.height + Style.space(12) + legend.height

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
        Rectangle { width: graph.plotW; height: 1; color: root.hairline }
        HUi.CrossfadeText {
          fontFamily: root.uiFont
          x: graph.plotW + Style.space(6)
          anchors.verticalCenter: parent.top
          text: root.historyAxisLabel(graph.axis.min + graph.axisSpan * modelData / 100, graph.metric)
          color: root.dimText
          fontSize: root.fCaption
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
        color: !bucket ? "transparent"
          : (graph.metric.key === "percent" && bucket.pct <= 20 ? root.urgent
            : (bucket.battery ? graph.batteryInk : graph.pluggedInk))
        opacity: !bucket ? 0 : (graph.hoverIndex < 0 || graph.hoverIndex === index ? 1 : 0.45)
        transform: Scale {
          origin.y: graph.plotH
          yScale: bar.bucket ? Math.max(0.02, graph.valueOf(bar.bucket)) : 0
          Behavior on yScale { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        }
        Behavior on opacity { NumberAnimation { duration: graph.hoverIndex >= 0 ? Motion.instant : Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
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
      y: graph.plotH + Style.space(4)
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
      y: timeRow.y + timeRow.height + Style.space(8)
      spacing: Style.space(12)
      Repeater {
        model: [
          { ink: graph.batteryInk, text: "On battery" },
          { ink: graph.pluggedInk, text: "Plugged in" }
        ]
        Row {
          required property var modelData
          spacing: Style.space(5)
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(8)
            height: Style.space(8)
            radius: Style.space(2)
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
  component PopUpButton: HUi.Pressable {
    id: pop
    property string text: ""
    property bool open: false
    // Sized for the widest value, so switching never resizes it.
    property string widest: "30 min"
    implicitWidth: widestMetrics.advanceWidth + chevron.implicitWidth + popRow.spacing + Style.space(20)
    implicitHeight: Style.space(Motion.controlHeight)
    width: implicitWidth
    height: implicitHeight
    tint: root.fg
    showFill: false
    activeFocusOnTab: false

    TextMetrics { id: widestMetrics; font.family: root.uiFont; font.pixelSize: root.fSmall; font.weight: Font.DemiBold; text: pop.widest }

    // The resting fill is the segmented track's wash; hover and press add
    // the usual state alpha on top of it.
    Rectangle {
      anchors.fill: parent
      radius: pop.radius
      color: pop.pressed || pop.open || pop.hovered ? root.washHover : root.m.capsule
      border.width: 1
      border.color: root.hairline
      Behavior on color {
        ColorAnimation {
          duration: pop.hovered || pop.pressed ? Motion.instant : Motion.fast
          easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
        }
      }
    }

    Row {
      id: popRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      HUi.CrossfadeText {
        fontFamily: root.uiFont
        anchors.verticalCenter: parent.verticalCenter
        text: pop.text
        color: root.fg
        fontSize: root.fSmall
        fontWeight: Font.DemiBold
      }
      Text {
        id: chevron
        anchors.verticalCenter: parent.verticalCenter
        text: Apple.sf(0x10018A)
        color: root.dimText
        font.family: root.symbolFont
        font.pixelSize: root.fCaption
        rotation: pop.open ? -90 : 90
        Behavior on rotation { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      }
    }
  }

  // Overview tile: small secondary label over the value.
  component StatTile: Rectangle {
    id: stat
    property string label: ""
    property string value: ""
    implicitHeight: statCol.implicitHeight + Style.space(16)
    radius: root.pt(Apple.radiusRow)
    color: root.wash
    border.width: 1
    border.color: root.hairline

    Column {
      id: statCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      HUi.CrossfadeText {
        fontFamily: root.uiFont
        width: parent.width
        text: stat.label
        color: root.dimText
        elide: Text.ElideRight
        fontSize: root.fCaption
      }
      HUi.CrossfadeText {
        fontFamily: root.uiFont
        width: parent.width
        text: stat.value
        color: root.fg
        elide: Text.ElideRight
        fontSize: root.fBody
        fontWeight: Font.DemiBold
      }
    }
  }

  // Small-caps heading of an Advanced section (same as the Control Center).
  component SectionLabel: AUi.SectionLabel { leftPadding: 0; topPadding: 0 }

  // Secondary one-liner under a control (what the selected mode does).
  component Caption: HUi.CrossfadeText {
    width: parent.width
    color: root.dimText
    elide: Text.ElideRight
    fontFamily: root.uiFont
    fontSize: root.fCaption
  }

  // macOS segmented control: the accent selection glides between segments
  // (HUi.Highlight, glide). Wraps into rows with `columns`. `cursorIndex`
  // draws the keyboard ring.
  component Segmented: Item {
    id: seg
    property var options: []
    property var labels: []
    property string current: ""
    property int columns: Math.max(1, options.length)
    property int cursorIndex: -1
    property bool busy: false
    signal picked(string value)

    readonly property real inset: Style.space(2)
    readonly property int currentIndex: options.indexOf(current)
    readonly property int labelSize: columns > 3 ? root.fCaption : root.fSmall

    implicitHeight: segGrid.implicitHeight + inset * 2
    opacity: busy ? Motion.disabledOpacity : 1
    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: root.wash
      border.width: 1
      border.color: root.hairline
    }

    Item {
      anchors.fill: parent
      anchors.margins: seg.inset

      HUi.Highlight {
        glide: true
        color: root.accent
        radius: height / 2
        target: seg.currentIndex >= 0 && seg.currentIndex < segRep.count ? segRep.itemAt(seg.currentIndex) : null
      }

      Grid {
        id: segGrid
        width: parent.width
        columns: seg.columns
        spacing: seg.inset
        readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

        Repeater {
          id: segRep
          model: seg.options

          HUi.Pressable {
            id: cell
            required property var modelData
            required property int index
            readonly property bool isCurrent: index === seg.currentIndex
            width: segGrid.cellWidth
            height: Style.space(Motion.controlHeight) - seg.inset * 2
            radius: height / 2
            tint: root.fg
            showFill: !isCurrent
            enabled: !seg.busy
            activeFocusOnTab: false
            onClicked: seg.picked(String(modelData))

            Text {
              anchors.fill: parent
              anchors.leftMargin: Style.space(4)
              anchors.rightMargin: Style.space(4)
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: seg.labels[cell.index] !== undefined ? seg.labels[cell.index] : String(cell.modelData)
              color: cell.isCurrent ? "#ffffff" : root.fg
              font.family: root.uiFont
              font.pixelSize: seg.labelSize
              font.weight: cell.isCurrent ? Font.DemiBold : Font.Normal
              Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
            }

            // Keyboard cursor ring (arrow keys in the Advanced section).
            Rectangle {
              anchors.fill: parent
              anchors.margins: -Style.space(Motion.focusRing)
              radius: cell.radius + Style.space(Motion.focusRing)
              color: "transparent"
              border.width: Style.space(Motion.focusRing)
              border.color: root.m.cursorRing
              opacity: seg.cursorIndex === cell.index ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
            }
          }
        }
      }
    }
  }

  // One fan: its name, a bar of its speed against its maximum, and its rpm.
  component FanRow: Item {
    id: fanRow
    property var fan: null
    property string name: ""
    readonly property real fraction: Math.max(0, Math.min(1, Model.fanFraction(fanRow.fan)))

    implicitHeight: Math.max(fanName.implicitHeight, fanRpm.implicitHeight)

    Text {
      id: fanName
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(84)
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: fanRow.name
      color: root.dimText
      font.family: root.uiFont
      font.pixelSize: root.fSmall
    }

    Item {
      id: fanTrack
      anchors.left: fanName.right
      anchors.leftMargin: Style.space(8)
      anchors.right: fanRpm.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      height: Style.space(4)
      clip: true

      Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.trackColor
      }
      Rectangle {
        width: parent.width
        height: parent.height
        radius: height / 2
        color: root.fg
        x: fanSpring.value - parent.width
      }
      HUi.SpringValue { id: fanSpring; to: fanRow.fraction * fanTrack.width; epsilon: 0.5 }
    }

    HUi.CrossfadeText {
      fontFamily: root.uiFont
      id: fanRpm
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(66)
      horizontalAlignment: Text.AlignRight
      text: fanRow.fan && fanRow.fan.rpm !== null ? fanRow.fan.rpm + " rpm" : "—"
      color: root.fg
      fontSize: root.fSmall
    }
  }

  // One temperature: the reading, and what it is of.
  component TempTile: Rectangle {
    id: tempTile
    property var reading: null
    readonly property bool hot: !!tempTile.reading && tempTile.reading.c >= 90

    implicitHeight: tempBox.implicitHeight + Style.space(12)
    radius: Style.space(Motion.radiusControl)
    color: root.wash
    border.width: 1
    border.color: root.hairline

    Column {
      id: tempBox
      anchors.centerIn: parent
      width: parent.width - Style.space(8)
      spacing: Style.space(1)

      HUi.CrossfadeText {
        fontFamily: root.uiFont
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: tempTile.reading ? tempTile.reading.c + "°" : "—"
        color: tempTile.hot ? root.urgent : root.fg
        fontSize: root.fSmall
        fontWeight: Font.DemiBold
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: tempTile.reading ? tempTile.reading.label : ""
        color: root.dimText
        font.family: root.uiFont
        font.pixelSize: root.fCaption
      }
    }
  }

  // The boost shared by a group of fans (cpu or gpu), in percent of the kernel's 0-255.
  component BoostSlider: Column {
    id: boostBox
    property string group: ""
    property string title: ""
    readonly property var boost: Model.groupBoost(root.fans, group)

    width: parent.width
    spacing: Style.space(4)
    visible: boost !== null

    Item {
      width: parent.width
      height: boostTitle.implicitHeight
      Text {
        id: boostTitle
        text: boostBox.title
        color: root.dimText
        font.family: root.uiFont
        font.pixelSize: root.fSmall
      }
      Text {
        anchors.right: parent.right
        text: (boostSlider.dragging ? Math.round(boostSlider.liveValue) : Model.boostPercent(boostBox.boost)) + " %"
        color: root.fg
        font.family: root.uiFont
        font.pixelSize: root.fSmall
      }
    }

    AUi.Slider {
      id: boostSlider
      width: parent.width
      minimum: 0
      maximum: 100
      step: 5
      value: Model.boostPercent(boostBox.boost)
      enabled: !root.dellBusy
      onReleased: function(v) { root.setFanBoost(boostBox.group, Math.round(v / 5) * 5) }
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
      interval: 240
      running: root.opened && arrow.dir !== "none"
      repeat: true
      onTriggered: arrow.phase = (arrow.phase + 1) % 3
    }

    Row {
      anchors.centerIn: parent
      spacing: Style.space(2)
      Repeater {
        model: 3
        Rectangle {
          required property int index
          width: Style.space(3)
          height: width
          radius: width / 2
          color: root.fg
          opacity: arrow.dotOpacity(index)
          Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        }
      }
    }
  }

  component FlowNode: Rectangle {
    id: node
    property string iconText: ""
    property string title: ""
    property string value: ""
    property string sub: ""
    property var rows: []
    property bool dimmed: false
    property bool collapsible: false
    property bool expanded: false

    implicitHeight: nodeBox.implicitHeight + Style.space(14)
    radius: Style.space(Motion.radiusControl)
    color: root.wash
    border.width: 1
    border.color: root.hairline

    Column {
      id: nodeBox
      anchors.top: parent.top
      anchors.topMargin: Style.space(7)
      anchors.horizontalCenter: parent.horizontalCenter
      width: parent.width - Style.space(10)
      spacing: Style.space(2)
      opacity: node.dimmed ? Motion.disabledOpacity : 1
      Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        visible: node.iconText !== ""
        text: node.iconText
        color: root.fg
        font.family: root.iconFont
        font.pixelSize: root.fTitle
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: node.title
        color: root.dimText
        font.family: root.uiFont
        font.pixelSize: root.fCaption
      }

      // Value, plus a chevron that reveals the breakdown.
      Item {
        width: parent.width
        height: Math.max(nodeValue.implicitHeight, node.collapsible ? Style.space(Motion.controlMin) : 0)

        HUi.CrossfadeText {
          fontFamily: root.uiFont
          id: nodeValue
          anchors.verticalCenter: parent.verticalCenter
          x: node.collapsible ? (parent.width - width - chevron.width) / 2 : (parent.width - width) / 2
          width: implicitWidth
          text: node.value
          color: root.fg
          fontSize: root.fSmall
          fontWeight: Font.DemiBold
        }

        HUi.Pressable {
          id: chevron
          visible: node.collapsible
          anchors.left: nodeValue.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(Motion.controlMin)
          height: width
          radius: Style.space(Motion.radiusChip)
          tint: root.fg
          activeFocusOnTab: false
          onClicked: node.expanded = !node.expanded

          Text {
            anchors.centerIn: parent
            text: Apple.sf(0x10018A)
            rotation: node.expanded ? 90 : 0
            color: root.dimText
            font.family: root.symbolFont
            font.pixelSize: root.fCaption
            Behavior on rotation { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
          }
        }
      }

      Text {
        width: parent.width
        visible: node.sub !== ""
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: node.sub
        color: root.dimText
        font.family: root.uiFont
        font.pixelSize: root.fCaption
      }

      HUi.Collapse {
        width: parent.width
        expanded: !node.collapsible || node.expanded
        Column {
          width: parent.width
          topPadding: Style.space(2)
          Repeater {
            model: node.rows
            Item {
              required property var modelData
              width: parent.width
              height: rowLabel.implicitHeight
              Text {
                id: rowLabel
                textFormat: Text.PlainText
                text: modelData.label
                color: root.dimText
                font.family: root.uiFont
                font.pixelSize: root.fCaption
              }
              Text {
                anchors.right: parent.right
                textFormat: Text.PlainText
                text: modelData.value
                color: root.fg
                font.family: root.uiFont
                font.pixelSize: root.fCaption
                font.weight: Font.DemiBold
              }
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
