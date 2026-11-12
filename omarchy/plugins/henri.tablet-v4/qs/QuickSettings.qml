import QtQuick
import QtQuick.Effects
import Quickshell
import "file:///home/henri/.local/share/velum/qml/Velum"

// Quick Settings — Android's notification shade on the tablet (henri.tablet-v4, phase 4 of
// docs/TABLET-V4-PLAN.md; look and behaviour: lab/mui-material src/QuickSettings.jsx + src/QsPages.jsx).
// A split shade: Quick Settings left (header with clock, date, edit / power / settings; tabs Controls /
// Battery / Tablet / Power; tile details for Internet, Bluetooth and Sound; tile editing), the notification history
// right (below it in portrait). Values: surface.material.qs (tokens/surfaces/material-qs.tokens.json).
//
// ---- API for the owner (the top-edge pull in tablet mode routes here instead of FullCenter) -------------
//
//   QuickSettings {
//     anchors.fill: parent          // a full-screen overlay layer window of the owner; it stays mapped and
//                                   // takes input only while `shown` (the owner sets its mask / visibility)
//     backend: qsb                  // a QsBackend (its `active` should follow `shown`)
//     wallpaper: "<path>"           // optional: blurred once from a downscaled copy behind the shade
//     topInset: 0                   // px above the status bar line the panels hang from
//
//     // the owner's finger from the top edge drives the shade:
//     dragging: true                //   while the finger moves,
//     dragProgress: dy / travel     //   0 … 1 (travel = the shade's `travel` in px),
//     // and on lift:
//     release(velocityY)            //   px/s, down positive — opens past `commit` of the travel or on a
//                                   //   fling (surface.material.qs.shade), else springs back closed;
//                                   //   then the owner sets dragging: false
//   }
//   open() / close()                — e.g. from IPC or a tap on the status bar
//   readonly progress (0 … 1), shown (on screen or moving), travel (px)
//   signal opened()                 — settled open
//   signal closed()                 — settled closed after a close (push up, tap beside, Escape, an action):
//                                     the owner may now unmap / drop its input region
//   signal tileLongPressed(key)     — a held tile without details of its own (dnd, dark, night, airplane,
//                                     rotate): the owner may open a settings page
//
// Its own finger: a push up anywhere on the shade (not on the slider) carries it and closes it on release
// (or springs back), a tap beside the panels or Escape closes it, a sideways swipe on the page turns the
// page, a vertical one on a list that can move that way (the Controls page taller than the shade, a tile's
// details) scrolls it and flings on lift (`scroller`); nothing reaches the home screen behind (the window
// takes every point while shown). Only transform and opacity change per frame: the panels slide by a
// Translate on one spring; the backdrop is a cached blur.
FocusScope {
  id: qs
  property var backend: null
  property bool dragging: false
  property real dragProgress: 0
  property string wallpaper: ""
  property real topInset: 0
  signal opened()
  signal closed()
  signal tileLongPressed(string key)

  readonly property var k: Theme.core.surface.material.qs
  readonly property real travel: height * k.shade.travel
  readonly property bool land: width >= height
  readonly property real edge: k.status.edge
  readonly property real qsW: land ? Math.min(k.panel.width, (width - 3 * edge) / 2) : width - 2 * edge   // lint-ok: three margins beside two panels
  readonly property real pageW: qsW - 2 * k.panel.pad
  readonly property var tabNames: ["Controls", "Battery", "Tablet", "Power"]

  // ---- the shade's position: the owner's finger, the shade's own finger, or the spring
  property bool wantOpen: false
  property bool released: false            // release() took over from the owner's finger
  property bool ownDrag: false
  property real ownProgress: 0
  readonly property real progress: Math.max(0, Math.min(1,
    ownDrag ? ownProgress : dragging && !released ? dragProgress : shade.value))
  readonly property bool shown: progress > 0 || dragging || ownDrag || shade.moving
  // open and standing: the owner's backend reads the system only then (results that came in during a
  // pull rebuilt tiles and the notification list in the moving frames)
  readonly property bool still: shown && !dragging && !ownDrag && !shade.moving
  onDraggingChanged: released = false
  Spring {
    id: shade
    preset: Theme.spring("smooth")
    reduced: Theme.reduceMotion
    target: qs.wantOpen ? 1 : 0
    onMovingChanged: qs.settled()
  }
  function settled() {
    if (shade.moving || ownDrag || (dragging && !released)) return
    if (wantOpen && shade.value >= 1) opened()
    if (!wantOpen && shade.value <= 0) {
      const c = pageRep.itemAt(0)
      if (c && c.item) { c.item.scroller.cancelFlick(); c.item.scroller.contentY = 0 }
      tab = 0; detail = ""; editing = false; confirm.open = false
      seen = [true, false, false, false]
      closed()
    }
  }
  // from p with the finger's speed (px/s) to the side the gesture chose
  function settleFrom(p, velocity, open) {
    shade.snap(p)
    const was = wantOpen
    wantOpen = open
    shade.velocity = velocity / Math.max(1, travel)
    if (was === open && Math.abs(shade.value - shade.target) > 0) shade.anim.start()
    if (shade.value === shade.target && !shade.moving) settled()
  }
  function release(velocity) {
    const p = progress
    const k2 = k.shade
    const open = velocity > k2.flick ? true : velocity < -k2.flick ? false : wantOpen ? p > 1 - k2.commit : p > k2.commit
    released = true
    settleFrom(p, velocity, open)
  }
  function open() { settleFrom(progress, 0, true) }
  function close() { settleFrom(progress, 0, false) }

  focus: shown
  onShownChanged: if (shown) forceActiveFocus()
  Keys.onEscapePressed: close()

  // ---- page state
  property int tab: 0
  property string detail: ""               // "wifi" | "bluetooth" | "sound": its list instead of the pages
  property bool editing: false
  property var seen: [true, false, false, false]   // pages loaded since the shade opened
  function markSeen(i) {
    if (i < 0 || i >= seen.length || seen[i]) return
    const s = seen.slice(); s[i] = true; seen = s
  }
  onTabChanged: markSeen(tab)
  // the strip is as tall as the tallest page loaded (Controls, mostly), so turning a page lays nothing out
  property var pageHeights: [0, 0, 0, 0]
  function setPageHeight(i, h) { const a = pageHeights.slice(); a[i] = h; pageHeights = a }
  Binding { target: qs.backend; property: "wantHistory"; value: qs.shown && (qs.seen[1] || qs.seen[2]); when: !!qs.backend }

  function goTab(i) {
    detail = ""
    i = Math.max(0, Math.min(tabNames.length - 1, i))
    if (i === tab) return
    pager.snap(tab - pageDx / Math.max(1, pageW))
    tab = i
  }
  function showDetail(kind) { editing = false; detail = kind }
  function edit(on) { detail = ""; goTab(0); editing = on }

  // ---- what tiles and power tiles do
  property var pendingAction: null
  function ask(title, text, action, danger, fn) {
    confirm.title = title; confirm.text = text; confirm.action = action; confirm.danger = danger
    pendingAction = fn
    confirm.open = true
  }
  function answer(yes) {
    confirm.open = false
    const f = pendingAction
    pendingAction = null
    if (yes && f) f()
  }
  function toggleTile(key) {
    const b = backend
    if (!b) return
    switch (key) {
    case "wifi": {
      if (b.airplane) { b.setAirplane(false); return }
      if (b.wifiOn && b.castOverWifi)
        ask("Turn off Wi-Fi?", "The iPad shows this screen over Wi-Fi. Turning Wi-Fi off ends the cast.", "Turn off", true, () => b.setWifi(false))
      else b.setWifi(!b.wifiOn)
      return
    }
    case "bluetooth": b.setBluetooth(!b.btOn); return
    case "sound": if (b.hasSink) b.setMuted(!b.muted); return
    case "dnd": b.setDnd(!b.dnd); return
    case "dark": b.setDark(!b.dark); return
    case "night": b.setNight(!b.night); return
    case "airplane":
      if (!b.airplane && b.castOverWifi)
        ask("Turn on Airplane mode?", "The iPad shows this screen over Wi-Fi. Airplane mode ends the cast.", "Turn on", true, () => b.setAirplane(true))
      else b.setAirplane(!b.airplane)
      return
    case "saver": b.setPowerMode(b.powerMode === "saver" ? "balanced" : "saver"); return
    case "rotate": if (b.rotationAvailable) b.setRotate(!b.rotate); return
    case "cast": goTab(2); return
    }
  }
  function longPressTile(key) {
    if (key === "wifi" || key === "bluetooth" || key === "sound") showDetail(key)
    else if (key === "cast") goTab(2)
    else if (key === "saver") goTab(1)
    else tileLongPressed(key)
  }
  readonly property var powerAsk: ({
    logout: ["Log out?", "Open apps close and the session ends.", "Log out"],
    restart: ["Restart now?", "Open apps close and the computer restarts.", "Restart"],
    off: ["Shut down now?", "Open apps close and the computer turns off.", "Shut down"] })
  function choosePower(key) {
    const b = backend
    if (!b) return
    const q = powerAsk[key]
    if (q) { ask(q[0], q[1], q[2], true, () => { close(); b.power(key) }); return }
    close()
    b.power(key)
  }

  // ---- behind the shade: the cached blurred wallpaper and the scrim, both only fading
  Item {
    id: backdrop
    anchors.fill: parent
    opacity: qs.progress
    visible: opacity > 0
    Item {
      anchors.fill: parent
      visible: qs.wallpaper !== "" && !Theme.userReduceTransparency
      // blurred once and kept (also while the shade is closed: made again at each pull's first frame,
      // it held that frame), then only composited while it fades
      layer.enabled: visible
      Image {
        id: wall
        anchors.fill: parent
        source: qs.wallpaper !== "" ? "file://" + qs.wallpaper : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: qs.width / qs.k.shade.blurDownscale
        sourceSize.height: qs.height / qs.k.shade.blurDownscale
        asynchronous: true
        cache: true
        visible: false
      }
      MultiEffect { anchors.fill: parent; source: wall; blurEnabled: true; blur: 1; blurMax: qs.k.shade.blurMax }
    }
    Rectangle { anchors.fill: parent; color: qs.k.shade.scrim }
  }

  // a tap beside the panels closes; the press is taken either way (nothing reaches the home screen). Beside is
  // decided at the press: a tap on a tile that opens shorter details (Bluetooth's chevron) shrinks the panel
  // before this tap ends, and the lifted finger then stood beside it
  TapHandler {
    enabled: qs.shown
    property bool beside: false
    onPressedChanged: if (pressed) {
      const p = point.position
      const inside = (it) => { const r = it.mapToItem(qs, 0, 0); return p.x >= r.x && p.x <= r.x + it.width && p.y >= r.y && p.y <= r.y + it.height }
      beside = !inside(qsPanel) && !inside(notifPanel)
    }
    onTapped: if (beside) qs.close()
  }

  // the Controls page and the details list do not take a finger themselves (their Flickables are not
  // interactive): the shade's finger scrolls the one under it when it can move that way, else carries the shade
  readonly property real pagesMax: panels.height - 2 * k.panel.pad - header.height - k.header.bottom - tabs.height - k.tabs.bottom
  readonly property real detailMax: pagesMax + tabs.height + k.tabs.bottom   // the details stand where tabs and pages were
  function scroller() {
    if (detail !== "") return detailLoader.item ? detailLoader.item.scroller : null
    const c = tab === 0 ? pageRep.itemAt(0) : null
    return c && c.item ? c.item.scroller : null
  }
  function canScroll(f, dy) {
    return !!f && f.contentHeight > f.height + 1 && (dy < 0 ? f.contentY < f.contentHeight - f.height : f.contentY > 0)
  }
  property var scrolling: null
  property real scrollFrom: 0
  property real scrollT0: 0

  // the shade's own finger: vertical = carry the shade (or scroll), sideways on the page = turn it
  property string swipe: ""                // "" | pending | shade | scroll | page | none
  property real pressProgress: 0
  property real pageDx: 0
  DragHandler {
    id: finger
    target: null
    enabled: qs.shown && !(qs.dragging && !qs.released)
    dragThreshold: qs.k.shade.slop
    grabPermissions: PointerHandler.CanTakeOverFromItems | PointerHandler.CanTakeOverFromHandlersOfDifferentType
      | PointerHandler.ApprovesTakeOverByHandlersOfSameType   // a held tile (editing) or a notification card takes its finger
    // the axis is chosen on the first movement after activation (translation is still zero when it activates)
    function decide(t) {
      const p = centroid.pressPosition
      const r = pagesClip.mapToItem(qs, 0, 0)
      const onPages = pagesClip.visible && p.x >= r.x && p.x <= r.x + pagesClip.width && p.y >= r.y && p.y <= r.y + pagesClip.height
      const f = Math.abs(t.x) > Math.abs(t.y) ? null : qs.scroller()
      const fr = f ? f.mapToItem(qs, 0, 0) : null
      if (Math.abs(t.x) > Math.abs(t.y)) qs.swipe = onPages && !qs.editing && qs.detail === "" ? "page" : "none"
      else if (f && p.x >= fr.x && p.x <= fr.x + f.width && p.y >= fr.y && p.y <= fr.y + f.height && qs.canScroll(f, t.y)) {
        f.cancelFlick()
        qs.scrolling = f
        qs.scrollFrom = f.contentY
        qs.scrollT0 = t.y
        qs.swipe = "scroll"
      } else {
        qs.swipe = "shade"
        qs.pressProgress = qs.progress
        qs.ownProgress = qs.progress
        qs.ownDrag = true
        shade.snap(qs.progress)
      }
    }
    onActiveChanged: {
      if (active) {
        samples = []
        qs.swipe = "pending"
        if (translation.x !== 0 || translation.y !== 0) decide(translation)
        return
      }
      if (qs.swipe === "shade") {
        const v = flickSpeed()
        const p = qs.ownProgress
        qs.ownDrag = false
        qs.settleFrom(p, v, v > qs.k.shade.flick ? true : v < -qs.k.shade.flick ? false : p > 1 - qs.k.shade.commit)
      } else if (qs.swipe === "scroll") {
        if (qs.scrolling) qs.scrolling.flick(0, centroid.velocity.y)
        qs.scrolling = null
      } else if (qs.swipe === "page") {
        const dx = qs.pageDx
        const from = qs.tab - dx / Math.max(1, qs.pageW)
        let next = qs.tab
        if (Math.abs(dx) > qs.pageW * qs.k.pages.commit) next = Math.max(0, Math.min(qs.tabNames.length - 1, qs.tab + (dx < 0 ? 1 : -1)))
        qs.pageDx = 0
        pager.snap(from)
        if (next !== qs.tab) qs.tab = next
        else pager.from(from)
      }
      qs.swipe = ""
    }
    // the release speed from the finger's own points over sampleWindow, not Qt's estimate: points from a
    // cast come in clumps after a pause (2026-11-12), and a clump read as a flick closed the shade on a tap
    property var samples: []
    function flickSpeed() {
      const l = samples, t = Date.now()
      samples = []
      if (l.length < 2 || Math.abs(qs.ownProgress - qs.pressProgress) * qs.travel < qs.k.shade.flickTravel) return 0
      let i = 0
      while (i < l.length - 2 && t - l[i][0] > Theme.core.surface.tablet.sampleWindow) i++
      return (l[l.length - 1][1] - l[i][1]) * 1000 / Math.max(Theme.core.surface.tablet.sampleWindow, t - l[i][0])
    }
    onTranslationChanged: {
      if (!active) return
      const now = Date.now()
      samples = samples.filter(e => now - e[0] <= 2 * Theme.core.surface.tablet.sampleWindow).concat([[now, translation.y]])
      if (qs.swipe === "pending") decide(translation)
      if (qs.swipe === "shade") qs.ownProgress = Math.max(0, Math.min(1, qs.pressProgress + translation.y / Math.max(1, qs.travel)))
      else if (qs.swipe === "scroll" && qs.scrolling) {
        const f = qs.scrolling
        f.contentY = Math.max(0, Math.min(f.contentHeight - f.height, qs.scrollFrom - (translation.y - qs.scrollT0)))
      }
      else if (qs.swipe === "page") {
        const dx = translation.x
        const edge = (qs.tab === 0 && dx > 0) || (qs.tab === qs.tabNames.length - 1 && dx < 0)
        qs.pageDx = edge ? dx * qs.k.pages.resist : dx
        if (dx < 0) qs.markSeen(qs.tab + 1); else qs.markSeen(qs.tab - 1)
      }
    }
  }
  Spring { id: pager; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion; target: qs.tab }
  readonly property real pagePos: swipe === "page" ? tab - pageDx / Math.max(1, pageW) : pager.value

  // ---- the panels: one Translate on the shade's spring, opacity in the first part of it
  Item {
    id: panels
    x: qs.edge
    y: qs.topInset + qs.k.status.height
    width: qs.width - 2 * qs.edge
    height: qs.height - y - qs.edge
    opacity: Math.min(1, qs.progress / qs.k.shade.fadeShare)
    visible: qs.shown
    transform: Translate { y: -(1 - qs.progress) * qs.travel }

    // Quick Settings
    Item {
      id: qsPanel
      width: qs.qsW
      height: inner.height + 2 * qs.k.panel.pad
      VShadow { layers: Theme.r.popover.shadow; radius: qs.k.panel.radius }
      Rectangle {
        anchors.fill: parent
        radius: qs.k.panel.radius
        color: Theme.userReduceTransparency ? Theme.r.popover.bgOpaque : Theme.r.popover.bg
        border.width: qs.k.panel.rim
        border.color: Theme.r.line.rim
      }
      Item {
        id: inner
        x: qs.k.panel.pad; y: qs.k.panel.pad
        width: qs.pageW
        height: header.height + qs.k.header.bottom + (qs.detail !== "" ? detailLoader.height : tabs.height + qs.k.tabs.bottom + pagesClip.height)

        // header: clock and date, edit / power / settings (Done while editing)
        Item {
          id: header
          width: parent.width
          height: Math.max(clockCol.height, qs.k.header.button)
          Column {
            id: clockCol
            anchors.bottom: parent.bottom
            spacing: qs.k.header.dateGap
            MText { size: "h4"; text: Qt.formatTime(clock.date, "HH:mm") }
            MText { tone: "secondary"; text: Qt.locale("en_GB").toString(clock.date, "dddd d MMMM") }
          }
          Row {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: qs.k.header.gap
            visible: !qs.editing
            MIconButton { objectName: "btn-edit"; icon: "pencil"; label: "Edit tiles"; onClicked: qs.edit(true) }
            MIconButton { objectName: "btn-power"; icon: "power"; label: "Power menu"; onClicked: qs.goTab(qs.tabNames.length - 1) }
            MIconButton { objectName: "btn-settings"; icon: "settings"; label: "Settings"; onClicked: { if (qs.backend) qs.backend.openSettings(); qs.close() } }
          }
          Item {
            objectName: "btn-done"
            visible: qs.editing
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: doneLabel.width + 2 * qs.k.header.donePad
            height: qs.k.header.doneHeight
            Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.r.accent.base }
            Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.r.ink.onAccent; opacity: doneTap.pressed ? Theme.core.alpha.pressed : 0 }
            MText { id: doneLabel; anchors.centerIn: parent; medium: true; text: "Done"; color: Theme.r.ink.onAccent }
            TapHandler { id: doneTap; onTapped: qs.editing = false }
          }
        }

        QsTabs {
          id: tabs
          visible: qs.detail === ""
          y: header.height + qs.k.header.bottom
          width: parent.width
          model: qs.tabNames
          current: qs.tab
          position: qs.pagePos
          onChosen: i => qs.goTab(i)
        }

        // the pages side by side in a clipped strip; a page is loaded once shown (or a finger brings it)
        Item {
          id: pagesClip
          visible: qs.detail === ""
          y: tabs.y + tabs.height + qs.k.tabs.bottom
          width: parent.width
          height: Math.max.apply(null, qs.pageHeights)
          clip: true
          Item {
            id: strip
            transform: Translate { x: -qs.pagePos * qs.pageW }
            Repeater {
              id: pageRep
              model: [ctlPage, batteryPage, tabletPage, powerPage]
              Loader {
                required property var modelData
                required property int index
                x: index * qs.pageW
                width: qs.pageW
                active: qs.seen[index]
                sourceComponent: modelData
                readonly property real h: item ? item.implicitHeight : 0
                onHChanged: qs.setPageHeight(index, h)
              }
            }
          }
        }

        Loader {
          id: detailLoader
          active: qs.detail !== ""
          y: header.height + qs.k.header.bottom
          width: parent.width
          height: item ? item.implicitHeight : 0
          // none while no details show: `active` may turn true before this follows a new kind, and a stale
          // component would stand for a frame (the Wi-Fi details' scan ran when Sound opened)
          sourceComponent: qs.detail === "sound" ? soundDetail : qs.detail !== "" ? netDetail : null
        }
      }
      QsConfirm {
        id: confirm
        anchors.fill: parent
        onCanceled: qs.answer(false)
        onAccepted: qs.answer(true)
      }
    }

    // the notifications: beside it in landscape, below it in portrait
    Item {
      id: notifPanel
      x: qs.land ? qs.qsW + qs.edge : 0
      y: qs.land ? 0 : qsPanel.height + qs.edge
      width: qs.land ? panels.width - qs.qsW - qs.edge : qs.qsW
      height: notes.height + 2 * qs.k.panel.pad
      VShadow { layers: Theme.r.popover.shadow; radius: qs.k.panel.radius }
      Rectangle {
        anchors.fill: parent
        radius: qs.k.panel.radius
        color: Theme.userReduceTransparency ? Theme.r.popover.bgOpaque : Theme.r.popover.bg
        border.width: qs.k.panel.rim
        border.color: Theme.r.line.rim
      }
      QsNotifications {
        id: notes
        x: qs.k.panel.pad; y: qs.k.panel.pad
        width: parent.width - 2 * qs.k.panel.pad
        backend: qs.backend
        maxHeight: (qs.land ? panels.height : panels.height - notifPanel.y) - 2 * qs.k.panel.pad
      }
    }
  }

  SystemClock { id: clock; precision: SystemClock.Minutes; enabled: qs.shown }

  Component { id: ctlPage; QsControls { backend: qs.backend; editing: qs.editing; maxHeight: qs.pagesMax
    onToggleRequested: key => qs.toggleTile(key); onDetailRequested: key => qs.showDetail(key); onLongPressed: key => qs.longPressTile(key) } }
  Component { id: netDetail; QsDetail { backend: qs.backend; kind: qs.detail; onBack: qs.detail = "" } }
  Component { id: soundDetail; QsSound { backend: qs.backend; maxHeight: qs.detailMax; onBack: qs.detail = ""
    onSettingsRequested: { if (qs.backend) qs.backend.openSoundSettings(); qs.close() } } }
  Component { id: batteryPage; QsBattery { backend: qs.backend } }
  Component { id: tabletPage; QsTablet { backend: qs.backend } }
  Component { id: powerPage; QsPower { onChosen: (key, text) => qs.choosePower(key) } }
}
