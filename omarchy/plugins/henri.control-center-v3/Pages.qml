import QtQuick
import QtQuick.Effects
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
  implicitHeight: stack.implicitHeight

  // ---- navigation (the backend scans/polls only on the page that shows it)
  property var names: []
  readonly property string current: names.length ? names[names.length - 1] : "main"
  onCurrentChanged: if (be) be.page = current
  readonly property var pageFor: ({ wifi: wifiPage, bluetooth: btPage, sound: soundPage, airpods: podsPage, display: displayPage,
                                    focus: focusPage, keyboard: kbdPage, hardware: hwPage, experiments: expPage,
                                    battery: power.page("battery"), "battery-history": power.page("battery-history") })
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
    readonly property real naturalHeight: (title ? Theme.layout.module.section : 0) + cardBody.childrenRect.height + Theme.layout.module.tileInset * 2
    height: naturalHeight
    VText { id: cardTitle; visible: card.title !== ""; x: Theme.layout.module.pad; height: Theme.layout.module.section; verticalAlignment: Text.AlignVCenter
      text: card.title; font.weight: Font.DemiBold; color: Theme.r.popover.ink }
    VText { visible: card.titleDetail !== ""; anchors.right: parent.right; anchors.rightMargin: Theme.layout.module.pad
      width: Math.min(implicitWidth, card.width - cardTitle.x - cardTitle.width - 2 * Theme.layout.module.pad); elide: Text.ElideRight
      horizontalAlignment: Text.AlignRight; height: Theme.layout.module.section; verticalAlignment: Text.AlignVCenter; text: card.titleDetail; tone: "secondary" }
    MouseArea { visible: card.opens !== ""; width: parent.width; height: Theme.layout.module.section; onClicked: cc.push(card.opens) }
    Item { id: cardBody; y: (card.title ? Theme.layout.module.section : Theme.layout.module.tileInset); width: parent.width; height: childrenRect.height }
  }

  // a tile of rows with an optional title (the detail pages' building block)

  // the head tile of a detail page: a large badge, a title, what it is doing; a control may stand right

  component SegmentRow: Item {
    property alias model: seg.model
    property alias currentIndex: seg.currentIndex
    signal activated(int i)
    width: parent ? parent.width : 0; height: Theme.m.control.height + Theme.layout.list.gap
    VSegment { id: seg; x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter; onActivated: i => parent.activated(i) }
  }

  readonly property real gap: Theme.layout.module.gap

  // ================================================================ main page
  Component {
    id: mainPage
    Column {
      id: mp
      spacing: cc.gap
      readonly property real colW: (width - cc.gap) / 2

      // the tiles come in one after the other when the island opens (stagger.step apart, at most stagger.max)
      property real t: 1
      readonly property int step: Theme.core.motion.stagger.step
      NumberAnimation { id: revealAnim; target: mp; property: "t"; from: 0; to: 1; duration: Theme.dur("fast") + mp.step * Theme.core.motion.stagger.max }
      function reveal() {
        if (Theme.reduceMotion) return
        var shownKids = []
        for (var i = 0; i < children.length; i++) if (children[i].visible) shownKids.push(children[i])
        var total = revealAnim.duration
        shownKids.forEach(function (c, k) {
          var start = Math.min(k, Theme.core.motion.stagger.max) * mp.step / total, len = Theme.dur("fast") / total
          c.opacity = Qt.binding(function () { var x = Math.max(0, Math.min(1, (mp.t - start) / len)); return 1 - Math.pow(1 - x, 3) })
        })
        revealAnim.restart()
      }
      Connections { target: cc.be; function onOpenedChanged() { if (cc.be.opened && cc.current === "main") mp.reveal() } }

      // -- every workspace as a miniature; a click switches there
      Spaces { width: parent.width; active: cc.be.opened && cc.current === "main"; onChosen: cc.closeRequested() }

      // -- connectivity | focus + quick badges
      Item {
        width: parent.width; height: conn.height
        VTile {
          id: conn
          width: mp.colW; height: connCol.height + 2 * Theme.layout.module.tileInset
          Column {
            id: connCol; y: Theme.layout.module.tileInset; width: parent.width
            VToggleTile { width: parent.width; icon: "wifi"; title: "Wi-Fi"; on: cc.be.wifiOn
              glyph: cc.be.wifiOn && cc.be.wifiName ? wifiGlyph : null
              subtitle: !cc.be.wifiOn ? "Off" : cc.be.wifiPending || cc.be.wifiName || "Not Connected"
              onToggled: cc.be.toggleWifi(); onOpened: cc.push("wifi") }
            VToggleTile { width: parent.width; icon: "bluetooth"; title: "Bluetooth"; on: cc.be.btOn
              subtitle: !cc.be.btOn ? "Off" : cc.be.btConnected.length === 1 ? (cc.be.btConnected[0].name || "1 Device") + cc.btBattery(cc.be.btConnected[0])
                        : cc.be.btConnected.length > 1 ? cc.be.btConnected.length + " Devices" : "On"
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

      // -- Now Playing: cover, title, a progress line, transport
      VTile {
        id: np
        visible: cc.be.player !== null
        readonly property var pl: cc.be.player
        readonly property bool timed: pl !== null && pl.positionSupported === true && pl.lengthSupported === true && pl.length > 0
        width: parent.width; height: npRow.height + (timed ? Theme.layout.module.pad + Theme.layout.meter.bar : 0) + 2 * Theme.layout.module.pad
        // MPRIS only reports the position when asked
        Timer { interval: 1000; repeat: true; running: np.visible && cc.be.playing && np.timed; onTriggered: np.pl.positionChanged() }
        // the cover, blurred, as the tile's ground
        Item { id: npBg; anchors.fill: parent; visible: false; layer.enabled: true
          Image { anchors.fill: parent; source: art.source; fillMode: Image.PreserveAspectCrop; asynchronous: true
            sourceSize: Qt.size(Theme.layout.module.toggle, Theme.layout.module.toggle) } }
        Rectangle { id: npMask; anchors.fill: parent; radius: np.radius; visible: false; layer.enabled: true }
        MultiEffect {
          anchors.fill: parent; source: npBg
          blurEnabled: true; blur: 1; blurMax: Theme.layout.meter.coverBlur
          maskEnabled: true; maskSource: npMask
          opacity: art.ready ? Theme.core.alpha.cover : 0
          Behavior on opacity { NumberAnimation { duration: Theme.dur("slow") } }
        }
        Item {
          id: npRow
          x: Theme.layout.module.pad; y: Theme.layout.module.pad; width: parent.width - 2 * x; height: Theme.layout.module.toggle
          VArtwork { id: art; size: parent.height; anchors.verticalCenter: parent.verticalCenter
            source: np.pl && np.pl.trackArtUrl ? np.pl.trackArtUrl : "" }
          Column {
            x: art.width + Theme.layout.module.pad; width: parent.width - x - transport.width - Theme.layout.list.gap
            anchors.verticalCenter: parent.verticalCenter
            VText { width: parent.width; elide: Text.ElideRight; text: np.pl ? (np.pl.trackTitle || np.pl.identity || "") : ""; font.weight: Font.DemiBold; color: Theme.r.popover.ink }
            VText { width: parent.width; elide: Text.ElideRight; text: np.pl ? (np.pl.trackArtist || np.pl.identity || "") : ""; tone: "secondary"; font.pixelSize: Theme.m.type.small }
          }
          Row {
            id: transport
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            VButton { kind: "plain"; icon: "backward"; onClicked: cc.be.media.runAction("previous", false) }
            VButton { kind: "plain"; icon: cc.be.playing ? "pause" : "play"; onClicked: cc.be.media.runAction("playPause", false) }
            VButton { kind: "plain"; icon: "forward"; onClicked: cc.be.media.runAction("next", false) }
          }
        }
        Item {
          visible: np.timed
          x: Theme.layout.module.pad; y: npRow.y + npRow.height + Theme.layout.module.pad; width: parent.width - 2 * x; height: Theme.layout.meter.bar
          VText { id: npPos; anchors.verticalCenter: parent.verticalCenter; tone: "secondary"; font.pixelSize: Theme.m.type.small
            text: cc.formatTime(np.pl ? np.pl.position : 0) }
          VText { id: npLen; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; tone: "secondary"; font.pixelSize: Theme.m.type.small
            text: cc.formatTime(np.pl ? np.pl.length : 0) }
          VMeter { x: npPos.width + Theme.layout.list.gap; width: npLen.x - x - Theme.layout.list.gap; anchors.verticalCenter: parent.verticalCenter
            value: np.timed ? np.pl.position / np.pl.length : 0 }
        }
      }

      // -- Display | Sound: thick sliders, side by side (one height: the taller card)
      Row {
        spacing: cc.gap
        readonly property real cardH: Math.max(dispCard.naturalHeight, soundCard.naturalHeight)
        Card {
          id: dispCard; width: mp.colW; height: parent.cardH
          title: "Display"; opens: "display"
          titleDetail: cc.be.brightnessAvailable ? "" : (cc.be.focusedMonitor || "")
          Item {
            visible: cc.be.brightnessAvailable; width: parent.width; height: visible ? Theme.layout.meter.slider + Theme.layout.module.pad : 0
            VFillSlider { x: Theme.layout.module.pad; width: parent.width - 2 * x; icon: "brightness"
              value: cc.be.brightness / 100; readout: cc.be.brightness + " %"; onMoved: v => cc.be.setBrightness(v * 100) }
          }
          MRow { visible: !cc.be.brightnessAvailable; height: visible ? Theme.layout.module.row : 0; icon: "display"
            text: "Appearance"; detail: Theme.variant.charAt(0).toUpperCase() + Theme.variant.slice(1) + " · " + (Theme.dark ? "Dark" : "Light")
            onClicked: cc.push("display") }
        }
        Card {
          id: soundCard; width: mp.colW; height: parent.cardH
          title: "Sound"; opens: cc.be.airpodsActive ? "airpods" : "sound"
          titleDetail: cc.be.airpodsActive ? cc.be.airpodsName : (cc.be.sinkRows.filter(r => r.active).map(r => r.label)[0] || "")
          Item {
            width: parent.width; height: Theme.layout.meter.slider + Theme.layout.module.pad
            VFillSlider { x: Theme.layout.module.pad; width: parent.width - 2 * x
              icon: cc.be.muted || cc.be.volume <= 0 ? "sound.mute" : cc.be.volume < 0.34 ? "sound.low" : cc.be.volume < 0.67 ? "sound.mid" : "sound"
              value: cc.be.muted ? 0 : cc.be.volume; readout: cc.be.muted ? "Muted" : Math.round(cc.be.volume * 100) + " %"
              onMoved: v => cc.be.setVolume(v); onIconClicked: cc.be.toggleMute() }
          }
        }
      }

      // -- battery and hardware as small widgets (each opens its page)
      Row {
        spacing: cc.gap
        WidgetTile {
          visible: cc.be.hasBattery
          width: mp.colW; onClicked: cc.push("battery")
          VBatteryArt { id: wbat; x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter; size: Theme.layout.meter.battery / 2
            level: cc.be.batteryLevel; charging: cc.be.charging; plugged: cc.be.onAC && !cc.be.charging }
          Column {
            x: wbat.x + wbat.width + Theme.layout.module.pad; width: parent.width - x - Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter
            VText { text: Math.round(cc.be.batteryLevel * 100) + " %"; color: Theme.r.popover.ink; font.pixelSize: Theme.m.type.title; font.weight: Font.DemiBold }
            VText { width: parent.width; elide: Text.ElideRight; tone: "secondary"; font.pixelSize: Theme.m.type.small
              text: cc.be.batteryTime ? cc.be.batteryTime : cc.be.charging ? "Charging" : cc.be.onAC ? "Power Adapter" : "Battery" }
          }
        }
        WidgetTile {
          width: cc.be.hasBattery ? mp.colW : mp.width; onClicked: cc.push("hardware")
          Row {
            anchors.centerIn: parent; spacing: Theme.layout.module.pad * 2
            MiniRing { value: Math.max(0, cc.be.cpuLoad) / 100; label: "CPU" }
            MiniRing { value: cc.be.memUsedFrac; label: "Memory" }
          }
        }
      }
    }
  }
  function btBattery(d) { return d && d.batteryAvailable ? " · " + Math.round((d.battery || 0) * 100) + " %" : "" }
  Component { id: wifiGlyph
    VSignal { size: Theme.layout.module.badge * Theme.layout.icon.badge * 1.15; color: Theme.r.ink.onAccent
      level: { var c = cc.be.wifiRows.filter(r => r.connected); return c.length ? c[0].signal / 100 : 1 } } }
  function formatTime(sec) {
    var s = Math.max(0, Math.floor(sec)), m = Math.floor(s / 60)
    return m + ":" + (s % 60 < 10 ? "0" : "") + s % 60
  }
  // a tile that opens a page, pressed like a badge
  component WidgetTile: VTile {
    id: wt
    signal clicked()
    height: Theme.layout.meter.card
    Spring { id: wtPress; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: wtMouse.pressed ? Theme.scale("press") : 1 }
    scale: wtPress.value
    Rectangle { anchors.fill: parent; radius: parent.radius; color: Theme.r.popover.fillHover; visible: wtMouse.containsMouse }
    MouseArea { id: wtMouse; anchors.fill: parent; hoverEnabled: true; onClicked: wt.clicked() }
  }
  component MiniRing: Column {
    id: mr
    property real value: 0
    property string label: ""
    spacing: Theme.layout.list.gap / 4
    VRing { anchors.horizontalCenter: parent.horizontalCenter; size: Theme.layout.module.quick; line: Theme.layout.meter.bar
      value: mr.value; color: mr.value >= 0.9 ? Theme.r.danger : Theme.r.accent.base
      VText { anchors.centerIn: parent; text: Math.round(mr.value * 100); color: Theme.r.popover.ink; font.pixelSize: Theme.m.type.small; font.weight: Font.DemiBold } }
    VText { anchors.horizontalCenter: parent.horizontalCenter; text: mr.label; tone: "secondary"; font.pixelSize: Theme.m.type.small }
  }

  // ================================================================ Wi-Fi
  Component {
    id: wifiPage
    Column {
      spacing: cc.gap
      MHead { title: "Wi-Fi" }
      Hero {
        on: cc.be.wifiOn
        title: !cc.be.wifiOn ? "Wi-Fi" : cc.be.wifiName || "Not Connected"
        subtitle: !cc.be.wifiOn ? "Off" : cc.be.wifiName ? "Connected" + (cc.be.netInfo.ip ? " · " + cc.be.netInfo.ip : "") : "Choose a network"
        glyph: Component { VSignal { size: Theme.layout.icon.large * 1.2; color: cc.be.wifiOn ? Theme.r.ink.onAccent : Theme.r.popover.ink
          level: { var c = cc.be.wifiRows.filter(r => r.connected); return !cc.be.wifiOn ? 0 : c.length ? c[0].signal / 100 : 0 } } }
        onBadgeTapped: cc.be.toggleWifi()
        VSwitch { surface: "popover"; checked: cc.be.wifiOn; onToggled: cc.be.toggleWifi() }
      }
      Group {
        visible: cc.be.wifiOn && cc.be.wifiRowsShown.some(r => r.known || r.connected)
        title: "Known Networks"
        Repeater { model: cc.be.wifiOn ? cc.be.wifiRowsShown.filter(r => r.known || r.connected) : []; delegate: netRow }
      }
      Group {
        visible: cc.be.wifiOn && cc.be.wifiRowsShown.some(r => !r.known && !r.connected)
        title: "Other Networks"
        titleDetail: cc.be.wifiScanning ? "Searching…" : ""
        Repeater { model: cc.be.wifiOn ? cc.be.wifiRowsShown.filter(r => !r.known && !r.connected) : []; delegate: netRow }
      }
      Group {
        MRow { text: "Advanced"; detail: cc.be.netInfo.ip || ""
          onClicked: cc.be.wifiAdvanced = !cc.be.wifiAdvanced
          VIcon { name: "chevron.right"; weight: "bold"; size: Theme.layout.icon.small; color: Theme.r.popover.inkSecondary; rotation: cc.be.wifiAdvanced ? 90 : 0
            Behavior on rotation { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } } } }
        Column {
          width: parent.width; visible: cc.be.wifiAdvanced
          MSep {}
          MRow { clickable: false; text: "Network"; detail: (cc.be.netInfo.ssid || cc.be.netInfo.iface || "—") + (cc.be.netInfo.freq ? " · " + (parseFloat(cc.be.netInfo.freq) / 1000).toFixed(1) + " GHz" : "") }
          MRow { clickable: false; text: "Signal"; detail: cc.be.netInfo.signal_dbm ? cc.be.netInfo.signal_dbm + " dBm · " + (cc.be.netInfo.bitrate || "") : "—" }
          MRow { clickable: false; text: "Router"; detail: (cc.be.netInfo.gateway || "—") + (cc.be.routerPings.length ? " · " + cc.be.routerPings[cc.be.routerPings.length - 1] + " ms" : "") }
          MRow { clickable: false; text: "Internet Latency"; detail: cc.be.internetPings.length ? cc.be.internetPings[cc.be.internetPings.length - 1] + " ms" : "—" }
          VChart {
            visible: cc.be.internetPings.length > 1
            x: Theme.layout.module.pad; width: parent.width - 2 * x; height: visible ? Theme.layout.meter.chart : 0
            readonly property real peak: Math.max.apply(null, cc.be.internetPings.concat(cc.be.routerPings, [1])) * 1.25   // headroom over the peak
            values: cc.be.internetPings.map(v => v / peak)
          }
          MRow { clickable: false; text: "Traffic"; detail: "↓ " + (cc.be.netDownRate / 1e6).toFixed(1) + "  ↑ " + (cc.be.netUpRate / 1e6).toFixed(1) + " MB/s" }
          MSection { text: "DNS" }
          SegmentRow { model: ["DHCP", "Cloudflare", "Google", "Custom"]
            currentIndex: Math.max(0, model.indexOf(cc.be.dnsPending || cc.be.dnsProvider)); onActivated: i => cc.be.setDns(model[i]) }
          MSection { visible: cc.be.bandInfo.available.length > 1; text: "Band" }
          SegmentRow { visible: cc.be.bandInfo.available.length > 1
            model: ["auto"].concat(cc.be.bandInfo.available).map(b => b === "auto" ? "Automatic" : b + " GHz")
            currentIndex: Math.max(0, ["auto"].concat(cc.be.bandInfo.available).indexOf(cc.be.bandPending || cc.be.bandInfo.selected))
            onActivated: i => cc.be.setBand(["auto"].concat(cc.be.bandInfo.available)[i]) }
          MSep {}
          MRow { icon: "qrcode"; text: "Share as QR Code"; visible: cc.be.netInfo.type === "wifi"; onClicked: cc.be.openWifiQr() }
          MRow { icon: "gauge"; text: "Speed Test"; onClicked: cc.be.openSpeedTest() }
        }
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
        leading: Component { VSignal { level: nr.modelData.signal / 100; color: nr.modelData.connected ? Theme.r.accent.base : Theme.r.popover.ink } }
        text: nr.modelData.name
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
  component BtRow: MRow {
    required property var modelData
    icon: cc.be.btIconName(modelData.icon); text: modelData.name
    busy: cc.be.btPending[modelData.address] !== undefined
    detail: busy ? "" : modelData.connected ? (modelData.battery >= 0 ? modelData.battery + " %" : "Connected") : modelData.paired ? "Not Connected" : ""
    checked: modelData.connected
    onClicked: cc.be.btActivate(modelData)
    VBattery { visible: modelData.connected && modelData.battery >= 0; height: Theme.layout.icon.small * 0.7
      level: Math.max(0, modelData.battery) / 100; ink: Theme.r.popover.ink }
  }
  Component {
    id: btPage
    Column {
      spacing: cc.gap
      MHead { title: "Bluetooth" }
      Hero {
        icon: "bluetooth"; on: cc.be.btOn; title: "Bluetooth"
        subtitle: !cc.be.btOn ? "Off" : cc.be.btConnected.length === 1 ? (cc.be.btConnected[0].name || "1 Device") + " connected"
                  : cc.be.btConnected.length > 1 ? cc.be.btConnected.length + " devices connected" : cc.be.btDiscovering ? "Looking for devices…" : "On"
        onBadgeTapped: cc.be.toggleBluetooth()
        VSwitch { surface: "popover"; checked: cc.be.btOn; onToggled: cc.be.toggleBluetooth() }
      }
      Group {
        visible: cc.be.btOn && cc.be.btRows.some(r => r.paired || r.connected); title: "My Devices"
        Repeater { model: cc.be.btOn ? cc.be.btRows.filter(r => r.paired || r.connected) : []; BtRow {} }
      }
      Group {
        visible: cc.be.btOn && cc.be.btRows.some(r => !r.paired && !r.connected); title: "Nearby"
        Repeater { model: cc.be.btOn ? cc.be.btRows.filter(r => !r.paired && !r.connected) : []; BtRow {} }
      }
      Group {
        MRow { icon: "settings"; text: "Bluetooth Settings…"; onClicked: { cc.closeRequested(); Quickshell.execDetached(["omarchy-launch-bluetooth"]) } }
      }
    }
  }

  // ================================================================ Sound
  Component {
    id: soundPage
    Column {
      spacing: cc.gap
      MHead { title: "Sound" }
      Group {
        title: "Output Volume"; titleDetail: cc.be.muted ? "Muted" : Math.round(cc.be.volume * 100) + " %"
        SliderRow { icon: cc.be.muted ? "sound.mute" : "sound.low"; iconEnd: "sound"; value: cc.be.muted ? 0 : cc.be.volume; onMoved: v => cc.be.setVolume(v); onIconClicked: cc.be.toggleMute() }
      }
      Group {
        title: "Output"
        Repeater {
          model: cc.be.sinkRows
          MRow { required property var modelData; icon: cc.be.sinkIconName(modelData.label); text: modelData.label; checked: modelData.active; onClicked: cc.be.setSink(modelData) }
        }
      }
      Group {
        visible: cc.be.airpodsActive
        MRow { icon: "headphones"; text: cc.be.airpodsName
          detail: cc.be.airpodsLevel >= 0 ? cc.be.airpodsLevel + " %" : ""; onClicked: cc.push("airpods")
          VIcon { name: "chevron.right"; weight: "bold"; size: Theme.layout.icon.small; color: Theme.r.popover.inkSecondary } }
      }
    }
  }
  Component {
    id: podsPage
    Column {
      readonly property var pods: cc.be.podService
      spacing: cc.gap
      MHead { title: cc.be.airpodsName }
      // the buds and the case as batteries side by side
      Row {
        spacing: cc.gap
        Repeater {
          model: cc.be.airpodsBatteries
          VTile {
            required property var modelData
            width: (cc.width - (cc.be.airpodsBatteries.length - 1) * cc.gap) / Math.max(1, cc.be.airpodsBatteries.length); height: Theme.layout.meter.hero
            Column {
              anchors.centerIn: parent; spacing: Theme.layout.list.gap
              VBatteryArt { anchors.horizontalCenter: parent.horizontalCenter; size: Theme.layout.meter.battery / 2
                level: Math.max(0, modelData.level) / 100; charging: modelData.charging }
              VText { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.level === Pods.LEVEL_UNKNOWN ? "—" : modelData.level + " %"
                color: Theme.r.popover.ink; font.weight: Font.DemiBold }
              VText { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.label; tone: "secondary"; font.pixelSize: Theme.m.type.small }
            }
          }
        }
      }
      Group {
        visible: pods.supportsNoiseControl || pods.supportsConversationalAwareness
        title: pods.supportsNoiseControl ? "Noise Control" : ""
        SegmentRow { visible: pods.supportsNoiseControl
          model: cc.be.airpodsModes.map(m => Pods.noiseModeName(m) === "Noise Cancellation" ? "Noise Cancel" : Pods.noiseModeName(m))
          currentIndex: Math.max(0, cc.be.airpodsModes.indexOf(pods.noiseMode)); onActivated: i => pods.setNoiseMode(cc.be.airpodsModes[i]) }
        MRow { visible: pods.supportsConversationalAwareness; clickable: false; text: "Conversation Awareness"
          VSwitch { surface: "popover"; checked: pods.conversationalAwareness; onToggled: c => pods.setConversationalAwareness(c) } }
      }
      Group {
        MRow { text: pods.connected ? "Disconnect" : "Connect"; busy: pods.connectionBusy; onClicked: pods.toggleConnection() }
      }
    }
  }

  // ================================================================ Display
  Component {
    id: displayPage
    Column {
      spacing: cc.gap
      MHead { title: "Display" }
      Group {
        title: cc.be.brightnessAvailable ? "Brightness" : ""
        titleDetail: cc.be.brightnessAvailable ? cc.be.brightness + " %" : ""
        SliderRow { visible: cc.be.brightnessAvailable; icon: "brightness.low"; iconEnd: "brightness"; value: cc.be.brightness / 100; onMoved: v => cc.be.setBrightness(v * 100) }
        MRow { icon: "night-shift"; text: "Night Shift"; clickable: false
          VSwitch { surface: "popover"; checked: cc.be.nightShift; onToggled: c => cc.be.setNightShift(c) } }
      }
      Group {
        title: "Appearance"
        Row {
          x: Theme.layout.module.pad; spacing: Theme.layout.module.pad; bottomPadding: Theme.layout.module.pad
          readonly property real cell: (parent.width - 2 * Theme.layout.module.pad - 2 * spacing) / 3
          Repeater {
            model: [{ key: "auto", label: "Automatic" }, { key: "light", label: "Light" }, { key: "dark", label: "Dark" }]
            ThumbCell { required property var modelData; width: parent.cell; label: modelData.label
              dark: modelData.key === "dark"; auto: modelData.key === "auto"
              selected: (cc.velum.values.appearance || "auto") === modelData.key
              onChosen: cc.velum.set("appearance", modelData.key) }
          }
        }
      }
      Group {
        title: "Style"
        Row {
          x: Theme.layout.module.pad; spacing: Theme.layout.module.pad; bottomPadding: Theme.layout.module.pad
          readonly property real cell: (parent.width - 2 * Theme.layout.module.pad - 3 * spacing) / 4
          Repeater {
            model: ["pearl", "glass", "paper", "slate"]
            ThumbCell { required property var modelData; width: parent.cell; label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
              variant: modelData; dark: Theme.dark; selected: Theme.variant === modelData
              onChosen: cc.velum.set("variant", modelData) }
          }
        }
      }
      Group {
        title: "Text Size"
        SliderRow { icon: "text"; value: cc.be.textSizeIndex / (cc.be.textSizeStops.length - 1)
          onMoved: v => cc.be.setTextSizeIndex(v * (cc.be.textSizeStops.length - 1)) }
        MSection { visible: cc.be.scalePresets.length > 1; text: "Scale" }
        SegmentRow { visible: cc.be.scalePresets.length > 1; model: cc.be.scalePresets.map(s => s + "×")
          currentIndex: Math.max(0, cc.be.scalePresets.indexOf(cc.be.monitorScale)); onActivated: i => cc.be.setScale(cc.be.scalePresets[i]) }
      }
      Group {
        visible: cc.be.displays.length > 1; title: "Displays"
        Repeater {
          model: cc.be.displays.length > 1 ? cc.be.displays : []
          MRow { required property var modelData; icon: modelData.name === cc.be.internalMonitor ? "laptop" : "desktop"
            text: modelData.description || modelData.name; checked: modelData.enabled; dim: !modelData.enabled
            onClicked: cc.be.toggleDisplay(modelData) }
        }
      }
    }
  }

  // ================================================================ Focus
  Component {
    id: focusPage
    Column {
      spacing: cc.gap
      MHead { title: "Focus" }
      VTile {
        width: parent.width; height: fcol.height + 2 * Theme.layout.module.pad * 2
        Column {
          id: fcol; y: Theme.layout.module.pad * 2; width: parent.width; spacing: Theme.layout.list.gap
          VBadge { anchors.horizontalCenter: parent.horizontalCenter; size: Theme.layout.meter.card * 0.75; icon: "focus"; on: cc.be.dnd
            onTapped: cc.be.setDnd(!cc.be.dnd) }
          VText { anchors.horizontalCenter: parent.horizontalCenter; text: "Do Not Disturb"; color: Theme.r.popover.ink
            font.pixelSize: Theme.m.type.title; font.weight: Font.DemiBold }
          VText { x: Theme.layout.module.pad * 2; width: parent.width - 2 * x; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
            tone: "secondary"; font.pixelSize: Theme.m.type.small
            text: cc.be.dnd ? "On — notifications wait quietly in the Notification Center." : "Off — notifications show as banners." }
          Item { width: parent.width; height: Theme.m.control.height
            VSwitch { anchors.centerIn: parent; surface: "popover"; checked: cc.be.dnd; onToggled: c => cc.be.setDnd(c) } }
        }
      }
    }
  }

  // ================================================================ Keyboard
  Component {
    id: kbdPage
    Column {
      spacing: cc.gap
      MHead { title: "Keyboard Brightness" }
      Group {
        title: "Brightness"; titleDetail: cc.be.kbd ? Math.round(cc.be.kbd.level * 100) + " %" : ""
        SliderRow { icon: "keyboard.light"; value: cc.be.kbd ? cc.be.kbd.level : 0; onMoved: v => cc.be.kbd.setLevel(v) }
      }
      Group {
        title: "Turn Off After Inactivity"
        SegmentRow {
          model: cc.be.kbd ? cc.be.kbd.timeoutChoices.map(s => cc.be.kbdTimeoutLabel(s)) : []
          currentIndex: cc.be.kbd ? Math.max(0, cc.be.kbd.timeoutChoices.indexOf(cc.be.kbd.timeout)) : 0
          onActivated: i => cc.be.kbd.setTimeoutSeconds(cc.be.kbd.timeoutChoices[i]) }
      }
    }
  }

  // a miniature desktop with its name (appearance and style pickers)
  component ThumbCell: Column {
    id: tc
    property string label: ""
    property string variant: Theme.variant
    property bool dark: false
    property bool auto: false
    property bool selected: false
    signal chosen()
    spacing: Theme.layout.list.gap
    VAppearanceThumb {
      width: tc.width; height: width * 0.64
      variant: tc.variant; dark: tc.dark; auto: tc.auto; selected: tc.selected
      Spring { id: tcPress; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: tcMouse.pressed ? Theme.scale("press") : 1 }
      scale: tcPress.value
      MouseArea { id: tcMouse; anchors.fill: parent; onClicked: tc.chosen() }
    }
    VText { anchors.horizontalCenter: parent.horizontalCenter; text: tc.label; font.pixelSize: Theme.m.type.small
      font.weight: tc.selected ? Font.DemiBold : Font.Normal; color: tc.selected ? Theme.r.popover.ink : Theme.r.popover.inkSecondary }
  }
  // ================================================================ Battery
  // everything of the battery menu (taken over from henri.power-v3): PowerService + PowerPages,
  // the same pages the right island of the bar shows
  PowerService { id: powerSvc; opened: !!cc.be && cc.be.opened && cc.current.indexOf("battery") === 0 }
  PowerPages { id: power; svc: powerSvc; onPushRequested: n => cc.push(n); onBackRequested: cc.back() }

  // ================================================================ Hardware
  // Three rings (CPU, memory, disk) that sweep in when the page shows, the CPU
  // load as a live strip chart, the programs using the most CPU (btop shows all); fans turn with their speed.
  component RingCell: Column {
    id: rcell
    property real value: 0
    property string label: ""
    property string sub: ""
    property color tone: Theme.r.accent.base
    spacing: Theme.layout.list.gap / 2
    VRing {
      anchors.horizontalCenter: parent.horizontalCenter; value: rcell.value; color: rcell.tone
      VText { anchors.centerIn: parent; text: Math.round(rcell.value * 100) + " %"; color: Theme.r.popover.ink; font.weight: Font.DemiBold }
    }
    VText { anchors.horizontalCenter: parent.horizontalCenter; text: rcell.label; color: Theme.r.popover.ink; font.weight: Font.DemiBold }
    VText { anchors.horizontalCenter: parent.horizontalCenter; text: rcell.sub; tone: "secondary"; font.pixelSize: Theme.m.type.small }
  }
  component MeterRow: Item {
    id: mrow
    property string icon: ""
    property string text: ""
    property string detail: ""
    property real value: 0
    property bool hot: false
    default property alias glyph: mglyph.data
    width: parent ? parent.width : 0
    height: Theme.layout.module.row
    readonly property real pad: Theme.layout.module.pad
    Item { id: mglyph; x: mrow.pad; width: Theme.layout.icon.regular; height: parent.height
      VIcon { visible: mrow.icon !== ""; anchors.centerIn: parent; name: mrow.icon; color: Theme.r.popover.ink } }
    VText { id: mlabel; x: mglyph.x + mglyph.width + mrow.pad; anchors.verticalCenter: parent.verticalCenter; text: mrow.text; color: Theme.r.popover.ink }
    VText { id: mdet; anchors.right: parent.right; anchors.rightMargin: mrow.pad; anchors.verticalCenter: parent.verticalCenter
      text: mrow.detail; tone: "secondary" }
    VMeter { x: parent.width / 2 - mrow.pad; width: parent.width - x - Theme.layout.meter.readout - 2 * mrow.pad; anchors.verticalCenter: parent.verticalCenter
      value: mrow.value; color: mrow.hot ? Theme.r.danger : Theme.r.accent.base; colorTop: mrow.hot ? Theme.r.danger : Theme.r.accent.top }
  }
  Component {
    id: hwPage
    Column {
      id: hp
      readonly property var hw: cc.be.hw
      readonly property real third: (width - 2 * cc.gap) / 3
      spacing: cc.gap
      MHead { title: "Hardware" }

      // -- rings
      VTile {
        width: parent.width; height: rings.height + 2 * Theme.layout.module.pad
        Row {
          id: rings; y: Theme.layout.module.pad; anchors.horizontalCenter: parent.horizontalCenter
          RingCell { width: hp.third; value: Math.max(0, cc.be.cpuLoad) / 100; label: "CPU"; sub: cc.be.formatGHz(hp.hw.freqAvg)
            tone: cc.be.cpuLoad >= 85 ? Theme.r.danger : Theme.r.accent.base }
          RingCell { width: hp.third; value: cc.be.memUsedFrac; label: "Memory"
            sub: cc.be.formatGiB(hp.hw.memTotal - hp.hw.memAvail, 1) + " of " + cc.be.formatGiB(hp.hw.memTotal, 0) + " GB"
            tone: cc.be.memUsedFrac >= 0.9 ? Theme.r.danger : Theme.r.accent.base }
          RingCell { width: hp.third; value: cc.be.diskUsedFrac; label: "Disk"
            sub: cc.be.formatBytesGB(hp.hw.diskUsed) + " of " + cc.be.formatBytesGB(hp.hw.diskTotal)
            tone: cc.be.diskUsedFrac >= 0.9 ? Theme.r.danger : Theme.r.accent.base }
        }
      }

      // -- CPU load, live
      Card {
        title: "CPU Load"
        titleDetail: [hp.hw.model || "", hp.hw.cores > 0 ? hp.hw.cores + " Cores" : ""].filter(t => t).join(" · ")
        VChart {
          x: Theme.layout.module.pad; width: parent.width - 2 * x
          live: true; interval: cc.be.hwInterval; capacity: cc.be.cpuHistoryLength
          values: cc.be.cpuHistory
        }
      }

      // -- the programs using the most CPU; the full list opens in btop
      Card {
        title: "Top Processes"; titleDetail: "% CPU"
        Column {
          width: parent.width
          VText { visible: cc.be.topProcs.length === 0; x: Theme.layout.module.pad; height: Theme.layout.module.row
            verticalAlignment: Text.AlignVCenter; text: "Measuring…"; tone: "secondary" }
          Repeater {
            model: cc.be.topProcs
            MeterRow {
              required property var modelData
              text: modelData.label + (modelData.count > 1 ? " (" + modelData.count + ")" : ""); detail: Math.round(modelData.cpu) + " %"
              value: modelData.cpu / 100; hot: modelData.cpu >= 85
              Image { visible: modelData.iconPath !== ""; anchors.centerIn: parent; source: modelData.iconPath
                width: Theme.layout.icon.regular; height: width; sourceSize.width: width * 2; sourceSize.height: height * 2 }
              VIcon { visible: modelData.iconPath === ""; anchors.centerIn: parent; name: "apps"; color: Theme.r.popover.inkSecondary }
            }
          }
          MSep {}
          MRow { icon: "gauge"; text: "Show All Processes"; detail: "btop"; onClicked: cc.be.openActivityMonitor()
            VIcon { name: "chevron.right"; weight: "bold"; size: Theme.layout.icon.small; color: Theme.r.popover.inkSecondary } }
        }
      }

      // -- fans, swap, uptime
      VTile {
        width: parent.width; height: sensors.height + 2 * Theme.layout.module.tileInset
        Column {
          id: sensors; y: Theme.layout.module.tileInset; width: parent.width
          Repeater {
            model: hp.hw.fans || []
            MeterRow {
              required property var modelData; required property int index
              text: modelData.label || "Fan " + (index + 1); detail: modelData.rpm + " rpm"; value: modelData.rpm / 6000
              VFan { anchors.centerIn: parent; size: Theme.layout.icon.regular; rpm: modelData.rpm }
            }
          }
          MeterRow { visible: hp.hw.swapTotal > 0; icon: "memory"; text: "Swap"; detail: Math.round(cc.be.swapUsedFrac * 100) + " %"; value: cc.be.swapUsedFrac }
          MRow { clickable: false; icon: "clock"; text: "Uptime"; detail: cc.be.formatUptime(hp.hw.uptime) }
        }
      }
      Group {
        MRow { icon: "flask"; text: "Experiments"; onClicked: cc.push("experiments")
          VIcon { name: "chevron.right"; weight: "bold"; size: Theme.layout.icon.small; color: Theme.r.popover.inkSecondary } }
      }
    }
  }

  // ================================================================ Experiments
  Component {
    id: expPage
    Column {
      spacing: cc.gap
      MHead { title: "Experiments" }
      Group {
        MRow { icon: "energy"; text: "Low-Power Rendering"; clickable: false
          VSwitch { surface: "popover"; checked: cc.be.renderPowerOn; onToggled: c => cc.be.setRenderPower(c) } }
        MRow { icon: "display"; text: "No Effects"; clickable: false
          VSwitch { surface: "popover"; checked: cc.be.noEffectsOn; onToggled: c => cc.be.setNoEffects(c) } }
        VText { x: Theme.layout.module.pad; width: parent.width - 2 * x; wrapMode: Text.WordWrap; tone: "secondary"; font.pixelSize: Theme.m.type.small
          bottomPadding: Theme.layout.list.gap
          text: "No Effects turns off blur, shadows and window animations." }
      }
    }
  }
}
