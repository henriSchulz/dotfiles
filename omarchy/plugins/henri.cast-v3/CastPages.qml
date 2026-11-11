import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// The tablet panel's pages over a CastService (`svc`): its battery, the stream, its panel's
// brightness and the switches for keyboards, Power Mode, Fast Mode and its microphone. Faceless
// itself — it hands out the page as a Component for the host's VPageStack (the right island of
// the bar, Panel.qml, and the Control Center in tablet mode, henri.control-center-v3
// FullCenter.qml), as henri.control-center-v3's PowerPages does for the battery.
//
//   CastPages { id: cast; svc: castSvc }
//   VPageStack { initial: cast.page("tablet") }
Item {
  id: cp
  property var svc: null
  visible: false
  function page(name) { return name === "tablet" ? mainPage : null }

  // an on/off tile: shows its new state at the click (want), dimmed while it cannot switch
  component ToggleTile: VTile {
    id: tile
    property string text
    property string icon
    property string key
    property bool on
    property bool can: true
    signal switched(bool on)
    height: Theme.m.control.height * 2
    radius: Theme.m.radius.row + Theme.layout.module.tileInset / 2
    VPressable {
      id: press
      anchors.fill: parent; radius: parent.radius
      enabled: tile.can
      selected: tile.on && tile.can
      onClicked: {
        const on = !tile.on
        tile.switched(on)
        cp.svc.want(tile.key, on)
      }
      Column {
        anchors.centerIn: parent
        VIcon { anchors.horizontalCenter: parent.horizontalCenter; name: tile.icon
          weight: press.selected ? "fill" : "regular"; color: press.contentColor }
        VText { anchors.horizontalCenter: parent.horizontalCenter; text: tile.text
          font.weight: Font.DemiBold; color: press.contentColor }
      }
    }
  }

  // ============================================================ first page
  Component {
    id: mainPage
    Column {
      id: mp
      readonly property var s: cp.svc
      readonly property real third: (width - 2 * Theme.layout.module.gap) / 3
      spacing: Theme.layout.module.gap

      Item {
        width: parent.width; height: Theme.layout.module.head
        VText { x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter; text: "Tablet"
          color: Theme.r.popover.ink; font.pixelSize: Theme.m.type.title; font.weight: Font.DemiBold }
      }

      // -- its battery and what it is doing
      VTile {
        width: parent.width; height: Theme.layout.meter.hero
        VBatteryArt {
          id: art
          x: Theme.layout.module.pad * 2; anchors.verticalCenter: parent.verticalCenter
          level: mp.s.batteryFraction; charging: mp.s.charging; plugged: mp.s.plugged
        }
        Column {
          x: art.x + art.width + Theme.layout.module.pad * 2; width: parent.width - x - Theme.layout.module.pad
          anchors.verticalCenter: parent.verticalCenter
          VCrossfadeText { width: parent.width; text: mp.s.pctText; color: Theme.r.popover.ink
            pixelSize: Theme.core.type.largeTitle; weight: Font.DemiBold }
          VCrossfadeText { width: parent.width; elide: Text.ElideRight; tone: "secondary"; color: Theme.r.popover.inkSecondary
            text: mp.s.statusText() }
        }
      }

      // -- the stream
      Grid {
        columns: 3; spacing: Theme.layout.module.gap
        VStatTile { width: mp.third; label: "Latency"; value: mp.s.connected ? Math.round(mp.s.i.latency) + " ms" : "—" }
        VStatTile { width: mp.third; label: "Power Draw"; value: mp.s.watts() }
        VStatTile { width: mp.third; label: "Data Rate"; value: mp.s.connected ? mp.s.rate(mp.s.i.kbit) : "—" }
      }

      // -- its panel, only for a tablet with its own brightness switches (mac-cast); the iPad follows
      // this Mac's backlight, set in Control Center (Henri 2026-11-11)
      Item {
        visible: typeof mp.s.i.perfTablet === "boolean"
        width: parent.width; height: Theme.layout.meter.slider
        VFillSlider { width: parent.width; icon: "brightness"
          value: mp.s.i.brightness >= 0 ? mp.s.i.brightness : 0
          readout: mp.s.i.brightness >= 0 ? Math.round(mp.s.i.brightness * 100) + " %" : ""
          onMoved: v => mp.s.setBrightness(v) }
      }

      // -- on/off tiles: this Mac's keyboard and trackpad, the tablet's cover, the cover's light.
      // Input is switched off only until the connection starts over; a tile is dimmed while the
      // tablet cannot switch it (no cover attached). The tablet's cover, its light, Power Mode and
      // the microphone are left out for a tablet that has none of them (the iPad: null in cast.json, Henri
      // 2026-11-11); the Grid closes the gaps
      VModuleSection { width: parent.width; text: "Keyboard & Trackpad" }
      Grid {
        columns: 3; spacing: Theme.layout.module.gap
        ToggleTile { width: mp.third; text: "Mac"; icon: "laptop"; key: "mac"; on: mp.s.tileOn("mac", mp.s.i.macInput !== false)
          onSwitched: v => mp.s.setInput("mac", v) }
        ToggleTile { width: mp.third; text: "Tablet"; icon: "tablet"; key: "tablet"; on: mp.s.tileOn("tablet", mp.s.i.tabletInput === true)
          can: typeof mp.s.i.tabletInput === "boolean"; visible: can; onSwitched: v => mp.s.setInput("tablet", v) }
        ToggleTile { width: mp.third; text: "Keyboard Light"; icon: "keyboard.light"; key: "light"; on: mp.s.tileOn("light", mp.s.i.kbdlight === true)
          can: mp.s.i.keyboard === true; visible: mp.s.i.kbdlight !== null && mp.s.i.kbdlight !== undefined
          onSwitched: v => mp.s.setKeyboardLight(v) }

        // -- the stream: Power Mode (the tablet's performance profile while casting, smoothest, uses
        // more battery), Fast Mode (a smaller stream for a few ms less latency), the tablet's
        // microphone as this Mac's input (off, the tablet captures nothing). A tile is dimmed while
        // the other side cannot switch it (perfTablet, fast, micTablet absent: an older build)
        ToggleTile { width: mp.third; text: "Power Mode"; icon: "gauge"; key: "perf"; on: mp.s.tileOn("perf", mp.s.i.perf === true)
          can: typeof mp.s.i.perfTablet === "boolean"; visible: can; onSwitched: v => mp.s.setPerf(v) }
        ToggleTile { width: mp.third; text: "Fast Mode"; icon: "bolt"; key: "fast"; on: mp.s.tileOn("fast", mp.s.i.fast === true)
          can: typeof mp.s.i.fast === "boolean"; onSwitched: v => mp.s.setFast(v) }
        ToggleTile { width: mp.third; text: "Microphone"; icon: "mic"; key: "mic"; on: mp.s.tileOn("mic", mp.s.i.mic === true)
          can: typeof mp.s.i.micTablet === "boolean"; visible: can; onSwitched: v => mp.s.setMic(v) }
        // the iPad's counterpart of its own Use Wi-Fi button: ends a Wi-Fi cast, dimmed over the cable
        // (mac-cast has its own switches, so not for it)
        ToggleTile { width: mp.third; text: "End Wi-Fi"; icon: "wifi.slash"; key: "wifiend"; on: false
          visible: typeof mp.s.i.perfTablet !== "boolean"; can: mp.s.connected && mp.s.i.link === "wifi"
          onSwitched: mp.s.endWifi() }
      }

      VText {
        x: Theme.layout.module.pad; width: parent.width - 2 * x
        tone: "secondary"; font.pixelSize: Theme.m.type.small; elide: Text.ElideRight
        bottomPadding: Theme.layout.module.pad - Theme.layout.module.tileInset
        text: (mp.s.i.link === "cable" ? "Cable" : "Wi-Fi") + " · " + (mp.s.i.mode === "own" ? "Own Screen" : "Mirror")
          + (mp.s.i.size ? " · " + mp.s.i.size[0] + " × " + mp.s.i.size[1] + " · " + mp.s.i.hz + " Hz · "
          + (mp.s.i.encoder === "apple-ave" ? "Hardware Encoder" : "Software Encoder") : "")
      }
    }
  }
}
