import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import qs.Commons
import "Display.js" as Display
import "Network.js" as Net
import "AirPods.js" as Pods
import "file:///home/henri/.local/share/velum/qml/Velum"

// Control Center v3 — the backend, taken over from henri.control-center-v2
// (Panel.qml:76-873) without its UI: Wi-Fi (Quickshell.Networking, 802.1X via
// system/henri-wifi-eap, link stats/DNS/band), Bluetooth, sound (Pipewire +
// pactl port availability, AirPods via librepods), brightness and displays
// (omarchy-monitor-state), keyboard backlight, AirDrop
// (LocalSend), tiling layout, hardware and low-power rendering. New in v3:
// Do Not Disturb and Night Shift (shell services), battery and power profile
// (UPower). The UI sets `opened` and `page`; scanning and polling follow.
Item {
  id: root
  property var shell: null
  property bool opened: false
  signal closeRequested()

  function kvParse(text) {
    var out = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var eq = lines[i].indexOf("=")
      if (eq > 0) out[lines[i].substring(0, eq)] = lines[i].substring(eq + 1)
    }
    return out
  }
  property var renderPower: ({})
  readonly property bool renderPowerOn: renderPower.state === "on"
  readonly property bool noEffectsOn: renderPower.effects === "off"


  // ---- Wi-Fi
  readonly property var wifiDevice: {
    var devices = Networking.devices ? Networking.devices.values : []
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (!d || d.type !== DeviceType.Wifi) continue
      if (d.connected) return d
      if (!fallback) fallback = d
    }
    return fallback
  }
  readonly property string wifiName: {
    if (!wifiDevice || !wifiDevice.networks) return ""
    var nets = wifiDevice.networks.values
    for (var i = 0; i < nets.length; i++) if (nets[i] && nets[i].connected) return nets[i].name
    return ""
  }
  readonly property bool wifiOn: Networking.wifiEnabled

  // ---- Bluetooth
  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property bool btOn: btAdapter ? btAdapter.enabled : false
  readonly property var btConnected: {
    var list = []
    var devices = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < devices.length; i++) if (devices[i] && devices[i].connected) list.push(devices[i])
    return list
  }

  // The UI says which page is shown; scanning and polling only run there.
  property string page: "main"
  onPageChanged: {
    if (page === "sound" && !sinkPortProc.running) sinkPortProc.running = true
    if (page === "sound" && !sourcePortProc.running) sourcePortProc.running = true
  }

  readonly property bool wifiScanning: opened && page === "wifi" && wifiOn
  property var scannerDevice: null
  onWifiScanningChanged: syncScanner()
  onWifiDeviceChanged: syncScanner()
  function syncScanner() {
    var next = wifiScanning ? wifiDevice : null
    if (scannerDevice && scannerDevice !== next) scannerDevice.scannerEnabled = false
    scannerDevice = next
    if (scannerDevice) scannerDevice.scannerEnabled = true
  }
  readonly property var wifiRows: {
    var rows = []
    var seen = {}
    var nets = wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
    for (var i = 0; i < nets.length; i++) {
      var n = nets[i]
      if (!n || !n.name || seen[n.name]) continue
      seen[n.name] = true
      rows.push({
        name: n.name,
        connected: !!n.connected,
        known: !!n.known,
        signal: Math.round((n.signalStrength || 0) * 100),
        secure: n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe,
        enterprise: n.security === WifiSecurityType.Wpa2Eap || n.security === WifiSecurityType.WpaEap
          || n.security === WifiSecurityType.Wpa3SuiteB192
      })
    }
    rows.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      if (a.known !== b.known) return a.known ? -1 : 1
      return b.signal - a.signal
    })
    return rows
  }
  property string wifiPending: ""
  property string wifiPasswordFor: ""
  property var wifiRowsFrozen: []
  onWifiPasswordForChanged: if (wifiPasswordFor !== "") wifiRowsFrozen = wifiRows
  readonly property var wifiRowsShown: wifiPasswordFor !== "" ? wifiRowsFrozen : wifiRows
  property string wifiFailed: ""

  function wifiNetwork(name) {
    var nets = wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
    for (var i = 0; i < nets.length; i++) if (nets[i] && nets[i].name === name) return nets[i]
    return null
  }
  function wifiActivate(row) {
    var net = wifiNetwork(row.name)
    if (!net) return
    var retryCredentials = row.enterprise && wifiFailed === row.name
    wifiFailed = ""
    if (row.connected) {
      markWifiPending(row.name)
      net.disconnect()
    } else if (row.secure && (!row.known || retryCredentials)) {
      wifiPasswordFor = wifiPasswordFor === row.name ? "" : row.name
      return
    } else {
      markWifiPending(row.name)
      net.connect()
    }
    wifiPendingTimeout.restart()
  }
  function wifiConnectWithPassword(name, password) {
    var net = wifiNetwork(name)
    if (!net || password === "") return
    wifiPasswordFor = ""
    wifiFailed = ""
    markWifiPending(name)
    net.connectWithPsk(password)
    wifiPendingTimeout.restart()
  }
  readonly property string wifiEapPath: String(Qt.resolvedUrl("system/henri-wifi-eap")).replace(/^file:\/\//, "")
  property string wifiEapRequest: ""
  property string wifiIdentity: ""
  property int wifiShakeTick: 0
  function wifiConnectEnterprise(name, identity, password) {
    if (identity === "" || password === "" || eapProc.running) return
    wifiIdentity = identity
    wifiPasswordFor = ""
    wifiFailed = ""
    markWifiPending(name)
    wifiEapRequest = JSON.stringify({ ssid: name, identity: identity, password: password })
    eapProc.running = true
  }
  Process {
    id: eapProc
    property string ssid: ""
    command: [root.wifiEapPath]
    stdinEnabled: true
    onStarted: {
      ssid = root.wifiPending
      write(root.wifiEapRequest + "\n")
      root.wifiEapRequest = ""
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      stdinEnabled = true
      if (root.wifiPending === ssid) root.wifiPending = ""
      if (exitCode !== 0) {
        root.wifiFailed = ssid
        if (root.opened && root.page === "wifi") {
          root.wifiPasswordFor = ssid
          root.wifiShakeTick++
        }
      }
    }
  }
  property bool wifiPendingStartedConnected: false
  onWifiRowsChanged: {
    if (wifiPending === "") return
    for (var i = 0; i < wifiRows.length; i++) {
      if (wifiRows[i].name === wifiPending && wifiRows[i].connected !== wifiPendingStartedConnected) {
        wifiPending = ""
        wifiPendingTimeout.stop()
        return
      }
    }
  }
  function markWifiPending(name) {
    var net = wifiNetwork(name)
    wifiPendingStartedConnected = net ? !!net.connected : false
    wifiPending = name
  }
  Timer {
    id: wifiPendingTimeout
    interval: 20000
    onTriggered: {
      var net = root.wifiNetwork(root.wifiPending)
      if (net && !net.connected && !root.wifiPendingStartedConnected) root.wifiFailed = root.wifiPending
      root.wifiPending = ""
    }
  }

  // ---- Wi-Fi advanced options: live link stats, band and DNS
  property bool wifiAdvanced: false
  readonly property bool netPolling: opened && page === "wifi" && wifiAdvanced
  property var netInfo: ({})
  property real netPrevRx: 0
  property real netPrevTx: 0
  property real netPrevTime: 0
  property string netPrevIface: ""
  property real netDownRate: 0
  property real netUpRate: 0
  property var routerPings: []
  property var internetPings: []
  property string dnsProvider: ""
  property string dnsPending: ""
  property var bandInfo: ({ band: "", selected: "auto", available: [] })
  property string bandPending: ""
  readonly property bool netConnected: !!netInfo.iface

  onNetPollingChanged: if (netPolling) {
    netPrevTime = 0
    routerPings = []
    internetPings = []
    pollNetwork(true)
  }
  function pollNetwork(all) {
    if (!netDetailsProc.running) netDetailsProc.running = true
    if (all && !dnsProc.running) dnsProc.running = true
    if (all && !bandProc.running) bandProc.running = true
  }
  function updateNetDetails(raw) {
    var next = Net.parseKeyValue(raw)
    if (bandPending !== "" && !next.iface) return
    var now = Date.now() / 1000
    var rx = parseFloat(next.rx_bytes || "0")
    var tx = parseFloat(next.tx_bytes || "0")
    if ((next.iface || "") !== netPrevIface || netPrevTime === 0) {
      netDownRate = 0
      netUpRate = 0
      routerPings = []
      internetPings = []
    } else if (now > netPrevTime) {
      netDownRate = Math.max(0, (rx - netPrevRx) / (now - netPrevTime))
      netUpRate = Math.max(0, (tx - netPrevTx) / (now - netPrevTime))
    }
    netPrevIface = next.iface || ""
    netPrevRx = rx
    netPrevTx = tx
    netPrevTime = now
    if (next.router_ping_ms !== undefined) routerPings = Net.appendSample(routerPings, next.router_ping_ms, 24)
    if (next.internet_ping_ms !== undefined) internetPings = Net.appendSample(internetPings, next.internet_ping_ms, 24)
    netInfo = next
  }
  function setDns(provider) {
    if (provider === dnsProvider && provider !== "Custom") return
    if (provider === "Custom") {
      root.closeRequested()
      Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-dns Custom"])
      return
    }
    dnsPending = provider
    netActionProc.command = ["omarchy-dns", provider]
    netActionProc.running = true
  }
  function setBand(band) {
    if (band === bandInfo.selected || netActionProc.running) return
    bandPending = band
    netActionProc.command = ["omarchy-network-band", band]
    netActionProc.running = true
  }
  function summonOverlay(pluginId, payload) {
    root.closeRequested()
    overlayDelay.pluginId = pluginId
    overlayDelay.payload = JSON.stringify(payload)
    overlayDelay.restart()
  }
  Timer {
    id: overlayDelay
    property string pluginId: ""
    property string payload: "{}"
    interval: 180
    onTriggered: if (root.shell) root.shell.summon(pluginId, payload)
  }
  Timer {
    interval: 1500
    repeat: true
    running: root.netPolling
    onTriggered: root.pollNetwork(false)
  }
  Process {
    id: netDetailsProc
    command: ["omarchy-network-status", "--verbose"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.updateNetDetails(text) }
  }
  Process {
    id: dnsProc
    command: ["omarchy-dns"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.dnsProvider = String(text || "").trim() || "DHCP"
        root.dnsPending = ""
      }
    }
  }
  Process {
    id: bandProc
    command: ["omarchy-network-band"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var kv = Net.parseKeyValue(text)
        var available = String(kv.available || "").split(" ").filter(function(t) { return t !== "" })
        if (root.bandPending !== "" && available.length === 0) return
        root.bandInfo = { band: kv.band || "", selected: kv.selected || "auto", available: available }
      }
    }
  }
  Process {
    id: netActionProc
    onExited: {
      root.bandPending = ""
      if (!dnsProc.running) dnsProc.running = true
      if (!bandProc.running) bandProc.running = true
    }
  }

  // ---- Bluetooth rows
  readonly property bool btDiscovering: opened && page === "bluetooth" && btOn
  onBtDiscoveringChanged: if (btAdapter) btAdapter.discovering = btDiscovering
  readonly property var btRows: {
    var rows = []
    var devices = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (!d || !d.address) continue
      var name = d.name || d.deviceName || ""
      if (name === "" || name.replace(/-/g, ":") === d.address) continue
      rows.push({
        address: d.address,
        name: name,
        icon: String(d.icon || ""),
        connected: !!d.connected,
        paired: !!(d.paired || d.bonded || d.trusted),
        battery: d.batteryAvailable ? Math.round((d.battery || 0) * 100) : -1
      })
    }
    rows.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      if (a.paired !== b.paired) return a.paired ? -1 : 1
      return a.name.localeCompare(b.name)
    })
    return rows
  }
  property var btPending: ({})
  function btActivate(row) {
    var action = row.connected ? "disconnect" : row.paired ? "connect" : "pair"
    var next = Object.assign({}, btPending)
    next[row.address] = row.connected ? "Disconnecting …" : "Connecting …"
    btPending = next
    Quickshell.execDetached(["omarchy-bluetooth-device", action, row.address])
    btPendingClear.restart()
  }
  onBtRowsChanged: {
    var changed = false
    var next = Object.assign({}, btPending)
    for (var i = 0; i < btRows.length; i++) {
      var r = btRows[i]
      var p = next[r.address]
      if (p && ((p === "Connecting …" && r.connected) || (p === "Disconnecting …" && !r.connected))) {
        delete next[r.address]
        changed = true
      }
    }
    if (changed) btPending = next
  }
  Timer {
    id: btPendingClear
    interval: 20000
    onTriggered: root.btPending = ({})
  }
  // ---- Sound outputs and inputs (pactl tells which are actually plugged)
  function unplugged(text) {
    var gone = ({})
    try {
      var list = JSON.parse(String(text || "[]"))
      for (var i = 0; i < list.length; i++) {
        var ports = list[i].ports || []
        if (ports.length === 0) continue
        var reachable = false
        for (var j = 0; j < ports.length; j++) {
          if (String(ports[j].availability || "") !== "not available") reachable = true
        }
        if (!reachable) gone[list[i].name] = true
      }
    } catch (e) {}
    return gone
  }
  property var unavailableSinks: ({})
  Process {
    id: sinkPortProc
    command: ["pactl", "-f", "json", "list", "sinks"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.unavailableSinks = root.unplugged(text)
    }
  }
  property var unavailableSources: ({})
  Process {
    id: sourcePortProc
    command: ["pactl", "-f", "json", "list", "sources"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.unavailableSources = root.unplugged(text)
    }
  }
  readonly property var sinkRows: {
    var rows = []
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isSink || n.isStream || !n.audio) continue
      if (n.name === "easyeffects_sink") continue
      if (unavailableSinks[n.name] && !(sink !== null && n.id === sink.id)) continue
      var props = n.properties || {}
      rows.push({
        id: n.id,
        name: n.name || "",
        label: n.nickname || props["node.nick"] || n.description || n.name || "Output",
        active: sink !== null && n.id === sink.id
      })
    }
    return rows
  }
  function setSink(row) {
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i] && nodes[i].id === row.id) {
        Pipewire.preferredDefaultAudioSink = nodes[i]
        Quickshell.execDetached(["omarchy-audio-output-set-default", String(row.id), row.name])
        return
      }
    }
  }
  readonly property var source: Pipewire.defaultAudioSource
  // inputs: every audio node that is no sink and no stream (Easy Effects' own stays: it is the
  // processed microphone); the tablet's microphone while a tablet casts (ipadcast)
  readonly property var sourceRows: {
    var rows = []
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || n.isSink || n.isStream || !n.audio) continue
      var props = n.properties || {}
      if (unavailableSources[n.name] && !(source !== null && n.id === source.id)) continue
      rows.push({
        id: n.id,
        name: n.name || "",
        label: n.name === "easyeffects_source" ? "Easy Effects"
          : (n.nickname || props["node.nick"] || n.description || n.name || "Input"),
        active: source !== null && n.id === source.id
      })
    }
    return rows
  }
  // only the default: streams that follow it move with it, Easy Effects' own capture stays put
  function setSource(row) {
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i] && nodes[i].id === row.id) {
        Pipewire.preferredDefaultAudioSource = nodes[i]
        Quickshell.execDetached(["pactl", "set-default-source", row.name])
        return
      }
    }
  }
  function sourceIconName(row) {
    var l = String(row.label + " " + row.name).toLowerCase()
    if (l.indexOf("tablet") >= 0) return "tablet"
    if (l.indexOf("headset") >= 0 || l.indexOf("head") >= 0) return "headphones"
    return "mic"
  }

  // Velum icon names for a device (UI picks these)
  function btIconName(icon) {
    var i = String(icon || "")
    if (i.indexOf("headset") >= 0 || i.indexOf("headphone") >= 0) return "headphones"
    if (i.indexOf("audio") >= 0 || i.indexOf("speaker") >= 0) return "speaker"
    if (i.indexOf("mouse") >= 0) return "mouse"
    if (i.indexOf("keyboard") >= 0) return "keyboard"
    if (i.indexOf("computer") >= 0) return "desktop"
    return "bluetooth"
  }
  function sinkIconName(label) {
    var l = String(label).toLowerCase()
    if (l.indexOf("hdmi") >= 0 || l.indexOf("displayport") >= 0) return "display"
    if (l.indexOf("head") >= 0 || l.indexOf("kopfh") >= 0) return "headphones"
    return "speaker"
  }

  // ---- Hardware (system/henri-hwstat, 2 s while open)
  readonly property string hwStatPath: String(Qt.resolvedUrl("system/henri-hwstat")).replace(/^file:\/\//, "")
  property var hw: ({ temp: -1, fans: [], freqAvg: 0, freqPeak: 0, freqMax: 0, threads: 0, cores: 0, model: "",
                      load1: 0, memTotal: 0, memAvail: 0, swapTotal: 0, swapFree: 0, diskTotal: 0, diskUsed: 0, uptime: 0 })
  property var hwPrev: null
  property int cpuLoad: -1
  readonly property real memUsedFrac: hw.memTotal > 0 ? 1 - hw.memAvail / hw.memTotal : 0
  readonly property real swapUsedFrac: hw.swapTotal > 0 ? 1 - hw.swapFree / hw.swapTotal : 0
  readonly property real diskUsedFrac: hw.diskTotal > 0 ? hw.diskUsed / hw.diskTotal : 0
  readonly property string hwSummary: {
    var parts = []
    if (cpuLoad >= 0) parts.push("CPU " + cpuLoad + " %")
    if (hw.memTotal > 0) parts.push("RAM " + formatGiB(hw.memTotal - hw.memAvail, 1) + " / " + formatGiB(hw.memTotal, 0) + " GB")
    if (hw.temp >= 0) parts.push(hw.temp + " °C")
    return parts.join(" · ")
  }
  function formatGiB(kib, digits) { return (kib / 1048576).toFixed(digits) }
  function formatBytesGB(bytes) { return Math.round(bytes / 1e9) + " GB" }
  function formatGHz(mhz) { return mhz > 0 ? (mhz / 1000).toFixed(2) + " GHz" : "--" }
  function formatUptime(s) {
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), mi = Math.floor(s % 3600 / 60)
    return d > 0 ? d + " d " + h + " h" : h > 0 ? h + " h " + mi + " min" : mi + " min"
  }
  function refreshHardware() { if (!hwStatProc.running) hwStatProc.running = true }
  function applyHwStat(raw) {
    var s
    try { s = JSON.parse(String(raw || "").trim()) } catch (e) { return }
    // the very first sample has nothing to compare with: take the second one soon, not a poll later
    if (!hwPrev && root.opened) hwSecond.restart()
    if (hwPrev && s.cpuTotal > hwPrev.cpuTotal) {
      var dt = s.cpuTotal - hwPrev.cpuTotal
      cpuLoad = Math.max(0, Math.min(100, Math.round(100 * (1 - (s.cpuIdle - hwPrev.cpuIdle) / dt))))
    }
    hwPrev = { cpuTotal: s.cpuTotal, cpuIdle: s.cpuIdle }
    hw = s
    if (cpuLoad >= 0) cpuHistory = cpuHistory.concat([cpuLoad / 100]).slice(-cpuHistoryLength)
  }
  // the last minute of CPU load (0 … 1, one sample per poll) for the live chart on the Hardware page
  readonly property int hwInterval: 2000
  readonly property int cpuHistoryLength: 31
  property var cpuHistory: []
  Process {
    id: hwStatProc
    command: [root.hwStatPath]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyHwStat(text) }
  }
  Timer { interval: Theme.delay("settle"); running: root.opened; onTriggered: root.refreshHardware() }
  Timer { id: hwSecond; interval: Theme.delay("loading"); onTriggered: root.refreshHardware() }
  Timer { interval: root.hwInterval; repeat: true; running: root.opened; onTriggered: root.refreshHardware() }

  // ---- Top processes (system/henri-topcpu, on the Hardware page): the programs using the most CPU,
  // summed per name, in percent of the whole CPU; a program with a desktop entry shows its name and icon
  readonly property string topCpuPath: String(Qt.resolvedUrl("system/henri-topcpu")).replace(/^file:\/\//, "")
  readonly property bool topPolling: opened && page === "hardware"
  property var topProcs: []
  property var appInfoCache: ({})
  onTopPollingChanged: if (topPolling) { topProcs = []; if (!topCpuProc.running) topCpuProc.running = true }
  Timer { interval: root.hwInterval; repeat: true; running: root.topPolling; onTriggered: if (!topCpuProc.running) topCpuProc.running = true }
  Process {
    id: topCpuProc
    command: [root.topCpuPath, "5"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: {
      var o; try { o = JSON.parse(String(text || "").trim()) } catch (e) { return }
      // the first call only takes a sample: keep the rows until a real one comes
      if (o.procs.length) root.topProcs = o.procs.map(p => Object.assign({}, p, root.appInfo(p.name)))
    } }
  }
  // a desktop entry for a process name, only when it really is that app (heuristicLookup guesses wide)
  function appInfo(name) {
    if (appInfoCache[name] !== undefined) return appInfoCache[name]
    var n = String(name).toLowerCase(), e = null
    try { e = DesktopEntries.byId(name) || DesktopEntries.byId(n) || DesktopEntries.heuristicLookup(name) } catch (err) {}
    if (e && !(String(e.id).toLowerCase().indexOf(n) >= 0 || String(e.startupClass || "").toLowerCase() === n || String(e.name).toLowerCase() === n)) e = null
    var path = ""
    if (e && e.icon) { try { path = Quickshell.iconPath(e.icon, true) } catch (err2) {} }
    var info = { label: e && e.name ? e.name : name, iconPath: path || "" }
    var c = Object.assign({}, appInfoCache); c[name] = info; appInfoCache = c
    return info
  }
  function openActivityMonitor() { root.closeRequested(); run("omarchy-launch-or-focus-tui btop") }

  // ---- Low-power rendering (Experiments)
  readonly property string renderPowerPath: String(Qt.resolvedUrl("system/henri-render-power")).replace(/^file:\/\//, "")
  function refreshRenderPower() { if (!renderPowerProc.running) renderPowerProc.running = true }
  function setRenderPower(on) {
    if (renderPowerSetProc.running) return
    renderPowerSetProc.command = [root.renderPowerPath, on ? "on" : "off"]
    renderPowerSetProc.running = true
  }
  function setNoEffects(on) {
    if (renderPowerSetProc.running) return
    renderPowerSetProc.command = [root.renderPowerPath, "effects", on ? "on" : "off"]
    renderPowerSetProc.running = true
  }
  Process {
    id: renderPowerProc
    command: [root.renderPowerPath, "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.renderPower = root.kvParse(text) }
  }
  Process {
    id: renderPowerSetProc
    onExited: root.refreshRenderPower()
  }
  Timer { interval: Theme.delay("settle"); running: root.opened; onTriggered: root.refreshRenderPower() }

  // ---- Services owned by the shell
  function service(id) {
    return shell && typeof shell.firstPartyServiceFor === "function"
      ? shell.firstPartyServiceFor(id) : null
  }

  // ---- AirPods (librepods daemon)
  AirPodsService { id: pods }
  readonly property var podService: pods
  readonly property bool airpodsActive: pods.hasAirPods
  readonly property string airpodsName: pods.modelName !== "" ? pods.modelName
    : pods.deviceName !== "" ? pods.deviceName : "AirPods"
  readonly property string airpodsVariant: pods.isHeadset ? "max" : pods.isProSeries ? "pro" : "buds"
  readonly property var airpodsModes: pods.availableModes()
  readonly property var airpodsBatteries: pods.isHeadset
    ? [{ label: "Headphones", level: pods.headsetBattery.level, charging: pods.headsetBattery.charging }]
    : [{ label: "Left", level: pods.leftPod.level, charging: pods.leftPod.charging },
       { label: "Right", level: pods.rightPod.level, charging: pods.rightPod.charging },
       { label: "Case", level: pods.caseBattery.level, charging: pods.caseBattery.charging }]
  readonly property int airpodsLevel: {
    var levels = pods.isHeadset ? [pods.headsetBattery.level] : [pods.leftPod.level, pods.rightPod.level]
    var known = levels.filter(function(l) { return l !== Pods.LEVEL_UNKNOWN })
    return known.length ? Math.min.apply(null, known) : -1
  }
  onAirpodsActiveChanged: if (!airpodsActive && page === "airpods") page = "main"

  // ---- Sound
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }
  function setVolume(v) {
    if (!sink || !sink.audio) return
    sink.audio.volume = Math.max(0, Math.min(1, v))
    if (muted && v > 0) sink.audio.muted = false
  }
  function toggleMute() { if (sink && sink.audio) sink.audio.muted = !muted }
  readonly property string volumeIcon: volume < 0.34 || muted ? "sound.low" : "sound"

  // ---- Display brightness
  property int brightness: 0
  property bool brightnessAvailable: false
  property string internalMonitor: ""
  property int queuedBrightness: -1
  // While a tablet casts the Mac (mac-cast through ipadcast) its panel follows this machine's
  // backlight, so the slider shows and moves that backlight even with no internal panel.
  // ipadcast sends "osd cast on|off" (repeated every few seconds while connected).
  property bool cast: false
  property string castBacklight: ""
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "custom") return
      var d = String(event.data)
      if (d === "osd cast on" || d === "osd cast off") {
        var on = d === "osd cast on"
        if (on !== root.cast) { root.cast = on; if (root.opened) root.refresh() }
      }
    }
  }
  Process {
    id: castBrightProc
    command: ["brightnessctl", "-m", "-c", "backlight"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var f = String(text || "").trim().split("\n")[0].split(",")
        if (!root.cast || f.length < 5) return
        root.castBacklight = f[0]
        root.brightnessAvailable = true
        root.brightness = Math.max(1, Math.min(100, parseInt(f[3], 10) || 0))
      }
    }
  }

  // ---- Keyboard backlight (henri.kbdlight service: level + turn-off delay).
  //      Since omarchy 4.0.6 a plugin gets no other plugin's service object, so
  //      `kbd` is a stand-in with the service's interface: it reads the state the
  //      service writes to $XDG_RUNTIME_DIR/henri-kbdlight-<instance>.json and
  //      sends changes as the Hyprland events `kbdlight set|timeout …`.
  //      Without the file (service off, no backlight) `kbd` is null.
  property var kbd: kbdState.available === true ? kbdProxy : null
  property var kbdState: ({})
  FileView {
    id: kbdFile
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/henri-kbdlight-" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + ".json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.kbdState = JSON.parse(text()) } catch (e) {} }
    onLoadFailed: root.kbdState = ({})
  }
  QtObject {
    id: kbdProxy
    readonly property bool available: root.kbdState.available === true
    readonly property bool binary: root.kbdState.binary === true
    // set at once on a change (the slider follows the finger), then corrected by the file
    property real level: typeof root.kbdState.level === "number" ? root.kbdState.level : 0
    readonly property int timeout: typeof root.kbdState.timeout === "number" ? root.kbdState.timeout : 0
    readonly property var timeoutChoices: root.kbdState.timeoutChoices || []
    function setLevel(v) { level = binary ? (v > 0 ? 1 : 0) : Math.max(0, Math.min(1, v)); root.kbdEvent("set " + level) }
    function setTimeoutSeconds(s) { root.kbdEvent("timeout " + Math.max(0, Math.round(s))) }
  }
  Connections { target: root; function onKbdStateChanged() { if (typeof root.kbdState.level === "number") kbdProxy.level = root.kbdState.level } }
  function kbdEvent(cmd) {
    Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.event(\"kbdlight " + cmd + "\")" : "event kbdlight " + cmd)
  }
  readonly property bool kbdAvailable: kbd !== null && kbd.available === true
  readonly property bool kbdBinary: kbdAvailable && kbd.binary === true
  function kbdTimeoutLabel(s) { return s === 0 ? "Never" : s < 60 ? s + " s" : (s / 60) + " min" }

  // ---- Display settings: text size, scale presets, monitors
  property string focusedMonitor: ""
  property string monitorScale: ""
  property var displays: []
  property bool displayExpanded: false
  readonly property var focusedDisplay: {
    for (var i = 0; i < displays.length; i++) if (displays[i] && displays[i].focused) return displays[i]
    return displays.length ? displays[0] : null
  }
  readonly property var scalePresets: focusedDisplay
    ? Display.availableScales(["1", "1.25", "1.6", "2", "3", "4"], focusedDisplay.width, focusedDisplay.height)
    : []
  readonly property int enabledDisplayCount: {
    var n = 0
    for (var i = 0; i < displays.length; i++) if (displays[i] && displays[i].enabled) n++
    return n
  }
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  property int textSizePreviewIndex: -1
  readonly property int textSizeIndex: {
    if (textSizePreviewIndex >= 0) return textSizePreviewIndex
    var best = 0
    for (var i = 0; i < textSizeStops.length; i++)
      if (Math.abs(textSizeStops[i] - Style.font.baseSize) < Math.abs(textSizeStops[best] - Style.font.baseSize)) best = i
    return best
  }

  // ---- Tiling layout (dwindle / scrolling). Read from the active workspace;
  //      set from here for EVERY workspace (Henri: the Control Center choice is
  //      global), persisted per workspace the way omarchy's own toggle does it
  //      (~/.local/state/omarchy/workspace-layouts/<id>.lua, loaded at start).
  property string tilingLayout: ""
  function setTilingLayout(layout) {
    if (layout === tilingLayout) return
    tilingLayout = layout
    actionProc.command = ["bash", "-c",
      'L="$1"; D="$HOME/.local/state/omarchy/workspace-layouts"; mkdir -p "$D"; '
      + 'for id in $( { hyprctl workspaces -j | jq -r ".[].id"; seq 1 10; } | grep -E "^[0-9]+$" | sort -un ); do '
      + 'printf \'hl.workspace_rule({ workspace = "%s", layout = "%s" })\\n\' "$id" "$L" > "$D/$id.lua"; '
      + 'hyprctl eval "hl.workspace_rule({ workspace = \\"$id\\", layout = \\"$L\\" })" >/dev/null 2>&1; done',
      "_", layout]
    if (!actionProc.running) actionProc.running = true
  }

  // ---- Rotation lock (hypr-autorotate, the tablet): offered where the panel
  //      has an accelerometer and the watcher is installed. Locked = the panel
  //      keeps the orientation it has now (the watcher skips while the lock file exists).
  //      While a tablet casts this machine, the lock is ipadcast's: the cast desktop
  //      stops following the tablet's turns while $XDG_RUNTIME_DIR/ipadcast/rotation-lock exists.
  property bool rotationAvailable: false
  property bool rotationLocked: false
  function setRotationLocked(on) {
    rotationLocked = on
    if (cast) run((on ? "touch" : "rm -f") + ' "$XDG_RUNTIME_DIR/ipadcast/rotation-lock"')
    else run("hypr-autorotate " + (on ? "lock" : "unlock"))
  }
  Process {
    id: rotationProc
    command: ["bash", "-c", root.cast
      ? '[[ -e "$XDG_RUNTIME_DIR/ipadcast/rotation-lock" ]] && echo locked || echo unlocked'
      : 'command -v hypr-autorotate >/dev/null || exit 0; '
      + 'for d in /sys/bus/iio/devices/iio:device*; do [[ $(cat "$d/name" 2>/dev/null) == accel_3d ]] && { hypr-autorotate status; exit; }; done']
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var st = String(text || "").trim()
        root.rotationAvailable = st !== ""
        root.rotationLocked = st === "locked"
      }
    }
  }

  // ---- AirDrop stand-in: LocalSend
  property bool localsendRunning: false
  function run(cmd) { Quickshell.execDetached(["bash", "-c", cmd]) }

  function setBrightness(value) {
    var percent = Math.max(1, Math.min(100, Math.round(value)))
    brightness = percent
    if (brightnessProc.running) { queuedBrightness = percent; return }
    queuedBrightness = -1
    brightnessProc.command = cast && castBacklight !== ""
      ? ["brightnessctl", "-q", "-d", castBacklight, "set", percent + "%"]
      : ["omarchy-brightness-display", "--no-osd", "--monitor", internalMonitor, percent + "%"]
    brightnessProc.running = true
  }
  function refresh() {
    kbdFile.reload()   // the service may have written its file after this panel loaded
    if (!stateProc.running) stateProc.running = true
    if (!sinkPortProc.running) sinkPortProc.running = true
    if (!sourcePortProc.running) sourcePortProc.running = true
    if (!localsendProc.running) localsendProc.running = true
    if (!tilingProc.running) tilingProc.running = true
    if (!rotationProc.running) rotationProc.running = true
  }
  function setScale(scale) {
    monitorScale = Display.cleanScale(scale, focusedDisplay.width, focusedDisplay.height)
    actionProc.command = ["omarchy-hyprland-monitor-scaling", String(scale)]
    if (!actionProc.running) actionProc.running = true
  }
  function setTextSizeIndex(index) {
    var i = Math.max(0, Math.min(textSizeStops.length - 1, Math.round(index)))
    if (i === textSizeIndex) return
    textSizePreviewIndex = i
    textSizeProc.command = ["omarchy-display-text-size", String(textSizeStops[i])]
    if (!textSizeProc.running) textSizeProc.running = true
  }
  function toggleDisplay(display) {
    if (!display || !display.name) return
    if (display.enabled && enabledDisplayCount <= 1) return
    actionProc.command = ["hyprctl", "keyword", "monitor",
      display.name + (display.enabled ? ",disable" : ",preferred,auto,auto")]
    if (!actionProc.running) actionProc.running = true
  }

  function toggleWifi() { Networking.wifiEnabled = !Networking.wifiEnabled }
  function toggleBluetooth() { Quickshell.execDetached(["omarchy-bluetooth-power", root.btOn ? "off" : "on"]) }
  function toggleAirdrop() {
    if (localsendRunning) { run("pkill -x localsend"); localsendRunning = false }
    else { run("setsid -f localsend >/dev/null 2>&1"); localsendRunning = true }
  }
  function openAirdrop() { root.closeRequested(); run("omarchy-launch-or-focus localsend 'setsid -f localsend'") }
  function openWifiQr() {
    summonOverlay("omarchy.wifiqr", netInfo.iface ? { iface: netInfo.iface, ssid: netInfo.ssid || "" } : {})
  }
  function openSpeedTest() {
    summonOverlay("omarchy.speedtest", netInfo.type === "wifi" ? { connection: netInfo.ssid || "Wi-Fi" } : {})
  }

  onOpenedChanged: {
    if (opened) {
      refresh()
      pods.refresh()
      if (!netDetailsProc.running) netDetailsProc.running = true
    } else {
      displayExpanded = false
      page = "main"
      wifiPasswordFor = ""
      wifiAdvanced = false
    }
  }

  Process {
    id: stateProc
    command: ["omarchy-monitor-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var b = String(lines[0] || "").trim()
        root.brightnessAvailable = b !== "" && b !== "unavailable"
        if (root.brightnessAvailable) root.brightness = Math.max(0, Math.min(100, parseInt(b, 10)))
        root.internalMonitor = String(lines[1] || "").trim()
        root.focusedMonitor = String(lines[5] || "").trim()
        root.monitorScale = Display.normalizeScale(String(lines[6] || "").trim())
        root.displays = Display.parseDisplays(String(lines[7] || "[]").trim())
        if (root.cast && !castBrightProc.running) castBrightProc.running = true
      }
    }
  }
  Process {
    id: brightnessProc
    onExited: if (root.queuedBrightness >= 0) root.setBrightness(root.queuedBrightness)
  }
  Process { id: actionProc; onExited: root.refresh() }
  Process { id: textSizeProc; onExited: textSizeSettle.restart() }
  Timer { id: textSizeSettle; interval: 600; onTriggered: root.textSizePreviewIndex = -1 }
  Process {
    id: localsendProc
    command: ["pgrep", "-x", "localsend"]
    onExited: function(code) { root.localsendRunning = code === 0 }
  }
  Process {
    id: tilingProc
    command: ["hyprctl", "activeworkspace", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.tilingLayout = JSON.parse(text).tiledLayout || "" } catch (e) {} }
    }
  }


  // ---- New in v3: Do Not Disturb, Night Shift (shell services), battery + power profile (UPower)
  readonly property var notifService: shell ? (service("henri.notifications-v3") || service("omarchy.notifications") || service("henri.notifications")) : null
  readonly property bool dnd: notifService ? notifService.doNotDisturb === true : false
  function setDnd(on) { if (notifService && typeof notifService.setDoNotDisturb === "function") notifService.setDoNotDisturb(on) }
  readonly property var nightService: shell ? service("omarchy.nightlight") : null
  readonly property bool nightShift: nightService ? nightService.enabled === true : false
  function setNightShift(on) { if (nightService && typeof nightService.setNightlight === "function") nightService.setNightlight(on) }
  readonly property var battery: UPower.displayDevice
  readonly property bool hasBattery: battery !== null && battery.isLaptopBattery === true
  readonly property real batteryLevel: battery ? battery.percentage : 0     // 0 … 1
  readonly property bool charging: battery ? battery.state === UPowerDeviceState.Charging : false
  readonly property bool onAC: UPower.onBattery === false
  readonly property string batteryTime: {
    if (!battery) return ""
    var s = charging ? battery.timeToFull : battery.timeToEmpty
    if (!s || s <= 0) return ""
    var h = Math.floor(s / 3600), m = Math.round(s % 3600 / 60)
    return h + ":" + (m < 10 ? "0" : "") + m + (charging ? " until full" : " left")
  }
  readonly property int powerProfile: PowerProfiles.profile === PowerProfile.PowerSaver ? 0 : PowerProfiles.profile === PowerProfile.Performance ? 2 : 1
  function setPowerProfile(i) { PowerProfiles.profile = [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance][i] }
}
