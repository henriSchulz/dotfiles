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

// macOS Big Sur-style Control Center. This was henri-ui's sandbox for the
// Big Sur direction — built as a private fork of Motion.js/HUi.* so it could
// experiment without disturbing the shared library or its other consumers.
// That experiment is done: the glass tokens, radii and uiFont it proved out
// live in the shared henri-ui now, and this plugin is back to importing it
// like everyone else.
//
// Everything else here drives the same backends the stock panels use
// (Quickshell.Networking, Bluetooth, Pipewire, the shell's media service,
// omarchy-brightness-display), so state stays in sync with the bar icons and
// the detail panels. Clicking a tile's round icon toggles it; clicking its
// label opens the stock detail panel, like the chevron in macOS.
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
  // The tiles are frosted rather than a wash of the foreground: the panel's
  // own colour again, so they stay lighter than what shows through it (macOS
  // Control Center) and a dark theme still gets dark tiles. The Hyprland blur
  // on this popup's namespace (looknfeel.lua) is what makes it read as glass.
  readonly property color tileColor: Motion.glass
    ? Util.alpha(Color.popups.background, Motion.glassTileAlpha)
    : Qt.rgba(fg.r, fg.g, fg.b, 0.07)
  readonly property color tileHover: Motion.glass
    ? Util.alpha(Color.popups.background, Motion.glassTileHoverAlpha)
    : Qt.rgba(fg.r, fg.g, fg.b, 0.11)
  readonly property color circleOff: Qt.rgba(fg.r, fg.g, fg.b, 0.14)
  readonly property color circleOn: Color.accent
  // Glyphs/text on the accent fill: white or black by contrast.
  readonly property color onIcon: Motion.onColor(circleOn)
  // Secondary text: foreground at henri-ui's secondary alpha (not a darkened fg / muted).
  readonly property color dimText: Util.alpha(fg, Motion.secondaryTextAlpha)
  readonly property string iconFont: bar ? bar.fontFamily : root.uiFont
  // SF Symbols (local font only, not in the repo). Bluetooth has no SF symbol → Nerd glyph via fallback.
  readonly property string symbolFont: ".SF Symbols Fallback"
  readonly property string uiFont: Motion.uiFont
  function sf(cp) { return String.fromCodePoint(cp) }
  readonly property int tileRadius: Style.space(Motion.radiusPopover)
  readonly property int gap: Style.space(12)
  readonly property int panelWidth: Style.space(350)
  readonly property int colWidth: Math.floor((panelWidth - gap) / 2)

  // ---- Trackpad bridge (mt-bridge): a MacBook's trackpad arriving over a
  // USB-C cable, or over Wi-Fi when the cable is out. Both daemons keep a
  // small status file and this watches those, because polling them with
  // processes would cost frames at exactly the moment the panel opens.
  property var padLink: ({})
  property var padStream: ({})
  // Freshness is a comparison against the clock, and a binding cannot notice
  // time passing by itself. Mentioning padTick makes these re-evaluate when
  // the timer below bumps it; the comparison itself is always true.
  property int padTick: 0
  readonly property bool padLinkUp: padLink.state === "up"
  readonly property bool padBridgeUp: padTick >= 0
    && Number(padStream.updated || 0) > 0
    && Date.now() / 1000 - Number(padStream.updated) < 4
  // The switch has to flip the instant it's pressed, not once the status
  // file confirms it -- systemctl itself is fast, but stopping the service
  // deletes the file rather than updating it, and padBridgeUp then only
  // notices four seconds later (its own staleness window). null = trust
  // padBridgeUp; true/false = trust the press until reality agrees with it.
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
  // mtsend pings once a second whether or not a finger is down, so this is
  // the Mac actually answering right now -- not a guess from how stale the
  // touch fields look, which used to read "Idle" the same way whether the
  // Mac was sitting there idle or not reachable at all.
  readonly property bool padLinked: padStream.linked === "1"
  readonly property string padSubtitle: !padBridgeUp ? "Off"
    : padStreaming ? (padTransport !== "" ? "Over " + padTransport : "Connected")
    : padLinked ? (padTransport !== "" ? "Idle \u00b7 " + padTransport : "Connected")
    : padLinkUp ? "Cable up \u00b7 not connected" : "Not connected"

  // ---- The Mac's screen, arriving as H.264 from the same machine. mac-stream
  // keeps a status file for the same reason the trackpad's daemons do, and it
  // carries a heartbeat: presence alone would still claim a mirror after the
  // viewer was killed outright.
  property var screenState: ({})
  readonly property bool screenOn: padTick >= 0
    && Number(screenState.updated || 0) > 0
    && Date.now() / 1000 - Number(screenState.updated) < 6
  readonly property string screenRoute: screenState.route || ""
  readonly property string screenSubtitle: !screenOn ? "Off"
    : screenRoute !== "" ? "Over " + screenRoute : "Mirroring"

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
  Timer {
    // These files vanish with their services, and a watch cannot follow a file
    // that is not there, so re-read while the panel is open. Reading a file is
    // cheap; this is deliberately not a process.
    running: root.opened
    interval: 1000
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.padTick++
      padLinkFile.reload()
      padStreamFile.reload()
      screenFile.reload()
      // Once the real state agrees with the press, or five seconds have
      // passed and it still hasn't (systemctl failed, most likely), stop
      // overriding and show what is actually true again.
      if (root.padOverride !== null
          && (root.padBridgeUp === root.padOverride
              || Date.now() - root.padOverrideSetAt > 5000))
        root.padOverride = null
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

  // ---- Detail pages. Like macOS, a tile's label swaps the grid for a list
  //      inside the same popup ("main" | "wifi" | "bluetooth" | "sound" | "hardware").
  property string page: "main"
  function showPage(name) {
    // Opening the outputs list is the moment the plug state has to be current.
    if (name === "sound" && !sinkPortProc.running) sinkPortProc.running = true
    page = name
  }

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

  // Sound outputs. PipeWire keeps a sink for every HDMI/DisplayPort output of
  // the card whether or not anything is plugged into it, and the node itself
  // carries no hint of that -- the plug state lives on the device's routes,
  // which Quickshell does not expose. pactl reports it per sink, so ask it and
  // drop the sinks whose every port is unplugged.
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
            if (ports.length === 0) continue   // no ports at all: not a plug question
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
      // Never hide what sound is actually playing out of.
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
  // the caller's own services).
  function service(id) {
    return shell && typeof shell.firstPartyServiceFor === "function"
      ? shell.firstPartyServiceFor(id) : null
  }
  readonly property var media: opened ? service("omarchy.media") : null
  readonly property var player: media ? media.activePlayer : null

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
    if (!sinkPortProc.running) sinkPortProc.running = true
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

  // ---- Keyboard cursor (main page). A flat, reading-order list of the main
  // page's focusable stops. Arrow keys / hjkl move it (dy between stops, dx
  // acts on the focused one — same moveRequested convention PanelKeyCatcher's
  // stock consumers use, e.g. omarchy.bluetooth); Enter/Space activates.
  // Tab still switches bar panels (root.switchPanel) and Esc still closes or
  // goes back — unchanged, shared with every other panel in the shell.
  property bool cursorActive: false
  property int mainCursorIndex: 0
  property int playbackCursorIndex: 1  // 0 previous, 1 play/pause, 2 next
  readonly property var mainStops: {
    var s = ["wifi", "bluetooth", "airdrop", "trackpad", "screen", "display", "sound"]
    if (player) s.push("playback")
    s.push("hardware")
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
    else if (f === "playback") playbackCursorIndex = Math.max(0, Math.min(2, playbackCursorIndex + dx))
    else if (dx > 0) {
      if (f === "wifi" || f === "bluetooth" || f === "trackpad") showPage(f)
      else if (f === "screen") showPage("screen")
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
    else if (f === "trackpad") toggleTrackpad()
    else if (f === "screen") launchMacScreen()
    else if (f === "display") displayExpanded = !displayExpanded
    else if (f === "sound") toggleMute()
    else if (f === "playback") { if (media) media.runAction(["previous", "playPause", "next"][playbackCursorIndex], false) }
    else if (f === "hardware") showPage("hardware")
  }

  // Named so the row's mouse handlers and the keyboard cursor above share one
  // implementation instead of two copies drifting apart.
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
  function toggleMute() { if (sink && sink.audio) sink.audio.muted = !muted }

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
    // Big Sur badges connectivity toggles as full circles but its
    // accessory tiles (Do Not Disturb, Screen Mirroring) as squircles —
    // same distinction as Trackpad/Mac Screen here vs. Wi-Fi/Bluetooth/AirDrop.
    property bool squircle: false
    signal clicked()
    width: Style.space(32)
    height: width
    radius: squircle ? width * 0.28 : width / 2
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
    // Keyboard cursor is on this tile (root.mainFocus) — draws the ring below.
    property bool hasCursor: false
    // Position in the entrance cascade; -1 opts out.
    property int revealIndex: -1
    signal clicked()
    radius: root.tileRadius
    color: hoverable && tileMouse.containsMouse ? root.tileHover : root.tileColor
    // Big Sur's cards read as separate surfaces even where the glass alpha
    // gap alone reads thin (bright wallpaper, low-contrast angle) — a
    // hairline finishes the edge the way a subtle drop shadow would.
    border.width: 1
    border.color: Util.alpha(root.fg, Motion.hairlineAlpha)
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

    // Keyboard-cursor ring (henri-ui: accent ring, fast fade in). z above any
    // externally-supplied children, which land after the tile's own in paint
    // order. Never intercepts pointer events (no MouseArea of its own).
    Rectangle {
      z: 1
      anchors.fill: parent
      radius: tile.radius
      color: "transparent"
      border.width: Math.max(2, Style.space(2))
      border.color: Color.accent
      opacity: tile.hasCursor ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    }
  }

  // Icon + two lines of text, used inside the connectivity tile and Focus.
  component ToggleRow: Item {
    id: row
    property string icon: ""
    property bool on: false
    property string title: ""
    property string subtitle: ""
    property bool squircle: false
    property bool hasCursor: false
    signal toggled()
    signal details()
    implicitHeight: Style.space(38)

    Circle {
      id: rowCircle
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      icon: row.icon
      on: row.on
      squircle: row.squircle
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
        font.family: root.uiFont
        font.pixelSize: Style.font.subtitle
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: row.subtitle
        visible: text !== ""
        color: root.dimText
        font.family: root.uiFont
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

    // Keyboard-cursor ring (henri-ui: accent ring, fast fade in).
    Rectangle {
      anchors.fill: parent
      radius: Style.space(8)
      color: "transparent"
      border.width: Math.max(2, Style.space(2))
      border.color: Color.accent
      opacity: row.hasCursor ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    }
  }

  // Like ToggleRow, but for something you open rather than switch on. The
  // circle still carries the state, because knowing whether the mirror is
  // live is worth a glance -- it just is not the control any more. Opening a
  // window is an action, and an action wants a button.
  component LaunchRow: Item {
    id: lrow
    property string icon: ""
    property bool on: false
    property string title: ""
    property string subtitle: ""
    property string action: "Open"
    property bool squircle: false
    property bool hasCursor: false
    signal launched()
    signal details()
    implicitHeight: Style.space(38)

    Circle {
      id: lrowCircle
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      icon: lrow.icon
      on: lrow.on
      squircle: lrow.squircle
      onClicked: lrow.launched()
    }
    Column {
      anchors.left: lrowCircle.right
      anchors.leftMargin: Style.space(8)
      anchors.right: lrowButton.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      spacing: 0
      Text {
        width: parent.width
        text: lrow.title
        color: root.fg
        font.family: root.uiFont
        font.pixelSize: Style.font.subtitle
        font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: lrow.subtitle
        visible: text !== ""
        color: root.dimText
        font.family: root.uiFont
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
    // Icon only, and squarely for room: a worded button leaves about ninety
    // pixels for the title in a tile this narrow, and "Mac Screen" does not
    // fit in ninety pixels. Icon-only controls owe the reader a name, and
    // there is no tooltip anywhere in this panel to give them one, so the
    // accessible name carries it.
    HUi.Button {
      id: lrowButton
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      icon: root.sf(0x100C13)
      fontFamily: root.symbolFont
      Accessible.role: Accessible.Button
      Accessible.name: lrow.action + " " + lrow.title
      onClicked: lrow.launched()
    }
    MouseArea {
      anchors.fill: parent
      anchors.leftMargin: lrowCircle.width + Style.space(4)
      anchors.rightMargin: lrowButton.width + Style.space(6)
      cursorShape: Qt.PointingHandCursor
      onClicked: lrow.details()
    }

    // Keyboard-cursor ring (henri-ui: accent ring, fast fade in).
    Rectangle {
      anchors.fill: parent
      radius: Style.space(8)
      color: "transparent"
      border.width: Math.max(2, Style.space(2))
      border.color: Color.accent
      opacity: lrow.hasCursor ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
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
    height: stColumn.implicitHeight + Style.space(24)
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
      anchors.topMargin: Style.space(12)
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
          fontFamily: root.uiFont
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
          fontFamily: root.uiFont
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

      // Big Sur's slider: one continuous pill, the icon sitting inside its
      // left edge rather than in a separate column beside it. Fill and knob
      // are both plain white so they read as one shape; the track's accent
      // tint is what gives an empty/low slider (Sound, muted) a visible rail.
      Item {
        width: parent.width
        height: Math.max(stSlider.implicitHeight, Style.space(30))

        PanelSlider {
          id: stSlider
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          bar: root.bar
          minimum: 0
          maximum: 1
          step: 0.05
          value: st.value
          // Henri's values.
          trackHeight: Style.space(22)
          knobSize: Style.space(30)
          fillColor: "#ffffff"
          knobColor: "#ffffff"
          trackColor: Util.alpha(Color.accent, 0.28)
          tickColor: "transparent"
          onMoved: function(v) { st.moved(v) }
        }
        HUi.CrossfadeText {
          id: stIcon
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(16)
          text: st.icon
          color: Util.alpha(Color.accent, 0.85)
          fontFamily: root.symbolFont
          // Kept clearly smaller than the track height so it never touches
          // the pill's top/bottom edge.
          fontSize: Style.space(12)
          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            cursorShape: Qt.PointingHandCursor
            onClicked: st.iconClicked()
          }
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
    font.family: root.uiFont
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
        font.family: root.uiFont
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
        id: chevronText
        anchors.verticalCenter: parent.verticalCenter
        text: root.sf(0x100189)
        transform: Translate {
          x: chevronHover.hovered && !Motion.reduceMotion ? -Style.space(3) : 0
          Behavior on x {
            NumberAnimation {
              duration: chevronHover.hovered ? Motion.instant : Motion.fast
              easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
            }
          }
        }
        color: root.fg
        font.family: root.symbolFont
        font.pixelSize: Style.font.iconLarge
        // Hovering anywhere in the (much wider) click target below shouldn't
        // nudge the chevron — only actually hovering it should.
        HoverHandler { id: chevronHover }
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: ph.title
        color: root.fg
        font.family: root.uiFont
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
        font.family: root.uiFont
        font.pixelSize: Style.font.subtitle
        font.weight: lr.active ? Font.DemiBold : Font.Normal
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        visible: text !== ""
        text: lr.subtitle
        color: root.dimText
        font.family: root.uiFont
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
      font.family: root.uiFont
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
      fontFamily: root.uiFont
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
      font.family: root.uiFont
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
      fontFamily: root.uiFont
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
    font.family: root.uiFont
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
      font.family: root.uiFont
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
        font.family: root.uiFont
        font.pixelSize: Style.font.subtitle
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: sr.caption
        color: root.dimText
        font.family: root.uiFont
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
      fontFamily: root.uiFont
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
        font.family: root.uiFont
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
    font.family: root.uiFont
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
      // Main page: dy moves the cursor between tiles, dx acts on the focused
      // one (open its detail page, nudge brightness, pick a transport
      // button). Detail pages have no cursor yet — ← (or h) there still just
      // goes back, like Esc (drill-in flow).
      onMoveRequested: function(dx, dy) {
        if (root.page !== "main") { if (dx < 0) root.page = "main"; return }
        if (dy !== 0) root.mainMoveCursor(dy)
        else if (dx !== 0) root.mainMoveHorizontal(dx)
      }
      onActivateRequested: root.mainActivate()
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

      // Top block: what the machine talks to on the left (one tall tile,
      // three rows); what it borrows from the Mac on the right, as two
      // separate single-row tiles stacked with a gap — like Big Sur's own
      // Do Not Disturb / Screen Mirroring pair, not one merged tile.
      Row {
        id: topRow
        spacing: root.gap

        Tile {
          revealIndex: 0
          width: root.colWidth
          height: connectivity.implicitHeight + Style.space(20)

          Column {
            id: connectivity
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(10)
            anchors.rightMargin: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            ToggleRow {
              width: parent.width
              icon: root.wifiOn ? root.sf(0x100647) : root.sf(0x100648)
              on: root.wifiOn
              title: "Wi-Fi"
              subtitle: !root.wifiOn ? "Off" : (root.wifiName !== "" ? root.wifiName : "Not connected")
              hasCursor: root.mainFocus === "wifi"
              onToggled: root.toggleWifi()
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
              hasCursor: root.mainFocus === "bluetooth"
              onToggled: root.toggleBluetooth()
              onDetails: root.showPage("bluetooth")
            }
            ToggleRow {
              width: parent.width
              icon: root.sf(0x100319)
              on: root.localsendRunning
              title: "AirDrop"
              subtitle: root.localsendRunning ? "LocalSend active" : "LocalSend"
              hasCursor: root.mainFocus === "airdrop"
              onToggled: root.toggleAirdrop()
              onDetails: root.openAirdrop()
            }
          }
        }

        // The Mac side of the desk: its trackpad and its screen, the two
        // things this machine borrows over the cable — each its own tile.
        Column {
          width: root.colWidth
          spacing: root.gap

          Tile {
            revealIndex: 1
            width: parent.width
            height: trackpadRow.implicitHeight + Style.space(20)

            ToggleRow {
              id: trackpadRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              icon: root.sf(0x100EA4)
              on: root.padOn
              squircle: true
              title: "Mac Input"
              subtitle: root.padSubtitle
              hasCursor: root.mainFocus === "trackpad"
              onToggled: root.toggleTrackpad()
              onDetails: root.showPage("trackpad")
            }
          }

          Tile {
            revealIndex: 2
            width: parent.width
            height: screenRow.implicitHeight + Style.space(20)

            LaunchRow {
              id: screenRow
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              icon: root.sf(0x1008B9)
              on: root.screenOn
              squircle: true
              title: "Mac Screen"
              subtitle: root.screenSubtitle
              action: root.screenOn ? "Show" : "Open"
              hasCursor: root.mainFocus === "screen"
              // Already running means raise the window it is in, not start a
              // second one. Closing it is what closing a window is for; the
              // detail page has the switch for when it is on another
              // workspace.
              onLaunched: root.launchMacScreen()
              onDetails: root.showPage("screen")
            }
          }
        }
      }

      SliderTile {
        revealIndex: 3
        visible: root.brightnessAvailable || root.displays.length > 0
        heading: "Display"
        icon: root.sf(root.brightness < 40 ? 0x1001AC : 0x1001AE)
        value: root.brightness / 100
        expandable: true
        expanded: root.displayExpanded
        hasCursor: root.mainFocus === "display"
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
            font.family: root.uiFont
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
            font.family: root.uiFont
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
        revealIndex: 4
        visible: root.sink !== null
        heading: root.airpodsActive ? root.airpodsName : "Sound"
        headingGlyph: root.airpodsActive ? airpodsGlyph : null
        headingDetail: root.airpodsActive && root.airpodsLevel >= 0 ? root.airpodsLevel + " %" : ""
        expandable: true
        icon: root.muted || root.volume === 0 ? root.sf(0x1002A3) : root.volume < 0.34 ? root.sf(0x1002A5) : root.volume < 0.67 ? root.sf(0x1002A7) : root.sf(0x1002A9)
        value: root.muted ? 0 : Math.min(1, root.volume)
        hasCursor: root.mainFocus === "sound"
        onMoved: function(v) {
          if (!root.sink || !root.sink.audio) return
          root.sink.audio.volume = v
          if (root.muted && v > 0) root.sink.audio.muted = false
        }
        onIconClicked: root.toggleMute()
        onHeadingClicked: root.showPage(root.airpodsActive ? "airpods" : "sound")
      }

      // Now Playing — only while an MPRIS player has a track.
      Tile {
        revealIndex: 5
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
            font.family: root.uiFont
            font.pixelSize: Style.font.subtitle
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: root.player ? (root.player.trackArtist || root.player.identity || "") : ""
            color: root.dimText
            font.family: root.uiFont
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
              id: playBtn
              required property var modelData
              required property int index
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
              // Keyboard-cursor ring: one of the three transport buttons,
              // picked with ←/→ while "playback" is the focused stop.
              Rectangle {
                anchors.fill: parent
                radius: playBtn.radius
                color: "transparent"
                border.width: Math.max(2, Style.space(2))
                border.color: Color.accent
                opacity: root.mainFocus === "playback" && root.playbackCursorIndex === playBtn.index ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
              }
            }
          }
        }
      }

      // Hardware: CPU load, memory and temperature at a glance.
      Tile {
        revealIndex: 6
        width: root.panelWidth
        height: Style.space(52)
        hoverable: true
        hasCursor: root.mainFocus === "hardware"
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
            font.family: root.uiFont
            font.pixelSize: Style.font.subtitle
            font.weight: Font.DemiBold
          }
          HUi.CrossfadeText {
            width: parent.width
            visible: root.hwSummary !== ""
            text: root.hwSummary
            color: root.hw.temp >= 80 ? root.tempColor(root.hw.temp) : root.dimText
            fontFamily: root.uiFont
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
              font.family: root.uiFont
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
                  font.family: root.uiFont
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
                  font.family: root.uiFont
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
            font.family: root.uiFont
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
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                }
                HUi.CrossfadeText {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(14)
                  horizontalAlignment: Text.AlignRight
                  text: pods.adaptiveNoiseLevel + " %"
                  color: root.dimText
                  fontFamily: root.uiFont
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
            font.family: root.uiFont
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
          font.family: root.uiFont
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

      // Mac screen — the MacBook's display arriving as H.264. Everything here
      // describes this side: what the far side is doing is its own business
      // and asking would mean a probe on every tick.
      PageHeader {
        visible: root.detailPage === "screen"
        title: "Mac Screen"
      }
      Separator { visible: root.detailPage === "screen" }
      Column {
        id: screenPage
        visible: root.detailPage === "screen"
        width: root.panelWidth
        leftPadding: Style.space(6)
        rightPadding: Style.space(6)
        topPadding: Style.space(4)
        bottomPadding: Style.space(6)
        spacing: Style.space(6)
        readonly property int innerWidth: root.panelWidth - Style.space(12)
        readonly property int cellWidth: Math.floor((innerWidth - Style.space(16)) / 2)

        UsageHeader {
          width: screenPage.innerWidth
          title: "Mirror"
          value: root.screenOn
            ? (root.screenRoute !== "" ? "Over " + root.screenRoute : "Mirroring")
            : "Off"
          valueColor: root.screenOn ? Color.accent : root.dimText
        }
        Text {
          width: screenPage.innerWidth
          wrapMode: Text.WordWrap
          color: root.dimText
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          text: root.screenOn
              ? "The Mac is capturing its own screen and sending it here. Nothing on it had to be clicked."
            : root.padLinkUp
              ? "Cable is up. Turning this on opens the mirror."
              : "No cable. It will fall back to Wi-Fi, which costs delay and drops frames."
        }

        Row {
          spacing: Style.space(6)
          HUi.Button {
            text: root.screenOn ? "Show window" : "Open mirror"
            prominent: !root.screenOn
            fontFamily: root.uiFont
            onClicked: { root.close(); root.run("omarchy-launch-or-focus gst-launch-1.0 'setsid -f mac-stream'") }
          }
          HUi.Button {
            visible: root.screenOn
            text: "Close"
            fontFamily: root.uiFont
            // By pid from the status file, not by name: more than one viewer
            // may be running and only the one that wrote this file is ours.
            onClicked: root.run("kill " + (root.screenState.pid || 0))
          }
        }

        Separator { width: screenPage.innerWidth }

        ListLabel { text: "Stream" }
        Grid {
          columns: 2
          columnSpacing: Style.space(16)
          rowSpacing: Style.space(2)
          Stat { width: screenPage.cellWidth; label: "Route"; value: root.screenRoute !== "" ? root.screenRoute : "--" }
          Stat { width: screenPage.cellWidth; label: "Source"; value: root.screenState.host || "--" }
          Stat { width: screenPage.cellWidth; label: "Port"; value: root.screenState.port || "--" }
          Stat { width: screenPage.cellWidth; label: "Decoder"; value: root.screenState.decoder || "--" }
          Stat {
            width: screenPage.cellWidth
            label: "Running"
            value: root.screenOn && Number(root.screenState.started || 0) > 0
              ? root.formatUptime(Math.max(0, Math.floor(Date.now() / 1000 - Number(root.screenState.started))))
              : "--"
          }
        }
      }

      // Mac Input — where the MacBook's trackpad and keyboard are coming in,
      // and over which route. Read only except for the receiver switch: the
      // cable link comes and goes with the cable, which is not this panel's
      // to decide.
      PageHeader {
        visible: root.detailPage === "trackpad"
        title: "Mac Input"
        showSwitch: true
        checked: root.padOn
        onToggled: root.toggleTrackpad()
      }
      Separator { visible: root.detailPage === "trackpad" }
      Column {
        id: padPage
        visible: root.detailPage === "trackpad"
        width: root.panelWidth
        leftPadding: Style.space(6)
        rightPadding: Style.space(6)
        topPadding: Style.space(4)
        bottomPadding: Style.space(6)
        spacing: Style.space(6)
        readonly property int innerWidth: root.panelWidth - Style.space(12)
        readonly property int cellWidth: Math.floor((innerWidth - Style.space(16)) / 2)

        UsageHeader {
          width: padPage.innerWidth
          title: "Connection"
          value: (!root.padBridgeUp ? "Off"
            : root.padStreaming ? (root.padTransport !== "" ? root.padTransport : "Connected")
            : root.padLinked ? "Idle"
            : "Not connected")
            + (root.padButton ? " \u00b7 click" : "")
            + (root.padKeysHeld > 0 ? " \u00b7 " + root.padKeysHeld + " key"
               + (root.padKeysHeld === 1 ? "" : "s") : "")
          valueColor: root.padStreaming ? Color.accent
            : !root.padBridgeUp || root.padLinked ? root.dimText : Color.urgent
        }
        Text {
          width: padPage.innerWidth
          wrapMode: Text.WordWrap
          color: root.dimText
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
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

        Separator { width: padPage.innerWidth }

        ListLabel { text: "Cable" }
        Grid {
          columns: 2
          columnSpacing: Style.space(16)
          rowSpacing: Style.space(2)
          Stat { width: padPage.cellWidth; label: "Link"; value: root.padLinkUp ? "Up" : "Down" }
          Stat { width: padPage.cellWidth; label: "Interface"; value: root.padLink["interface"] || "--" }
          Stat { width: padPage.cellWidth; label: "Address"; value: root.padLink.address || "--" }
          Stat { width: padPage.cellWidth; label: "Ethernet in"; value: root.padLink.rx_frames || "--" }
        }

        Separator { width: padPage.innerWidth }

        ListLabel { text: "Stream" }
        Grid {
          columns: 2
          columnSpacing: Style.space(16)
          rowSpacing: Style.space(2)
          Stat { width: padPage.cellWidth; label: "Mac"; value: !root.padBridgeUp ? "--" : root.padLinked ? "Connected" : "Not connected" }
          Stat { width: padPage.cellWidth; label: "Route"; value: root.padTransport !== "" ? root.padTransport : "--" }
          Stat { width: padPage.cellWidth; label: "Source"; value: root.padStream.source || "--" }
          Stat { width: padPage.cellWidth; label: "Fingers"; value: root.padStreaming ? String(root.padStream.contacts || 0) : "--" }
          Stat { width: padPage.cellWidth; label: "Button"; value: !root.padStreaming ? "--" : root.padButton ? "Pressed" : "Released" }
          Stat { width: padPage.cellWidth; label: "Touch frames"; value: root.padStream.frames || "--" }
        }

        Separator { width: padPage.innerWidth }

        ListLabel { text: "Keyboard" }
        Grid {
          columns: 2
          columnSpacing: Style.space(16)
          rowSpacing: Style.space(2)
          Stat {
            width: padPage.cellWidth
            label: "Device"
            value: root.padKeyboard ? "Present" : "Off"
          }
          Stat {
            width: padPage.cellWidth
            label: "Held"
            value: root.padBridgeUp ? String(root.padKeysHeld) : "--"
          }
          Stat {
            width: padPage.cellWidth
            label: "Key events"
            value: root.padStream.key_events || "--"
          }
        }
        Text {
          width: padPage.innerWidth
          wrapMode: Text.WordWrap
          color: root.dimText
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          text: "Keys map by position: this machine's layout decides the "
            + "character. Both hotkeys stay on the Mac."
        }
      }
    }
    }
  }
}
