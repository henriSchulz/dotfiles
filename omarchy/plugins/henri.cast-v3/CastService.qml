import QtQuick
import Quickshell
import Quickshell.Io

// Everything the tablet panel knows: what the tablet that shows this Mac (mac-cast on the tablet,
// ipadcast here) and the stream report, and what can be switched on it. Faceless — the bar's
// island (Panel.qml) and the Control Center in tablet mode (henri.control-center-v3
// FullCenter.qml) each load their own instance and show CastPages over it.
//
//   CastService { id: castSvc; opened: <the pages are on screen> }
//   CastPages { svc: castSvc }
//
// ipadcast writes it all to $XDG_RUNTIME_DIR/ipadcast/cast.json every 2 s and removes the file
// when the tablet goes.
Item {
  id: svc
  visible: false
  // the pages are on screen: every report is taken, not only what the bar shows
  property bool opened: false

  // ipadcast rewrites the file every 2 s. A new info object re-renders the shell's layers even
  // when nothing visible changed, and every such frame goes to the tablet through zcast's encoder
  // (m1-power, 2026-10-27: a burst of ~5 frames every 2 s on a still screen). So while the pages
  // are closed info only changes with what the bar shows; seen keeps the connection alive.
  property var info: null
  property var latest: null
  property real seen: 0
  property real now: Date.now() / 1000
  readonly property bool connected: !!info && now - seen < 8
  readonly property var i: info || ({})
  FileView {
    id: infoFile
    property bool missing: true
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/ipadcast/cast.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      let j = null
      try { j = JSON.parse(text() || "null") } catch (e) {}
      svc.latest = j
      missing = false
      if (!j) { svc.info = null; return }
      svc.seen = j.time
      const was = svc.info
      if (svc.opened || !was || Math.round(j.battery) !== Math.round(was.battery) || j.state !== was.state)
        svc.info = j
    }
    onLoadFailed: { svc.info = null; missing = true }
  }
  // a watch can't see a file that does not exist yet (nor its removal for sure): look again
  // now and then; the clock ends a connection whose reports stopped
  Timer {
    interval: 2000; repeat: true; running: true
    onTriggered: {
      svc.now = Date.now() / 1000
      if (infoFile.missing || !svc.connected) infoFile.reload()
    }
  }
  // opened: the latest report at once, not the one the bar last kept
  onOpenedChanged: if (opened && latest) info = latest

  readonly property real batteryFraction: connected && info.battery !== null ? Math.max(0, Math.min(1, info.battery / 100)) : 0
  readonly property bool charging: connected && info.state === "Charging"
  readonly property bool plugged: connected && (info.state === "Full" || info.state === "Not")
  readonly property string pctText: Math.round(batteryFraction * 100) + " %"
  function watts() { return connected ? Math.abs(info.watts).toFixed(1) + " W" : "—" }
  function statusText() {
    if (!connected) return ""
    if (charging) return "Charging · " + watts()
    if (plugged) return "On Power · " + watts()
    return "On Battery · " + watts()
  }
  function rate(kbit) { return kbit >= 1000 ? (kbit / 1000).toFixed(1) + " Mbit/s" : Math.round(kbit) + " kbit/s" }
  function setBrightness(v) {
    Quickshell.execDetached(["brightnessctl", "-q", "-c", "backlight", "set", Math.max(1, Math.round(v * 100)) + "%"])
  }
  // ipadcast hears this on Hyprland's event socket and hands it to the tablet
  function setKeyboardLight(on) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.event(\"ipadcast kbdlight " + (on ? "on" : "off") + "\")"])
  }
  // this Mac's own keyboard and trackpad ("mac") or the tablet's cover ("tablet"); ipadcast turns
  // both on again when the tablet connects anew
  // Power Mode: smoothness over battery, kept until switched off (ipadcast, type 10 to the tablet)
  function setPerf(on) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.event(\"ipadcast perf " + (on ? "on" : "off") + "\")"])
  }
  // the iPad's Wi-Fi session ends (ipad-link: SIGUSR1); the iPad's own home offers it again
  function endWifi() {
    Quickshell.execDetached(["systemctl", "--user", "kill", "--kill-whom=main", "-s", "USR1", "ipad-link.service"])
  }
  // Fast Mode: a smaller stream (the tablet scales it up), a few ms less latency (ipadcast, "fast" in cast.json)
  function setFast(on) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.event(\"ipadcast fast " + (on ? "on" : "off") + "\")"])
  }
  // the tablet's microphone as this Mac's input, kept until switched off (ipadcast, type 11 to the tablet)
  function setMic(on) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.event(\"ipadcast mic " + (on ? "on" : "off") + "\")"])
  }
  function setInput(which, on) {
    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.event(\"ipadcast " + which + "input " + (on ? "on" : "off") + "\")"])
  }

  // a tile shows its new state at the click: the tablet answers only in its next report (every
  // 2 s, its cover a round later). The wish stands until a report agrees, at most 6 s
  property var pending: ({})
  function want(key, on) {
    const p = Object.assign({}, pending)
    p[key] = { on: on, until: Date.now() / 1000 + 6 }
    pending = p
  }
  function tileOn(key, reported) {
    const p = pending[key]
    return p && now < p.until ? p.on : reported
  }
  onInfoChanged: {
    const r = { mac: i.macInput !== false, tablet: i.tabletInput === true, light: i.kbdlight === true,
      perf: i.perf === true, fast: i.fast === true, mic: i.mic === true }
    const p = {}
    let changed = false
    for (const k in pending) {
      if (pending[k].on === r[k] || now >= pending[k].until) changed = true
      else p[k] = pending[k]
    }
    if (changed) pending = p
  }
}
