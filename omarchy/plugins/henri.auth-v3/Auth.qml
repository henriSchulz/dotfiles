import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import "file:///home/henri/.local/share/velum/qml/Velum"

// Velum's polkit agent: when anything asks polkit for the password (pkexec, an app's privileged action),
// a card comes out of the top of the focused screen with the lock, polkit's message, the command and the
// password field (macOS's authorization panel, at the top as Henri asked, 2026-10-29). Enter or
// Authenticate answers, Esc or Cancel cancels; a wrong password shakes the field and asks again.
//
// The password goes to polkit's own helper through the AuthFlow (submit), never anywhere else; nothing
// here keeps it after the answer. polkit tells only the program (`/usr/bin/bash`), not its arguments:
// `ask-root 'COMMAND'` (~/.local/bin) notes the command in $XDG_RUNTIME_DIR/velum-auth/request before
// it runs pkexec, and the card shows it when a pkexec request comes within a minute of that note.
//
// One agent per session: a rig shell (VELUM_SHELL_RIG, same login session) never registers; there
// `preview` opens a pretend request ("velum" is its password).
// IPC: omarchy.auth state | preview COMMAND | previewType TEXT | previewSubmit | cancel
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property var au: Theme.core.surface.auth
  readonly property bool inRig: !!Quickshell.env("VELUM_SHELL_RIG")

  Loader { id: agentLoader; active: !root.inRig; sourceComponent: Component { PolkitAgent {} } }
  readonly property var agent: agentLoader.item
  readonly property var flow: root.agent && root.agent.isActive && root.agent.flow ? root.agent.flow
                              : pretend.active ? pretend : null
  readonly property bool showing: !!root.flow && !root.flow.isCompleted

  // ---- the command ask-root noted ---------------------------------------------------------------
  property string command: ""
  FileView {
    id: request
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/velum-auth/request"
    blockLoading: true
    printErrors: false
  }
  function readCommand() {
    root.command = ""
    if (!root.flow) return
    if (root.flow === pretend) { root.command = pretend.cmd; return }
    if (root.flow.actionId !== "org.freedesktop.policykit.exec") return
    request.reload()
    try {
      var o = JSON.parse(request.text())
      if (o && typeof o.cmd === "string" && Date.now() / 1000 - Number(o.t) < 60) root.command = o.cmd
    } catch (e) {}
  }

  // where it shows: the focused screen when the request came
  property string screenName: ""
  property int attempts: 0
  onShowingChanged: {
    if (!root.showing) return
    root.screenName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : (Quickshell.screens[0] ? Quickshell.screens[0].name : "")
    root.attempts = 0
    root.readCommand()
  }
  Connections {
    target: root.flow
    ignoreUnknownSignals: true
    function onAuthenticationFailed() { root.attempts++ }
  }

  function answer(text) {
    if (root.flow && root.flow.isResponseRequired) root.flow.submit(text)
  }
  function cancel() {
    if (root.flow) root.flow.cancelAuthenticationRequest()
  }

  // ---- the rig's pretend request -----------------------------------------------------------------
  QtObject {
    id: pretend
    property bool active: false
    property string cmd: ""
    property string message: "Authentication is needed to run `/usr/bin/bash' as the super user"
    property string actionId: "org.freedesktop.policykit.exec"
    property bool isResponseRequired: true
    property string inputPrompt: "Password: "
    property bool responseVisible: false
    property string supplementaryMessage: ""
    property bool supplementaryIsError: false
    property bool isCompleted: false
    property bool isSuccessful: false
    signal authenticationFailed()
    function submit(v) {
      if (v === "velum") { isSuccessful = true; isCompleted = true; done.restart() }
      else authenticationFailed()
    }
    function cancelAuthenticationRequest() { isCompleted = true; done.restart() }
  }
  Timer { id: done; interval: Theme.dur("base"); onTriggered: pretend.active = false }

  IpcHandler {
    target: "omarchy.auth"
    function state(): string {
      var f = root.flow
      return JSON.stringify({ registered: !!(root.agent && root.agent.isRegistered), showing: root.showing, screen: root.screenName,
                              command: root.command, message: f ? f.message : "", attempts: root.attempts,
                              success: f ? f.isSuccessful : false })
    }
    function preview(command: string): void {
      if (!root.inRig) return
      pretend.cmd = command; pretend.isCompleted = false; pretend.isSuccessful = false; pretend.active = true
    }
    function previewType(text: string): void { if (card.field) card.field.text = text }
    function previewSubmit(): void { if (card.field) card.submit() }
    function cancel(): void { root.cancel() }
  }

  // ---- the card ---------------------------------------------------------------------------------
  QtObject { id: card; property var field: null; property var submitFn: null; function submit() { if (submitFn) submitFn() } }

  Variants {
    model: Quickshell.screens.filter(function (s) { return s.name === root.screenName })

    PanelWindow {
      id: win
      required property var modelData
      screen: modelData
      anchors { top: true; left: true; right: true }
      implicitHeight: root.au.top + pop.implicitHeight + root.au.shadowRoom
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"
      visible: root.showing || pop.visible
      WlrLayershell.namespace: "velum-surface"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: root.showing ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
      mask: Region { item: pop }

      VPopover {
        id: pop
        kind: "panel"
        origin: Item.Top
        open: root.showing
        x: Math.round((win.width - width) / 2)
        y: root.au.top
        pad: root.au.pad

        property real shakeX: 0
        transform: Translate { x: pop.shakeX }
        Connections {
          target: root
          function onAttemptsChanged() { if (root.attempts > 0) { field.text = ""; shake.restart() } }
        }
        SequentialAnimation {
          id: shake
          readonly property real amp: Theme.reduceMotion ? 0 : Theme.core.motion.offset.shake
          readonly property int step: Theme.dur("shake") / 6
          NumberAnimation { target: pop; property: "shakeX"; to: -shake.amp; duration: shake.step; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") }
          NumberAnimation { target: pop; property: "shakeX"; to: shake.amp; duration: shake.step * 2; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") }
          NumberAnimation { target: pop; property: "shakeX"; to: -shake.amp / 2; duration: shake.step * 2; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") }
          NumberAnimation { target: pop; property: "shakeX"; to: 0; duration: shake.step; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") }
        }

        function submit() {
          if (!root.showing || !root.flow || !root.flow.isResponseRequired) return
          var t = field.text
          field.text = ""
          root.answer(t)
        }
        Component.onCompleted: { card.field = field; card.submitFn = pop.submit }
        onOpenChanged: if (open) { field.text = ""; focusLater.restart() }
        Timer { id: focusLater; interval: 0; onTriggered: field.focusField() }

        Keys.onEscapePressed: root.cancel()

        Column {
          id: body
          width: root.au.width - 2 * root.au.pad
          spacing: root.au.gap

          Row {
            spacing: root.au.gap
            VIcon { name: "lock"; weight: "fill"; size: root.au.icon; color: Theme.r.accent.base }
            Column {
              width: body.width - root.au.icon - root.au.gap
              spacing: Theme.layout.list.gap / 2
              VText {
                width: parent.width
                text: root.command !== "" ? "Run as administrator" : "Authentication Required"
                font.pixelSize: root.au.title
                font.weight: Font.DemiBold
                color: Theme.r.popover.ink
              }
              VText {
                width: parent.width
                wrapMode: Text.Wrap
                text: root.flow ? root.flow.message : ""
                font.pixelSize: root.au.body
                color: Theme.r.popover.inkSecondary
              }
            }
          }

          // the command ask-root noted: what will run
          Rectangle {
            visible: root.command !== ""
            width: body.width
            height: code.implicitHeight + 2 * root.au.codePad
            radius: root.au.codeRadius
            color: Theme.r.popover.tile
            Text {
              id: code
              x: root.au.codePad
              y: root.au.codePad
              width: parent.width - 2 * root.au.codePad
              text: root.command
              wrapMode: Text.WrapAnywhere
              maximumLineCount: root.au.codeLines
              elide: Text.ElideRight
              font.family: Theme.core.font.mono[0]
              font.pixelSize: root.au.code
              color: Theme.r.popover.ink
            }
          }

          VField {
            id: field
            width: body.width
            secret: !(root.flow && root.flow.responseVisible)
            placeholder: root.flow ? String(root.flow.inputPrompt || "Password").replace(/:\s*$/, "") : "Password"
            enabled: !!root.flow && root.flow.isResponseRequired
            onAccepted: pop.submit()
            Keys.onEscapePressed: root.cancel()
          }

          VText {
            visible: text !== ""
            width: body.width
            wrapMode: Text.Wrap
            text: root.flow && root.flow.supplementaryMessage ? root.flow.supplementaryMessage
                  : root.attempts > 0 ? "Wrong password. Try again." : ""
            font.pixelSize: root.au.body
            color: root.flow && root.flow.supplementaryMessage && !root.flow.supplementaryIsError ? Theme.r.popover.inkSecondary : Theme.r.menu.danger
          }

          Item {
            width: body.width
            height: buttons.implicitHeight
            Row {
              id: buttons
              anchors.right: parent.right
              spacing: Theme.layout.list.gap
              VButton { text: "Cancel"; onClicked: root.cancel() }
              VButton { text: "Authenticate"; kind: "primary"; enabled: field.text !== ""; onClicked: pop.submit() }
            }
          }
        }
      }
    }
  }
}
