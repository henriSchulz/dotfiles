import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import qs.Commons
import qs.Ui
import "Display.js" as Display

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
  readonly property color onIcon: Color.popups.background
  readonly property color dimText: Qt.rgba(fg.r, fg.g, fg.b, 0.6)
  readonly property string iconFont: bar ? bar.fontFamily : Style.font.family
  readonly property int tileRadius: Math.max(Style.space(12), Style.cornerRadius)
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
  //      inside the same popup ("main" | "wifi" | "bluetooth" | "sound").
  property string page: "main"
  function showPage(name) { page = name }

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
        secure: n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe
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
  property string wifiFailed: ""

  function wifiNetwork(name) {
    var nets = wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
    for (var i = 0; i < nets.length; i++) if (nets[i] && nets[i].name === name) return nets[i]
    return null
  }
  function wifiActivate(row) {
    var net = wifiNetwork(row.name)
    if (!net) return
    wifiFailed = ""
    if (row.connected) {
      markWifiPending(row.name)
      net.disconnect()
    } else if (row.secure && !row.known) {
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
  function wifiIcon(signal) {
    return signal >= 75 ? "󰤨" : signal >= 50 ? "󰤥" : signal >= 25 ? "󰤢" : "󰤟"
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
    next[row.address] = row.connected ? "Trenne …" : "Verbinde …"
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
      if (p && ((p === "Verbinde …" && r.connected) || (p === "Trenne …" && !r.connected))) {
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
    if (icon.indexOf("headset") >= 0 || icon.indexOf("headphone") >= 0) return "󰋋"
    if (icon.indexOf("audio") >= 0 || icon.indexOf("speaker") >= 0) return "󰓃"
    if (icon.indexOf("mouse") >= 0) return "󰍽"
    if (icon.indexOf("keyboard") >= 0) return "󰌌"
    if (icon.indexOf("phone") >= 0) return "󰏲"
    if (icon.indexOf("computer") >= 0) return "󰌢"
    if (icon.indexOf("gaming") >= 0 || icon.indexOf("joystick") >= 0) return "󰊴"
    return "󰂯"
  }

  // Sound outputs.
  readonly property var sinkRows: {
    var rows = []
    var nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (!n || !n.isSink || n.isStream || !n.audio) continue
      var props = n.properties || {}
      rows.push({
        id: n.id,
        name: n.name || "",
        label: n.nickname || props["node.nick"] || n.description || n.name || "Ausgabe",
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
    if (l.indexOf("hdmi") >= 0 || l.indexOf("displayport") >= 0) return "󰍹"
    if (l.indexOf("head") >= 0 || l.indexOf("kopfh") >= 0) return "󰋋"
    return "󰓃"
  }

  // ---- Services owned by the shell
  function service(ids) {
    if (!shell) return null
    for (var i = 0; i < ids.length; i++) {
      var s = shell.serviceFor(ids[i])
      if (s) return s
    }
    return null
  }
  readonly property var notifications: opened ? service(["omarchy.notifications"]) : null
  readonly property var nightlight: opened ? service(["omarchy.nightlight"]) : null
  readonly property var idle: opened ? service(["henri.idle", "omarchy.idle"]) : null
  readonly property var media: opened ? service(["omarchy.media"]) : null

  readonly property bool dnd: notifications ? notifications.doNotDisturb : false
  readonly property bool nightOn: nightlight ? nightlight.enabled : false
  readonly property bool stayAwake: idle ? idle.stayAwake : false

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
    if (opened) refresh()
    else {
      displayExpanded = false
      page = "main"
      wifiPasswordFor = ""
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

  Process {
    id: localsendProc
    command: ["pgrep", "-x", "localsend"]
    onExited: function(code) { root.localsendRunning = code === 0 }
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
    scale: circleMouse.pressed ? 0.92 : 1
    Behavior on color { ColorAnimation { duration: 140 } }
    Behavior on scale { NumberAnimation { duration: 90 } }

    Text {
      anchors.centerIn: parent
      text: circle.icon
      font.family: root.iconFont
      font.pixelSize: Style.font.iconLarge
      color: circle.on ? root.onIcon : root.fg
    }
    MouseArea {
      id: circleMouse
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: circle.clicked()
    }
  }

  component Tile: Rectangle {
    id: tile
    property bool hoverable: false
    signal clicked()
    radius: root.tileRadius
    color: hoverable && tileMouse.containsMouse ? root.tileHover : root.tileColor
    Behavior on color { ColorAnimation { duration: 100 } }
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
    default property alias extra: extraColumn.data
    signal moved(real value)
    signal iconClicked()
    signal headingClicked()
    width: root.panelWidth
    height: stColumn.implicitHeight + Style.space(15)
    clip: true
    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

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

        Text {
          id: stHeading
          text: st.heading
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
          font.weight: Font.DemiBold
        }
        Text {
          visible: st.expandable
          anchors.right: parent.right
          anchors.verticalCenter: stHeading.verticalCenter
          text: "󰅂"
          rotation: st.expanded ? 90 : 0
          color: root.dimText
          font.family: root.iconFont
          font.pixelSize: Style.font.icon
          Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
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

        Text {
          id: stIcon
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(20)
          text: st.icon
          color: root.fg
          font.family: root.iconFont
          font.pixelSize: Style.font.iconLarge
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
    Behavior on color { ColorAnimation { duration: 120 } }
    Text {
      anchors.centerIn: parent
      text: pill.label
      color: pill.selected ? root.onIcon : root.fg
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
      font.weight: pill.selected ? Font.DemiBold : Font.Normal
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
        text: "󰅁"
        color: root.fg
        font.family: root.iconFont
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
      Behavior on color { ColorAnimation { duration: 140 } }
      Rectangle {
        width: parent.height - Style.space(4)
        height: width
        radius: width / 2
        y: Style.space(2)
        x: ph.checked ? parent.width - width - Style.space(2) : Style.space(2)
        color: ph.checked ? root.onIcon : root.fg
        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
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
    signal clicked()
    width: root.panelWidth
    height: Style.space(44)
    radius: Style.space(10)
    color: lrMouse.containsMouse ? root.tileColor : "transparent"

    Rectangle {
      id: lrCircle
      anchors.left: parent.left
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(28)
      height: width
      radius: width / 2
      color: lr.active ? root.circleOn : root.circleOff
      Text {
        anchors.centerIn: parent
        text: lr.icon
        color: lr.active ? root.onIcon : root.fg
        font.family: root.iconFont
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
      }
    }
    Text {
      id: lrTrailing
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: lr.trailing
      color: root.dimText
      font.family: root.iconFont
      font.pixelSize: Style.font.bodySmall
    }
    MouseArea {
      id: lrMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: lr.clicked()
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

  component Separator: Rectangle {
    width: root.panelWidth
    height: 1
    color: root.circleOff
  }

  // Footer link at the bottom of a detail page.
  component FooterLink: Text {
    id: fl
    signal clicked()
    leftPadding: Style.space(6)
    color: flMouse.containsMouse ? root.fg : root.dimText
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: root.gap
    contentWidth: root.panelWidth + root.gap * 2
    contentHeight: panel.fittedContentHeight(root.page === "main" ? content.implicitHeight : detail.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.page !== "main") root.page = "main"
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
    }

    Column {
      id: content
      width: root.panelWidth
      spacing: root.gap
      visible: root.page === "main"

      // Top block: connectivity on the left, Focus + small toggles on the right.
      Row {
        spacing: root.gap

        Tile {
          width: root.colWidth
          height: connectivity.implicitHeight + Style.space(20)

          Column {
            id: connectivity
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(4)

            ToggleRow {
              width: parent.width
              icon: root.wifiOn ? "󰖩" : "󰖪"
              on: root.wifiOn
              title: "WLAN"
              subtitle: !root.wifiOn ? "Aus" : (root.wifiName !== "" ? root.wifiName : "Nicht verbunden")
              onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
              onDetails: root.showPage("wifi")
            }
            ToggleRow {
              width: parent.width
              icon: root.btOn ? "󰂯" : "󰂲"
              on: root.btOn
              title: "Bluetooth"
              subtitle: !root.btOn ? "Aus"
                : root.btConnected.length === 1 ? (root.btConnected[0].name || "1 Gerät")
                : root.btConnected.length > 1 ? root.btConnected.length + " Geräte"
                : "Ein"
              // omarchy-bluetooth-power persists the state (see the stock panel).
              onToggled: Quickshell.execDetached(["omarchy-bluetooth-power", root.btOn ? "off" : "on"])
              onDetails: root.showPage("bluetooth")
            }
            ToggleRow {
              width: parent.width
              icon: "󰜡"
              on: root.localsendRunning
              title: "AirDrop"
              subtitle: root.localsendRunning ? "LocalSend aktiv" : "LocalSend"
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
            width: root.colWidth
            height: Style.space(52)
            hoverable: true
            onClicked: if (root.notifications) root.notifications.setDoNotDisturb(!root.dnd)

            ToggleRow {
              anchors.fill: parent
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(6)
              icon: "󰽥"
              on: root.dnd
              title: "Fokus"
              subtitle: root.dnd ? "Nicht stören" : ""
              onToggled: if (root.notifications) root.notifications.setDoNotDisturb(!root.dnd)
              onDetails: if (root.notifications) root.notifications.setDoNotDisturb(!root.dnd)
            }
          }

          Row {
            spacing: root.gap
            SmallTile {
              icon: "󰖔"
              on: root.nightOn
              title: "Night Shift"
              onClicked: if (root.nightlight) root.nightlight.setNightlight(!root.nightOn)
            }
            SmallTile {
              icon: "󰅶"
              on: root.stayAwake
              title: "Wach bleiben"
              onClicked: if (root.idle) root.idle.setIdleEnabled(root.stayAwake)
            }
          }
        }
      }

      SliderTile {
        visible: root.brightnessAvailable || root.displays.length > 0
        heading: "Bildschirm"
        icon: root.brightness < 40 ? "󰃞" : root.brightness < 75 ? "󰃟" : "󰃠"
        value: root.brightness / 100
        expandable: true
        expanded: root.displayExpanded
        onHeadingClicked: root.displayExpanded = !root.displayExpanded
        onMoved: function(v) { root.setBrightness(v * 100) }

        // ---- Text size
        SectionLabel { text: "Textgröße · " + root.textSizeStops[root.textSizeIndex] + " px" }
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
          text: "Skalierung" + (root.displays.length > 1 && root.focusedMonitor ? " · " + root.focusedMonitor : "")
                + (root.focusedDisplay && root.monitorScale
                   ? " · wirkt wie " + Display.looksLike(root.monitorScale, root.focusedDisplay.width, root.focusedDisplay.height)
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
          text: "Monitore"
        }
        Repeater {
          model: root.displays.length > 1 ? root.displays : []
          delegate: Item {
            required property var modelData
            width: parent.width
            height: Style.space(30)
            opacity: modelData.enabled && root.enabledDisplayCount <= 1 ? 0.6 : 1
            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: (modelData.focused ? "󰍹  " : "󰍺  ") + modelData.name
                    + (modelData.width ? "   " + modelData.width + " × " + modelData.height : "")
              color: root.fg
              font.family: root.iconFont
              font.pixelSize: Style.font.bodySmall
            }
            Pill {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(52)
              label: modelData.enabled ? "An" : "Aus"
              selected: modelData.enabled
              onClicked: root.toggleDisplay(modelData)
            }
          }
        }

      }

      SliderTile {
        visible: root.sink !== null
        heading: "Ton"
        expandable: true
        icon: root.muted || root.volume === 0 ? "󰝟" : root.volume < 0.34 ? "󰕿" : root.volume < 0.67 ? "󰖀" : "󰕾"
        value: root.muted ? 0 : Math.min(1, root.volume)
        onMoved: function(v) {
          if (!root.sink || !root.sink.audio) return
          root.sink.audio.volume = v
          if (root.muted && v > 0) root.sink.audio.muted = false
        }
        onIconClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.muted
        onHeadingClicked: root.showPage("sound")
      }

      // Now Playing — only while an MPRIS player has a track.
      Tile {
        id: nowPlaying
        readonly property bool playing: root.media && root.media.activePlayer ? root.media.activePlayer.isPlaying === true : false
        visible: root.media ? root.media.hasMedia === true : false
        width: root.panelWidth
        height: Style.space(64)

        Rectangle {
          id: art
          anchors.left: parent.left
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(44)
          height: width
          radius: Style.space(8)
          color: root.circleOff
          clip: true

          Text {
            anchors.centerIn: parent
            visible: artImage.status !== Image.Ready
            text: "󰝚"
            color: root.dimText
            font.family: root.iconFont
            font.pixelSize: Style.font.iconLarge
          }
          Image {
            id: artImage
            anchors.fill: parent
            source: root.media ? root.media.artUrl : ""
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
            text: root.media ? root.media.title : ""
            color: root.fg
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.weight: Font.DemiBold
            elide: Text.ElideRight
          }
          Text {
            width: parent.width
            text: root.media ? (root.media.artist || root.media.identity) : ""
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
              { icon: "󰒮", action: "previous" },
              { icon: nowPlaying.playing ? "󰏤" : "󰐊", action: "playPause" },
              { icon: "󰒭", action: "next" }
            ]
            delegate: Rectangle {
              required property var modelData
              width: Style.space(30)
              height: width
              radius: width / 2
              color: controlMouse.containsMouse ? root.circleOff : "transparent"
              Text {
                anchors.centerIn: parent
                text: modelData.icon
                color: root.fg
                font.family: root.iconFont
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

      // Bottom row, like "Edit Controls" on macOS.
      Tile {
        width: root.panelWidth
        height: Style.space(40)
        hoverable: true
        onClicked: root.openPluginManager()

        Text {
          id: pluginsIcon
          anchors.left: parent.left
          anchors.leftMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          text: "󰐱"
          color: root.fg
          font.family: root.iconFont
          font.pixelSize: Style.font.iconLarge
        }
        Text {
          anchors.left: pluginsIcon.right
          anchors.leftMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: "Plugins verwalten"
          color: root.fg
          font.family: Style.font.family
          font.pixelSize: Style.font.subtitle
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.space(14)
          anchors.verticalCenter: parent.verticalCenter
          text: "󰅂"
          color: root.dimText
          font.family: root.iconFont
          font.pixelSize: Style.font.icon
        }
      }
    }

    // ---- Detail pages
    Column {
      id: detail
      width: root.panelWidth
      spacing: Style.space(4)
      visible: root.page !== "main"

      // Wi-Fi
      PageHeader {
        visible: root.page === "wifi"
        title: "WLAN"
        showSwitch: true
        checked: root.wifiOn
        onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
      }
      Separator { visible: root.page === "wifi" }
      ListLabel {
        visible: root.page === "wifi" && root.wifiOn
        text: root.wifiRows.length ? "Netzwerke" : "Suche nach Netzwerken …"
      }
      Flickable {
        visible: root.page === "wifi" && root.wifiOn
        width: root.panelWidth
        height: Math.min(wifiList.implicitHeight, Style.space(44) * 8)
        contentHeight: wifiList.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: wifiList
          width: parent.width
          Repeater {
            model: root.page === "wifi" ? root.wifiRows : []
            delegate: Column {
              required property var modelData
              width: root.panelWidth

              ListRow {
                icon: root.wifiIcon(modelData.signal)
                active: modelData.connected
                title: modelData.name
                subtitle: root.wifiPending === modelData.name ? (modelData.connected ? "Trenne …" : "Verbinde …")
                  : root.wifiFailed === modelData.name ? "Verbindung fehlgeschlagen"
                  : modelData.connected ? "Verbunden"
                  : modelData.known ? "Bekannt" : ""
                trailing: modelData.secure ? "󰌾" : ""
                onClicked: root.wifiActivate(modelData)
              }

              // Inline password entry for a new secured network.
              Rectangle {
                visible: root.wifiPasswordFor === modelData.name
                x: Style.space(44)
                width: root.panelWidth - Style.space(50)
                height: visible ? Style.space(32) : 0
                radius: Style.space(8)
                color: root.tileColor
                border.width: 1
                border.color: passwordInput.activeFocus ? root.circleOn : root.circleOff

                onVisibleChanged: if (visible) { passwordInput.text = ""; passwordInput.forceActiveFocus() }

                TextInput {
                  id: passwordInput
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(34)
                  verticalAlignment: TextInput.AlignVCenter
                  echoMode: TextInput.Password
                  color: root.fg
                  selectionColor: root.circleOn
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  clip: true
                  Keys.onReturnPressed: root.wifiConnectWithPassword(modelData.name, text)
                  Keys.onEnterPressed: root.wifiConnectWithPassword(modelData.name, text)
                  Keys.onEscapePressed: root.wifiPasswordFor = ""

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: parent.text === ""
                    text: "Passwort"
                    color: root.dimText
                    font: parent.font
                  }
                }
                Text {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰁔"
                  color: passwordInput.text === "" ? root.dimText : root.fg
                  font.family: root.iconFont
                  font.pixelSize: Style.font.icon
                  MouseArea {
                    anchors.fill: parent
                    anchors.margins: -Style.space(6)
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.wifiConnectWithPassword(modelData.name, passwordInput.text)
                  }
                }
              }
            }
          }
        }
      }

      // Bluetooth
      PageHeader {
        visible: root.page === "bluetooth"
        title: "Bluetooth"
        showSwitch: true
        checked: root.btOn
        onToggled: Quickshell.execDetached(["omarchy-bluetooth-power", root.btOn ? "off" : "on"])
      }
      Separator { visible: root.page === "bluetooth" }
      ListLabel {
        visible: root.page === "bluetooth" && root.btOn
        text: root.btRows.length ? "Geräte" : "Suche nach Geräten …"
      }
      ListLabel {
        visible: root.page === "bluetooth" && !root.btOn
        text: "Bluetooth ist aus"
      }
      Flickable {
        visible: root.page === "bluetooth" && root.btOn
        width: root.panelWidth
        height: Math.min(btList.implicitHeight, Style.space(44) * 8)
        contentHeight: btList.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: btList
          width: parent.width
          Repeater {
            model: root.page === "bluetooth" ? root.btRows : []
            delegate: ListRow {
              required property var modelData
              icon: root.btIcon(modelData.icon)
              active: modelData.connected
              title: modelData.name
              subtitle: root.btPending[modelData.address]
                || (modelData.connected ? "Verbunden" : modelData.paired ? "Gekoppelt" : "Nicht gekoppelt")
              trailing: modelData.battery >= 0 ? modelData.battery + " %" : ""
              onClicked: root.btActivate(modelData)
            }
          }
        }
      }

      // Sound
      PageHeader {
        visible: root.page === "sound"
        title: "Ton"
      }
      Separator { visible: root.page === "sound" }
      Item {
        visible: root.page === "sound" && root.sink !== null
        width: root.panelWidth
        height: Style.space(40)
        Text {
          id: soundIcon
          anchors.left: parent.left
          anchors.leftMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(20)
          text: root.muted || root.volume === 0 ? "󰝟" : "󰕾"
          color: root.fg
          font.family: root.iconFont
          font.pixelSize: Style.font.iconLarge
          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.sink && root.sink.audio) root.sink.audio.muted = !root.muted
          }
        }
        PanelSlider {
          anchors.left: soundIcon.right
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
      ListLabel {
        visible: root.page === "sound"
        text: "Ausgabe"
      }
      Repeater {
        model: root.page === "sound" ? root.sinkRows : []
        delegate: ListRow {
          required property var modelData
          icon: root.sinkIcon(modelData.label)
          active: modelData.active
          title: modelData.label
          trailing: modelData.active ? "󰄬" : ""
          onClicked: if (!modelData.active) root.setSink(modelData)
        }
      }
    }
  }
}
