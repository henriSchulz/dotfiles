import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import "file:///home/henri/.local/share/velum/qml/Velum"

// What the tablet's Quick Settings show and switch (henri.tablet-v4, phase 4 of docs/TABLET-V4-PLAN.md).
// Faceless; QuickSettings.qml and StatusBar.qml read it, the owner holds one instance:
//
//   QsBackend { id: qsb; live: true; active: shade.shown; velum: <the owner's VelumSettings> }
//
// live     false (the default): every command that would change the system — Wi-Fi, Bluetooth,
//          brightness, volume, mute, the default output / input, Night Light, power, the casting tablet's
//          switches, Wi-Fi / Bluetooth connections —
//          is only logged (`log`, console "qs dry-run: …") and its new state kept here, so the shade
//          behaves the same. The harness and every rig leave it false; only the live plugin sets it.
// active   the shade is on screen: system values are read every surface.material.qs.pages.poll, the
//          notification history and today's battery history too. Closed, nothing polls — the status bar
//          lives on what changes by itself (UPower, NetworkManager, BlueZ, the DND file).
//
// The commands are the control-center-v3 Backend's (plugins share no service objects, omarchy 4.0.6),
// written out as argv so a dry run can print them:
//   Wi-Fi         nmcli radio wifi on|off
//   a network     nmcli connection up|down id SSID; new: nmcli device wifi connect SSID [password …]
//   Bluetooth     omarchy-bluetooth-power on|off; a device: omarchy-bluetooth-device connect|disconnect MAC
//   Airplane      rfkill block|unblock all
//   DND           omarchy-shell notifications setDnd on|off   (henri.notifications-v3's IPC)
//   Night Light   omarchy-toggle-nightlight
//   Dark theme    VelumSettings.set("appearance", "dark"|"light")
//   Power mode    powerprofilesctl set power-saver|balanced|performance   (Battery Saver = power-saver)
//   Auto-rotate   hypr-autorotate lock|unlock; while a tablet casts: touch / rm $XDG_RUNTIME_DIR/ipadcast/rotation-lock
//   Brightness    as control-center-v3: while a tablet casts, its panel follows this machine's backlight
//                 (ipadcast sends it on): brightnessctl -q -d BACKLIGHT set N%; on this machine's own panel
//                 (eDP / LVDS / DSI) the slider is a position on henri.osd-v3's grid (4 extra-dim steps below
//                 the 16 normal ones) and goes to the OSD service as hyprctl dispatch hl.dsp.event("osd set G")
//                 (live: Hyprland.dispatch, no process); else omarchy-brightness-display --no-osd N%
//   Wi-Fi scan    nmcli device wifi rescan when the details open (a read: it runs in a dry run too)
//   Volume, mute  the default sink's audio.volume / audio.muted through Quickshell's PipeWire (live: no process,
//                 every move while a finger drags), logged as wpctl set-volume|set-mute ID …
//   Output        omarchy-audio-output-set-default ID NAME (default sink + the apps' streams move along)
//   Input         pactl set-default-source NAME (only the default: Easy Effects' own capture stays put)
//   Sound settings  uwsm-app -- omarchy-settings open sound (System Settings → Sound)
//   Tablet        hyprctl dispatch hl.dsp.event("ipadcast macinput|perf|fast|mic on|off")   (henri.cast-v3)
//   Power         omarchy-system-lock, systemctl suspend, omarchy-system-logout, omarchy-system-reboot,
//                 omarchy-system-shutdown
//   Settings      uwsm-app -- gtk-launch omarchy-settings.desktop (System Settings)
Item {
  id: root
  visible: false

  property bool live: false
  property bool active: false
  property var velum: null
  readonly property var k: Theme.core.surface.material.qs

  // ---- the command log (dry runs and live ones, and the reads that ask the system for something: `read`),
  // newest last
  property var log: []
  signal ran(var argv, bool wasLive)
  function remember(entry) { log = log.concat([entry]).slice(-60) }   // lint-ok: the log keeps the last 60 commands
  function run(argv, shown) {
    const entry = { at: Date.now(), argv: shown || argv, live: root.live }
    remember(entry)
    if (root.live) Quickshell.execDetached(argv)
    else console.info("qs dry-run: " + entry.argv.join(" "))
    ran(entry.argv, root.live)
  }

  // ---- a switched value shows its new state at once; the system's answer replaces it when it agrees (or
  // after surface.material.qs.tablet.wish). A dry run keeps the wish: nothing on the system changes.
  property var wish: ({})
  property real now: Date.now()
  function want(key, value) {
    const w = Object.assign({}, wish)
    w[key] = { value: value, until: root.live ? Date.now() + k.tablet.wish : Infinity }
    wish = w
  }
  function shown(key, reported) {
    const w = wish[key]
    return w && root.now < w.until ? w.value : reported
  }
  function settle(key, reported) {
    const w = wish[key]
    if (!w || !root.live) return
    if (w.value === reported || Date.now() >= w.until) {
      const x = Object.assign({}, wish)
      delete x[key]
      wish = x
    }
  }

  // ---- Wi-Fi (NetworkManager through Quickshell, no polling, no rescans)
  readonly property var wifiDevice: {
    const devices = Networking.devices ? Networking.devices.values : []
    let fallback = null
    for (let i = 0; i < devices.length; i++) {
      const d = devices[i]
      if (!d || d.type !== DeviceType.Wifi) continue
      if (d.connected) return d
      if (!fallback) fallback = d
    }
    return fallback
  }
  readonly property bool wifiReported: Networking.wifiEnabled
  readonly property bool wifiOn: shown("wifi", wifiReported)
  onWifiReportedChanged: settle("wifi", wifiReported)
  readonly property var wifiRows: {
    const rows = []
    const seen = {}
    const nets = wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
    for (let i = 0; i < nets.length; i++) {
      const n = nets[i]
      if (!n || !n.name || seen[n.name]) continue
      seen[n.name] = true
      rows.push({ name: n.name, connected: !!n.connected, known: !!n.known,
        signal: Math.round((n.signalStrength || 0) * 100),
        secure: n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe })
    }
    // what the last scan found beyond them (nmcli's list; saved = a connection of that name exists)
    for (let i = 0; i < wifiScanned.length; i++) {
      const n = wifiScanned[i]
      if (seen[n.name]) continue
      seen[n.name] = true
      rows.push({ name: n.name, connected: n.connected, known: wifiSaved.indexOf(n.name) >= 0, signal: n.signal, secure: n.secure })
    }
    rows.sort((a, b) => a.connected !== b.connected ? (a.connected ? -1 : 1)
      : a.known !== b.known ? (a.known ? -1 : 1) : b.signal - a.signal)
    return rows
  }
  readonly property string wifiName: {
    for (let i = 0; i < wifiRows.length; i++) if (wifiRows[i].connected) return wifiRows[i].name
    return ""
  }
  function setWifi(on) {
    want("wifi", on)
    run(["nmcli", "radio", "wifi", on ? "on" : "off"])
  }
  // a network row: disconnect the connected one, bring up a known one, join an open one; a new secured one
  // needs `password`
  property string wifiPending: ""
  function wifiActivate(row, password) {
    wifiPending = row.name
    pendingClear.restart()
    if (row.connected) run(["nmcli", "connection", "down", "id", row.name])
    else if (row.known) run(["nmcli", "connection", "up", "id", row.name])
    else if (row.secure) run(["nmcli", "device", "wifi", "connect", row.name, "password", password || ""],
                             ["nmcli", "device", "wifi", "connect", row.name, "password", "***"])
    else run(["nmcli", "device", "wifi", "connect", row.name])
  }

  // ---- Wi-Fi scan: Quickshell shows only what NetworkManager knows, often just the connected network. The
  // details ask for a scan when they open (and by their refresh button): `nmcli device wifi rescan` returns at
  // once and NetworkManager scans in the background, so the list (qs-read wifi: nmcli … --rescan no) is read
  // surface.material.qs.wifi.reads times every .step; "Scanning…" meanwhile. NetworkManager refuses a rescan
  // right after another one (exit code 1): quietly, the list is read once — it is fresh then anyway.
  property var wifiScanned: []            // [{ name, signal, secure, connected }]
  property var wifiSaved: []              // names of the saved Wi-Fi connections
  property bool wifiScanning: false
  property int scanReads: 0               // reads left in this scan
  function wifiRescan() {
    if (wifiScanning || !wifiOn || airplane) return
    wifiScanning = true
    remember({ at: Date.now(), argv: rescanProc.command, live: false, read: true })
    rescanProc.running = true
  }
  Process {
    id: rescanProc
    command: ["nmcli", "device", "wifi", "rescan"]
    onExited: code => {
      root.scanReads = code === 0 ? root.k.wifi.reads : 1
      if (code === 0) scanStep.restart()
      else if (!wifiList.running) wifiList.running = true
    }
  }
  Timer { id: scanStep; interval: root.k.wifi.step; onTriggered: if (!wifiList.running) wifiList.running = true }
  Process {
    id: wifiList
    command: [root.reader, "wifi"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const j = JSON.parse(text)
          const nets = j.networks || []
          if (JSON.stringify(nets) !== JSON.stringify(root.wifiScanned)) root.wifiScanned = nets
          if (JSON.stringify(j.saved || []) !== JSON.stringify(root.wifiSaved)) root.wifiSaved = j.saved || []
        } catch (e) {}
      }
    }
    onExited: {
      root.scanReads--
      if (root.scanReads > 0 && root.wifiScanning) scanStep.restart()
      else root.wifiScanning = false
    }
  }

  // ---- Bluetooth (BlueZ through Quickshell): the paired devices, no discovery
  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property bool btReported: btAdapter ? btAdapter.enabled : false
  readonly property bool btOn: shown("bluetooth", btReported)
  onBtReportedChanged: settle("bluetooth", btReported)
  readonly property var btRows: {
    const rows = []
    const devices = Bluetooth.devices ? Bluetooth.devices.values : []
    for (let i = 0; i < devices.length; i++) {
      const d = devices[i]
      if (!d || !d.address || !(d.paired || d.bonded)) continue
      const name = d.name || d.deviceName || ""
      if (name === "" || name.replace(/-/g, ":") === d.address) continue
      rows.push({ address: d.address, name: name, icon: String(d.icon || ""), connected: !!d.connected })
    }
    rows.sort((a, b) => a.connected !== b.connected ? (a.connected ? -1 : 1) : a.name.localeCompare(b.name))
    return rows
  }
  readonly property string btConnectedName: btRows.length && btRows[0].connected ? btRows[0].name : ""
  function setBluetooth(on) {
    want("bluetooth", on)
    run(["omarchy-bluetooth-power", on ? "on" : "off"])
  }
  property string btPending: ""
  function btActivate(row) {
    btPending = row.address
    pendingClear.restart()
    run(["omarchy-bluetooth-device", row.connected ? "disconnect" : "connect", row.address])
  }
  function btIcon(icon) {
    const i = String(icon || "")
    if (i.indexOf("headset") >= 0 || i.indexOf("headphone") >= 0 || i.indexOf("audio") >= 0) return "headphones"
    if (i.indexOf("mouse") >= 0) return "mouse"
    if (i.indexOf("keyboard") >= 0) return "keyboard"
    if (i.indexOf("computer") >= 0 || i.indexOf("phone") >= 0) return "laptop"
    return "bluetooth"
  }
  Timer { id: pendingClear; interval: root.k.tablet.wish; onTriggered: { root.wifiPending = ""; root.btPending = "" } }

  // ---- this machine's battery for the status bar (UPower: changes arrive by themselves)
  readonly property var upower: UPower.displayDevice
  readonly property bool hasBattery: upower !== null && upower.isLaptopBattery === true
  readonly property real level: upower ? upower.percentage : 1          // 0 … 1
  readonly property bool charging: upower ? upower.state === UPowerDeviceState.Charging : false
  readonly property bool plugged: !charging && UPower.onBattery === false

  // ---- power profile (power-profiles-daemon through Quickshell)
  readonly property string modeReported: PowerProfiles.profile === PowerProfile.PowerSaver ? "saver"
    : PowerProfiles.profile === PowerProfile.Performance ? "performance" : "balanced"
  readonly property string powerMode: shown("mode", modeReported)
  onModeReportedChanged: settle("mode", modeReported)
  function setPowerMode(m) {
    want("mode", m)
    run(["powerprofilesctl", "set", m === "saver" ? "power-saver" : m])
  }

  // ---- Do Not Disturb: henri.notifications-v3 keeps it in ~/.local/state/omarchy/notifications.json
  property bool dndReported: false
  readonly property bool dnd: shown("dnd", dndReported)
  onDndReportedChanged: settle("dnd", dndReported)
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/notifications.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.dndReported = JSON.parse(text() || "{}").dnd === true } catch (e) {} }
  }
  function setDnd(on) {
    want("dnd", on)
    run(["omarchy-shell", "notifications", "setDnd", on ? "on" : "off"])
  }

  // ---- dark theme: Velum's appearance
  readonly property bool dark: Theme.dark
  function setDark(on) {
    const word = on ? "dark" : "light"
    if (root.live && root.velum) {
      root.velum.set("appearance", word)
      remember({ at: Date.now(), argv: ["velum", "set", "appearance", word], live: true })
      return
    }
    // a dry run (or no VelumSettings handed in): only logged; the dry run's own process shows it
    remember({ at: Date.now(), argv: ["velum", "set", "appearance", word], live: false })
    console.info("qs dry-run: velum set appearance " + word)
    if (!root.live) Theme.dark = on
  }


  // ---- polled while the shade is open (qs-read: sysfs battery, rfkill, hyprsunset, brightnessctl, rotation)
  readonly property string reader: String(Qt.resolvedUrl("qs-read")).replace(/^file:\/\//, "")
  property var sys: ({})
  readonly property var battery: sys.battery || null
  readonly property bool airplaneReported: sys.airplane === true
  readonly property bool airplane: shown("airplane", airplaneReported)
  onAirplaneReportedChanged: settle("airplane", airplaneReported)
  readonly property bool nightReported: sys.night === true
  readonly property bool night: shown("night", nightReported)
  onNightReportedChanged: settle("night", nightReported)
  readonly property bool rotationAvailable: sys.rotation === "locked" || sys.rotation === "unlocked"
  readonly property bool rotateReported: sys.rotation === "unlocked"
  readonly property bool rotate: shown("rotate", rotateReported)
  onRotateReportedChanged: settle("rotate", rotateReported)
  // brightness: which way it goes (control-center-v3's Backend: cast / dimAware / omarchy-brightness-display)
  readonly property string panel: sys.internal || ""          // this machine's own panel, "" without one (the M1)
  readonly property string backlight: sys.brightness ? sys.brightness.device : ""
  readonly property string brightPath: castConnected && backlight !== "" ? "cast" : panel !== "" ? "dim" : "display"
  // the OSD's grid from the backlight's raw value (control-center-v3 Backend.gridFromRaw, henri.osd-v3's grid)
  function gridFromRaw(raw, max) {
    const f = raw / max, floor = 0.01, minF = 0.0025       // lint-ok: henri.osd-v3's grid, as control-center-v3
    const l = f < floor - 0.5 / max ? -Math.min(1, Math.log(Math.max(f, 1 / max) / floor) / Math.log(minF / floor))
      : Math.sqrt(Math.max(0, Math.min(1, (f - floor) / (1 - floor))))
    return (l < 0 ? l * 4 + 4 : 4 + l * 16) / 20                // lint-ok: 4 extra-dim + 16 steps (henri.osd-v3)
  }
  readonly property real brightnessReported: !sys.brightness ? 0.5
    : brightPath === "dim" && sys.brightness.max > 0 ? gridFromRaw(sys.brightness.raw, sys.brightness.max)
    : sys.brightness.percent / 100
  property real brightness: 0.5
  property bool brightnessHeld: false   // a finger on the slider: the polls leave it alone
  onBrightnessReportedChanged: if (!brightnessHeld) brightness = brightnessReported
  readonly property var history: sys.history ? (sys.history.akku || []) : []
  readonly property var tabletHistory: sys.history && tabletLog !== "" ? (sys.history[tabletLog] || []) : []
  property bool wantHistory: false        // the Battery or Tablet page is loaded

  function setAirplane(on) {
    want("airplane", on)
    run(["rfkill", on ? "block" : "unblock", "all"])
  }
  function setNight(on) {
    if (on === night) return
    want("night", on)
    run(["omarchy-toggle-nightlight"])
  }
  function setRotate(on) {
    want("rotate", on)
    if (castConnected) run(["bash", "-c", (on ? "rm -f" : "touch") + ' "$XDG_RUNTIME_DIR/ipadcast/rotation-lock"'])
    else run(["hypr-autorotate", on ? "unlock" : "lock"])
  }
  // brightness: every move while live (the OSD's grid by event; a process: one in flight, the latest queued),
  // logged once on release
  function brightCommand(path, v) {
    const pct = Math.max(1, Math.round(v * 100)) + "%"
    if (path === "cast") return ["brightnessctl", "-q", "-d", backlight, "set", pct]
    if (path === "dim") return ["hyprctl", "dispatch", 'hl.dsp.event("osd set ' + v.toFixed(4) + '")']
    return ["omarchy-brightness-display", "--no-osd"].concat(panel !== "" ? ["--monitor", panel] : []).concat([pct])
  }
  property real queued: -1
  function setBrightness(v, final) {
    brightness = Math.max(0, Math.min(1, v))
    const path = brightPath
    const argv = brightCommand(path, brightness)
    if (!root.live) { if (final) run(argv); return }
    if (final) remember({ at: Date.now(), argv: argv, live: true })
    if (path === "dim") {
      Hyprland.dispatch(Hyprland.usingLua ? argv[2] : "event osd set " + brightness.toFixed(4))
      return
    }
    if (brightProc.running) { queued = brightness; return }
    brightProc.command = argv
    brightProc.running = true
  }
  Process {
    id: brightProc
    onExited: if (root.queued >= 0) { const v = root.queued; root.queued = -1; root.setBrightness(v, false) }
  }

  // ---- Sound (PipeWire through Quickshell, as control-center-v3's Backend): the default sink's volume and mute,
  // the outputs and inputs to pick from. PipeWire gives names and descriptions of every node, but its properties
  // only for the nodes it is told to track; what a row needs beyond that (unplugged ports, virtual sinks, the
  // kind of device) comes from pactl's lists, read with the other values while the shade stands open.
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property var source: Pipewire.defaultAudioSource
  PwObjectTracker { objects: root.sink ? [root.sink] : [] }
  readonly property real volumeReported: sink && sink.audio ? Math.max(0, Math.min(1, sink.audio.volume)) : 0
  property real volume: volumeReported      // the slider's value (a finger's while it drags; a dry run keeps it)
  property bool volumeHeld: false           // a finger on a volume slider: the system's value waits
  onVolumeReportedChanged: if (!volumeHeld) volume = volumeReported
  readonly property bool mutedReported: sink && sink.audio ? sink.audio.muted : false
  readonly property bool muted: shown("mute", mutedReported)
  onMutedReportedChanged: settle("mute", mutedReported)
  readonly property bool hasSink: !!sink
  readonly property string volumeIcon: muted || volume <= 0 ? "sound.mute"
    : volume < k.sound.lowShare ? "sound.low" : volume < k.sound.midShare ? "sound.mid" : "sound"
  // what a log line names: the sink's id (wpctl's own words for the same change)
  function sinkTarget() { return sink ? String(sink.id) : "@DEFAULT_AUDIO_SINK@" }
  function setMuted(on) {
    if (on === muted) return
    want("mute", on)
    const argv = ["wpctl", "set-mute", sinkTarget(), on ? "1" : "0"]
    if (!root.live) { run(argv); return }
    if (sink && sink.audio) sink.audio.muted = on
    remember({ at: Date.now(), argv: argv, live: true })
  }
  // every move while live (a property write, no process), logged once on release; moving it up unmutes
  function setVolume(v, final) {
    volume = Math.max(0, Math.min(1, v))
    if (muted && volume > 0) setMuted(false)
    const argv = ["wpctl", "set-volume", sinkTarget(), volume.toFixed(2)]
    if (!root.live) { if (final) run(argv); return }
    if (sink && sink.audio) sink.audio.volume = volume
    if (final) remember({ at: Date.now(), argv: argv, live: true })
  }

  // the default output and input by name; a pick shows at once (want), the system's answer settles it
  readonly property string sinkReported: sink ? sink.name : ""
  readonly property string sinkName: shown("sink", sinkReported)
  onSinkReportedChanged: settle("sink", sinkReported)
  readonly property string sourceReported: source ? source.name : ""
  readonly property string sourceName: shown("source", sourceReported)
  onSourceReportedChanged: settle("source", sourceReported)

  // pactl's sinks / sources by name: unplugged (every port "not available", control-center-v3's `unplugged`),
  // virtual (a null sink: Easy Effects, loopbacks), a microphone chain (a null sink whose monitor is a
  // microphone: Omarchy's Asahi mic), and the words that tell the kind of device
  property var sinkInfo: ({})
  property var sourceInfo: ({})
  function soundInfo(text) {
    const out = {}
    try {
      const list = JSON.parse(String(text || "[]"))
      for (let i = 0; i < list.length; i++) {
        const d = list[i], p = d.properties || {}, ports = d.ports || []
        out[d.name] = {
          unplugged: ports.length > 0 && ports.every(x => String(x.availability || "") === "not available"),
          virtual: String(p["node.virtual"]) === "true" || p["factory.name"] === "support.null-audio-sink",
          micChain: !!p["omarchy.asahi-mic.owner"],
          api: String(p["device.api"] || ""), bus: String(p["device.bus"] || ""),
          words: [p["device.icon_name"], p["device.form_factor"], p["application.name"]].join(" ").toLowerCase()
        }
      }
    } catch (e) {}
    return out
  }
  Process {
    id: sinkInfoProc
    command: ["pactl", "-f", "json", "list", "sinks"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { const i = root.soundInfo(text); if (JSON.stringify(i) !== JSON.stringify(root.sinkInfo)) root.sinkInfo = i }
    }
  }
  Process {
    id: sourceInfoProc
    command: ["pactl", "-f", "json", "list", "sources"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { const i = root.soundInfo(text); if (JSON.stringify(i) !== JSON.stringify(root.sourceInfo)) root.sourceInfo = i }
    }
  }
  function readSound() {
    if (!sinkInfoProc.running) sinkInfoProc.running = true
    if (!sourceInfoProc.running) sourceInfoProc.running = true
  }

  // a row's name as System Settings shows it: the nickname (else the description) without a board code
  // ("MacBook Air J313 Speakers" → "MacBook Air Speakers"), one run-together word split ("AsahiMicrophone")
  function soundLabel(n) {
    if (n.name === "easyeffects_source") return "Easy Effects"
    let d = String(n.nickname || n.description || n.name || "")
    d = d.replace(/\s*\b[JT]\d{3,4}[a-z]?\b/gi, "")
    if (d.indexOf(" ") < 0) d = d.replace(/([a-z])(?=[A-Z][a-z])/g, "$1 ")
    return d.replace(/\s+/g, " ").trim() || String(n.name)
  }
  // its kind (the row's second line) and symbol: a tablet (the casting iPad's ipad_speakers, "iPad Air"),
  // Bluetooth, headphones, a display, USB, else the machine's own
  function soundKind(n, info, output) {
    const w = [n.name, n.description, n.nickname, info ? info.words : ""].join(" ").toLowerCase()
    const plain = output ? "speaker" : "mic"
    const head = /head(phone|set)/.test(w)
    if (w.indexOf("ipad") >= 0 || w.indexOf("tablet") >= 0) return { kind: "Tablet", icon: "tablet" }
    if (String(n.name).indexOf("easyeffects") === 0) return { kind: "Audio effects", icon: plain }
    if ((info && info.api === "bluez5") || String(n.name).indexOf("bluez") === 0) return { kind: "Bluetooth", icon: head ? "headphones" : plain }
    if (head) return { kind: "Headphones", icon: "headphones" }
    if (/hdmi|displayport|video-display/.test(w)) return { kind: "Display", icon: output ? "display" : plain }
    if (info && info.bus === "usb") return { kind: "USB", icon: plain }
    if (info && info.virtual) return { kind: "Virtual", icon: plain }
    return { kind: "Built-in", icon: plain }
  }
  function micChain(n, info) {
    return n.isSink && ((!!source && n.id === source.id) || n.name === sourceName || (!!info && info.micChain))
  }
  // outputs: the sinks that are no stream (the casting iPad's ipad_speakers is one), not Easy Effects' own, no
  // microphone chain, no virtual or unplugged one unless it is the default
  readonly property var sinkRows: {
    const rows = []
    const nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (let i = 0; i < nodes.length; i++) {
      const n = nodes[i]
      if (!n || !n.isSink || n.isStream || !n.audio || n.name === "easyeffects_sink") continue
      const info = sinkInfo[n.name]
      const current = n.name === sinkName
      if (micChain(n, info) || (!current && !!info && (info.unplugged || info.virtual))) continue
      const kind = soundKind(n, info, true)
      rows.push({ id: n.id, name: n.name, label: soundLabel(n), kind: kind.kind, icon: kind.icon, active: current })
    }
    rows.sort((a, b) => a.label.localeCompare(b.label))
    return rows
  }
  // inputs: the sources that are no stream (Easy Effects' own stays: it is the processed microphone — Quickshell
  // gives its Audio/Source/Virtual node no type, pactl lists it), unplugged ones only while they are the default,
  // and a microphone chain (picked by its monitor)
  readonly property var sourceRows: {
    const rows = []
    const nodes = Pipewire.nodes ? Pipewire.nodes.values : []
    for (let i = 0; i < nodes.length; i++) {
      const n = nodes[i]
      const info = !n ? null : n.isSink ? sinkInfo[n.name] : sourceInfo[n.name]
      if (!n || n.isStream || !(n.audio || (!n.isSink && !!info))) continue
      if (n.isSink && !micChain(n, info)) continue
      const current = n.name === sourceName
      if (!current && !n.isSink && !!info && info.unplugged) continue
      const kind = n.isSink ? { kind: "Built-in", icon: "mic" } : soundKind(n, info, false)
      rows.push({ id: n.id, name: n.name, label: soundLabel(n), kind: kind.kind, icon: kind.icon, active: current, monitor: n.isSink })
    }
    rows.sort((a, b) => a.label.localeCompare(b.label))
    return rows
  }
  readonly property string sinkLabel: {
    for (let i = 0; i < sinkRows.length; i++) if (sinkRows[i].active) return sinkRows[i].label
    return sink ? soundLabel(sink) : ""
  }
  function setSink(row) {
    if (row.name === sinkName) return
    want("sink", row.name)
    run(["omarchy-audio-output-set-default", String(row.id), row.name])
  }
  function setSource(row) {
    if (row.name === sourceName) return
    want("source", row.name)
    run(["pactl", "set-default-source", row.monitor ? row.name + ".monitor" : row.name])
  }
  // System Settings on its Sound page (omarchy-settings open AREA: one instance, asked over its IPC)
  function openSoundSettings() { run(["uwsm-app", "--", "omarchy-settings", "open", "sound"]) }

  Process {
    id: stateProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.sys = JSON.parse(text) } catch (e) {} }
    }
    onExited: if (root.readAgain) { root.readAgain = false; root.readState() }
  }
  property bool readAgain: false   // asked while a read ran (a page that wants the history just loaded)
  function readState() {
    if (stateProc.running) { readAgain = true; return }
    stateProc.command = [reader, "state"].concat(wantHistory ? ["--history", "akku"] : [])
      .concat(wantHistory && tabletLog !== "" ? ["--history", tabletLog] : [])
    stateProc.running = true
  }
  function refresh() {
    root.now = Date.now()
    readState()
    readSound()
    if (!notifProc.running) notifProc.running = true
    castFile.reload()
  }
  Timer { interval: root.k.pages.poll; repeat: true; running: root.active; triggeredOnStart: true; onTriggered: root.refresh() }
  onWantHistoryChanged: if (wantHistory && active) readState()

  // ---- the shell's notification history (read only; a swipe or Clear all hides a card here, the files stay)
  property var notifications: []
  property var hidden: ({})
  readonly property var notificationsShown: notifications.filter(n => !hidden[n.id])
  Process {
    id: notifProc
    command: [root.reader, "notifications", Quickshell.env("HOME") + "/.local/state/omarchy/notifications/history"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const list = JSON.parse(text).notifications || []
          // a new object only when something changed (the column keeps its delegates)
          if (JSON.stringify(list) !== JSON.stringify(root.notifications)) root.notifications = list
        } catch (e) {}
      }
    }
  }
  function hide(id) { const h = Object.assign({}, hidden); h[id] = true; hidden = h }
  function hideAll() { const h = Object.assign({}, hidden); notificationsShown.forEach(n => h[n.id] = true); hidden = h }

  // ---- the casting tablet (ipadcast's cast.json, as henri.cast-v3's CastService), read while open
  property var cast: null
  property real castSeen: 0
  readonly property bool castConnected: !!cast && root.now / 1000 - castSeen < k.tablet.stale / 1000
  FileView {
    id: castFile
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/ipadcast/cast.json"
    watchChanges: root.active
    printErrors: false
    onFileChanged: if (root.active) reload()
    onLoaded: {
      let j = null
      try { j = JSON.parse(text() || "null") } catch (e) {}
      root.cast = j
      if (j) root.castSeen = j.time
      root.now = Date.now()
      if (j) ["macInput", "perf", "fast", "mic"].forEach(key => root.settle("tablet." + key, j[key] === true))
    }
    onLoadFailed: root.cast = null
  }
  readonly property bool castOverWifi: castConnected && cast.link !== "cable"
  // its name: ipad-link logs "casting to the NAME" (qs-read tablet), read once per open while one casts
  property string tabletName: "Tablet"
  property string tabletLog: ""           // its battery history's prefix in ~/Projects/akku-test/verlauf
  property bool tabletAsked: false
  function readTablet() {
    if (!root.active || !castConnected || tabletAsked || tabletProc.running) return
    tabletAsked = true
    tabletProc.running = true
  }
  onCastConnectedChanged: { if (!castConnected) tabletAsked = false; readTablet() }
  onActiveChanged: {
    if (active) { readTablet(); return }
    tabletAsked = false
    wifiScanned = []
  }
  Process {
    id: tabletProc
    command: [root.reader, "tablet"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          const j = JSON.parse(text)
          root.tabletName = j.name || "Tablet"
          if ((j.log || "") !== root.tabletLog) { root.tabletLog = j.log || ""; if (root.wantHistory) root.readState() }
        } catch (e) {}
      }
    }
  }
  function tabletOn(key) { return shown("tablet." + key, !!cast && cast[key] === true) }
  function setTablet(key, on) {
    want("tablet." + key, on)
    const word = key === "macInput" ? "macinput" : key
    run(["hyprctl", "dispatch", 'hl.dsp.event("ipadcast ' + word + " " + (on ? "on" : "off") + '")'])
  }

  // ---- power and settings
  readonly property var powerCommands: ({
    lock: ["omarchy-system-lock"], sleep: ["systemctl", "suspend"], logout: ["omarchy-system-logout"],
    restart: ["omarchy-system-reboot"], off: ["omarchy-system-shutdown"] })
  function power(key) { if (powerCommands[key]) run(powerCommands[key]) }
  // System Settings (~/Projects/settings, the dock's omarchy-settings), as the home screen launches an app
  // (Henri 2026-11-12: the gear opened Omarchy's menu)
  function openSettings() { run(["uwsm-app", "--", "gtk-launch", "omarchy-settings.desktop"]) }

  // ---- the tiles in their order (Controls), kept in $XDG_STATE_HOME/velum/tablet-qs.json with the tiles that
  // existed when it was written (`known`): a tile added since joins a saved order after its neighbour in allTiles
  readonly property var allTiles: ["wifi", "bluetooth", "sound", "dnd", "dark", "night", "airplane", "saver", "rotate", "cast"]
  readonly property var v1Tiles: ["wifi", "bluetooth", "dnd", "dark", "night", "airplane", "saver", "rotate", "cast"]   // version 1 had no `known`
  property var tiles: allTiles
  function withNew(order, known) {
    const out = order.filter(x => allTiles.indexOf(x) >= 0)
    for (let i = 0; i < allTiles.length; i++) {
      const t = allTiles[i]
      if (known.indexOf(t) >= 0 || out.indexOf(t) >= 0) continue
      let at = 0
      for (let j = i - 1; j >= 0; j--) if (out.indexOf(allTiles[j]) >= 0) { at = out.indexOf(allTiles[j]) + 1; break }
      out.splice(at, 0, t)
    }
    return out
  }
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/velum"
  FileView {
    id: tileFile
    path: root.stateDir + "/tablet-qs.json"
    printErrors: false
    atomicWrites: true
    onLoaded: {
      try {
        const j = JSON.parse(text() || "{}")
        if (Array.isArray(j.tiles)) root.tiles = root.withNew(j.tiles, Array.isArray(j.known) ? j.known : root.v1Tiles)
      } catch (e) {}
    }
  }
  Process { id: mkdir; command: ["mkdir", "-p", root.stateDir] }
  Component.onCompleted: mkdir.running = true
  function setTiles(order) {
    tiles = order.slice()
    tileFile.setText(JSON.stringify({ version: 2, tiles: tiles, known: allTiles }, null, 2) + "\n")
  }
}
