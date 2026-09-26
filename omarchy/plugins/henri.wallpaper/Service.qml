// Wallpaper -- macOS-style picker for a global desktop wallpaper.
//
// Shows the images in ~/Pictures/Wallpaper as a grid of thumbnails. A click
// sets the wallpaper right away (the panel stays open to try the next one),
// Enter sets it and closes. The chosen image is kept for every theme:
// `henri-wallpaper set` records it in ~/.config/omarchy/global-wallpaper, and
// henri.background (the cloned background renderer) then only recolors on a
// theme change. The toggle at the bottom hands the background back to the
// theme.
//
// Open with `omarchy-shell wallpaper toggle` (SUPER+CTRL+SPACE, or a double
// click on the desktop).

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string bin: home + "/.local/bin/henri-wallpaper"
  readonly property string folder: home + "/Pictures/Wallpaper"
  readonly property string folderLabel: "~/Pictures/Wallpaper"
  readonly property string backgroundLink: home + "/.local/state/omarchy/current/background"

  property bool opened: false
  // Monitor the panel opened on; it stays there even if focus moves.
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

  readonly property int columns: 4

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

  // `henri-wallpaper theme` swaps the link asynchronously; read it back after.
  Timer {
    id: themeLinkDelay
    interval: Motion.slow
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

      visible: here && (root.opened || reveal.shown)
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "henri-wallpaper"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: root.opened && here ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

      // Light dim behind the panel, like a sheet.
      Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.18)
        opacity: root.opened ? 1 : 0
        Behavior on opacity {
          NumberAnimation {
            duration: root.opened ? Motion.slow : Motion.exit(Motion.slow)
            easing.type: Easing.BezierSpline
            easing.bezierCurve: root.opened ? Motion.easeOut : Motion.easeExit
          }
        }
      }

      HUi.Reveal {
        id: reveal
        kind: "panel"
        origin: Item.Center
        open: root.opened && win.here
        onDismissRequested: root.close()
        anchors.centerIn: parent
        width: card.implicitWidth
        height: card.implicitHeight

        HUi.Surface {
          id: card
          anchors.fill: parent
          role: "popups"
          kind: "panel"
          padding: Style.space(20)

          readonly property real ring: Style.space(4)
          readonly property real tileW: Style.space(168)
          readonly property real tileH: Math.round(tileW * 10 / 16)
          readonly property real gap: Style.space(12)
          readonly property int rows: Math.max(1, Math.ceil(root.images.length / root.columns))
          readonly property real gridW: root.columns * tileW + (root.columns - 1) * gap
          readonly property real gridH: rows * tileH + (rows - 1) * gap
          readonly property real viewH: root.images.length === 0
            ? tileH * 1.6
            : Math.min(gridH, 3 * tileH + 2.5 * gap) + ring * 2

          implicitWidth: gridW + ring * 2 + contentLeftInset + contentRightInset
          implicitHeight: body.implicitHeight + contentTopInset + contentBottomInset

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

          Column {
            id: body
            x: card.contentLeftInset
            y: card.contentTopInset
            width: card.width - card.contentLeftInset - card.contentRightInset
            spacing: Style.space(16)

            // Header: title, folder, "open folder".
            Item {
              width: parent.width
              height: Math.max(titles.implicitHeight, folderButton.implicitHeight)

              Column {
                id: titles
                x: card.ring
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  text: "Hintergrundbild"
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.heading
                  font.weight: Font.DemiBold
                }
                HUi.CrossfadeText {
                  text: root.folderLabel + (root.loaded
                    ? "  ·  " + root.images.length + (root.images.length === 1 ? " Bild" : " Bilder")
                    : "")
                  color: Util.alpha(Color.foreground, Motion.secondaryTextAlpha)
                  fontSize: Style.font.bodySmall
                  fontFamily: Style.font.family
                }
              }

              HUi.Button {
                id: folderButton
                anchors.right: parent.right
                anchors.rightMargin: card.ring
                anchors.verticalCenter: parent.verticalCenter
                icon: "󰉋"
                text: "Ordner öffnen"
                onClicked: root.openFolder()
              }
            }

            // Grid of thumbnails.
            Flickable {
              id: flick
              width: parent.width
              height: card.viewH
              clip: true
              contentWidth: width
              contentHeight: grid.height + card.ring * 2
              interactive: contentHeight > height
              boundsBehavior: Flickable.DragAndOvershootBounds
              flickDeceleration: Motion.flickDeceleration
              maximumFlickVelocity: Motion.maximumFlickVelocity

              Behavior on contentY {
                enabled: root.keyboardNav
                NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
              }

              function reveal(index) {
                const row = Math.floor(index / root.columns);
                const top = row * (card.tileH + card.gap);
                const bottom = top + card.tileH + card.ring * 2;
                if (top < contentY)
                  contentY = top;
                else if (bottom > contentY + height)
                  contentY = bottom - height;
              }

              Connections {
                target: root
                function onCursorChanged() { if (root.keyboardNav) flick.reveal(root.cursor) }
              }

              Grid {
                id: grid
                x: card.ring
                y: card.ring
                columns: root.columns
                spacing: card.gap

                Repeater {
                  model: root.images

                  HUi.StaggerIn {
                    id: cell
                    required property var modelData
                    required property int index
                    width: card.tileW
                    height: card.tileH
                    active: reveal.open
                    index: cell.index

                    readonly property bool current: cell.modelData.path === root.displayed
                    readonly property bool cursorHere: root.keyboardNav && root.cursor === cell.index

                    // Selection ring: the image on screen.
                    Rectangle {
                      anchors.fill: parent
                      anchors.margins: -card.ring + Style.space(1)
                      radius: tile.radius + card.ring - Style.space(1)
                      color: "transparent"
                      border.width: Style.space(3)
                      border.color: Color.accent
                      opacity: cell.current ? 1 : cell.cursorHere ? 0.45 : 0
                      Behavior on opacity {
                        NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
                      }
                    }

                    HUi.Pressable {
                      id: tile
                      anchors.fill: parent
                      showFill: false
                      activeFocusOnTab: false
                      radius: Style.space(Motion.radiusControl)
                      Accessible.name: cell.modelData.path.split("/").pop()
                      onClicked: {
                        root.keyboardNav = false;
                        root.cursor = cell.index;
                        root.apply(cell.modelData.path, false);
                      }

                      ClippingRectangle {
                        anchors.fill: parent
                        radius: tile.radius
                        color: Util.alpha(Color.foreground, Motion.hoverAlpha)

                        Image {
                          id: thumb
                          anchors.fill: parent
                          source: Util.fileUrl(cell.modelData.thumb)
                          sourceSize.width: Math.ceil(card.tileW * 2)
                          fillMode: Image.PreserveAspectCrop
                          asynchronous: true
                          cache: true
                          smooth: true
                          opacity: status === Image.Ready ? 1 : 0
                          Behavior on opacity {
                            NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
                          }
                        }

                        // Hover/press veil over the photo.
                        Rectangle {
                          anchors.fill: parent
                          color: Util.alpha(Color.foreground,
                            tile.pressed ? Motion.pressedAlpha : tile.hovered ? Motion.hoverAlpha : 0)
                          Behavior on color {
                            ColorAnimation {
                              duration: (tile.hovered || tile.pressed) ? Motion.instant : Motion.fast
                              easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
                            }
                          }
                        }
                      }

                      // Check badge on the image on screen.
                      Rectangle {
                        id: badge
                        width: Style.space(20)
                        height: width
                        radius: width / 2
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Style.space(6)
                        color: Color.accent
                        border.width: Style.space(1.5)
                        border.color: Motion.onColor(Color.accent)
                        opacity: cell.current ? 1 : 0
                        scale: Motion.reduceMotion ? 1 : badgeScale.value
                        Behavior on opacity {
                          NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
                        }

                        Text {
                          anchors.centerIn: parent
                          text: "󰄬"
                          color: Motion.onColor(Color.accent)
                          font.family: Style.font.family
                          font.pixelSize: Style.font.bodySmall
                        }
                      }
                      HUi.SpringValue { id: badgeScale; preset: Motion.snappy; to: cell.current ? 1 : 0.8 }
                    }
                  }
                }
              }

              // Empty folder.
              Column {
                anchors.centerIn: parent
                spacing: Style.space(6)
                opacity: root.loaded && root.images.length === 0 ? 1 : 0
                visible: opacity > 0
                Behavior on opacity {
                  NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "󰸉"
                  color: Util.alpha(Color.foreground, Motion.secondaryTextAlpha)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.displayLarge
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Noch keine Bilder"
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.weight: Font.DemiBold
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: "Lege Bilder in " + root.folderLabel + " ab."
                  color: Util.alpha(Color.foreground, Motion.secondaryTextAlpha)
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }
            }

            // Hairline between grid and footer.
            Rectangle {
              width: parent.width
              height: Style.spacing.hairline
              color: Util.alpha(Color.foreground, Motion.hairlineAlpha)
            }

            // Footer: global toggle, done.
            Item {
              width: parent.width
              height: Math.max(footerText.implicitHeight, doneButton.implicitHeight)

              HUi.Toggle {
                id: globalToggle
                x: card.ring
                anchors.verticalCenter: parent.verticalCenter
                checked: root.globalMode
                onToggled: function(on) {
                  root.setGlobal(on);
                  checked = Qt.binding(function() { return root.globalMode; });
                }
              }

              Column {
                id: footerText
                anchors.left: globalToggle.right
                anchors.leftMargin: Style.space(10)
                anchors.right: doneButton.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  text: "Für alle Themes verwenden"
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                HUi.CrossfadeText {
                  width: parent.width
                  text: root.globalMode
                    ? "Theme-Wechsel behalten dieses Bild."
                    : "Aus: Jedes Theme bringt seinen eigenen Hintergrund mit."
                  color: Util.alpha(Color.foreground, Motion.secondaryTextAlpha)
                  fontSize: Style.font.bodySmall
                  fontFamily: Style.font.family
                }
              }

              HUi.Button {
                id: doneButton
                anchors.right: parent.right
                anchors.rightMargin: card.ring
                anchors.verticalCenter: parent.verticalCenter
                text: "Fertig"
                prominent: true
                onClicked: root.close()
              }
            }
          }
        }
      }
    }
  }
}
