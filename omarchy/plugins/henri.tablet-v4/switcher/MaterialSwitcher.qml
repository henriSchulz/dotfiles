import QtQuick
import Quickshell
import Quickshell.Hyprland
import "file:///home/henri/.local/share/velum/qml/Velum"
import "Nav.js" as Nav
import "../Resample.js" as Resample

// henri.tablet-v4's App Switcher — Android Recents on a tablet (lab/mui-material src/Switcher.jsx):
// the open windows as one row of cards, the newest on the right and in the middle, each with its real
// picture (ScreencopyView, one capture per open), its app's icon and name above it. One finger, one
// gesture: sideways the row follows it 1:1, a release carries on (fling) and settles on the nearest
// card on a spring, with give past the ends; up on a card pushes it away (far or fast: closed, it flies
// off and the others close the gap; else it drops back); a tap on a card switches to it, a tap beside
// or Escape closes; Clear all closes every window. Values: Theme.core.surface.material.switcher.
//
// API (the owner — Home/Tablet — drives it; integration comes later):
//   anchors.fill: <the screen's overlay>     it takes the whole screen; the size is the screen's
//   progress: real 0 … 1    how far it is there. The owner moves it: a finger from the bottom strip
//                           (NavGesture.pull) while dragging, then 1 (open) or 0 (closed). Driven or
//                           not, the row rises and fades with it (entrance follows the finger).
//   dragging: bool          a finger of the owner drives `progress`: follow it tightly, take no touch
//   screenName: string      only that monitor's windows ("" = every monitor)
//   backdrop: Component     optional, under the scrim (e.g. a cached blurred wallpaper copy); never
//                           a live blur of moving content
//   appFor: function(cls)   optional → { name, icon } for a window class (default: DesktopEntries)
//   signal switchTo(string address)    a card was tapped: focus that window, then set progress 0
//   signal closeWindow(string address) a card was pushed away (or Clear all): close that window — sent
//                                      once the card has flown off (the picture would die with it)
//   signal closed()                    a tap beside, Escape, or after Clear all: set progress 0
//   press(x, y) / drag(x, y) / lift() / cancel()   a finger in this item's coordinates, for an owner
//                           that routes touch itself (edge socket, rig); the item has its own
//                           MouseArea + MultiPointTouchArea otherwise
//   warm: bool             a finger is on the gesture strip: build the cards and take their pictures
//                           now, while nothing moves (made at the gesture's first frame, they cost it
//                           ~80 ms); warm alone shows nothing and takes no input
//   open (read only)        content is shown (progress > 0 or still settling); closed = a Loader
//                           with nothing in it (or only warm), no frames
//   takeHand(rect, address, others) over an app the owner's own card was pulled up and rests at `rect` (this
//                           item's coordinates): the switcher stands at once, that window's card flies
//                           from there into its place, the rest fades in — one movement, no second
//                           entrance. signal handTaken() once its card is there: hide the owner's
//   info()                  state for tests: { open, n, offset, centred, windows: [{address, name}] }
Item {
  id: sw

  property real progress: 0
  property bool dragging: false
  property string screenName: ""
  property Component backdrop: null
  property var appFor: null
  property bool warm: false
  // keep the cards made between opens (tablet mode): made at the open, their pictures were not there in
  // time for a hand-over (the Home button) and an icon placeholder flew. Kept, an open starts on the
  // last pictures and asks for fresh ones (as henri.tablet-v3's cards do). Made again keepAfter after a
  // close, when nothing moves
  property bool keep: false
  property bool kept: false
  Timer {
    id: keepLater
    interval: sw.cfg.keepAfter
    running: sw.keep && !sw.kept && !sw.shows && !sw.warm
    onTriggered: { sw.handedOff = false; sw.kept = true }
  }
  onKeepChanged: if (!keep) kept = false
  onHandedOffChanged: if (handedOff) kept = false       // after a launch the row is made again later
  // an open (a finger on the edge, or shown): the kept row takes the windows and pictures of now
  property bool fresh: false
  function wake() { if (fresh) return; fresh = true; if (body.item) body.item.reopen() }
  onShowsChanged: { if (shows) wake(); else if (!warm) fresh = false }
  // how long the grown card stays after the switch (the owner knows whether Hyprland slides)
  property int handoff: cfg.launchHandoff

  signal switchTo(string address)
  signal closeWindow(string address)
  signal closed()
  signal handTaken()

  readonly property var cfg: Theme.core.surface.material.switcher
  readonly property var tt: Theme.core.surface.tablet
  readonly property string family: Theme.core.surface.material.widgets.font[0]
  readonly property bool shows: sw.holding || sw.progress > 0 || enter.moving || enter.value > 0.002
  readonly property bool open: body.active && shows
  // opening an app holds the switcher as it is until the window stands under the grown card
  property bool holding: false
  // …and then goes at once (the window stands where the card was): no sinking back over it
  property bool handedOff: false
  onProgressChanged: {
    if (progress > 0 && !holding) handedOff = false
    if (progress <= 0) pendingHand = null
  }
  // warm lingers a moment: the finger's lift ends it just before the owner opens the switcher
  onWarmChanged: {
    if (warm && !holding) handedOff = false
    if (warm) wake()
    else { warmLinger.restart(); if (!shows) fresh = false }
  }
  Timer { id: warmLinger; interval: Theme.dur("fast") }
  // what shows: the spring's value (tight while a finger drives, Material's settle once it lets go)
  readonly property real shown: holding ? 1 : Math.max(0, Math.min(1, enter.value))

  Spring {
    id: enter
    preset: sw.dragging ? Theme.spring("interactive") : sw.cfg.enterSpring
    reduced: Theme.reduceMotion
    target: Math.max(0, Math.min(1, sw.progress))
  }

  function press(x, y) { if (body.item) body.item.press(x, y) }
  function drag(x, y) { if (body.item) body.item.move(x, y) }
  function lift() { if (body.item) body.item.release() }
  function cancel() { if (body.item) body.item.cancel() }
  function info() { return body.item ? body.item.info() : { open: false, n: 0 } }
  // a hand-over waiting for the content (the Loader builds asynchronously)
  property var pendingHand: null
  // others: [{ address, rect }] the owner's neighbour cards beside it — they fly into their places too
  function takeHand(rect, address, others) {
    pendingHand = { rect: rect, address: String(address || ""), others: others || [] }
    if (body.item && body.status === Loader.Ready) body.item.takeHand()
  }

  // ---- the windows: Hyprland's toplevels, refreshed on its events (their IPC objects carry the
  // focus history, workspace and monitor)
  // the desktop entries load on first use, asynchronously: start that now, not at the first open
  Component.onCompleted: { Hyprland.refreshToplevels(); sw.entries = DesktopEntries.applications.values.length }
  property int entries: 0
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var n = event.name
      if (n === "openwindow" || n === "closewindow" || n === "activewindowv2" || n === "movewindowv2") refresh.restart()
    }
  }
  Timer { id: refresh; interval: Theme.dur("fast"); onTriggered: Hyprland.refreshToplevels() }

  function monitorName(id) {
    var mons = Hyprland.monitors.values
    for (var i = 0; i < mons.length; i++) if (mons[i].id === id) return mons[i].name
    return ""
  }
  // where the window stands on its screen (logical px from the screen's top left): a launched card
  // lands there — under the status bar a window is shorter than the screen
  function placeOf(o) {
    var mons = Hyprland.monitors.values, mx = 0, my = 0
    for (var i = 0; i < mons.length; i++) if (mons[i].id === o.monitor) { var m = mons[i].lastIpcObject; mx = m ? m.x || 0 : 0; my = m ? m.y || 0 : 0 }
    if (!o.at || !o.size || !(o.size[0] > 0) || !(o.size[1] > 0)) return null
    return Qt.rect(o.at[0] - mx, o.at[1] - my, o.size[0], o.size[1])
  }
  function appOf(cls, title) {
    if (sw.appFor) { var r = sw.appFor(cls); if (r) return r }
    var e = null
    try { e = DesktopEntries.byId(cls) || DesktopEntries.heuristicLookup(cls) } catch (err) {}
    var icon = e && e.icon ? Quickshell.iconPath(e.icon, true) : ""
    if (!icon) icon = Quickshell.iconPath(String(cls || "").toLowerCase(), true)
    return { name: e && e.name ? e.name : String(title || cls || ""), icon: icon }
  }
  // oldest first (left), newest last (right): Hyprland's focus history, 0 = the focused window
  function scan() {
    var tl = Hyprland.toplevels.values, out = []
    for (var i = 0; i < tl.length; i++) {
      var t = tl[i], o = t.lastIpcObject
      if (!o || !o.address || o.mapped === false || o.hidden) continue
      if (o.workspace && String(o.workspace.name || "").indexOf("special:") === 0) continue
      if (sw.screenName && monitorName(o.monitor) !== sw.screenName) continue
      var app = appOf(o.class, o.title)
      out.push({ address: String(o.address), toplevel: t, name: app.name, icon: app.icon, place: placeOf(o),
                 focus: typeof o.focusHistoryID === "number" ? o.focusHistoryID : Number.MAX_SAFE_INTEGER })
    }
    out.sort(function (a, b) { return b.focus - a.focus })
    return out
  }

  Loader {
    id: body
    anchors.fill: parent
    active: !sw.handedOff && (sw.shows || sw.warm || warmLinger.running || sw.kept)
    // made over a few frames: built at a finger's touch, a blocking build held the gesture's first moves
    asynchronous: true
    sourceComponent: content
  }

  Component {
    id: content
    Item {
      id: root
      focus: true
      Keys.onEscapePressed: sw.closed()

      // taken once per open: the row never reorders under a finger
      property var windows: []
      Component.onCompleted: {
        windows = sw.scan(); forceActiveFocus()
        sw.fresh = sw.shows || sw.warm               // made ahead (kept): the next open takes fresh pictures
        // a hand-over waits (the Home button: nothing warmed the cards): stand still and show nothing
        // until it is taken — rising meanwhile was a second movement before the card's (Henri 2026-11-12)
        if (sw.pendingHand) { takenOver = true; handS.snap(1); handWait.start() }
      }
      readonly property int n: windows.length
      readonly property real cardH: height * sw.cfg.cardShare
      readonly property real cardW: cardH * (width / Math.max(1, height))
      readonly property real step: cardW + sw.cfg.cardGap
      readonly property var range: Nav.bounds(n, step)
      readonly property real p: sw.shown
      // a kept row at a new open: the windows of now (delegates of known windows stay, with their
      // last picture until the fresh one comes), nothing left over from the last open
      function reopen() {
        windows = sw.scan()
        rowX.snap(0)
        launching = -1; handed = false; launchS.snap(0)
        takenOver = false; handAddress = ""; handOthers = ({}); rowY = 0; rowScale = 1
        for (var i = 0; i < n; i++) { var c = cardItem(i); if (c) { c.launch = 0; c.lifted = false; c.refresh() } }
        forceActiveFocus()
      }
      // ---- taken over from the owner's card: the row stands (no rise), that card flies into its place
      property bool takenOver: false
      property string handAddress: ""
      property var handOthers: ({})          // address → true: neighbours handed over with it
      // the row's height on screen: a handed card stays at the height the finger left it (it only grows
      // to the row's size about its own middle). Moving it to the middle of the screen took it down
      // again after the finger had brought it up (Henri 2026-11-12). Within the screen: header to Clear all
      property real rowY: 0
      // …and its size: the row takes the handed card's size, so nothing moves at the hand-over (it grew
      // to the row's size about its middle, and its lower edge still went down, Henri 2026-11-12)
      property real rowScale: 1
      function rowYFor(cy, k) {
        var lo = -(height / 2 - k * (cardH / 2 + sw.cfg.headerHeight + sw.cfg.headerGap))
        var hi = height / 2 - k * (cardH / 2 + sw.cfg.clearTop + sw.cfg.clearHeight)
        return Math.max(lo, Math.min(hi, cy - height / 2))
      }
      Spring { id: handS; preset: sw.cfg.enterSpring; reduced: Theme.reduceMotion; target: 0 }
      readonly property real hand: takenOver ? handS.value : 0
      Connections { target: sw; function onProgressChanged() { if (sw.progress <= 0) root.takenOver = false } }
      // its card and its picture first (the Home button warms nothing: an icon placeholder stood
      // full screen for a moment); at most handWait, then it goes as it is
      Timer { id: handWait; interval: Theme.dur("fast") / 8; repeat: true; property real since: 0
              onRunningChanged: if (running) since = Date.now()
              onTriggered: root.takeHand() }
      function takeHand() {
        var h = sw.pendingHand
        if (!h) { handWait.stop(); return }
        var c = null
        for (var i = 0; i < n; i++) if (windows[i].address === h.address && cardItem(i)) c = cardItem(i)
        var ready = c && c.hasPicture
        if (!ready && n > 0 && Date.now() - handWait.since < sw.cfg.handWait) { if (!handWait.running) handWait.start(); return }
        handWait.stop()
        sw.pendingHand = null
        // that card in the middle of the row
        var at = -1
        for (var j = 0; j < n; j++) if (windows[j].address === h.address) at = j
        var k = Math.max(sw.cfg.handScaleMin, Math.min(sw.cfg.handScaleMax, h.rect.width / Math.max(1, cardW)))
        rowScale = k
        // centred on the card, scaled about the screen's middle: the card's middle stays where it is
        rowX.snap((at >= 0 ? -Nav.slot(at, n, step) : 0) + (h.rect.x + h.rect.width / 2 - width / 2) / k)
        rowY = rowYFor(h.rect.y + h.rect.height / 2, k)
        handAddress = h.address
        takenOver = true
        if (c) {
          // its place in the row, without the hand's own transform (it may stand at 1 already)
          c.handFrom = c.parent.mapToItem(root, c.x, c.y)
          c.handRect = h.rect
          var map = {}
          for (var k = 0; k < h.others.length; k++) {
            var o = h.others[k]
            for (var m = 0; m < n; m++) {
              var oc = cardItem(m)
              if (!oc || windows[m].address !== o.address || o.address === h.address) continue
              oc.handFrom = oc.parent.mapToItem(root, oc.x, oc.y)
              oc.handRect = o.rect
              map[o.address] = true
            }
          }
          handOthers = map
          handS.snap(1)
          handS.from(1)
        } else handS.snap(0)
        sw.handTaken()
      }

      // the row's offset: 1:1 under a finger, a spring after it
      Spring { id: rowX; preset: sw.cfg.rowSpring; reduced: Theme.reduceMotion; target: 0 }
      function settle(to, v) {
        rowX.velocity = v
        if (rowX.target !== to) rowX.target = to
        else if (rowX.value !== to) rowX.anim.start()
      }
      onRangeChanged: if (!g && rowX.target > range.hi) settle(range.hi, 0)

      function cardItem(i) { return cards.itemAt(i) }
      function cardAt(x, y) {
        for (var i = n - 1; i >= 0; i--) {
          var c = cardItem(i)
          if (!c || c.away) continue
          var pt = c.mapFromItem(root, x, y)
          if (c.contains(pt)) return i
        }
        return -1
      }
      function onClear(x, y) {
        if (!clear.visible) return false
        var pt = clear.mapFromItem(root, x, y)
        return clear.contains(pt)
      }

      // ---- one finger
      property var g: null
      property real lastFling: 0
      // touches from the iPad cast come in steps (~44 ms): moves glide one per frame (Resample.js, fed
      // by rowFeed); the real last point goes in before the lift
      property var rs: null
      property real fx: 0
      property real fy: 0
      property real rx: 0
      property real ry: 0
      function move(x, y) { if (!g || !rs) return; rx = x; ry = y; rs.push(Date.now(), x, y) }
      function feed() {
        var a = rs ? rs.at(Date.now()) : null
        if (a && (a.x !== fx || a.y !== fy)) { fx = a.x; fy = a.y; moveNow(a.x, a.y) }
      }
      FrameAnimation { id: rowFeed; running: root.g !== null; onTriggered: root.feed() }
      function press(x, y) {
        if (sw.dragging) return
        rs = Resample.create(sw.tt.cast.resampleMinGap, sw.tt.cast.resampleMaxGap)
        rs.push(Date.now(), x, y); fx = x; fy = y; rx = x; ry = y
        rowX.snap(rowX.value)
        var c = onClear(x, y) ? -2 : cardAt(x, y)
        g = { x0: x, y0: y, from: rowX.value, kind: c === -2 ? "clear" : "", card: c, samples: [[Date.now(), x, y]] }
        clear.down = c === -2
      }
      function moveNow(x, y) {
        if (!g) return
        var t = Date.now()
        g.samples = Nav.trim(g.samples.concat([[t, x, y]]), t, sw.cfg.sampleWindow)
        var dx = x - g.x0, dy = y - g.y0
        if (g.kind === "clear") { clear.down = onClear(x, y); return }
        if (!g.kind) {
          g.kind = Nav.classify(dx, dy, sw.cfg.slop, g.card >= 0)
          if (g.kind === "lift") { var c0 = cardItem(g.card); if (c0) c0.lifted = true }
        }
        // the row's own units (it may stand scaled, rowScale)
        if (g.kind === "row") rowX.snap(Nav.follow(g.from, dx / rowScale, range.lo, range.hi, width * sw.cfg.rowRubber))
        else if (g.kind === "lift") { var c = cardItem(g.card); if (c) c.follow(Math.min(0, dy) / rowScale) }
      }
      function release() {
        if (g && (rx !== fx || ry !== fy)) moveNow(rx, ry)
        var d = g
        g = null
        if (!d) return
        clear.down = false
        var v = Nav.velocity(d.samples, Date.now(), sw.cfg.sampleWindow)
        if (d.kind === "clear") { var last = d.samples[d.samples.length - 1]; if (onClear(last[1], last[2])) clearAll(); return }
        if (!d.kind) {                                   // a tap: a card switches, beside it closes
          if (d.card >= 0 && windows[d.card]) launchAt(d.card)
          else sw.closed()
          return
        }
        lastFling = v.x
        if (d.kind === "row") { settle(Nav.settle(rowX.value, v.x / rowScale, step, range.lo, range.hi, sw.cfg.flingProject), v.x / rowScale); return }
        var c = cardItem(d.card)
        if (!c) return
        c.lifted = false
        if (Nav.lifted(c.y - (height / 2 - cardH / 2), v.y / rowScale, cardH, sw.cfg) === "close") closeAt(d.card, v.y / rowScale)
        else c.drop(v.y / rowScale)
      }
      function cancel() {
        var d = g
        g = null
        clear.down = false
        if (!d) return
        if (d.kind === "row") settle(Nav.settle(rowX.value, 0, step, range.lo, range.hi, 0), 0)
        else if (d.kind === "lift") { var c = cardItem(d.card); if (c) { c.lifted = false; c.drop(0) } }
      }

      // ---- opening: the tapped card grows from its place to the whole screen with its picture, the rest
      // fades; only when it covers the screen does the window take the focus underneath (switchTo), and a
      // moment later the switcher lets go — the window is where the card was, nothing jumps in between
      property int launching: -1
      Spring {
        id: launchS
        preset: sw.cfg.launchSpring
        reduced: Theme.reduceMotion
        target: 0
        onValueChanged: {
          var c = root.cardItem(root.launching)
          if (c) c.launch = value
          if (root.launching >= 0 && !root.handed && value >= sw.cfg.launchSwitchAt) {
            root.handed = true
            sw.switchTo(root.windows[root.launching].address)
            handoff.restart()
          }
        }
      }
      property bool handed: false
      Timer { id: handoff; interval: sw.handoff; onTriggered: { sw.handedOff = true; sw.holding = false; enter.snap(0) } }
      function launchAt(i) {
        var c = cardItem(i)
        if (!c || launching >= 0) return
        rowX.snap(rowX.value)
        c.from = c.mapToItem(root, 0, 0)
        launching = i
        handed = false
        sw.holding = true
        launchS.target = 1
      }

      // ---- closing: the card flies, the window is asked to close, then it leaves the row
      property var leaving: ({})
      function closeAt(i, vy) {
        var w = windows[i], c = cardItem(i)
        if (!w || !c) return
        c.fly(vy)
        var l = Object.assign({}, leaving); l[w.address] = true; leaving = l
        gone.restart()
      }
      Timer {
        id: gone
        interval: sw.cfg.closeAfter
        // the window is asked to close only now: its picture would vanish with it mid-flight
        onTriggered: {
          for (var a in root.leaving) sw.closeWindow(a)
          var keep = root.windows.filter(function (w) { return !root.leaving[w.address] })
          root.leaving = ({})
          root.windows = keep
        }
      }
      function clearAll() {
        for (var i = 0; i < n; i++) {
          var c = cardItem(i)
          if (c && !c.away) c.fly(0)
        }
        clearDone.restart()
      }
      Timer {
        id: clearDone
        interval: sw.cfg.clearDelay
        onTriggered: {
          for (var i = 0; i < root.windows.length; i++) sw.closeWindow(root.windows[i].address)
          sw.closed()
        }
      }

      // a window that closed elsewhere while open leaves the row too
      Connections {
        target: Hyprland.toplevels
        function onValuesChanged() {
          var live = {}, tl = Hyprland.toplevels.values
          for (var i = 0; i < tl.length; i++) { var o = tl[i].lastIpcObject; if (o && o.address) live[String(o.address)] = true }
          var keep = root.windows.filter(function (w) { return live[w.address] || root.leaving[w.address] })
          if (keep.length !== root.windows.length) root.windows = keep
        }
      }

      function info() {
        return { open: true, p: p, n: n, offset: rowX.value, target: rowX.target, step: step, centred: Nav.centred(rowX.value, n, step), fling: lastFling,
                 cardW: cardW, cardH: cardH,
                 windows: windows.map(function (w, i) { var c = cardItem(i); return { address: w.address, name: w.name, picture: !!(c && c.hasPicture), away: !!(c && c.away) } }) }
      }

      // ---- what lies behind: the owner's backdrop, the scrim
      Loader { anchors.fill: parent; sourceComponent: sw.backdrop; opacity: root.p; active: sw.backdrop !== null }
      Rectangle { anchors.fill: parent; color: sw.cfg.scrim; opacity: root.p }

      // ---- the row rises with the finger and settles in the middle
      Item {
        id: stage
        anchors.fill: parent
        // risen with the finger, or standing at once when taken over from the owner's card
        readonly property real rise: root.takenOver ? 1 : root.p
        opacity: rise
        readonly property real others: 1 - launchS.value
        transform: [
          Scale { origin.x: stage.width / 2; origin.y: stage.height / 2; xScale: (sw.cfg.enterScale + (1 - sw.cfg.enterScale) * stage.rise) * root.rowScale; yScale: xScale },
          Translate { y: (1 - stage.rise) * stage.height * sw.cfg.enterRise + root.rowY }
        ]
        Item {
          id: row
          anchors.fill: parent
          transform: Translate { x: rowX.value }
          Repeater {
            id: cards
            model: ScriptModel { values: root.windows; objectProp: "address" }
            SwitcherCard {
              required property var modelData
              entry: modelData
              readonly property bool handed: modelData.address === root.handAddress || !!root.handOthers[modelData.address]
              dim: (root.launching >= 0 && index !== root.launching ? stage.others : 1) * (handed ? 1 : 1 - root.hand)
              hand: handed ? root.hand : 0
              rowScale: root.rowScale
              count: root.n
              cardW: root.cardW
              cardH: root.cardH
              step: root.step
              areaW: root.width
              areaH: root.height
            }
          }
        }
        // Clear all under the cards, or the note that there is nothing
        Rectangle {
          id: clear
          property bool down: false
          anchors.horizontalCenter: parent.horizontalCenter
          y: parent.height / 2 + root.cardH / 2 + sw.cfg.clearTop
          visible: root.n > 0
          opacity: stage.others * (1 - root.hand)
          width: clearText.implicitWidth + 2 * sw.cfg.clearPad
          height: sw.cfg.clearHeight
          radius: height / 2
          color: down ? sw.cfg.clearPressed : sw.cfg.clearFill
          Text {
            id: clearText
            anchors.centerIn: parent
            text: "Clear all"
            color: sw.cfg.ink
            font.family: sw.family
            font.pixelSize: sw.cfg.labelSize
            font.weight: sw.cfg.labelWeight
          }
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          y: parent.height / 2 + root.cardH / 2 + sw.cfg.clearTop
          visible: root.n === 0
          text: "No recent apps"
          color: sw.cfg.ink
          font.family: sw.family
          font.pixelSize: sw.cfg.emptySize
        }
      }

      // ---- touch (MultiPointTouchArea: Qt's mouse stand-in for touch never reached a MouseArea on the
      // cast, henri.tablet-v3 2026-11-07) and a pointer (the rig) through the MouseArea
      MultiPointTouchArea {
        anchors.fill: parent
        enabled: !sw.dragging
        maximumTouchPoints: 1
        mouseEnabled: false
        onPressed: function (pts) { root.press(pts[0].x, pts[0].y) }
        onUpdated: function (pts) { root.move(pts[0].x, pts[0].y) }
        onReleased: function (pts) { root.release() }
        onCanceled: root.cancel()
      }
      MouseArea {
        anchors.fill: parent
        enabled: !sw.dragging
        preventStealing: true
        onPressed: function (m) { root.press(m.x, m.y) }
        onPositionChanged: function (m) { root.move(m.x, m.y) }
        onReleased: function (m) { root.release() }
        onCanceled: root.cancel()
      }
    }
  }
}
