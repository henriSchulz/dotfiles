// Wallpaper -- macOS-style picker for a global desktop wallpaper (v3, Velum).
//
// Shows the images in ~/Pictures/Wallpaper as a grid of thumbnails, one
// section per subfolder (as macOS's Wallpaper settings: the folder's name, one
// row, Show All for the rest; pictures loose in the folder come first). A click
// sets the wallpaper right away (the card stays open to try the next one),
// Enter sets it and closes, Esc or a click beside the card closes. The chosen
// image is kept for every theme: `henri-wallpaper set` records it in
// ~/.config/omarchy/global-wallpaper, and henri.background(-v3) then only
// recolors on a theme change. The switch at the bottom hands the background
// back to the theme.
//
// Open with `omarchy-shell wallpaper toggle` (SUPER+CTRL+SPACE in
// bindings.lua, or a double click on the desktop, which henri.background(-v3)
// forwards). IPC target "wallpaper": toggle | open | close | set PATH | status.
//
// v3: the same logic, state files and IPC as henri.wallpaper, drawn with
// Velum. The card is a VPopover in the middle of the screen (popover material,
// blurred by the compositor through the namespace velum-surface; it grows on
// the popover spring and leaves faster), padded and spaced like a sheet over
// the scrim of a sheet. Thumbnails, ring and badge: surface.wallpaper tokens.

import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.Commons
import "file:///home/henri/.local/share/velum/qml/Velum"

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string bin: home + "/.local/bin/henri-wallpaper"
  // henri-wallpaper's folder (HENRI_WALLPAPER_DIR: the rig shows the real one under its fake HOME)
  readonly property string folder: Quickshell.env("HENRI_WALLPAPER_DIR") || home + "/Pictures/Wallpaper"
  readonly property string folderLabel: "~/Pictures/Wallpaper"

  readonly property var wp: Theme.core.surface.wallpaper

  property bool opened: false
  // Monitor the card opened on; it stays there even if focus moves.
  property string screenName: ""
  // [{ path, thumb, section }] in the order on screen: section by section.
  property var images: []
  // [{ key, title, start, count }]: key = the folder below root.folder ("" = loose pictures).
  property var sections: []
  // key -> true for the sections showing all their pictures (Show All).
  property var expanded: ({})
  property bool loaded: false
  // Image on screen right now (theme or global).
  property string displayed: ""
  // Global wallpaper; empty = the theme picks the background.
  readonly property string pinned: String(pinView.text() || "").trim()
  readonly property bool globalMode: pinned !== ""
  // Keyboard cursor in the grid.
  property int cursor: 0
  property bool keyboardNav: false

  readonly property int columns: wp.columns

  // the view scrolls to the tile with this index (cells answer it)
  signal revealRequested(int index)

  function sectionOf(index) {
    for (let s = 0; s < sections.length; s++)
      if (index >= sections[s].start && index < sections[s].start + sections[s].count)
        return sections[s];
    return null;
  }

  function shownCount(sec) {
    return root.expanded[sec.key] ? sec.count : Math.min(sec.count, root.columns);
  }

  function setExpanded(key, on) {
    const next = Object.assign({}, root.expanded);
    if (on) next[key] = true;
    else delete next[key];
    root.expanded = next;
    // the keyboard cursor never stays on a picture that went away
    const sec = root.sectionOf(root.cursor);
    if (!on && sec && sec.key === key && root.cursor >= sec.start + root.columns)
      root.cursor = sec.start + root.columns - 1;
  }

  // the section of the picture on screen shows it (open, new listing)
  function expandForCurrent() {
    const i = root.indexOfPath(root.displayed);
    const sec = root.sectionOf(i);
    if (sec && i >= sec.start + root.columns && !root.expanded[sec.key])
      root.setExpanded(sec.key, true);
  }

  // the tiles on screen, row by row across the sections: [[index, …], …]
  function visibleRows() {
    const rows = [];
    for (let s = 0; s < sections.length; s++) {
      const sec = sections[s], n = root.shownCount(sec);
      for (let r = 0; r < n; r += root.columns) {
        const row = [];
        for (let c = r; c < Math.min(n, r + root.columns); c++)
          row.push(sec.start + c);
        rows.push(row);
      }
    }
    return rows;
  }

  function indexOfPath(path) {
    for (let i = 0; i < images.length; i++)
      if (images[i].path === path)
        return i;
    return -1;
  }

  function open() {
    if (root.opened)
      return "ok";
    const mon = Hyprland.focusedMonitor;
    root.screenName = mon ? mon.name : "";
    root.keyboardNav = false;
    root.expandForCurrent();
    root.cursor = Math.max(0, root.indexOfPath(root.displayed));
    root.opened = true;
    root.refresh();
    return "ok";
  }

  function close() {
    root.opened = false;
    return "ok";
  }

  function toggle() {
    return root.opened ? root.close() : root.open();
  }

  function refresh() {
    if (!listProc.running)
      listProc.running = true;
    if (!linkProc.running)
      linkProc.running = true;
  }

  function apply(path, andClose) {
    if (!path)
      return;
    root.displayed = path;
    Quickshell.execDetached([root.bin, "set", path]);
    if (andClose)
      root.close();
  }

  function setGlobal(on) {
    if (on) {
      const pick = root.images[root.cursor] ? root.images[root.cursor].path : root.displayed;
      root.apply(pick, false);
    } else {
      Quickshell.execDetached([root.bin, "theme"]);
      themeLinkDelay.restart();
    }
  }

  function openFolder() {
    Quickshell.execDetached(["bash", "-c", "mkdir -p \"$1\" && xdg-open \"$1\"", "_", root.folder]);
    root.close();
  }

  // left/right (delta ±1) and Home/End (±Infinity) walk the tiles on screen in reading order
  function moveCursor(delta) {
    const flat = [].concat.apply([], root.visibleRows());
    if (flat.length === 0)
      return;
    root.keyboardNav = true;
    const at = Math.max(0, flat.indexOf(root.cursor));
    root.cursor = flat[Math.max(0, Math.min(flat.length - 1, at + delta))];
  }

  // up/down: the same column of the next row, which may be the next section's
  function moveRow(delta) {
    const rows = root.visibleRows();
    if (rows.length === 0)
      return;
    root.keyboardNav = true;
    let r = rows.findIndex(row => row.indexOf(root.cursor) >= 0);
    if (r < 0) { root.cursor = rows[0][0]; return; }
    const c = rows[r].indexOf(root.cursor);
    r = Math.max(0, Math.min(rows.length - 1, r + delta));
    root.cursor = rows[r][Math.min(c, rows[r].length - 1)];
  }

  IpcHandler {
    target: "wallpaper"

    function toggle(): string { return root.toggle() }
    function open(): string { return root.open() }
    function close(): string { return root.close() }
    function set(path: string): string { root.apply(path, false); return "ok" }
    // Show All / Show Less of a section, by its folder ("" = the loose pictures)
    function showAll(key: string, on: bool): string { root.setExpanded(key, on); return "ok" }
    // the rig only (VELUM_SHELL_RIG): slow every Velum motion down to look at it frame by frame
    function rigSpeed(factor: string): string {
      if (!Quickshell.env("VELUM_SHELL_RIG")) return "rig only";
      Theme.speed = Math.max(1, Number(factor) || 1);
      return "speed " + Theme.speed;
    }
    function status(): string {
      return JSON.stringify({ opened: root.opened, screen: root.screenName, images: root.images.length,
        sections: root.sections.map(s => s.key + ":" + s.count), expanded: Object.keys(root.expanded),
        displayed: root.displayed, pinned: root.pinned, cursor: root.cursor });
    }
  }

  FileView {
    id: pinView
    path: root.home + "/.config/omarchy/global-wallpaper"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  Process {
    id: listProc
    command: [root.bin, "list"]
    stdout: StdioCollector {
      onStreamFinished: {
        // group by folder: the loose pictures first, then the folders in natural order
        const bySection = {};
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
          const parts = lines[i].split("\t");
          if (parts.length !== 2 || !parts[0])
            continue;
          const rel = parts[0].startsWith(root.folder + "/") ? parts[0].slice(root.folder.length + 1) : parts[0];
          const key = rel.indexOf("/") >= 0 ? rel.slice(0, rel.lastIndexOf("/")) : "";
          (bySection[key] = bySection[key] || []).push({ path: parts[0], thumb: parts[1], section: key });
        }
        const keys = Object.keys(bySection).sort((a, b) =>
          a === "" ? -1 : b === "" ? 1 : a.localeCompare(b, undefined, { numeric: true, sensitivity: "base" }));
        const out = [], secs = [];
        for (const key of keys) {
          secs.push({ key: key, title: key === "" ? "Pictures" : key.split("/").join(" / "),
                      start: out.length, count: bySection[key].length });
          Array.prototype.push.apply(out, bySection[key]);
        }
        root.sections = secs;
        root.images = out;
        root.loaded = true;
        if (root.opened && !root.keyboardNav)
          root.expandForCurrent();
        if (!root.keyboardNav)
          root.cursor = Math.max(0, root.indexOfPath(root.displayed));
        root.cursor = Math.min(root.cursor, Math.max(0, out.length - 1));
      }
    }
  }

  // The link points at a display-size copy; `displayed` maps it back to the
  // original in the folder, which is what the grid knows.
  Process {
    id: linkProc
    command: [root.bin, "displayed"]
    stdout: StdioCollector {
      onStreamFinished: root.displayed = String(text || "").trim()
    }
  }

  // `henri-wallpaper theme` swaps the link asynchronously; read it back after
  // (the same wait as the live picker, henri-ui Motion.slow).
  Timer {
    id: themeLinkDelay
    interval: Theme.dur("slow")
    onTriggered: if (!linkProc.running) linkProc.running = true
  }

  // Thumbnails are cheap once cached; build them at login, not on first open.
  Component.onCompleted: root.refresh()

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData

      readonly property bool here: root.screenName === "" || modelData.name === root.screenName
      readonly property bool shown: root.opened && here

      visible: here && (root.opened || card.visible || scrim.opacity > 0)
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      // compositor blur behind the card's material (ignore_alpha 0.6: the scrim and shadow stay unblurred)
      WlrLayershell.namespace: "velum-surface"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: win.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

      // the scrim of a sheet: the desktop dims a little behind the card; a click on it closes
      Rectangle {
        id: scrim
        anchors.fill: parent
        color: Theme.core.color.scrim
        opacity: win.shown ? Theme.core.alpha.scrim : 0
        Behavior on opacity {
          NumberAnimation {
            duration: win.shown ? Theme.dur("slow") : Theme.exit(Theme.dur("slow"))
            easing.type: Easing.BezierSpline
            easing.bezierCurve: win.shown ? Theme.curve("out") : Theme.curve("exit")
          }
        }
        MouseArea { anchors.fill: parent; enabled: win.shown; onClicked: root.close() }
      }

      Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(e) {
          switch (e.key) {
          case Qt.Key_Left: root.moveCursor(-1); break;
          case Qt.Key_Right: root.moveCursor(1); break;
          case Qt.Key_Up: root.moveRow(-1); break;
          case Qt.Key_Down: root.moveRow(1); break;
          case Qt.Key_Home: root.moveCursor(-Infinity); break;
          case Qt.Key_End: root.moveCursor(Infinity); break;
          case Qt.Key_Escape: root.close(); break;
          case Qt.Key_Space:
            if (root.images[root.cursor]) root.apply(root.images[root.cursor].path, false);
            break;
          case Qt.Key_Return:
          case Qt.Key_Enter:
            if (root.images[root.cursor]) root.apply(root.images[root.cursor].path, true);
            else root.close();
            break;
          default:
            e.accepted = false;
            return;
          }
          e.accepted = true;
        }
      }

      // swallows clicks on the card's own empty space, so they never reach the scrim
      MouseArea { anchors.fill: card; enabled: win.shown }

      VPopover {
        id: card
        anchors.centerIn: parent
        open: win.shown
        origin: Item.Center
        pad: Theme.layout.sheet.pad
        radius: Theme.m.radius.panel

        // the grid: whole thumbnails, the ring's room around them; a section = its head + its rows
        readonly property real ring: root.wp.ring
        readonly property real tileW: root.wp.tile
        readonly property real tileH: Math.round(root.wp.tile * root.wp.tileAspect)
        readonly property real gap: root.wp.gap
        readonly property real gridW: root.columns * tileW + (root.columns - 1) * gap
        // a section's head: its folder's name and Show All, a button high
        readonly property bool heads: root.sections.length > 1 || (root.sections.length === 1 && root.sections[0].key !== "")
        readonly property real headH: heads ? Theme.m.control.height + Theme.layout.section.gap : 0
        // wp.rows sections of one row fit, half a section gap of the next peeks out
        readonly property real capH: root.wp.rows * (headH + tileH) + (root.wp.rows - 1) * root.wp.sectionGap + root.wp.sectionGap / 2
        readonly property real viewH: root.images.length === 0
          ? tileH * root.wp.empty
          : Math.min(sectionsCol.height, capH) + 2 * ring

        Column {
          id: body
          width: card.gridW + 2 * card.ring
          spacing: Theme.layout.sheet.gap

          // ---- head: title, folder and count, Open Folder
          Item {
            width: parent.width
            height: Math.max(titles.implicitHeight, folderButton.implicitHeight)

            Column {
              id: titles
              x: card.ring
              anchors.verticalCenter: parent.verticalCenter
              VText {
                text: "Wallpaper"
                font.pixelSize: Theme.m.type.title
                font.weight: Font.DemiBold
              }
              VCrossfadeText {
                width: body.width - folderButton.width - 2 * card.ring - Theme.layout.list.gap
                text: root.folderLabel + (root.loaded
                  ? "  ·  " + root.images.length + (root.images.length === 1 ? " picture" : " pictures")
                    + (card.heads ? " in " + root.sections.length + (root.sections.length === 1 ? " folder" : " folders") : "")
                  : "")
                tone: "secondary"
                pixelSize: Theme.m.type.small
              }
            }

            VButton {
              id: folderButton
              anchors.right: parent.right
              anchors.rightMargin: card.ring
              anchors.verticalCenter: parent.verticalCenter
              icon: "folder"
              text: "Open Folder"
              onClicked: root.openFolder()
            }
          }

          // ---- the grid of thumbnails
          Flickable {
            id: flick
            width: parent.width
            height: card.viewH
            clip: true
            contentWidth: width
            contentHeight: sectionsCol.height + 2 * card.ring
            interactive: contentHeight > height
            boundsBehavior: Flickable.DragAndOvershootBounds
            flickDeceleration: root.wp.flickDeceleration
            maximumFlickVelocity: root.wp.maxFlickVelocity

            // touchpad: Omarchy scales touchpad scrolling by 0.4 for every surface (input.lua scroll_factor),
            // so the grid takes the fingers itself — 1:1 again, and on lift a flick at the fingers' speed
            WheelHandler {
              acceptedDevices: PointerDevice.TouchPad
              property var samples: []   // [{ t, dy }] of the last momentumWindow ms
              onWheel: ev => {
                if (!flick.interactive)
                  return;
                const now = Date.now();
                const recent = samples.filter(s => now - s.t <= Theme.core.motion.scroll.momentumWindow);
                if (ev.phase === Qt.ScrollEnd) {
                  samples = [];
                  if (recent.length > 1) {
                    const span = Math.max(1, now - recent[0].t);
                    flick.flick(0, recent.reduce((a, s) => a + s.dy, 0) / span * 1000);   // lint-ok: ms → s
                  }
                  return;
                }
                if (ev.phase === Qt.ScrollBegin) {
                  flick.cancelFlick();
                  recent.length = 0;
                }
                root.keyboardNav = false;
                const dy = ev.pixelDelta.y * Theme.core.motion.scroll.touchpadGain;
                recent.push({ t: now, dy: dy });
                samples = recent;
                flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - dy));
              }
            }

            // the keyboard cursor scrolls the grid along (a visible thing moves A → B)
            Behavior on contentY {
              enabled: root.keyboardNav
              NumberAnimation { duration: Theme.move(Theme.dur("base")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") }
            }

            // a tile into view, with its section's head when it sits in the first row
            function revealItem(item, withHead) {
              const p = item.mapToItem(flick.contentItem, 0, 0);
              const top = p.y - card.ring - (withHead ? card.headH : 0);
              const bottom = p.y + card.tileH + card.ring;
              const maxY = Math.max(0, contentHeight - height);
              if (top < contentY)
                contentY = Math.max(0, top);
              else if (bottom > contentY + height)
                contentY = Math.min(maxY, bottom - height);
            }

            Connections {
              target: root
              function onCursorChanged() { if (root.keyboardNav) root.revealRequested(root.cursor) }
              // the picture on screen is in view when the card opens (it jumps there, nothing scrolls)
              function onOpenedChanged() { if (root.opened) Qt.callLater(flick.showCurrent) }
              function onImagesChanged() { if (root.opened && !root.keyboardNav) Qt.callLater(flick.showCurrent) }
            }
            function showCurrent() {
              const i = root.indexOfPath(root.displayed);
              if (i >= 0) root.revealRequested(i);
            }

            Column {
              id: sectionsCol
              x: card.ring
              y: card.ring
              width: card.gridW
              spacing: root.wp.sectionGap

              Repeater {
                model: root.sections

                Column {
                  id: section
                  required property var modelData
                  readonly property bool all: !!root.expanded[section.modelData.key]
                  readonly property bool more: section.modelData.count > root.columns
                  width: sectionsCol.width
                  spacing: Theme.layout.section.gap

                  // ---- the section's head: folder name, Show All (N) / Show Less
                  Item {
                    width: parent.width
                    height: Theme.m.control.height
                    visible: card.heads

                    VText {
                      anchors.left: parent.left
                      anchors.right: showAll.visible ? showAll.left : parent.right
                      anchors.rightMargin: Theme.layout.list.gap
                      anchors.verticalCenter: parent.verticalCenter
                      text: section.modelData.title
                      font.weight: Font.DemiBold
                      elide: Text.ElideRight
                    }
                    VButton {
                      id: showAll
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      visible: section.more
                      kind: "plain"
                      text: section.all ? "Show Less" : "Show All (" + section.modelData.count + ")"
                      onClicked: {
                        root.keyboardNav = false;
                        root.setExpanded(section.modelData.key, !section.all);
                      }
                    }
                  }

                  Grid {
                    columns: root.columns
                    spacing: card.gap

                    Repeater {
                      model: root.images.slice(section.modelData.start, section.modelData.start + section.modelData.count)

                      Item {
                        id: cell
                        required property var modelData
                        required property int index
                        readonly property int gi: section.modelData.start + cell.index
                        width: card.tileW
                        height: card.tileH
                        // the first row always, the rest with Show All (it fades in; Show Less jumps)
                        readonly property bool shown: cell.index < root.columns || section.all
                        visible: cell.shown
                        onShownChanged: if (cell.shown && root.opened) fadeIn.restart()
                        NumberAnimation {
                          id: fadeIn
                          target: cell; property: "opacity"; from: 0; to: 1
                          duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out")
                        }

                        readonly property bool current: cell.modelData.path === root.displayed
                        readonly property bool cursorHere: root.keyboardNav && root.cursor === cell.gi

                        Connections {
                          target: root
                          function onRevealRequested(i) { if (i === cell.gi && cell.visible) flick.revealItem(cell, cell.index < root.columns) }
                        }
                          // the ring: accent around the picture on screen, half strength on the keyboard cursor; it jumps
                          Rectangle {
                            anchors.fill: parent
                            anchors.margins: -(card.ring - Theme.layout.separator)
                            radius: Theme.m.radius.control + card.ring - Theme.layout.separator
                            color: "transparent"
                            border.width: root.wp.ringWidth
                            border.color: Theme.r.accent.base
                            opacity: cell.current ? 1 : cell.cursorHere ? Theme.core.alpha.focusRing : 0
                          }

                          VPressable {
                            id: tile
                            anchors.fill: parent
                            showFill: false
                            activeFocusOnTab: false
                            radius: Theme.m.radius.control
                            Accessible.name: cell.modelData.path.split("/").pop()
                            onClicked: {
                              root.keyboardNav = false;
                              root.cursor = cell.gi;
                              root.apply(cell.modelData.path, false);
                            }

                            ClippingRectangle {
                              anchors.fill: parent
                              radius: tile.radius
                              color: Theme.r.popover.fillHover

                              Image {
                                anchors.fill: parent
                                source: Util.fileUrl(cell.modelData.thumb)
                                sourceSize.width: Math.ceil(2 * card.tileW)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                                smooth: true
                                opacity: status === Image.Ready ? 1 : 0
                                Behavior on opacity {
                                  NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") }
                                }
                              }

                              // hover / press veil over the photo: in at once, out on fast
                              Rectangle {
                                anchors.fill: parent
                                color: tile.tint
                                opacity: tile.pressed ? Theme.core.alpha.pressed : tile.hovered ? Theme.core.alpha.hover : 0
                                Behavior on opacity {
                                  NumberAnimation {
                                    duration: (tile.hovered || tile.pressed) ? Theme.dur("instant") : Theme.dur("fast")
                                    easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out")
                                  }
                                }
                              }
                            }

                            // the check on the picture on screen
                            Rectangle {
                              width: root.wp.badge
                              height: width
                              radius: width / 2
                              anchors.right: parent.right
                              anchors.bottom: parent.bottom
                              anchors.margins: root.wp.badgeInset
                              color: Theme.r.accent.base
                              border.width: root.wp.badgeRim
                              border.color: Theme.r.ink.onAccent
                              opacity: cell.current ? 1 : 0
                              scale: badgeScale.value
                              Behavior on opacity {
                                NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") }
                              }

                              VIcon {
                                anchors.centerIn: parent
                                name: "check"
                                weight: "bold"
                                size: Theme.layout.icon.small
                                color: Theme.r.ink.onAccent
                              }
                            }
                            Spring { id: badgeScale; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: cell.current ? 1 : Theme.scale("iconFrom") }
                          }
                      }
                    }
                  }
                }
              }
            }

            // ---- an empty folder
            Column {
              anchors.centerIn: parent
              spacing: Theme.layout.section.gap
              opacity: root.loaded && root.images.length === 0 ? 1 : 0
              visible: opacity > 0
              Behavior on opacity {
                NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") }
              }

              VIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "image"
                size: root.wp.emptyIcon
                color: Theme.r.popover.inkSecondary
              }
              VText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "No Pictures Yet"
                font.pixelSize: Theme.m.type.title
                font.weight: Font.DemiBold
              }
              VText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Put pictures in " + root.folderLabel + "."
                tone: "secondary"
              }
            }
          }

          // ---- foot (a sheet's footer, as on macOS): the global switch with what it means, Done
          Item {
            width: parent.width
            height: Math.max(footText.implicitHeight, doneButton.implicitHeight) + Theme.layout.sheet.gap

            Rectangle {   // one device pixel between the grid and the footer
              width: parent.width
              height: 1 / Screen.devicePixelRatio
              color: Theme.r.popover.line
            }

            VSwitch {
              id: globalSwitch
              x: card.ring
              anchors.verticalCenter: footText.verticalCenter
              checked: root.globalMode
              onToggled: function(on) {
                root.setGlobal(on);
                checked = Qt.binding(function() { return root.globalMode; });
              }
            }

            Column {
              id: footText
              anchors.left: globalSwitch.right
              anchors.leftMargin: Theme.layout.list.gap
              anchors.right: doneButton.left
              anchors.rightMargin: Theme.layout.list.padX
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Math.max(0, (doneButton.implicitHeight - implicitHeight) / 2)

              VText { text: "Use for All Themes" }
              VCrossfadeText {
                width: parent.width
                elide: Text.ElideRight
                text: root.globalMode
                  ? "Theme changes keep this picture."
                  : "Off: every theme brings its own background."
                tone: "secondary"
                pixelSize: Theme.m.type.small
              }
            }

            VButton {
              id: doneButton
              anchors.right: parent.right
              anchors.rightMargin: card.ring
              anchors.bottom: parent.bottom
              kind: "primary"
              text: "Done"
              onClicked: root.close()
            }
          }
        }
      }
    }
  }
}
