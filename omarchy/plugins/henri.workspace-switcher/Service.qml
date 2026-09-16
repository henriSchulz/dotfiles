// Workspace Switcher -- Windows-style Super+Tab for Hyprland.
//
// Hold Super and press Tab: a small strip of live workspace previews appears in
// the middle of the screen. Every further Tab (Shift+Tab goes back) moves the
// selection. Letting go of Super switches to the selected workspace -- nothing
// changes before that.
//
// Hyprland owns the keys: SUPER+TAB calls `next`/`prev` over IPC, and a release
// bind on SUPER_L calls `commit`. The strip also takes keyboard focus, so it
// sees the Super release itself; whichever arrives first wins, the other is a
// no-op. Esc cancels, a click on a preview switches right away.

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool shown: false
  // Workspace ids in strip order, frozen when the strip opens so the selection
  // index cannot shift under the user while they tab through it.
  property var ids: []
  property int selected: 0

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

  function snapshot() {
    const out = [];
    const all = Hyprland.workspaces.values || [];
    for (let i = 0; i < all.length; i++)
      if (all[i].id > 0)
        out.push(all[i].id);
    out.sort((a, b) => a - b);
    return out;
  }

  function step(dir) {
    if (!root.shown) {
      Hyprland.refreshMonitors();
      Hyprland.refreshWorkspaces();
      Hyprland.refreshToplevels();
      wallpaperProbe.running = true;
      root.ids = root.snapshot();
      const active = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1;
      root.selected = Math.max(0, root.ids.indexOf(active));
      root.shown = true;
    }
    const n = root.ids.length;
    if (n > 0)
      root.selected = (root.selected + dir + n) % n;
    return "ok";
  }

  function commit() {
    if (!root.shown)
      return "idle";
    const id = root.ids[root.selected];
    root.shown = false;
    if (id !== undefined && /^[0-9]{1,6}$/.test(String(id))) {
      const active = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1;
      if (id !== active)
        Hyprland.dispatch(Hyprland.usingLua
          ? "hl.dsp.focus({ workspace = \"" + id + "\" })"
          : "workspace " + id);
    }
    return "ok";
  }

  function cancel() {
    root.shown = false;
    return "ok";
  }

  IpcHandler {
    target: "workspace-switcher"

    function next(): string { return root.step(1) }
    function prev(): string { return root.step(-1) }
    function commit(): string { return root.commit() }
    function cancel(): string { return root.cancel() }
    function status(): string {
      return JSON.stringify({ shown: root.shown, ids: root.ids, selected: root.selected });
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

      visible: root.shown && onFocusedMonitor
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "workspace-switcher"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

      readonly property real tileW: {
        const n = Math.max(1, root.ids.length);
        const room = (panel.width * 0.9 - card.padding * 2 - (n - 1) * row.spacing) / n;
        return Math.max(90, Math.min(240, room));
      }

      // Click outside the card closes without switching.
      TapHandler { onTapped: root.cancel() }

      Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.cancel()
        Keys.onReturnPressed: root.commit()
        Keys.onEnterPressed: root.commit()
        Keys.onLeftPressed: root.step(-1)
        Keys.onRightPressed: root.step(1)
        Keys.onReleased: event => {
          // Only the Super key itself -- the modifier mask on other releases
          // (Tab, Shift) is not reliable enough to decide on.
          if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta) {
            root.commit("key");
            event.accepted = true;
          }
        }
      }

      Rectangle {
        id: card
        readonly property real padding: 18
        anchors.centerIn: parent
        width: row.width + padding * 2
        height: row.height + padding * 2
        radius: 14
        color: Qt.rgba(Color.background.r, Color.background.g, Color.background.b, 0.88)
        border.width: 1
        border.color: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.12)

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
              readonly property bool isActive: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id === modelData

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
                      captureSource: root.shown ? modelData.wayland : null
                      live: root.shown
                      paintCursor: false
                    }
                  }
                }

                Item {
                  id: mask
                  anchors.fill: parent
                  layer.enabled: true
                  visible: false
                  Rectangle { anchors.fill: parent; radius: 8; color: "black" }
                }

                Rectangle {
                  anchors.fill: parent
                  anchors.margins: -4
                  radius: 11
                  color: "transparent"
                  border.width: cell.isSelected ? 3 : 1
                  border.color: cell.isSelected ? Color.accent
                              : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.18)
                }

                TapHandler {
                  onTapped: {
                    root.selected = cell.index;
                    root.commit();
                  }
                }
              }

              Text {
                width: panel.tileW
                horizontalAlignment: Text.AlignHCenter
                textFormat: Text.PlainText
                text: String(cell.ws && cell.ws.name ? cell.ws.name : cell.modelData)
                font.family: Style.font.menuFamily
                font.pixelSize: 14
                font.bold: cell.isActive
                color: cell.isSelected ? Color.foreground
                     : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.6)
              }
            }
          }
        }
      }
    }
  }
}
