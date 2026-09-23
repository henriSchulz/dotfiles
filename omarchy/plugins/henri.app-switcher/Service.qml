// App Switcher -- macOS-style Cmd+Tab, on Alt+Tab.
//
// Hold Alt and press Tab: after a short moment a row of app icons appears,
// most recently used first, the current app on the left. Every further Tab
// (Shift+Tab goes back) moves the selection, letting go of Alt switches to it.
// A quick tap switches straight to the previous app without flashing the row --
// exactly what Cmd+Tab does on a Mac.
//
// Apps, not windows. Windows are grouped by their appId, and switching goes to
// the app's most recently used window, wherever it lives; Hyprland follows it
// to the right workspace on its own.
//
// Keys. Hyprland owns them (bindings.lua): ALT+TAB, ALT+SHIFT+TAB and the
// Alt_L release send `custom>>app-switcher <next|prev|commit>` on Hyprland's
// event socket -- no process per key, so there is no latency and the events
// arrive in the order they happened. The row never takes the keyboard: with Alt
// held, Hyprland's binds win anyway, and holding focus would make Hyprland
// refocus the window the row let go of. A click outside cancels, a click on an
// icon switches, hovering preselects.
//
// Order. The switcher keeps its own most-recently-used list, fed by every focus
// change while the shell runs, because Hyprland's focusHistoryID only arrives
// with an IPC refresh and would be one gesture behind. Windows the list has not
// seen yet (right after a shell restart) fall back to that focusHistoryID, so
// the very first Alt+Tab of a session is already in the right order.
//
// Motion (henri-ui): the row reveals like a menu from the centre, the selection
// jumps instantly (frequent interaction), only the app name under it crossfades.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

Item {
  id: root

  property var shell: null
  property var manifest: null

  // An Alt+Tab gesture is running (Alt is held).
  property bool armed: false
  // The row is on screen (armed and held longer than Motion.switcherDelay).
  property bool shown: false
  // App records in row order, frozen when the gesture starts so the selection
  // cannot shift under the user while they tab through it.
  property var apps: []
  property int selected: 0

  // Most recently used windows, newest first. Only ever compared by identity
  // (indexOf), never dereferenced, so entries of closed windows are harmless.
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

  // Hyprland's own focus history, for windows this service has not seen focused
  // yet. Its toplevels carry the matching Wayland handle in `wayland`.
  function hyprHistory(tl) {
    const all = Hyprland.toplevels.values || [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].wayland === tl) {
        const o = all[i].lastIpcObject;
        const n = o ? Number(o.focusHistoryID) : NaN;
        return isFinite(n) ? n : 9999;
      }
    }
    return 9999;
  }

  function windowRank(tl) {
    const i = root.mruWindows.indexOf(tl);
    return i >= 0 ? i : 1000 + root.hyprHistory(tl);
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

  // Reverse-DNS ids often have no desktop entry under the full id, but do under
  // their last segment (org.omarchy.agent -> agent.desktop).
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

  // The desktop entry's name if there is one; otherwise the app id made
  // readable -- the raw "org.omarchy.agent" is not a name anyone recognises.
  function appName(appId, entry) {
    const n = entry && entry.name ? String(entry.name) : "";
    if (n.length > 0)
      return n;
    return root.titleCase(root.shortId(appId));
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
    const list = [];
    const byId = ({});
    const tls = ToplevelManager.toplevels.values || [];
    for (let i = 0; i < tls.length; i++) {
      const tl = tls[i];
      const appId = String(tl && tl.appId ? tl.appId : "").trim();
      if (appId.length === 0)
        continue;
      const rank = root.windowRank(tl);
      const seen = byId[appId];
      if (!seen) {
        const entry = root.entryFor(appId);
        const item = { appId: appId, rank: rank, window: tl, windows: 1,
                       name: root.appName(appId, entry),
                       icon: root.iconSource(appId, entry) };
        byId[appId] = item;
        list.push(item);
      } else {
        seen.windows += 1;
        if (rank < seen.rank) {
          seen.rank = rank;
          seen.window = tl;
        }
      }
    }
    list.sort((a, b) => a.rank - b.rank);
    return list;
  }

  // ------------------------------------------------------------------ gesture

  function begin(reveal) {
    Hyprland.refreshToplevels();
    root.apps = root.snapshot();
    // Index 0 is the app in front, so the first Tab lands on the previous one.
    root.selected = 0;
    root.armed = true;
    if (reveal)
      revealTimer.restart();
  }

  function move(dir) {
    const n = root.apps.length;
    if (n > 0)
      root.selected = (root.selected + dir + n) % n;
  }

  // Wayland activation carries the switch; Hyprland follows the window to its
  // workspace. The dispatch is only a fallback for a toplevel without a handle.
  function activate(item) {
    if (!item)
      return;
    try {
      if (item.window && typeof item.window.activate === "function") {
        item.window.activate();
        return;
      }
    } catch (e) {}
    const all = Hyprland.toplevels.values || [];
    for (let i = 0; i < all.length; i++) {
      if (all[i].wayland !== item.window)
        continue;
      const o = all[i].lastIpcObject;
      const addr = o ? String(o.address || "") : "";
      if (!/^0x[0-9a-f]{4,16}$/.test(addr))
        return;
      Hyprland.dispatch(Hyprland.usingLua
        ? "hl.dsp.focus({ window = \"address:" + addr + "\" })"
        : "focuswindow address:" + addr);
      return;
    }
  }

  function finish(doSwitch) {
    revealTimer.stop();
    if (!root.armed)
      return "idle";
    const item = root.apps[root.selected];
    root.armed = false;
    root.shown = false;
    if (doSwitch && item && root.selected !== 0)
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
    interval: Motion.switcherDelay
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
      for (let i = 0; i < root.apps.length; i++)
        names.push(root.apps[i].name + (root.apps[i].windows > 1 ? " (" + root.apps[i].windows + ")" : ""));
      return JSON.stringify({ armed: root.armed, shown: root.shown,
                              selected: root.selected, apps: names });
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

      // Mapped only while needed: a permanently mapped, click-through overlay
      // breaks the click-outside close of other popups (Hyprland focus grab).
      // Mapping starts with the gesture (armed), so it runs in parallel with
      // Motion.switcherDelay instead of after it.
      visible: (root.armed || reveal.visible) && onFocusedMonitor && root.apps.length > 0
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "app-switcher"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      readonly property int padding: Style.space(22)
      readonly property int gap: Style.space(12)
      readonly property int cellGap: Style.space(12)

      // Icons shrink once the row would leave the screen, like macOS does.
      readonly property int cell: {
        const n = Math.max(1, root.apps.length);
        const room = (panel.width * 0.9 - padding * 2 - (n - 1) * cellGap) / n;
        return Math.round(Math.max(Style.space(44), Math.min(Style.space(96), room)));
      }
      readonly property int iconSize: Math.round(cell * 0.78)

      TapHandler { enabled: root.shown; onTapped: root.cancel() }

      HUi.Reveal {
        id: reveal
        anchors.centerIn: parent
        width: card.width
        height: card.height
        open: root.shown && panel.onFocusedMonitor && root.apps.length > 0
        kind: "menu"
        origin: Item.Center
        fromX: 0
        fromY: 0
        // No focus grab (the row never takes the keyboard); outside clicks are
        // caught by the panel.
        closeOnOutsideClick: false
        closeOnEscape: false

        Rectangle {
          id: card
          width: content.width + panel.padding * 2
          height: content.height + panel.padding * 2
          radius: Style.space(Motion.radiusPanel)
          color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.97)
          border.width: 1
          border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, Motion.hairlineAlpha)

          // Swallow clicks on the card's padding so they do not cancel.
          TapHandler {}

          Column {
            id: content
            anchors.centerIn: parent
            spacing: panel.gap

            Row {
              id: row
              spacing: panel.cellGap

              Repeater {
                model: root.apps

                delegate: Item {
                  id: cell
                  required property var modelData
                  required property int index
                  readonly property bool isSelected: root.selected === index

                  width: panel.cell
                  height: panel.cell

                  // Selection jumps instantly -- this is a frequent, fast
                  // interaction; a gliding highlight would lag the keystroke.
                  Rectangle {
                    anchors.fill: parent
                    radius: Style.space(Motion.radiusPanel)
                    visible: cell.isSelected
                    color: Util.alpha(Color.accent, 0.25)
                  }

                  Image {
                    id: icon
                    anchors.centerIn: parent
                    width: panel.iconSize
                    height: panel.iconSize
                    source: cell.modelData.icon
                    visible: source !== "" && status === Image.Ready
                    sourceSize.width: 128
                    sourceSize.height: 128
                    asynchronous: true
                    cache: true
                    smooth: true
                  }

                  // Nothing on disk for this app: its initial, same footprint.
                  Rectangle {
                    anchors.centerIn: parent
                    width: panel.iconSize
                    height: panel.iconSize
                    radius: Style.space(Motion.radiusControl)
                    visible: !icon.visible
                    color: Util.alpha(Color.foreground, Motion.hoverAlpha)

                    Text {
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: String(cell.modelData.name || "?").charAt(0).toUpperCase()
                      font.family: Style.font.family
                      font.pixelSize: Math.round(panel.iconSize * 0.5)
                      font.weight: Font.DemiBold
                      color: Util.alpha(Color.foreground, Motion.secondaryTextAlpha)
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
              }
            }

            // Name of the selected app. Fixed height so the card never resizes
            // while the selection moves.
            Item {
              width: row.width
              height: Math.round(Style.font.title * 1.6)

              HUi.CrossfadeText {
                anchors.centerIn: parent
                width: parent.width
                text: {
                  const item = root.apps[root.selected];
                  return item ? item.name : "";
                }
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                color: Color.foreground
                fontFamily: Style.font.family
                fontSize: Style.font.title
                fontWeight: Font.DemiBold
              }
            }
          }
        }
      }
    }
  }
}
