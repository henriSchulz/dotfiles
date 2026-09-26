import QtQuick
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "Apple.js" as Apple

// Tahoe-Slider: 4-pt-Track, weißer Fill, kein Knopf. Beim Ziehen klebt der
// Fill am Zeiger, sonst gleitet er (fast). `stops` > 1 zeichnet Rasterkerben
// und rastet auf ganze Indizes (Text-Größe).
Item {
  id: gs
  readonly property var m: Apple.material(gs)
  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 0.05
  property int stops: 0
  property bool enabled: true
  property real liveValue: value
  property bool dragging: false
  signal moved(real value)
  signal released(real value)
  onValueChanged: if (!dragging) liveValue = value
  readonly property real range: Math.max(0.0001, maximum - minimum)
  readonly property real progress: Math.max(0, Math.min(1, (liveValue - minimum) / range))
  implicitHeight: Style.space(22)
  opacity: enabled ? 1 : Motion.disabledOpacity
  Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }

  Rectangle {
    id: track
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left; anchors.right: parent.right
    height: Style.space(Apple.sliderH)
    radius: height / 2
    color: m.sliderTrack
  }
  Repeater {
    model: gs.stops > 1 ? gs.stops : 0
    Rectangle {
      required property int index
      width: Math.max(1, Style.space(1)); height: track.height + Style.space(4)
      radius: 1
      color: m.sliderTrack
      anchors.verticalCenter: track.verticalCenter
      x: Math.max(0, Math.min(track.width - width, track.width * (index / (gs.stops - 1)) - width / 2))
    }
  }
  Rectangle {
    anchors.verticalCenter: track.verticalCenter
    anchors.left: track.left
    height: track.height
    radius: track.radius
    color: m.sliderFill
    width: gs.progress > 0 ? Math.max(height, track.width * gs.progress) : 0
    Behavior on width {
      enabled: !gs.dragging
      NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
    }
  }
  MouseArea {
    anchors.fill: parent
    enabled: gs.enabled
    cursorShape: Qt.PointingHandCursor
    function at(x) {
      var f = Math.max(0, Math.min(1, x / Math.max(1, track.width)))
      var v = gs.minimum + f * gs.range
      if (gs.stops > 1) v = Math.round(v)
      return Math.max(gs.minimum, Math.min(gs.maximum, v))
    }
    onPressed: function(e) { gs.dragging = true; gs.liveValue = at(e.x); gs.moved(gs.liveValue) }
    onPositionChanged: function(e) { if (gs.dragging) { gs.liveValue = at(e.x); gs.moved(gs.liveValue) } }
    onReleased: function(e) { gs.dragging = false; gs.released(gs.liveValue); gs.liveValue = gs.value }
    onWheel: function(w) {
      var d = gs.stops > 1 ? 1 : gs.step
      var next = Math.max(gs.minimum, Math.min(gs.maximum, gs.liveValue + (w.angleDelta.y > 0 ? d : -d)))
      gs.liveValue = next; gs.moved(next); gs.released(next)
    }
  }
}
