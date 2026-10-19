import QtQuick
import Quickshell
import "AirPods.js" as Pods
import "file:///home/henri/.local/share/velum/qml/Velum"

// The pages of Control Center v3: the module grid, and the detail pages that
// slide in from the right (VPageStack; ‹ or Esc goes back). All values come
// from Backend.qml; all looks from Velum (Pearl by default).
Item {
  id: cc
  property var be: null
  property var velum: null
  signal closeRequested()
  signal pluginsRequested()
  implicitHeight: stack.implicitHeight

  // ---- navigation (the backend scans/polls only on the page that shows it)
  property var names: []
  readonly property string current: names.length ? names[names.length - 1] : "main"
  onCurrentChanged: if (be) be.page = current
  readonly property var pageFor: ({ wifi: wifiPage, bluetooth: btPage, sound: soundPage, airpods: podsPage, display: displayPage,
                                    focus: focusPage, keyboard: kbdPage, battery: batteryPage, hardware: hwPage, experiments: expPage })
  function show(name) {
    var adv = name === "wifi-advanced"
    if (adv) name = "wifi"
    if (!pageFor[name]) return
    if (current === name) return
    if (names.length) { stack.reset(); names = [] }
    stack.push(pageFor[name]); names = [name]
    if (adv) be.wifiAdvanced = true
  }
  function push(name) { stack.push(pageFor[name]); names = names.concat([name]) }
  function back() {
    if (stack.depth < 2) return false
    stack.pop(); names = names.slice(0, -1)
    return true
  }
  function reset() { stack.reset(); names = [] }

  VPageStack { id: stack; width: parent.width; initial: mainPage }

  // ---- parts: everything takes the page's width
  component MRow: VModuleRow { width: parent ? parent.width : implicitWidth }
  component MHead: VPageHead { width: parent ? parent.width : implicitWidth; onBack: cc.back() }
  component MSection: VModuleSection { width: parent ? parent.width : 0 }
  component MSep: VModuleSep { width: parent ? parent.width : implicitWidth }
  component Glyph: VIcon { color: Theme.r.popover.inkSecondary }
  // a slider row: icon (opens a page when given one), the slider, a trailing icon
  component SliderRow: Item {
    id: sr
    property string icon: ""
    property string iconEnd: ""
    property real value: 0
    property string opens: ""
    signal moved(real v)
    signal iconClicked()
    width: parent ? parent.width : 0
    height: Theme.layout.module.row
    readonly property real pad: Theme.layout.module.pad
    VIcon { id: si; x: sr.pad; anchors.verticalCenter: parent.verticalCenter; name: sr.icon; color: Theme.r.popover.ink
      MouseArea { anchors.fill: parent; anchors.margins: -Theme.layout.list.gap / 2; onClicked: sr.opens ? cc.push(sr.opens) : sr.iconClicked() } }
    VSlider { x: si.x + si.width + sr.pad; width: parent.width - x - (sr.iconEnd ? Theme.layout.icon.regular + 2 * sr.pad : sr.pad)
      anchors.verticalCenter: parent.verticalCenter; value: sr.value; onMoved: v => sr.moved(v) }
    VIcon { visible: sr.iconEnd !== ""; anchors.right: parent.right; anchors.rightMargin: sr.pad; anchors.verticalCenter: parent.verticalCenter
      name: sr.iconEnd; color: Theme.r.popover.inkSecondary }
  }
  // a module card with a title over its content
  component Card: VTile {
    id: card
    property string title: ""
    property string titleDetail: ""
    property string opens: ""
    default property alias body: cardBody.data
    width: parent ? parent.width : 0
    height: (title ? Theme.layout.module.section : 0) + cardBody.childrenRect.height + Theme.layout.module.tileInset * 2
    VText { visible: card.title !== ""; x: Theme.layout.module.pad; height: Theme.layout.module.section; verticalAlignment: Text.AlignVCenter
      text: card.title; font.weight: Font.DemiBold; color: Theme.r.popover.ink }
    VText { visible: card.titleDetail !== ""; anchors.right: parent.right; anchors.rightMargin: Theme.layout.module.pad
      height: Theme.layout.module.section; verticalAlignment: Text.AlignVCenter; text: card.titleDetail; tone: "secondary" }
    MouseArea { visible: card.opens !== ""; width: parent.width; height: Theme.layout.module.section; onClicked: cc.push(card.opens) }
    Item { id: cardBody; y: (card.title ? Theme.layout.module.section : Theme.layout.module.tileInset); width: parent.width; height: childrenRect.height }
  }

  readonly property real gap: Theme.layout.module.gap

  // ================================================================ main page
  Component {
    id: mainPage
    Column {
      id: mp
      spacing: cc.gap
      readonly property real colW: (width - cc.gap) / 2

      // -- connectivity | focus + quick badges
      Item {
        width: parent.width; height: conn.height
        VTile {
          id: conn
          width: mp.colW; height: connCol.height + 2 * Theme.layout.module.tileInset
          Column {
            id: connCol; y: Theme.layout.module.tileInset; width: parent.width
            VToggleTile { width: parent.width; icon: "wifi"; title: "Wi-Fi"; on: cc.be.wifiOn
              subtitle: !cc.be.wifiOn ? "Off" : cc.be.wifiPending || cc.be.wifiName || "Not Connected"
              onToggled: cc.be.toggleWifi(); onOpened: cc.push("wifi") }
            VToggleTile { width: parent.width; icon: "bluetooth"; title: "Bluetooth"; on: cc.be.btOn
              subtitle: !cc.be.btOn ? "Off" : cc.be.btConnected.length === 1 ? (cc.be.btConnected[0].name || "1 Device") : cc.be.btConnected.length > 1 ? cc.be.btConnected.length + " Devices" : "On"
              onToggled: cc.be.toggleBluetooth(); onOpened: cc.push("bluetooth") }
            VToggleTile { width: parent.width; icon: "airdrop"; title: "AirDrop"; on: cc.be.localsendRunning
              subtitle: cc.be.localsendRunning ? "LocalSend On" : "Off"
              onToggled: cc.be.toggleAirdrop(); onOpened: cc.be.openAirdrop() }
          }
        }
        Column {
          x: mp.colW + cc.gap; width: mp.colW; spacing: cc.gap
          VTile {
            width: parent.width; height: Theme.layout.module.toggle + 2 * Theme.layout.module.tileInset
            VToggleTile { y: Theme.layout.module.tileInset; width: parent.width; icon: "focus"; title: "Focus"
              subtitle: cc.be.dnd ? "Do Not Disturb" : "Off"; on: cc.be.dnd
              onToggled: cc.be.setDnd(!cc.be.dnd); onOpened: cc.push("focus") }
          }
          VTile {
            id: quick
            width: parent.width; height: conn.height - Theme.layout.module.toggle - 2 * Theme.layout.module.tileInset - cc.gap
            readonly property real b: Theme.layout.module.quick
            Row {
              anchors.centerIn: parent
              spacing: (quick.width - 2 * Theme.layout.module.pad - 4 * quick.b) / 3
              VBadge { size: quick.b; icon: "moon"; on: Theme.dark; onTapped: cc.velum.set("appearance", Theme.dark ? "light" : "dark") }
              VBadge { size: quick.b; icon: "night-shift"; on: cc.be.nightShift; onTapped: cc.be.setNightShift(!cc.be.nightShift) }
              VBadge { size: quick.b; icon: cc.be.tilingLayout === "scrolling" ? "layout.columns" : "layout.tiles"; on: cc.be.tilingLayout === "scrolling"
                onTapped: cc.be.setTilingLayout(cc.be.tilingLayout === "scrolling" ? "dwindle" : "scrolling") }
              VBadge { size: quick.b; icon: cc.be.kbdAvailable ? "keyboard.light" : "display"; on: cc.be.kbdAvailable && cc.be.kbd.level > 0
                onTapped: cc.push(cc.be.kbdAvailable ? "keyboard" : "display") }
            }
          }
        }
      }

      // -- Now Playing
      VTile {
        visible: cc.be.player !== null
        width: parent.width; height: Theme.layout.module.toggle + 2 * Theme.layout.module.tileInset
        VBadge { id: art; x: Theme.layout.menu.itemPadX; anchors.verticalCenter: parent.verticalCenter; icon: "music"; on: cc.be.playing }
        Column {
          x: art.x + art.width + Theme.layout.menu.itemPadX; width: parent.width - x - transport.width - Theme.layout.module.pad
          anchors.verticalCenter: parent.verticalCenter
          VText { width: parent.width; elide: Text.ElideRight; text: cc.be.player ? (cc.be.player.trackTitle || cc.be.player.identity || "") : ""; font.weight: Font.DemiBold; color: Theme.r.popover.ink }
          VText { width: parent.width; elide: Text.ElideRight; text: cc.be.player ? (cc.be.player.trackArtist || "") : ""; tone: "secondary"; font.pixelSize: Theme.m.type.small }
        }
        Row {
          id: transport
          anchors.right: parent.right; anchors.rightMargin: Theme.layout.module.pad / 2; anchors.verticalCenter: parent.verticalCenter
          VButton { kind: "plain"; icon: "backward"; onClicked: cc.be.media.runAction("previous", false) }
          VButton { kind: "plain"; icon: cc.be.playing ? "pause" : "play"; onClicked: cc.be.media.runAction("playPause", false) }
          VButton { kind: "plain"; icon: "forward"; onClicked: cc.be.media.runAction("next", false) }
        }
      }

      // -- Display, Sound
      Card {
        title: "Display"; opens: "display"
        titleDetail: cc.be.brightnessAvailable ? cc.be.brightness + " %" : ""
        SliderRow { icon: "brightness"; opens: "display"; value: cc.be.brightness / 100; visible: cc.be.brightnessAvailable
          height: visible ? Theme.layout.module.row : 0
          onMoved: v => cc.be.setBrightness(v * 100) }
        MRow { visible: !cc.be.brightnessAvailable; height: visible ? Theme.layout.module.row : 0; icon: "display"
          text: cc.be.focusedMonitor || "Display"; detail: cc.be.monitorScale ? cc.be.monitorScale + "×" : ""; onClicked: cc.push("display") }
      }
      Card {
        title: "Sound"; opens: cc.be.airpodsActive ? "airpods" : "sound"
        titleDetail: cc.be.airpodsActive ? cc.be.airpodsName : ""
        SliderRow { icon: cc.be.muted ? "sound.low" : "sound"; opens: "sound"; value: cc.be.muted ? 0 : cc.be.volume
          onMoved: v => cc.be.setVolume(v) }
      }

      // -- battery, hardware, experiments
      VTile {
        width: parent.width; height: moreCol.height + 2 * Theme.layout.module.tileInset
        Column {
          id: moreCol; y: Theme.layout.module.tileInset; width: parent.width
          MRow {
            visible: cc.be.hasBattery; icon: "energy"; text: "Battery"
            detail: Math.round(cc.be.batteryLevel * 100) + " %" + (cc.be.batteryTime ? " · " + cc.be.batteryTime : "")
            onClicked: cc.push("battery")
            VBattery { height: Theme.layout.icon.small * 0.7; level: cc.be.batteryLevel; charging: cc.be.charging; plugged: cc.be.onAC && !cc.be.charging; ink: Theme.r.popover.ink }
          }
          MRow { icon: "cpu"; text: "Hardware"; detail: cc.be.hwSummary; onClicked: cc.push("hardware") }
          MRow { icon: "flask"; text: "Experiments"; onClicked: cc.push("experiments") }
          MRow { icon: "apps"; text: "Plugins"; onClicked: cc.pluginsRequested() }
        }
      }
    }
  }

  // ================================================================ Wi-Fi
  Component {
    id: wifiPage
    Column {
      MHead { title: "Wi-Fi"; VSwitch { surface: "popover"; checked: cc.be.wifiOn; onToggled: cc.be.toggleWifi() } }
      MSection { visible: cc.be.wifiOn; text: "Known Networks" }
      Repeater { model: cc.be.wifiOn ? cc.be.wifiRowsShown.filter(r => r.known || r.connected) : []; delegate: netRow }
      MSection { visible: cc.be.wifiOn; text: "Other Networks" }
      Repeater { model: cc.be.wifiOn ? cc.be.wifiRowsShown.filter(r => !r.known && !r.connected) : []; delegate: netRow }
      MSep {}
      MRow { text: "Advanced"; detail: cc.be.netInfo.ip || ""
        onClicked: cc.be.wifiAdvanced = !cc.be.wifiAdvanced
        VIcon { name: "chevron.right"; weight: "bold"; size: Theme.layout.icon.small; color: Theme.r.popover.inkSecondary; rotation: cc.be.wifiAdvanced ? 90 : 0
          Behavior on rotation { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } } } }
      Column {
        width: parent.width; visible: cc.be.wifiAdvanced
        MRow { clickable: false; text: "Network"; detail: (cc.be.netInfo.ssid || cc.be.netInfo.iface || "—") + (cc.be.netInfo.freq ? " · " + (parseFloat(cc.be.netInfo.freq) / 1000).toFixed(1) + " GHz" : "") }
        MRow { clickable: false; text: "Signal"; detail: cc.be.netInfo.signal_dbm ? cc.be.netInfo.signal_dbm + " dBm · " + (cc.be.netInfo.bitrate || "") : "—" }
        MRow { clickable: false; text: "Router"; detail: (cc.be.netInfo.gateway || "—") + (cc.be.routerPings.length ? " · " + cc.be.routerPings[cc.be.routerPings.length - 1] + " ms" : "") }
        MRow { clickable: false; text: "Internet"; detail: cc.be.internetPings.length ? cc.be.internetPings[cc.be.internetPings.length - 1] + " ms" : "—" }
        MRow { clickable: false; text: "Traffic"; detail: "↓ " + (cc.be.netDownRate / 1e6).toFixed(1) + "  ↑ " + (cc.be.netUpRate / 1e6).toFixed(1) + " MB/s" }
        MSection { text: "DNS" }
        Item { width: parent.width; height: Theme.m.control.height + Theme.layout.list.gap
          VSegment { x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter; model: ["DHCP", "Cloudflare", "Google", "Custom"]
            currentIndex: Math.max(0, model.indexOf(cc.be.dnsPending || cc.be.dnsProvider)); onActivated: i => cc.be.setDns(model[i]) } }
        MSection { visible: cc.be.bandInfo.available.length > 1; text: "Band" }
        Item { visible: cc.be.bandInfo.available.length > 1; width: parent.width; height: Theme.m.control.height + Theme.layout.list.gap
          VSegment { x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter
            model: ["auto"].concat(cc.be.bandInfo.available).map(b => b === "auto" ? "Automatic" : b + " GHz")
            currentIndex: Math.max(0, ["auto"].concat(cc.be.bandInfo.available).indexOf(cc.be.bandPending || cc.be.bandInfo.selected))
            onActivated: i => cc.be.setBand(["auto"].concat(cc.be.bandInfo.available)[i]) } }
        MSep {}
        MRow { icon: "qrcode"; text: "Share as QR Code"; visible: cc.be.netInfo.type === "wifi"; onClicked: cc.be.openWifiQr() }
        MRow { icon: "gauge"; text: "Speed Test"; onClicked: cc.be.openSpeedTest() }
      }
    }
  }
  Component {
    id: netRow
    Column {
      id: nr
      required property var modelData
      readonly property bool asking: cc.be.wifiPasswordFor === modelData.name
      width: parent ? parent.width : 0
      MRow {
        icon: "wifi"; text: nr.modelData.name
        checked: nr.modelData.connected; busy: cc.be.wifiPending === nr.modelData.name
        detail: cc.be.wifiFailed === nr.modelData.name ? "Failed" : ""
        onClicked: cc.be.wifiActivate(nr.modelData)
        VIcon { visible: nr.modelData.secure; name: "lock"; size: Theme.layout.icon.small; color: Theme.r.popover.inkSecondary }
      }
      // password (and identity for 802.1X), right under the network
      Column {
        visible: nr.asking
        x: Theme.layout.module.pad; width: parent.width - 2 * x; spacing: Theme.layout.list.gap
        topPadding: Theme.layout.list.gap / 2; bottomPadding: Theme.layout.list.gap
        VField { id: ident; visible: nr.modelData.enterprise; width: parent.width; placeholder: "Username"; text: cc.be.wifiIdentity }
        VField { id: pass; width: parent.width; placeholder: "Password"; secret: true; onAccepted: join.clicked() }
        Row {
          anchors.right: parent.right; spacing: Theme.layout.list.gap
          VButton { text: "Cancel"; onClicked: cc.be.wifiPasswordFor = "" }
          VButton { id: join; kind: "primary"; text: "Join"; onClicked: nr.modelData.enterprise
            ? cc.be.wifiConnectEnterprise(nr.modelData.name, ident.text, pass.text) : cc.be.wifiConnectWithPassword(nr.modelData.name, pass.text) }
        }
      }
      onAskingChanged: if (asking) Qt.callLater(function () { (nr.modelData.enterprise && !ident.text ? ident : pass).focusField() })
    }
  }

  // ================================================================ Bluetooth
  Component {
    id: btPage
    Column {
      MHead { title: "Bluetooth"; VSwitch { surface: "popover"; checked: cc.be.btOn; onToggled: cc.be.toggleBluetooth() } }
      MSection { visible: cc.be.btOn; text: "Devices" }
      Repeater {
        model: cc.be.btOn ? cc.be.btRows : []
        MRow {
          required property var modelData
          icon: cc.be.btIconName(modelData.icon); text: modelData.name
          busy: cc.be.btPending[modelData.address] !== undefined
          detail: busy ? "" : modelData.connected ? (modelData.battery >= 0 ? modelData.battery + " %" : "Connected") : modelData.paired ? "" : "New"
          checked: modelData.connected
          onClicked: cc.be.btActivate(modelData)
        }
      }
      MSep {}
      MRow { text: "Bluetooth Settings…"; onClicked: { cc.closeRequested(); Quickshell.execDetached(["omarchy-launch-bluetooth"]) } }
    }
  }

  // ================================================================ Sound
  Component {
    id: soundPage
    Column {
      MHead { title: "Sound" }
      MSection { text: "Output Volume" }
      SliderRow { icon: "sound.low"; iconEnd: "sound"; value: cc.be.muted ? 0 : cc.be.volume; onMoved: v => cc.be.setVolume(v); onIconClicked: cc.be.toggleMute() }
      MSection { text: "Output" }
      Repeater {
        model: cc.be.sinkRows
        MRow { required property var modelData; icon: cc.be.sinkIconName(modelData.label); text: modelData.label; checked: modelData.active; onClicked: cc.be.setSink(modelData) }
      }
      MSep { visible: cc.be.airpodsActive }
      MRow { visible: cc.be.airpodsActive; icon: "headphones"; text: cc.be.airpodsName
        detail: cc.be.airpodsLevel >= 0 ? cc.be.airpodsLevel + " %" : ""; onClicked: cc.push("airpods")
        VIcon { name: "chevron.right"; weight: "bold"; size: Theme.layout.icon.small; color: Theme.r.popover.inkSecondary } }
    }
  }
  Component {
    id: podsPage
    Column {
      readonly property var pods: cc.be.podService
      MHead { title: cc.be.airpodsName }
      Repeater {
        model: cc.be.airpodsBatteries
        MRow { required property var modelData; clickable: false; text: modelData.label
          detail: modelData.level === Pods.LEVEL_UNKNOWN ? "—" : modelData.level + " %"
          VBattery { height: Theme.layout.icon.small * 0.7; level: Math.max(0, modelData.level) / 100; charging: modelData.charging; ink: Theme.r.popover.ink } }
      }
      MSection { visible: pods.supportsNoiseControl; text: "Noise Control" }
      Item { visible: pods.supportsNoiseControl; width: parent.width; height: Theme.m.control.height + Theme.layout.list.gap
        VSegment { x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter
          model: cc.be.airpodsModes.map(m => Pods.noiseModeName(m) === "Noise Cancellation" ? "Noise Cancel" : Pods.noiseModeName(m))
          currentIndex: Math.max(0, cc.be.airpodsModes.indexOf(pods.noiseMode)); onActivated: i => pods.setNoiseMode(cc.be.airpodsModes[i]) } }
      MRow { visible: pods.supportsConversationalAwareness; clickable: false; text: "Conversation Awareness"
        VSwitch { surface: "popover"; checked: pods.conversationalAwareness; onToggled: c => pods.setConversationalAwareness(c) } }
      MSep {}
      MRow { text: pods.connected ? "Disconnect" : "Connect"; busy: pods.connectionBusy; onClicked: pods.toggleConnection() }
    }
  }

  // ================================================================ Display
  Component {
    id: displayPage
    Column {
      MHead { title: "Display" }
      MSection { visible: cc.be.brightnessAvailable; text: "Brightness" }
      SliderRow { visible: cc.be.brightnessAvailable; icon: "brightness.low"; iconEnd: "brightness"; value: cc.be.brightness / 100; onMoved: v => cc.be.setBrightness(v * 100) }
      MRow { icon: "night-shift"; text: "Night Shift"; clickable: false
        VSwitch { surface: "popover"; checked: cc.be.nightShift; onToggled: c => cc.be.setNightShift(c) } }
      MSection { text: "Appearance" }
      Item { width: parent.width; height: Theme.m.control.height + Theme.layout.list.gap
        VSegment { x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter; model: ["Automatic", "Light", "Dark"]
          currentIndex: ["auto", "light", "dark"].indexOf(cc.velum.values.appearance || "auto"); onActivated: i => cc.velum.set("appearance", ["auto", "light", "dark"][i]) } }
      MSection { text: "Style" }
      Item { width: parent.width; height: Theme.m.control.height + Theme.layout.list.gap
        VSegment { x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter; model: ["Pearl", "Glass", "Paper", "Slate"]
          currentIndex: Math.max(0, ["pearl", "glass", "paper", "slate"].indexOf(Theme.variant)); onActivated: i => cc.velum.set("variant", ["pearl", "glass", "paper", "slate"][i]) } }
      MSection { text: "Text Size" }
      SliderRow { icon: "text"; value: cc.be.textSizeIndex / (cc.be.textSizeStops.length - 1)
        onMoved: v => cc.be.setTextSizeIndex(v * (cc.be.textSizeStops.length - 1)) }
      MSection { visible: cc.be.scalePresets.length > 1; text: "Scale" }
      Item { visible: cc.be.scalePresets.length > 1; width: parent.width; height: Theme.m.control.height + Theme.layout.list.gap
        VSegment { x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter; model: cc.be.scalePresets.map(s => s + "×")
          currentIndex: Math.max(0, cc.be.scalePresets.indexOf(cc.be.monitorScale)); onActivated: i => cc.be.setScale(cc.be.scalePresets[i]) } }
      MSection { visible: cc.be.displays.length > 1; text: "Displays" }
      Repeater {
        model: cc.be.displays.length > 1 ? cc.be.displays : []
        MRow { required property var modelData; icon: modelData.name === cc.be.internalMonitor ? "laptop" : "desktop"
          text: modelData.description || modelData.name; checked: modelData.enabled; dim: !modelData.enabled
          onClicked: cc.be.toggleDisplay(modelData) }
      }
    }
  }

  // ================================================================ Focus
  Component {
    id: focusPage
    Column {
      MHead { title: "Focus" }
      MRow { icon: "focus"; text: "Do Not Disturb"; clickable: false
        VSwitch { surface: "popover"; checked: cc.be.dnd; onToggled: c => cc.be.setDnd(c) } }
      VText { x: Theme.layout.module.pad; width: parent.width - 2 * x; wrapMode: Text.WordWrap; tone: "secondary"; font.pixelSize: Theme.m.type.small
        bottomPadding: Theme.layout.list.gap
        text: "Notifications stay in the Notification Center and do not show banners." }
    }
  }

  // ================================================================ Keyboard
  Component {
    id: kbdPage
    Column {
      MHead { title: "Keyboard Brightness" }
      SliderRow { icon: "keyboard.light"; value: cc.be.kbd ? cc.be.kbd.level : 0; onMoved: v => cc.be.kbd.setLevel(v) }
      MSection { text: "Turn Off After Inactivity" }
      Item { width: parent.width; height: Theme.m.control.height + Theme.layout.list.gap
        VSegment { x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter
          model: cc.be.kbd ? cc.be.kbd.timeoutChoices.map(s => cc.be.kbdTimeoutLabel(s)) : []
          currentIndex: cc.be.kbd ? Math.max(0, cc.be.kbd.timeoutChoices.indexOf(cc.be.kbd.timeout)) : 0
          onActivated: i => cc.be.kbd.setTimeoutSeconds(cc.be.kbd.timeoutChoices[i]) } }
    }
  }

  // ================================================================ Battery
  Component {
    id: batteryPage
    Column {
      MHead { title: "Battery"; VText { text: Math.round(cc.be.batteryLevel * 100) + " %"; font.weight: Font.DemiBold; color: Theme.r.popover.ink } }
      MRow { clickable: false; text: "Power Source"; detail: cc.be.onAC ? "Power Adapter" : "Battery" }
      MRow { clickable: false; visible: cc.be.batteryTime !== ""; text: cc.be.charging ? "Until Full" : "Remaining"; detail: cc.be.batteryTime.replace(/ (until full|left)$/, "") }
      MSection { text: "Energy Mode" }
      Item { width: parent.width; height: Theme.m.control.height + Theme.layout.list.gap
        VSegment { x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter; model: ["Low Power", "Automatic", "High Power"]
          currentIndex: cc.be.powerProfile; onActivated: i => cc.be.setPowerProfile(i) } }
    }
  }

  // ================================================================ Hardware
  Component {
    id: hwPage
    Column {
      readonly property var hw: cc.be.hw
      MHead { title: "Hardware" }
      MRow { clickable: false; icon: "cpu"; text: hw.model || "Processor"; detail: cc.be.cpuLoad >= 0 ? cc.be.cpuLoad + " %" : "" }
      MRow { clickable: false; text: "Frequency"; detail: cc.be.formatGHz(hw.freqAvg) + " · peak " + cc.be.formatGHz(hw.freqPeak) }
      MRow { clickable: false; visible: hw.temp >= 0; text: "Temperature"; detail: hw.temp + " °C" }
      Repeater { model: hw.fans || []
        MRow { required property var modelData; required property int index; clickable: false; text: modelData.label || "Fan " + (index + 1); detail: modelData.rpm + " rpm" } }
      MSep {}
      MRow { clickable: false; text: "Memory"; detail: cc.be.formatGiB(hw.memTotal - hw.memAvail, 1) + " / " + cc.be.formatGiB(hw.memTotal, 0) + " GB" }
      MRow { clickable: false; visible: hw.swapTotal > 0; text: "Swap"; detail: Math.round(cc.be.swapUsedFrac * 100) + " %" }
      MRow { clickable: false; icon: "disk"; text: "Disk"; detail: cc.be.formatBytesGB(hw.diskUsed) + " / " + cc.be.formatBytesGB(hw.diskTotal) }
      MRow { clickable: false; text: "Uptime"; detail: cc.be.formatUptime(hw.uptime) }
    }
  }

  // ================================================================ Experiments
  Component {
    id: expPage
    Column {
      MHead { title: "Experiments" }
      MRow { text: "Low-Power Rendering"; clickable: false
        VSwitch { surface: "popover"; checked: cc.be.renderPowerOn; onToggled: c => cc.be.setRenderPower(c) } }
      MRow { text: "No Effects"; clickable: false
        VSwitch { surface: "popover"; checked: cc.be.noEffectsOn; onToggled: c => cc.be.setNoEffects(c) } }
      VText { x: Theme.layout.module.pad; width: parent.width - 2 * x; wrapMode: Text.WordWrap; tone: "secondary"; font.pixelSize: Theme.m.type.small
        bottomPadding: Theme.layout.list.gap
        text: "No Effects turns off blur, shadows and window animations." }
    }
  }
}
