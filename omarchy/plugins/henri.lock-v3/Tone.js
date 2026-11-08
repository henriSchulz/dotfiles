.pragma library
// The lock screen's colours from the wallpaper (design 4B of lab/web/lock2.html): two seeds read
// from the picture's pixels, and the OKLCH arithmetic the lab does with relative colours
// (oklch(from seed L calc(c * k) h)). Pure — node tests/tone_test.js.

function srgbToLinear(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }
function linearToSrgb(v) { return v <= 0.0031308 ? 12.92 * v : 1.055 * Math.pow(v, 1 / 2.4) - 0.055 }

// r, g, b in 0..1 → {l, c, h}
function toOklch(r, g, b) {
  var R = srgbToLinear(r), G = srgbToLinear(g), B = srgbToLinear(b)
  var l = Math.cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B)
  var m = Math.cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B)
  var s = Math.cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B)
  var L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
  var a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
  var bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
  return { l: L, c: Math.sqrt(a * a + bb * bb), h: Math.atan2(bb, a) }
}

function inGamut(v) { return v >= -1e-4 && v <= 1 + 1e-4 }

function oklchToRgb(L, C, h) {
  var a = C * Math.cos(h), b = C * Math.sin(h)
  var l = Math.pow(L + 0.3963377774 * a + 0.2158037573 * b, 3)
  var m = Math.pow(L - 0.1055613458 * a - 0.0638541728 * b, 3)
  var s = Math.pow(L - 0.0894841775 * a - 1.2914855480 * b, 3)
  return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
          -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
          -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s]
}

// OKLCH → [r, g, b] 0..1; out of sRGB the chroma is lowered until it fits (as browsers map it)
function fromOklch(L, C, h) {
  var lin = oklchToRgb(L, C, h)
  for (var i = 0; i < 24 && !(inGamut(lin[0]) && inGamut(lin[1]) && inGamut(lin[2])); i++) {
    C *= 0.85
    lin = oklchToRgb(L, C, h)
  }
  return lin.map(function (v) { return Math.min(1, Math.max(0, linearToSrgb(Math.min(1, Math.max(0, v))))) })
}

function hsv(r, g, b) {
  var mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn, h = 0
  if (d > 0) {
    if (mx === r) h = ((g - b) / d) % 6
    else if (mx === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h /= 6
    if (h < 0) h += 1
  }
  return { h: h, s: mx === 0 ? 0 : d / mx, v: mx }
}

// data: RGBA bytes (Canvas getImageData().data); opts: {bins, minSaturation, minValue}
// → [[r, g, b], [r, g, b]] in 0..1, the two heaviest hue bins (the first twice when only one), or null
function seeds(data, opts) {
  var bins = {}
  for (var i = 0; i + 3 < data.length; i += 4) {
    var r = data[i] / 255, g = data[i + 1] / 255, b = data[i + 2] / 255
    var p = hsv(r, g, b)
    if (p.s < opts.minSaturation || p.v < opts.minValue) continue
    var k = Math.min(opts.bins - 1, Math.floor(p.h * opts.bins)), w = p.s * p.v
    var e = bins[k] || (bins[k] = [0, 0, 0, 0])
    e[0] += r * w; e[1] += g * w; e[2] += b * w; e[3] += w
  }
  var top = Object.keys(bins).map(function (k) { return bins[k] }).sort(function (x, y) { return y[3] - x[3] })
  if (!top.length) return null
  var pick = function (e) { return [e[0] / e[3], e[1] / e[3], e[2] / e[3]] }
  return [pick(top[0]), pick(top[top.length > 1 ? 1 : 0])]
}

// oklch(from seed L calc(c * share) h) → [r, g, b]
function tone(seed, L, share) {
  var o = toOklch(seed[0], seed[1], seed[2])
  return fromOklch(L, o.c * share, o.h)
}

// oklch(from seed L chroma h) — an absolute chroma (the dark ink)
function toneAbs(seed, L, chroma) {
  var o = toOklch(seed[0], seed[1], seed[2])
  return fromOklch(L, chroma, o.h)
}

function hex(rgb) {
  return "#" + rgb.map(function (v) { var s = Math.round(v * 255).toString(16); return s.length < 2 ? "0" + s : s }).join("")
}

if (typeof module !== "undefined") module.exports = { seeds: seeds, tone: tone, toneAbs: toneAbs, toOklch: toOklch, fromOklch: fromOklch, hex: hex }
