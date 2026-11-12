import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "file:///home/henri/.local/share/velum/qml/Velum"
import "qs"

// A harness for the tablet's Quick Settings (henri.tablet-v4/qs) — a plain Quickshell config, not the
// omarchy shell: one full-screen overlay window on the output QS_OUTPUT with a stand-in home screen (the
// wallpaper), the status bar, and the shade. It plays the owner: a finger from the top edge drives the shade
// (dragging / dragProgress / release), as the tablet's top-edge pull will. The backend is NEVER live here:
// every command is logged ("qs dry-run: …") and kept in `log`. tests/qs-harness/harness.sh runs it in a
// nested Hyprland with its own XDG_STATE_HOME (tablet-qs.json) — see there.
//
// IPC (qs ipc call qs …): state, open, close, pull PHASE Y [VELOCITY], tab N, detail wifi|bluetooth|"",
// edit true|false, toggle KEY, longPress KEY, power KEY, accept, cancel, dark true|false, esc, log, tiles,
// setTiles "KEY KEY …", speed N, inset PX (the owner's topInset), scroll (the Controls page's and the details
// list's scroll), brightCmd PATH V (the command a brightness path would run), rescan (the details' refresh)
ShellRoot {
  id: root
  readonly property string outputName: Quickshell.env("QS_OUTPUT") || ""
  readonly property var target: {
    const list = Quickshell.screens
    for (let i = 0; i < list.length; i++) if (list[i].name === outputName) return list[i]
    return list.length ? list[0] : null
  }
  FontLoader { source: Quickshell.env("QS_ROBOTO_400") ? "file://" + Quickshell.env("QS_ROBOTO_400") : "" }
  FontLoader { source: Quickshell.env("QS_ROBOTO_500") ? "file://" + Quickshell.env("QS_ROBOTO_500") : "" }
  Component.onCompleted: {
    Theme.variant = Quickshell.env("QS_VARIANT") || "opal"
    Theme.dark = Quickshell.env("QS_APPEARANCE") === "dark"
    Theme.touch = true
  }

  QsBackend { id: qsb; live: false; active: shade.shown }

  PanelWindow {
    id: win
    screen: root.target
    anchors { left: true; right: true; top: true; bottom: true }
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "velum-qs-harness"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore

    // the stand-in home screen: the wallpaper (what the shade blurs a copy of)
    Image {
      anchors.fill: parent
      source: "file://" + root.wallpaper
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: width; sourceSize.height: height
    }

    StatusBar { id: sbar; width: parent.width; backend: qsb; shown: shade.progress < 1 }

    // the owner's pull: a finger from the status bar line
    MouseArea {
      id: pull
      width: parent.width
      height: Theme.core.surface.material.qs.status.height + Theme.core.surface.material.qs.shade.slop
      enabled: !shade.shown || shade.dragging
      property real y0: 0
      property real lastY: 0
      property real lastT: 0
      property real vel: 0
      onPressed: mouse => { y0 = mouse.y; lastY = mouse.y; lastT = Date.now(); vel = 0; shade.dragProgress = 0; shade.dragging = true }
      onPositionChanged: mouse => {
        const t = Date.now()
        if (t > lastT) vel = (mouse.y - lastY) / (t - lastT) * 1000
        lastY = mouse.y; lastT = t
        shade.dragProgress = Math.max(0, (mouse.y - y0) / shade.travel)
      }
      onReleased: { shade.release(vel); shade.dragging = false }
      onCanceled: { shade.release(0); shade.dragging = false }
    }

    QuickSettings {
      id: shade
      anchors.fill: parent
      backend: qsb
      wallpaper: root.wallpaper
      onClosed: root.events = root.events.concat(["closed"])
      onOpened: root.events = root.events.concat(["opened"])
      onTileLongPressed: key => root.events = root.events.concat(["long " + key])
    }
  }
  readonly property string wallpaper: Quickshell.env("QS_WALLPAPER") || ""
  property var events: []

  IpcHandler {
    target: "qs"
    function state(): string {
      return JSON.stringify({ progress: shade.progress, shown: shade.shown, open: shade.wantOpen, tab: shade.tab,
        pagePos: shade.pagePos, detail: shade.detail, editing: shade.editing, confirm: shade.pendingAction !== null,
        tiles: qsb.tiles, seen: shade.seen, dark: Theme.dark, events: root.events,
        notifications: qsb.notificationsShown.length, cast: qsb.castConnected, castWifi: qsb.castOverWifi, wifi: qsb.wifiOn, bt: qsb.btOn,
        brightness: Math.round(qsb.brightness * 100), mode: qsb.powerMode, dnd: qsb.dnd, night: qsb.night,
        airplane: qsb.airplane, battery: qsb.battery ? qsb.battery.capacity : null, history: qsb.history.length,
        log: qsb.log.length, scanning: qsb.wifiScanning, networks: qsb.wifiRows.length, scanned: qsb.wifiScanned.length,
        brightPath: qsb.brightPath, tabletName: qsb.tabletName, tabletLog: qsb.tabletLog, hasBattery: qsb.hasBattery, level: qsb.level, upType: qsb.upower ? qsb.upower.type : -1, upLaptop: qsb.upower ? qsb.upower.isLaptopBattery : null })
    }
    function log(): string { return JSON.stringify(qsb.log.map(e => (e.read ? "read " : e.live ? "LIVE " : "dry ") + e.argv.join(" "))) }
    function inset(px: real): string { shade.topInset = px; return String(shade.topInset) }
    function scroll(): string {
      const out = {}
      const c = shade.scroller()
      if (c) out.now = { y: Math.round(c.contentY), max: Math.round(Math.max(0, c.contentHeight - c.height)), h: Math.round(c.height) }
      out.pagesMax = Math.round(shade.pagesMax)
      return JSON.stringify(out)
    }
    function brightCmd(path: string, v: real): string { return qsb.brightCommand(path, v).join(" ") }
    function rescan(): string { qsb.wifiRescan(); return String(qsb.wifiScanning) }
    function open(): string { shade.open(); return "ok" }
    function close(): string { shade.close(); return "ok" }
    function pull(phase: string, y: real, velocity: real): string {
      if (phase === "start") { shade.dragProgress = 0; shade.dragging = true }
      else if (phase === "move") shade.dragProgress = y / shade.travel
      else { shade.release(velocity); shade.dragging = false }
      return String(shade.progress)
    }
    function tab(n: int): string { shade.goTab(n); return String(shade.tab) }
    function detail(kind: string): string { if (kind === "") shade.detail = ""; else shade.showDetail(kind); return shade.detail }
    function edit(on: bool): string { shade.edit(on); return String(shade.editing) }
    function toggle(key: string): string { shade.toggleTile(key); return "ok" }
    function longPress(key: string): string { shade.longPressTile(key); return shade.detail }
    function power(key: string): string { shade.choosePower(key); return String(shade.pendingAction !== null) }
    function accept(): string { shade.answer(true); return "ok" }
    function cancel(): string { shade.answer(false); return "ok" }
    function dark(on: bool): string { Theme.dark = on; return String(Theme.dark) }
    function esc(): string { shade.close(); return "ok" }
    function tiles(): string { return JSON.stringify(qsb.tiles) }
    function setTiles(keys: string): string { qsb.setTiles(keys.split(" ").filter(x => x)); return JSON.stringify(qsb.tiles) }
    function speed(n: real): string { Theme.speed = n; return String(Theme.speed) }
    function statusProbe(): string { return JSON.stringify(sbar.probe()) }
    // the centre of the visible item named NAME (objectName), in the window: "X Y", or "" when none shows
    function xy(name: string): string {
      const find = (it) => {
        if (!it || !it.visible) return null
        if (it.objectName === name && it.width > 0) return it
        const kids = it.children || []
        for (let i = 0; i < kids.length; i++) { const f = find(kids[i]); if (f) return f }
        if (it.contentItem && kids.indexOf(it.contentItem) < 0) return find(it.contentItem)
        return null
      }
      const f = find(shade)
      if (!f) return ""
      const p = f.mapToItem(shade, f.width / 2, f.height / 2)
      return Math.round(p.x) + " " + Math.round(p.y)
    }
    function clearEvents(): string { root.events = []; return "ok" }
  }
}
