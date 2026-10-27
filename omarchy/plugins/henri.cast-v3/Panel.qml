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
// sync-status (dotfiles) writes every 5 min and at once when the panel opens — one row on the first page, the details on a page
// of their own (VPageStack).
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
      if (syncFile.missing || !root.syncFresh) syncFile.reload()
    }
  }

  // ---- the sync with the tablet
  property var sync: null
  readonly property bool syncFresh: !!sync && now - sync.time < 330
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
  function filesBusy() {
    return syncFresh && sync.peer && sync.files.errors === 0
      && (sync.files.syncing > 0 || (sync.files.peerPercent !== null && sync.files.peerPercent < 100))
  }
  // the one line on the first page: the worst of files, conflicts, settings and dotfiles
  function syncSummary() {
    if (!syncFresh) return "—"
    const files = filesText()
    if (files !== "Up to Date") return files
    if (sync.conflicts.count > 0) return sync.conflicts.count + (sync.conflicts.count === 1 ? " Conflict" : " Conflicts")
    if (sync.dotfiles.length > 0 || sync.settings.length > 0) return "Needs Attention"
    return "Up to Date"
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

  IpcHandler {
    target: "henri.cast"
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    // straight onto the Sync page
    function sync() { root.open(); if (stack.depth < 2) stack.push(syncPage) }
    function state(): string { return JSON.stringify({ connected: root.connected, opened: root.opened, depth: stack.depth,
                                                       summary: root.syncSummary(), height: content.height, pulling: panel.pulling,
                                                       from: [panel.from.x, panel.from.y, panel.from.width, panel.from.height], info: root.info, sync: root.sync }) }
  }

  onConnectedChanged: if (!connected) close()
  onOpenedChanged: {
    if (opened && !connected) close()
    else if (opened && latest) info = latest
    // sync-status runs every 5 min (a find over the home folders, P-cores at full clock each
    // time): fresh numbers when somebody looks
    else if (opened) Quickshell.execDetached(["systemctl", "--user", "start", "--no-block", "sync-status.service"])
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
  readonly property real third: (content.width - 2 * Theme.layout.module.gap) / 3
  function goBack() { if (stack.depth > 1) stack.pop(); else root.close() }

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
        VStatTile { width: root.third; label: "Connection"; value: root.i.link === "cable" ? "Cable" : "Wi-Fi" }
        VStatTile { width: root.third; label: "Draw"; value: root.watts() }
        VStatTile { width: root.third; label: "Screen"; value: root.i.mode === "own" ? "Own" : "Mirror" }
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
        Repeater {
          model: [
            { text: "Mac", icon: "laptop", on: root.i.macInput !== false, can: true, key: "mac" },
            { text: "Tablet", icon: "tablet", on: root.i.tabletInput === true, can: typeof root.i.tabletInput === "boolean", key: "tablet" },
            { text: "Keyboard Light", icon: "keyboard.light", on: root.i.kbdlight === true, can: root.i.keyboard === true, key: "light" }
          ]
          VTile {
            id: inputTile
            required property var modelData
            width: root.third; height: Theme.m.control.height * 2
            radius: Theme.m.radius.row + Theme.layout.module.tileInset / 2
            VPressable {
              id: inputPress
              anchors.fill: parent; radius: parent.radius
              enabled: inputTile.modelData.can
              selected: inputTile.modelData.on && inputTile.modelData.can
              onClicked: inputTile.modelData.key === "light" ? root.setKeyboardLight(!inputTile.modelData.on)
                : root.setInput(inputTile.modelData.key, !inputTile.modelData.on)
              Column {
                anchors.centerIn: parent
                VIcon { anchors.horizontalCenter: parent.horizontalCenter; name: inputTile.modelData.icon
                  weight: inputPress.selected ? "fill" : "regular"; color: inputPress.contentColor }
                VText { anchors.horizontalCenter: parent.horizontalCenter; text: inputTile.modelData.text
                  font.weight: Font.DemiBold; color: inputPress.contentColor }
              }
            }
          }
        }
      }

      // -- the sync with this Mac: one row, its details on their own page
      VModuleRow {
        width: parent.width; icon: "sync"; text: "Sync"
        busy: root.filesBusy(); detail: root.syncSummary()
        onClicked: stack.push(syncPage)
        VIcon { name: "chevron.right"; weight: "bold"; size: Theme.layout.icon.small; color: Theme.r.popover.inkSecondary }
      }

      VText {
        x: Theme.layout.module.pad; width: parent.width - 2 * x
        tone: "secondary"; font.pixelSize: Theme.m.type.small; elide: Text.ElideRight
        bottomPadding: Theme.layout.module.pad - Theme.layout.module.tileInset
        text: root.i.size ? root.i.size[0] + " × " + root.i.size[1] + " · " + root.i.hz + " Hz · "
          + (root.i.encoder === "apple-ave" ? "Hardware Encoder" : "Software Encoder") : ""
      }
    }
  }

  // ============================================================ sync page
  Component {
    id: syncPage
    Column {
      spacing: Theme.layout.module.gap
      VPageHead { width: parent.width; title: "Sync"; onBack: stack.pop() }
      VModuleRow {
        width: parent.width; clickable: false; icon: "folder"; text: "Files"
        busy: root.filesBusy(); detail: root.filesText()
      }
      VModuleRow {
        width: parent.width; visible: root.syncFresh && root.sync.conflicts.count > 0
        icon: "duplicate"; text: "Conflicts"
        detail: root.syncFresh ? root.sync.conflicts.count + (root.sync.conflicts.count === 1 ? " File" : " Files") : ""
        onClicked: root.showConflict()
      }
      VModuleRow { width: parent.width; clickable: false; icon: "settings"; text: "Settings"; detail: root.settingsText() }
      VModuleRow { width: parent.width; clickable: false; icon: "code"; text: "Dotfiles"; detail: root.dotfilesText() }
      Item { width: parent.width; height: Theme.layout.module.pad - Theme.layout.module.tileInset }
    }
  }
}
