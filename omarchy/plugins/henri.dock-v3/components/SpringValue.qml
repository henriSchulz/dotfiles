import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// The Dock's spring (SwiftUI response / dampingRatio, mass 1), with the API the
// dock was written against (henri-ui SpringValue): `to`, `epsilon`, `movement`,
// `reduced`, snap(). Presets are Velum's (Theme.spring(…), Theme.core.surface.dock.*).
// Retargeting mid-flight keeps the velocity.
FrameAnimation {
  id: root

  property real to: 0
  property real value: 0
  property real velocity: 0
  property var preset: Theme.spring("smooth")
  readonly property real response: preset.response
  readonly property real dampingRatio: preset.dampingRatio
  // rest threshold in the value's own unit: ~0.5 for pixels, ~0.001 for scale/opacity
  property real epsilon: 0.001
  // reduced motion: a spring that moves something snaps; movement: false = a fade, keeps animating
  property bool movement: true
  property bool reduced: Theme.reduceMotion
  readonly property bool _snaps: movement && reduced

  function snap(v) {
    velocity = 0
    value = _snaps ? to : v
    running = value !== to
  }

  running: false
  onToChanged: {
    if (_snaps) { velocity = 0; value = to; running = false; return }
    if (value !== to) running = true
  }
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
