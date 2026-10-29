// Wallpaper -- macOS-style picker for a global desktop wallpaper (v3, Velum).
//
// Shows the images in ~/Pictures/Wallpaper as a grid of thumbnails. A click
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
  readonly property string folder: home + "/Pictures/Wallpaper"
  readonly property string folderLabel: "~/Pictures/Wallpaper"

  readonly property var wp: Theme.core.surface.wallpaper

  property bool opened: false
  // Monitor the card opened on; it stays there even if focus moves.
  property string screenName: ""
  // [{ path, thumb }] in folder order.
  property var images: []
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

  function moveCursor(delta) {
    const n = root.images.length;
    if (n === 0)
      return;
    root.keyboardNav = true;
    root.cursor = Math.max(0, Math.min(n - 1, root.cursor + delta));
  }

  IpcHandler {
    target: "wallpaper"

    function toggle(): string { return root.toggle() }
    function open(): string { return root.open() }
    function close(): string { return root.close() }
    function set(path: string): string { root.apply(path, false); return "ok" }
    // the rig only (VELUM_SHELL_RIG): slow every Velum motion down to look at it frame by frame
    function rigSpeed(factor: string): string {
      if (!Quickshell.env("VELUM_SHELL_RIG")) return "rig only";
      Theme.speed = Math.max(1, Number(factor) || 1);
      return "speed " + Theme.speed;
    }
    function status(): string {
      return JSON.stringify({ opened: root.opened, screen: root.screenName, images: root.images.length,
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
        const out = [];
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
          const parts = lines[i].split("\t");
          if (parts.length === 2 && parts[0])
            out.push({ path: parts[0], thumb: parts[1] });
        }
        root.images = out;
        root.loaded = true;
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
          case Qt.Key_Up: root.moveCursor(-root.columns); break;
          case Qt.Key_Down: root.moveCursor(root.columns); break;
          case Qt.Key_Home: root.moveCursor(-root.images.length); break;
          case Qt.Key_End: root.moveCursor(root.images.length); break;
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

        // the grid: whole thumbnails, the ring's room around them
        readonly property real ring: root.wp.ring
        readonly property real tileW: root.wp.tile
        readonly property real tileH: Math.round(root.wp.tile * root.wp.tileAspect)
        readonly property real gap: root.wp.gap
        readonly property int rows: Math.max(1, Math.ceil(root.images.length / root.columns))
        readonly property real gridW: root.columns * tileW + (root.columns - 1) * gap
        readonly property real gridH: rows * tileH + (rows - 1) * gap
        readonly property real viewH: root.images.length === 0
          ? tileH * root.wp.empty
          : Math.min(gridH, root.wp.rows * tileH + (root.wp.rows - 1) * gap + gap / 2) + 2 * ring

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
            contentHeight: grid.height + 2 * card.ring
            interactive: contentHeight > height
            boundsBehavior: Flickable.DragAndOvershootBounds
            flickDeceleration: root.wp.flickDeceleration
            maximumFlickVelocity: root.wp.maxFlickVelocity

            // the keyboard cursor scrolls the grid along (a visible thing moves A → B)
            Behavior on contentY {
              enabled: root.keyboardNav
              NumberAnimation { duration: Theme.move(Theme.dur("base")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") }
            }

            function reveal(index) {
              const row = Math.floor(index / root.columns);
              const top = row * (card.tileH + card.gap);
              const bottom = top + card.tileH + 2 * card.ring;
              if (top < contentY)
                contentY = top;
              else if (bottom > contentY + height)
                contentY = bottom - height;
            }

            Connections {
              target: root
              function onCursorChanged() { if (root.keyboardNav) flick.reveal(root.cursor) }
              // the picture on screen is in view when the card opens (it jumps there, nothing scrolls)
              function onOpenedChanged() { if (root.opened) flick.showCurrent() }
              function onImagesChanged() { if (root.opened && !root.keyboardNav) flick.showCurrent() }
            }
            function showCurrent() {
              const i = root.indexOfPath(root.displayed);
              if (i >= 0) reveal(i);
            }

            Grid {
              id: grid
              x: card.ring
              y: card.ring
              columns: root.columns
              spacing: card.gap

              Repeater {
                model: root.images

                Item {
                  id: cell
                  required property var modelData
                  required property int index
                  width: card.tileW
                  height: card.tileH

                  readonly property bool current: cell.modelData.path === root.displayed
                  readonly property bool cursorHere: root.keyboardNav && root.cursor === cell.index

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
                      root.cursor = cell.index;
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
