import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "file:///home/henri/.local/share/velum/qml/Velum"

// The small bar on the active window where fingers work, as iPadOS's multitasking control: close and
// fullscreen, floating at the window's top centre on the popover material. It shows on every screen
// in tablet mode, and on the cast screen (the tablet showing the Mac, $XDG_RUNTIME_DIR/ipadcast/
// touch-output) otherwise. Over a fullscreen window too (overlay layer); the bar only takes input on
// its own card. Geometry: surface.tablet.windowBar.
Item {
  id: wbar

  property bool tabletMode: false
  property var dispatch: null              // Tablet.qml's dispatch(luaExpr, legacy)

  readonly property var wb: Theme.core.surface.tablet.windowBar
  readonly property var shadow: Theme.r.popover.shadow
  // room for the whole shadow around the card (VShadow draws outside it)
  readonly property real room: shadowRoom(shadow)
  function shadowRoom(layers) {
    var r = 0
    for (var i = 0; i < (layers || []).length; i++) r = Math.max(r, layers[i].blur + Math.abs(layers[i].offsetY) + (layers[i].spread || 0))
    return Math.ceil(r)
  }

  // ---- the cast screen
  property string castScreen: ""
  FileView {
    id: castFile
    property bool missing: true
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/ipadcast/touch-output"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { wbar.castScreen = String(text() || "").trim(); missing = false }
    onLoadFailed: { wbar.castScreen = ""; missing = true }
  }
  // a watch can't see a file that does not exist yet: look again now and then
  Timer { interval: Theme.delay("hudHold"); repeat: true; running: castFile.missing; onTriggered: castFile.reload() }

  // ---- the active window, as Hyprland last reported it
  readonly property var win: Hyprland.activeToplevel
  readonly property var ipc: win ? win.lastIpcObject : null
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = event.name
      if (n === "activewindowv2" || n === "movewindowv2" || n === "openwindow" || n === "closewindow"
          || n === "fullscreen" || n === "changefloatingmode" || n === "workspacev2" || n === "focusedmonv2")
        refresh.restart()
    }
  }
  // the size settles a moment after the event (layout, the app's own resize)
  Timer { id: refresh; interval: Theme.delay("settle"); onTriggered: Hyprland.refreshToplevels() }
  // a window resized by hand sends no event: look again while a bar shows
  Timer { interval: Theme.delay("hudHold"); repeat: true; running: wbar.ipc !== null; onTriggered: Hyprland.refreshToplevels() }

  function shownOn(screen) {
    if (!screen || !ipc || !ipc.at || !ipc.size || ipc.mapped === false) return false
    if (!(tabletMode || (castScreen !== "" && screen.name === castScreen))) return false
    if (ipc.workspace && String(ipc.workspace.name).indexOf("special:") === 0) return false
    var m = Hyprland.monitorFor(screen)
    return !!m && ipc.monitor === m.id
  }

  function close() { if (win && win.wayland) win.wayland.close() }
  function fullscreen() {
    if (dispatch) dispatch("hl.dsp.window.fullscreen({ mode = \"fullscreen\" })", "fullscreen 0")
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: pw
      required property var modelData
      screen: modelData
      readonly property bool on: wbar.shownOn(modelData)
      visible: on || fade.running
      anchors { top: true; left: true }
      exclusionMode: ExclusionMode.Ignore
      implicitWidth: card.width + 2 * wbar.room
      implicitHeight: card.height + 2 * wbar.room
      // the card's centre on the window's top centre, just below its edge
      // (the last place stays while it fades out)
      readonly property real wantLeft: on ? Math.round(wbar.ipc.at[0] - modelData.x + wbar.ipc.size[0] / 2 - implicitWidth / 2) : NaN
      readonly property real wantTop: on ? Math.round(wbar.ipc.at[1] - modelData.y + wbar.wb.top - wbar.room) : NaN
      property real lastLeft: 0
      property real lastTop: 0
      onWantLeftChanged: if (!isNaN(wantLeft)) lastLeft = wantLeft
      onWantTopChanged: if (!isNaN(wantTop)) lastTop = wantTop
      margins.left: isNaN(wantLeft) ? lastLeft : wantLeft
      margins.top: isNaN(wantTop) ? lastTop : wantTop
      color: "transparent"
      WlrLayershell.namespace: "velum-surface"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region { item: card }

      Item {
        id: card
        x: wbar.room
        y: wbar.room
        width: 2 * wbar.wb.button + 2 * wbar.wb.pad
        height: wbar.wb.height
        opacity: pw.on ? 1 : 0
        Behavior on opacity { NumberAnimation { id: fade; duration: pw.on ? Theme.dur("fast") : Theme.exit(Theme.dur("fast")) } }

        VShadow { layers: wbar.shadow; radius: Theme.m.radius.control + wbar.wb.pad }
        Rectangle {
          anchors.fill: parent
          radius: Theme.m.radius.control + wbar.wb.pad
          color: Theme.reduceTransparency ? Theme.r.popover.bgOpaque : Theme.r.popover.bg
          border.width: 1 / Screen.devicePixelRatio
          border.color: Theme.r.line.rim
        }
        Row {
          x: wbar.wb.pad
          y: wbar.wb.pad
          VPressable {
            id: closeButton
            width: wbar.wb.button
            height: wbar.wb.height - 2 * wbar.wb.pad
            onClicked: wbar.close()
            VIcon { anchors.centerIn: parent; name: "close"; weight: "bold"; size: wbar.wb.icon; color: closeButton.contentColor }
          }
          VPressable {
            id: fullButton
            width: wbar.wb.button
            height: wbar.wb.height - 2 * wbar.wb.pad
            onClicked: wbar.fullscreen()
            VIcon {
              anchors.centerIn: parent
              name: wbar.ipc && wbar.ipc.fullscreen === 2 ? "fullscreen.exit" : "fullscreen"
              weight: "bold"; size: wbar.wb.icon; color: fullButton.contentColor
            }
          }
        }
      }
    }
  }
}
