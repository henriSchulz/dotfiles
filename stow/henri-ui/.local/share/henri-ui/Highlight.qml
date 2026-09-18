import QtQuick
import qs.Commons
import "Motion.js" as Motion

// One selection shape that GLIDES between items (menus, lists, tabs,
// segmented controls) instead of each item lighting up on its own.
// It must share its parent's coordinate space with the targets (sibling of
// the items, or placed at 0,0 over the Column/Row that holds them).
//
//   HUi.Highlight { target: list.currentItem }
Rectangle {
  id: root

  property Item target: null
  property real inset: 0
  property bool suppressed: false      // e.g. blink off during a menu flash

  color: Color.accent
  radius: Style.space(Motion.radiusRow)
  x: sx.value; y: sy.value; width: sw.value; height: sh.value
  opacity: target && !suppressed ? 1 : 0
  Behavior on opacity {
    enabled: !root.suppressed
    NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
  }

  SpringValue { id: sx; epsilon: 0.3; to: root.target ? root.target.x + root.inset : root.x }
  SpringValue { id: sy; epsilon: 0.3; to: root.target ? root.target.y + root.inset : root.y }
  SpringValue { id: sw; epsilon: 0.3; to: root.target ? root.target.width - root.inset * 2 : root.width }
  SpringValue { id: sh; epsilon: 0.3; to: root.target ? root.target.height - root.inset * 2 : root.height }

  // Appearing from nothing: start at the target instead of flying in from 0,0.
  property Item _previous: null
  onTargetChanged: {
    if (target && (!_previous || opacity < 0.05)) {
      sx.snap(target.x + inset); sy.snap(target.y + inset)
      sw.snap(target.width - inset * 2); sh.snap(target.height - inset * 2)
    }
    _previous = target
  }
}
