import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "Apple.js" as Apple

// SectionLabel mit Aufklapp-Chevron rechts — Kopf einer einklappbaren Gruppe
// (der Inhalt darunter sitzt in einem HUi.Collapse mit demselben `expanded`).
// Die ganze Zeile ist klickbar; Hover hebt nur die Farbe an (häufige
// Interaktion: kein Scale, keine Bewegung), der Chevron dreht wie in macOS
// von › nach ˅.
//
//   AUi.DisclosureLabel { text: "Debug"; expanded: open; onClicked: open = !open }
//   HUi.Collapse { expanded: open; … }
Item {
  id: dl
  readonly property var m: Apple.material(dl)
  property string text: ""
  property bool expanded: false
  property alias leftPadding: label.leftPadding
  signal clicked()

  width: parent ? parent.width : 0
  implicitHeight: label.implicitHeight
  height: implicitHeight

  readonly property color inkNow: hover.hovered ? m.inkSecondary : m.inkMuted

  SectionLabel {
    id: label
    anchors.left: parent.left
    anchors.right: chevron.left
    anchors.rightMargin: Style.space(6)
    text: dl.text
    elide: Text.ElideRight
    color: dl.inkNow
    Behavior on color { ColorAnimation { duration: hover.hovered ? Motion.instant : Motion.fast } }
  }
  Text {
    id: chevron
    anchors.right: parent.right
    anchors.rightMargin: Style.space(2)
    anchors.verticalCenter: label.verticalCenter
    anchors.verticalCenterOffset: label.topPadding / 2
    text: Apple.sf(0x10018A)
    color: dl.inkNow
    font.family: Apple.symbolFont
    font.pixelSize: Style.space(Apple.footnote)
    rotation: dl.expanded ? 90 : 0
    Behavior on color { ColorAnimation { duration: hover.hovered ? Motion.instant : Motion.fast } }
    Behavior on rotation {
      enabled: !Motion.reduceMotion
      NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
    }
  }
  HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
  MouseArea {
    anchors.fill: parent
    anchors.topMargin: -Style.space(4)
    anchors.bottomMargin: -Style.space(4)
    cursorShape: Qt.PointingHandCursor
    onClicked: dl.clicked()
  }
  Accessible.role: Accessible.Button
  Accessible.name: dl.text
  Accessible.onPressAction: dl.clicked()
}
