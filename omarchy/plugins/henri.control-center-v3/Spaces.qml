import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import "file:///home/henri/.local/share/velum/qml/Velum"

// The top tile of the Control Center: a miniature of every workspace
// (wallpaper + live window captures, as the workspace switcher draws them).
// A click switches there and closes the island. Captures run only while
// the island is open. The "+" after them makes a new workspace (the next free number) and goes
// there — Hyprland drops an empty workspace nobody is on, so it can't wait in the row.
VTile {
  id: sp
  property bool active: false
  signal chosen()

  readonly property real pad: Theme.layout.module.pad
  readonly property real gap: Theme.layout.list.gap
  readonly property real labelH: Theme.m.type.body + gap

  readonly property var ids: {
    const out = [];
    const all = Hyprland.workspaces.values || [];
    for (let i = 0; i < all.length; i++)
      if (all[i].id > 0)
        out.push(all[i].id);
    out.sort((a, b) => a - b);
    return out;
  }
  readonly property int currentId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1
  readonly property var focusedMon: Hyprland.focusedMonitor
  readonly property real aspect: focusedMon && focusedMon.width > 0 ? focusedMon.height / focusedMon.width : 0.625
  // as wide as the room allows, at most a quarter of the module width
  readonly property real tileW: {
    const n = ids.length + 1;   // the miniatures and the "+"
    const room = (width - 2 * pad - (n - 1) * pad) / n;
    return Math.max(0, Math.min(Theme.layout.module.width / 4, room));
  }
  readonly property real tileH: tileW * aspect

  width: parent ? parent.width : 0
  height: tileH + labelH + 2 * pad
  visible: ids.length > 0

  readonly property string wallpaperLink: Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
  property string wallpaperTarget: ""
  readonly property string wallpaperSource:
      "file://" + wallpaperLink + (wallpaperTarget ? "?v=" + encodeURIComponent(wallpaperTarget) : "")
  Process {
    id: wallpaperProbe
    command: ["readlink", "-f", sp.wallpaperLink]
    stdout: StdioCollector { onStreamFinished: sp.wallpaperTarget = String(text || "").trim().slice(0, 512) }
  }
  onActiveChanged: if (active) {
    Hyprland.refreshWorkspaces();
    Hyprland.refreshToplevels();
    wallpaperProbe.running = true;
  }

  function workspaceById(id) {
    const all = Hyprland.workspaces.values || [];
    for (let i = 0; i < all.length; i++)
      if (all[i].id === id)
        return all[i];
    return null;
  }
  function go(id) {
    sp.chosen();
    if (id === sp.currentId || !/^[0-9]{1,6}$/.test(String(id)))
      return;
    Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.focus({ workspace = \"" + id + "\" })" : "workspace " + id);
  }
  // the lowest number no workspace has yet
  function addSpace() {
    let id = 1;
    while (sp.ids.indexOf(id) >= 0)
      id++;
    sp.go(id);
  }

  Row {
    anchors.centerIn: parent
    spacing: sp.pad

    Repeater {
      model: sp.ids

      delegate: Column {
        id: cell
        required property var modelData
        readonly property var ws: sp.workspaceById(modelData)
        readonly property var mon: ws && ws.monitor ? ws.monitor : sp.focusedMon
        readonly property real monX: mon ? mon.x : 0
        readonly property real monY: mon ? mon.y : 0
        readonly property real monW: mon && mon.width > 0 ? mon.width / mon.scale : 1
        readonly property bool isCurrent: modelData === sp.currentId
        readonly property real tileRadius: Theme.m.radius.control
        spacing: sp.gap

        Item {
          width: sp.tileW
          height: sp.tileH

          Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect { maskEnabled: true; maskSource: mask; maskThresholdMin: 0.5; maskSpreadAtMin: 1.0 }

            Image {
              anchors.fill: parent
              source: sp.active ? sp.wallpaperSource : ""
              sourceSize.width: sp.tileW * 2
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
                // back to front, so the last used window ends up on top
                out.sort((a, b) => (b.lastIpcObject.focusHistoryID || 0) - (a.lastIpcObject.focusHistoryID || 0));
                return out;
              }
              delegate: ScreencopyView {
                required property var modelData
                readonly property var ipc: modelData.lastIpcObject
                readonly property var at: ipc && ipc.at ? ipc.at : [0, 0]
                readonly property var size: ipc && ipc.size ? ipc.size : [0, 0]
                readonly property real k: sp.tileW / cell.monW
                x: (at[0] - cell.monX) * k
                y: (at[1] - cell.monY) * k
                width: size[0] * k
                height: size[1] * k
                captureSource: sp.active ? modelData.wayland : null
                live: sp.active
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

          // the tile's hairline; the current workspace gets the accent ring outside it
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
            anchors.margins: -ring
            radius: cell.tileRadius + ring
            color: "transparent"
            visible: cell.isCurrent
            border.width: ring
            border.color: Theme.r.accent.base
          }

          TapHandler { onTapped: sp.go(cell.modelData) }
        }

        VText {
          anchors.horizontalCenter: parent.horizontalCenter
          text: String(cell.ws && cell.ws.name ? cell.ws.name : cell.modelData)
          font.weight: cell.isCurrent ? Font.DemiBold : Theme.m.type.bodyWeight
          tone: cell.isCurrent ? "primary" : "secondary"
        }
      }
    }

    // a new workspace
    Column {
      spacing: sp.gap
      VPressable {
        id: addButton
        width: sp.tileW
        height: sp.tileH
        radius: Theme.m.radius.control
        onClicked: sp.addSpace()
        Rectangle {
          anchors.fill: parent
          radius: Theme.m.radius.control
          color: "transparent"
          border.width: Theme.layout.separator
          border.color: Theme.r.line.strong
        }
        VIcon { anchors.centerIn: parent; name: "plus"; weight: "bold"; color: addButton.contentColor }
      }
      VText {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "New"
        tone: "secondary"
      }
    }
  }
}
