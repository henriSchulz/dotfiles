.pragma library
// The App Switcher's and the gesture navigation's arithmetic, pure (no QML), so node can test it
// (tests/switcher-harness/nav_test.js). After lab/mui-material src/Switcher.jsx and Launcher.jsx.
// `cfg` is Theme.core.surface.material.switcher.

// past an end something gives way less and less, never more than `limit` (lab model.js rubber)
function rubber(x, limit) { return limit <= 0 ? 0 : limit * (1 - 1 / (x / limit + 1)) }

// a finger's samples [[ms, x, y], …]: keep at least two, drop the ones older than `window` ms
function trim(samples, now, window) {
  var out = samples.slice()
  while (out.length > 2 && now - out[0][0] > window) out.shift()
  return out
}

// its speed in px/s over the samples; 0 when the last one is older than `window` (it rested)
function velocity(samples, now, window) {
  if (!samples || samples.length < 2) return { x: 0, y: 0 }
  var a = samples[0], b = samples[samples.length - 1]
  if (now - b[0] > window || b[0] <= a[0]) return { x: 0, y: 0 }
  var dt = (b[0] - a[0]) / 1000
  return { x: (b[1] - a[1]) / dt, y: (b[2] - a[2]) / dt }
}

// the row: card i's centre sits at W/2 + (i − (n − 1)) · step + offset, so offset 0 puts the newest
// (last) card in the middle and offset (n − 1) · step the oldest
function bounds(n, step) { return { lo: 0, hi: Math.max(0, (n - 1) * step) } }
function slot(i, n, step) { return (i - (n - 1)) * step }

// the row under a finger: 1:1, with give past either end
function follow(from, dx, lo, hi, limit) {
  var v = from + dx
  if (v < lo) return lo - rubber(lo - v, limit)
  if (v > hi) return hi + rubber(v - hi, limit)
  return v
}

// let go: carried on by the speed (a fling), then the nearest card
function settle(x, vx, step, lo, hi, project) {
  if (step <= 0) return lo
  var to = Math.round((x + vx * project) / step) * step
  return Math.max(lo, Math.min(hi, to))
}

// the card nearest the middle at this offset (its index), for tests and the owner
function centred(x, n, step) {
  if (n <= 0 || step <= 0) return -1
  return Math.max(0, Math.min(n - 1, n - 1 - Math.round(x / step)))
}

// what a moving finger is doing, once it has left the slop: "lift" (up on a card) or "row"
function classify(dx, dy, slop, onCard) {
  if (Math.sqrt(dx * dx + dy * dy) <= slop) return ""
  return Math.abs(dy) > Math.abs(dx) && dy < 0 && onCard ? "lift" : "row"
}

// a card pushed up and let go: closed when far (share of its height) or flicked up, else back
function lifted(dy, vy, cardH, cfg) {
  return (-dy > cardH * cfg.cardDismiss || vy < -cfg.flick) ? "close" : "back"
}

// gesture navigation: how far the switcher has come with a finger `travel` px up a screen `height` tall
function pull(travel, height, reach) {
  if (height <= 0 || reach <= 0) return 0
  return Math.max(0, Math.min(1, travel / (height * reach)))
}

// the finger let go: "home" (a fast flick up, only when there is a way home), "switcher" (up far
// enough: it settles open), else "back" (it sinks away). vy in px/s, negative = up.
function decide(travel, vy, wayHome, nav) {
  if (vy < -nav.homeFlick && wayHome) return "home"
  if (travel > nav.travel) return "switcher"
  return "back"
}
