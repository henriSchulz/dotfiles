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
import "file:///home/henri/.local/share/apple-ui/Apple.js" as Apple
import "file:///home/henri/.local/share/apple-ui" as AUi

// Control Center v2 — macOS-Tahoe-Layout auf apple-ui (echte, gemessene
// Apple-Werte statt Omarchy-Theme; siehe ~/.local/share/apple-ui/Apple.js).
// Bewegung weiterhin aus henri-ui. Alle Funktionen von henri.control-center
// (v1): Wi-Fi mit Passwort/802.1X und erweiterten Optionen, Bluetooth-Geräte,
// AirDrop (LocalSend), Mac Input/Screen/Mode (mt-bridge), Display (Helligkeit,
// Textgröße, Skalierung, Monitore), Sound (Ausgänge, AirPods), Now Playing,
// Hardware, Experimente, Plugin-Manager, Tastatur-Cursor, IPC-Seitenaufrufe.
//
// Das Material (dunkles/helles Glas) folgt der Wallpaper-Helligkeit unter dem
// Panel (AUi.Backdrop) — wie macOS.
Panel {
  id: root
  moduleName: "henri.control-center-v2"
  ipcTarget: "henri.control-center-v2"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var shell: bar ? bar.shell : null

  // ---- Material (apple-ui). `mat` hängt als appleMaterial am Popup-Inhalt.
  AUi.Backdrop { id: backdrop }
  AUi.Material { id: mat; dark: backdrop.dark }
  readonly property var m: mat
  readonly property bool darkGlass: mat.dark
  // Low-power rendering (Experiments): the flag file under ~/.local/state/henri
  // is the state, looknfeel.lua applies it on reload; `status` also reports the
  // values Hyprland really runs with, so the switch reflects reality.
  property var renderPower: ({})
  readonly property bool renderPowerOn: renderPower.state === "on"
  readonly property bool renderPowerBusy: renderPowerSetProc.running
  readonly property real backdropLuma: backdrop.luma
  function setBackdropLuma(v) { backdrop.set(v) }
  function refreshBackdrop() { backdrop.remeasure() }
  function pt(v) { return Style.space(v) }
  function ptr(v) { return Style.spaceReal(v) }
  readonly property int panelWidth: pt(Apple.contentWidth)
  readonly property int gap: pt(Apple.gap)
  readonly property int half: pt(Apple.tile)
  readonly property int tileH: pt(Apple.tileH)
  readonly property string uiFont: Apple.uiFont
  readonly property string symbolFont: Apple.symbolFont
  readonly property string iconFont: bar ? bar.fontFamily : Style.font.family
  function sf(cp) { return String.fromCodePoint(cp) }

  // ---- Trackpad bridge (mt-bridge): a MacBook's trackpad arriving over a
  // USB-C cable, or over Wi-Fi when the cable is out. Both daemons keep a
  // small status file and this watches those, because polling them with
  // processes would cost frames at exactly the moment the panel opens.
  property var padLink: ({})
  property var padStream: ({})
  property int padTick: 0
  readonly property bool padLinkUp: padLink.state === "up"
  readonly property bool padBridgeUp: padTick >= 0
    && Number(padStream.updated || 0) > 0
    && Date.now() / 1000 - Number(padStream.updated) < 4
  property var padOverride: null
  property double padOverrideSetAt: 0
  readonly property bool padOn: padOverride !== null ? padOverride : padBridgeUp
  readonly property bool padStreaming: padBridgeUp
    && Number(padStream.last_packet || 0) > 0
    && Date.now() / 1000 - Number(padStream.last_packet) < 3
  readonly property string padTransport: padStream.transport || ""
  readonly property bool padButton: padStream.button === "1"
  readonly property bool padKeyboard: padStream.keyboard === "1"
  readonly property int padKeysHeld: Number(padStream.keys_held || 0)
  readonly property bool padLinked: padStream.linked === "1"
  readonly property string padSubtitle: !padBridgeUp ? "Off"
    : padStreaming ? (padTransport !== "" ? "Over " + padTransport : "Connected")
    : padLinked ? (padTransport !== "" ? "Idle · " + padTransport : "Connected")
    : padLinkUp ? "Cable up · not connected" : "Not connected"

  // ---- The Mac's screen, arriving as H.264 (mac-stream status file + heartbeat).
  property var screenState: ({})
  readonly property bool screenOn: padTick >= 0
    && Number(screenState.updated || 0) > 0
    && Date.now() / 1000 - Number(screenState.updated) < 6
  readonly property string screenRoute: screenState.route || ""
  readonly property string screenSubtitle: !screenOn ? "Off"
    : screenRoute !== "" ? "Over " + screenRoute : "Mirroring"

  // ---- Mac mode: "server" vs "desktop", read from a file mac-mode-poll fills.
  property var macModeState: ({})
  property int macModeTick: 0
  readonly property string macModePin: macModeState.pin || "auto"
  readonly property string macModeEffective: macModeState.mode || ""
  readonly property int macModeDisplays: Number(macModeState.displays || 0)
  readonly property bool macModeFresh: macModeTick >= 0
    && Number(macModeState.updated || 0) > 0
    && Date.now() / 1000 - Number(macModeState.updated) < 40
  property var macModeOverride: null
  property double macModeOverrideSetAt: 0
  readonly property string macModePinShown: macModeOverride !== null ? macModeOverride : macModePin
  readonly property string macModeShown: macModeOverride !== null
    ? (macModeOverride === "auto" ? (macModeDisplays > 1 ? "desktop" : "server") : macModeOverride)
    : macModeEffective
  readonly property bool macModeIsDesktop: macModeShown === "desktop"
  readonly property string macModeSubtitle: !macModeFresh && macModeOverride === null ? "Unreachable"
    : (macModeIsDesktop ? "Desktop" : "Server") + (macModePinShown === "auto" ? " · Auto" : " · Forced")

  // One "Mac" tile stands for the three mt-bridge features. Its page leads
  // with one status synthesized across all three (actively streaming beats
  // merely reachable beats nothing answering at all); Mode's picker is
  // simple enough to sit right there with nothing further to drill into,
  // Input and Screen are a level below it.
  readonly property string macOverall: (padStreaming || screenOn) ? "connected"
    : (padBridgeUp || padLinkUp || macModeFresh) ? "possible" : "unreachable"
  readonly property string macOverallLabel: macOverall === "connected" ? "Connected"
    : macOverall === "possible" ? "Connection possible" : "Not reachable"
  readonly property string macOverallDetail: macOverall === "connected"
      ? (padStreaming && screenOn ? "Trackpad and screen are both active."
         : padStreaming ? "Fingers are arriving from the Mac."
         : "The screen is mirroring.")
    : macOverall === "possible" ? "The Mac is reachable, but nothing is streaming right now."
    : "No cable and no answer over the network. Check that the Mac is awake."
  readonly property var macPages: ["trackpad", "screen"]
  function backPage() { return macPages.indexOf(page) >= 0 ? "mac" : "main" }
  function goBack() { page = backPage() }

  function padParse(text) {
    var out = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var eq = lines[i].indexOf("=")
      if (eq > 0) out[lines[i].substring(0, eq)] = lines[i].substring(eq + 1)
    }
    return out
  }

  FileView {
    id: padLinkFile
    path: "/run/mt-bridge/link"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.padLink = root.padParse(text())
  }
  FileView {
    id: padStreamFile
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/mt-bridge/status"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.padStream = root.padParse(text())
  }
  FileView {
    id: screenFile
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/mt-bridge/screen"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.screenState = root.padParse(text())
  }
  FileView {
    id: macModeFile
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/mt-bridge/macmode"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.macModeState = root.padParse(text())
  }
  Timer {
    running: root.opened
    interval: 1000
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.padTick++
      padLinkFile.reload()
      padStreamFile.reload()
      screenFile.reload()
      macModeFile.reload()
      if (root.padOverride !== null
          && (root.padBridgeUp === root.padOverride
              || Date.now() - root.padOverrideSetAt > 5000))
        root.padOverride = null
      if (root.macModeOverride !== null
          && (root.macModePin === root.macModeOverride
              || Date.now() - root.macModeOverrideSetAt > 6000))
        root.macModeOverride = null
    }
  }

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

  // ---- Detail pages ("main" | wifi | bluetooth | sound | airpods | hardware |
  //      screen | trackpad | macmode | experiments)
  property string page: "main"
  function showPage(name) {
    if (name === "sound" && !sinkPortProc.running) sinkPortProc.running = true
    page = name
  }
  property string detailPage: "wifi"
  property double pageShownAt: 0
  property bool revealed: false
  property bool heightAnimated: false
  onPageChanged: {
    if (page !== "main") detailPage = page
    pageShownAt = Date.now()
  }
  function rowDelay(index) {
    return Date.now() - pageShownAt < Motion.slow ? Motion.stagger(index) : -1
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
  function wifiIcon(signal) { return sf(0x100647) }
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
  function btIconFont(icon) { return btIcon(icon).codePointAt(0) >= 0x100000 ? symbolFont : iconFont }

  // ---- Sound outputs (pactl tells which sinks are actually plugged)
  property var unavailableSinks: ({})
  Process {
    id: sinkPortProc
    command: ["pactl", "-f", "json", "list", "sinks"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
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
        root.unavailableSinks = gone
      }
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
  function sinkIcon(label) {
    var l = String(label).toLowerCase()
    if (l.indexOf("hdmi") >= 0 || l.indexOf("displayport") >= 0) return sf(0x1008B9)
    if (l.indexOf("head") >= 0 || l.indexOf("kopfh") >= 0) return sf(0x100448)
    return sf(0x10074E)
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
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyHwStat(text) }
  }
  Timer { interval: Motion.settleDelay; running: root.opened; onTriggered: root.refreshHardware() }
  Timer { interval: 2000; repeat: true; running: root.opened; onTriggered: root.refreshHardware() }

  // ---- Low-power rendering (Experiments)
  readonly property string renderPowerPath: String(Qt.resolvedUrl("system/henri-render-power")).replace(/^file:\/\//, "")
  function refreshRenderPower() { if (!renderPowerProc.running) renderPowerProc.running = true }
  function setRenderPower(on) {
    if (renderPowerSetProc.running) return
    renderPowerSetProc.command = [root.renderPowerPath, on ? "on" : "off"]
    renderPowerSetProc.running = true
  }
  Process {
    id: renderPowerProc
    command: [root.renderPowerPath, "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.renderPower = root.padParse(text) }
  }
  Process {
    id: renderPowerSetProc
    onExited: root.refreshRenderPower()
  }
  Timer { interval: Motion.settleDelay; running: root.opened; onTriggered: root.refreshRenderPower() }

  // ---- Services owned by the shell
  function service(id) {
    return shell && typeof shell.firstPartyServiceFor === "function"
      ? shell.firstPartyServiceFor(id) : null
  }
  readonly property var media: opened ? service("omarchy.media") : null
  readonly property var player: media ? media.activePlayer : null
  readonly property bool playing: player ? player.isPlaying === true : false

  // ---- AirPods (librepods daemon)
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
  readonly property int airpodsLevel: {
    var levels = pods.isHeadset ? [pods.headsetBattery.level] : [pods.leftPod.level, pods.rightPod.level]
    var known = levels.filter(function(l) { return l !== Pods.LEVEL_UNKNOWN })
    return known.length ? Math.min.apply(null, known) : -1
  }
  function noiseModeIcon(mode) {
    if (mode === Pods.NOISE_ANC) return sf(0xF0A45)
    if (mode === Pods.NOISE_TRANSPARENCY) return sf(0xF07C5)
    if (mode === Pods.NOISE_ADAPTIVE) return sf(0xF00E1)
    return sf(0xF1852)
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
  readonly property string volumeGlyph: muted || volume === 0 ? sf(0x1002A3) : volume < 0.34 ? sf(0x1002A5) : volume < 0.67 ? sf(0x1002A7) : sf(0x1002A9)

  // ---- Display brightness
  property int brightness: 0
  property bool brightnessAvailable: false
  property string internalMonitor: ""
  property int queuedBrightness: -1

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

  // ---- AirDrop stand-in: LocalSend
  property bool localsendRunning: false
  function run(cmd) { Quickshell.execDetached(["bash", "-c", cmd]) }

  // ---- Plugin manager (hosted by BarWidget.qml)
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
    if (!sinkPortProc.running) sinkPortProc.running = true
    if (!localsendProc.running) localsendProc.running = true
    if (!tilingProc.running) tilingProc.running = true
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

  // ---- Keyboard cursor (main page): reading-order stops, ↑↓/jk move, ←→/hl
  //      act on the focused stop, Enter/Space activates. Tab switches panels,
  //      Esc closes or goes back (PanelKeyCatcher).
  property bool cursorActive: false
  property int mainCursorIndex: 0
  property int playbackCursorIndex: 1
  readonly property var mainStops: {
    var s = ["wifi", "bluetooth"]
    if (player) s.push("playback")
    s = s.concat(["airdrop", "mac", "hardware", "experiments", "qr", "speedtest",
                  "textsize", "layout", "display", "sound", "plugins"])
    return s
  }
  readonly property string mainFocus: cursorActive && page === "main"
    && mainCursorIndex >= 0 && mainCursorIndex < mainStops.length ? mainStops[mainCursorIndex] : ""
  onMainStopsChanged: mainCursorIndex = Math.max(0, Math.min(mainStops.length - 1, mainCursorIndex))

  function mainMoveCursor(dy) {
    if (!cursorActive) { cursorActive = true; return }
    mainCursorIndex = Math.max(0, Math.min(mainStops.length - 1, mainCursorIndex + dy))
  }
  function mainMoveHorizontal(dx) {
    if (!cursorActive) { cursorActive = true; return }
    var f = mainFocus
    if (f === "display") setBrightness(brightness + dx * 5)
    else if (f === "sound") setVolume(volume + dx * 0.05)
    else if (f === "textsize") setTextSizeIndex(textSizeIndex + dx)
    else if (f === "layout") setTilingLayout(dx > 0 ? "scrolling" : "dwindle")
    else if (f === "playback") playbackCursorIndex = Math.max(0, Math.min(2, playbackCursorIndex + dx))
    else if (dx > 0) {
      if (f === "wifi" || f === "bluetooth" || f === "mac" || f === "hardware" || f === "experiments") showPage(f)
      else if (f === "airdrop") openAirdrop()
      else if (f === "sound") showPage(airpodsActive ? "airpods" : "sound")
    }
  }
  function mainActivate() {
    if (!cursorActive) return
    var f = mainFocus
    if (f === "wifi") toggleWifi()
    else if (f === "bluetooth") toggleBluetooth()
    else if (f === "airdrop") toggleAirdrop()
    else if (f === "mac") showPage("mac")
    else if (f === "hardware") showPage("hardware")
    else if (f === "experiments") showPage("experiments")
    else if (f === "display") displayExpanded = !displayExpanded
    else if (f === "sound") toggleMute()
    else if (f === "layout") setTilingLayout(tilingLayout === "scrolling" ? "dwindle" : "scrolling")
    else if (f === "qr") openWifiQr()
    else if (f === "speedtest") openSpeedTest()
    else if (f === "plugins") openPluginManager()
    else if (f === "playback") { if (media) media.runAction(["previous", "playPause", "next"][playbackCursorIndex], false) }
  }

  function toggleWifi() { Networking.wifiEnabled = !Networking.wifiEnabled }
  function toggleBluetooth() { Quickshell.execDetached(["omarchy-bluetooth-power", root.btOn ? "off" : "on"]) }
  function toggleAirdrop() {
    if (localsendRunning) { run("pkill -x localsend"); localsendRunning = false }
    else { run("setsid -f localsend >/dev/null 2>&1"); localsendRunning = true }
  }
  function openAirdrop() { close(); run("omarchy-launch-or-focus localsend 'setsid -f localsend'") }
  function toggleTrackpad() {
    var goingUp = !padOn
    padOverride = goingUp
    padOverrideSetAt = Date.now()
    run(goingUp ? "systemctl --user start mtbridge" : "systemctl --user stop mtbridge")
  }
  function launchMacScreen() { close(); run("omarchy-launch-or-focus gst-launch-1.0 'setsid -f mac-stream'") }
  function setMacMode(mode) {
    macModeOverride = mode
    macModeOverrideSetAt = Date.now()
    run("ssh -o ConnectTimeout=3 -o BatchMode=yes henrischulz@192.168.178.126 /Users/henrischulz/.local/bin/mac-mode set " + mode
      + "; systemctl --user start mac-mode-poll.service")
  }
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
      revealTimer.restart()
      // The QR/speed-test tiles need the interface name; cheap, one process.
      if (!netDetailsProc.running) netDetailsProc.running = true
    } else {
      revealed = false
      heightAnimated = false
      revealTimer.stop()
      displayExpanded = false
      page = "main"
      wifiPasswordFor = ""
      wifiAdvanced = false
      cursorActive = false
      mainCursorIndex = 0
      playbackCursorIndex = 1
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
  Process { id: actionProc; onExited: root.refresh() }
  Process { id: textSizeProc; onExited: textSizeSettle.restart() }
  Timer { id: textSizeSettle; interval: 600; onTriggered: root.textSizePreviewIndex = -1 }
  Timer {
    id: revealTimer
    interval: 16
    onTriggered: { root.revealed = true; heightReadyTimer.restart() }
  }
  Timer { id: heightReadyTimer; interval: 60; onTriggered: root.heightAnimated = true }
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

  // ======================================================== components

  // Half-width connectivity tile (140 × 64): badge toggles, the rest drills in.
  component ToggleTile: AUi.Tile {
    id: tt
    property string icon: ""
    property string iconFont: root.symbolFont
    property real iconSize: root.ptr(18)
    property bool on: false
    property string title: ""
    property string subtitle: ""
    property bool squircle: false
    property bool badgeToggles: true
    signal toggled()
    signal details()
    width: root.half
    height: root.tileH
    interactive: true
    onClicked: tt.details()
    AUi.Badge {
      id: ttBadge
      x: root.pt(Apple.badgeInset)
      anchors.verticalCenter: parent.verticalCenter
      on: tt.on
      glyph: tt.icon
      glyphFont: tt.iconFont
      glyphSize: tt.iconSize
      squircle: tt.squircle
      clickable: tt.badgeToggles
      onClicked: tt.toggled()
    }
    Column {
      x: root.pt(Apple.textX)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x - root.pt(8)
      spacing: 0
      AUi.Title { width: parent.width; text: tt.title }
      AUi.Subtitle {
        width: parent.width
        visible: tt.subtitle !== ""
        text: tt.subtitle
        wrapMode: Text.WordWrap
        maximumLineCount: 2
      }
    }
  }

  // Wide slider tile (292 × 64): title, glyphs and the Tahoe slider at y 42.
  component SliderTile: AUi.Tile {
    id: st
    property string heading: ""
    property string leftGlyph: ""
    property string rightGlyph: ""
    property real value: 0
    property bool sliderEnabled: true
    property string headingDetail: ""
    property Component headingGlyph: null
    property bool expandable: false
    property bool expanded: false
    default property alias extra: extraColumn.data
    signal moved(real value)
    signal leftGlyphClicked()
    signal rightGlyphClicked()
    signal headingClicked()
    width: root.panelWidth
    height: root.tileH + (expanded ? extraColumn.implicitHeight + root.pt(12) : 0)
    clip: true
    Behavior on height {
      enabled: root.heightAnimated
      NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
    }

    Item {
      id: stHead
      x: root.pt(Apple.labelInset); y: root.pt(Apple.labelTop)
      width: parent.width - x - root.pt(Apple.labelInset)
      height: stTitle.implicitHeight
      Loader {
        id: stGlyph
        anchors.verticalCenter: parent.verticalCenter
        active: st.headingGlyph !== null
        sourceComponent: st.headingGlyph
        width: active ? root.pt(20) : 0
      }
      HUi.CrossfadeText {
        id: stTitle
        anchors.left: stGlyph.right
        text: st.heading
        color: root.m.ink
        fontFamily: root.uiFont
        fontSize: root.pt(Apple.headline)
        fontWeight: Font.Bold
      }
      HUi.CrossfadeText {
        anchors.right: stChevron.left
        anchors.rightMargin: root.pt(6)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: st.headingDetail
        color: root.m.inkSecondary
        fontFamily: root.uiFont
        fontSize: root.pt(Apple.subheadline)
      }
      Text {
        id: stChevron
        visible: st.expandable
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.sf(0x10018A)
        rotation: st.expanded ? 90 : 0
        color: root.m.inkSecondary
        font.family: root.symbolFont
        font.pixelSize: root.pt(12)
        Behavior on rotation { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      }
      MouseArea {
        anchors.fill: parent
        anchors.margins: -root.pt(4)
        cursorShape: Qt.PointingHandCursor
        onClicked: st.headingClicked()
      }
    }
    AUi.Glyph {
      id: stLeft
      x: root.ptr(15.5); y: root.pt(Apple.sliderY) - height / 2
      text: st.leftGlyph
      size: root.ptr(16)
      MouseArea { anchors.fill: parent; anchors.margins: -root.pt(4); cursorShape: Qt.PointingHandCursor; onClicked: st.leftGlyphClicked() }
    }
    AUi.Slider {
      x: root.ptr(36.5); y: root.pt(Apple.sliderY) - height / 2
      width: root.ptr(217.5)
      value: st.value
      enabled: st.sliderEnabled
      onMoved: function(v) { st.moved(v) }
    }
    AUi.Glyph {
      x: root.ptr(259.5); y: root.pt(Apple.sliderY) - height / 2
      text: st.rightGlyph
      size: root.ptr(17)
      MouseArea { anchors.fill: parent; anchors.margins: -root.pt(4); cursorShape: Qt.PointingHandCursor; onClicked: st.rightGlyphClicked() }
    }
    Column {
      id: extraColumn
      x: root.pt(Apple.labelInset); y: root.tileH
      width: parent.width - root.pt(Apple.labelInset) * 2
      visible: st.expanded
      opacity: st.expanded ? 1 : 0
      spacing: root.pt(8)
      transform: Translate {
        y: st.expanded || Motion.reduceMotion ? 0 : -root.pt(8)
        Behavior on y { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      }
      Behavior on opacity {
        NumberAnimation {
          duration: st.expanded ? Motion.base : Motion.exit(Motion.fast)
          easing.type: Easing.BezierSpline
          easing.bezierCurve: st.expanded ? Motion.easeOut : Motion.easeExit
        }
      }
    }
  }

  // Volume slider of the default output with a mute glyph (Sound + AirPods pages).
  component VolumeRow: Item {
    width: root.panelWidth
    height: root.pt(40)
    AUi.Glyph {
      id: vrIcon
      anchors.left: parent.left
      anchors.leftMargin: root.pt(14)
      anchors.verticalCenter: parent.verticalCenter
      width: root.pt(20)
      text: root.volumeGlyph
      size: root.ptr(16)
      MouseArea { anchors.fill: parent; anchors.margins: -root.pt(4); cursorShape: Qt.PointingHandCursor; onClicked: root.toggleMute() }
    }
    AUi.Slider {
      anchors.left: vrIcon.right
      anchors.right: parent.right
      anchors.leftMargin: root.pt(8)
      anchors.rightMargin: root.pt(16)
      anchors.verticalCenter: parent.verticalCenter
      value: root.muted ? 0 : Math.min(1, root.volume)
      onMoved: function(v) { root.setVolume(v) }
    }
  }

  // One battery cell on the AirPods page.
  component PodBattery: Column {
    id: pb
    property string label: ""
    property int level: -1
    property bool charging: false
    readonly property bool known: level !== Pods.LEVEL_UNKNOWN
    spacing: root.pt(3)
    HUi.CrossfadeText {
      anchors.horizontalCenter: parent.horizontalCenter
      text: pb.known ? pb.level + " %" : "--"
      color: pb.known && pb.level <= 20 && !pb.charging ? root.m.urgent : root.m.ink
      fontFamily: root.uiFont
      fontSize: root.pt(Apple.body)
      fontWeight: Font.DemiBold
    }
    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: root.pt(5)
      HUi.BatteryGlyph {
        anchors.verticalCenter: parent.verticalCenter
        visible: pb.known
        height: root.pt(10)
        level: Pods.levelFraction(pb.level)
        charging: pb.charging
        ink: root.m.ink
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: pb.label
        color: root.m.inkMuted
        font.family: root.uiFont
        font.pixelSize: root.pt(Apple.footnote)
      }
    }
  }

  // Detail-page body with the standard insets and a two-column stat grid width.
  component PageBody: Column {
    width: root.panelWidth
    leftPadding: root.pt(6)
    rightPadding: root.pt(6)
    topPadding: root.pt(4)
    bottomPadding: root.pt(6)
    spacing: root.pt(6)
    readonly property int innerWidth: root.panelWidth - root.pt(12)
    readonly property int cellWidth: Math.floor((innerWidth - root.pt(16)) / 2)
  }

  Component {
    id: airpodsGlyph
    AirPodsIcon {
      iconSize: root.pt(15)
      color: root.m.ink
      variant: root.airpodsVariant
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
    padding: root.pt(Apple.padding)
    cardColor: root.m.sheet
    borderSpec: Border.flat(root.m.hairline, 1)
    contentWidth: root.panelWidth + panel.padding * 2
    property real shownHeight: panel.fittedContentHeight(root.page === "main" ? content.implicitHeight : detail.implicitHeight)
    contentHeight: Math.round(heightSpring.value)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.page !== "main") root.goBack()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (root.page !== "main") { if (dx < 0) root.goBack(); return }
        if (dy !== 0) root.mainMoveCursor(dy)
        else if (dx !== 0) root.mainMoveHorizontal(dx)
      }
      onActivateRequested: root.mainActivate()
    }

    Item {
      id: pages
      anchors.fill: parent
      clip: true
      // apple-ui components find their palette and the reveal flag here.
      property var appleMaterial: mat
      property bool appleRevealed: root.revealed

      HUi.SpringValue {
        id: heightSpring
        preset: Motion.smooth
        epsilon: 0.3
        to: panel.shownHeight
        onToChanged: if (!root.heightAnimated) snap(to)
      }

      // ---- Main page (drill-in: 30 % parallax left + fade)
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

        // Row 1: Wi-Fi / Bluetooth stacked | Now Playing
        Row {
          spacing: root.gap
          Column {
            spacing: root.gap
            ToggleTile {
              revealIndex: 0
              icon: root.wifiOn ? root.sf(0x100647) : root.sf(0x100648)
              on: root.wifiOn
              title: "Wi-Fi"
              subtitle: !root.wifiOn ? "Off" : (root.wifiName !== "" ? root.wifiName : "Not connected")
              hasCursor: root.mainFocus === "wifi"
              onToggled: root.toggleWifi()
              onDetails: root.showPage("wifi")
            }
            ToggleTile {
              revealIndex: 1
              icon: root.btOn ? "󰂯" : "󰂲"
              iconFont: root.iconFont
              iconSize: root.ptr(19)
              on: root.btOn
              title: "Bluetooth"
              subtitle: !root.btOn ? "Off"
                : root.btConnected.length === 1 ? (root.btConnected[0].name || "1 device")
                : root.btConnected.length > 1 ? root.btConnected.length + " devices"
                : "On"
              hasCursor: root.mainFocus === "bluetooth"
              onToggled: root.toggleBluetooth()
              onDetails: root.showPage("bluetooth")
            }
          }

          // Now Playing (140 × 140): cover at (14,14), title/artist, transport at y 100.
          AUi.Tile {
            id: nowPlaying
            revealIndex: 2
            width: root.half
            height: root.half
            Rectangle {
              id: art
              x: root.pt(Apple.artInset); y: root.pt(Apple.artInset)
              width: root.pt(Apple.art); height: width
              radius: root.pt(Apple.radiusArt)
              color: root.m.artPlaceholder
              antialiasing: true
              clip: true
              AUi.Glyph {
                anchors.centerIn: parent
                visible: artImage.status !== Image.Ready
                text: root.sf(0x10046A)
                size: root.ptr(16)
                color: root.m.inkMuted
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
              x: root.pt(Apple.artInset)
              y: root.player ? root.pt(60) : root.pt(74)
              width: parent.width - x * 2
              spacing: 0
              Text {
                width: parent.width
                text: root.player ? (root.player.trackTitle || "Now Playing") : "Not Playing"
                color: root.m.ink
                font.family: root.uiFont
                font.pixelSize: root.pt(Apple.body)
                font.weight: Font.Medium
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                visible: root.player !== null
                text: root.player ? (root.player.trackArtist || root.player.identity || "") : ""
                color: root.m.inkSecondary
                font.family: root.uiFont
                font.pixelSize: root.pt(Apple.subheadline)
                elide: Text.ElideRight
              }
            }
            Row {
              x: root.pt(21); y: root.pt(Apple.transportY)
              spacing: root.pt(10)
              Repeater {
                model: [
                  { g: 0x10028A, action: "previous", main: false },
                  { g: root.playing ? 0x100286 : 0x100284, action: "playPause", main: true },
                  { g: 0x10028C, action: "next", main: false }
                ]
                delegate: Rectangle {
                  id: playBtn
                  required property var modelData
                  required property int index
                  width: root.pt(Apple.transport); height: width; radius: width / 2
                  color: playMouse.containsMouse && root.player ? root.m.badgeOff : "transparent"
                  Behavior on color {
                    ColorAnimation {
                      duration: playMouse.containsMouse ? Motion.instant : Motion.fast
                      easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
                    }
                  }
                  HUi.CrossfadeText {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    text: root.sf(modelData.g)
                    fontFamily: root.symbolFont
                    fontSize: root.ptr(modelData.main ? 20 : 15)
                    color: root.player || modelData.main ? root.m.ink : root.m.inkMuted
                  }
                  MouseArea {
                    id: playMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root.player !== null
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.media) root.media.runAction(modelData.action, false)
                  }
                  Rectangle {
                    anchors.fill: parent
                    radius: playBtn.radius
                    color: "transparent"
                    border.width: Math.max(2, root.pt(2))
                    border.color: root.m.cursorRing
                    opacity: root.mainFocus === "playback" && root.playbackCursorIndex === playBtn.index ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
                  }
                }
              }
            }
          }
        }

        // Row 2: AirDrop | Mac Input
        Row {
          spacing: root.gap
          ToggleTile {
            revealIndex: 3
            icon: root.sf(0x100319)
            on: root.localsendRunning
            title: "AirDrop"
            subtitle: root.localsendRunning ? "LocalSend active" : "LocalSend"
            hasCursor: root.mainFocus === "airdrop"
            onToggled: root.toggleAirdrop()
            onDetails: root.openAirdrop()
          }
          ToggleTile {
            revealIndex: 4
            icon: root.sf(0x100657)
            on: root.macOverall === "connected"
            squircle: true
            title: "Mac"
            subtitle: root.macOverallLabel
            hasCursor: root.mainFocus === "mac"
            badgeToggles: false
            onDetails: root.showPage("mac")
          }
        }

        // Icon row: Hardware, Experiments, Wi-Fi QR, speed test
        Row {
          spacing: root.gap
          AUi.IconTile {
            revealIndex: 5
            glyph: root.sf(0x1009D3); name: "Hardware"
            hasCursor: root.mainFocus === "hardware"
            onClicked: root.showPage("hardware")
          }
          AUi.IconTile {
            revealIndex: 5
            glyph: root.sf(0x10096E); name: "Experiments"
            hasCursor: root.mainFocus === "experiments"
            onClicked: root.showPage("experiments")
          }
          AUi.IconTile {
            revealIndex: 5
            glyph: root.sf(0x100582); name: "Share Wi-Fi as QR code"
            hasCursor: root.mainFocus === "qr"
            onClicked: root.openWifiQr()
          }
          AUi.IconTile {
            revealIndex: 5
            glyph: root.sf(0x10037E); name: "Speed test"
            hasCursor: root.mainFocus === "speedtest"
            onClicked: root.openSpeedTest()
          }
        }

        // Row 3: Text Size (A … A slider) | Layout (dwindle / scrolling)
        Row {
          spacing: root.gap
          AUi.Tile {
            revealIndex: 6
            width: root.half
            height: root.tileH
            hasCursor: root.mainFocus === "textsize"
            AUi.Title { x: root.pt(Apple.labelInset); y: root.pt(Apple.labelTop); text: "Text Size" }
            HUi.CrossfadeText {
              anchors.right: parent.right
              anchors.rightMargin: root.pt(Apple.labelInset)
              y: root.pt(Apple.labelTop)
              horizontalAlignment: Text.AlignRight
              text: root.textSizeStops[root.textSizeIndex] + " px"
              color: root.m.inkSecondary
              fontFamily: root.uiFont
              fontSize: root.pt(Apple.subheadline)
            }
            Text {
              x: root.pt(Apple.labelInset); y: root.pt(Apple.sliderY) - height / 2
              text: "A"
              color: root.m.ink
              font.family: root.uiFont
              font.pixelSize: root.pt(10)
            }
            AUi.Slider {
              x: root.pt(32); y: root.pt(Apple.sliderY) - height / 2
              width: root.half - root.pt(32) - root.pt(30)
              minimum: 0
              maximum: root.textSizeStops.length - 1
              stops: root.textSizeStops.length
              value: root.textSizeIndex
              onReleased: function(v) { root.setTextSizeIndex(v) }
            }
            Text {
              anchors.right: parent.right
              anchors.rightMargin: root.pt(Apple.labelInset) - root.pt(2)
              y: root.pt(Apple.sliderY) - height / 2
              text: "A"
              color: root.m.ink
              font.family: root.uiFont
              font.pixelSize: root.pt(17)
            }
          }
          AUi.Tile {
            revealIndex: 6
            width: root.half
            height: root.tileH
            hasCursor: root.mainFocus === "layout"
            AUi.Title { x: root.pt(Apple.labelInset); y: root.pt(Apple.labelTop); text: "Layout" }
            Row {
              x: root.pt(Apple.labelInset) - root.pt(2)
              y: root.pt(Apple.sliderY) - height / 2
              spacing: root.pt(6)
              readonly property int capW: Math.floor((root.half - root.pt(Apple.labelInset) * 2 + root.pt(4) - spacing) / 2)
              AUi.Capsule {
                width: parent.capW
                symbol: root.sf(0x100BEB)
                selected: root.tilingLayout === "dwindle"
                Accessible.role: Accessible.Button
                Accessible.name: "Dwindle layout"
                onClicked: root.setTilingLayout("dwindle")
              }
              AUi.Capsule {
                width: parent.capW
                symbol: root.sf(0x1003DF)
                selected: root.tilingLayout === "scrolling"
                Accessible.role: Accessible.Button
                Accessible.name: "Scrolling layout"
                onClicked: root.setTilingLayout("scrolling")
              }
            }
          }
        }

        // Display: brightness; the title chevron folds scale presets + monitors out.
        SliderTile {
          revealIndex: 7
          visible: root.brightnessAvailable || root.displays.length > 0
          heading: "Display"
          headingDetail: root.focusedDisplay && root.monitorScale && root.displayExpanded
            ? Display.looksLike(root.monitorScale, root.focusedDisplay.width, root.focusedDisplay.height) : ""
          leftGlyph: root.sf(0x1001AC)
          rightGlyph: root.sf(0x1001AE)
          value: root.brightness / 100
          sliderEnabled: root.brightnessAvailable
          expandable: root.displays.length > 0
          expanded: root.displayExpanded
          hasCursor: root.mainFocus === "display"
          onHeadingClicked: if (expandable) root.displayExpanded = !root.displayExpanded
          onMoved: function(v) { root.setBrightness(v * 100) }
          onLeftGlyphClicked: root.setBrightness(root.brightness - 10)
          onRightGlyphClicked: root.setBrightness(root.brightness + 10)

          AUi.SectionLabel {
            visible: root.focusedDisplay !== null
            leftPadding: 0
            text: "Scale" + (root.displays.length > 1 && root.focusedMonitor ? " · " + root.focusedMonitor : "")
          }
          Row {
            visible: root.focusedDisplay !== null
            width: parent.width
            spacing: root.pt(5)
            Repeater {
              model: root.scalePresets
              delegate: AUi.Capsule {
                required property string modelData
                width: Math.floor((parent.width - parent.spacing * (root.scalePresets.length - 1)) / Math.max(1, root.scalePresets.length))
                label: Display.formatScale(Display.cleanScale(modelData, root.focusedDisplay.width, root.focusedDisplay.height))
                selected: Display.isActiveScale(modelData, root.monitorScale, root.focusedDisplay.width, root.focusedDisplay.height)
                onClicked: if (!selected) root.setScale(modelData)
              }
            }
          }
          AUi.SectionLabel { visible: root.displays.length > 1; leftPadding: 0; text: "Monitors" }
          Repeater {
            model: root.displays.length > 1 ? root.displays : []
            delegate: Item {
              required property var modelData
              width: parent.width
              height: root.pt(28)
              opacity: modelData.enabled && root.enabledDisplayCount <= 1 ? Motion.disabledOpacity : 1
              Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: root.pt(8)
                AUi.Glyph {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.sf(0x1008B9)
                  size: root.ptr(12)
                  color: modelData.focused ? root.m.ink : root.m.inkMuted
                }
                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: modelData.name + (modelData.width ? "   " + modelData.width + " × " + modelData.height : "")
                  color: root.m.ink
                  font.family: root.uiFont
                  font.pixelSize: root.pt(Apple.subheadline)
                }
              }
              AUi.Capsule {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: root.pt(52)
                label: modelData.enabled ? "On" : "Off"
                selected: modelData.enabled
                onClicked: root.toggleDisplay(modelData)
              }
            }
          }
        }

        // Sound: volume; the title (AirPods name while connected) opens the page,
        // the AirPlay-style circle picks the output.
        AUi.Tile {
          id: soundTile
          revealIndex: 8
          visible: root.sink !== null
          width: root.panelWidth
          height: root.tileH
          hasCursor: root.mainFocus === "sound"
          Item {
            x: root.pt(Apple.labelInset); y: root.pt(Apple.labelTop)
            width: parent.width - x * 2
            height: soundTitle.implicitHeight
            Loader {
              id: soundGlyph
              anchors.verticalCenter: parent.verticalCenter
              active: root.airpodsActive
              sourceComponent: airpodsGlyph
              width: active ? root.pt(20) : 0
            }
            HUi.CrossfadeText {
              id: soundTitle
              anchors.left: soundGlyph.right
              text: root.airpodsActive ? root.airpodsName : "Sound"
              color: root.m.ink
              fontFamily: root.uiFont
              fontSize: root.pt(Apple.headline)
              fontWeight: Font.Bold
            }
            HUi.CrossfadeText {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              horizontalAlignment: Text.AlignRight
              text: root.airpodsActive && root.airpodsLevel >= 0 ? root.airpodsLevel + " %" : ""
              color: root.m.inkSecondary
              fontFamily: root.uiFont
              fontSize: root.pt(Apple.subheadline)
            }
            MouseArea {
              anchors.fill: parent
              anchors.margins: -root.pt(4)
              cursorShape: Qt.PointingHandCursor
              onClicked: root.showPage(root.airpodsActive ? "airpods" : "sound")
            }
          }
          AUi.Glyph {
            x: root.ptr(16.5); y: root.pt(Apple.sliderY) - height / 2
            text: root.muted || root.volume === 0 ? root.sf(0x1002A3) : root.sf(0x1002A5)
            size: root.ptr(14)
            MouseArea { anchors.fill: parent; anchors.margins: -root.pt(4); cursorShape: Qt.PointingHandCursor; onClicked: root.toggleMute() }
          }
          AUi.Slider {
            x: root.pt(34); y: root.pt(Apple.sliderY) - height / 2
            width: root.pt(180)
            value: root.muted ? 0 : Math.min(1, root.volume)
            onMoved: function(v) { root.setVolume(v) }
          }
          AUi.Glyph {
            x: root.ptr(220.5); y: root.pt(Apple.sliderY) - height / 2
            text: root.sf(0x1002A9)
            size: root.ptr(16)
            MouseArea { anchors.fill: parent; anchors.margins: -root.pt(4); cursorShape: Qt.PointingHandCursor; onClicked: root.setVolume(1) }
          }
          AUi.IconButton {
            x: root.pt(252); y: root.pt(Apple.sliderY) - height / 2
            width: root.pt(Apple.airplay)
            icon: root.sf(0x10074E)
            name: "Sound output"
            onClicked: root.showPage("sound")
          }
        }

        // Plugins … — the capsule at the foot, where macOS keeps "Edit Controls".
        Item {
          width: root.panelWidth
          height: root.pt(Apple.capsuleH) + root.pt(Apple.capsuleGap - Apple.gap)
          AUi.Capsule {
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.pt(Apple.capsuleGap - Apple.gap)
            width: root.pt(Apple.capsuleW)
            label: "Plugins …"
            Accessible.role: Accessible.Button
            Accessible.name: "Plugins"
            onClicked: root.openPluginManager()
            Rectangle {
              anchors.fill: parent
              radius: parent.radius
              color: "transparent"
              border.width: Math.max(2, root.pt(2))
              border.color: root.m.cursorRing
              opacity: root.mainFocus === "plugins" ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
            }
          }
        }
      }

      // ---- Detail pages (slide in from the right)
      Column {
        id: detail
        width: root.panelWidth
        spacing: root.pt(4)
        readonly property bool current: root.page !== "main"
        visible: opacity > 0.01
        opacity: current ? 1 : 0
        x: current || Motion.reduceMotion ? 0 : root.panelWidth
        Behavior on opacity { NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }
        Behavior on x { enabled: root.heightAnimated; NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }

        // Wi-Fi
        AUi.PageHeader {
          visible: root.detailPage === "wifi"
          title: "Wi-Fi"
          showSwitch: true
          checked: root.wifiOn
          onToggled: root.toggleWifi()
          onBack: root.page = "main"
        }
        AUi.Separator { visible: root.detailPage === "wifi" }
        AUi.SectionLabel {
          visible: root.detailPage === "wifi" && root.wifiOn
          text: root.wifiRows.length ? "Networks" : "Searching for networks …"
        }
        AUi.SectionLabel { visible: root.detailPage === "wifi" && !root.wifiOn; text: "Wi-Fi is off" }
        Flickable {
          visible: root.detailPage === "wifi" && root.wifiOn
          width: root.panelWidth
          height: Math.min(wifiList.implicitHeight, root.pt(Apple.rowH) * (root.wifiAdvanced ? 4 : 8))
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
                AUi.ListRow {
                  enterDelay: root.rowDelay(index)
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
                Item {
                  id: credBox
                  readonly property bool wanted: root.wifiPasswordFor === modelData.name
                  readonly property bool enterprise: !!modelData.enterprise
                  readonly property bool rejected: root.wifiFailed === modelData.name
                  visible: height > 0.5
                  x: root.pt(44)
                  width: root.panelWidth - root.pt(50)
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
                    spacing: root.pt(6)
                    transform: Translate { id: credShift }
                    AUi.TextField {
                      id: userField
                      visible: credBox.enterprise
                      placeholder: "Username"
                      error: credBox.rejected
                      nextField: passField.input
                      onSubmitted: credBox.submit()
                      onCancelled: root.wifiPasswordFor = ""
                      onEdited: credBox.clearError()
                    }
                    AUi.TextField {
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

        // Advanced options
        Rectangle {
          visible: root.detailPage === "wifi" && root.wifiOn
          width: root.panelWidth
          height: advancedColumn.implicitHeight
          radius: root.pt(Apple.radiusRow)
          color: root.wifiAdvanced ? root.m.tile : Qt.rgba(root.m.tile.r, root.m.tile.g, root.m.tile.b, 0)
          border.width: root.wifiAdvanced ? 1 : 0
          border.color: root.m.hairline
          clip: true
          Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
          Behavior on height { enabled: root.heightAnimated; NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
          Column {
            id: advancedColumn
            width: parent.width
            Item {
              width: parent.width
              height: root.pt(36)
              Text {
                anchors.left: parent.left
                anchors.leftMargin: root.pt(12)
                anchors.verticalCenter: parent.verticalCenter
                text: "Advanced Options"
                color: advMouse.containsMouse ? root.m.ink : root.m.inkMuted
                font.family: root.uiFont
                font.pixelSize: root.pt(Apple.body)
                Behavior on color {
                  ColorAnimation {
                    duration: advMouse.containsMouse ? Motion.instant : Motion.fast
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
                  }
                }
              }
              Text {
                anchors.right: parent.right
                anchors.rightMargin: root.pt(14)
                anchors.verticalCenter: parent.verticalCenter
                text: root.sf(0x10018A)
                rotation: root.wifiAdvanced ? 90 : 0
                color: root.m.inkMuted
                font.family: root.symbolFont
                font.pixelSize: root.pt(12)
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
              leftPadding: root.pt(12)
              rightPadding: root.pt(12)
              bottomPadding: root.pt(12)
              spacing: root.pt(8)
              transform: Translate {
                y: root.wifiAdvanced || Motion.reduceMotion ? 0 : -root.pt(10)
                Behavior on y { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
              }
              Behavior on opacity {
                NumberAnimation {
                  duration: root.wifiAdvanced ? Motion.base : Motion.exit(Motion.fast)
                  easing.type: Easing.BezierSpline
                  easing.bezierCurve: root.wifiAdvanced ? Motion.easeOut : Motion.easeExit
                }
              }
              readonly property int innerWidth: root.panelWidth - root.pt(24)

              Item {
                width: parent.innerWidth
                height: root.pt(34)
                Column {
                  anchors.left: parent.left
                  anchors.right: advButtons.left
                  anchors.verticalCenter: parent.verticalCenter
                  AUi.Title { width: parent.width; text: root.netConnected ? (root.netInfo.ssid || root.wifiName || root.netInfo.iface) : "Not connected" }
                  Text {
                    width: parent.width
                    visible: text !== ""
                    text: [Net.formatFreq(root.netInfo.freq), root.netInfo.bitrate || "",
                           root.netInfo.signal_dbm ? root.netInfo.signal_dbm + " dBm" : ""]
                          .filter(function(t) { return t !== "" }).join(" · ")
                    color: root.m.inkMuted
                    font.family: root.uiFont
                    font.pixelSize: root.pt(Apple.footnote)
                    elide: Text.ElideRight
                  }
                }
                Row {
                  id: advButtons
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: root.pt(6)
                  AUi.IconButton { visible: root.netInfo.type === "wifi"; icon: root.sf(0x100582); name: "Share as QR code"; onClicked: root.openWifiQr() }
                  AUi.IconButton { icon: root.sf(0x10037E); name: "Speed test"; onClicked: root.openSpeedTest() }
                }
              }
              AUi.Separator { width: parent.innerWidth }
              Grid {
                columns: 2
                columnSpacing: root.pt(16)
                rowSpacing: root.pt(2)
                readonly property bool hasPings: root.internetPings.length > 0
                readonly property int cellWidth: Math.floor((parent.innerWidth - root.pt(16)) / 2)
                AUi.Stat { width: parent.cellWidth; label: "Ping"; value: Net.formatPing(Net.averageLatency(root.internetPings, 5)) }
                AUi.Stat { width: parent.cellWidth; label: "Packet loss"; value: parent.hasPings ? Net.packetLoss(root.internetPings) + " %" : "--" }
                AUi.Stat { width: parent.cellWidth; label: "Download"; value: Net.formatRate(root.netDownRate) }
                AUi.Stat { width: parent.cellWidth; label: "Upload"; value: Net.formatRate(root.netUpRate) }
                AUi.Stat { width: parent.cellWidth; label: "Received"; value: Net.formatBytes(root.netInfo.rx_bytes) }
                AUi.Stat { width: parent.cellWidth; label: "Sent"; value: Net.formatBytes(root.netInfo.tx_bytes) }
                AUi.Stat { width: parent.cellWidth; label: "IP"; value: root.netInfo.ip || "--" }
                AUi.Stat { width: parent.cellWidth; label: "Gateway"; value: root.netInfo.gateway || "--" }
                AUi.Stat { width: parent.cellWidth; label: "Router ping"; value: Net.formatPing(Net.averageLatency(root.routerPings, 5)) }
                AUi.Stat { width: parent.cellWidth; label: "Interface"; value: root.netInfo.iface || "--" }
              }
              AUi.SectionLabel {
                visible: root.bandInfo.available.length > 0 && root.netInfo.type === "wifi"
                leftPadding: 0
                text: "Wi-Fi band" + (root.bandInfo.band ? " · current " + Net.bandLabel(root.bandInfo.band) : "")
              }
              Row {
                visible: root.bandInfo.available.length > 0 && root.netInfo.type === "wifi"
                spacing: root.pt(5)
                readonly property var options: ["auto"].concat(root.bandInfo.available)
                Repeater {
                  model: parent.options
                  delegate: AUi.Capsule {
                    required property string modelData
                    width: Math.floor((root.panelWidth - root.pt(24) - root.pt(5) * 3) / 4)
                    label: root.bandPending === modelData ? "…" : Net.bandLabel(modelData)
                    selected: root.bandInfo.selected === modelData
                    onClicked: root.setBand(modelData)
                  }
                }
              }
              AUi.SectionLabel { leftPadding: 0; text: "DNS provider" }
              Row {
                spacing: root.pt(5)
                Repeater {
                  model: [
                    { id: "DHCP", label: "DHCP" },
                    { id: "Cloudflare", label: "Cloudflare" },
                    { id: "Google", label: "Google" },
                    { id: "Custom", label: "Custom" }
                  ]
                  delegate: AUi.Capsule {
                    required property var modelData
                    width: Math.floor((root.panelWidth - root.pt(24) - root.pt(5) * 3) / 4)
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
        AUi.PageHeader {
          visible: root.detailPage === "bluetooth"
          title: "Bluetooth"
          showSwitch: true
          checked: root.btOn
          onToggled: root.toggleBluetooth()
          onBack: root.page = "main"
        }
        AUi.Separator { visible: root.detailPage === "bluetooth" }
        AUi.SectionLabel {
          visible: root.detailPage === "bluetooth" && root.btOn
          text: root.btRows.length ? "Devices" : "Searching for devices …"
        }
        AUi.SectionLabel { visible: root.detailPage === "bluetooth" && !root.btOn; text: "Bluetooth is off" }
        Flickable {
          visible: root.detailPage === "bluetooth" && root.btOn
          width: root.panelWidth
          height: Math.min(btList.implicitHeight, root.pt(Apple.rowH) * 8)
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
              delegate: AUi.ListRow {
                required property var modelData
                required property int index
                enterDelay: root.rowDelay(index)
                busy: !!root.btPending[modelData.address]
                icon: root.btIcon(modelData.icon)
                iconFont: root.btIconFont(modelData.icon)
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
        AUi.PageHeader { visible: root.detailPage === "sound"; title: "Sound"; onBack: root.page = "main" }
        AUi.Separator { visible: root.detailPage === "sound" }
        VolumeRow { visible: root.detailPage === "sound" && root.sink !== null }
        AUi.SectionLabel { visible: root.detailPage === "sound"; text: "Output" }
        Repeater {
          model: root.detailPage === "sound" ? root.sinkRows : []
          delegate: AUi.ListRow {
            required property var modelData
            required property int index
            enterDelay: root.rowDelay(index)
            icon: root.sinkIcon(modelData.label)
            active: modelData.active
            title: modelData.label
            trailing: modelData.active ? root.sf(0x100185) : " "
            onClicked: if (!modelData.active) root.setSink(modelData)
          }
        }
        AUi.ListRow {
          visible: root.detailPage === "sound" && pods.daemonReachable && !pods.connected && pods.deviceName !== ""
          icon: root.sf(0xF1852)
          iconFont: root.iconFont
          title: root.airpodsName
          subtitle: pods.connectionBusy ? "Connecting …" : pods.actionStatus !== "" ? pods.actionStatus : "Not connected"
          busy: pods.connectionBusy
          onClicked: pods.toggleConnection()
        }

        // AirPods
        AUi.PageHeader { visible: root.detailPage === "airpods"; title: root.airpodsName; onBack: root.page = "main" }
        AUi.Separator { visible: root.detailPage === "airpods" }
        Flickable {
          visible: root.detailPage === "airpods"
          width: root.panelWidth
          height: Math.min(podsPage.implicitHeight, Math.max(root.pt(240), panel.availableCardHeight - root.pt(80)))
          contentHeight: podsPage.implicitHeight
          clip: true
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds
          flickDeceleration: Motion.flickDeceleration
          maximumFlickVelocity: Motion.maximumFlickVelocity
          Column {
            id: podsPage
            width: root.panelWidth
            spacing: root.pt(4)
            Row {
              x: root.pt(6)
              topPadding: root.pt(6)
              bottomPadding: root.pt(4)
              Repeater {
                model: root.airpodsBatteries
                delegate: PodBattery {
                  required property var modelData
                  width: Math.floor((root.panelWidth - root.pt(12)) / root.airpodsBatteries.length)
                  label: modelData.label
                  level: modelData.level
                  charging: modelData.charging
                }
              }
            }
            VolumeRow {}
            AUi.Caption {
              visible: text !== ""
              width: root.panelWidth
              leftPadding: root.pt(6)
              rightPadding: root.pt(6)
              text: pods.actionStatus !== "" ? pods.actionStatus : pods.lastError
              color: root.m.urgent
            }
            AUi.SectionLabel { visible: root.airpodsModes.length > 0; text: "Listening Mode" }
            Repeater {
              model: root.detailPage === "airpods" ? root.airpodsModes : []
              delegate: AUi.ListRow {
                required property var modelData
                required property int index
                enterDelay: root.rowDelay(index)
                icon: root.noiseModeIcon(modelData)
                iconFont: root.iconFont
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
                topPadding: root.pt(2)
                bottomPadding: root.pt(6)
                spacing: root.pt(2)
                Item {
                  width: root.panelWidth
                  height: adaptiveLabel.implicitHeight
                  Text {
                    id: adaptiveLabel
                    x: root.pt(14)
                    text: "Adaptive noise level"
                    color: root.m.inkMuted
                    font.family: root.uiFont
                    font.pixelSize: root.pt(Apple.footnote)
                  }
                  HUi.CrossfadeText {
                    anchors.right: parent.right
                    anchors.rightMargin: root.pt(16)
                    horizontalAlignment: Text.AlignRight
                    text: pods.adaptiveNoiseLevel + " %"
                    color: root.m.inkMuted
                    fontFamily: root.uiFont
                    fontSize: root.pt(Apple.footnote)
                  }
                }
                AUi.Slider {
                  x: root.pt(14)
                  width: root.panelWidth - root.pt(30)
                  value: pods.adaptiveNoiseLevel / 100
                  onMoved: function(v) { pods.setAdaptiveNoiseLevel(v * 100) }
                }
              }
            }
            AUi.SwitchRow {
              visible: pods.supportsConversationalAwareness
              title: "Conversation Awareness"
              caption: "Lowers the volume when you start talking"
              checked: pods.conversationalAwareness
              onToggled: function(on) { pods.setConversationalAwareness(on) }
            }
            AUi.SwitchRow {
              visible: pods.supportsOneBudANC
              title: "One-Bud Noise Cancellation"
              caption: "Keeps the mode on with only one AirPod in"
              checked: pods.oneBudANC
              onToggled: function(on) { pods.setOneBudANC(on) }
            }
            AUi.SectionLabel { text: "Pause Media When Removed" }
            Row {
              x: root.pt(6)
              spacing: root.pt(6)
              topPadding: root.pt(2)
              bottomPadding: root.pt(4)
              Repeater {
                model: [
                  { label: "One AirPod", value: Pods.EAR_PAUSE_ONE_OUT },
                  { label: "Both", value: Pods.EAR_PAUSE_BOTH_OUT },
                  { label: "Never", value: Pods.EAR_DISABLED }
                ]
                delegate: AUi.Capsule {
                  required property var modelData
                  width: Math.floor((root.panelWidth - root.pt(24)) / 3)
                  label: modelData.label
                  selected: pods.earDetectionBehavior === modelData.value
                  onClicked: pods.setEarDetectionBehavior(modelData.value)
                }
              }
            }
            AUi.Separator {}
            Item {
              width: root.panelWidth
              height: root.pt(30)
              AUi.Link {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: pods.connectionRequest === "disconnect" ? "Disconnecting …" : "Disconnect"
                onClicked: if (!pods.busy) pods.toggleConnection()
              }
              AUi.Link {
                anchors.right: parent.right
                anchors.rightMargin: root.pt(6)
                anchors.verticalCenter: parent.verticalCenter
                text: "Sound Output …"
                onClicked: root.showPage("sound")
              }
            }
          }
        }

        // Experiments
        AUi.PageHeader { visible: root.detailPage === "experiments"; title: "Experiments"; onBack: root.page = "main" }
        AUi.Separator { visible: root.detailPage === "experiments" }
        Column {
          visible: root.detailPage === "experiments"
          width: root.panelWidth
          AUi.SectionLabel { text: "Control Center material" }
          AUi.SwitchRow {
            title: "Dark glass"
            caption: "Measured " + backdrop.luma.toFixed(2) + " · dark below " + backdrop.threshold.toFixed(2)
            checked: backdrop.dark
            onToggled: function(on) { backdrop.set(on ? 0 : 1) }
          }
          AUi.Caption {
            x: root.pt(12)
            topPadding: root.pt(4)
            bottomPadding: root.pt(10)
            width: root.panelWidth - root.pt(24)
            text: "Follows the wallpaper under the panel, like macOS. This switch forces it until the next wallpaper change."
          }
          AUi.SectionLabel { text: "Rendering" }
          AUi.SwitchRow {
            title: "Low-power rendering"
            caption: root.renderPowerBusy
              ? "Reloading Hyprland…"
              : root.renderPowerOn
                ? "Direct scanout · " + (root.renderPower.passes || "2") + " blur passes · CM off"
                : "Direct scanout, 2 blur passes, no CM pass"
            checked: root.renderPowerOn
            onToggled: function(on) { root.setRenderPower(on) }
          }
          AUi.Caption {
            x: root.pt(12)
            topPadding: root.pt(4)
            bottomPadding: root.pt(10)
            width: root.panelWidth - root.pt(24)
            text: "Lets the GPU idle between frames: fullscreen video goes straight to the display, and the bar and dock blur a little less deep. Reloads Hyprland when switched."
          }
        }

        // Hardware
        AUi.PageHeader { visible: root.detailPage === "hardware"; title: "Hardware"; onBack: root.page = "main" }
        AUi.Separator { visible: root.detailPage === "hardware" }
        PageBody {
          id: hwPage
          visible: root.detailPage === "hardware"
          function meterColor(f) { return f >= 0.9 ? root.m.urgent : root.m.accent }
          AUi.Caption {
            visible: text !== ""
            width: hwPage.innerWidth
            text: root.hw.model + (root.hw.cores > 0 ? " · " + root.hw.cores + " cores / " + root.hw.threads + " threads" : "")
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
          }
          AUi.UsageHeader { width: hwPage.innerWidth; title: "CPU"; value: root.cpuLoad >= 0 ? root.cpuLoad + " %" : "--" }
          AUi.Meter { width: hwPage.innerWidth; fraction: root.cpuLoad / 100; fillColor: hwPage.meterColor(root.cpuLoad / 100) }
          Grid {
            columns: 2
            columnSpacing: root.pt(16)
            rowSpacing: root.pt(2)
            topPadding: root.pt(2)
            AUi.Stat { width: hwPage.cellWidth; label: "Clock"; value: root.formatGHz(root.hw.freqAvg) }
            AUi.Stat { width: hwPage.cellWidth; label: "Fastest core"; value: root.formatGHz(root.hw.freqPeak) }
            AUi.Stat { width: hwPage.cellWidth; label: "Max clock"; value: root.formatGHz(root.hw.freqMax) }
            AUi.Stat { width: hwPage.cellWidth; label: "Load (1 min)"; value: Number(root.hw.load1).toFixed(2) }
            AUi.Stat { width: hwPage.cellWidth; label: "Temperature"; value: root.hw.temp >= 0 ? root.hw.temp + " °C" : "--" }
            Repeater {
              model: root.hw.fans
              delegate: AUi.Stat {
                required property var modelData
                width: hwPage.cellWidth
                label: modelData.label
                value: modelData.rpm > 0 ? modelData.rpm + " rpm" : "Idle"
              }
            }
          }
          AUi.Separator { width: hwPage.innerWidth }
          AUi.UsageHeader {
            width: hwPage.innerWidth
            title: "Memory"
            value: root.hw.memTotal > 0
              ? root.formatGiB(root.hw.memTotal - root.hw.memAvail, 1) + " of " + root.formatGiB(root.hw.memTotal, 1) + " GB"
              : "--"
          }
          AUi.Meter { width: hwPage.innerWidth; fraction: root.memUsedFrac; fillColor: hwPage.meterColor(root.memUsedFrac) }
          Grid {
            columns: 2
            columnSpacing: root.pt(16)
            rowSpacing: root.pt(2)
            topPadding: root.pt(2)
            AUi.Stat { width: hwPage.cellWidth; label: "Used"; value: Math.round(root.memUsedFrac * 100) + " %" }
            AUi.Stat { width: hwPage.cellWidth; label: "Available"; value: root.formatGiB(root.hw.memAvail, 1) + " GB" }
            AUi.Stat { width: hwPage.cellWidth; label: "Swap"; value: root.hw.swapTotal > 0 ? root.formatGiB(root.hw.swapTotal - root.hw.swapFree, 1) + " GB" : "Off" }
            AUi.Stat { width: hwPage.cellWidth; label: "Swap size"; value: root.hw.swapTotal > 0 ? root.formatGiB(root.hw.swapTotal, 0) + " GB" : "--" }
          }
          AUi.Separator { width: hwPage.innerWidth }
          AUi.UsageHeader {
            width: hwPage.innerWidth
            title: "Disk"
            value: root.hw.diskTotal > 0 ? root.formatBytesGB(root.hw.diskUsed) + " of " + root.formatBytesGB(root.hw.diskTotal) : "--"
          }
          AUi.Meter { width: hwPage.innerWidth; fraction: root.diskUsedFrac; fillColor: hwPage.meterColor(root.diskUsedFrac) }
          Grid {
            columns: 2
            columnSpacing: root.pt(16)
            topPadding: root.pt(2)
            AUi.Stat { width: hwPage.cellWidth; label: "Free"; value: root.formatBytesGB(root.hw.diskTotal - root.hw.diskUsed) }
            AUi.Stat { width: hwPage.cellWidth; label: "Uptime"; value: root.hw.uptime > 0 ? root.formatUptime(root.hw.uptime) : "--" }
          }
        }

        // Mac — everything this machine borrows from the MacBook, one row each.
        AUi.PageHeader { visible: root.detailPage === "mac"; title: "Mac"; onBack: root.page = "main" }
        AUi.Separator { visible: root.detailPage === "mac" }
        PageBody {
          id: macPage
          visible: root.detailPage === "mac"
          spacing: root.pt(10)
          AUi.UsageHeader {
            width: macPage.innerWidth
            title: "Right now"
            value: root.macOverallLabel
            valueColor: root.macOverall === "connected" ? root.m.accent
              : root.macOverall === "unreachable" ? root.m.urgent : root.m.inkMuted
          }
          AUi.Caption { width: macPage.innerWidth; text: root.macOverallDetail }

          AUi.Separator { width: macPage.innerWidth }
          AUi.SectionLabel { leftPadding: 0; text: "Mode" }
          Row {
            width: macPage.innerWidth
            spacing: root.pt(5)
            Repeater {
              model: [ { id: "auto", label: "Auto" }, { id: "server", label: "Server" }, { id: "desktop", label: "Desktop" } ]
              delegate: AUi.Capsule {
                required property var modelData
                width: Math.floor((macPage.innerWidth - root.pt(10)) / 3)
                label: modelData.label
                selected: root.macModePinShown === modelData.id
                onClicked: if (!selected) root.setMacMode(modelData.id)
              }
            }
          }
          AUi.Caption {
            width: macPage.innerWidth
            text: "Auto follows the Mac's own monitor: attached → Desktop, unplugged → Server. "
              + "Server/Desktop here pin it regardless. "
              + (root.macModeFresh
                 ? root.macModeDisplays + " display" + (root.macModeDisplays === 1 ? "" : "s") + " detected."
                 : "No recent answer to say which.")
          }

          AUi.Separator { width: macPage.innerWidth }
          AUi.SectionLabel { leftPadding: 0; text: "More" }
          AUi.ListRow {
            enterDelay: root.rowDelay(0)
            icon: root.sf(0x100A33)
            active: root.padOn
            title: "Mac Input"
            subtitle: root.padSubtitle
            trailing: root.sf(0x10018A)
            onClicked: root.showPage("trackpad")
          }
          AUi.ListRow {
            enterDelay: root.rowDelay(1)
            icon: root.sf(0x1008B9)
            active: root.screenOn
            title: "Mac Screen"
            subtitle: root.screenSubtitle
            trailing: root.sf(0x10018A)
            onClicked: root.showPage("screen")
          }
          Item { width: 1; height: root.pt(4) }
        }

        // Mac Screen
        AUi.PageHeader { visible: root.detailPage === "screen"; title: "Mac Screen"; onBack: root.page = "mac" }
        AUi.Separator { visible: root.detailPage === "screen" }
        PageBody {
          id: screenPage
          visible: root.detailPage === "screen"
          AUi.UsageHeader {
            width: screenPage.innerWidth
            title: "Mirror"
            value: root.screenOn ? (root.screenRoute !== "" ? "Over " + root.screenRoute : "Mirroring") : "Off"
            valueColor: root.screenOn ? root.m.accent : root.m.inkMuted
          }
          AUi.Caption {
            width: screenPage.innerWidth
            text: root.screenOn
                ? "The Mac is capturing its own screen and sending it here. Nothing on it had to be clicked."
              : root.padLinkUp
                ? "Cable is up. Turning this on opens the mirror."
                : "No cable. It will fall back to Wi-Fi, which costs delay and drops frames."
          }
          Row {
            spacing: root.pt(6)
            AUi.Button {
              text: root.screenOn ? "Show window" : "Open mirror"
              prominent: !root.screenOn
              onClicked: root.launchMacScreen()
            }
            AUi.Button {
              visible: root.screenOn
              text: "Close"
              onClicked: root.run("kill " + (root.screenState.pid || 0))
            }
          }
          AUi.Separator { width: screenPage.innerWidth }
          AUi.SectionLabel { leftPadding: 0; text: "Stream" }
          Grid {
            columns: 2
            columnSpacing: root.pt(16)
            rowSpacing: root.pt(2)
            AUi.Stat { width: screenPage.cellWidth; label: "Route"; value: root.screenRoute !== "" ? root.screenRoute : "--" }
            AUi.Stat { width: screenPage.cellWidth; label: "Source"; value: root.screenState.host || "--" }
            AUi.Stat { width: screenPage.cellWidth; label: "Port"; value: root.screenState.port || "--" }
            AUi.Stat { width: screenPage.cellWidth; label: "Decoder"; value: root.screenState.decoder || "--" }
            AUi.Stat {
              width: screenPage.cellWidth
              label: "Running"
              value: root.screenOn && Number(root.screenState.started || 0) > 0
                ? root.formatUptime(Math.max(0, Math.floor(Date.now() / 1000 - Number(root.screenState.started))))
                : "--"
            }
          }
        }

        // Mac Input
        AUi.PageHeader {
          visible: root.detailPage === "trackpad"
          title: "Mac Input"
          showSwitch: true
          checked: root.padOn
          onToggled: root.toggleTrackpad()
          onBack: root.page = "mac"
        }
        AUi.Separator { visible: root.detailPage === "trackpad" }
        PageBody {
          id: padPage
          visible: root.detailPage === "trackpad"
          AUi.UsageHeader {
            width: padPage.innerWidth
            title: "Connection"
            value: (!root.padBridgeUp ? "Off"
              : root.padStreaming ? (root.padTransport !== "" ? root.padTransport : "Connected")
              : root.padLinked ? "Idle"
              : "Not connected")
              + (root.padButton ? " · click" : "")
              + (root.padKeysHeld > 0 ? " · " + root.padKeysHeld + " key" + (root.padKeysHeld === 1 ? "" : "s") : "")
            valueColor: root.padStreaming ? root.m.accent
              : !root.padBridgeUp || root.padLinked ? root.m.inkMuted : root.m.urgent
          }
          AUi.Caption {
            width: padPage.innerWidth
            text: !root.padBridgeUp
                ? "The receiver is not running."
              : root.padStreaming
                ? "Fingers are arriving from " + (root.padStream.source || "the Mac") + "."
              : root.padLinked
                ? "The Mac is connected over " + (root.padTransport || "the link") + " and waiting for a touch."
              : root.padLinkUp
                ? "Cable is up, but the Mac isn't answering. Check that mtsend is running there."
                : "Not connected. Plug the cable in, or start mtsend on the Mac."
          }
          AUi.Separator { width: padPage.innerWidth }
          AUi.SectionLabel { leftPadding: 0; text: "Cable" }
          Grid {
            columns: 2
            columnSpacing: root.pt(16)
            rowSpacing: root.pt(2)
            AUi.Stat { width: padPage.cellWidth; label: "Link"; value: root.padLinkUp ? "Up" : "Down" }
            AUi.Stat { width: padPage.cellWidth; label: "Interface"; value: root.padLink["interface"] || "--" }
            AUi.Stat { width: padPage.cellWidth; label: "Address"; value: root.padLink.address || "--" }
            AUi.Stat { width: padPage.cellWidth; label: "Ethernet in"; value: root.padLink.rx_frames || "--" }
          }
          AUi.Separator { width: padPage.innerWidth }
          AUi.SectionLabel { leftPadding: 0; text: "Stream" }
          Grid {
            columns: 2
            columnSpacing: root.pt(16)
            rowSpacing: root.pt(2)
            AUi.Stat { width: padPage.cellWidth; label: "Mac"; value: !root.padBridgeUp ? "--" : root.padLinked ? "Connected" : "Not connected" }
            AUi.Stat { width: padPage.cellWidth; label: "Route"; value: root.padTransport !== "" ? root.padTransport : "--" }
            AUi.Stat { width: padPage.cellWidth; label: "Source"; value: root.padStream.source || "--" }
            AUi.Stat { width: padPage.cellWidth; label: "Fingers"; value: root.padStreaming ? String(root.padStream.contacts || 0) : "--" }
            AUi.Stat { width: padPage.cellWidth; label: "Button"; value: !root.padStreaming ? "--" : root.padButton ? "Pressed" : "Released" }
            AUi.Stat { width: padPage.cellWidth; label: "Touch frames"; value: root.padStream.frames || "--" }
          }
          AUi.Separator { width: padPage.innerWidth }
          AUi.SectionLabel { leftPadding: 0; text: "Keyboard" }
          Grid {
            columns: 2
            columnSpacing: root.pt(16)
            rowSpacing: root.pt(2)
            AUi.Stat { width: padPage.cellWidth; label: "Device"; value: root.padKeyboard ? "Present" : "Off" }
            AUi.Stat { width: padPage.cellWidth; label: "Held"; value: root.padBridgeUp ? String(root.padKeysHeld) : "--" }
            AUi.Stat { width: padPage.cellWidth; label: "Key events"; value: root.padStream.key_events || "--" }
          }
          AUi.Caption {
            width: padPage.innerWidth
            text: "Keys map by position: this machine's layout decides the character. Both hotkeys stay on the Mac."
          }
        }

      }
    }
  }
}
