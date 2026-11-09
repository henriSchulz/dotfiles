import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "file:///home/henri/.local/share/velum/qml/Velum"

// The tablet that shows this Mac (mac-cast on the tablet, ipadcast here) in the menu bar:
// its symbol and battery, only while it is connected. A click grows the right island into
// what it reports — battery, draw, latency, connection — and what the stream does, with a
// brightness slider for its panel (the tablet follows this Mac's backlight while casting).
// ipadcast writes it all to $XDG_RUNTIME_DIR/ipadcast/cast.json every 2 s and removes the
// file when the tablet goes.
Panel {
  id: root
  moduleName: "henri.cast"
  ipcTarget: "henri.cast"
  manageIpc: false

  // ---- what the tablet and the stream report
  // ipadcast rewrites the file every 2 s. A new info object re-renders the shell's layers even
  // when nothing visible changed, and every such frame goes to the tablet through zcast's encoder
  // (m1-power, 2026-10-27: a burst of ~5 frames every 2 s on a still screen). So while the island
  // is closed info only changes with what the bar shows; seen keeps the connection alive.
  property var info: null
  property var latest: null
  property real seen: 0
  property real now: Date.now() / 1000
  readonly property bool connected: !!info && now - seen < 8
  FileView {
    id: infoFile
    property bool missing: true
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/ipadcast/cast.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      let j = null
      try { j = JSON.parse(text() || "null") } catch (e) {}
      root.latest = j
      missing = false
      if (!j) { root.info = null; return }
      root.seen = j.time
      const was = root.info
      if (root.opened || !was || Math.round(j.battery) !== Math.round(was.battery) || j.state !== was.state)
        root.info = j
    }
    onLoadFailed: { root.info = null; missing = true }
  }
  // a watch can't see a file that does not exist yet (nor its removal for sure): look again
  // now and then; the clock ends a connection whose reports stopped
  Timer {
    interval: 2000; repeat: true; running: true
    onTriggered: {
      root.now = Date.now() / 1000
      if (infoFile.missing || !root.connected) infoFile.reload()
    }
  }

  readonly property real batteryFraction: connected && info.battery !== null ? Math.max(0, Math.min(1, info.battery / 100)) : 0
  readonly property bool charging: connected && info.state === "Charging"
  readonly property bool plugged: connected && (info.state === "Full" || info.state === "Not")
  function watts() { return connected ? Math.abs(info.watts).toFixed(1) + " W" : "—" }
  function statusText() {
    if (!connected) return ""
    if (charging) return "Charging · " + watts()
    if (plugged) return "On Power · " + watts()
    return "On Battery · " + watts()
  }
  function rate(kbit) { return kbit >= 1000 ? (kbit / 1000).toFixed(1) + " Mbit/s" : Math.round(kbit) + " kbit/s" }
  function setBrightness(v) {
    Quickshell.execDetached(["brightnessctl", "-q", "-c", "backlight", "set", Math.max(1, Math.round(v * 100)) + "%"])
  }
  // ipadcast hears this on Hyprland's event socket and hands it to the tablet
  function setKeyboardLight(on) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.event(\"ipadcast kbdlight " + (on ? "on" : "off") + "\")"])
  }
  // this Mac's own keyboard and trackpad ("mac") or the tablet's cover ("tablet"); ipadcast turns
  // both on again when the tablet connects anew
  // Power Mode: smoothness over battery, kept until switched off (ipadcast, type 10 to the tablet)
  function setPerf(on) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.event(\"ipadcast perf " + (on ? "on" : "off") + "\")"])
  }
  // Fast Mode: a smaller stream (the tablet scales it up), a few ms less latency (ipadcast, "fast" in cast.json)
  function setFast(on) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.event(\"ipadcast fast " + (on ? "on" : "off") + "\")"])
  }
  // the tablet's microphone as this Mac's input, kept until switched off (ipadcast, type 11 to the tablet)
  function setMic(on) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.event(\"ipadcast mic " + (on ? "on" : "off") + "\")"])
  }
  function setInput(which, on) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.event(\"ipadcast " + which + "input " + (on ? "on" : "off") + "\")"])
  }

  IpcHandler {
    target: "henri.cast"
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function state(): string { return JSON.stringify({ connected: root.connected, opened: root.opened, depth: stack.depth,
                                                       height: content.height, pulling: panel.pulling,
                                                       from: [panel.from.x, panel.from.y, panel.from.width, panel.from.height], info: root.info }) }
  }

  onConnectedChanged: if (!connected) close()
  onOpenedChanged: {
    if (opened && !connected) { close(); return }
    if (!opened) return
    if (latest) info = latest
  }
  visible: connected
  implicitWidth: connected ? button.implicitWidth : 0
  implicitHeight: connected ? button.implicitHeight : 0

  // ============================================================ bar button
  readonly property string pctText: Math.round(root.batteryFraction * 100) + " %"
  readonly property real iconSize: Style.spaceReal(15)
  readonly property real barContentWidth: pctMetrics.advanceWidth + Style.spaceReal(5) + iconSize
  readonly property real openPanelIndicatorWidth: !button.vertical ? barContentWidth : 0
  TextMetrics { id: pctMetrics; font.family: root.bar ? root.bar.fontFamily : Theme.font; font.pixelSize: Style.font.body; text: root.pctText }

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
          VIcon {
            anchors.verticalCenter: parent.verticalCenter
            name: "tablet"
            size: root.iconSize
            color: button ? button.foreground : Color.foreground
          }
          VCrossfadeText {
            anchors.verticalCenter: parent.verticalCenter
            width: implicitWidth
            text: root.pctText
            color: button ? button.foreground : Color.foreground
            pixelSize: Style.font.body
          }
        }
      }
    }
    tooltipText: ""
    onPressed: function (b) { if (root.connected) root.toggle() }
  }

  // a finger pulls this panel down from the top edge above its item (tablet mode, cast screen)
  VPullZone { surface: "cast"; item: button; island: panel; opened: root.opened; onCommit: root.open() }

  // ================================================================= island
  VIslandWindow {
    id: panel
    anchorItem: button
    bar: root.bar
    namespace: "velum-surface"   // Hyprland: blur with ignore_alpha 0.6 (only the material, never the shadow), no layer animation
    align: "right"
    open: root.opened && root.connected
    toWidth: Theme.layout.module.width
    contentHeight: content.height
    onDismissed: root.close()
    onReopenRequested: root.open()

    onEscapePressed: root.goBack()
    // every open starts on the first page: back to it once the island has shrunk
    onShownChanged: if (!shown) stack.reset()

    Item {
      id: content
      width: Theme.layout.module.width - 2 * panel.pad
      height: stack.implicitHeight
      VPageStack { id: stack; width: parent.width; initial: mainPage }
    }
  }

  readonly property var i: root.info || ({})

  // a tile shows its new state at the click: the tablet answers only in its next report (every
  // 2 s, its cover a round later). The wish stands until a report agrees, at most 6 s
  property var pending: ({})
  function want(key, on) {
    const p = Object.assign({}, pending)
    p[key] = { on: on, until: Date.now() / 1000 + 6 }
    pending = p
  }
  function tileOn(key, reported) {
    const p = pending[key]
    return p && now < p.until ? p.on : reported
  }
  onInfoChanged: {
    const r = { mac: i.macInput !== false, tablet: i.tabletInput === true, light: i.kbdlight === true,
      perf: i.perf === true, fast: i.fast === true, mic: i.mic === true }
    const p = {}
    let changed = false
    for (const k in pending) {
      if (pending[k].on === r[k] || now >= pending[k].until) changed = true
      else p[k] = pending[k]
    }
    if (changed) pending = p
  }
  readonly property real third: (content.width - 2 * Theme.layout.module.gap) / 3
  function goBack() { if (stack.depth > 1) stack.pop(); else root.close() }

  // an on/off tile: shows its new state at the click (want), dimmed while it cannot switch
  component ToggleTile: VTile {
    id: tile
    property string text
    property string icon
    property string key
    property bool on
    property bool can: true
    signal switched(bool on)
    width: root.third; height: Theme.m.control.height * 2
    radius: Theme.m.radius.row + Theme.layout.module.tileInset / 2
    VPressable {
      id: press
      anchors.fill: parent; radius: parent.radius
      enabled: tile.can
      selected: tile.on && tile.can
      onClicked: {
        const on = !tile.on
        tile.switched(on)
        root.want(tile.key, on)
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
          level: root.batteryFraction; charging: root.charging; plugged: root.plugged
        }
        Column {
          x: art.x + art.width + Theme.layout.module.pad * 2; width: parent.width - x - Theme.layout.module.pad
          anchors.verticalCenter: parent.verticalCenter
          VCrossfadeText { width: parent.width; text: root.pctText; color: Theme.r.popover.ink
            pixelSize: Theme.core.type.largeTitle; weight: Font.DemiBold }
          VCrossfadeText { width: parent.width; elide: Text.ElideRight; tone: "secondary"; color: Theme.r.popover.inkSecondary
            text: root.statusText() }
        }
      }

      // -- the stream
      Grid {
        columns: 3; spacing: Theme.layout.module.gap
        VStatTile { width: root.third; label: "Latency"; value: root.connected ? Math.round(root.i.latency) + " ms" : "—" }
        VStatTile { width: root.third; label: "Frame Rate"; value: root.connected ? Math.round(root.i.fps) + " fps" : "—" }
        VStatTile { width: root.third; label: "Data Rate"; value: root.connected ? root.rate(root.i.kbit) : "—" }
      }

      // -- its panel
      Item {
        width: parent.width; height: Theme.layout.meter.slider
        VFillSlider { width: parent.width; icon: "brightness"
          value: root.i.brightness >= 0 ? root.i.brightness : 0
          readout: root.i.brightness >= 0 ? Math.round(root.i.brightness * 100) + " %" : ""
          onMoved: v => root.setBrightness(v) }
      }

      // -- three on/off tiles: this Mac's keyboard and trackpad, the tablet's cover, the cover's light.
      // Input is switched off only until the connection starts over; a tile is dimmed while the
      // tablet cannot switch it (no cover attached, an old mac-cast)
      VModuleSection { width: parent.width; text: "Keyboard & Trackpad" }
      Row {
        spacing: Theme.layout.module.gap
        ToggleTile { text: "Mac"; icon: "laptop"; key: "mac"; on: root.tileOn("mac", root.i.macInput !== false)
          onSwitched: v => root.setInput("mac", v) }
        ToggleTile { text: "Tablet"; icon: "tablet"; key: "tablet"; on: root.tileOn("tablet", root.i.tabletInput === true)
          can: typeof root.i.tabletInput === "boolean"; onSwitched: v => root.setInput("tablet", v) }
        ToggleTile { text: "Keyboard Light"; icon: "keyboard.light"; key: "light"; on: root.tileOn("light", root.i.kbdlight === true)
          can: root.i.keyboard === true; onSwitched: v => root.setKeyboardLight(v) }
      }

      // -- the stream: Power Mode (the tablet's performance profile while casting, smoothest, uses
      // more battery), Fast Mode (a smaller stream for a few ms less latency), the tablet's
      // microphone as this Mac's input (off, the tablet captures nothing). A tile is dimmed while
      // the other side cannot switch it (perfTablet, fast, micTablet absent: an older build)
      Row {
        spacing: Theme.layout.module.gap
        ToggleTile { text: "Power Mode"; icon: "gauge"; key: "perf"; on: root.tileOn("perf", root.i.perf === true)
          can: typeof root.i.perfTablet === "boolean"; onSwitched: v => root.setPerf(v) }
        ToggleTile { text: "Fast Mode"; icon: "bolt"; key: "fast"; on: root.tileOn("fast", root.i.fast === true)
          can: typeof root.i.fast === "boolean"; onSwitched: v => root.setFast(v) }
        ToggleTile { text: "Microphone"; icon: "mic"; key: "mic"; on: root.tileOn("mic", root.i.mic === true)
          can: typeof root.i.micTablet === "boolean"; onSwitched: v => root.setMic(v) }
      }

      VText {
        x: Theme.layout.module.pad; width: parent.width - 2 * x
        tone: "secondary"; font.pixelSize: Theme.m.type.small; elide: Text.ElideRight
        bottomPadding: Theme.layout.module.pad - Theme.layout.module.tileInset
        text: (root.i.link === "cable" ? "Cable" : "Wi-Fi") + " · " + (root.i.mode === "own" ? "Own Screen" : "Mirror")
          + (root.i.size ? " · " + root.i.size[0] + " × " + root.i.size[1] + " · " + root.i.hz + " Hz · "
          + (root.i.encoder === "apple-ave" ? "Hardware Encoder" : "Software Encoder") : "")
      }
    }
  }
}
