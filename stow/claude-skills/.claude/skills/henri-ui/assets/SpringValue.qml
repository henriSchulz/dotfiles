import QtQuick

// SwiftUI-style spring for QML. Copy into the plugin root next to Motion.js.
//
//   SpringValue { id: s; to: popup.open ? 1 : 0.95; response: 0.35 }
//   Item { scale: s.value }
//
// Retargeting mid-flight keeps the current velocity, so rapid open/close or
// hover in/out never jumps or restarts — the core of the macOS feel.
// Presets (see SKILL.md): smooth 0.35/1.0, snappy 0.40/0.85,
// gentle 0.50/1.0, bouncy 0.45/0.75.
FrameAnimation {
  id: root

  property real to: 0
  property real value: 0
  property real velocity: 0
  property real response: 0.35
  property real dampingRatio: 1.0
  // Rest threshold in the value's own unit: ~0.5 for pixels, ~0.001 for scale/opacity.
  property real epsilon: 0.001

  // Jump to v without animating; keeps the `to` binding intact, so the spring
  // then runs from v to the current target (e.g. start an open from 0.96).
  function snap(v) {
    velocity = 0
    value = v
    running = value !== to
  }

  running: false
  onToChanged: if (value !== to) running = true
  Component.onCompleted: value = to

  onTriggered: {
    const dt = Math.min(frameTime, 1 / 30)
    const k = Math.pow(2 * Math.PI / response, 2)
    const c = 4 * Math.PI * dampingRatio / response
    const steps = Math.max(1, Math.ceil(dt / 0.002))
    const h = dt / steps
    let x = value
    let v = velocity
    for (let i = 0; i < steps; i++) {
      v += (-k * (x - to) - c * v) * h
      x += v * h
    }
    if (Math.abs(x - to) < epsilon && Math.abs(v) < epsilon * 10) {
      value = to
      velocity = 0
      running = false
    } else {
      value = x
      velocity = v
    }
  }
}
