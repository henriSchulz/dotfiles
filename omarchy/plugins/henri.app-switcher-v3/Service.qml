// Window Switcher -- Alt+Tab through the windows of the current workspace.
//
// Hold Alt and press Tab: after a short moment a row of live window previews
// appears, the window in front on the left, then the one used before it, and
// so on. Every further Tab (Shift+Tab goes back) moves the selection, letting
// go of Alt switches to it. A quick tap switches straight to the previous
// window without flashing the row.
//
// Windows, not apps, and only the ones on the workspace you are on. It is the
// answer to several fullscreen (or zoomed) windows lying on top of each other,
// where only the top one is visible: the row shows every one of them as a
// miniature, the way the workspace switcher (Super+Tab) shows workspaces.
// Focusing a window under a fullscreen one hands the fullscreen over to it
// (misc:on_focus_under_fullscreen = 1). Other workspaces are Super+Tab's job;
// minimized windows (special:minimized) are the dock's.
//
// Keys. Hyprland owns them (bindings.lua): ALT+TAB, ALT+SHIFT+TAB and the
// Alt_L release send `custom>>app-switcher <next|prev|commit>` on Hyprland's
// event socket -- no process per key, so there is no latency and the events
// arrive in the order they happened. The plugin id and event names are the old
// app switcher's, so the binds did not have to move. The row never takes the
// keyboard: with Alt held, Hyprland's binds win anyway, and holding focus would
// make Hyprland refocus the window the row let go of. A click outside cancels,
// a click on a preview switches, hovering preselects.
//
// Order. The switcher keeps its own most-recently-used list, fed by every focus
// change while the shell runs, because Hyprland's focusHistoryID only arrives
// with an IPC refresh and would be one gesture behind. Windows the list has not
// seen yet (right after a shell restart) fall back to that focusHistoryID.
//
// Look and motion (Velum v3): the row is a floating card of the popover
// material (Pearl by default), blurred by the compositor (namespace
// velum-surface). Tiles have the workspace switcher's shape -- the monitor's
// aspect, the window fitted inside with rounded corners, icon and title under
// it. The card appears out of the centre on the smooth spring from
// launcherFrom with a fast fade and leaves faster than it came; the selection
// ring jumps instantly (frequent interaction).

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "file:///home/henri/.local/share/velum/qml/Velum"

Item {
  id: root

  property var shell: null
  property var manifest: null

  // An Alt+Tab gesture is running (Alt is held).
  property bool armed: false
  // The row is on screen (armed and held longer than the switcher delay).
  property bool shown: false
  // Window records in row order, frozen when the gesture starts so the
  // selection cannot shift under the user while they tab through it.
  property var windows: []
  property int selected: 0

  // Most recently used windows (Wayland handles), newest first. Only ever
  // compared by identity (indexOf), so entries of closed windows are harmless.
  property var mruWindows: []

  // ---------------------------------------------------------------- ordering

  function touch(tl) {
    if (!tl)
      return;
    const next = [tl];
    const prev = root.mruWindows;
    for (let i = 0; i < prev.length && next.length < 64; i++)
      if (prev[i] !== tl)
        next.push(prev[i]);
    root.mruWindows = next;
  }

  function windowRank(handle) {
    if (handle.wayland && handle.wayland === ToplevelManager.activeToplevel)
      return -1;
    const i = root.mruWindows.indexOf(handle.wayland);
    if (i >= 0)
      return i;
    const o = handle.lastIpcObject;
    const n = o ? Number(o.focusHistoryID) : NaN;
    return 1000 + (isFinite(n) ? n : 9999);
  }

  // ------------------------------------------------------------------- model

  // Last segment of a reverse-DNS app id: org.omarchy.agent -> agent.
  function shortId(appId) {
    const id = String(appId || "");
    const dot = id.lastIndexOf(".");
    return dot >= 0 && dot < id.length - 1 ? id.slice(dot + 1) : id;
  }

  function lookup(name) {
    if (!name || typeof DesktopEntries === "undefined" || !DesktopEntries)
      return null;
    try {
      return DesktopEntries.heuristicLookup(name) || DesktopEntries.byId(name) || null;
    } catch (e) {
      return null;
    }
  }

  function entryFor(appId) {
    return root.lookup(appId) || root.lookup(root.shortId(appId));
  }

  function titleCase(value) {
    const words = String(value || "").replace(/[-_.]+/g, " ").trim().split(/ +/);
    const out = [];
    for (let i = 0; i < words.length; i++)
      if (words[i].length > 0)
        out.push(words[i].charAt(0).toUpperCase() + words[i].slice(1));
    return out.join(" ");
  }

  function appName(appId, entry) {
    const n = entry && entry.name ? String(entry.name) : "";
    return n.length > 0 ? n : root.titleCase(root.shortId(appId));
  }

  function iconSource(appId, entry) {
    const name = entry && entry.icon ? String(entry.icon) : "";
    if (name.indexOf("file://") === 0 || name.indexOf("image://") === 0)
      return name;
    if (name.charAt(0) === "/")
      return "file://" + name;
    const id = String(appId || "");
    const tries = [name, id, id.toLowerCase(), root.shortId(id).toLowerCase(),
                   "application-x-executable"];
    for (let i = 0; i < tries.length; i++) {
      if (tries[i].length === 0)
        continue;
      let p = "";
      try { p = Quickshell.iconPath(tries[i], true); } catch (e) {}
      if (p && p.length > 0)
        return p;
    }
    return "";
  }

  function snapshot() {
    const ws = Hyprland.focusedWorkspace;
    const tls = ws && ws.toplevels ? (ws.toplevels.values || []) : [];
    const list = [];
    for (let i = 0; i < tls.length; i++) {
      const h = tls[i];
      const o = h.lastIpcObject;
      if (!h.wayland || (o && (o.mapped === false || o.hidden === true)))
        continue;
      const appId = String(h.wayland.appId || (o && o.class) || "").trim();
      const entry = root.entryFor(appId);
      list.push({ handle: h, rank: root.windowRank(h), appId: appId,
                  name: root.appName(appId, entry), icon: root.iconSource(appId, entry) });
    }
    list.sort((a, b) => a.rank - b.rank);
    return list;
  }

  // ------------------------------------------------------------------ gesture

  function begin(reveal) {
    Hyprland.refreshToplevels();
    root.windows = root.snapshot();
    // Index 0 is the window in front, so the first Tab lands on the previous one.
    root.selected = 0;
    root.armed = true;
    if (reveal)
      revealTimer.restart();
  }

  function move(dir) {
    const n = root.windows.length;
    if (n > 0)
      root.selected = (root.selected + dir + n) % n;
  }

  // Under the Lua parser a dispatch string is code: the address is checked for
  // shape before it goes in.
  function address(handle) {
    let v = String((handle && handle.address) || "").trim().toLowerCase();
    if (v.slice(0, 2) === "0x")
      v = v.slice(2);
    return /^[0-9a-f]{4,16}$/.test(v) ? "0x" + v : "";
  }

  function activate(item) {
    if (!item)
      return;
    const addr = root.address(item.handle);
    if (addr) {
      Hyprland.dispatch(Hyprland.usingLua
        ? "hl.dsp.focus({ window = \"address:" + addr + "\" })"
        : "focuswindow address:" + addr);
      return;
    }
    try {
      if (item.handle.wayland && typeof item.handle.wayland.activate === "function")
        item.handle.wayland.activate();
    } catch (e) {}
  }

  function finish(doSwitch) {
    revealTimer.stop();
    if (!root.armed)
      return "idle";
    const item = root.windows[root.selected];
    root.armed = false;
    root.shown = false;
    if (doSwitch && item && item.rank !== -1)
      root.activate(item);
    return "ok";
  }

  function step(dir) {
    if (!root.armed)
      root.begin(true);
    root.move(dir);
    return "ok";
  }

  function commit() { return root.finish(true) }
  function cancel() { return root.finish(false) }

  // Row appears only when Alt+Tab is held; a quick tap never flashes it.
  Timer {
    id: revealTimer
    interval: Theme.delay("switcher")
    onTriggered: if (root.armed) root.shown = true
  }

  Connections {
    target: ToplevelManager
    function onActiveToplevelChanged() {
      // Not while switching: the row is showing the order the gesture started
      // with, and the focus it hands out is the result, not new input.
      if (!root.armed)
        root.touch(ToplevelManager.activeToplevel);
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "custom")
        return;
      const d = String(event.data);
      if (d === "app-switcher next") root.step(1);
      else if (d === "app-switcher prev") root.step(-1);
      else if (d === "app-switcher commit") root.commit();
      else if (d === "app-switcher cancel") root.cancel();
    }
  }

  IpcHandler {
    target: "app-switcher"

    function next(): string { return root.step(1) }
    function prev(): string { return root.step(-1) }
    function commit(): string { return root.commit() }
    function cancel(): string { return root.cancel() }
    function status(): string {
      const names = [];
      for (let i = 0; i < root.windows.length; i++)
        names.push(root.windows[i].name + ": " + String(root.windows[i].handle.title || ""));
      return JSON.stringify({ armed: root.armed, shown: root.shown,
                              selected: root.selected, windows: names });
    }
  }

  Component.onCompleted: root.touch(ToplevelManager.activeToplevel)

  // --------------------------------------------------------------------- row

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      screen: modelData

      readonly property var hyprMonitor: Hyprland.monitorFor(modelData)
      readonly property bool onFocusedMonitor:
          !Hyprland.focusedMonitor || !hyprMonitor || Hyprland.focusedMonitor.id === hyprMonitor.id
      readonly property real monW: hyprMonitor ? hyprMonitor.width / hyprMonitor.scale : panel.width
      readonly property real monH: hyprMonitor ? hyprMonitor.height / hyprMonitor.scale : panel.height

      // Mapped only while needed: a permanently mapped, click-through overlay
      // breaks the click-outside close of other popups (Hyprland focus grab).
      // Mapping starts with the gesture (armed), so it runs in parallel with
      // the switcher delay instead of after it.
      visible: (root.armed || card.opacity > 0.001) && onFocusedMonitor && root.windows.length > 0
      readonly property bool active: root.shown || card.opacity > 0.001
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "velum-surface"   // Hyprland: blur with ignore_alpha 0.6 (only the material, never the shadow), no layer animation
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      readonly property bool open: root.shown && panel.onFocusedMonitor && root.windows.length > 0
      readonly property real pad: Theme.layout.module.pad * 1.5
      readonly property real gap: Theme.layout.module.gap
      // The workspace switcher's tile size, so both rows read as one family.
      readonly property real tileW: {
        const n = Math.max(1, root.windows.length);
        const room = (panel.width * 0.9 - panel.pad * 2 - (n - 1) * panel.gap) / n;
        return Math.max(Theme.layout.module.width / 5, Math.min(Theme.layout.module.width / 2, room));
      }
      readonly property real tileH: panel.tileW * panel.monH / panel.monW

      TapHandler { enabled: root.shown; onTapped: root.cancel() }

      // Enter: out of the centre, smooth spring from launcherFrom, fast fade.
      // Exit: a little smaller (exitTo), faster fade.
      Spring { id: grow; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion; target: panel.open ? 1 : Theme.scale("exitTo"); value: 1 }
      onOpenChanged: if (open) grow.from(Theme.scale("launcherFrom"))

      VFloatingCard {
        id: card
        anchors.centerIn: parent
        width: row.width + panel.pad * 2
        height: row.height + panel.pad * 2
        scale: grow.value
        opacity: panel.open ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: panel.open ? Theme.dur("fast") : Theme.exit(Theme.dur("base"))
          easing.type: Easing.BezierSpline; easing.bezierCurve: panel.open ? Theme.curve("out") : Theme.curve("exit") } }

        // Swallow clicks on the card's padding so they do not cancel.
        TapHandler {}

        Row {
          id: row
          anchors.centerIn: parent
          spacing: panel.gap

          Repeater {
            model: root.windows

            delegate: Column {
              id: cell
              required property var modelData
              required property int index
              readonly property var ipc: modelData.handle.lastIpcObject
              readonly property real winW: ipc && ipc.size ? ipc.size[0] : panel.monW
              readonly property real winH: ipc && ipc.size ? ipc.size[1] : panel.monH
              // Fit the window into the tile, never upscale past the monitor's scale.
              readonly property real k: Math.min(panel.tileW / Math.max(1, cell.winW), panel.tileH / Math.max(1, cell.winH))
              readonly property bool isSelected: root.selected === index
              readonly property real tileRadius: Theme.m.radius.control

              spacing: Theme.layout.list.gap

              Item {
                width: panel.tileW
                height: panel.tileH

                Item {
                  id: thumb
                  anchors.centerIn: parent
                  width: Math.round(cell.winW * cell.k)
                  height: Math.round(cell.winH * cell.k)

                  Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: MultiEffect {
                      maskEnabled: true
                      maskSource: mask
                      maskThresholdMin: 0.5
                      maskSpreadAtMin: 1.0
                    }

                    // Until the first frame arrives: the app's tile.
                    Rectangle {
                      anchors.fill: parent
                      color: Theme.r.popover.tile
                      visible: !shot.hasContent
                      Image {
                        anchors.centerIn: parent
                        width: Theme.layout.module.toggle
                        height: width
                        source: cell.modelData.icon
                        sourceSize.width: 128
                        sourceSize.height: 128
                        asynchronous: true
                        cache: true
                      }
                    }

                    ScreencopyView {
                      id: shot
                      anchors.fill: parent
                      // Capture only while visible; the service stays loaded.
                      captureSource: panel.active ? cell.modelData.handle.wayland : null
                      live: panel.active
                      paintCursor: false
                    }
                  }

                  Item {
                    id: mask
                    anchors.fill: parent
                    layer.enabled: true
                    visible: false
                    Rectangle { anchors.fill: parent; radius: cell.tileRadius; color: "black" }
                  }

                  // The preview's own hairline, then the selection ring outside
                  // it. The ring jumps instantly (frequent interaction).
                  Rectangle {
                    anchors.fill: parent
                    radius: cell.tileRadius
                    color: "transparent"
                    border.width: Theme.layout.separator
                    border.color: Theme.r.line.base
                  }
                  Rectangle {
                    readonly property real ring: Theme.core.size.focusRing
                    anchors.fill: parent
                    anchors.margins: -2 * ring
                    radius: cell.tileRadius + 2 * ring
                    color: "transparent"
                    visible: cell.isSelected
                    border.width: ring + Theme.layout.separator
                    border.color: Theme.r.accent.base
                  }
                }

                // Hover preselects, like macOS.
                HoverHandler {
                  enabled: root.shown
                  onHoveredChanged: if (hovered) root.selected = cell.index
                }

                TapHandler {
                  onTapped: {
                    root.selected = cell.index;
                    root.finish(true);
                  }
                }
              }

              // App icon and window title: two windows of the same app differ
              // only here.
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.layout.list.gap / 2 + Theme.layout.separator

                Image {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Theme.layout.icon.regular
                  height: width
                  source: cell.modelData.icon
                  visible: source !== "" && status === Image.Ready
                  sourceSize.width: 64
                  sourceSize.height: 64
                  asynchronous: true
                  cache: true
                  smooth: true
                }

                VText {
                  width: Math.min(implicitWidth, panel.tileW - Theme.layout.icon.regular - parent.spacing)
                  text: String(cell.modelData.handle.title || cell.modelData.name)
                  elide: Text.ElideRight
                  font.pixelSize: Theme.m.type.body
                  font.weight: cell.isSelected ? Font.DemiBold : Theme.m.type.bodyWeight
                  color: cell.isSelected ? Theme.r.popover.ink : Theme.r.popover.inkSecondary
                }
              }
            }
          }
        }
      }
    }
  }
}
