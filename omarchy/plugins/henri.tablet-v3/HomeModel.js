.pragma library
// Tablet mode's home screen and home gesture (Home.qml): the geometry, no QML. All in logical px
// of the app area (W × H, the overlay's size); a card's x / y are its centre's offset from the
// area's centre, s its scale. cfg = Theme.core.surface.tablet.home.
// Tests: node tests/home_test.js

// how far past a limit a finger gets: less and less, never more than `limit`
function rubber(x, limit) { return limit * (1 - 1 / (x / limit + 1)) }

// The card under a finger that has come `up` px up (negative: pushed down) and `dx` px sideways,
// moving up at `vy` px/s. As SpringBoard does it: the scale falls linearly with the travel
// (1 − up / (shrinkTravel × H)) down to minScale, then only resists; the bottom edge stays under the
// finger; sideways it follows, damped by up to sideDamp the faster it goes up; rubber-banded where
// `blocked` says there is no app.
function follow(up, dx, W, H, cfg, blocked, vy) {
  var p = Math.max(0, up) / (H * cfg.shrinkTravel)
  var lin = 1 - p
  var s = lin >= cfg.minScale ? lin : cfg.minScale - rubber(cfg.minScale - lin, 0.08)
  var y = H / 2 - Math.max(0, up) - s * H / 2 + (up < 0 ? rubber(-up, cfg.pushDown) : 0)
  var damp = 1 - cfg.sideDamp * Math.max(0, Math.min(1, (vy || 0) / cfg.sideDampSpeed))
  var x = dx * damp
  if (blocked && ((dx > 0 && blocked.left) || (dx < 0 && blocked.right))) x = (dx > 0 ? 1 : -1) * rubber(Math.abs(dx), cfg.sideResist)
  return { s: s, x: x, y: y, progress: p, home: Math.min(1, p * cfg.homeReveal) }
}

// Where a released card goes, as SpringBoard decides it from the finger's last speed (re-read on
// release, so a pause shown earlier does not lock it): "back" | "home" | "switcher" | "next" | "prev".
//   travel up px, dx sideways px, vUp / vx px/s, n apps, cur the card's index, W × H the area
function destination(travel, dx, vUp, vx, n, cur, W, H, cfg, tcfg) {
  var side = Math.abs(dx) > cfg.slideCommit * W
          || (Math.abs(vx) > tcfg.slideFlick && Math.abs(vUp) < cfg.homeSteep * Math.abs(vx) && (vx > 0) === (dx > 0) && Math.abs(dx) > tcfg.slop)
  var step = dx < 0 ? 1 : -1
  if (side && travel < H * cfg.homeDistance / 2 && cur + step >= 0 && cur + step < n) return step > 0 ? "next" : "prev"
  if (travel < cfg.minTravel) return "back"
  if (vUp > cfg.homeVelocity) return "home"
  if (vUp > cfg.homeMinVelocity && vUp > cfg.homeSteep * Math.abs(vx)) return "home"
  if (Math.abs(vUp) < cfg.homeMinVelocity && Math.abs(vx) < cfg.homeMinVelocity) return "switcher"
  if (vUp < -cfg.homeMinVelocity) return "back"
  return travel > cfg.homeDistance * H ? "home" : "back"
}

// the cards beside the one under the finger, at its scale: i - cur places to its right
function besideX(i, cur, s, x, W, cfg) { return x + (i - cur) * (s * W + cfg.cardGap) }

// The App Switcher: a few apps in one larger row, more in two rows; the newest column on the
// right, older ones to the left, scrolling sideways. sx = where the newest column's centre sits.
function switcherGeo(n, W, H, cfg) {
  var rows = n > cfg.oneRow ? 2 : 1
  var s = rows === 2 ? cfg.switcherScale
                     : Math.min(cfg.oneRowScale, (W - 2 * cfg.cardGap - cfg.cardGap * (n - 1)) / Math.max(1, n) / W)
  var cw = s * W, ch = s * H
  var stepX = cw + cfg.cardGap, stepY = ch + cfg.rowGap, cols = Math.ceil(n / rows)
  var edge = W / 2 - cfg.edgeInset - cw / 2
  var span = (cols - 1) * stepX
  // all columns on screen: centred; more: the newest at the right edge, scrolling to the oldest
  var fits = span + cw <= W - 2 * cfg.cardGap + 0.5
  var lo = fits ? span / 2 : edge
  var hi = fits ? span / 2 : span - edge
  return { s: s, rows: rows, stepX: stepX, stepY: stepY, lo: lo, hi: hi, cols: cols }
}
// card i of n (0 = oldest, n-1 = newest)
function switcherPos(i, n, sx, g, cfg) {
  var back = n - 1 - i, k = Math.floor(back / g.rows), r = back % g.rows
  return { x: sx - k * g.stepX, y: g.rows === 1 ? cfg.rowShift : (r === 0 ? -g.stepY / 2 : g.stepY / 2) + cfg.rowShift }
}
// where a scroll lands: momentum, then a whole column
function switcherSnap(sx, velocity, g, cfg) {
  var t = sx + velocity * cfg.switcherMomentum
  return Math.max(g.lo, Math.min(g.hi, g.lo + Math.round((t - g.lo) / g.stepX) * g.stepX))
}
// a finger scrolling the switcher past its ends meets a rubber band
function switcherClamp(sx, g, limit) {
  if (sx < g.lo) return g.lo - rubber(g.lo - sx, limit)
  if (sx > g.hi) return g.hi + rubber(sx - g.hi, limit)
  return sx
}

// The home screen's grid and dock for an area of W × H.
function grid(W, H, cfg) {
  var land = W >= H
  var icon = Math.round(Math.min(W, H) * (land ? cfg.iconShare : cfg.iconSharePortrait))
  var dockIcon = Math.round(icon * cfg.dockIcon)
  var dockH = Math.round(dockIcon * cfg.dockHeight)
  var dockGap = Math.round(icon * cfg.dockGap)
  return {
    cols: land ? cfg.cols : cfg.rows, rows: land ? cfg.rows : cfg.cols,
    icon: icon, dockIcon: dockIcon, dockH: dockH, dockGap: dockGap,
    dockPad: Math.round(dockIcon * cfg.dockPad), dockSpace: Math.round(dockIcon * cfg.dockSpace),
    side: Math.round(W * (land ? cfg.sideShare : cfg.sideSharePortrait)),
    top: Math.round(H * cfg.topShare),
    bottom: dockH + dockGap + cfg.dotsAbove * 2 + cfg.dot,
    perPage: cfg.cols * cfg.rows
  }
}

// the corner radius of a card at scale s morphing (m 0 → 1) into an icon of `iconSize` on screen,
// in the card's own px (it is drawn scaled by s)
function cardRadius(s, m, H, cfg) {
  var r = cfg.cardRadius / Math.max(s, 0.05) * Math.min(1, (1 - s) * 6)
  return (1 - m) * r + m * H * cfg.iconRadius
}
