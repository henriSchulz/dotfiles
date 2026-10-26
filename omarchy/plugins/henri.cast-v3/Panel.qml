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
// file when the tablet goes. Below that, how the sync between this Mac and the tablet stands
// (Syncthing over the cable, dotfiles, settings), from $XDG_RUNTIME_DIR/henri/sync.json, which
// sync-status (dotfiles) writes every 30 s.
Panel {
  id: root
  moduleName: "henri.cast"
  ipcTarget: "henri.cast"
  manageIpc: false

  // ---- what the tablet and the stream report
  property var info: null
  property real now: Date.now() / 1000
  readonly property bool connected: !!info && now - info.time < 8
  FileView {
    id: infoFile
    property bool missing: true
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/ipadcast/cast.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.info = JSON.parse(text() || "null") } catch (e) { root.info = null }
      missing = false
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
      if (syncFile.missing || !root.syncFresh) syncFile.reload()
    }
  }

  // ---- the sync with the tablet
  property var sync: null
  readonly property bool syncFresh: !!sync && now - sync.time < 90
  FileView {
    id: syncFile
    property bool missing: true
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/henri/sync.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.sync = JSON.parse(text() || "null") } catch (e) { root.sync = null }
      missing = false
    }
    onLoadFailed: { root.sync = null; missing = true }
  }
  function filesText() {
    if (!syncFresh) return "—"
    const f = sync.files
    if (!sync.peer) return "Not Connected"
    if (f.errors > 0) return f.errors + (f.errors === 1 ? " Error" : " Errors")
    if (f.peerPercent !== null && f.peerPercent < 100) return "Syncing · " + Math.floor(f.peerPercent) + " %"
    if (f.syncing > 0) return "Syncing"
    return "Up to Date"
  }
  function dotfilesText() {
    if (!syncFresh) return "—"
    if (sync.dotfiles.length === 0) return "Up to Date"
    return sync.dotfiles.some(l => l.indexOf("by hand") >= 0) ? "Merge by Hand" : "Needs Attention"
  }
  function settingsText() {
    if (!syncFresh) return "—"
    return sync.settings.length === 0 ? "Up to Date" : sync.settings.length + " Differ"
  }
  // the newest conflict copy, selected in Finder
  function showConflict() {
    if (!syncFresh || sync.conflicts.count === 0) return
    Quickshell.execDetached(["finder", "--select", sync.conflicts.newest[0]])
    root.close()
  }

  readonly property real batteryFraction: connected && info.battery !== null ? Math.max(0, Math.min(1, info.battery / 100)) : 0
  readonly property bool charging: connected && info.state === "Charging"
  readonly property bool plugged: connected && (info.state === "Full" || info.state === "Not")
  function watts() { return connected ? Math.abs(info.watts).toFixed(1) + " W" : "—" }
  function statusText() {
    if (!connected) return ""
    if (charging) return "Charging"
    if (plugged) return "On Power"
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
  function setInput(which, on) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.event(\"ipadcast " + which + "input " + (on ? "on" : "off") + "\")"])
  }

  // 0 both, 1 the Mac's own, 2 the tablet's: the side that stays on goes first (one shell, so in
  // order), so both are never off
  function pickInput(i) {
    const ev = (which, on) => "hl.dsp.event(\"ipadcast " + which + "input " + (on ? "on" : "off") + "\")"
    const first = i === 2 ? ev("tablet", true) : ev("mac", true)
    const second = i === 2 ? ev("mac", false) : ev("tablet", i === 0)
    Quickshell.execDetached(["sh", "-c", "hyprctl dispatch \"$1\" && hyprctl dispatch \"$2\"", "sh", first, second])
  }

  IpcHandler {
    target: "henri.cast"
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function state(): string { return JSON.stringify({ connected: root.connected, opened: root.opened, info: root.info, sync: root.sync }) }
  }

  onConnectedChanged: if (!connected) close()
  onOpenedChanged: if (opened && !connected) close()
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
    onEscapePressed: root.close()

    Column {
      id: content
      width: Theme.layout.module.width - 2 * panel.pad
      spacing: Theme.layout.module.gap
      readonly property real third: (width - 2 * spacing) / 3
      readonly property var i: root.info || ({})

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
        columns: 3; spacing: content.spacing
        VStatTile { width: content.third; label: "Latency"; value: root.connected ? Math.round(content.i.latency) + " ms" : "—" }
        VStatTile { width: content.third; label: "Frame Rate"; value: root.connected ? Math.round(content.i.fps) + " fps" : "—" }
        VStatTile { width: content.third; label: "Data Rate"; value: root.connected ? root.rate(content.i.kbit) : "—" }
        VStatTile { width: content.third; label: "Connection"; value: content.i.link === "cable" ? "Cable" : "Wi-Fi" }
        VStatTile { width: content.third; label: "Draw"; value: root.watts() }
        VStatTile { width: content.third; label: "Screen"; value: content.i.mode === "own" ? "Own" : "Mirror" }
      }

      // -- its panel
      Item {
        width: parent.width; height: Theme.layout.meter.slider
        VFillSlider { width: parent.width; icon: "brightness"
          value: content.i.brightness >= 0 ? content.i.brightness : 0
          readout: content.i.brightness >= 0 ? Math.round(content.i.brightness * 100) + " %" : ""
          onMoved: v => root.setBrightness(v) }
      }

      // -- its keyboard's light (on or off only); hidden while no keyboard is attached
      VModuleRow {
        width: parent.width; visible: content.i.keyboard === true; clickable: false
        icon: "keyboard.light"; text: "Keyboard Light"
        VSwitch { surface: "popover"; checked: content.i.kbdlight === true; onToggled: c => root.setKeyboardLight(c) }
      }

      // -- which keyboard and trackpad work the Mac — both, the Mac's own or the tablet's cover: switched
      // only until the connection starts over; just the Mac's switch while the tablet's mac-cast cannot
      // switch its cover
      VModuleSection { visible: inputSeg.visible; text: "Keyboard & Trackpad" }
      Row {
        id: inputSeg
        spacing: content.spacing
        visible: typeof content.i.tabletInput === "boolean"
        readonly property int current: content.i.macInput === false ? 2 : content.i.tabletInput === false ? 1 : 0
        Repeater {
          model: [{ text: "Both", icons: ["laptop", "tablet"] }, { text: "Mac", icons: ["laptop"] }, { text: "Tablet", icons: ["tablet"] }]
          VTile {
            id: inputTile
            required property int index
            required property var modelData
            width: content.third; height: Theme.m.control.height * 2
            radius: Theme.m.radius.row + Theme.layout.module.tileInset / 2
            VPressable {
              id: inputPress
              anchors.fill: parent; radius: parent.radius
              selected: inputSeg.current === inputTile.index
              onClicked: if (!selected) root.pickInput(inputTile.index)
              Column {
                anchors.centerIn: parent
                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  Repeater {
                    model: inputTile.modelData.icons
                    VIcon { required property string modelData; name: modelData
                      weight: inputPress.selected ? "fill" : "regular"; color: inputPress.contentColor }
                  }
                }
                VText { anchors.horizontalCenter: parent.horizontalCenter; text: inputTile.modelData.text
                  font.weight: Font.DemiBold; color: inputPress.contentColor }
              }
            }
          }
        }
      }
      VModuleRow {
        width: parent.width; visible: !inputSeg.visible; clickable: false
        icon: "laptop"; text: "Mac Keyboard & Trackpad"
        VSwitch { surface: "popover"; checked: content.i.macInput !== false; onToggled: c => root.setInput("mac", c) }
      }

      // -- the sync with this Mac
      VModuleSection { text: "Sync" }
      VModuleRow {
        width: parent.width; clickable: false; icon: "folder"; text: "Files"
        busy: root.syncFresh && root.sync.peer && root.sync.files.errors === 0
          && (root.sync.files.syncing > 0 || (root.sync.files.peerPercent !== null && root.sync.files.peerPercent < 100))
        detail: root.filesText()
      }
      VModuleRow {
        width: parent.width; visible: root.syncFresh && root.sync.conflicts.count > 0
        icon: "duplicate"; text: "Conflicts"
        detail: root.syncFresh ? root.sync.conflicts.count + (root.sync.conflicts.count === 1 ? " File" : " Files") : ""
        onClicked: root.showConflict()
      }
      VModuleRow { width: parent.width; clickable: false; icon: "settings"; text: "Settings"; detail: root.settingsText() }
      VModuleRow { width: parent.width; clickable: false; icon: "code"; text: "Dotfiles"; detail: root.dotfilesText() }

      VText {
        x: Theme.layout.module.pad; width: parent.width - 2 * x
        tone: "secondary"; font.pixelSize: Theme.m.type.small; elide: Text.ElideRight
        bottomPadding: Theme.layout.module.pad - Theme.layout.module.tileInset
        text: content.i.size ? content.i.size[0] + " × " + content.i.size[1] + " · " + content.i.hz + " Hz · "
          + (content.i.encoder === "apple-ave" ? "Hardware Encoder" : "Software Encoder") : ""
      }
    }
  }
}
