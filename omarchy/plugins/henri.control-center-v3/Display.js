// Scale helpers, mirrored from the stock omarchy.monitor panel's Model.js so
// the presets here match what `omarchy-hyprland-monitor-scaling` will apply.
.pragma library

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

function gcd(a, b) {
  while (b) {
    var r = a % b
    a = b
    b = r
  }
  return a
}

// Hyprland only accepts scales that divide the mode into whole logical pixels
// (in 1/120 steps); round a requested scale up to the nearest clean one.
function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var w = Number(width)
  var h = Number(height)
  if (!isFinite(requested) || !isFinite(w) || !isFinite(h) || requested <= 0 || w <= 0 || h <= 0) return ""
  var divisor = gcd(Math.round(w * 120), Math.round(h * 120))
  var units = Math.round(requested * 120)
  if (units > divisor) units = divisor
  while (divisor % units !== 0) units++
  return normalizeScale(units / 120)
}

// Presets that land on distinct effective scales for this mode.
function availableScales(scales, width, height) {
  if (Number(width) <= 0 || Number(height) <= 0) return scales
  var seen = {}
  var out = []
  for (var i = 0; i < scales.length; i++) {
    var effective = cleanScale(scales[i], width, height)
    if (effective === "" || seen[effective]) continue
    seen[effective] = true
    out.push(scales[i])
  }
  return out
}

function isActiveScale(preset, current, width, height) {
  return current !== "" && cleanScale(preset, width, height) === normalizeScale(current)
}

// "1536 × 960" — the logical size a preset gives, i.e. what it "looks like".
function looksLike(scale, width, height) {
  var s = Number(cleanScale(scale, width, height))
  if (!isFinite(s) || s <= 0) return ""
  return Math.round(width / s) + " × " + Math.round(height / s)
}

function formatScale(scale) {
  return String(normalizeScale(scale)).replace(".", ",") + "×"
}

function parseDisplays(raw) {
  try {
    var list = JSON.parse(String(raw || "[]"))
    return Array.isArray(list) ? list : []
  } catch (e) {
    return []
  }
}
