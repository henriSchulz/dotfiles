// Workspace Switcher -- Windows-style Super+Tab for Hyprland.
//
// Hold Super and press Tab: after a short moment a strip of live workspace
// previews appears. Every further Tab (Shift+Tab goes back) moves the
// selection. Letting go of Super switches to the selected workspace. A quick
// tap switches straight to the next workspace without flashing the strip.
//
// Keys. Hyprland owns them (bindings.lua): SUPER+TAB, SUPER+SHIFT+TAB and the
// SUPER_L release send `custom>>workspace-switcher <next|prev|commit>` on
// Hyprland's event socket -- no process per key, so there is no latency and
// the events arrive in the order they happened. The strip never takes the
// keyboard: with Super held, Hyprland's binds win anyway, and holding the
// focus made Hyprland refocus the old workspace when the strip let go of it.
// A click outside cancels, a click on a preview switches.
//
// Motion (henri-ui): the strip reveals like a menu from the centre. On commit
// it drifts in the direction the desktop slides (target right of the current
// workspace -> everything moves left) while it fades, and Hyprland's own layer
// fade is off for this namespace (looknfeel.lua), so nothing animates twice.

import QtQuick
import QtQuick.Effects
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

  // A Super+Tab gesture is running (Super is held).
  property bool armed: false
  // The strip is on screen (armed and held longer than Motion.switcherDelay).
  property bool shown: false
  // Workspace ids in strip order, frozen when the gesture starts so the
  // selection index cannot shift under the user while they tab through it.
  property var ids: []
  property int selected: 0
  // Index of the workspace that was active when the gesture started.
  property int origin: 0
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

  function snapshot() {
    const out = [];
    const all = Hyprland.workspaces.values || [];
    for (let i = 0; i < all.length; i++)
      if (all[i].id > 0)
        out.push(all[i].id);
    out.sort((a, b) => a - b);
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
    interval: Motion.switcherDelay
    onTriggered: if (root.armed) root.shown = true
  }

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
                              selected: root.selected });
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

      // Mapped ahead of time (henri-ui §5): mapping on Super+Tab cost ~150 ms
      // before the first frame. While idle it draws nothing and lets every
      // click through.
      visible: onFocusedMonitor
      readonly property bool active: root.shown || reveal.visible
      mask: active ? null : clickThrough
      Region { id: clickThrough }
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "workspace-switcher"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      readonly property real tileW: {
        const n = Math.max(1, root.ids.length);
        const room = (panel.width * 0.9 - card.padding * 2 - (n - 1) * row.spacing) / n;
        return Math.max(90, Math.min(240, room));
      }

      // Click outside the strip closes without switching.
      TapHandler { enabled: root.shown; onTapped: root.cancel() }

      HUi.Reveal {
        id: reveal
        anchors.centerIn: parent
        width: card.width
        height: card.height
        open: root.shown && panel.onFocusedMonitor
        kind: "menu"
        origin: Item.Center
        fromY: 0
        // Enter: straight out of the centre. Exit after a switch: drift along
        // with the workspace slide (the desktop moves opposite to the travel).
        fromX: -root.travel * Motion.carryOffset
        // No focus grab (the strip never takes the keyboard); outside clicks
        // are caught by the panel.
        closeOnOutsideClick: false
        closeOnEscape: false

        Rectangle {
          id: card
          readonly property real padding: 18
          width: row.width + padding * 2
          height: row.height + padding * 2
          radius: Style.space(Motion.radiusPanel)
          color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.97)
          border.width: 1
          border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, Motion.hairlineAlpha)

          // Swallow clicks on the card's padding so they do not cancel.
          TapHandler {}

          Row {
            id: row
            anchors.centerIn: parent
            spacing: 14

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

                spacing: 8

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
                    Rectangle { anchors.fill: parent; radius: Style.space(Motion.radiusControl); color: "black" }
                  }

                  // Selection ring jumps instantly (frequent interaction, like
                  // Cmd+Tab); only its colour eases.
                  Rectangle {
                    anchors.fill: parent
                    anchors.margins: -4
                    radius: Style.space(Motion.radiusControl) + 4
                    color: "transparent"
                    border.width: cell.isSelected ? 3 : 1
                    border.color: cell.isSelected ? Color.accent
                                : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18)
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
                  spacing: 6

                  // Marks where you are now, so the direction of the switch is
                  // readable before you let go.
                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6
                    height: 6
                    radius: 3
                    color: Color.accent
                    visible: cell.isCurrent
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: String(cell.ws && cell.ws.name ? cell.ws.name : cell.modelData)
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.title
                    font.bold: cell.isSelected
                    color: cell.isSelected ? Color.foreground
                         : Util.alpha(Color.foreground, Motion.secondaryTextAlpha)
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
