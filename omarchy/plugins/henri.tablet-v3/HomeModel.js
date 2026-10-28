.pragma library
// Tablet mode's home screen and home gesture (Home.qml): the geometry, no QML. All in logical px
// of the app area (W × H, the overlay's size); a card's x / y are its centre's offset from the
// area's centre, s its scale. cfg = Theme.core.surface.tablet.home.
// Tests: node tests/home_test.js

// how far past a limit a finger gets: less and less, never more than `limit`
function rubber(x, limit) { return limit * (1 - 1 / (x / limit + 1)) }

// The card under a finger that went down `fromBottom` px above the area's bottom edge, has come
// `up` px up (negative: pushed down) and `dx` px sideways. Its bottom edge stays under the finger,
// it shrinks with the travel, x follows 1:1 (rubber-banded where `blocked` says there is no app).
function follow(up, dx, W, H, cfg, blocked) {
  var p = Math.max(0, up) / (H * cfg.shrinkTravel)
  var s = p <= 1 ? 1 - (1 - cfg.minScale) * (1 - Math.pow(1 - p, 2)) : cfg.minScale - rubber(p - 1, 0.08)
  var y = H / 2 - Math.max(0, up) - s * H / 2 + (up < 0 ? rubber(-up, cfg.pushDown) : 0)
  var x = dx
  if (blocked && ((dx > 0 && blocked.left) || (dx < 0 && blocked.right))) x = (dx > 0 ? 1 : -1) * rubber(Math.abs(dx), cfg.sideResist)
  return { s: s, x: x, y: y, progress: p, home: Math.min(1, p * cfg.homeReveal) }
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
