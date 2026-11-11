import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "file:///home/henri/.local/share/velum/qml/Velum"

// Control Center in tablet mode (iPadOS): a finger pulls it down from the top right and it covers
// the whole screen over a blurred picture of it. Layout = option 1 of lab/web/control-center-full3.html
// (Henri 2026-11-09), every value once:
//   status line   this machine's battery · the casting tablet's battery · the network · the stream
//   band          the network as a list | Display and Sound, stretched to the list's height
//   MacBook Air   six toggle tiles and the power mode | the last hour's chart and the numbers
//   iPad          the tablet's six switches (henri.cast-v3 CastService), only while it is connected
// A tile that has more opens the island's detail page (Pages, detailsOnly) as a card over it.
//
// The picture behind is one capture of the screen per open (ScreencopyView, blurred from a smaller
// copy): Hyprland's blur is off while a tablet casts, and one capture costs nothing per frame. Under
// the finger only transform and opacity change: the picture is fully there within backdropBy of the
// pull, the boxes grow out of the top right corner, one after the other.
// Closed by a tap beside the boxes, a swipe up (the boxes follow the finger) or Esc.
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
      shot.captureSource = win.screen
      shot.captureFrame()
      return
    }
    shot.captureSource = null
    detailOpen = false
    details.reset()
  }
  onOpenChanged: {
    if (open) { focusPrimed = false; prime.restart(); Qt.callLater(function () { if (win.open) keys.forceActiveFocus() }) }
    else { prime.stop(); focusPrimed = false; detailOpen = false }
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
    // the blur is all there within the first share of the pull; the boxes come after it, so the sharp
    // screen never shows through half-faded tiles
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

  // ---- what it shows
  // this machine's battery menu (the status line, the chart, health, the power mode)
  PowerService { id: power; opened: win.open }
  // the tablet that shows this Mac (henri.cast-v3), only while it is connected
  Loader {
    id: castLoader
    source: Qt.resolvedUrl("../henri.cast-v3/CastService.qml")
    onLoaded: item.opened = Qt.binding(function () { return win.open })
  }
  readonly property var cast: castLoader.status === Loader.Ready ? castLoader.item : null
  readonly property bool tablet: !!cast && cast.connected
  readonly property var ci: cast ? cast.i : ({})

  // a tile that has more: the island's detail page as a card over the boxes
  property bool detailOpen: false
  function detail(name) { details.show(name); detailOpen = true }
  function leaveDetail() { detailOpen = false }
  function back() { if (detailOpen) details.back(); else dismissed() }
  readonly property string detailPage: details.current

  readonly property real contentW: Math.min(screenW - 2 * cfg.margin, cfg.maxWidth)
  readonly property real half: (contentW - cfg.gap) / 2

  Flickable {
    id: flick
    anchors.fill: parent
    opacity: win.detailOpen ? 0 : 1
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: win.detailOpen ? Theme.exit(Theme.dur("fast")) : Theme.dur("fast") } }
    interactive: win.open && !win.detailOpen
    contentWidth: width
    contentHeight: Math.max(height, boxes.height + win.cfg.top + win.cfg.margin)
    boundsBehavior: Flickable.DragOverBounds
    // swiped up past the end: let go far or fast enough, it closes (the boxes follow the finger)
    onDraggingChanged: if (!dragging && win.open && VGestures.commits(verticalOvershoot, win.tt.pullTravel, verticalVelocity)) win.dismissed()

    // a tap beside the boxes closes
    MouseArea {
      width: flick.contentWidth; height: flick.contentHeight
      onClicked: win.dismissed()
    }

    Column {
      id: boxes
      x: Math.round((flick.width - win.contentW) / 2); y: win.cfg.top
      width: win.contentW
      spacing: win.cfg.gap
      // out of the top right corner, where the finger pulled
      transform: Scale {
        origin.x: boxes.width; origin.y: -win.cfg.top
        xScale: win.cfg.scaleFrom + (1 - win.cfg.scaleFrom) * win.p; yScale: xScale
      }

      // ============================================================ status line
      Box {
        id: statusBox
        order: 0
        height: statusRow.height + 2 * win.cfg.pad
        Row {
          id: statusRow
          x: win.cfg.pad; y: win.cfg.pad; width: parent.width - 2 * x
          spacing: win.cfg.pad
          StatusItem {
            visible: power.batteryPresent
            battery: true; level: power.batteryFraction; charging: power.charging; plugged: power.plugged
            title: "MacBook Air · " + Math.round(power.batteryFraction * 100) + " %"
            detail: power.statusText + (power.flowText && power.flowText !== "—" ? " · " + power.flowText : "")
            onTapped: win.detail("battery")
          }
          Divider { visible: power.batteryPresent && win.tablet }
          StatusItem {
            visible: win.tablet
            battery: true; level: win.cast ? win.cast.batteryFraction : 0; charging: !!win.cast && win.cast.charging; plugged: !!win.cast && win.cast.plugged
            title: "iPad · " + (win.cast ? win.cast.pctText : "")
            detail: win.cast ? win.cast.statusText() : ""
          }
          Divider {}
          StatusItem {
            icon: "wifi"
            title: "Wi-Fi"
            detail: !win.be ? "" : !win.be.wifiOn ? "Off" : win.be.wifiName || "Not Connected"
            onTapped: win.detail("wifi")
          }
        }
        // the stream, at the right end
        Column {
          visible: win.tablet
          anchors.right: parent.right; anchors.rightMargin: win.cfg.pad; anchors.verticalCenter: parent.verticalCenter
          VText { anchors.right: parent.right; text: win.tablet ? Math.round(win.ci.latency) + " ms · " + (win.cast ? win.cast.watts() : "") : ""
            color: Theme.r.popover.ink; font.weight: Font.DemiBold }
          VText { anchors.right: parent.right; tone: "secondary"; font.pixelSize: Theme.m.type.small
            text: win.tablet ? win.cast.rate(win.ci.kbit) + " · " + (win.ci.link === "cable" ? "Cable" : "Wi-Fi") : "" }
        }
      }

      // ============================================================ network | sliders
      Row {
        id: band
        property int order: 1
        opacity: win.reveal(order)
        width: parent.width; height: conn.height
        spacing: win.cfg.gap
        VTile {
          id: conn
          width: win.half; height: connCol.height + 2 * Theme.layout.module.tileInset
          MouseArea { anchors.fill: parent }
          Column {
            id: connCol
            x: Theme.layout.module.tileInset; y: Theme.layout.module.tileInset; width: parent.width - 2 * x
            VToggleTile { tinted: true; width: parent.width; icon: "wifi"; title: "Wi-Fi"; on: !!win.be && win.be.wifiOn
              subtitle: !win.be ? "" : !win.be.wifiOn ? "Off" : win.be.wifiPending || win.be.wifiName || "Not Connected"
              onToggled: win.be.toggleWifi(); onOpened: win.detail("wifi") }
            VToggleTile { tinted: true; width: parent.width; icon: "bluetooth"; title: "Bluetooth"; on: !!win.be && win.be.btOn
              subtitle: !win.be ? "" : !win.be.btOn ? "Off" : win.be.btConnected.length === 1 ? (win.be.btConnected[0].name || "1 Device")
                        : win.be.btConnected.length > 1 ? win.be.btConnected.length + " Devices" : "On"
              onToggled: win.be.toggleBluetooth(); onOpened: win.detail("bluetooth") }
            VToggleTile { tinted: true; width: parent.width; icon: "airdrop"; title: "AirDrop"; on: !!win.be && win.be.localsendRunning
              subtitle: !!win.be && win.be.localsendRunning ? "LocalSend On" : "Off"
              onToggled: win.be.toggleAirdrop(); onOpened: win.be.openAirdrop() }
          }
        }
        VTile {
          width: win.half; height: conn.height
          MouseArea { anchors.fill: parent }
          Column {
            id: sliders
            x: win.cfg.pad; width: parent.width - 2 * x
            spacing: win.cfg.tileGap
            // always the height of two (a lone Sound slider stays a slider, centred), never a ball
            readonly property real each: (parent.height - 2 * win.cfg.pad - spacing) / 2
            y: win.be && win.be.brightnessAvailable ? win.cfg.pad : (parent.height - each) / 2
            VFillSlider {
              visible: !!win.be && win.be.brightnessAvailable
              width: parent.width; height: sliders.each; icon: "brightness"; opens: true
              value: !win.be ? 0 : win.be.dimAware ? win.be.brightGrid : win.be.brightness / 100
              readout: !win.be ? "" : (win.be.dimAware ? Math.round(win.be.brightGrid * 100) : win.be.brightness) + " %"
              onMoved: v => win.be.dimAware ? win.be.setBrightGrid(v) : win.be.setBrightness(v * 100)
              onOpened: win.detail("display")
            }
            VFillSlider {
              width: parent.width; height: sliders.each; opens: true; iconAction: true
              icon: !win.be || win.be.muted || win.be.volume <= 0 ? "sound.mute" : win.be.volume < 0.34 ? "sound.low" : win.be.volume < 0.67 ? "sound.mid" : "sound"
              value: !win.be || win.be.muted ? 0 : win.be.volume
              readout: !win.be ? "" : win.be.muted ? "Muted" : Math.round(win.be.volume * 100) + " %"
              onMoved: v => win.be.setVolume(v); onIconClicked: win.be.toggleMute()
              onOpened: win.detail(win.be.airpodsActive ? "airpods" : "sound")
            }
          }
        }
      }

      // ============================================================ MacBook Air
      Box {
        order: 2
        height: macHead.height + win.cfg.inner + macBody.height + 2 * win.cfg.pad
        Head { id: macHead; icon: "laptop"; text: "MacBook Air"
          detail: power.timeText && power.timeText !== "—" ? power.timeLabel + " · " + power.timeText : "" }
        Row {
          id: macBody
          x: win.cfg.pad; y: macHead.y + macHead.height + win.cfg.inner; width: parent.width - 2 * x
          height: Math.max(macLeft.height, macRight.height)
          spacing: win.cfg.inner
          Column {
            id: macLeft
            width: (macBody.width - macBody.spacing) * win.cfg.split
            spacing: win.cfg.tileGap
            Grid {
              id: macTiles
              columns: 3; spacing: win.cfg.tileGap
              readonly property real cell: (macLeft.width - 2 * spacing) / 3
              Toggle { width: macTiles.cell; icon: "moon"; text: "Dark"; on: Theme.dark
                onTapped: win.velum.set("appearance", Theme.dark ? "light" : "dark") }
              Toggle { width: macTiles.cell; icon: "night-shift"; text: "Night Shift"; on: !!win.be && win.be.nightShift
                onTapped: win.be.setNightShift(!win.be.nightShift) }
              Toggle { width: macTiles.cell; icon: "keyboard.light"; text: "Key Light"; on: !!win.be && win.be.kbdAvailable && win.be.kbd.level > 0
                can: !!win.be && win.be.kbdAvailable; onTapped: win.detail("keyboard") }
              Toggle { width: macTiles.cell; icon: win.be && win.be.tilingLayout === "scrolling" ? "layout.columns" : "layout.tiles"; text: "Tiling"
                on: !!win.be && win.be.tilingLayout === "scrolling"
                onTapped: win.be.setTilingLayout(win.be.tilingLayout === "scrolling" ? "dwindle" : "scrolling") }
              Toggle { width: macTiles.cell; icon: "tablet"; text: "Tablet Mode"; on: Theme.touch
                onTapped: win.be.run("tablet-mode toggle") }
              Toggle { width: macTiles.cell; icon: "rotation.lock"; text: "Rotation"; on: !!win.be && win.be.rotationLocked
                can: !!win.be && win.be.rotationAvailable; onTapped: win.be.setRotationLocked(!win.be.rotationLocked) }
            }
            // the power mode, one card per profile
            Row {
              id: modes
              visible: power.profiles.length > 0
              spacing: win.cfg.tileGap
              readonly property real cell: (macLeft.width - (power.profiles.length - 1) * spacing) / Math.max(1, power.profiles.length)
              Repeater {
                model: power.profiles
                Mode { required property var modelData
                  width: modes.cell; icon: power.profileIcon(modelData); text: power.profileLabel(modelData)
                  selected: power.activeProfile === modelData; onChosen: power.setProfile(modelData) }
              }
            }
          }
          Column {
            id: macRight
            width: macBody.width - macLeft.width - macBody.spacing
            spacing: win.cfg.tileGap
            // the last hours (opens History)
            VTile {
              id: chartTile
              // as tall as the toggles and the power mode beside it leave over the numbers: no hole in the box
              width: parent.width; height: Math.max(0, macLeft.height - nums.height - macRight.spacing)
              visible: power.historyBars.length > 0
              Rectangle { anchors.fill: parent; radius: parent.radius; color: Theme.r.popover.fillHover; visible: chartMouse.containsMouse && Theme.hover }
              MouseArea { id: chartMouse; anchors.fill: parent; hoverEnabled: true; onClicked: win.detail("battery-history") }
              Column {
                id: chartCol
                x: win.cfg.pad; y: win.cfg.pad; width: parent.width - 2 * x
                spacing: Theme.layout.list.gap / 2
                Item {
                  id: chartHead
                  width: parent.width; height: Theme.layout.module.section / 2 + Theme.layout.list.gap
                  VText { anchors.verticalCenter: parent.verticalCenter; text: "Last " + power.historyRange.label
                    font.weight: Font.DemiBold; font.pixelSize: Theme.m.type.small; color: Theme.r.popover.inkSecondary }
                  VIcon { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    name: "chevron.right"; weight: "bold"; size: Theme.layout.icon.small; color: Theme.r.popover.inkSecondary }
                }
                VChart {
                  width: parent.width; height: chartTile.height - 2 * win.cfg.pad - chartCol.spacing - chartHead.height
                  values: power.historyBars.map(b => b ? b.pct / 100 : null)
                  marks: power.historyBars.map(b => !!b && !b.battery)
                }
              }
            }
            Row {
              id: nums
              spacing: win.cfg.tileGap
              readonly property real cell: (macRight.width - 2 * spacing) / 3
              Num { width: nums.cell; label: "Health"; value: power.health >= 0 ? Math.round(power.health * 100) + " %" : "—"; onTapped: win.detail("battery") }
              Num { width: nums.cell; label: "CPU"; value: !win.be || win.be.cpuLoad < 0 ? "--" : win.be.cpuLoad + " %"; onTapped: win.detail("hardware") }
              Num { width: nums.cell; label: "Memory"; value: win.be ? Math.round(win.be.memUsedFrac * 100) + " %" : ""; onTapped: win.detail("hardware") }
            }
          }
        }
      }

      // ============================================================ iPad
      Box {
        order: 3
        present: win.tablet
        height: padHead.height + win.cfg.inner + win.cfg.tile + 2 * win.cfg.pad
        Head { id: padHead; icon: "tablet"; text: "iPad"
          detail: !win.tablet ? "" : (win.ci.mode === "own" ? "Own Screen" : "Mirror")
            + (win.ci.size ? " · " + win.ci.size[0] + " × " + win.ci.size[1] + " · " + Math.round(win.ci.hz) + " Hz" : "") }
        Row {
          id: padTiles
          x: win.cfg.pad; y: padHead.y + padHead.height + win.cfg.inner
          spacing: win.cfg.tileGap
          // the cover's keys, its light and Power Mode only for a tablet that has them (the iPad: null
          // in cast.json, Henri 2026-11-11); the others share the row
          readonly property bool keys: typeof win.ci.tabletInput === "boolean"
          readonly property bool light: win.ci.kbdlight !== null && win.ci.kbdlight !== undefined
          readonly property bool perf: typeof win.ci.perfTablet === "boolean"
          readonly property int count: 3 + (keys ? 1 : 0) + (light ? 1 : 0) + (perf ? 1 : 0)
          readonly property real cell: (parent.width - 2 * win.cfg.pad - (count - 1) * spacing) / count
          // a tile shows its new state at the click: the tablet answers only in its next report (want)
          Toggle { width: padTiles.cell; icon: "laptop"; text: "Mac Keys"
            on: !!win.cast && win.cast.tileOn("mac", win.ci.macInput !== false)
            onTapped: { var v = !on; win.cast.setInput("mac", v); win.cast.want("mac", v) } }
          Toggle { width: padTiles.cell; icon: "tablet"; text: "iPad Keys"
            on: !!win.cast && win.cast.tileOn("tablet", win.ci.tabletInput === true); can: typeof win.ci.tabletInput === "boolean"; visible: padTiles.keys
            onTapped: { var v = !on; win.cast.setInput("tablet", v); win.cast.want("tablet", v) } }
          Toggle { width: padTiles.cell; icon: "keyboard.light"; text: "Cover Light"
            on: !!win.cast && win.cast.tileOn("light", win.ci.kbdlight === true); can: win.ci.keyboard === true; visible: padTiles.light
            onTapped: { var v = !on; win.cast.setKeyboardLight(v); win.cast.want("light", v) } }
          Toggle { width: padTiles.cell; icon: "gauge"; text: "Power Mode"
            on: !!win.cast && win.cast.tileOn("perf", win.ci.perf === true); can: typeof win.ci.perfTablet === "boolean"; visible: padTiles.perf
            onTapped: { var v = !on; win.cast.setPerf(v); win.cast.want("perf", v) } }
          Toggle { width: padTiles.cell; icon: "bolt"; text: "Fast Mode"
            on: !!win.cast && win.cast.tileOn("fast", win.ci.fast === true); can: typeof win.ci.fast === "boolean"
            onTapped: { var v = !on; win.cast.setFast(v); win.cast.want("fast", v) } }
          Toggle { width: padTiles.cell; icon: "mic"; text: "Microphone"
            on: !!win.cast && win.cast.tileOn("mic", win.ci.mic === true); can: typeof win.ci.micTablet === "boolean"
            onTapped: { var v = !on; win.cast.setMic(v); win.cast.want("mic", v) } }
        }
      }
    }
  }

  // a box fades in once the pull has come this far (one after the other)
  function reveal(k) {
    var start = k * cfg.stagger
    return Math.max(0, Math.min(1, (p - start) / (1 - start)))
  }

  // ---- detail pages: the island's, as a card over the boxes
  // the boxes step back (fade) while a detail card stands on the picture; a tap beside it puts it away
  MouseArea { anchors.fill: parent; enabled: win.detailOpen; visible: enabled; onClicked: win.leaveDetail() }
  Item {
    id: card
    property string velumSurface: "popover"
    readonly property real pad: Theme.layout.module.pad
    width: Theme.layout.module.island
    height: details.implicitHeight + 2 * pad
    x: Math.round((win.screenW - width) / 2); y: win.cfg.top
    opacity: win.detailOpen ? 1 : 0
    visible: opacity > 0
    scale: cardSpring.value
    Spring { id: cardSpring; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: win.detailOpen ? 1 : win.cfg.scaleFrom }
    Behavior on opacity { NumberAnimation { duration: win.detailOpen ? Theme.dur("fast") : Theme.exit(Theme.dur("fast")) } }
    // put away once faded: the next detail starts on its own page
    onVisibleChanged: if (!visible && !win.detailOpen) details.reset()
    readonly property real radius: Theme.m.radius.panel + Theme.layout.module.tileInset
    VShadow { layers: Theme.r.popover.shadow; radius: card.radius }
    Rectangle {
      anchors.fill: parent; radius: card.radius
      color: Theme.r.popover.bgOpaque
      border.width: Theme.layout.separator; border.color: Theme.r.line.rim
    }
    MouseArea { anchors.fill: parent }
    Pages {
      id: details
      x: card.pad; y: card.pad; width: card.width - 2 * card.pad
      be: win.be; velum: win.velum
      detailsOnly: true
      stagger: false
      maxHeight: win.screenH - win.cfg.top - win.cfg.margin - 2 * card.pad
      columnWidth: width
      onLeaveRequested: win.leaveDetail()
      onCloseRequested: win.dismissed()
    }
  }

  Item {
    id: keys
    focus: true
    Keys.onPressed: function (e) {
      if (e.key !== Qt.Key_Escape) return
      e.accepted = true
      win.back()
    }
  }

  // ---- parts
  // a box of the layout: the tile, its place in the reveal, swallows taps on its empty parts
  component Box: VTile {
    id: box
    property int order: 0
    property bool present: true
    visible: present
    width: boxes.width
    opacity: win.reveal(order)
    MouseArea { anchors.fill: parent }
  }
  // the head of a box: symbol, name, a note at the right end
  component Head: Item {
    id: head
    property string icon: ""
    property string text: ""
    property string detail: ""
    x: win.cfg.pad; y: win.cfg.pad; width: parent.width - 2 * x; height: Theme.layout.icon.regular
    Row {
      anchors.verticalCenter: parent.verticalCenter; spacing: Theme.layout.list.gap
      VIcon { anchors.verticalCenter: parent.verticalCenter; name: head.icon; weight: "fill"; size: Theme.layout.icon.regular; color: Theme.r.popover.inkSecondary }
      VText { anchors.verticalCenter: parent.verticalCenter; text: head.text; color: Theme.r.popover.ink; font.weight: Font.DemiBold }
    }
    VText { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: head.detail; tone: "secondary"; font.pixelSize: Theme.m.type.small }
  }
  // one item of the status line: a battery or a symbol, a title, what it is doing
  component StatusItem: Item {
    id: si
    property bool battery: false
    property real level: 0
    property bool charging: false
    property bool plugged: false
    property string icon: ""
    property string title: ""
    property string detail: ""
    signal tapped()
    width: siRow.width; height: siRow.height
    Row {
      id: siRow
      spacing: Theme.layout.list.gap
      VBattery { visible: si.battery; anchors.verticalCenter: parent.verticalCenter; level: si.level; charging: si.charging; plugged: si.plugged; surface: "popover" }
      VIcon { visible: !si.battery; anchors.verticalCenter: parent.verticalCenter; name: si.icon; weight: "fill"; color: Theme.r.popover.ink }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        VText { text: si.title; color: Theme.r.popover.ink; font.weight: Font.DemiBold }
        VText { text: si.detail; tone: "secondary"; font.pixelSize: Theme.m.type.small }
      }
    }
    MouseArea { anchors.fill: parent; onClicked: si.tapped() }
  }
  component Divider: Rectangle {
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    width: 1 / Screen.devicePixelRatio; height: win.cfg.statusDivider
    color: Theme.r.line.base
  }
  // a toggle tile: its symbol on a squircle and its name; on = the accent, dimmed while it cannot switch
  component Toggle: VTile {
    id: tg
    property string icon: ""
    property string text: ""
    property bool on: false
    property bool can: true
    signal tapped()
    height: win.cfg.tile
    radius: Theme.m.radius.row + Theme.layout.module.tileInset
    VPressable {
      id: tgPress
      anchors.fill: parent; radius: parent.radius
      enabled: tg.can
      selected: tg.on && tg.can
      onClicked: tg.tapped()
      Row {
        x: (win.cfg.tile - win.cfg.badge) / 2; anchors.verticalCenter: parent.verticalCenter
        width: parent.width - x; spacing: Theme.layout.list.gap
        Rectangle {
          width: win.cfg.badge; height: width; radius: Theme.m.radius.row
          color: tgPress.selected ? "transparent" : Theme.r.popover.badgeOff
          VIcon { anchors.centerIn: parent; name: tg.icon; weight: "fill"; color: tgPress.contentColor }
        }
        VText { anchors.verticalCenter: parent.verticalCenter; width: parent.width - win.cfg.badge - parent.spacing - win.cfg.inner
          text: tg.text; elide: Text.ElideRight; color: tgPress.contentColor; font.weight: Font.Medium }
      }
    }
  }
  // a power mode as a card: its symbol and name in a row, the accent rim while chosen
  component Mode: VTile {
    id: md
    property string icon: ""
    property string text: ""
    property bool selected: false
    signal chosen()
    height: win.cfg.tile
    radius: Theme.m.radius.row + Theme.layout.module.tileInset
    border.width: md.selected ? Theme.layout.separator * 2 : Theme.layout.separator
    border.color: md.selected ? Theme.r.accent.base : Theme.r.line.rim
    Spring { id: mdPress; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: mdMouse.pressed ? Theme.scale("press") : 1 }
    scale: mdPress.value
    Rectangle { anchors.fill: parent; radius: parent.radius; color: Theme.r.popover.fillHover; visible: mdMouse.containsMouse && Theme.hover && !md.selected }
    Row {
      anchors.centerIn: parent; spacing: Theme.layout.list.gap
      VIcon { anchors.verticalCenter: parent.verticalCenter; name: md.icon; weight: "fill"; color: md.selected ? Theme.r.accent.text : Theme.r.popover.inkSecondary }
      VText { anchors.verticalCenter: parent.verticalCenter; text: md.text
        font.weight: md.selected ? Font.DemiBold : Font.Medium; color: md.selected ? Theme.r.accent.text : Theme.r.popover.inkSecondary }
    }
    MouseArea { id: mdMouse; anchors.fill: parent; hoverEnabled: true; onClicked: md.chosen() }
  }
  // a number on a tile; a tap opens its page
  component Num: VStatTile {
    id: num
    height: win.cfg.tile
    signal tapped()
    MouseArea { anchors.fill: parent; onClicked: num.tapped() }
  }

  // the tablet window bar hides while this covers the screen (same overlay layer)
  readonly property bool covering: shown
  onCoveringChanged: VOverlays.hold(win, screen ? screen.name : "", covering)
  onScreenChanged: VOverlays.hold(win, screen ? screen.name : "", covering)
  Component.onDestruction: VOverlays.hold(win, "", false)
}
