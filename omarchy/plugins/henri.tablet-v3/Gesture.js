.pragma library
// The home-zone gesture: what a finger that went down on the bottom edge means.
// Pure logic (no QML), fed with (time ms, x, y) in logical px; every call returns the
// actions it decided, in order. Tests: node tests/gesture_test.js
//
//   var g = Gesture.create(cfg)        cfg = Theme.core.surface.tablet
//   g.down(t, x, y)   g.move(t, x, y)   g.tick(t)   g.up(t, x, y)   g.cancel()
//
// Modes after the finger goes down:
//   pending   not yet past `slop`
//   lift      upward (lift move, travel in px): a pause above `holdTravel` turns it into the
//             App Switcher; released high (`homeTravel`) or fast (`homeFlick`) it goes home,
//             otherwise it ends (lift end). Nothing follows it yet: the dock is no longer pulled
//             up from here (Henri, 2026-10-28: iPadOS-like home gesture instead)
//   switcher  Mission Control under the finger (switcher start / update / end, deltas in px,
//             negative = up)
//   slide     sideways along the edge: the next or previous app (workspace) on release;
//             the indicator follows the finger meanwhile (slide move / end)
//   held      the finger rested below the slop for `longPress`: Spotlight (longpress)
//   down      pushed down past `downSlop`: the app shrinks to a floating window (down)
//
// Actions: { do: "lift", phase: "move"|"end"|"cancel", travel, up, dx, velocity, vx }
//          (up: signed travel, dx: sideways from the start; tablet mode's Home.qml follows them)
//          { do: "home" }
//          { do: "switcher", phase: "start"|"update"|"end", delta, cancelled }
//          { do: "app", step: +1|-1 }
//          { do: "tap" }   released before the slop (the window bar above the indicator;
//                          a second one within `doubleTap` is the previous app, Tablet.qml)
//          { do: "slide", phase: "move"|"end", dx }   the indicator follows a sideways finger
//          { do: "longpress" }   { do: "down" }

function create(cfg) {
  var mode = "idle"
  var x0 = 0, y0 = 0, lastY = 0, t0 = 0
  var samples = []          // [t, x, y], only the last sampleWindow ms are kept
  var slowSince = -1

  function keep(t, x, y) {
    samples.push([t, x, y])
    while (samples.length > 2 && t - samples[0][0] > cfg.sampleWindow) samples.shift()
  }
  // px/s over the kept samples: { x, up } (up positive = toward the top of the screen)
  function velocity() {
    if (samples.length < 2) return { x: 0, up: 0 }
    var a = samples[0], b = samples[samples.length - 1]
    var dt = (b[0] - a[0]) / 1000
    if (dt <= 0) return { x: 0, up: 0 }
    return { x: (b[1] - a[1]) / dt, up: (a[2] - b[2]) / dt }
  }
  function travelUp() { return samples.length ? y0 - samples[samples.length - 1][2] : 0 }

  // lift → switcher once the finger rests high enough for holdTime
  function checkHold(t) {
    if (mode !== "lift") return []
    var v = velocity()
    var speed = Math.sqrt(v.x * v.x + v.up * v.up)
    // a finger that has not moved for a while has a stale window: count it as resting
    var resting = samples.length && t - samples[samples.length - 1][0] >= cfg.sampleWindow
    if (travelUp() < cfg.holdTravel || (speed >= cfg.holdSpeed && !resting)) { slowSince = -1; return [] }
    if (slowSince < 0) { slowSince = t; return [] }
    if (t - slowSince < cfg.holdTime) return []
    mode = "switcher"
    return [{ do: "switcher", phase: "start", delta: -travelUp() }]
  }

  return {
    get mode() { return mode },

    down: function (t, x, y) {
      mode = "pending"; x0 = x; y0 = y; lastY = y; t0 = t; samples = []; slowSince = -1
      keep(t, x, y)
      return []
    },

    move: function (t, x, y) {
      if (mode === "idle" || mode === "done" || mode === "held") return []
      keep(t, x, y)
      var dx = x - x0, up = y0 - y, out = []
      if (mode === "pending") {
        if (Math.abs(dx) > cfg.slop && Math.abs(dx) > up) mode = "slide"
        else if (up > cfg.slop) mode = "lift"
        else if (-up > cfg.downSlop && -up > Math.abs(dx)) { mode = "done"; return [{ do: "down" }] }
        else return []
      }
      if (mode === "slide") out.push({ do: "slide", phase: "move", dx: dx })
      if (mode === "lift") {
        out.push({ do: "lift", phase: "move", travel: Math.max(0, up), up: up, dx: dx })
        out = out.concat(checkHold(t))
      } else if (mode === "switcher") {
        out.push({ do: "switcher", phase: "update", delta: y - lastY, up: up, dx: dx })
      }
      lastY = y
      return out
    },

    tick: function (t) {
      if (mode === "pending" && t - t0 >= cfg.longPress) { mode = "held"; return [{ do: "longpress" }] }
      var out = checkHold(t)
      if (mode === "switcher" && !out.length) out.push({ do: "switcher", phase: "update", delta: 0 })   // keeps Mission Control's watchdog fed while the finger rests
      return out
    },

    up: function (t, x, y) {
      if (mode === "idle" || mode === "done") return []
      if (mode === "held") { mode = "done"; return [] }
      var out = this.move(t, x, y)
      var v = velocity(), dx = x - x0, was = mode
      mode = "done"
      if (was === "lift") {
        if (travelUp() >= cfg.homeTravel || v.up >= cfg.homeFlick) out.push({ do: "home", velocity: v.up, vx: v.x, dx: dx })
        else out.push({ do: "lift", phase: "end", travel: Math.max(0, travelUp()), velocity: v.up, vx: v.x, dx: dx })
      } else if (was === "switcher") {
        out.push({ do: "switcher", phase: "end", cancelled: false, dx: dx, travel: travelUp() })
      } else if (was === "slide") {
        out.push({ do: "slide", phase: "end", dx: dx })
        var flick = Math.abs(v.x) >= cfg.slideFlick && (v.x > 0) === (dx > 0)
        if (Math.abs(dx) >= cfg.slideCommit || flick) out.push({ do: "app", step: dx > 0 ? -1 : 1 })
      } else if (was === "pending") {
        out.push({ do: "tap" })   // never past the slop: the window bar above the indicator (WindowBar.qml)
      }
      return out
    },

    cancel: function () {
      var was = mode
      mode = "done"
      if (was === "lift") return [{ do: "lift", phase: "cancel" }]
      if (was === "switcher") return [{ do: "switcher", phase: "end", cancelled: true }]
      if (was === "slide") return [{ do: "slide", phase: "end", dx: 0 }]
      return []
    }
  }
}

