import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "Apple.js" as Apple

// Listenzeile einer Detailseite (44 pt): runder Icon-Badge, Titel + Status,
// optionaler Trailing-Text. Hover füllt (instant/fast), Press snappy. Mit
// `enterDelay` ≥ 0 gleitet die Zeile nach einem Seitenwechsel von rechts ein.
Rectangle {
  id: lr
  readonly property var m: Apple.material(lr)
  property string icon: ""
  property string iconFont: Apple.symbolFont
  property bool active: false
  property string title: ""
  property string subtitle: ""
  property string trailing: ""
  property string trailingFont: trailing.codePointAt(0) >= 0x100000 ? Apple.symbolFont : Apple.uiFont
  property bool busy: false
  property int enterDelay: -1
  signal clicked()
  width: parent ? parent.width : 0
  height: Style.space(Apple.rowH)
  radius: Style.space(Apple.radiusRow)
  color: mouse.containsMouse ? m.rowHover : Qt.rgba(m.rowHover.r, m.rowHover.g, m.rowHover.b, 0)
  Behavior on color {
    ColorAnimation {
      duration: mouse.containsMouse ? Motion.instant : Motion.fast
      easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut
    }
  }
  scale: press.value
  HUi.SpringValue { id: press; preset: Motion.snappy; to: mouse.pressed && !Motion.reduceMotion ? Motion.pressScale : 1 }

  transform: Translate { id: shift }
  Component.onCompleted: {
    if (enterDelay < 0) return
    opacity = 0
    shift.x = Motion.reduceMotion ? 0 : Style.space(18)
    enterPause.duration = enterDelay
    enter.start()
  }
  SequentialAnimation {
    id: enter
    PauseAnimation { id: enterPause; duration: 0 }
    ParallelAnimation {
      NumberAnimation { target: lr; property: "opacity"; to: 1; duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
      NumberAnimation { target: shift; property: "x"; to: 0; duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
    }
  }

  Rectangle {
    id: circle
    anchors.left: parent.left
    anchors.leftMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(28); height: width; radius: width / 2
    color: lr.active ? m.badgeOn : m.badgeOff
    antialiasing: true
    Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    scale: activeScale.value
    HUi.SpringValue { id: activeScale; preset: Motion.snappy; to: lr.active || Motion.reduceMotion ? 1 : 0.94 }
    Text {
      anchors.centerIn: parent
      text: lr.icon
      color: lr.active ? m.badgeOnGlyph : m.badgeOffGlyph
      Behavior on color { ColorAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      font.family: lr.iconFont
      font.pixelSize: Style.space(14)
    }
  }
  Column {
    anchors.left: circle.right
    anchors.leftMargin: Style.space(10)
    anchors.right: trailingText.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    Text {
      width: parent.width
      text: lr.title
      color: m.ink
      font.family: Apple.uiFont
      font.pixelSize: Style.space(Apple.body)
      font.weight: lr.active ? Font.DemiBold : Font.Normal
      elide: Text.ElideRight
    }
    Text {
      width: parent.width
      visible: text !== ""
      text: lr.subtitle
      color: m.inkMuted
      font.family: Apple.uiFont
      font.pixelSize: Style.space(Apple.subheadline)
      elide: Text.ElideRight
      SequentialAnimation on opacity {
        running: lr.busy
        loops: Animation.Infinite
        onRunningChanged: if (!running) parent.opacity = 1
        NumberAnimation { to: Motion.disabledOpacity; duration: Motion.slower; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut }
        NumberAnimation { to: 1; duration: Motion.slower; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut }
      }
    }
  }
  HUi.CrossfadeText {
    id: trailingText
    anchors.right: parent.right
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignRight
    text: lr.trailing
    color: m.inkMuted
    fontFamily: lr.trailingFont
    fontSize: Style.space(Apple.subheadline)
  }
  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: lr.clicked()
  }
}
