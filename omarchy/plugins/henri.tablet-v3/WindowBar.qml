import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "file:///home/henri/.local/share/velum/qml/Velum"

// The small bar above the home indicator where fingers work: the active app's name, Spotlight (with
// the on-screen keyboard), dictation, the on-screen keyboard, fullscreen and close, on the popover
// material. Dictation (voxtype) ends with the next tap anywhere on that screen: a clear surface
// over it takes that tap while recording (Henri 2026-10-26). A tap on the indicator opens it
// (Gesture.js "tap"); nothing sits on the window itself (Henri 2026-10-26: a handle in the window's
// corner lay over apps' own buttons; design 7 of lab/web/window-bar.html). It folds back after
// surface.tablet.windowBar.hold, a button used, another tap on the indicator or another window.
// In tablet mode on every screen, otherwise on the cast screen (the tablet showing the Mac,
// $XDG_RUNTIME_DIR/ipadcast/touch-output), where Tablet.qml shows the indicator for it.
// Over a fullscreen window too (overlay layer); the bar only takes input on its own card.
// Geometry: surface.tablet.windowBar.
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
    if (!m || ipc.monitor !== m.id) return false
    // on an empty workspace Hyprland names no active window, but activeToplevel keeps the last one:
    // it must stand on the workspace the screen shows
    return !m.activeWorkspace || !ipc.workspace || ipc.workspace.id === m.activeWorkspace.id
  }

  // the screen whose bar is open ("" = none); only the active window has one
  property string openOn: ""
  readonly property bool open: openOn !== ""
  onWinChanged: openOn = ""
  onOpenChanged: { armed = false; if (open) { hold.restart(); arm.restart() } else hold.stop() }
  Timer { id: hold; interval: wbar.wb.hold; onTriggered: wbar.openOn = "" }
  // the bar opens right above the finger that tapped the indicator: a second tap of a double tap
  // must not close the app, so the bar's buttons wait a moment before they act
  property bool armed: false
  Timer { id: arm; interval: Theme.delay("repeat"); onTriggered: wbar.armed = true }

  // a tap on the home indicator of that screen (Tablet.qml)
  function toggle(screenName) {
    if (openOn === screenName) { openOn = ""; return }
    // after a shell start Quickshell names no active window until the focus moves: ask Hyprland, then again
    if (!ipc) { Hyprland.refreshToplevels(); retry.screenName = screenName; retry.restart(); return }
    openFor(screenName)
  }
  function openFor(screenName) {
    var all = Quickshell.screens
    for (var i = 0; i < all.length; i++)
      if (all[i].name === screenName && shownOn(all[i]) && !VOverlays.covered(screenName)) { openOn = screenName; return }
  }

  Timer { id: retry; property string screenName: ""; interval: Theme.delay("settle"); onTriggered: wbar.openFor(screenName) }
  Component.onCompleted: Hyprland.refreshToplevels()

  // the app's name as its desktop entry has it, else its class
  readonly property string appName: {
    if (!ipc) return ""
    var c = String(ipc.class || ""), e = null
    try { e = DesktopEntries.byId(c) || DesktopEntries.heuristicLookup(c) } catch (err) {}
    return e && e.name ? e.name : c
  }

  function close() { if (win && win.wayland) win.wayland.close() }
  // henri.keyboard-v3 opens / closes on this event, on that screen
  function keyboard(screenName) {
    if (dispatch) dispatch("hl.dsp.event(\"velum-keyboard toggle " + screenName + "\")", "event velum-keyboard toggle " + screenName)
  }
  // Spotlight, with the keyboard to type into it (henri.menu-v3, henri.keyboard-v3)
  function search(screenName) {
    if (!dispatch) return
    dispatch("hl.dsp.event(\"menu summon root\")", "event menu summon root")
    dispatch("hl.dsp.event(\"velum-keyboard open " + screenName + "\")", "event velum-keyboard open " + screenName)
  }

  // ---- dictation: voxtype records until the next tap on this screen, then types what it heard
  property string dictateOn: ""             // the screen a dictation runs on ("" = none of ours)
  property string voxState: ""              // voxtype's alt: idle | recording | transcribing
  property bool heard: false                // voxtype said recording since we started it
  // the rig never touches the real microphone or types into the live session: a stub stands in
  readonly property string voxtype: Quickshell.env("VELUM_SHELL_RIG") ? Qt.resolvedUrl("tests/voxtype-stub").toString().replace(/^[a-z]+:\/\//, "") : "voxtype"
  function dictate(screenName) {
    dictateOn = screenName; heard = false; voxState = ""
    Quickshell.execDetached([voxtype, "record", "start"])
    dictateCheck.restart()
  }
  function stopDictation() {
    if (dictateOn === "") return
    dictateOn = ""
    Quickshell.execDetached([voxtype, "record", "stop"])
  }
  // voxtype's own state: a dictation ended elsewhere (Right Ctrl, its own timeout) lets the surface go
  Process {
    running: wbar.dictateOn !== ""
    command: [wbar.voxtype, "status", "--follow", "--format", "json"]
    stdout: SplitParser {
      onRead: function (line) {
        var o = null
        try { o = JSON.parse(line) } catch (e) { return }
        wbar.voxState = String(o.alt || "")
        if (wbar.voxState === "recording") wbar.heard = true
        else if (wbar.heard && wbar.voxState === "idle") wbar.dictateOn = ""
      }
    }
  }
  // voxtype never started recording (no daemon): do not leave a surface that eats taps
  Timer { id: dictateCheck; interval: Theme.delay("hudHold") * 2; onTriggered: if (!wbar.heard) wbar.dictateOn = "" }

  function fullscreen() {
    if (dispatch) dispatch("hl.dsp.window.fullscreen({ mode = \"fullscreen\" })", "fullscreen 0")
  }

  // the popover material the bar stands on
  component Plate: Item {
    property string velumSurface: "popover"
    height: wbar.wb.height
    VShadow { layers: wbar.shadow; radius: Theme.m.radius.control + wbar.wb.pad }
    Rectangle {
      anchors.fill: parent
      radius: Theme.m.radius.control + wbar.wb.pad
      color: Theme.reduceTransparency ? Theme.r.popover.bgOpaque : Theme.r.popover.bg
      border.width: 1 / Screen.devicePixelRatio
      border.color: Theme.r.line.rim
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: pw
      required property var modelData
      screen: modelData
      // not over an open Control Center, Notification Center or bar menu: same layer, and the later mapped wins
      readonly property bool on: wbar.openOn === modelData.name && wbar.shownOn(modelData) && !VOverlays.covered(modelData.name)
      onOnChanged: if (!on && wbar.openOn === modelData.name) wbar.openOn = ""
      visible: on || cardFade.running
      // centred above the home indicator (anchored to the bottom only)
      anchors { bottom: true }
      exclusionMode: ExclusionMode.Ignore
      margins.bottom: Math.round(Theme.core.surface.tablet.homeZone + wbar.wb.above - wbar.room)
      implicitWidth: card.width + 2 * wbar.room
      implicitHeight: card.height + 2 * wbar.room
      color: "transparent"
      WlrLayershell.namespace: "velum-surface"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region { item: card }

      // grows out of the indicator below it (motion.barPopup: fade, scale from the bottom centre)
      Plate {
        id: card
        x: wbar.room
        y: wbar.room
        width: row.width + 2 * wbar.wb.pad
        opacity: pw.on ? 1 : 0
        scale: pw.on || Theme.reduceMotion ? 1 : Theme.motion("barPopup.fromScale")
        transformOrigin: Item.Bottom
        Behavior on opacity { NumberAnimation { id: cardFade; duration: pw.on ? Theme.transitionMs("barPopup.in") : Theme.exit(Theme.transitionMs("barPopup.in")) } }
        Behavior on scale {
          NumberAnimation {
            duration: pw.on ? Theme.transitionMs("barPopup.in") : Theme.exit(Theme.transitionMs("barPopup.in"))
            easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion("barPopup.in").curve
          }
        }
        Row {
          id: row
          x: wbar.wb.pad
          y: wbar.wb.pad
          VText {
            id: label
            text: wbar.appName
            visible: text !== ""
            font.weight: Font.DemiBold
            width: Math.min(implicitWidth, wbar.wb.label + 2 * Theme.layout.control.padX)
            leftPadding: Theme.layout.control.padX
            rightPadding: Theme.layout.control.padX
            height: wbar.wb.height - 2 * wbar.wb.pad
          }
          Rectangle {
            visible: label.visible
            width: 1 / Screen.devicePixelRatio
            height: wbar.wb.icon
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.r.popover.line
          }
          VPressable {
            id: searchButton
            width: wbar.wb.button
            height: wbar.wb.height - 2 * wbar.wb.pad
            onClicked: if (wbar.armed) { wbar.search(pw.modelData.name); wbar.openOn = "" }
            VIcon { anchors.centerIn: parent; name: "search"; weight: "bold"; size: wbar.wb.icon; color: searchButton.contentColor }
          }
          VPressable {
            id: micButton
            width: wbar.wb.button
            height: wbar.wb.height - 2 * wbar.wb.pad
            onClicked: if (wbar.armed) { wbar.dictate(pw.modelData.name); wbar.openOn = "" }
            VIcon { anchors.centerIn: parent; name: "mic"; weight: "bold"; size: wbar.wb.icon; color: micButton.contentColor }
          }
          VPressable {
            id: keyButton
            width: wbar.wb.button
            height: wbar.wb.height - 2 * wbar.wb.pad
            onClicked: if (wbar.armed) { wbar.keyboard(pw.modelData.name); wbar.openOn = "" }
            VIcon { anchors.centerIn: parent; name: "keyboard"; size: wbar.wb.icon; color: keyButton.contentColor }
          }
          VPressable {
            id: fullButton
            width: wbar.wb.button
            height: wbar.wb.height - 2 * wbar.wb.pad
            onClicked: if (wbar.armed) { wbar.fullscreen(); wbar.openOn = "" }
            VIcon {
              anchors.centerIn: parent
              name: wbar.ipc && wbar.ipc.fullscreen === 2 ? "fullscreen.exit" : "fullscreen"
              weight: "bold"; size: wbar.wb.icon; color: fullButton.contentColor
            }
          }
          VPressable {
            id: closeButton
            width: wbar.wb.button
            height: wbar.wb.height - 2 * wbar.wb.pad
            onClicked: if (wbar.armed) { wbar.close(); wbar.openOn = "" }
            VIcon { anchors.centerIn: parent; name: "close"; weight: "bold"; size: wbar.wb.icon; color: closeButton.contentColor }
          }
        }
      }
    }
  }

  // while a dictation of ours records: a clear surface over its screen, the next tap ends it
  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      visible: wbar.dictateOn === modelData.name
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      WlrLayershell.namespace: "velum-dictation-stop"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      MouseArea { anchors.fill: parent; onPressed: wbar.stopDictation() }
    }
  }
}
