import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "Display.js" as Display
import "Network.js" as Net
import "AirPods.js" as Pods
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

// macOS-style Control Center. Everything here drives the same backends the
// stock panels use (Quickshell.Networking, Bluetooth, Pipewire, the shell's
// notification/nightlight/idle/media services, omarchy-brightness-display),
// so state stays in sync with the bar icons and the detail panels. Clicking a
// tile's round icon toggles it; clicking its label opens the stock detail
// panel, like the chevron in macOS.
Panel {
  id: root
  moduleName: "henri.control-center"
  ipcTarget: "henri.control-center"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var shell: bar ? bar.shell : null

  // ---- Palette. Tiles are a faint wash of the foreground over the popup
  //      background; an "on" icon circle takes the accent colour.
  readonly property color fg: Color.popups.text
  readonly property color tileColor: Qt.rgba(fg.r, fg.g, fg.b, 0.07)
  readonly property color tileHover: Qt.rgba(fg.r, fg.g, fg.b, 0.11)
  readonly property color circleOff: Qt.rgba(fg.r, fg.g, fg.b, 0.14)
  readonly property color circleOn: Color.accent
  // Glyphs/text on the accent fill: white or black by contrast (henri-ui).
  readonly property color onIcon: Motion.onColor(circleOn)
  // Secondary text: foreground at the henri-ui secondary alpha (not a darkened fg / muted).
  readonly property color dimText: Util.alpha(fg, Motion.secondaryTextAlpha)
  readonly property string iconFont: bar ? bar.fontFamily : Style.font.family
  // SF Symbols (local font only, not in the repo). Bluetooth has no SF symbol → Nerd glyph via fallback.
  readonly property string symbolFont: ".SF Symbols Fallback"
  function sf(cp) { return String.fromCodePoint(cp) }
  readonly property int tileRadius: Style.space(Motion.radiusPopover)
  readonly property int gap: Style.space(10)
  readonly property int panelWidth: Style.space(340)
  readonly property int colWidth: Math.floor((panelWidth - gap) / 2)

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

  // ---- Detail pages. Like macOS, a tile's label swaps the grid for a list
  //      inside the same popup ("main" | "wifi" | "bluetooth" | "sound" | "hardware").
  property string page: "main"
  function showPage(name) { page = name }

  // ---- Motion. `detailPage` keeps the last detail page mounted while it
  //      slides out, `revealed` drives the staggered tile entrance on open,
  //      and `pageShownAt` lets list rows animate in only right after a page
  //      change (not on every scan update that rebuilds the list).
  property string detailPage: "wifi"
  property double pageShownAt: 0
  property bool revealed: false
  property bool heightAnimated: false
  onPageChanged: {
    if (page !== "main") detailPage = page
    pageShownAt = Date.now()
  }
  function rowDelay(index) {
    // Only rows built while the drill-in transition runs cascade in.
    return Date.now() - pageShownAt < Motion.slow ? Motion.stagger(index) : -1
  }

  // Wi-Fi rows are primitive snapshots, never WifiNetwork objects: NM churn
  // can destroy a network while a delegate still holds it (see the stock
  // network panel). Actions look the object up by name at click time.
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
        // 802.1X: asks for username + password instead of a single key.
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
    // A saved enterprise profile that just failed most likely has stale
    // credentials: ask for them again instead of retrying the same ones.
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
  // WPA/WPA2-Enterprise: Quickshell only speaks PSK, so a helper creates the
  // 802.1X profile over D-Bus. Credentials go through stdin, never argv.
  readonly property string wifiEapPath: String(Qt.resolvedUrl("system/henri-wifi-eap")).replace(/^file:\/\//, "")
  property string wifiEapRequest: ""
  property string wifiIdentity: ""
  // Bumped on a rejected login so the credential fields shake once.
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
        // Reopen the fields (username kept) so a typo is a quick fix.
        if (root.opened && root.page === "wifi") {
          root.wifiPasswordFor = ssid
          root.wifiShakeTick++
        }
      }
    }
  }
  function wifiIcon(signal) {
    return sf(0x100647)
  }
  // The pending row settles once its connected state flips.
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

  // ---- Wi-Fi advanced options: live link stats, band and DNS, polled only
  //      while that section is expanded (the status script pings twice).
  property bool wifiAdvanced: false
  // Main page: Tiling, Hardware and Plugins live in a folded "Advanced" section.
  property bool advancedOpen: false
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
    // A band switch drops the link for a moment; keep the last good sample.
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
      // Custom servers are typed in a terminal prompt.
      close()
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
    close()
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
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateNetDetails(text)
    }
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

  // Bluetooth rows, same primitive-snapshot rule as Wi-Fi.
  readonly property bool btDiscovering: opened && page === "bluetooth" && btOn
  onBtDiscoveringChanged: if (btAdapter) btAdapter.discovering = btDiscovering
  readonly property var btRows: {
    var rows = []
    var devices = Bluetooth.devices ? Bluetooth.devices.values : []
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (!d || !d.address) continue
      var name = d.name || d.deviceName || ""
      // Unnamed discoveries show up as their MAC address; skip them.
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
  function btIcon(icon) {
    if (icon.indexOf("headset") >= 0 || icon.indexOf("headphone") >= 0) return sf(0x100448)
    if (icon.indexOf("audio") >= 0 || icon.indexOf("speaker") >= 0) return sf(0x10074E)
    if (icon.indexOf("mouse") >= 0) return sf(0x100EA4)
    if (icon.indexOf("keyboard") >= 0) return sf(0x100A33)
    if (icon.indexOf("phone") >= 0) return sf(0x1007DD)
    if (icon.indexOf("computer") >= 0) return sf(0x100657)
    if (icon.indexOf("gaming") >= 0 || icon.indexOf("joystick") >= 0) return sf(0x1006F8)
    return "󰂯"
  }

  // Sound outputs.
  readonly property var sinkRows: {
    var rows = []
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isSink || n.isStream || !n.audio) continue
      if (n.name === "easyeffects_sink") continue
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
  function sinkIcon(label) {
    var l = String(label).toLowerCase()
    if (l.indexOf("hdmi") >= 0 || l.indexOf("displayport") >= 0) return sf(0x1008B9)
    if (l.indexOf("head") >= 0 || l.indexOf("kopfh") >= 0) return sf(0x100448)
    return sf(0x10074E)
  }

  // ---- Hardware: read-only live readings from system/henri-hwstat (CPU load,
  //      clock, temperature, fans, memory, disk). Load is the idle delta
  //      between two consecutive samples.
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
    var d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60)
    return d > 0 ? d + " d " + h + " h" : h > 0 ? h + " h " + m + " min" : m + " min"
  }
  function tempColor(t) {
    return t >= 80 ? Color.urgent : root.fg
  }
  function refreshHardware() {
    if (!hwStatProc.running) hwStatProc.running = true
  }
  function applyHwStat(raw) {
    var s
    try { s = JSON.parse(String(raw || "").trim()) } catch (e) { return }
    if (hwPrev && s.cpuTotal > hwPrev.cpuTotal) {
      var dt = s.cpuTotal - hwPrev.cpuTotal
      cpuLoad = Math.max(0, Math.min(100, Math.round(100 * (1 - (s.cpuIdle - hwPrev.cpuIdle) / dt))))
    }
    hwPrev = { cpuTotal: s.cpuTotal, cpuIdle: s.cpuIdle }
    hw = s
  }

  Process {
    id: hwStatProc
    command: [root.hwStatPath]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyHwStat(text)
    }
  }
  // The summary sits on the main page now, so the first sample must not fork a
  // process into the opening animation (henri-ui §5) — the tile shows the values
  // from the last time the panel was open until the settled sample arrives.
  Timer {
    interval: Motion.settleDelay
    running: root.opened
    onTriggered: root.refreshHardware()
  }
  Timer {
    interval: 2000
    repeat: true
    running: root.opened
    onTriggered: root.refreshHardware()
  }

  // ---- Services owned by the shell
  // Plugins only get narrow first-party proxies now (serviceFor is limited to
  // the caller's own services); omarchy.idle resolves to the henri.idle clone.
  function service(id) {
    return shell && typeof shell.firstPartyServiceFor === "function"
      ? shell.firstPartyServiceFor(id) : null
  }
  readonly property var notifications: opened ? service("omarchy.notifications") : null
  readonly property var nightlight: opened ? service("omarchy.nightlight") : null
  readonly property var idle: opened ? service("omarchy.idle") : null
  readonly property var media: opened ? service("omarchy.media") : null
  readonly property var player: media ? media.activePlayer : null

  readonly property bool dnd: notifications ? notifications.doNotDisturb : false
  readonly property bool nightOn: nightlight ? nightlight.enabled : false
  readonly property bool stayAwake: idle ? idle.stayAwake : false

  // ---- AirPods, through the librepods daemon (AirPodsService.qml). While
  //      they are connected the Sound tile becomes theirs and drills into
  //      the "airpods" page with battery, listening mode and pod settings.
  AirPodsService { id: pods }
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
  // Lowest bud (or headset) level for the Sound tile, like the macOS menu.
  readonly property int airpodsLevel: {
    var levels = pods.isHeadset ? [pods.headsetBattery.level] : [pods.leftPod.level, pods.rightPod.level]
    var known = levels.filter(function(l) { return l !== Pods.LEVEL_UNKNOWN })
    return known.length ? Math.min.apply(null, known) : -1
  }
  function noiseModeIcon(mode) {
    if (mode === Pods.NOISE_ANC) return sf(0xF0A45)          // md ear-hearing-off
    if (mode === Pods.NOISE_TRANSPARENCY) return sf(0xF07C5) // md ear-hearing
    if (mode === Pods.NOISE_ADAPTIVE) return sf(0xF00E1)     // md brightness-auto
    return sf(0xF1852)                                        // md earbuds-outline
  }
  onAirpodsActiveChanged: if (!airpodsActive && page === "airpods") page = "main"

  // ---- Sound
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property real volume: sink && sink.audio ? sink.audio.volume : 0
  readonly property bool muted: sink && sink.audio ? sink.audio.muted : false
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }

  // ---- Display brightness (polled on open; set through the Omarchy CLI so
  //      the stock display panel and keyboard keys agree with us).
  property int brightness: 0
  property bool brightnessAvailable: false
  property string internalMonitor: ""
  property int queuedBrightness: -1

  // ---- Display settings (the stock omarchy.monitor panel, folded in):
  //      text size, scale presets for the focused display, and on/off per
  //      monitor when more than one is connected.
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
  // Same notches as the stock panel; the CLI takes any px in 9–20.
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  property int textSizePreviewIndex: -1
  readonly property int textSizeIndex: {
    if (textSizePreviewIndex >= 0) return textSizePreviewIndex
    var best = 0
    for (var i = 0; i < textSizeStops.length; i++)
      if (Math.abs(textSizeStops[i] - Style.font.baseSize) < Math.abs(textSizeStops[best] - Style.font.baseSize)) best = i
    return best
  }

  // ---- Tiling layout of the active workspace (dwindle / scrolling)
  property string tilingLayout: ""

  // Omarchy's toggle flips dwindle <-> scrolling and persists it per
  // workspace, so only call it when the target isn't already active.
  function setTilingLayout(layout) {
    if (layout === tilingLayout) return
    tilingLayout = layout
    actionProc.command = ["bash", "-c",
      "[ \"$(hyprctl activeworkspace -j | jq -r .tiledLayout)\" = \"$1\" ] || omarchy-hyprland-workspace-layout-toggle",
      "_", layout]
    if (!actionProc.running) actionProc.running = true
  }

  // ---- AirDrop stand-in: LocalSend
  property bool localsendRunning: false

  function run(cmd) { Quickshell.execDetached(["bash", "-c", cmd]) }

  // Hand over to the plugin manager hosted by BarWidget.qml. Wait for our own
  // popup to finish closing so its focus grab is gone before the next opens.
  function openPluginManager() {
    close()
    pluginManagerDelay.restart()
  }
  Timer {
    id: pluginManagerDelay
    interval: 180
    onTriggered: if (root.hostWidget) root.hostWidget.openPluginManager()
  }

  function setBrightness(value) {
    var percent = Math.max(1, Math.min(100, Math.round(value)))
    brightness = percent
    if (brightnessProc.running) { queuedBrightness = percent; return }
    queuedBrightness = -1
    brightnessProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", internalMonitor, percent + "%"]
    brightnessProc.running = true
  }

  function refresh() {
    if (!stateProc.running) stateProc.running = true
    if (!localsendProc.running) localsendProc.running = true
    if (!tilingProc.running) tilingProc.running = true
    if (!experimentalProc.running && !experimentalBusy) experimentalProc.running = true
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

  onOpenedChanged: {
    if (opened) {
      refresh()
      pods.refresh()
      revealTimer.restart()
    } else {
      revealed = false
      heightAnimated = false
      revealTimer.stop()
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
      }
    }
  }

  Process {
    id: brightnessProc
    onExited: if (root.queuedBrightness >= 0) root.setBrightness(root.queuedBrightness)
  }

  Process {
    id: actionProc
    onExited: root.refresh()
  }

  // Style picks the new base size up through its own file watch; drop the
  // preview once it has landed so the slider follows the live value again.
  Process {
    id: textSizeProc
    onExited: textSizeSettle.restart()
  }
  Timer {
    id: textSizeSettle
    interval: 600
    onTriggered: root.textSizePreviewIndex = -1
  }

  Timer {
    id: revealTimer
    interval: 16
    onTriggered: {
      root.revealed = true
      heightReadyTimer.restart()
    }
  }
  Timer {
    id: heightReadyTimer
    interval: 60
    onTriggered: root.heightAnimated = true
  }

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
      onStreamFinished: {
        try { root.tilingLayout = JSON.parse(text).tiledLayout || "" } catch (e) {}
      }
    }
  }

  // ---- Experiments. `henri-ui-experimental` owns the flag on disk; the panel
  // only reads and flips it, so the CLI and this switch can never disagree.
  // The flag lives in henri-ui/Experimental.js, which henri-ui-sync watches:
  // a second or two after the switch it restarts the shell and this panel goes
  // with it. That restart is what makes the new tokens take hold.
  property bool experimentalOn: false
  property bool experimentalBusy: false

  function setExperimental(on) {
    if (experimentalBusy) return
    experimentalBusy = true
    experimentalSetProc.command = ["henri-ui-experimental", on ? "on" : "off"]
    experimentalSetProc.running = true
  }

  Process {
    id: experimentalProc
    command: ["henri-ui-experimental", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.experimentalOn = String(text || "").trim() === "on"
    }
  }

  Process {
    id: experimentalSetProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.experimentalOn = String(text || "").trim() === "on"
    }
    onExited: root.experimentalBusy = false
  }

  // ======================================================== components

  // Round icon button. `on` fills it with the accent colour.
  component Circle: Rectangle {
    id: circle
    property string icon: ""
    property bool on: false
    signal clicked()
    width: Style.space(30)
    height: width
    radius: width / 2
    color: on ? root.circleOn : root.circleOff
    Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }

    // Press feedback: scale to Motion.pressScale, released with the snappy spring.
    scale: circlePress.value
    HUi.SpringValue {
      id: circlePress
      preset: Motion.snappy
      to: circleMouse.pressed && !Motion.reduceMotion ? Motion.pressScale : 1
    }

    // Subtle pop when the state flips: snap slightly in, snappy spring back
    // to 1 (snappy: under 1 % past the target). Independent of the press scale above.
    transform: Scale {
      origin.x: circle.width / 2
      origin.y: circle.height / 2
      xScale: circlePop.value
      yScale: circlePop.value
    }
    HUi.SpringValue { id: circlePop; preset: Motion.snappy; to: 1 }
    onOnChanged: if (root.revealed) circlePop.snap(Motion.pressScale)

    // Hover/press wash over the fill (replaces the old hover grow).
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      color: Util.alpha(root.fg, circleMouse.pressed ? Motion.pressedAlpha : circleMouse.containsMouse ? Motion.hoverAlpha : 0)
      Behavior on color {
        ColorAnimation {
          duration: circleMouse.containsMouse || circleMouse.pressed ? Motion.instant : Motion.fast
          easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
        }
      }
    }

    // Icon swaps crossfade.
    HUi.CrossfadeText {
      id: circleIcon
      anchors.centerIn: parent
      horizontalAlignment: Text.AlignHCenter
      text: circle.icon
      fontFamily: root.symbolFont
      fontSize: Style.font.iconLarge
      color: circle.on ? root.onIcon : root.fg
      Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    }
    MouseArea {
      id: circleMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: circle.clicked()
    }
  }

  component Tile: Rectangle {
    id: tile
    property bool hoverable: false
    // Position in the entrance cascade; -1 opts out.
    property int revealIndex: -1
    signal clicked()
    radius: root.tileRadius
    color: hoverable && tileMouse.containsMouse ? root.tileHover : root.tileColor
    Behavior on color {
      ColorAnimation {
        duration: tile.hoverable && tileMouse.containsMouse ? Motion.instant : Motion.fast
        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
      }
    }

    // Entrance cascade on open (Motion.stagger: 15 ms steps, max 10); the
    // exit is immediate because the whole popup fades out together.
    readonly property bool shown: revealIndex < 0 || root.revealed
    readonly property int revealDelay: Motion.stagger(revealIndex)
    property real enterScale: shown || Motion.reduceMotion ? 1 : Motion.popoverFromScale
    opacity: shown ? 1 : 0
    scale: enterScale * tilePress.value
    transform: Translate {
      id: tileShift
      y: tile.shown || Motion.reduceMotion ? 0 : -Style.space(10)
      Behavior on y {
        SequentialAnimation {
          PauseAnimation { duration: tile.shown ? tile.revealDelay : 0 }
          NumberAnimation { duration: tile.shown ? Motion.slow : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
        }
      }
    }
    Behavior on opacity {
      SequentialAnimation {
        PauseAnimation { duration: tile.shown ? tile.revealDelay : 0 }
        NumberAnimation { duration: tile.shown ? Motion.base : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
      }
    }
    Behavior on enterScale {
      SequentialAnimation {
        PauseAnimation { duration: tile.shown ? tile.revealDelay : 0 }
        NumberAnimation { duration: tile.shown ? Motion.slow : 0; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
      }
    }
    // Press feedback (hoverable tiles only), released with the snappy spring.
    HUi.SpringValue {
      id: tilePress
      preset: Motion.snappy
      to: tile.hoverable && tileMouse.pressed && !Motion.reduceMotion ? Motion.pressScale : 1
    }
    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: tile.hoverable
      cursorShape: tile.hoverable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: tile.clicked()
    }
  }

  // Icon + two lines of text, used inside the connectivity tile and Focus.
  component ToggleRow: Item {
    id: row
    property string icon: ""
    property bool on: false
    property string title: ""
    property string subtitle: ""
    signal toggled()
    signal details()
    implicitHeight: Style.space(38)

    Circle {
      id: rowCircle
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      icon: row.icon
      on: row.on
      onClicked: row.toggled()
    }
    Column {
      anchors.left: rowCircle.right
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0
      Text {
        width: parent.width
        text: row.title
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: row.subtitle
        visible: text !== ""
        color: root.dimText
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
    MouseArea {
      anchors.fill: parent
      anchors.leftMargin: rowCircle.width + Style.space(4)
      cursorShape: Qt.PointingHandCursor
      onClicked: row.details()
    }
  }

  // Small square tile: centred icon circle with a caption underneath.
  component SmallTile: Tile {
    id: small
    property string icon: ""
    property bool on: false
    property string title: ""
    hoverable: true
    width: Math.floor((root.colWidth - root.gap) / 2)
    height: Style.space(82)

    Column {
      anchors.centerIn: parent
      width: parent.width - Style.space(8)
      spacing: Style.space(5)
      Circle {
        anchors.horizontalCenter: parent.horizontalCenter
        icon: small.icon
        on: small.on
        onClicked: small.clicked()
      }
      Text {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: small.title
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        maximumLineCount: 2
      }
    }
  }

  // Wide tile with a heading and a slider, like Display / Sound on macOS.
  // With `expandable`, the heading gets a chevron and toggles `expanded`,
  // which reveals whatever children are placed inside the tile.
  component SliderTile: Tile {
    id: st
    property string heading: ""
    property string icon: ""
    property real value: 0
    property bool expandable: false
    property bool expanded: false
    property string headingDetail: ""
    property Component headingGlyph: null
    default property alias extra: extraColumn.data
    signal moved(real value)
    signal iconClicked()
    signal headingClicked()
    width: root.panelWidth
    height: stColumn.implicitHeight + Style.space(15)
    clip: true
    Behavior on height {
      enabled: root.heightAnimated
      NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
    }

    Column {
      id: stColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.topMargin: Style.space(9)
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(14)
      spacing: Style.space(4)

      Item {
        width: parent.width
        height: stHeading.implicitHeight

        Loader {
          id: stGlyph
          anchors.verticalCenter: stHeading.verticalCenter
          active: st.headingGlyph !== null
          sourceComponent: st.headingGlyph
          width: active ? Style.space(20) : 0
        }
        HUi.CrossfadeText {
          id: stHeading
          anchors.left: stGlyph.right
          text: st.heading
          color: root.fg
          fontSize: Style.font.subtitle
          fontWeight: Font.DemiBold
        }
        HUi.CrossfadeText {
          anchors.right: stChevron.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: stHeading.verticalCenter
          horizontalAlignment: Text.AlignRight
          text: st.headingDetail
          color: root.dimText
          fontSize: Style.font.bodySmall
        }
        Text {
          id: stChevron
          visible: st.expandable
          anchors.right: parent.right
          anchors.verticalCenter: stHeading.verticalCenter
          text: root.sf(0x10018A)
          rotation: st.expanded ? 90 : 0
          color: root.dimText
          font.family: root.symbolFont
          font.pixelSize: Style.font.icon
          Behavior on rotation { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: st.headingClicked()
        }
      }

      Item {
        width: parent.width
        height: stSlider.implicitHeight

        HUi.CrossfadeText {
          id: stIcon
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(20)
          text: st.icon
          color: root.fg
          fontFamily: root.symbolFont
          fontSize: Style.font.iconLarge
          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            cursorShape: Qt.PointingHandCursor
            onClicked: st.iconClicked()
          }
        }
        PanelSlider {
          id: stSlider
          anchors.left: stIcon.right
          anchors.right: parent.right
          anchors.leftMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          bar: root.bar
          minimum: 0
          maximum: 1
          step: 0.05
          value: st.value
          fillColor: root.fg
          knobColor: root.fg
          trackColor: root.circleOff
          tickColor: "transparent"
          onMoved: function(v) { st.moved(v) }
        }
      }

      Column {
        id: extraColumn
        width: parent.width
        visible: st.expanded
        opacity: st.expanded ? 1 : 0
        transform: Translate {
          y: st.expanded || Motion.reduceMotion ? 0 : -Style.space(8)
          Behavior on y { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        }
        Behavior on opacity {
          NumberAnimation {
            duration: st.expanded ? Motion.base : Motion.exit(Motion.fast)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: st.expanded ? Motion.easeOut : Motion.easeExit
          }
        }
        spacing: Style.space(8)
        topPadding: Style.space(4)
      }
    }
  }

  // Small caps section label inside an expanded tile.
  component SectionLabel: Text {
    color: root.dimText
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.6
  }

  // Pill button used for the scale presets.
  component Pill: Rectangle {
    id: pill
    property string label: ""
    property bool selected: false
    signal clicked()
    height: Style.space(26)
    radius: height / 2
    color: selected ? root.circleOn : pillMouse.containsMouse ? root.tileHover : root.circleOff
    Behavior on color {
      ColorAnimation {
        duration: pillMouse.containsMouse ? Motion.instant : Motion.fast
        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
      }
    }
    scale: pillPress.value
    HUi.SpringValue {
      id: pillPress
      preset: Motion.snappy
      to: pillMouse.pressed && !Motion.reduceMotion ? Motion.pressScale : 1
    }
    property string symbol: ""
    property color ink: pill.selected ? root.onIcon : root.fg
    Behavior on ink { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    Row {
      anchors.centerIn: parent
      spacing: Style.space(6)
      // SF Symbol, tinted like the label.
      Text {
        visible: pill.symbol !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: pill.symbol
        color: pill.ink
        font.family: root.symbolFont
        font.pixelSize: Style.font.bodySmall
        font.weight: pill.selected ? Font.DemiBold : Font.Normal
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pill.label
        color: pill.ink
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.weight: pill.selected ? Font.DemiBold : Font.Normal
      }
    }
    MouseArea {
      id: pillMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: pill.clicked()
    }
  }

  // Header of a detail page: back chevron + title, with an optional switch.
  component PageHeader: Item {
    id: ph
    property string title: ""
    property bool showSwitch: false
    property bool checked: false
    signal toggled()
    width: root.panelWidth
    height: Style.space(36)

    Row {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(6)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.sf(0x100189)
        transform: Translate {
          x: backMouse.containsMouse && !Motion.reduceMotion ? -Style.space(3) : 0
          Behavior on x {
            NumberAnimation {
              duration: backMouse.containsMouse ? Motion.instant : Motion.fast
              easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
            }
          }
        }
        color: root.fg
        font.family: root.symbolFont
        font.pixelSize: Style.font.iconLarge
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ph.title
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.weight: Font.DemiBold
      }
    }
    MouseArea {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: switchTrack.left
      id: backMouse
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.page = "main"
    }

    // macOS-style switch.
    Rectangle {
      id: switchTrack
      visible: ph.showSwitch
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(36)
      height: Style.space(20)
      radius: height / 2
      color: ph.checked ? root.circleOn : root.circleOff
      // henri-ui switch spec: track color crossfades (fast), knob glides with
      // the snappy spring. The knob follows the backend state (no optimistic flip).
      Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      Rectangle {
        width: parent.height - Style.space(4)
        height: width
        radius: width / 2
        y: Style.space(2)
        x: Style.space(2) + knobSpring.value * (parent.width - width - Style.space(4))
        color: ph.checked ? root.onIcon : root.fg
        Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        HUi.SpringValue { id: knobSpring; preset: Motion.snappy; to: ph.checked ? 1 : 0 }
      }
      MouseArea {
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        cursorShape: Qt.PointingHandCursor
        onClicked: ph.toggled()
      }
    }
  }

  // One entry in a detail list: round icon, name + status, optional trailing text.
  component ListRow: Rectangle {
    id: lr
    property string icon: ""
    property bool active: false
    property string title: ""
    property string subtitle: ""
    property string trailing: ""
    property bool busy: false
    property int rowIndex: 0
    signal clicked()
    width: root.panelWidth
    height: Style.space(44)
    radius: Style.space(Motion.radiusRow)
    color: lrMouse.containsMouse ? root.tileColor : Util.alpha(root.tileColor, 0)
    Behavior on color {
      ColorAnimation {
        duration: lrMouse.containsMouse ? Motion.instant : Motion.fast
        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
      }
    }
    scale: lrPress.value
    HUi.SpringValue {
      id: lrPress
      preset: Motion.snappy
      to: lrMouse.pressed && !Motion.reduceMotion ? Motion.pressScale : 1
    }

    // Rows built right after a page change slide in one after another.
    opacity: 1
    transform: Translate { id: lrShift }
    Component.onCompleted: {
      var delay = root.rowDelay(rowIndex)
      if (delay < 0) return
      opacity = 0
      lrShift.x = Motion.reduceMotion ? 0 : Style.space(18)
      lrEnterPause.duration = delay
      lrEnter.start()
    }
    SequentialAnimation {
      id: lrEnter
      PauseAnimation { id: lrEnterPause; duration: 0 }
      ParallelAnimation {
        NumberAnimation { target: lr; property: "opacity"; to: 1; duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
        NumberAnimation { target: lrShift; property: "x"; to: 0; duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
      }
    }

    Rectangle {
      id: lrCircle
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(28)
      height: width
      radius: width / 2
      color: lr.active ? root.circleOn : root.circleOff
      Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      scale: lrActiveScale.value
      HUi.SpringValue { id: lrActiveScale; preset: Motion.snappy; to: lr.active || Motion.reduceMotion ? 1 : 0.94 }
      Text {
        anchors.centerIn: parent
        text: lr.icon
        color: lr.active ? root.onIcon : root.fg
        Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        font.family: root.symbolFont
        font.pixelSize: Style.font.icon
      }
    }
    Column {
      anchors.left: lrCircle.right
      anchors.leftMargin: Style.space(10)
      anchors.right: lrTrailing.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      Text {
        width: parent.width
        text: lr.title
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.weight: lr.active ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        visible: text !== ""
        text: lr.subtitle
        color: root.dimText
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        // Breathe while connecting / disconnecting.
        SequentialAnimation on opacity {
          running: lr.busy
          loops: Animation.Infinite
          onRunningChanged: if (!running) parent.opacity = 1
          NumberAnimation { to: Motion.disabledOpacity; duration: Motion.slower; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut }
          NumberAnimation { to: 1; duration: Motion.slower; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut }
        }
      }
    }
    HUi.CrossfadeText {
      id: lrTrailing
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      text: lr.trailing
      color: root.dimText
      fontFamily: lr.trailing.codePointAt(0) >= 0x100000 ? root.symbolFont : root.iconFont
      fontSize: Style.font.bodySmall
    }
    MouseArea {
      id: lrMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: lr.clicked()
    }
  }

  // Label/value pair in the advanced stats grid.
  component Stat: Item {
    property string label: ""
    property string value: ""
    width: Math.floor((root.panelWidth - Style.space(24)) / 2)
    height: Style.space(20)
    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: parent.label
      color: root.dimText
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
    HUi.CrossfadeText {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      text: parent.value
      color: root.fg
      fontSize: Style.font.bodySmall
    }
  }

  // Usage bar for the Hardware page. The fill slides (transform only) inside
  // a clipped track; a round cap keeps the left end rounded like the track.
  component Meter: Item {
    id: meter
    property real fraction: 0
    property color fillColor: Color.accent
    readonly property real clamped: Math.max(0, Math.min(1, fraction))
    height: Style.space(6)
    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: root.circleOff
    }
    Rectangle {
      width: parent.height
      height: parent.height
      radius: height / 2
      color: meter.fillColor
      opacity: meter.clamped > 0 ? 1 : 0
      Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    }
    Item {
      x: meter.height / 2
      width: parent.width - x
      height: parent.height
      clip: true
      Rectangle {
        width: meter.width
        height: meter.height
        radius: height / 2
        color: meter.fillColor
        x: fillSpring.value - meter.width + meter.height / 2
        Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      }
    }
    HUi.SpringValue {
      id: fillSpring
      to: meter.clamped * (meter.width - meter.height / 2)
      epsilon: 0.5
    }
  }

  // Title + current value above a Meter ("CPU ........ 23 %").
  component UsageHeader: Item {
    property string title: ""
    property string value: ""
    property color valueColor: root.fg
    height: Style.space(24)
    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: parent.title
      color: root.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.weight: Font.DemiBold
    }
    HUi.CrossfadeText {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      text: parent.value
      color: parent.valueColor
      fontSize: Style.font.body
    }
  }

  // Small round action button (QR share, speed test).
  component IconButton: Rectangle {
    id: ib
    property string icon: ""
    property string tip: ""
    signal clicked()
    width: Style.space(30)
    height: width
    radius: width / 2
    color: ibMouse.containsMouse ? root.circleOff : root.tileColor
    Behavior on color {
      ColorAnimation {
        duration: ibMouse.containsMouse ? Motion.instant : Motion.fast
        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
      }
    }
    scale: ibPress.value
    HUi.SpringValue {
      id: ibPress
      preset: Motion.snappy
      to: ibMouse.pressed && !Motion.reduceMotion ? Motion.pressScale : 1
    }
    Text {
      anchors.centerIn: parent
      text: ib.icon
      color: root.fg
      font.family: root.symbolFont
      font.pixelSize: Style.font.icon
    }
    MouseArea {
      id: ibMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: ib.clicked()
    }
  }

  component ListLabel: Text {
    leftPadding: Style.space(6)
    topPadding: Style.space(4)
    color: root.dimText
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.6
  }

  // One-line text field for the inline Wi-Fi credentials. With `submitIcon`
  // it carries the join arrow on the right.
  component CredField: Rectangle {
    id: cf
    property alias input: cfInput
    property alias text: cfInput.text
    property string placeholder: ""
    property bool password: false
    property bool submitIcon: false
    property bool error: false
    property Item nextField: null
    property Item prevField: null
    signal submitted()
    signal cancelled()
    signal edited()
    width: parent ? parent.width : 0
    height: Style.space(32)
    radius: Style.space(Motion.radiusControl)
    color: root.tileColor
    border.width: 1
    border.color: cf.error ? Color.urgent : cfInput.activeFocus ? root.circleOn : root.circleOff
    Behavior on border.color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }

    TextInput {
      id: cfInput
      anchors.fill: parent
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: cf.submitIcon ? Style.space(34) : Style.space(10)
      verticalAlignment: TextInput.AlignVCenter
      echoMode: cf.password ? TextInput.Password : TextInput.Normal
      inputMethodHints: cf.password ? Qt.ImhSensitiveData | Qt.ImhNoPredictiveText : Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
      color: root.fg
      selectionColor: root.circleOn
      selectedTextColor: root.onIcon
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      clip: true
      Keys.onReturnPressed: cf.submitted()
      Keys.onEnterPressed: cf.submitted()
      Keys.onEscapePressed: cf.cancelled()
      onTextEdited: cf.edited()
      KeyNavigation.tab: cf.nextField
      KeyNavigation.backtab: cf.prevField

      Text {
        anchors.verticalCenter: parent.verticalCenter
        opacity: parent.text === "" ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.instant; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        text: cf.placeholder
        color: root.dimText
        font: parent.font
      }
    }
    Text {
      visible: cf.submitIcon
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: root.sf(0x100C13)
      color: cfInput.text === "" ? root.dimText : root.fg
      Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      font.family: root.symbolFont
      font.pixelSize: Style.font.icon
      MouseArea {
        anchors.fill: parent
        anchors.margins: -Style.space(6)
        cursorShape: Qt.PointingHandCursor
        onClicked: cf.submitted()
      }
    }
  }

  component Separator: Rectangle {
    width: root.panelWidth
    height: 1
    color: root.circleOff
  }

  // Volume slider of the default output, with a mute button (Sound + AirPods pages).
  component VolumeRow: Item {
    width: root.panelWidth
    height: Style.space(40)
    HUi.CrossfadeText {
      id: vrIcon
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(20)
      text: root.muted || root.volume === 0 ? root.sf(0x1002A3) : root.sf(0x1002A9)
      color: root.fg
      fontFamily: root.symbolFont
      fontSize: Style.font.iconLarge
      MouseArea {
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.muted
      }
    }
    PanelSlider {
      anchors.left: vrIcon.right
      anchors.right: parent.right
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(14)
      anchors.verticalCenter: parent.verticalCenter
      bar: root.bar
      minimum: 0
      maximum: 1
      step: 0.05
      value: root.muted ? 0 : Math.min(1, root.volume)
      fillColor: root.fg
      knobColor: root.fg
      trackColor: root.circleOff
      tickColor: "transparent"
      onMoved: function(v) {
        if (!root.sink || !root.sink.audio) return
        root.sink.audio.volume = v
        if (root.muted && v > 0) root.sink.audio.muted = false
      }
    }
  }

  // Row with a title, a caption and a switch; the whole row toggles.
  // The switch follows the backend (the binding is restored after a flip).
  component SwitchRow: Rectangle {
    id: sr
    property string title: ""
    property string caption: ""
    property bool checked: false
    signal toggled(bool on)
    width: root.panelWidth
    height: Style.space(48)
    radius: Style.space(Motion.radiusRow)
    color: srMouse.containsMouse ? root.tileColor : Util.alpha(root.tileColor, 0)
    Behavior on color {
      ColorAnimation {
        duration: srMouse.containsMouse ? Motion.instant : Motion.fast
        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
      }
    }
    MouseArea {
      id: srMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: sr.toggled(!sr.checked)
    }
    Column {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.right: srSwitch.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      Text {
        width: parent.width
        text: sr.title
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: sr.caption
        color: root.dimText
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
    HUi.Toggle {
      id: srSwitch
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      checked: sr.checked
      onToggled: function(on) {
        sr.toggled(on)
        srSwitch.checked = Qt.binding(function() { return sr.checked })
      }
    }
  }

  // One battery cell on the AirPods page: level, battery glyph and label.
  component PodBattery: Column {
    id: pb
    property string label: ""
    property int level: -1
    property bool charging: false
    readonly property bool known: level !== Pods.LEVEL_UNKNOWN
    spacing: Style.space(3)
    HUi.CrossfadeText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: pb.known ? pb.level + " %" : "--"
      color: pb.known && pb.level <= 20 && !pb.charging ? Color.urgent : root.fg
      fontSize: Style.font.subtitle
      fontWeight: Font.DemiBold
    }
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(5)
      HUi.BatteryGlyph {
        anchors.verticalCenter: parent.verticalCenter
        visible: pb.known
        height: Style.space(10)
        level: Pods.levelFraction(pb.level)
        charging: pb.charging
        ink: root.fg
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pb.label
        color: root.dimText
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }

  // Outline of the connected AirPods for the Sound tile heading.
  Component {
    id: airpodsGlyph
    AirPodsIcon {
      iconSize: Style.space(15)
      color: root.fg
      variant: root.airpodsVariant
    }
  }

  // Footer link at the bottom of a detail page.
  component FooterLink: Text {
    id: fl
    signal clicked()
    leftPadding: Style.space(6)
    color: flMouse.containsMouse ? root.fg : root.dimText
    Behavior on color {
      ColorAnimation {
        duration: flMouse.containsMouse ? Motion.instant : Motion.fast
        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
      }
    }
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
    MouseArea {
      id: flMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: fl.clicked()
    }
  }

  // ============================================================== layout

  HUi.PopupPanel {
    id: panel
    kind: "panel"
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: root.gap
    contentWidth: root.panelWidth + root.gap * 2
    // Height follows the visible page and glides (smooth spring) once the
    // popup is up; before that it snaps (heightSpring lives in `pages`).
    property real shownHeight: panel.fittedContentHeight(root.page === "main" ? content.implicitHeight : detail.implicitHeight)
    contentHeight: Math.round(heightSpring.value)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.page !== "main") root.page = "main"
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      // ← (or h) goes back from a detail page, like Esc (drill-in flow).
      onMoveRequested: function(dx, dy) { if (dx < 0 && root.page !== "main") root.page = "main" }
    }

    Item {
      id: pages
      anchors.fill: parent
      clip: true

      HUi.SpringValue {
        id: heightSpring
        preset: Motion.smooth
        epsilon: 0.3
        to: panel.shownHeight
        onToChanged: if (!root.heightAnimated) snap(to)
      }

    // Drill-in (henri-ui): the detail page comes in from the right, the main
    // grid moves 30 % left and fades; back mirrors it. Motion.slow, easeInOut.
    Column {
      id: content
      width: root.panelWidth
      spacing: root.gap
      readonly property bool current: root.page === "main"
      visible: opacity > 0.01
      opacity: current ? 1 : 0
      x: current || Motion.reduceMotion ? 0 : -root.panelWidth * Motion.pageParallax
      Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }
      Behavior on x { enabled: root.heightAnimated; NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }

      // Top block: connectivity on the left, Focus + small toggles on the right.
      Row {
        spacing: root.gap

        Tile {
          revealIndex: 0
          width: root.colWidth
          height: connectivity.implicitHeight + Style.space(20)

          Column {
            id: connectivity
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(4)

            ToggleRow {
              width: parent.width
              icon: root.wifiOn ? root.sf(0x100647) : root.sf(0x100648)
              on: root.wifiOn
              title: "Wi-Fi"
              subtitle: !root.wifiOn ? "Off" : (root.wifiName !== "" ? root.wifiName : "Not connected")
              onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
              onDetails: root.showPage("wifi")
            }
            ToggleRow {
              width: parent.width
              icon: root.btOn ? "󰂯" : "󰂲"
              on: root.btOn
              title: "Bluetooth"
              subtitle: !root.btOn ? "Off"
                : root.btConnected.length === 1 ? (root.btConnected[0].name || "1 device")
                : root.btConnected.length > 1 ? root.btConnected.length + " devices"
                : "On"
              // omarchy-bluetooth-power persists the state (see the stock panel).
              onToggled: Quickshell.execDetached(["omarchy-bluetooth-power", root.btOn ? "off" : "on"])
              onDetails: root.showPage("bluetooth")
            }
            ToggleRow {
              width: parent.width
              icon: root.sf(0x100319)
              on: root.localsendRunning
              title: "AirDrop"
              subtitle: root.localsendRunning ? "LocalSend active" : "LocalSend"
              onToggled: {
                if (root.localsendRunning) {
                  root.run("pkill -x localsend")
                  root.localsendRunning = false
                } else {
                  root.run("setsid -f localsend >/dev/null 2>&1")
                  root.localsendRunning = true
                }
              }
              onDetails: { root.close(); root.run("omarchy-launch-or-focus localsend 'setsid -f localsend'") }
            }
          }
        }

        Column {
          spacing: root.gap

          Tile {
            revealIndex: 1
            width: root.colWidth
            height: Style.space(52)
            hoverable: true
            onClicked: if (root.notifications) root.notifications.setDoNotDisturb(!root.dnd)

            ToggleRow {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(6)
              icon: root.sf(0x1001BA)
              on: root.dnd
              title: "Focus"
              subtitle: root.dnd ? "Do Not Disturb" : ""
              onToggled: if (root.notifications) root.notifications.setDoNotDisturb(!root.dnd)
              onDetails: if (root.notifications) root.notifications.setDoNotDisturb(!root.dnd)
            }
          }

          Row {
            spacing: root.gap
            SmallTile {
              revealIndex: 2
              icon: root.sf(0x1001B4)
              on: root.nightOn
              title: "Night Shift"
              onClicked: if (root.nightlight) root.nightlight.setNightlight(!root.nightOn)
            }
            SmallTile {
              revealIndex: 3
              icon: root.sf(0x1017B5)
              on: root.stayAwake
              title: "Stay Awake"
              onClicked: if (root.idle) root.idle.setIdleEnabled(root.stayAwake)
            }
          }
        }
      }

      SliderTile {
        revealIndex: 4
        visible: root.brightnessAvailable || root.displays.length > 0
        heading: "Display"
        icon: root.sf(root.brightness < 40 ? 0x1001AC : 0x1001AE)
        value: root.brightness / 100
        expandable: true
        expanded: root.displayExpanded
        onHeadingClicked: root.displayExpanded = !root.displayExpanded
        onMoved: function(v) { root.setBrightness(v * 100) }

        // ---- Text size
        SectionLabel { text: "Text size · " + root.textSizeStops[root.textSizeIndex] + " px" }
        Item {
          width: parent.width
          height: textSlider.implicitHeight
          Text {
            id: smallA
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(20)
            text: "A"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          PanelSlider {
            id: textSlider
            anchors.left: smallA.right
            anchors.right: bigA.left
            anchors.leftMargin: Style.space(6)
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            bar: root.bar
            minimum: 0
            maximum: root.textSizeStops.length - 1
            step: 1
            integer: true
            tickCount: root.textSizeStops.length
            tickColor: root.tileColor
            value: root.textSizeIndex
            fillColor: root.fg
            knobColor: root.fg
            trackColor: root.circleOff
            onReleased: function(v) { root.setTextSizeIndex(v) }
          }
          Text {
            id: bigA
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "A"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
          }
        }

        // ---- Scale presets for the focused display
        SectionLabel {
          visible: root.focusedDisplay !== null
          text: "Scale" + (root.displays.length > 1 && root.focusedMonitor ? " · " + root.focusedMonitor : "")
                + (root.focusedDisplay && root.monitorScale
                   ? " · looks like " + Display.looksLike(root.monitorScale, root.focusedDisplay.width, root.focusedDisplay.height)
                   : "")
        }
        Row {
          visible: root.focusedDisplay !== null
          width: parent.width
          spacing: Style.space(5)
          Repeater {
            model: root.scalePresets
            delegate: Pill {
              required property string modelData
              width: Math.floor((parent.width - parent.spacing * (root.scalePresets.length - 1)) / Math.max(1, root.scalePresets.length))
              label: Display.formatScale(Display.cleanScale(modelData, root.focusedDisplay.width, root.focusedDisplay.height))
              selected: Display.isActiveScale(modelData, root.monitorScale, root.focusedDisplay.width, root.focusedDisplay.height)
              onClicked: if (!selected) root.setScale(modelData)
            }
          }
        }

        // ---- Monitors (only with more than one)
        SectionLabel {
          visible: root.displays.length > 1
          text: "Monitors"
        }
        Repeater {
          model: root.displays.length > 1 ? root.displays : []
          delegate: Item {
            required property var modelData
            width: parent.width
            height: Style.space(30)
            opacity: modelData.enabled && root.enabledDisplayCount <= 1 ? 0.6 : 1
            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.sf(0x1008B9)
                color: modelData.focused ? root.fg : root.dimText
                font.family: root.symbolFont
                font.pixelSize: Style.font.bodySmall
              }
              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.name + (modelData.width ? "   " + modelData.width + " × " + modelData.height : "")
                color: root.fg
                font.family: root.iconFont
                font.pixelSize: Style.font.bodySmall
              }
            }
            Pill {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(52)
              label: modelData.enabled ? "On" : "Off"
              selected: modelData.enabled
              onClicked: root.toggleDisplay(modelData)
            }
          }
        }

      }

      SliderTile {
        revealIndex: 5
        visible: root.sink !== null
        heading: root.airpodsActive ? root.airpodsName : "Sound"
        headingGlyph: root.airpodsActive ? airpodsGlyph : null
        headingDetail: root.airpodsActive && root.airpodsLevel >= 0 ? root.airpodsLevel + " %" : ""
        expandable: true
        icon: root.muted || root.volume === 0 ? root.sf(0x1002A3) : root.volume < 0.34 ? root.sf(0x1002A5) : root.volume < 0.67 ? root.sf(0x1002A7) : root.sf(0x1002A9)
        value: root.muted ? 0 : Math.min(1, root.volume)
        onMoved: function(v) {
          if (!root.sink || !root.sink.audio) return
          root.sink.audio.volume = v
          if (root.muted && v > 0) root.sink.audio.muted = false
        }
        onIconClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.muted
        onHeadingClicked: root.showPage(root.airpodsActive ? "airpods" : "sound")
      }

      // Now Playing — only while an MPRIS player has a track.
      Tile {
        revealIndex: 6
        id: nowPlaying
        readonly property bool playing: root.player ? root.player.isPlaying === true : false
        visible: root.player !== null
        width: root.panelWidth
        height: Style.space(64)

        Rectangle {
          id: art
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(44)
          height: width
          radius: Style.space(Motion.radiusControl)
          color: root.circleOff
          clip: true

          Text {
            anchors.centerIn: parent
            visible: artImage.status !== Image.Ready
            text: root.sf(0x10046A)
            color: root.dimText
            font.family: root.symbolFont
            font.pixelSize: Style.font.iconLarge
          }
          Image {
            id: artImage
            anchors.fill: parent
            source: root.player ? (root.player.trackArtUrl || "") : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: width * 2
            sourceSize.height: height * 2
          }
        }

        Column {
          anchors.left: art.right
          anchors.leftMargin: Style.space(10)
          anchors.right: controls.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          Text {
            width: parent.width
            text: root.player ? (root.player.trackTitle || "") : ""
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: root.player ? (root.player.trackArtist || root.player.identity || "") : ""
            color: root.dimText
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }

        Row {
          id: controls
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)

          Repeater {
            model: [
              { icon: root.sf(0x10028A), action: "previous" },
              { icon: nowPlaying.playing ? root.sf(0x100286) : root.sf(0x100284), action: "playPause" },
              { icon: root.sf(0x10028C), action: "next" }
            ]
            delegate: Rectangle {
              required property var modelData
              width: Style.space(30)
              height: width
              radius: width / 2
              color: controlMouse.containsMouse ? root.circleOff : Util.alpha(root.circleOff, 0)
              Behavior on color {
                ColorAnimation {
                  duration: controlMouse.containsMouse ? Motion.instant : Motion.fast
                  easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
                }
              }
              Text {
                anchors.centerIn: parent
                text: modelData.icon
                color: root.fg
                font.family: root.symbolFont
                font.pixelSize: Style.font.iconLarge
              }
              MouseArea {
                id: controlMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.media) root.media.runAction(modelData.action, false)
              }
            }
          }
        }
      }

      // Hardware: CPU load, memory and temperature at a glance.
      Tile {
        revealIndex: 7
        width: root.panelWidth
        height: Style.space(52)
        hoverable: true
        onClicked: root.showPage("hardware")

        Circle {
          id: hwCircle
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          icon: root.sf(0x1009D3)
          onClicked: root.showPage("hardware")
        }
        Column {
          anchors.left: hwCircle.right
          anchors.leftMargin: Style.space(8)
          anchors.right: hwChevron.left
          anchors.verticalCenter: parent.verticalCenter
          Text {
            width: parent.width
            text: "Hardware"
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.weight: Font.DemiBold
          }
          HUi.CrossfadeText {
            width: parent.width
            visible: root.hwSummary !== ""
            text: root.hwSummary
            color: root.hw.temp >= 80 ? root.tempColor(root.hw.temp) : root.dimText
            fontSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
        }
        Text {
          id: hwChevron
          anchors.right: parent.right
          anchors.rightMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          text: root.sf(0x10018A)
          color: root.dimText
          font.family: root.symbolFont
          font.pixelSize: Style.font.icon
        }
      }

      // Advanced: rarely used controls, folded away like macOS disclosure sections.
      Item {
        id: advancedHeader
        width: root.panelWidth
        height: Style.space(28)
        opacity: root.revealed ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: "Advanced"
          color: advancedMouse.containsMouse ? root.fg : root.dimText
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.weight: Font.DemiBold
          Behavior on color {
            ColorAnimation {
              duration: advancedMouse.containsMouse ? Motion.instant : Motion.fast
              easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
            }
          }
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          text: root.sf(0x10018A)
          rotation: root.advancedOpen ? 90 : 0
          color: root.dimText
          font.family: root.symbolFont
          font.pixelSize: Style.font.icon
          Behavior on rotation { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        }
        MouseArea {
          id: advancedMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.advancedOpen = !root.advancedOpen
        }
      }

      HUi.Collapse {
        id: advancedSection
        width: root.panelWidth
        expanded: root.advancedOpen

        Column {
          width: root.panelWidth
          spacing: root.gap

          // Tiling layout for the active workspace.
          Tile {
            revealIndex: 8
            width: root.panelWidth
            height: tilingColumn.implicitHeight + Style.space(20)

            Column {
              id: tilingColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.topMargin: Style.space(9)
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(14)
              spacing: Style.space(8)

              Text {
                text: "Tiling"
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                font.weight: Font.DemiBold
              }
              Row {
                id: tilingRow
                width: parent.width
                spacing: Style.space(5)
                readonly property var layouts: [
                  // SF Symbols: square split recursively / rectangle.split.3x1.
                  { id: "dwindle", label: "Dwindle", symbol: String.fromCodePoint(0x100BEB) },
                  { id: "scrolling", label: "Scrolling", symbol: String.fromCodePoint(0x1003DF) }
                ]
                Repeater {
                  model: tilingRow.layouts
                  delegate: Pill {
                    required property var modelData
                    width: Math.floor((tilingRow.width - tilingRow.spacing * (tilingRow.layouts.length - 1)) / tilingRow.layouts.length)
                    label: modelData.label
                    symbol: modelData.symbol
                    selected: root.tilingLayout === modelData.id
                    onClicked: root.setTilingLayout(modelData.id)
                  }
                }
              }
            }
          }

          // Experiments: things that are being tried out and can be switched
          // straight back off, like the macOS look for GTK apps.
          Tile {
            revealIndex: 9
            width: root.panelWidth
            height: Style.space(40)
            hoverable: true
            onClicked: root.showPage("experiments")

            Text {
              id: experimentsIcon
              anchors.left: parent.left
              anchors.leftMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              text: root.sf(0xF0093)   // md flask
              color: root.experimentalOn ? root.circleOn : root.fg
              Behavior on color {
                ColorAnimation {
                  duration: Motion.fast
                  easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
                }
              }
              font.family: root.symbolFont
              font.pixelSize: Style.font.iconLarge
            }
            Text {
              anchors.left: experimentsIcon.right
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: "Experiments"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
            }
            HUi.CrossfadeText {
              anchors.right: experimentsChevron.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: root.experimentalOn ? "On" : ""
              color: root.dimText
              fontFamily: Style.font.family
              fontSize: Style.font.caption
            }
            Text {
              id: experimentsChevron
              anchors.right: parent.right
              anchors.rightMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              text: root.sf(0x10018A)
              color: root.dimText
              font.family: root.symbolFont
              font.pixelSize: Style.font.icon
            }
          }

          // Bottom row, like "Edit Controls" on macOS.
          Tile {
            revealIndex: 10
            width: root.panelWidth
            height: Style.space(40)
            hoverable: true
            onClicked: root.openPluginManager()

            Text {
              id: pluginsIcon
              anchors.left: parent.left
              anchors.leftMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              text: root.sf(0x10096E)
              color: root.fg
              font.family: root.symbolFont
              font.pixelSize: Style.font.iconLarge
            }
            Text {
              anchors.left: pluginsIcon.right
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: "Manage Plugins"
              color: root.fg
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(14)
              anchors.verticalCenter: parent.verticalCenter
              text: root.sf(0x10018A)
              color: root.dimText
              font.family: root.symbolFont
              font.pixelSize: Style.font.icon
            }
          }
        }
      }
    }

    // ---- Detail pages
    Column {
      id: detail
      width: root.panelWidth
      spacing: Style.space(4)
      readonly property bool current: root.page !== "main"
      visible: opacity > 0.01
      opacity: current ? 1 : 0
      x: current || Motion.reduceMotion ? 0 : root.panelWidth
      Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }
      Behavior on x { enabled: root.heightAnimated; NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }

      // Wi-Fi
      PageHeader {
        visible: root.detailPage === "wifi"
        title: "Wi-Fi"
        showSwitch: true
        checked: root.wifiOn
        onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
      }
      Separator { visible: root.detailPage === "wifi" }
      ListLabel {
        visible: root.detailPage === "wifi" && root.wifiOn
        text: root.wifiRows.length ? "Networks" : "Searching for networks …"
      }
      Flickable {
        visible: root.detailPage === "wifi" && root.wifiOn
        width: root.panelWidth
        height: Math.min(wifiList.implicitHeight, Style.space(44) * (root.wifiAdvanced ? 4 : 8))
        Behavior on height { enabled: root.heightAnimated; NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        contentHeight: wifiList.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: Motion.flickDeceleration
        maximumFlickVelocity: Motion.maximumFlickVelocity

        Column {
          id: wifiList
          width: parent.width
          Repeater {
            model: root.detailPage === "wifi" ? root.wifiRowsShown : []
            delegate: Column {
              required property var modelData
              required property int index
              width: root.panelWidth

              ListRow {
                rowIndex: index
                busy: root.wifiPending === modelData.name
                icon: root.wifiIcon(modelData.signal)
                active: modelData.connected
                title: modelData.name
                subtitle: root.wifiPending === modelData.name ? (modelData.connected ? "Disconnecting …" : "Connecting …")
                  : root.wifiFailed === modelData.name ? (modelData.enterprise ? "Check username and password" : "Connection failed")
                  : modelData.connected ? "Connected"
                  : modelData.known ? "Known"
                  : modelData.enterprise ? "Username and password" : ""
                trailing: modelData.secure ? root.sf(0x1003A1) : ""
                onClicked: root.wifiActivate(modelData)
              }

              // Inline credentials for a new secured network: one password
              // field, or username + password for WPA/WPA2-Enterprise.
              Item {
                id: credBox
                readonly property bool wanted: root.wifiPasswordFor === modelData.name
                readonly property bool enterprise: !!modelData.enterprise
                readonly property bool rejected: root.wifiFailed === modelData.name
                visible: height > 0.5
                x: Style.space(44)
                width: root.panelWidth - Style.space(50)
                height: wanted ? credColumn.implicitHeight : 0
                opacity: wanted ? 1 : 0
                clip: true
                Behavior on height { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
                Behavior on opacity {
                  NumberAnimation {
                    duration: credBox.wanted ? Motion.base : Motion.exit(Motion.fast)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: credBox.wanted ? Motion.easeOut : Motion.easeExit
                  }
                }

                function submit() {
                  if (enterprise) {
                    if (userField.text === "") { userField.input.forceActiveFocus(); return }
                    if (passField.text === "") { passField.input.forceActiveFocus(); return }
                    root.wifiConnectEnterprise(modelData.name, userField.text, passField.text)
                  } else {
                    root.wifiConnectWithPassword(modelData.name, passField.text)
                  }
                }
                function clearError() { if (rejected) root.wifiFailed = "" }

                onWantedChanged: {
                  if (!wanted) return
                  passField.text = ""
                  userField.text = enterprise ? root.wifiIdentity : ""
                  if (enterprise && userField.text === "") userField.input.forceActiveFocus()
                  else passField.input.forceActiveFocus()
                }

                // Rejected login: shake once, like the macOS password field.
                Connections {
                  target: root
                  function onWifiShakeTickChanged() { if (credBox.wanted && !Motion.reduceMotion) shake.restart() }
                }
                SequentialAnimation {
                  id: shake
                  NumberAnimation { target: credShift; property: "x"; to: Motion.shakeDistance; duration: Motion.shakeDuration / 6; easing.type: Easing.OutSine }
                  NumberAnimation { target: credShift; property: "x"; to: -Motion.shakeDistance; duration: Motion.shakeDuration / 4; easing.type: Easing.InOutSine }
                  NumberAnimation { target: credShift; property: "x"; to: Motion.shakeDistance; duration: Motion.shakeDuration / 4; easing.type: Easing.InOutSine }
                  NumberAnimation { target: credShift; property: "x"; to: 0; duration: Motion.shakeDuration / 3; easing.type: Easing.OutSine }
                }

                Column {
                  id: credColumn
                  width: parent.width
                  spacing: Style.space(6)
                  transform: Translate { id: credShift }

                  CredField {
                    id: userField
                    visible: credBox.enterprise
                    placeholder: "Username"
                    error: credBox.rejected
                    nextField: passField.input
                    onSubmitted: credBox.submit()
                    onCancelled: root.wifiPasswordFor = ""
                    onEdited: credBox.clearError()
                  }
                  CredField {
                    id: passField
                    placeholder: "Password"
                    password: true
                    submitIcon: true
                    error: credBox.rejected
                    prevField: credBox.enterprise ? userField.input : null
                    onSubmitted: credBox.submit()
                    onCancelled: root.wifiPasswordFor = ""
                    onEdited: credBox.clearError()
                  }
                }
              }
            }
          }
        }
      }

      // ---- Advanced options (everything the stock network panel shows)
      Rectangle {
        visible: root.detailPage === "wifi" && root.wifiOn
        width: root.panelWidth
        height: advancedColumn.implicitHeight
        radius: root.tileRadius
        color: root.wifiAdvanced ? root.tileColor : Util.alpha(root.tileColor, 0)
        clip: true
        Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        Behavior on height { enabled: root.heightAnimated; NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }

        Column {
          id: advancedColumn
          width: parent.width

          Item {
            width: parent.width
            height: Style.space(36)
            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: "Advanced Options"
              color: advMouse.containsMouse ? root.fg : root.dimText
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              Behavior on color {
                ColorAnimation {
                  duration: advMouse.containsMouse ? Motion.instant : Motion.fast
                  easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
                }
              }
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: root.sf(0x10018A)
              rotation: root.wifiAdvanced ? 90 : 0
              color: root.dimText
              font.family: root.symbolFont
              font.pixelSize: Style.font.icon
              Behavior on rotation { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
            }
            MouseArea {
              id: advMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.wifiAdvanced = !root.wifiAdvanced
            }
          }

          Column {
            width: parent.width
            visible: root.wifiAdvanced
            opacity: root.wifiAdvanced ? 1 : 0
            leftPadding: Style.space(12)
            rightPadding: Style.space(12)
            bottomPadding: Style.space(12)
            spacing: Style.space(8)
            transform: Translate {
              y: root.wifiAdvanced || Motion.reduceMotion ? 0 : -Style.space(10)
              Behavior on y { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
            }
            Behavior on opacity {
              NumberAnimation {
                duration: root.wifiAdvanced ? Motion.base : Motion.exit(Motion.fast)
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.wifiAdvanced ? Motion.easeOut : Motion.easeExit
              }
            }

            // Connection summary + share / speed test
            Item {
              width: root.panelWidth - Style.space(24)
              height: Style.space(34)
              Column {
                anchors.left: parent.left
                anchors.right: advButtons.left
                anchors.verticalCenter: parent.verticalCenter
                Text {
                  width: parent.width
                  text: root.netConnected ? (root.netInfo.ssid || root.wifiName || root.netInfo.iface) : "Not connected"
                  color: root.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.weight: Font.DemiBold
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  visible: text !== ""
                  text: [Net.formatFreq(root.netInfo.freq), root.netInfo.bitrate || "",
                         root.netInfo.signal_dbm ? root.netInfo.signal_dbm + " dBm" : ""]
                        .filter(function(t) { return t !== "" }).join(" · ")
                  color: root.dimText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
              Row {
                id: advButtons
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(6)
                IconButton {
                  visible: root.netInfo.type === "wifi"
                  icon: root.sf(0x100582)
                  onClicked: root.summonOverlay("omarchy.wifiqr",
                    root.netInfo.iface ? { iface: root.netInfo.iface, ssid: root.netInfo.ssid || "" } : {})
                }
                IconButton {
                  icon: root.sf(0x10037E)
                  onClicked: root.summonOverlay("omarchy.speedtest",
                    root.netInfo.type === "wifi" ? { connection: root.netInfo.ssid || "Wi-Fi" } : {})
                }
              }
            }

            Separator { width: root.panelWidth - Style.space(24) }

            Grid {
              columns: 2
              columnSpacing: 0
              rowSpacing: Style.space(2)
              readonly property bool hasPings: root.internetPings.length > 0
              Stat { label: "Ping"; value: Net.formatPing(Net.averageLatency(root.internetPings, 5)) }
              Stat { label: "Packet loss"; value: parent.hasPings ? Net.packetLoss(root.internetPings) + " %" : "--" }
              Stat { label: "Download"; value: Net.formatRate(root.netDownRate) }
              Stat { label: "Upload"; value: Net.formatRate(root.netUpRate) }
              Stat { label: "Received"; value: Net.formatBytes(root.netInfo.rx_bytes) }
              Stat { label: "Sent"; value: Net.formatBytes(root.netInfo.tx_bytes) }
              Stat { label: "IP"; value: root.netInfo.ip || "--" }
              Stat { label: "Gateway"; value: root.netInfo.gateway || "--" }
              Stat { label: "Router-Ping"; value: Net.formatPing(Net.averageLatency(root.routerPings, 5)) }
              Stat { label: "Interface"; value: root.netInfo.iface || "--" }
            }

            // Band pinning (only when the card offers a choice)
            SectionLabel {
              visible: root.bandInfo.available.length > 0 && root.netInfo.type === "wifi"
              text: "Wi-Fi band" + (root.bandInfo.band ? " · current " + Net.bandLabel(root.bandInfo.band) : "")
            }
            Row {
              visible: root.bandInfo.available.length > 0 && root.netInfo.type === "wifi"
              spacing: Style.space(5)
              readonly property var options: ["auto"].concat(root.bandInfo.available)
              Repeater {
                model: parent.options
                delegate: Pill {
                  required property string modelData
                  width: Math.floor((root.panelWidth - Style.space(24) - Style.space(5) * 3) / 4)
                  label: root.bandPending === modelData ? "…" : Net.bandLabel(modelData)
                  selected: root.bandInfo.selected === modelData
                  onClicked: root.setBand(modelData)
                }
              }
            }

            SectionLabel { text: "DNS provider" }
            Row {
              spacing: Style.space(5)
              Repeater {
                model: [
                  { id: "DHCP", label: "DHCP" },
                  { id: "Cloudflare", label: "Cloudflare" },
                  { id: "Google", label: "Google" },
                  { id: "Custom", label: "Custom" }
                ]
                delegate: Pill {
                  required property var modelData
                  width: Math.floor((root.panelWidth - Style.space(24) - Style.space(5) * 3) / 4)
                  label: root.dnsPending === modelData.id ? "…" : modelData.label
                  selected: (root.dnsPending || root.dnsProvider) === modelData.id
                  onClicked: root.setDns(modelData.id)
                }
              }
            }
          }
        }
      }

      // Bluetooth
      PageHeader {
        visible: root.detailPage === "bluetooth"
        title: "Bluetooth"
        showSwitch: true
        checked: root.btOn
        onToggled: Quickshell.execDetached(["omarchy-bluetooth-power", root.btOn ? "off" : "on"])
      }
      Separator { visible: root.detailPage === "bluetooth" }
      ListLabel {
        visible: root.detailPage === "bluetooth" && root.btOn
        text: root.btRows.length ? "Devices" : "Searching for devices …"
      }
      ListLabel {
        visible: root.detailPage === "bluetooth" && !root.btOn
        text: "Bluetooth is off"
      }
      Flickable {
        visible: root.detailPage === "bluetooth" && root.btOn
        width: root.panelWidth
        height: Math.min(btList.implicitHeight, Style.space(44) * 8)
        contentHeight: btList.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: Motion.flickDeceleration
        maximumFlickVelocity: Motion.maximumFlickVelocity

        Column {
          id: btList
          width: parent.width
          Repeater {
            model: root.detailPage === "bluetooth" ? root.btRows : []
            delegate: ListRow {
              required property var modelData
              required property int index
              rowIndex: index
              busy: !!root.btPending[modelData.address]
              icon: root.btIcon(modelData.icon)
              active: modelData.connected
              title: modelData.name
              subtitle: root.btPending[modelData.address]
                || (modelData.connected ? "Connected" : modelData.paired ? "Paired" : "Not paired")
              trailing: modelData.battery >= 0 ? modelData.battery + " %" : ""
              onClicked: root.btActivate(modelData)
            }
          }
        }
      }

      // Sound
      PageHeader {
        visible: root.detailPage === "sound"
        title: "Sound"
      }
      Separator { visible: root.detailPage === "sound" }
      VolumeRow { visible: root.detailPage === "sound" && root.sink !== null }
      ListLabel {
        visible: root.detailPage === "sound"
        text: "Output"
      }
      Repeater {
        model: root.detailPage === "sound" ? root.sinkRows : []
        delegate: ListRow {
          required property var modelData
          required property int index
          rowIndex: index
          icon: root.sinkIcon(modelData.label)
          active: modelData.active
          title: modelData.label
          trailing: modelData.active ? root.sf(0x100185) : " "
          onClicked: if (!modelData.active) root.setSink(modelData)
        }
      }
      ListRow {
        visible: root.detailPage === "sound" && pods.daemonReachable && !pods.connected && pods.deviceName !== ""
        icon: root.sf(0xF1852)
        title: root.airpodsName
        subtitle: pods.connectionBusy ? "Connecting …" : pods.actionStatus !== "" ? pods.actionStatus : "Not connected"
        busy: pods.connectionBusy
        onClicked: pods.toggleConnection()
      }

      // AirPods — everything the librepods daemon can do, shown while connected.
      PageHeader {
        visible: root.detailPage === "airpods"
        title: root.airpodsName
      }
      Separator { visible: root.detailPage === "airpods" }
      Flickable {
        visible: root.detailPage === "airpods"
        width: root.panelWidth
        // Tall on purpose; scrolls only on short screens.
        height: Math.min(podsPage.implicitHeight, Math.max(Style.space(240), panel.availableCardHeight - Style.space(80)))
        contentHeight: podsPage.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: Motion.flickDeceleration
        maximumFlickVelocity: Motion.maximumFlickVelocity

        Column {
          id: podsPage
          width: root.panelWidth
          spacing: Style.space(4)

          // Battery: left, right and case (or the one headset battery).
          Row {
            x: Style.space(6)
            topPadding: Style.space(6)
            bottomPadding: Style.space(4)
            Repeater {
              model: root.airpodsBatteries
              delegate: PodBattery {
                required property var modelData
                width: Math.floor((root.panelWidth - Style.space(12)) / root.airpodsBatteries.length)
                label: modelData.label
                level: modelData.level
                charging: modelData.charging
              }
            }
          }

          VolumeRow {}

          Text {
            visible: text !== ""
            width: root.panelWidth
            leftPadding: Style.space(6)
            rightPadding: Style.space(6)
            text: pods.actionStatus !== "" ? pods.actionStatus : pods.lastError
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          ListLabel {
            visible: root.airpodsModes.length > 0
            text: "Listening Mode"
          }
          Repeater {
            model: root.detailPage === "airpods" ? root.airpodsModes : []
            delegate: ListRow {
              required property var modelData
              required property int index
              rowIndex: index
              icon: root.noiseModeIcon(modelData)
              active: pods.noiseMode === modelData
              title: Pods.noiseModeName(modelData)
              trailing: active ? root.sf(0x100185) : " "
              onClicked: pods.setNoiseMode(modelData)
            }
          }
          HUi.Collapse {
            width: root.panelWidth
            expanded: pods.supportsAdaptive && pods.noiseMode === Pods.NOISE_ADAPTIVE
            Column {
              width: root.panelWidth
              topPadding: Style.space(2)
              bottomPadding: Style.space(6)
              spacing: Style.space(2)
              Item {
                width: root.panelWidth
                height: adaptiveLabel.implicitHeight
                Text {
                  id: adaptiveLabel
                  x: Style.space(12)
                  text: "Adaptive noise level"
                  color: root.dimText
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }
                HUi.CrossfadeText {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(14)
                  horizontalAlignment: Text.AlignRight
                  text: pods.adaptiveNoiseLevel + " %"
                  color: root.dimText
                  fontSize: Style.font.caption
                }
              }
              PanelSlider {
                x: Style.space(12)
                width: root.panelWidth - Style.space(26)
                bar: root.bar
                minimum: 0
                maximum: 1
                step: 0.05
                value: pods.adaptiveNoiseLevel / 100
                fillColor: root.fg
                knobColor: root.fg
                trackColor: root.circleOff
                tickColor: "transparent"
                onMoved: function(v) { pods.setAdaptiveNoiseLevel(v * 100) }
              }
            }
          }

          SwitchRow {
            visible: pods.supportsConversationalAwareness
            title: "Conversation Awareness"
            caption: "Lowers the volume when you start talking"
            checked: pods.conversationalAwareness
            onToggled: function(on) { pods.setConversationalAwareness(on) }
          }
          SwitchRow {
            visible: pods.supportsOneBudANC
            title: "One-Bud Noise Cancellation"
            caption: "Keeps the mode on with only one AirPod in"
            checked: pods.oneBudANC
            onToggled: function(on) { pods.setOneBudANC(on) }
          }

          ListLabel { text: "Pause Media When Removed" }
          Row {
            x: Style.space(6)
            spacing: Style.space(6)
            topPadding: Style.space(2)
            bottomPadding: Style.space(4)
            Repeater {
              model: [
                { label: "One AirPod", value: Pods.EAR_PAUSE_ONE_OUT },
                { label: "Both", value: Pods.EAR_PAUSE_BOTH_OUT },
                { label: "Never", value: Pods.EAR_DISABLED }
              ]
              delegate: Pill {
                required property var modelData
                width: Math.floor((root.panelWidth - Style.space(24)) / 3)
                label: modelData.label
                selected: pods.earDetectionBehavior === modelData.value
                onClicked: pods.setEarDetectionBehavior(modelData.value)
              }
            }
          }

          Separator {}
          Item {
            width: root.panelWidth
            height: Style.space(30)
            FooterLink {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: pods.connectionRequest === "disconnect" ? "Disconnecting …" : "Disconnect"
              onClicked: if (!pods.busy) pods.toggleConnection()
            }
            FooterLink {
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: "Sound Output …"
              onClicked: root.showPage("sound")
            }
          }
        }
      }

      // Experiments — switches for things that are still being tried out.
      // Every one of them is a flag a helper owns, so anything here can be
      // turned straight back off without leaving traces behind.
      PageHeader {
        visible: root.detailPage === "experiments"
        title: "Experiments"
      }
      Separator { visible: root.detailPage === "experiments" }
      Column {
        visible: root.detailPage === "experiments"
        width: root.panelWidth

        ListLabel { text: "Appearance" }
        SwitchRow {
          title: "macOS Mode"
          caption: root.experimentalBusy ? "Switching …"
            : root.experimentalOn ? "On — Tahoe shapes across the shell"
            : "Round the shell the way macOS Tahoe is"
          checked: root.experimentalOn
          onToggled: function(on) { root.setExperimental(on) }
        }
        Item {
          width: root.panelWidth
          height: explainer.implicitHeight + Style.space(14)
          Text {
            id: explainer
            x: Style.space(12)
            y: Style.space(4)
            width: root.panelWidth - Style.space(24)
            text: "Swaps the henri-ui corner radii and control sizes for Tahoe's, "
              + "everywhere at once. The shell restarts a moment after the switch, "
              + "so this panel will blink."
            wrapMode: Text.WordWrap
            color: root.dimText
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }

      // Hardware — read-only live readings, refreshed every 2 s.
      PageHeader {
        visible: root.detailPage === "hardware"
        title: "Hardware"
      }
      Separator { visible: root.detailPage === "hardware" }
      Column {
        id: hwPage
        visible: root.detailPage === "hardware"
        width: root.panelWidth
        leftPadding: Style.space(6)
        rightPadding: Style.space(6)
        topPadding: Style.space(4)
        bottomPadding: Style.space(6)
        spacing: Style.space(6)
        readonly property int innerWidth: root.panelWidth - Style.space(12)
        readonly property int cellWidth: Math.floor((innerWidth - Style.space(16)) / 2)
        function meterColor(f) { return f >= 0.9 ? Color.urgent : Color.accent }

        Text {
          visible: text !== ""
          width: hwPage.innerWidth
          text: root.hw.model + (root.hw.cores > 0 ? " · " + root.hw.cores + " cores / " + root.hw.threads + " threads" : "")
          color: root.dimText
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        // Processor
        UsageHeader {
          width: hwPage.innerWidth
          title: "CPU"
          value: root.cpuLoad >= 0 ? root.cpuLoad + " %" : "--"
        }
        Meter {
          width: hwPage.innerWidth
          fraction: root.cpuLoad / 100
          fillColor: hwPage.meterColor(root.cpuLoad / 100)
        }
        Grid {
          columns: 2
          columnSpacing: Style.space(16)
          rowSpacing: Style.space(2)
          topPadding: Style.space(2)
          Stat { width: hwPage.cellWidth; label: "Clock"; value: root.formatGHz(root.hw.freqAvg) }
          Stat { width: hwPage.cellWidth; label: "Fastest core"; value: root.formatGHz(root.hw.freqPeak) }
          Stat { width: hwPage.cellWidth; label: "Max clock"; value: root.formatGHz(root.hw.freqMax) }
          Stat { width: hwPage.cellWidth; label: "Load (1 min)"; value: Number(root.hw.load1).toFixed(2) }
          Stat {
            width: hwPage.cellWidth
            label: "Temperature"
            value: root.hw.temp >= 0 ? root.hw.temp + " °C" : "--"
          }
          Repeater {
            model: root.hw.fans
            delegate: Stat {
              required property var modelData
              width: hwPage.cellWidth
              label: modelData.label
              value: modelData.rpm > 0 ? modelData.rpm + " rpm" : "Idle"
            }
          }
        }

        Separator { width: hwPage.innerWidth }

        // Memory
        UsageHeader {
          width: hwPage.innerWidth
          title: "Memory"
          value: root.hw.memTotal > 0
            ? root.formatGiB(root.hw.memTotal - root.hw.memAvail, 1) + " of " + root.formatGiB(root.hw.memTotal, 1) + " GB"
            : "--"
        }
        Meter {
          width: hwPage.innerWidth
          fraction: root.memUsedFrac
          fillColor: hwPage.meterColor(root.memUsedFrac)
        }
        Grid {
          columns: 2
          columnSpacing: Style.space(16)
          rowSpacing: Style.space(2)
          topPadding: Style.space(2)
          Stat { width: hwPage.cellWidth; label: "Used"; value: Math.round(root.memUsedFrac * 100) + " %" }
          Stat { width: hwPage.cellWidth; label: "Available"; value: root.formatGiB(root.hw.memAvail, 1) + " GB" }
          Stat {
            width: hwPage.cellWidth
            label: "Swap"
            value: root.hw.swapTotal > 0 ? root.formatGiB(root.hw.swapTotal - root.hw.swapFree, 1) + " GB" : "Off"
          }
          Stat {
            width: hwPage.cellWidth
            label: "Swap size"
            value: root.hw.swapTotal > 0 ? root.formatGiB(root.hw.swapTotal, 0) + " GB" : "--"
          }
        }

        Separator { width: hwPage.innerWidth }

        // Storage
        UsageHeader {
          width: hwPage.innerWidth
          title: "Disk"
          value: root.hw.diskTotal > 0
            ? root.formatBytesGB(root.hw.diskUsed) + " of " + root.formatBytesGB(root.hw.diskTotal)
            : "--"
        }
        Meter {
          width: hwPage.innerWidth
          fraction: root.diskUsedFrac
          fillColor: hwPage.meterColor(root.diskUsedFrac)
        }
        Grid {
          columns: 2
          columnSpacing: Style.space(16)
          topPadding: Style.space(2)
          Stat { width: hwPage.cellWidth; label: "Free"; value: root.formatBytesGB(root.hw.diskTotal - root.hw.diskUsed) }
          Stat { width: hwPage.cellWidth; label: "Uptime"; value: root.hw.uptime > 0 ? root.formatUptime(root.hw.uptime) : "--" }
        }
      }
    }
    }
  }
}
