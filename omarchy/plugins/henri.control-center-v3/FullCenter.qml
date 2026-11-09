import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "file:///home/henri/.local/share/velum/qml/Velum"

// Control Center in tablet mode (iPadOS): a finger pulls it down from the top right and it covers
// the whole screen over a blurred picture of it. Wider than the island: beside the Control Center's
// own pages the battery menu of this machine (PowerPages) and, while a tablet shows this Mac, the
// tablet's page (henri.cast-v3 CastPages) — each section with its own page stack, so a tile still
// opens its detail page in place. Henri 2026-11-09: "alles in einem gesamten Kontrollzentrum".
//
// The picture behind is one capture of the screen per open (ScreencopyView, blurred from a smaller
// copy): Hyprland's blur is off while a tablet casts, and one capture costs nothing per frame. Under
// the finger only transform and opacity change: the picture fades in as the blur would grow, the
// columns grow out of the top right corner, one section after the other.
// Closed by a tap beside the tiles, a swipe up (the columns follow the finger) or Esc.
//
//   FullCenter { screen: …; be: be; velum: velum; onDismissed: open = false }
//   pull: -1 = no pull, 0…1 = how far a finger has pulled (VGestures, BarWidget.qml)
PanelWindow {
  id: win
  property var be: null
  property var velum: null
  property bool open: false
  property real pull: -1
  readonly property bool pulling: pull >= 0
  signal dismissed()

  readonly property var cfg: Theme.core.surface.tablet.controlCenter
  readonly property var tt: Theme.core.surface.tablet
  readonly property real screenW: screen ? screen.width : 0
  readonly property real screenH: screen ? screen.height : 0

  // ---- how far it is out: 0 closed … 1 open; a swipe up while open takes it back with the finger
  readonly property real closeShare: open && flick.dragging ? Math.max(0, Math.min(1, flick.verticalOvershoot / tt.pullTravel)) : 0
  Spring {
    id: prog
    preset: win.pulling && !win.open || win.closeShare > 0 ? win.tt.follow : Theme.spring("snappy")
    reduced: Theme.reduceMotion
    target: win.open ? 1 - win.closeShare : win.pulling ? Math.min(1, win.pull) : 0
  }
  readonly property real p: Math.max(0, Math.min(1, prog.value))
  readonly property bool shown: open || pulling || prog.moving || prog.value > 0
  // the user's own Reduce Transparency (Theme's is also on while Hyprland has no blur, as during a
  // cast — this picture is the shell's own, so it stays)
  readonly property bool opaque: !!velum && !!velum.values.reduceTransparency

  // ---- the picture behind: taken as the surface comes up, before it covers anything
  onShownChanged: {
    if (shown) {
      arrange()
      shot.captureSource = win.screen
      shot.captureFrame()
      return
    }
    shot.captureSource = null
    ccPages.reset(); battStack.reset(); castLoader.reset()
    flick.contentY = 0
  }
  onOpenChanged: {
    if (open) { focusPrimed = false; prime.restart(); Qt.callLater(function () { if (win.open) keys.forceActiveFocus() }) }
    else { prime.stop(); focusPrimed = false }
  }

  visible: shown
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  anchors { top: true; bottom: true; left: true; right: true }
  // no compositor blur (the picture is blurred here), no layer animation
  WlrLayershell.namespace: "velum-surface-dismiss"
  WlrLayershell.layer: WlrLayer.Overlay
  property bool focusPrimed: false
  WlrLayershell.keyboardFocus: open ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive) : WlrKeyboardFocus.None
  Timer { id: prime; interval: Theme.dur("fast") / 2; onTriggered: if (win.open) win.focusPrimed = true }
  // open: the whole screen takes the finger; pulled or going: nothing (the finger belongs to the bar)
  mask: open ? full : nothing
  Region { id: nothing }
  Region { id: full; width: win.screenW; height: win.screenH }

  Item {
    id: back
    anchors.fill: parent
    // the blur is all there within the first share of the pull (backdropBy); the tiles come after it,
    // so the sharp screen never shows through half-faded tiles
    opacity: Math.min(1, win.p / win.cfg.backdropBy)
    ScreencopyView {
      id: shot
      anchors.fill: parent
      live: false
      paintCursor: false
    }
    ShaderEffectSource {
      id: small
      anchors.fill: parent
      sourceItem: shot
      hideSource: true
      visible: false
      textureSize: Qt.size(Math.max(1, Math.round(width / win.cfg.blurDownscale)), Math.max(1, Math.round(height / win.cfg.blurDownscale)))
    }
    MultiEffect {
      anchors.fill: parent
      source: small
      visible: shot.hasContent && !win.opaque
      blurEnabled: true
      blur: 1
      blurMax: win.cfg.blur
      // darker as on iPadOS, so a light app behind does not wash out the tiles
      brightness: -win.cfg.dim
    }
    // the material over it: the island's own, so every tile reads as it does there
    Rectangle {
      anchors.fill: parent
      color: win.opaque || !shot.hasContent ? Theme.r.popover.bgOpaque : Theme.r.popover.bg
    }
  }

  // ---- the columns
  // as many columns as fit at minColumn, never wider than the island; each section goes into the
  // column that is shortest so far (Control Center first, so it stands top left). The choice is made
  // as the surface comes up and kept while it is open, so a page pushed in one section never moves
  // the others to another column.
  readonly property real gap: cfg.gap
  readonly property real usable: screenW - 2 * cfg.margin
  readonly property var sections: [ccSec, battSec, castSec].filter(function (s) { return s.present })
  readonly property int columns: Math.max(1, Math.min(sections.length, Math.floor((usable + gap) / (cfg.minColumn + gap))))
  readonly property real colW: Math.min(Theme.layout.module.island, (usable - (columns - 1) * gap) / columns)
  readonly property real left: Math.round((screenW - columns * colW - (columns - 1) * gap) / 2)
  property var columnOf: ({})          // section objectName → column
  function arrange() {
    var heights = [], out = {}
    for (var c = 0; c < columns; c++) heights.push(0)
    for (var k = 0; k < sections.length; k++) {
      var best = 0
      for (var c2 = 1; c2 < columns; c2++) if (heights[c2] < heights[best]) best = c2
      out[sections[k].objectName] = best
      heights[best] += sections[k].height + gap
    }
    columnOf = out
  }
  onColumnsChanged: arrange()
  onSectionsChanged: arrange()
  function colOf(s) { var c = columnOf[s.objectName]; return c === undefined ? Math.min(sections.indexOf(s), columns - 1) : c }
  function xOf(s) { return left + colOf(s) * (colW + gap) }
  function yOf(s) {
    var y = 0, c = colOf(s)
    for (var k = 0; k < sections.indexOf(s); k++) if (colOf(sections[k]) === c) y += sections[k].height + gap
    return y
  }
  // a section fades in once the pull has come this far (one after the other)
  function reveal(s) {
    var k = Math.max(0, sections.indexOf(s)), start = k * cfg.stagger
    return Math.max(0, Math.min(1, (p - start) / (1 - start)))
  }

  Flickable {
    id: flick
    anchors.fill: parent
    interactive: win.open
    contentWidth: width
    contentHeight: Math.max(height, body.height + win.cfg.top + win.cfg.margin)
    boundsBehavior: Flickable.DragOverBounds
    // swiped up past the end: let go far or fast enough, it closes (the columns follow the finger)
    onDraggingChanged: if (!dragging && win.open && VGestures.commits(verticalOvershoot, win.tt.pullTravel, verticalVelocity)) win.dismissed()

    // a tap beside the tiles closes
    MouseArea {
      width: flick.contentWidth; height: flick.contentHeight
      onClicked: win.dismissed()
    }

    Item {
      id: body
      y: win.cfg.top
      width: flick.width
      height: { var h = 0; for (var i = 0; i < win.sections.length; i++) h = Math.max(h, win.yOf(win.sections[i]) + win.sections[i].height); return h }
      // out of the top right corner, where the finger pulled
      transform: Scale {
        origin.x: body.width; origin.y: -win.cfg.top
        xScale: win.cfg.scaleFrom + (1 - win.cfg.scaleFrom) * win.p; yScale: xScale
      }

      Section {
        id: ccSec
        objectName: "cc"
        present: true
        height: ccPages.implicitHeight
        Pages {
          id: ccPages
          width: parent.width
          be: win.be; velum: win.velum
          // the sections come in under the finger: no stagger of the island's own
          stagger: false
          columnWidth: win.colW
          onCloseRequested: win.dismissed()
        }
      }

      // the battery menu of this machine
      PowerService { id: powerSvc; opened: win.open }
      PowerPages { id: power; svc: powerSvc; standalone: true; onPushRequested: n => battStack.push(power.page(n)); onBackRequested: battStack.pop() }
      Section {
        id: battSec
        objectName: "battery"
        present: powerSvc.batteryPresent
        height: battStack.implicitHeight
        VPageStack { id: battStack; width: parent.width; initial: power.page("battery") }
      }

      // the tablet that shows this Mac (henri.cast-v3), only while it is connected
      Section {
        id: castSec
        objectName: "tablet"
        present: castLoader.svc !== null && castLoader.svc.connected
        height: castStack.item ? castStack.item.implicitHeight : 0
        Loader {
          id: castLoader
          readonly property var svc: status === Loader.Ready ? item : null
          function reset() { if (castStack.item) castStack.item.reset() }
          source: Qt.resolvedUrl("../henri.cast-v3/CastService.qml")
          onLoaded: item.opened = Qt.binding(function () { return win.open })
        }
        Loader {
          id: castPagesLoader
          active: castLoader.status === Loader.Ready
          source: Qt.resolvedUrl("../henri.cast-v3/CastPages.qml")
          onLoaded: item.svc = castLoader.item
        }
        Loader {
          id: castStack
          width: parent.width
          active: castPagesLoader.status === Loader.Ready
          sourceComponent: VPageStack { width: castStack.width; initial: castPagesLoader.item.page("tablet") }
        }
      }
    }
  }

  // one section of the columns: placed by the window, swallows taps on its empty parts
  component Section: Item {
    id: sec
    property bool present: true
    visible: present
    x: win.xOf(sec); y: win.yOf(sec)
    width: win.colW
    opacity: win.reveal(sec)
    MouseArea { anchors.fill: parent }
  }

  Item {
    id: keys
    focus: true
    Keys.onPressed: function (e) {
      if (e.key !== Qt.Key_Escape) return
      e.accepted = true
      if (!ccPages.back()) win.dismissed()
    }
  }

  // the tablet window bar hides while this covers the screen (same overlay layer)
  readonly property bool covering: shown
  onCoveringChanged: VOverlays.hold(win, screen ? screen.name : "", covering)
  onScreenChanged: VOverlays.hold(win, screen ? screen.name : "", covering)
  Component.onDestruction: VOverlays.hold(win, "", false)
}
