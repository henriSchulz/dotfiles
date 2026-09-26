import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "Apple.js" as Apple

// Einzeiliges Eingabefeld (Wi-Fi-Passwort u. ä.). `submitIcon` zeigt rechts
// den Absende-Pfeil; `error` rötet den Rahmen (Farb-Fade, kein Sprung).
Rectangle {
  id: tf
  readonly property var m: Apple.material(tf)
  property alias input: inp
  property alias text: inp.text
  property string placeholder: ""
  property bool password: false
  property bool submitIcon: false
  property bool error: false
  property Item nextField: null
  property Item prevField: null
  signal submitted()
  signal cancelled()
  signal edited()
  width: parent ? parent.width : 0
  height: Style.space(32)
  radius: Style.space(Apple.radiusControl)
  color: m.field
  border.width: 1
  border.color: tf.error ? m.urgent : inp.activeFocus ? m.accent : m.hairline
  Behavior on border.color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }

  TextInput {
    id: inp
    anchors.fill: parent
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: tf.submitIcon ? Style.space(34) : Style.space(10)
    verticalAlignment: TextInput.AlignVCenter
    echoMode: tf.password ? TextInput.Password : TextInput.Normal
    inputMethodHints: tf.password ? Qt.ImhSensitiveData | Qt.ImhNoPredictiveText : Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
    color: m.ink
    selectionColor: m.accent
    selectedTextColor: "#ffffff"
    font.family: Apple.uiFont
    font.pixelSize: Style.space(Apple.body)
    clip: true
    Keys.onReturnPressed: tf.submitted()
    Keys.onEnterPressed: tf.submitted()
    Keys.onEscapePressed: tf.cancelled()
    onTextEdited: tf.edited()
    KeyNavigation.tab: tf.nextField
    KeyNavigation.backtab: tf.prevField
    Text {
      anchors.verticalCenter: parent.verticalCenter
      opacity: parent.text === "" ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Motion.instant; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      text: tf.placeholder
      color: m.inkMuted
      font: parent.font
    }
  }
  Text {
    visible: tf.submitIcon
    anchors.right: parent.right
    anchors.rightMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    text: Apple.sf(0x100C13)
    color: inp.text === "" ? m.inkMuted : m.ink
    Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    font.family: Apple.symbolFont
    font.pixelSize: Style.space(14)
    MouseArea {
      anchors.fill: parent
      anchors.margins: -Style.space(6)
      cursorShape: Qt.PointingHandCursor
      onClicked: tf.submitted()
    }
  }
}
