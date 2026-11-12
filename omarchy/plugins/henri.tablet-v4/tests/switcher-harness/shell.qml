import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "file:///home/henri/.local/share/velum/qml/Velum"
import "switcher"
import "widgets"

// The App Switcher / widgets harness (harness.sh): a plain Quickshell config in the nested rig, on its
// headless output SW, over the wallpaper — MaterialSwitcher wired as the owner will wire it
// (NavGesture's pull while a finger drives, open/closed after; switchTo/closeWindow as Hyprland
// dispatches into the NESTED compositor only), the four widgets on a page, the picker. IPC target
// "harness" (see harness.sh). Numbers here are the harness's own page layout, not component values.
ShellRoot {
  id: h

  property bool open: false          // the switcher, once no finger drives it
  property bool driven: false        // a test holds the switcher at `drivenP` (frames of the entrance)
  property real drivenP: 0
  property bool widgets: false
  property bool pickerOpen: false
  property var log: []
  function note(s) { var l = log.slice(-29); l.push(s); log = l }
  function dispatch(lua) { Hyprland.dispatch(lua) }

  readonly property string fonts: Quickshell.env("HARNESS_FONTS") || ""
  FontLoader { source: h.fonts ? "file://" + h.fonts + "/Roboto-Regular.ttf" : "" }
  FontLoader { source: h.fonts ? "file://" + h.fonts + "/Roboto-Medium.ttf" : "" }
  FontLoader { source: h.fonts ? "file://" + h.fonts + "/Roboto-Light.ttf" : "" }

  PanelWindow {
    id: win
    screen: Quickshell.screens.filter(function (s) { return s.name === "SW" })[0] || Quickshell.screens[0]
    anchors { top: true; left: true; right: true; bottom: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "velum-v4-harness"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    color: "transparent"
    // the home screen stands in: the wallpaper (only while the switcher or the widget page shows, so
    // the windows of the nested compositor are seen otherwise)
    mask: Region { item: h.open || h.driven || nav.dragging || sw.open || h.widgets || h.pickerOpen ? full : strip }
    Item { id: full; anchors.fill: parent }
    Item { id: strip; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; height: nav.height }

    Image {
      anchors.fill: parent
      visible: h.widgets || sw.open
      source: Quickshell.env("HARNESS_WALLPAPER") ? "file://" + Quickshell.env("HARNESS_WALLPAPER") : ""
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: width
      sourceSize.height: height
      asynchronous: true
    }

    // the widget page: a 6-column grid of cells as the home screen will have it
    Item {
      id: page
      anchors.fill: parent
      visible: h.widgets
      readonly property size cell: Qt.size((width - 48) / 6, (height - 120) / 5)
      Flow {
        x: 24; y: 72
        width: parent.width - 48
        spacing: 0
        Repeater {
          model: ["photos", "battery", "clock", "tablet"]
          Item {
            required property string modelData
            readonly property var span: modelData === "photos" ? [3, 2] : [2, 2]
            width: span[0] * page.cell.width
            height: span[1] * page.cell.height
            HomeWidget { anchors.fill: parent; anchors.margins: 12; kind: parent.modelData }
          }
        }
      }
    }

    MaterialSwitcher {
      id: sw
      anchors.fill: parent
      screenName: "SW"
      dragging: nav.dragging || h.driven
      progress: h.driven ? h.drivenP : nav.dragging ? nav.pull : h.open ? 1 : 0
      onSwitchTo: function (address) { h.note("switchTo " + address); h.dispatch("hl.dsp.focus({ window = \"address:" + address + "\" })"); h.open = false }
      onCloseWindow: function (address) { h.note("closeWindow " + address); h.dispatch("hl.dsp.window.close({ window = \"address:" + address + "\" })") }
      onClosed: { h.note("closed"); h.open = false }
    }
    NavGesture {
      id: nav
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      wayHome: h.widgets
      onOpenSwitcher: { h.note("nav switcher"); h.open = true }
      onHome: { h.note("nav home"); h.open = false; h.widgets = false }
      onSank: { h.note("nav back"); h.open = false }
    }
    WidgetPicker {
      id: picker
      anchors.fill: parent
      open: h.pickerOpen
      cell: page.cell
      onScreen: function (kind) { return kind === "clock" }
      onAdd: function (kind) { h.note("add " + kind); h.pickerOpen = false }
      onClosed: { h.note("picker closed"); h.pickerOpen = false }
    }
  }

  // a synthetic finger with real timing (speeds are measured from the clock): x/y glide in `steps`
  // moves `ms` apart, then rest `rest` ms, then lift. target: "switcher" or "nav"
  Timer {
    id: glider
    property var plan: null
    property int i: 0
    interval: 16
    repeat: true
    onTriggered: {
      var p = plan
      if (!p) { stop(); return }
      if (i <= p.steps) {
        var t = i / p.steps, x = p.x0 + (p.x1 - p.x0) * t, y = p.y0 + (p.y1 - p.y0) * t
        if (p.target === "nav") nav.update(y); else sw.drag(x, y)
        i++
        if (i > p.steps && p.rest > 0) { interval = p.rest; return }
        return
      }
      if (p.target === "nav") nav.end(); else sw.lift()
      plan = null
      stop()
    }
  }
  function glide(target, x0, y0, x1, y1, ms, steps, rest) {
    if (target === "nav") nav.begin(y0); else sw.press(x0, y0)
    glider.plan = { target: target, x0: x0, y0: y0, x1: x1, y1: y1, steps: Math.max(1, steps), rest: rest }
    glider.i = 1
    glider.interval = Math.max(1, Math.round(ms / Math.max(1, steps)))
    glider.restart()
  }

  IpcHandler {
    target: "harness"
    function open(): void { h.driven = false; h.open = true }
    function close(): void { h.driven = false; h.open = false }
    function drive(p: real): void { h.drivenP = p; h.driven = true }
    function undrive(open: bool): void { h.open = open; h.driven = false }
    function dark(on: bool): void { Theme.dark = on }
    function widgets(on: bool): void { h.widgets = on }
    function picker(on: bool): void { h.pickerOpen = on }
    function refresh(): void { Hyprland.refreshToplevels(); Hyprland.refreshMonitors() }
    function tap(x: real, y: real): void { sw.press(x, y); sw.lift() }
    function glide(target: string, x0: real, y0: real, x1: real, y1: real, ms: int, steps: int, rest: int): void { h.glide(target, x0, y0, x1, y1, ms, steps, rest) }
    function app(cls: string): string {
      var e = null, err = ""
      try { e = DesktopEntries.byId(cls) } catch (x) { err = String(x) }
      return JSON.stringify({ via: sw.appOf(cls, ""), byId: e ? e.name : null, err: err, n: DesktopEntries.applications.values.length })
    }
    function state(): string {
      return JSON.stringify({ sw: sw.info(), open: h.open, shown: sw.shown, nav: { last: nav.last, dragging: nav.dragging, pull: nav.pull },
                              picker: picker.info(), dark: Theme.dark, log: h.log, size: [win.width, win.height] })
    }
  }
}
