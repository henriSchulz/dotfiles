import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

// Battery menu in the henri-ui style. Fork of io.github.nipsen.dell-power
// (MIT, see LICENSE): the backend (UPower, omarchy tools, the root helper
// /usr/local/bin/dell-charge-limit) is unchanged; the popup is rebuilt.
// It opens on the overview — charge, battery size, time left, cycles and
// the current flow — and everything else sits under a collapsed "Advanced"
// disclosure: power profile, thermal mode, fans, power flow, charge mode, USB.
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
  property bool advancedOpen: false
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
  // Alienware laptops (and any whose helper reports them): the firmware's thermal
  // modes, and the fans and temperatures the EC reports.
  readonly property string brand: dellStatus !== null ? dellStatus.brand : "Dell"
  readonly property var thermal: dellStatus !== null ? dellStatus.thermal : null
  readonly property var thermalModes: Model.thermalChoices(thermal)
  readonly property bool thermalReady: thermal !== null && Model.thermalExtended(thermal)
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

  // ---- Look (henri-ui: theme colours, secondary text by alpha, token radii)
  readonly property color fg: Color.popups.text
  readonly property color dimText: Util.alpha(fg, Motion.secondaryTextAlpha)
  readonly property color wash: Util.alpha(fg, 0.07)
  readonly property color trackColor: Util.alpha(fg, 0.12)
  readonly property color hairline: Util.alpha(fg, Motion.hairlineAlpha)
  readonly property string iconFont: bar ? bar.fontFamily : Style.font.family
  readonly property int panelWidth: Style.space(340)
  readonly property int blockGap: Style.space(14)

  function upowerStates() {
    return {
      Charging: UPowerDeviceState.Charging,
      Discharging: UPowerDeviceState.Discharging,
      FullyCharged: UPowerDeviceState.FullyCharged,
      PendingCharge: UPowerDeviceState.PendingCharge
    }
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

  // ---------- Thermal mode and fan boost ----------

  function setThermalProfile(name) {
    if (thermal === null || name === thermal.profile) return
    dellRun(["profile", name])
  }

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

  IpcHandler {
    target: "henri.power"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function togglePercentage() { root.togglePercentage() }
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
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
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
            fontFamily: button ? button.fontFamily : Style.font.family
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
    kind: "popover"
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && root.batteryPresent
    focusTarget: keyCatcher
    padding: Style.space(14)
    contentWidth: panel.fittedContentWidth(root.panelWidth + padding * 2)
    // Follows the column, whose Collapse sections glide with the smooth spring.
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    // Every open starts on the overview: fold "Advanced" back once the popup
    // is fully gone, without animating it.
    onVisibleChanged: {
      if (visible) return
      root.advancedOpen = false
      advancedCollapse.snap()
    }

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      // ↓ / ⏎ / Space open "Advanced"; there ←/→ walk the power profiles,
      // ⏎ applies the one under the cursor, ↑ folds the section again.
      onMoveRequested: function(dx, dy) {
        if (!root.advancedOpen) {
          if (dy > 0) root.advancedOpen = true
          return
        }
        if (dx !== 0) {
          if (!root.cursorActive) { root.cursorActive = true; return }
          root.selectProfileByDelta(dx)
        } else if (dy < 0) {
          root.cursorActive = false
          root.advancedOpen = false
        }
      }
      onActivateRequested: {
        if (!root.advancedOpen) root.advancedOpen = true
        else if (root.cursorActive) root.activateSelectedProfile()
        else root.advancedOpen = false
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
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
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.weight: Font.DemiBold
            }

            HUi.CrossfadeText {
              width: parent.width
              text: root.heroStatusText
              color: root.dimText
              elide: Text.ElideRight
              fontSize: Style.font.bodySmall
            }
          }

          HUi.CrossfadeText {
            id: heroPercent
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: root.pctText
            color: root.fg
            fontSize: Style.font.display
            fontWeight: Font.DemiBold
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
            color: Color.urgent
            wrapMode: Text.WordWrap
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
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

        // ---------- Advanced disclosure ----------
        Item { width: 1; height: Style.space(12) }
        Rectangle { width: parent.width; height: 1; color: root.hairline }
        Item { width: 1; height: Style.space(6) }

        Item {
          width: parent.width
          height: Style.space(Motion.controlHeight)

          HUi.Pressable {
            id: advancedRow
            // Hover fill reaches a little past the text, like a macOS row.
            x: -Style.space(6)
            width: parent.width + Style.space(12)
            height: parent.height
            radius: Style.space(Motion.radiusRow)
            tint: root.fg
            pressScaleEnabled: false
            activeFocusOnTab: false
            onClicked: {
              root.cursorActive = false
              root.advancedOpen = !root.advancedOpen
            }

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: "Advanced"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.weight: Font.Medium
            }

            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "󰅂"
              rotation: root.advancedOpen ? 90 : 0
              color: root.dimText
              font.family: root.iconFont
              font.pixelSize: Style.font.icon
              Behavior on rotation {
                NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
              }
            }
          }
        }

        HUi.Collapse {
          id: advancedCollapse
          width: parent.width
          expanded: root.advancedOpen

          Column {
            width: parent.width
            spacing: 0

            // ---------- Power profile ----------
            HUi.Collapse {
              width: parent.width
              expanded: root.profiles.length > 0
              Column {
                width: parent.width
                topPadding: Style.space(8)
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

            // ---------- Thermal mode (firmware modes power-profiles-daemon cannot reach) ----------
            HUi.Collapse {
              width: parent.width
              expanded: root.thermalReady
              Column {
                width: parent.width
                topPadding: root.blockGap
                spacing: Style.space(6)
                SectionLabel { text: root.brand + " thermal mode" }
                Segmented {
                  width: parent.width
                  options: root.thermalModes
                  labels: root.thermalModes.map(function (m) { return Model.thermalLabel(String(m)) })
                  columns: options.length <= 4 ? options.length : (options.length > 6 ? 4 : 3)
                  current: root.thermal !== null ? root.thermal.profile : ""
                  busy: root.dellBusy
                  onPicked: function(value) { root.setThermalProfile(value) }
                }
                Caption { text: root.thermal !== null ? Model.thermalTip(String(root.thermal.profile)) : "" }
              }
            }

            // ---------- Fans and temperatures ----------
            HUi.Collapse {
              width: parent.width
              expanded: root.sensorsReady
              Column {
                width: parent.width
                topPadding: root.blockGap
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

                HUi.Collapse {
                  width: parent.width
                  expanded: root.fanBoostAvailable && root.thermalModes.indexOf("custom") >= 0
                    && root.thermal !== null && root.thermal.profile !== "custom"
                  Caption { text: "Pick Custom above to set the fan boost." }
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
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                    }
                    Caption { text: "Keeps the USB-A port powered while the laptop sleeps" }
                  }

                  HUi.Toggle {
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
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
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
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
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
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideMiddle
                    text: root.setupCopied ? "Copied — paste it in a terminal" : root.setupCommand
                    color: root.fg
                    fontSize: Style.font.caption
                  }
                }
              }
            }

            Item { width: 1; height: Style.space(4) }
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
      color: Util.alpha(Color.accent, 0.22)
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
        color: chargeBar.low ? Color.urgent : root.fg
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
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
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
    color: Color.accent
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

  // Overview tile: small secondary label over the value.
  component StatTile: Rectangle {
    id: stat
    property string label: ""
    property string value: ""
    implicitHeight: statCol.implicitHeight + Style.space(16)
    radius: Style.space(Motion.radiusControl)
    color: root.wash

    Column {
      id: statCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      HUi.CrossfadeText {
        width: parent.width
        text: stat.label
        color: root.dimText
        elide: Text.ElideRight
        fontSize: Style.font.caption
      }
      HUi.CrossfadeText {
        width: parent.width
        text: stat.value
        color: root.fg
        elide: Text.ElideRight
        fontSize: Style.font.body
        fontWeight: Font.DemiBold
      }
    }
  }

  // Small-caps heading of an Advanced section (same as the Control Center).
  component SectionLabel: Text {
    color: root.dimText
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.6
  }

  // Secondary one-liner under a control (what the selected mode does).
  component Caption: HUi.CrossfadeText {
    width: parent.width
    color: root.dimText
    elide: Text.ElideRight
    fontSize: Style.font.caption
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
    readonly property int labelSize: columns > 4 ? Style.font.caption : Style.font.bodySmall

    implicitHeight: segGrid.implicitHeight + inset * 2
    opacity: busy ? Motion.disabledOpacity : 1
    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }

    Rectangle {
      anchors.fill: parent
      radius: Style.space(Motion.radiusControl)
      color: root.wash
    }

    Item {
      anchors.fill: parent
      anchors.margins: seg.inset

      HUi.Highlight {
        glide: true
        radius: Style.space(Motion.radiusControl) - seg.inset
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
            radius: Style.space(Motion.radiusControl) - seg.inset
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
              color: cell.isCurrent ? Motion.onColor(Color.accent) : root.fg
              font.family: Style.font.family
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
              border.color: Util.alpha(Color.accent, 0.6)
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
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
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
      id: fanRpm
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(66)
      horizontalAlignment: Text.AlignRight
      text: fanRow.fan && fanRow.fan.rpm !== null ? fanRow.fan.rpm + " rpm" : "—"
      color: root.fg
      fontSize: Style.font.bodySmall
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

    Column {
      id: tempBox
      anchors.centerIn: parent
      width: parent.width - Style.space(8)
      spacing: Style.space(1)

      HUi.CrossfadeText {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: tempTile.reading ? tempTile.reading.c + "°" : "—"
        color: tempTile.hot ? Color.urgent : root.fg
        fontSize: Style.font.bodySmall
        fontWeight: Font.DemiBold
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: tempTile.reading ? tempTile.reading.label : ""
        color: root.dimText
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
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
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
      Text {
        anchors.right: parent.right
        text: (boostSlider.dragging ? Math.round(boostSlider.liveValue) : Model.boostPercent(boostBox.boost)) + " %"
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }

    PanelSlider {
      id: boostSlider
      width: parent.width
      bar: root.bar
      minimum: 0
      maximum: 100
      step: 5
      integer: true
      value: Model.boostPercent(boostBox.boost)
      fillColor: root.fg
      knobColor: root.fg
      trackColor: root.trackColor
      tickColor: "transparent"
      enabled: !root.dellBusy
      onReleased: function(v) { root.setFanBoost(boostBox.group, v) }
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
        font.pixelSize: Style.font.title
      }

      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: node.title
        color: root.dimText
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      // Value, plus a chevron that reveals the breakdown.
      Item {
        width: parent.width
        height: Math.max(nodeValue.implicitHeight, node.collapsible ? Style.space(Motion.controlMin) : 0)

        HUi.CrossfadeText {
          id: nodeValue
          anchors.verticalCenter: parent.verticalCenter
          x: node.collapsible ? (parent.width - width - chevron.width) / 2 : (parent.width - width) / 2
          width: implicitWidth
          text: node.value
          color: root.fg
          fontSize: Style.font.bodySmall
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
            text: "󰅂"
            rotation: node.expanded ? 90 : 0
            color: root.dimText
            font.family: root.iconFont
            font.pixelSize: Style.font.caption
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
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
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
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Text {
                anchors.right: parent.right
                textFormat: Text.PlainText
                text: modelData.value
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
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
