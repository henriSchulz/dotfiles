import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "file:///home/henri/.local/share/velum/qml/Velum"

// The bar above the home indicator where fingers work: the active app's icon and name, then Search
// (Spotlight), Dictate, Keyboard, Full Screen and Close — each a symbol with its name under it, a
// finger's size (concept A · Morph of lab/web/typing.html, Henri 2026-11-12: the 30 px bar was too
// small) — on the popover material. Keyboard turns the bar into the on-screen keyboard: the plate goes
// at once and henri.keyboard-v3 draws it on, growing into its toolbar ("velum-keyboard morph SCREEN X Y
// W H"); while the keyboard is up a tap on the indicator puts it away instead of opening the bar. Dictation (voxtype) ends with the next tap anywhere on that screen: a clear surface
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
  // Quickshell names the active window only after a focus event: until then the focused workspace's
  // last window stands in (a shell start, the first tap)
  readonly property var win: Hyprland.activeToplevel || fallbackWin
  property var fallbackWin: null
  function findFallback() {
    var ws = Hyprland.focusedWorkspace, o = ws ? ws.lastIpcObject : null
    var a = o && o.lastwindow ? String(o.lastwindow).replace(/^0x/, "") : ""
    var tl = Hyprland.toplevels.values
    for (var i = 0; a !== "" && i < tl.length; i++)
      if (String(tl[i].address).replace(/^0x/, "") === a) { fallbackWin = tl[i]; return }
  }
  readonly property var ipc: win ? win.lastIpcObject : null
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = event.name
      if (n === "custom") {
        var d = String(event.data)
        if (d.indexOf("velum-keyboard shown ") === 0) wbar.keyboardOn = d.slice(21).trim()
        else if (d.indexOf("velum-keyboard hidden ") === 0 && wbar.keyboardOn === d.slice(22).trim()) wbar.keyboardOn = ""
        return
      }
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
  onOpenChanged: { armed = false; if (open) { instantFold = false; hold.restart(); arm.restart() } else hold.stop() }
  Timer { id: hold; interval: wbar.wb.hold; onTriggered: wbar.openOn = "" }
  // the bar opens right above the finger that tapped the indicator: a second tap of a double tap
  // must not close the app, so the bar's buttons wait a moment before they act
  property bool armed: false
  Timer { id: arm; interval: Theme.delay("repeat"); onTriggered: wbar.armed = true }

  // a tap on the home indicator of that screen (Tablet.qml); while the keyboard is up there it goes
  function toggle(screenName) {
    if (keyboardOn === screenName) { openOn = ""; keyboard(screenName); return }
    if (openOn === screenName) { openOn = ""; return }
    // after a shell start Quickshell names no active window until the focus moves: ask Hyprland, then again
    if (!ipc) { Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces(); retry.screenName = screenName; retry.left = 5; retry.restart(); return }
    openFor(screenName)
  }
  function openFor(screenName) {
    var all = Quickshell.screens
    for (var i = 0; i < all.length; i++)
      if (all[i].name === screenName && shownOn(all[i]) && !VOverlays.covered(screenName)) { openOn = screenName; return }
  }

  Timer {
    id: retry
    property string screenName: ""
    property int left: 0
    interval: Theme.delay("settle")
    onTriggered: {
      if (!wbar.ipc) wbar.findFallback()
      if (!wbar.ipc && --left > 0) { Hyprland.refreshToplevels(); Hyprland.refreshWorkspaces(); restart(); return }
      wbar.openFor(screenName)
    }
  }
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
  // the bar's Keyboard button: the keyboard grows out of the plate at r ({ x, y, w, h } in screen px)
  function morphKeyboard(screenName, r) {
    if (!dispatch) return
    var e = "velum-keyboard morph " + screenName + " " + [r.x, r.y, r.w, r.h].map(Math.round).join(" ")
    dispatch("hl.dsp.event(\"" + e + "\")", "event " + e)
  }
  // where the keyboard is up ("velum-keyboard shown|hidden SCREEN" from henri.keyboard-v3)
  property string keyboardOn: ""
  // the plate leaves without its fade when it turns into the keyboard
  property bool instantFold: false
  // Spotlight (henri.menu-v3). The keyboard never comes by itself, only from its own button (Henri 2026-11-12)
  function search(screenName) {
    if (!dispatch) return
    dispatch("hl.dsp.event(\"menu summon root\")", "event menu summon root")
  }

  // ---- dictation: voxtype records until the next tap on this screen, then types what it heard
  property string dictateOn: ""             // the screen a dictation runs on ("" = none of ours)
  property string voxState: ""              // voxtype's alt: idle | recording | transcribing
  property bool heard: false                // voxtype said recording since we started it
  property bool following: false            // watching voxtype until it is idle again (outlives the surface)
  // the rig never touches the real microphone or types into the live session: a stub stands in
  readonly property string voxtype: Quickshell.env("VELUM_SHELL_RIG") ? Qt.resolvedUrl("tests/voxtype-stub").toString().replace(/^[a-z]+:\/\//, "") : "voxtype"
  // dictated into a terminal: Enter once the text is in, so it goes off at once (Henri 2026-10-26)
  readonly property var enterClasses: ["foot", "footclient"]
  property string enterFor: ""              // the terminal window's address, "" = no Enter
  function dictate(screenName) {
    dictateOn = screenName; heard = false; voxState = ""; following = true
    enterFor = ipc && enterClasses.indexOf(String(ipc.class)) >= 0 ? String(ipc.address) : ""
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
    running: wbar.following
    command: [wbar.voxtype, "status", "--follow", "--format", "json"]
    stdout: SplitParser {
      onRead: function (line) {
        var o = null
        try { o = JSON.parse(line) } catch (e) { return }
        wbar.voxState = String(o.alt || "")
        if (wbar.voxState === "recording") wbar.heard = true
        else if (wbar.heard && wbar.voxState === "idle") { wbar.dictateOn = ""; wbar.following = false; if (wbar.enterFor !== "") enterLater.restart() }
      }
    }
  }
  // voxtype says idle once it pasted the text; Enter a moment later, only into that same terminal
  Timer {
    id: enterLater
    interval: Theme.delay("settle")
    onTriggered: {
      var to = wbar.enterFor
      wbar.enterFor = ""
      Hyprland.refreshToplevels()
      if (!wbar.ipc || String(wbar.ipc.address) !== to) return
      // the way voxtype pasted it (wtype, a virtual keyboard to the focused window); Hyprland's
      // send_key_state never reached foot (Henri's test 2026-10-26)
      Quickshell.execDetached(["wtype", "-k", "Return"])
      wbar.entered++
    }
  }
  property int entered: 0                   // for tests: how many Enters went out

  // voxtype never started recording (no daemon): do not leave a surface that eats taps
  Timer { id: dictateCheck; interval: Theme.delay("hudHold") * 2; onTriggered: if (!wbar.heard) { wbar.dictateOn = ""; wbar.following = false; wbar.enterFor = "" } }

  function fullscreen() {
    if (dispatch) dispatch("hl.dsp.window.fullscreen({ mode = \"fullscreen\" })", "fullscreen 0")
  }

  // the app's icon from its desktop entry, else its class
  readonly property string appIcon: {
    if (!ipc) return ""
    var c = String(ipc.class || ""), e = null
    try { e = DesktopEntries.byId(c) || DesktopEntries.heuristicLookup(c) } catch (err) {}
    return Quickshell.iconPath(e && e.icon ? e.icon : c, true) || ""
  }

  // the popover material the bar stands on; its corner is concentric with the buttons'
  component Plate: Item {
    property string velumSurface: "popover"
    height: wbar.wb.height
    VShadow { layers: wbar.shadow; radius: wbar.wb.buttonRadius + wbar.wb.pad }
    Rectangle {
      anchors.fill: parent
      radius: wbar.wb.buttonRadius + wbar.wb.pad
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
      // a surface covered the screen: fold, after this binding has settled (else a binding loop on "on")
      onOnChanged: if (!on) Qt.callLater(function () { if (!pw.on && wbar.openOn === pw.modelData.name) wbar.openOn = "" })
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
        Behavior on opacity { NumberAnimation { id: cardFade; duration: wbar.instantFold ? 0 : pw.on ? Theme.transitionMs("barPopup.in") : Theme.exit(Theme.transitionMs("barPopup.in")) } }
        Behavior on scale {
          NumberAnimation {
            duration: wbar.instantFold ? 0 : pw.on ? Theme.transitionMs("barPopup.in") : Theme.exit(Theme.transitionMs("barPopup.in"))
            easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.motion("barPopup.in").curve
          }
        }
        Row {
          id: row
          x: wbar.wb.pad
          y: wbar.wb.pad
          height: wbar.wb.height - 2 * wbar.wb.pad
          // the app: its icon and name
          Row {
            id: name
            visible: label.text !== ""
            height: parent.height
            leftPadding: wbar.wb.namePad
            rightPadding: wbar.wb.namePad
            spacing: Theme.layout.control.gap
            Image {
              anchors.verticalCenter: parent.verticalCenter
              visible: wbar.appIcon !== ""
              source: wbar.appIcon
              width: wbar.wb.nameIcon
              height: wbar.wb.nameIcon
              sourceSize.width: wbar.wb.nameIcon * Screen.devicePixelRatio
              sourceSize.height: wbar.wb.nameIcon * Screen.devicePixelRatio
              smooth: true
            }
            VText {
              id: label
              anchors.verticalCenter: parent.verticalCenter
              text: wbar.appName
              font.pixelSize: wbar.wb.nameSize
              font.weight: Font.DemiBold
              width: Math.min(implicitWidth, wbar.wb.label)
              elide: Text.ElideRight
            }
          }
          Rectangle {
            visible: name.visible
            width: 1 / Screen.devicePixelRatio
            height: wbar.wb.icon
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.r.popover.line
          }
          Repeater {
            model: [
              { a: "search", icon: "search", text: "Search" },
              { a: "dictate", icon: "mic", text: "Dictate" },
              { a: "keyboard", icon: "keyboard", text: "Keyboard" },
              { a: "full", icon: wbar.ipc && wbar.ipc.fullscreen === 2 ? "fullscreen.exit" : "fullscreen", text: wbar.ipc && wbar.ipc.fullscreen === 2 ? "Exit Full" : "Full Screen" },
              { a: "close", icon: "close", text: "Close", danger: true }
            ]
            VPressable {
              id: button
              required property var modelData
              objectName: "windowBar:" + modelData.a
              width: wbar.wb.button
              height: row.height
              radius: wbar.wb.buttonRadius
              onClicked: if (wbar.armed) pw.act(modelData.a)
              Column {
                anchors.centerIn: parent
                VIcon {
                  anchors.horizontalCenter: parent.horizontalCenter
                  name: button.modelData.icon
                  size: wbar.wb.icon
                  color: button.modelData.danger ? Theme.r.danger : button.contentColor
                }
                VText {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: button.modelData.text
                  font.pixelSize: wbar.wb.buttonLabel
                  font.weight: Font.Medium
                  color: Theme.r.popover.inkSecondary
                }
              }
            }
          }
        }
      }

      // a button of the bar; Keyboard hands the plate over to the keyboard, which grows it into its toolbar
      function act(a) {
        var n = pw.modelData.name
        if (a === "keyboard") {
          if (wbar.keyboardOn === n) { wbar.keyboard(n); wbar.openOn = ""; return }
          var lx = (pw.modelData.width - pw.implicitWidth) / 2 + card.x
          var ly = pw.modelData.height - pw.margins.bottom - pw.implicitHeight + card.y
          wbar.morphKeyboard(n, { x: lx, y: ly, w: card.width, h: card.height })
          wbar.instantFold = true
          wbar.openOn = ""
          return
        }
        if (a === "search") wbar.search(n)
        else if (a === "dictate") wbar.dictate(n)
        else if (a === "full") wbar.fullscreen()
        else if (a === "close") wbar.close()
        wbar.openOn = ""
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
