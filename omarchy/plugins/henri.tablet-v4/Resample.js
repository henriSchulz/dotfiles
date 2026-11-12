.pragma library
// Edge fingers from a cast screen come in steps (ipadcast hands them on at ~22 Hz, homeStats on the
// iPad 2026-11-12), and a surface that sits on each point moves every second or third frame. This
// turns the points into one per frame: from where it stands it glides to each new point over the
// gap between points (their running mean, within minGap … maxGap), so it reaches a resting finger.
// Pure; tests: node tests/resample_test.js
//   var r = Resample.create(minGap, maxGap)
//   r.push(t, x, y)      a finger point (t in ms)
//   r.at(t) → {x, y}     where the surface stands at frame time t (null before the first point)
function create(minGap, maxGap) {
  var from = null, to = null, t0 = 0, last = 0, gap = maxGap
  function at(t) {
    if (!to) return null
    if (!from) return { x: to.x, y: to.y }
    var f = Math.max(0, Math.min(1, (t - t0) / gap))
    return { x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f }
  }
  function push(t, x, y) {
    from = to ? at(t) : null
    if (last) gap = Math.max(minGap, Math.min(maxGap, (gap + (t - last)) / 2))
    to = { x: x, y: y }
    t0 = t
    last = t
  }
  return { push: push, at: at }
}
