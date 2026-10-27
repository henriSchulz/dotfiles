import QtQuick

// SDDM greeter with the face of the Velum lock screen (henri.lock-v3). SDDM gives this file the
// context objects sddm, userModel, sessionModel and config; the face itself is Face.qml, a port of
// henri.lock-v3's LockView.qml.
//
// The greeter runs as the sddm user and cannot read ~. install/52-sddm-velum.sh therefore copies the
// Velum module into Velum/ here, and SF Pro + the SF Symbols font into the sddm user's own font dir
// (/var/lib/sddm/.local/share/fonts), where fontconfig offers every weight of the variable SF Pro.
// (A FontLoader would register only its default instance: the bold clock came out thin.) Without
// them Qt falls back to the system sans and Velum to its bundled Phosphor icons.
Rectangle {
  id: root
  width: 640
  height: 480
  color: "black"

  Loader {
    id: face
    anchors.fill: parent
    source: "Face.qml"
    focus: true
  }

  // If the face cannot load (a broken Velum copy, a QML error), a bare field still logs in:
  // a login screen that shows nothing would leave only the TTY.
  Loader {
    anchors.fill: parent
    active: face.status === Loader.Error
    focus: active
    sourceComponent: Item {
      readonly property int session: {
        for (var i = 0; i < sessionModel.rowCount(); i++)
          if (String(sessionModel.data(sessionModel.index(i, 0), Qt.DisplayRole) || "").indexOf("uwsm") !== -1) return i
        return sessionModel.lastIndex
      }
      Rectangle {  // lint-ok: emergency fallback, Velum itself failed to load
        anchors.centerIn: parent
        width: 360; height: 44; radius: 22
        color: "#33ffffff"; border.color: "#66ffffff"
        TextInput {
          id: pw
          anchors.fill: parent
          anchors.margins: 12
          focus: true
          color: "white"
          echoMode: TextInput.Password
          horizontalAlignment: TextInput.AlignHCenter
          verticalAlignment: TextInput.AlignVCenter
          onAccepted: sddm.login(String(config.user || userModel.lastUser), text, parent.parent.session)
          Component.onCompleted: forceActiveFocus()
        }
      }
      Connections { target: sddm; function onLoginFailed() { pw.text = "" } }
    }
  }
}
