// Workspace Switcher -- Windows-style Super+Tab for Hyprland.
//
// Hold Super and press Tab: after a short moment a strip of live workspace
// previews appears. Every further Tab (Shift+Tab goes back) moves the
// selection. Letting go of Super switches to the selected workspace. A quick
// tap switches straight to the previous workspace without flashing the strip.
//
// Order is most recently used, like Cmd+Tab on a Mac, not by number: the
// workspace you are on is leftmost, the one before it next, and so on. That is
// what makes tapping Super+Tab bounce between the two you are working in --
// numeric order sent you one workspace further every time and there was no
// going back and forth. Pressing Tab again walks further into the past.
// Workspaces the list has not seen yet (right after a shell restart) follow in
// numeric order.
//
// Keys. Hyprland owns them (bindings.lua): SUPER+TAB, SUPER+SHIFT+TAB and the
// SUPER_L release send `custom>>workspace-switcher <next|prev|commit>` on
// Hyprland's event socket -- no process per key, so there is no latency and
// the events arrive in the order they happened. The strip never takes the
// keyboard: with Super held, Hyprland's binds win anyway, and holding the
// focus made Hyprland refocus the old workspace when the strip let go of it.
// A click outside cancels, a click on a preview switches.
//
// Look and motion (Velum v3): the strip is a floating card of the popover
// material (Pearl by default), blurred by the compositor (namespace
// velum-surface: blur, ignore_alpha 0.6, no layer animation of its own). It
// appears out of the centre on the smooth spring from launcherFrom with a fast
// fade; on commit it drifts by offset.carry in the direction the desktop
// slides (target right of the current workspace -> everything moves left)
// while it fades out faster than it came. The selection ring jumps.

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

  // A Super+Tab gesture is running (Super is held).
  property bool armed: false
  // The strip is on screen (armed and held longer than the switcher delay).
  property bool shown: false
  // Workspace ids in strip order, frozen when the gesture starts so the
  // selection index cannot shift under the user while they tab through it.
  property var ids: []
  property int selected: 0
  // Index of the workspace that was active when the gesture started.
  property int origin: 0
  // Workspace ids in most-recently-used order, newest first. Kept live from
  // every workspace change while the shell runs -- Hyprland itself only
  // remembers the single previous workspace, which is not enough to walk back.
  property var mru: []
  // Direction of the last switch: +1 = to the right, -1 = to the left, 0 = none.
  property int travel: 0

  readonly property string wallpaperLink:
      Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
  property string wallpaperTarget: ""
  readonly property string wallpaperSource:
      "file://" + wallpaperLink + (wallpaperTarget ? "?v=" + encodeURIComponent(wallpaperTarget) : "")

  function workspaceById(id) {
    const all = Hyprland.workspaces.values || [];
    for (let i = 0; i < all.length; i++)
      if (all[i].id === id)
        return all[i];
    return null;
  }

  function activeId() {
    return Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1;
  }

  function touch(id) {
    if (!(id > 0))
      return;
    const next = [id];
    const prev = root.mru;
    for (let i = 0; i < prev.length && next.length < 32; i++)
      if (prev[i] !== id)
        next.push(prev[i]);
    root.mru = next;
  }

  function snapshot() {
    const live = [];
    const all = Hyprland.workspaces.values || [];
    for (let i = 0; i < all.length; i++)
      if (all[i].id > 0)
        live.push(all[i].id);
    live.sort((a, b) => a - b);

    const active = root.activeId();
    const out = [];
    // Where you are, then where you were, then further back.
    if (live.indexOf(active) >= 0)
      out.push(active);
    for (let i = 0; i < root.mru.length; i++) {
      const id = root.mru[i];
      if (id !== active && live.indexOf(id) >= 0 && out.indexOf(id) < 0)
        out.push(id);
    }
    // Never visited since the shell started: in numeric order, at the end.
    for (let i = 0; i < live.length; i++)
      if (out.indexOf(live[i]) < 0)
        out.push(live[i]);
    return out;
  }

  function begin(reveal) {
    Hyprland.refreshWorkspaces();
    Hyprland.refreshToplevels();
    root.ids = root.snapshot();
    root.origin = Math.max(0, root.ids.indexOf(root.activeId()));
    root.selected = root.origin;
    root.travel = 0;
    root.armed = true;
    if (reveal) {
      wallpaperProbe.running = true;
      revealTimer.restart();
    }
  }

  function move(dir) {
    const n = root.ids.length;
    if (n > 0)
      root.selected = (root.selected + dir + n) % n;
  }

  function finish(doSwitch) {
    revealTimer.stop();
    if (!root.armed)
      return "idle";
    const id = root.ids[root.selected];
    const switching = doSwitch && id !== undefined && id !== root.activeId()
                      && /^[0-9]{1,6}$/.test(String(id));
    // Same rule Hyprland uses for its slide: a higher id lies to the right.
    root.travel = switching ? (id > root.activeId() ? 1 : -1) : 0;
    root.armed = false;
    root.shown = false;
    if (switching)
      Hyprland.dispatch(Hyprland.usingLua
        ? "hl.dsp.focus({ workspace = \"" + id + "\" })"
        : "workspace " + id);
    return "ok";
  }

  function step(dir) {
    if (!root.armed)
      root.begin(true);
    root.move(dir);
    return "ok";
  }

  function commit() {
    return root.finish(true);
  }

  function cancel() {
    return root.finish(false);
  }

  // Strip appears only when Super+Tab is held; a quick tap never flashes it.
  Timer {
    id: revealTimer
    interval: Theme.delay("switcher")
    onTriggered: if (root.armed) root.shown = true
  }

  Connections {
    target: Hyprland
    // Not while a gesture runs: the strip is showing the order it started with,
    // and the switch it hands out is the result, not new input. Recording it
    // afterwards is what the next Super+Tab bounces back to.
    function onFocusedWorkspaceChanged() {
      if (!root.armed)
        root.touch(root.activeId());
    }
  }

  Component.onCompleted: root.touch(root.activeId())

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "custom")
        return;
      const d = String(event.data);
      if (d === "workspace-switcher next") root.step(1);
      else if (d === "workspace-switcher prev") root.step(-1);
      else if (d === "workspace-switcher commit") root.commit();
    }
  }

  IpcHandler {
    target: "workspace-switcher"

    function next(): string { return root.step(1) }
    function prev(): string { return root.step(-1) }
    function commit(): string { return root.commit() }
    function cancel(): string { return root.cancel() }
    function status(): string {
      return JSON.stringify({ armed: root.armed, shown: root.shown, ids: root.ids,
                              selected: root.selected, mru: root.mru });
    }
  }

  // The wallpaper link is replaced on a theme change; the target path busts
  // the image cache so the previews pick the new one up.
  Process {
    id: wallpaperProbe
    command: ["readlink", "-f", root.wallpaperLink]
    stdout: StdioCollector {
      onStreamFinished: root.wallpaperTarget = String(text || "").trim().slice(0, 512)
    }
  }

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
      // broke the click-outside close of other popups (Hyprland focus grab).
      // Mapping starts with the gesture (armed), so it runs in parallel with
      // the switcher delay instead of after it.
      visible: (root.armed || card.opacity > 0.001) && onFocusedMonitor
      readonly property bool active: root.shown || card.opacity > 0.001
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "velum-surface"   // Hyprland: blur with ignore_alpha 0.6 (only the material, never the shadow), no layer animation
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      readonly property bool open: root.shown && panel.onFocusedMonitor
      readonly property real pad: Theme.layout.module.pad * 1.5
      readonly property real gap: Theme.layout.module.gap
      readonly property real tileW: {
        const n = Math.max(1, root.ids.length);
        const room = (panel.width * 0.9 - panel.pad * 2 - (n - 1) * panel.gap) / n;
        return Math.max(Theme.layout.module.width / 5, Math.min(Theme.layout.module.width / 2, room));
      }

      // Click outside the strip closes without switching.
      TapHandler { enabled: root.shown; onTapped: root.cancel() }

      // Enter: out of the centre, smooth spring from launcherFrom, fast fade.
      // Exit: a little smaller (exitTo), faster fade; after a switch it drifts
      // along with the workspace slide (the desktop moves opposite to the travel).
      Spring { id: grow; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion; target: panel.open ? 1 : Theme.scale("exitTo"); value: 1 }
      Spring { id: drift; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion; target: panel.open ? 0 : -root.travel * Theme.move(Theme.core.motion.offset.carry) }
      onOpenChanged: if (open) { grow.from(Theme.scale("launcherFrom")); drift.snap(0) }

      VFloatingCard {
        id: card
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: drift.value
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
            model: root.ids

            delegate: Column {
              id: cell
              required property var modelData
              required property int index
              readonly property var ws: root.workspaceById(modelData)
              readonly property var mon: ws && ws.monitor ? ws.monitor : panel.hyprMonitor
              readonly property real monX: mon ? mon.x : 0
              readonly property real monY: mon ? mon.y : 0
              readonly property real monW: mon ? mon.width / mon.scale : panel.width
              readonly property real monH: mon ? mon.height / mon.scale : panel.height
              readonly property bool isSelected: root.selected === index
              readonly property bool isCurrent: root.origin === index
              readonly property real tileRadius: Theme.m.radius.control

              spacing: Theme.layout.list.gap

              Item {
                width: panel.tileW
                height: panel.tileW * cell.monH / cell.monW

                Item {
                  anchors.fill: parent
                  layer.enabled: true
                  layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: mask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                  }

                  Image {
                    anchors.fill: parent
                    source: root.wallpaperSource
                    sourceSize.width: 480
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                  }

                  Repeater {
                    model: {
                      const out = [];
                      const tls = cell.ws && cell.ws.toplevels ? (cell.ws.toplevels.values || []) : [];
                      for (let i = 0; i < tls.length; i++) {
                        const o = tls[i].lastIpcObject;
                        if (tls[i].wayland && o && o.mapped !== false && o.hidden !== true)
                          out.push(tls[i]);
                      }
                      // Back to front, so the last used window ends up on top.
                      out.sort((a, b) => (b.lastIpcObject.focusHistoryID || 0) - (a.lastIpcObject.focusHistoryID || 0));
                      return out;
                    }

                    delegate: ScreencopyView {
                      required property var modelData
                      readonly property var ipc: modelData.lastIpcObject
                      readonly property var at: ipc && ipc.at ? ipc.at : [0, 0]
                      readonly property var size: ipc && ipc.size ? ipc.size : [0, 0]
                      readonly property real k: panel.tileW / cell.monW
                      x: (at[0] - cell.monX) * k
                      y: (at[1] - cell.monY) * k
                      width: size[0] * k
                      height: size[1] * k
                      // Capture only while visible; the service stays loaded.
                      captureSource: panel.active ? modelData.wayland : null
                      live: panel.active
                      paintCursor: false
                    }
                  }
                }

                Item {
                  id: mask
                  anchors.fill: parent
                  layer.enabled: true
                  visible: false
                  Rectangle { anchors.fill: parent; radius: cell.tileRadius; color: "black" }
                }

                // The tile's own hairline, then the selection ring outside it. The
                // ring jumps instantly (frequent interaction, like Cmd+Tab).
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

                TapHandler {
                  onTapped: {
                    root.selected = cell.index;
                    root.finish(true);
                  }
                }
              }

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.layout.list.gap / 2 + Theme.layout.separator

                // Marks where you are now, so the direction of the switch is
                // readable before you let go.
                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: Theme.layout.list.gap - Theme.layout.separator
                  height: width
                  radius: width / 2
                  color: Theme.r.accent.base
                  visible: cell.isCurrent
                }

                VText {
                  text: String(cell.ws && cell.ws.name ? cell.ws.name : cell.modelData)
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
