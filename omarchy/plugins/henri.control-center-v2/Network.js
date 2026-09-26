// Parsing and formatting for the Wi-Fi page's advanced options, mirrored from
// the stock omarchy.network panel's Model.js so the numbers match it.
.pragma library

// `iw` prints non-ASCII SSID bytes as \xNN escapes.
function decodeIwSsid(value) {
  var raw = String(value || "")
  try {
    var encoded = ""
    for (var i = 0; i < raw.length; i++) {
      if (raw[i] === "\\" && raw[i + 1] === "x" && /^[0-9a-f]{2}$/i.test(raw.substring(i + 2, i + 4))) {
        var hex = raw.substring(i + 2, i + 4)
        var byte = parseInt(hex, 16)
        encoded += byte < 32 || byte === 127 ? encodeURIComponent(raw.substring(i, i + 4)) : "%" + hex
        i += 3
      } else {
        encoded += encodeURIComponent(raw[i])
      }
    }
    return decodeURIComponent(encoded)
  } catch (error) {
    return raw
  }
}

// Tab-separated key/value lines from omarchy-network-status / -band.
function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var idx = lines[i].indexOf("\t")
    if (idx === -1) continue
    var key = lines[i].substring(0, idx)
    var value = lines[i].substring(idx + 1)
    next[key] = key === "ssid" ? decodeIwSsid(value) : value.trim()
  }
  return next
}

function appendSample(samples, raw, limit) {
  var values = Array.isArray(samples) ? samples.slice() : []
  var n = parseFloat(raw)
  values.push(isFinite(n) && n >= 0 ? n : null)
  while (values.length > limit) values.shift()
  return values
}

function averageLatency(samples, limit) {
  var total = 0
  var count = 0
  for (var i = Math.max(0, samples.length - limit); i < samples.length; i++) {
    if (typeof samples[i] !== "number") continue
    total += samples[i]
    count++
  }
  return count > 0 ? total / count : -1
}

function packetLoss(samples) {
  if (!samples.length) return 0
  var lost = 0
  for (var i = 0; i < samples.length; i++) if (samples[i] === null) lost++
  return Math.round(lost / samples.length * 100)
}

function formatBytes(bytes) {
  var n = Number(bytes)
  if (!isFinite(n) || n < 0) n = 0
  if (n < 1024) return Math.round(n) + " B"
  if (n < 1024 * 1024) return (n / 1024).toFixed(1).replace(".", ",") + " KB"
  if (n < 1024 * 1024 * 1024) return (n / (1024 * 1024)).toFixed(1).replace(".", ",") + " MB"
  return (n / (1024 * 1024 * 1024)).toFixed(2).replace(".", ",") + " GB"
}

function formatRate(bytesPerSec) {
  return formatBytes(bytesPerSec) + "/s"
}

function formatPing(ms) {
  return ms < 0 ? "--" : Math.round(ms) + " ms"
}

function formatFreq(mhz) {
  var v = parseFloat(mhz)
  if (!v) return ""
  if (v >= 2400 && v < 2500) return "2.4 GHz"
  if (v >= 4900 && v < 5925) return "5 GHz"
  if (v >= 5925 && v < 7125) return "6 GHz"
  return (v / 1000).toFixed(1).replace(".", ",") + " GHz"
}

function bandLabel(band) {
  if (band === "auto") return "Auto"
  return String(band).replace(".", ",") + " GHz"
}
