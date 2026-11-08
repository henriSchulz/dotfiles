import QtQuick
import Quickshell
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "file:///home/henri/.local/share/velum/qml/Velum"
import "Tone.js" as Tone

// Lock screen face, Velum — design 4B "Zweiton" of lab/web/lock2.html (Henri 2026-11-08), no glass:
// the sharp wallpaper over the top fades into a flat fall between the wallpaper's two main colours
// (Tone.js reads them from a small copy of the picture), and date, a large clock and a capsule
// password field stand low in the middle on that fall. Tokens: surface.lock. Same API and the same
// password input as henri.lock's LockView: every property, signal and function below the look is
// unchanged, and the TextInput keeps its handlers line for line (onTextChanged, onAccepted, Keys:
// Esc / Ctrl+U clear); a shake on a failed attempt and a gentle spring when the screen comes up.
// Service.qml (session lock, PAM, fingerprint) is the original, untouched.
//
// On a touch screen (the tablet, a cast screen) a round keyboard button under the field slides
// Velum's on-screen keyboard (VKeyboard) up from the bottom edge: its keys type straight into the
// password field, return unlocks. henri.keyboard-v3 cannot help here — a session lock covers every
// layer surface.
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
  // ---- design 4B: sizes are shares of the screen width, `unit` is the text unit
  readonly property var face: Theme.core.surface.lock
  readonly property var look: Theme.dark ? face.dark : face.light
  readonly property real unit: Math.max(face.typeMin, width * face.type)
  readonly property real fieldWidth: Math.round(width * face.field)
  readonly property real fieldHeight: Math.round(unit * face.fieldHeight)
  readonly property int fieldFontSize: Math.round(unit)
  readonly property int passwordDotFontSize: Math.round(unit * 1.1)
  readonly property int passwordDotLetterSpacing: Math.round(unit * 0.16)
  readonly property real footSpace: Math.round(width * face.foot)
  readonly property int clockSize: Math.round(width * face.clock)

  // the two seeds of the wallpaper ([r, g, b] 0..1); until they are read, the accent stands in
  property var seeds: null
  readonly property var fallbackSeed: [Theme.r.accent.base.r, Theme.r.accent.base.g, Theme.r.accent.base.b]
  readonly property var seedTop: seeds ? seeds[0] : fallbackSeed
  readonly property var seedBottom: seeds ? seeds[1] : fallbackSeed
  // the fall's colour at height p (0 top … 1 bottom), with alpha a
  function fallAt(p, a) {
    var t = toneTop, b = toneBottom
    return Qt.rgba(t.r + (b.r - t.r) * p, t.g + (b.g - t.g) * p, t.b + (b.b - t.b) * p, a)
  }
  function rgb(a, alpha) { return Qt.rgba(a[0], a[1], a[2], alpha === undefined ? 1 : alpha) }
  readonly property color toneTop: rgb(Tone.tone(seedTop, look.top.l, look.top.c))
  readonly property color toneBottom: rgb(Tone.tone(seedBottom, look.bottom.l, look.bottom.c))
  readonly property var inkRgb: Theme.dark ? Tone.toneAbs(seedTop, look.ink.l, look.ink.chroma) : Tone.tone(seedTop, look.ink.l, look.ink.c)
  readonly property color ink: rgb(inkRgb)
  readonly property color inkSecondary: rgb(inkRgb, face.alpha.secondary)
  readonly property color inkLine: rgb(inkRgb, face.alpha.line)
  readonly property color inkSoft: rgb(inkRgb, face.alpha.soft)
  readonly property string userInitial: (Quickshell.env("USER") || "").charAt(0).toUpperCase()
  readonly property var battery: UPower.displayDevice
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

  // the on-screen keyboard (the button under the field opens it, its hide key closes it)
  property bool keyboardShown: false
  readonly property real keyboardHeight: keys.boardHeight
  // the face moves up as far as the keyboard would cover the field and the hint under it
  readonly property real keyboardLift: Math.max(0, keyboardHeight + Theme.layout.window.pad - footSpace)

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

  // keys of the on-screen keyboard, as the hardware keys would reach the field
  function oskType(text) {
    if (!passwordInput.enabled || passwordInput.readOnly) return
    passwordInput.forceActiveFocus()
    passwordInput.insert(passwordInput.cursorPosition, text)
  }
  function oskKey(key) {
    root.wakeRequested()
    if (!passwordInput.enabled || passwordInput.readOnly) return
    passwordInput.forceActiveFocus()
    var c = passwordInput.cursorPosition
    if (key === "BackSpace") { if (c > 0) passwordInput.remove(c - 1, c) }
    else if (key === "Return") passwordInput.accepted()
    else if (key === "Left") passwordInput.cursorPosition = Math.max(0, c - 1)
    else if (key === "Right") passwordInput.cursorPosition = Math.min(passwordInput.text.length, c + 1)
  }
  function setKeyboard(on) {
    if (on && !root.inputEnabled) return
    if (on) keys.reset()
    root.keyboardShown = on
    root.wakeRequested()
    root.forcePasswordFocus()
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
    else keyboardShown = false
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

  // the keyboard comes up from the bottom edge, going away is quicker; the field lifts with it
  property real keyboardOut: keyboardShown ? 1 : 0
  Behavior on keyboardOut {
    NumberAnimation {
      duration: root.keyboardShown ? Theme.dur("base") : Theme.exit(Theme.dur("base"))
      easing.type: Easing.BezierSpline
      easing.bezierCurve: root.keyboardShown ? Theme.curve("out") : Theme.curve("exit")
    }
  }

  readonly property real fieldLift: keyboardLift * (Theme.reduceMotion ? (keyboardShown ? 1 : 0) : keyboardOut)

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

    // ---- the fall between the two tones, the whole screen
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0; color: root.toneTop }
        GradientStop { position: 1; color: root.toneBottom }
      }
    }

    // ---- the wallpaper, sharp, over the top; a flat veil in the dark; then it fades into the fall
    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.loadBackground ? root.fileUrl(root.backgroundPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
      opacity: status === Image.Ready ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Theme.dur("base"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
    }
    Rectangle {
      anchors.fill: parent
      color: Theme.core.color.scrim
      visible: root.look.photoDim > 0
      opacity: root.look.photoDim * wallpaper.opacity
    }
    // the photo's fade: the fall's own colour at each height, clear down to `solid`, opaque from `clear`
    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0; color: root.fallAt(0, 0) }
        GradientStop { position: root.face.photo.solid; color: root.fallAt(root.face.photo.solid, 0) }
        GradientStop { position: root.face.photo.clear; color: root.fallAt(root.face.photo.clear, 1) }
        GradientStop { position: 1; color: root.toneBottom }
      }
    }

    // reads the two seeds from a small copy of the wallpaper (once per picture)
    Canvas {
      id: sampler
      width: root.face.seed.sample
      height: root.face.seed.sample
      opacity: 0
      readonly property string src: root.loadBackground && root.backgroundPath ? root.fileUrl(root.backgroundPath) : ""
      property string done: ""
      onSrcChanged: if (src && src !== done) loadImage(src)
      Component.onCompleted: if (src) loadImage(src)
      onImageLoaded: requestPaint()
      onPaint: {
        if (!src || !isImageLoaded(src)) return
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.drawImage(src, 0, 0, width, height)
        var found = Tone.seeds(ctx.getImageData(0, 0, width, height).data, root.face.seed)
        if (found) root.seeds = found
        unloadImage(src)
        done = src
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    // ---- date, clock, field and hint: one column, low in the middle, lifted by the keyboard
    Column {
      id: faceColumn
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.footSpace
      spacing: 0
      transform: Translate { y: -root.fieldLift + (1 - appear.value) * Theme.move(Theme.core.motion.offset.carry) }
      opacity: appear.value

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDate(root.now, "dddd, d MMMM")
        color: root.inkSecondary
        font.family: Theme.font
        font.pixelSize: Math.round(root.unit * root.face.date)
        font.weight: Font.DemiBold
      }
      Text {
        id: clockText
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatTime(root.now, "H:mm")
        color: root.ink
        font.family: Theme.font
        font.pixelSize: root.clockSize
        font.weight: Font.Bold
        font.letterSpacing: root.clockSize * root.face.clockTracking
      }
      // the clock's line box already holds a part of the gap under its figures
      Item { width: 1; height: Math.max(0, Math.round(root.clockSize * root.face.clockGap) - (clockText.height - root.clockSize)) }

    // ---- the password field: a flat capsule in the ink's soft share, the initial at its left
    Item {
      id: fieldBox
      width: root.fieldWidth
      height: root.fieldHeight
      anchors.horizontalCenter: parent.horizontalCenter
      scale: Theme.scale("popoverFrom") + (1 - Theme.scale("popoverFrom")) * appear.value
      transform: Translate { x: root.shakeX }

      Rectangle {
        id: inputField
        anchors.fill: parent
        radius: height / 2
        color: root.inkSoft
        border.width: root.errorState || passwordInput.activeFocus && passwordInput.text.length > 0 ? Theme.core.size.focusRing : Theme.layout.separator
        border.color: root.errorState ? Theme.r.danger : (passwordInput.activeFocus && passwordInput.text.length > 0 ? root.ink : root.inkLine)
        Behavior on border.color { ColorAnimation { duration: Theme.dur("fast") } }
        clip: true
        readonly property real borderTop: 0
        readonly property real borderRight: 0
        readonly property real borderBottom: 0
        readonly property real borderLeft: 0

        // the user's initial, a disc in the ink at the capsule's left
        Rectangle {
          id: avatar
          readonly property real size: Math.round(root.unit * root.face.avatar)
          width: size
          height: size
          radius: size / 2
          anchors.left: parent.left
          anchors.leftMargin: Math.round((parent.height - size) / 2)
          anchors.verticalCenter: parent.verticalCenter
          color: root.ink
          visible: !root.authenticatingPassword && root.userInitial.length > 0
          Text {
            anchors.centerIn: parent
            text: root.userInitial
            color: root.toneBottom
            font.family: Theme.font
            font.pixelSize: Math.round(avatar.size * 0.5)
            font.weight: Font.DemiBold
          }
        }

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
          passwordCharacter: "●"
          passwordMaskDelay: 0
          color: root.ink
          selectionColor: Theme.r.accent.base
          selectedTextColor: Theme.r.ink.onAccent
          font.family: Theme.font
          font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
          font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
          cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
          cursorDelegate: Rectangle {
            width: Theme.layout.separator * 2
            color: root.ink
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
          color: root.authenticatingPassword ? root.ink : (root.failureMessage.length > 0 ? Theme.r.danger : root.inkSecondary)
          font.family: Theme.font
          font.pixelSize: root.fieldFontSize
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          elide: Text.ElideRight
        }

        // while the password is checked: a spinner where the initial was
        VSpinner {
          anchors.left: parent.left
          anchors.leftMargin: Theme.layout.module.pad
          anchors.verticalCenter: parent.verticalCenter
          visible: root.authenticatingPassword
          color: root.inkSecondary
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
          color: root.inkSecondary
        }
      }
    }

    // with a fingerprint enrolled, a hint under the field says both ways in (macOS)
    Text {
      id: hint
      anchors.horizontalCenter: parent.horizontalCenter
      topPadding: Math.round(root.unit * root.face.hint)
      visible: root.fingerprintConfigured || root.errorState
      opacity: root.inputEnabled ? 1 : 0
      text: root.errorState ? "Try again or use your fingerprint" : "Use fingerprint or enter password"
      color: root.inkSecondary
      font.family: Theme.font
      font.pixelSize: Math.round(root.unit * root.face.hint)
      font.weight: Font.Medium
    }
    }

    // the keyboard button under the face: a finger's way in on a touch screen; flat, in the ink's soft share
    Item {
      id: keyButton
      readonly property real size: Theme.core.surface.keyboard.lockButton
      width: size
      height: size
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: faceColumn.bottom
      anchors.topMargin: Math.round((root.footSpace - size) / 2)
      transform: Translate { y: -root.fieldLift }
      visible: root.inputEnabled
      opacity: appear.value * (1 - root.keyboardOut)
      scale: tapKey.pressed ? Theme.scale("press") : 1
      Behavior on scale { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
      Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.inkSoft
        border.width: Theme.layout.separator
        border.color: root.inkLine
      }
      VIcon { anchors.centerIn: parent; name: "keyboard"; size: Theme.core.surface.keyboard.lockIcon; color: root.ink }
      TapHandler { id: tapKey; enabled: !root.keyboardShown; onTapped: root.setKeyboard(true) }
    }

    // the battery in the corner at the foot (only with a battery; the middle keeps the keyboard button)
    Row {
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Math.round(root.width * root.face.status)
      spacing: Theme.layout.list.gap
      visible: !!root.battery && root.battery.isLaptopBattery
      opacity: appear.value
      VIcon { anchors.verticalCenter: parent.verticalCenter; name: "battery"; size: Math.round(root.unit * root.face.hint * 1.2); color: root.inkSecondary }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.battery ? Math.round(root.battery.percentage * 100) + " %" : ""
        color: root.inkSecondary
        font.family: Theme.font
        font.pixelSize: Math.round(root.unit * root.face.hint)
      }
    }

    // Lock screen message, centred near the bottom edge as on macOS. Kept
    // on its last text while fading out so it never blinks away.
    Text {
      id: lockMessage
      objectName: "lockMessage"
      property string shown: ""
      textFormat: Text.PlainText
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: Math.round(parent.width * root.face.message)
      width: Math.min(parent.width - 2 * Theme.layout.window.pad, Theme.layout.module.width * 1.3)
      text: root.message.length > 0 ? root.message : shown
      onTextChanged: if (root.message.length > 0) shown = root.message
      opacity: root.message.length > 0 ? 1 : 0
      visible: opacity > 0
      color: root.ink
      font.family: Theme.font
      font.pixelSize: Math.round(root.unit)
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

    VKeyboard {
      id: keys
      anchors { left: parent.left; right: parent.right }
      height: boardHeight
      y: parent.height - (Theme.reduceMotion ? boardHeight : boardHeight * root.keyboardOut)
      opacity: Theme.reduceMotion ? root.keyboardOut : 1
      visible: root.keyboardOut > 0
      onTyped: function (text) { root.oskType(text) }
      onKeyPressed: function (key) { root.oskKey(key) }
      onHideRequested: root.setKeyboard(false)
    }
  }
}
