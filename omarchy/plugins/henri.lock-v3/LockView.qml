import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui
import "file:///home/henri/.local/share/velum/qml/Velum"

// Lock screen face, Velum (Pearl). Same API and the same password input as
// henri.lock's LockView: every property, signal and function below the look
// is unchanged, and the TextInput keeps its handlers line for line
// (onTextChanged, onAccepted, Keys: Esc / Ctrl+U clear). Only the look is new:
// the blurred wallpaper, a large clock and date as on macOS, the password
// field on the popover material, a shake on a failed attempt and a gentle
// spring when the screen comes up. Service.qml (session lock, PAM, fingerprint)
// is the original, untouched.
Item {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  // "Show message when locked" (System Settings > Lock Screen), "" = none
  property string message: ""
  property bool syncingPasswordText: false

  readonly property string placeholderText: "Enter Password"
  readonly property real fieldWidth: Math.round(Theme.layout.module.width * 0.62)
  readonly property real fieldHeight: Theme.m.control.height + Theme.layout.module.pad
  readonly property int fieldFontSize: Theme.m.type.body
  readonly property int passwordDotFontSize: Math.round(Theme.m.type.title * 1.1)
  readonly property int passwordDotLetterSpacing: Math.round(Theme.m.type.title * 0.16)
  // Space to keep clear on each side of the field for the fingerprint icon
  // (icon width plus a gap) so the centered dots never run under it.
  readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.width + Theme.layout.list.gap) : 0
  // Shrink the dots to fit once the password outgrows the field, so every
  // keystroke stays visible — otherwise long passwords clip with no feedback.
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0
  // white text straight over the photo (clock, date, message)
  readonly property color photoInk: Theme.r.ink.onAccent

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  // Cache-busts the lock background by appending `?v=`. Adding a query
  // string keeps Image's loader happy while forcing it to reload when the
  // user picks a new background mid-session.
  function fileUrl(path) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
    appear.from(0)
  }

  // ---- motion (look only): the face comes up on the gentle spring, a failed attempt shakes the field
  Spring { id: appear; preset: Theme.spring("gentle"); reduced: Theme.reduceMotion; target: 1 }
  onFailedAttemptsChanged: if (failedAttempts > 0) shake.restart()
  property real shakeX: 0
  SequentialAnimation {
    id: shake
    readonly property real amp: Theme.reduceMotion ? 0 : Theme.core.motion.offset.shake
    readonly property int step: Theme.dur("shake") / 6
    NumberAnimation { target: root; property: "shakeX"; to: -shake.amp; duration: shake.step; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") }
    NumberAnimation { target: root; property: "shakeX"; to: shake.amp; duration: shake.step * 2; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") }
    NumberAnimation { target: root; property: "shakeX"; to: -shake.amp / 2; duration: shake.step * 2; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") }
    NumberAnimation { target: root; property: "shakeX"; to: 0; duration: shake.step; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") }
  }

  // the clock runs only while the face is shown
  property date now: new Date()
  Timer { interval: 1000; repeat: true; running: root.visible; triggeredOnStart: true; onTriggered: root.now = new Date() }

  // Measures the masked password at full size; passwordDotScale compares this
  // against the field width to decide how far the dots must shrink to fit.
  TextMetrics {
    id: dotMetrics
    font.family: Theme.font
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(passwordInput.text.length)
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background

    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.loadBackground ? root.fileUrl(root.backgroundPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.status === Image.Ready
      blur: 1.0
      blurMax: 128
      blurMultiplier: 1.25
      contrast: -0.08
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    // ---- clock and date, high on the screen as on macOS
    Column {
      id: clockBlock
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.round(parent.height * 0.12) + (1 - appear.value) * Theme.move(-Theme.core.motion.offset.carry)
      opacity: appear.value
      spacing: 0
      // a soft shade so the white clock reads on any photo
      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: (Theme.r.popover.shadow || []).length > 1 ? Theme.r.popover.shadow[1].color : "transparent"
        shadowBlur: 1.0
        shadowVerticalOffset: Theme.layout.separator * 2
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDate(root.now, "dddd, d MMMM")
        color: root.photoInk
        font.family: Theme.font
        font.pixelSize: Theme.m.type.title * 1.4
        font.weight: Font.DemiBold
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatTime(root.now, "H:mm")
        color: root.photoInk
        font.family: Theme.font
        font.pixelSize: Theme.m.type.title * 6.5
        font.weight: Font.Bold
      }
    }
    // ---- the password field on the popover material
    Item {
      id: fieldBox
      width: root.fieldWidth
      height: root.fieldHeight
      anchors.centerIn: parent
      anchors.verticalCenterOffset: Math.round(parent.height * 0.08)
      opacity: appear.value
      scale: Theme.scale("popoverFrom") + (1 - Theme.scale("popoverFrom")) * appear.value
      transform: Translate { x: root.shakeX }

      VShadow { layers: Theme.r.popover.shadow; radius: inputField.radius }
      Rectangle {
        id: inputField
        anchors.fill: parent
        radius: height / 2
        color: Theme.reduceTransparency ? Theme.r.popover.bgOpaque : Theme.r.popover.bg
        border.width: root.errorState ? Theme.core.size.focusRing : Theme.layout.separator
        border.color: root.errorState ? Theme.r.danger : Theme.r.line.rim
        Behavior on border.color { ColorAnimation { duration: Theme.dur("fast") } }
        clip: true
        readonly property real borderTop: 0
        readonly property real borderRight: 0
        readonly property real borderBottom: 0
        readonly property real borderLeft: 0

        TextInput {
          id: passwordInput
          anchors.fill: parent
          anchors.topMargin: inputField.borderTop
          // Reserve the fingerprint icon's width on both sides so the centered
          // dots stay symmetric and never slide under the icon as they grow.
          anchors.rightMargin: inputField.borderRight + Theme.layout.module.pad + root.fingerprintReserve
          anchors.bottomMargin: inputField.borderBottom
          anchors.leftMargin: inputField.borderLeft + Theme.layout.module.pad + root.fingerprintReserve
          verticalAlignment: TextInput.AlignVCenter
          horizontalAlignment: TextInput.AlignHCenter
          activeFocusOnPress: true
          clip: true
          enabled: root.inputEnabled && !root.authenticatingPassword
          readOnly: root.authenticatingPassword
          echoMode: TextInput.Password
          passwordCharacter: "\u25CF"
          passwordMaskDelay: 0
          color: Theme.r.popover.ink
          selectionColor: Theme.r.accent.base
          selectedTextColor: Theme.r.ink.onAccent
          font.family: Theme.font
          font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
          font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
          cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
          cursorDelegate: Rectangle {
            width: Theme.layout.separator * 2
            color: Theme.r.accent.base
            visible: passwordInput.cursorVisible
          }

          onTextChanged: {
            if (!root.syncingPasswordText) root.passwordTextEdited(text)
            if (text.length > 0) {
              root.wakeRequested()
            }
            if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
          }

          onAccepted: {
            var submitted = root.passwordText
            root.passwordTextEdited("")
            if (submitted.length > 0) root.submitPassword(submitted)
          }

          Keys.onPressed: function(event) {
            root.wakeRequested()
            if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
              root.passwordTextEdited("")
              event.accepted = true
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.fill: passwordInput
          text: root.authenticatingPassword ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
          visible: passwordInput.text.length === 0
          color: root.authenticatingPassword ? Theme.r.popover.ink : (root.failureMessage.length > 0 ? Theme.r.danger : Theme.r.popover.inkSecondary)
          font.family: Theme.font
          font.pixelSize: root.fieldFontSize
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }

        // while the password is checked: a spinner where the dots were
        VSpinner {
          anchors.left: parent.left
          anchors.leftMargin: Theme.layout.module.pad
          anchors.verticalCenter: parent.verticalCenter
          visible: root.authenticatingPassword
          color: Theme.r.popover.inkSecondary
        }

        // Fingerprint hint pinned inside the field's right edge when a sensor is
        // enrolled, so the user knows they can touch to unlock instead of typing.
        VIcon {
          id: fingerprintIcon
          objectName: "fingerprintIndicator"
          anchors.right: parent.right
          anchors.rightMargin: inputField.borderRight + Theme.layout.module.pad
          anchors.verticalCenter: parent.verticalCenter
          visible: root.fingerprintConfigured
          name: "fingerprint"
          size: Theme.layout.icon.large
          color: Theme.r.popover.inkSecondary
        }
      }
    }

    // with a fingerprint enrolled, a hint under the field says both ways in (macOS)
    Text {
      anchors.horizontalCenter: fieldBox.horizontalCenter
      anchors.top: fieldBox.bottom
      anchors.topMargin: Theme.layout.module.pad
      visible: root.fingerprintConfigured
      opacity: appear.value * (root.inputEnabled ? 0.85 : 0)
      text: "Use fingerprint or enter password"
      color: root.photoInk
      font.family: Theme.font
      font.pixelSize: Theme.m.type.small
      font.weight: Font.Medium
    }

    // Lock screen message, centred near the bottom edge as on macOS. Kept
    // on its last text while fading out so it never blinks away.
    Text {
      id: lockMessage
      objectName: "lockMessage"
      property string shown: ""
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Math.round(parent.height * 0.08)
      width: Math.min(parent.width - 2 * Theme.layout.window.pad, Theme.layout.module.width * 1.3)
      text: root.message.length > 0 ? root.message : shown
      onTextChanged: if (root.message.length > 0) shown = root.message
      opacity: root.message.length > 0 ? 1 : 0
      visible: opacity > 0
      color: root.photoInk
      font.family: Theme.font
      font.pixelSize: Theme.m.type.title
      font.weight: Font.Medium
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.Wrap
      maximumLineCount: 3
      elide: Text.ElideRight

      Behavior on opacity {
        NumberAnimation {
          duration: root.message.length > 0 ? Theme.dur("base") : Theme.exit(Theme.dur("base"))
          easing.type: Easing.BezierSpline
          easing.bezierCurve: root.message.length > 0 ? Theme.curve("out") : Theme.curve("exit")
        }
      }
    }
  }
}
