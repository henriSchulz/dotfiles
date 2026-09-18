// Workspace Switcher -- Windows-style Super+Tab for Hyprland.
//
// Hold Super and press Tab: after a short moment a strip of live workspace
// previews appears. Every further Tab (Shift+Tab goes back) moves the
// selection. Letting go of Super switches to the selected workspace. A quick
// tap switches straight to the next workspace without flashing the strip.
//
// Event order. Hyprland owns the keys (bindings.lua): SUPER+TAB sends
// `next <seq>`, the SUPER_L release sends `commit <seq>`. Every call is its own
// process, so a quick tap can deliver the release *before* the Tab -- which
// used to leave the strip open or switch nothing. The bindings number every
// event without gaps, so a commit knows how many Tabs came before it: if some
// are still on their way it waits for them (at most overtakenWait), then
// switches. A Tab that shows up with a pending commit never opens the strip.
// The strip also takes keyboard focus and sees the Super release itself; that
// only counts if Hyprland's release never arrives. Esc or a click outside
// cancels, a click on a preview switches.
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

  function parseSeq(seq) {
    const n = Number(seq);
    return isFinite(n) && n > 0 ? n : 0;
  }

  function begin(reveal) {
    Hyprland.refreshWorkspaces();
    Hyprland.refreshToplevels();
    root.ids = root.snapshot();
    root.origin = Math.max(0, root.ids.indexOf(root.activeId()));
    root.selected = root.origin;
    root.travel = 0;
    root.armed = true;
    verifyTimer.stop();
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
    keyReleaseFallback.stop();
    if (!root.armed)
      return "idle";
    const id = root.ids[root.selected];
    const switching = doSwitch && id !== undefined && id !== root.activeId()
                      && /^[0-9]{1,6}$/.test(String(id));
    // Same rule Hyprland uses for its slide: a higher id lies to the right.
    root.travel = switching ? (id > root.activeId() ? 1 : -1) : 0;
    const hadFocus = root.shown;
    root.armed = false;
    root.shown = false;
    if (switching) {
      root.switchTo = id;
      // While the strip holds the keyboard, Hyprland answers its release by
      // refocusing the last window -- on the old workspace, which undid the
      // switch. Hand the keyboard back first, then switch.
      if (hadFocus)
        switchTimer.restart();
      else
        root.dispatchSwitch();
    }
    return "ok";
  }

  property int switchTo: -1

  function dispatchSwitch() {
    switchTimer.stop();
    const id = root.switchTo;
    root.switchTo = -1;
    if (!/^[0-9]{1,6}$/.test(String(id)))
      return;
    Hyprland.dispatch(Hyprland.usingLua
      ? "hl.dsp.focus({ workspace = \"" + id + "\" })"
      : "workspace " + id);
    root.verifyId = id;
    verifyTimer.restart();
  }

  // Safety net: if the old workspace still took the focus back, switch once more.
  property int verifyId: -1
  Timer {
    id: verifyTimer
    interval: 250
    onTriggered: {
      if (!root.armed && root.verifyId > 0 && root.activeId() !== root.verifyId) {
        root.switchTo = root.verifyId;
        root.verifyId = -1;
        root.dispatchSwitch();
        verifyTimer.stop();
      }
      root.verifyId = -1;
    }
  }

  Timer {
    id: switchTimer
    interval: 60
    onTriggered: root.dispatchSwitch()
  }

  // Every sequenced event since the last commit, so a commit can tell whether
  // Tabs it overtook are still on their way.
  property var seen: ({})
  property real lastCommitSeq: 0
  property real pendingCommit: 0

  function note(seq) {
    if (seq)
      root.seen[seq] = true;
  }

  function settle() {
    if (!root.pendingCommit)
      return;
    let missing = 0;
    for (let s = root.lastCommitSeq + 1; s < root.pendingCommit; s++)
      if (!root.seen[s])
        missing++;
    // A large gap is not lost Tabs but a restart (shell or Hyprland config).
    if (missing === 0 || missing > 20)
      root.applyCommit();
    else if (!overtakenWait.running)
      overtakenWait.restart();
  }

  function applyCommit() {
    overtakenWait.stop();
    root.lastCommitSeq = root.pendingCommit;
    root.pendingCommit = 0;
    root.seen = ({});
    root.finish(true);
  }

  function step(dir, seqArg) {
    const seq = root.parseSeq(seqArg);
    if (seq && seq <= root.lastCommitSeq)
      return "stale";   // arrived after its gesture had already given up waiting
    root.note(seq);
    if (!root.armed)
      root.begin(!root.pendingCommit);   // overtaken by the release: no strip
    root.move(dir);
    root.settle();
    return "ok";
  }

  function commit(seqArg) {
    const seq = root.parseSeq(seqArg);
    if (!seq)
      return root.finish(true);
    if (seq <= root.lastCommitSeq)
      return "stale";
    root.note(seq);
    root.pendingCommit = Math.max(root.pendingCommit, seq);
    root.settle();
    return "ok";
  }

  function cancel() {
    return root.finish(false);
  }

  // Strip appears only when Super+Tab is held; a quick tap never flashes it.
  Timer {
    id: revealTimer
    interval: Motion.switcherDelay
    onTriggered: if (root.armed && !root.pendingCommit) root.shown = true
  }
  // Longest a commit waits for Tabs it overtook (each is a separate process).
  Timer {
    id: overtakenWait
    interval: 300
    onTriggered: root.applyCommit()
  }
  // The strip saw Super go up itself. Hyprland's release event is the one that
  // counts (it knows the order); this only catches a release that got lost.
  Timer {
    id: keyReleaseFallback
    interval: 300
    onTriggered: if (root.armed && !root.pendingCommit) root.finish(true)
  }

  IpcHandler {
    target: "workspace-switcher"

    function next(seq: string): string { return root.step(1, seq) }
    function prev(seq: string): string { return root.step(-1, seq) }
    function commit(seq: string): string { return root.commit(seq) }
    function cancel(): string { return root.cancel() }
    function status(): string {
      return JSON.stringify({ armed: root.armed, shown: root.shown, ids: root.ids,
                              selected: root.selected, lastCommitSeq: root.lastCommitSeq,
                              pendingCommit: root.pendingCommit });
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

      // Stays mapped while the strip animates out.
      visible: (root.shown || reveal.visible) && onFocusedMonitor
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "workspace-switcher"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: root.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

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
        // Reveal's focus grab clears the moment the overlay maps (the keyboard
        // grab below and it fight), so outside clicks are caught by the panel.
        closeOnOutsideClick: false
        onDismissRequested: root.cancel()

        Item {
          anchors.fill: parent
          focus: true
          Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
              root.cancel();
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.finish(true);
            } else if (event.key === Qt.Key_Left) {
              root.move(-1);
            } else if (event.key === Qt.Key_Right) {
              root.move(1);
            } else if (!(event.modifiers & Qt.MetaModifier)
                       && event.key !== Qt.Key_Super_L && event.key !== Qt.Key_Super_R
                       && event.key !== Qt.Key_Meta) {
              // Super is no longer held but its release got lost somewhere.
              keyReleaseFallback.restart();
            } else {
              return;
            }
            event.accepted = true;
          }
          Keys.onReleased: event => {
            if (event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R || event.key === Qt.Key_Meta) {
              keyReleaseFallback.restart();
              event.accepted = true;
            }
          }
        }

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
                        captureSource: panel.visible ? modelData.wayland : null
                        live: panel.visible
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
