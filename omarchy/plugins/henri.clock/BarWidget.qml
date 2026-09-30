import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Date/time label for the bar, and the host for two popups: the Notification
// Center (NotificationCenter.qml — like macOS, a click on the date opens the
// column of notifications and widgets) and the calendar (Panel.qml).
//
// Left click opens the Notification Center, right click walks the common
// label formats, middle click opens the calendar. The timezone picker moved
// to IPC (`omarchy-shell omarchy.clock timezone`).
BarWidget {
  id: root
  moduleName: "omarchy.clock"

  property date displayDate: clock.date

  readonly property string configuredFormat: vertical
    ? setting("verticalFormat", "HH\n—\nmm")
    : setting("format", "dddd HH:mm")
  readonly property string configuredAltFormat: vertical
    ? setting("verticalFormatAlt", "dd\nMMM\n'W'ww\n''yy")
    : setting("formatAlt", "d MMMM 'W'ww yyyy")

  readonly property var formatRing: Model.clockFormatRing(configuredFormat, configuredAltFormat, Model.clockFormats(vertical))

  // What the bar shows is what shell.json stores, so a cycled format is the
  // format from then on rather than something that reverts on restart.
  readonly property string activeFormat: configuredFormat
  readonly property string displayText: formatted(displayDate)
  readonly property var verticalLines: displayText.split("\n")

  function refresh() {
    displayDate = new Date()
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function cycleFormat() {
    var current = String(configuredFormat)
    var next = Model.nextClockFormat(formatRing, current)
    if (next === "" || next === current) return

    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[vertical ? "verticalFormat" : "format"] = next

    // Applied locally first so the label changes on the click itself; the
    // shell.json write comes back through the bar as the same value.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function formatted(date) {
    // German day and month names ("Mi. 16. Sept."); Qt.formatDateTime is always English.
    return Qt.locale("de_DE").toString(date, activeFormat.replace(/ww/g, Model.isoWeekLiteral(date.getFullYear(), date.getMonth(), date.getDate())))
  }

  // ---- Calendar popup. Shape contract for shell.summon/hide/toggle
  //      routing: Bar.findPanelWidget requires open/close/opened on the
  //      bar-widget root.
  readonly property bool calendarOpened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool centerOpened: centerLoader.item ? centerLoader.item.opened === true : false
  readonly property bool opened: calendarOpened || centerOpened

  // open/close/toggle are the bar's summon contract: they mean the Notification
  // Center now. The calendar keeps its own entry points.
  function open() {
    if (centerLoader.item) centerLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
    if (centerLoader.item) centerLoader.item.close()
  }

  function togglePanel() {
    if (centerLoader.item) centerLoader.item.toggle()
  }

  function openCalendar() {
    if (centerLoader.item) centerLoader.item.close()
    if (panelLoader.item) panelLoader.item.open()
  }

  function toggleCalendar() {
    if (!panelLoader.item) return
    if (panelLoader.item.opened) panelLoader.item.close()
    else openCalendar()
  }

  function toggleWeekStart() {
    if (panelLoader.item) panelLoader.item.toggleWeekStart()
  }

  // The clock fills more slot than it paints a mark for, at both
  // orientations: horizontally it is a text label in a padded slot, so the
  // dot takes the label width; vertically it is a stack of icon-sized lines,
  // so the dot takes one line — the same mark every icon widget gets, rather
  // than a rule running the height of the whole stack.
  readonly property real openPanelIndicatorWidth: button.labelWidth
  readonly property real openPanelIndicatorHeight: Math.max(Style.space(10), Math.round(Style.bar.iconSlot * 0.55))

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: (panelLoader.item && panelLoader.item.popoutSwitchClosing === true)
    || (centerLoader.item && centerLoader.item.popoutSwitchClosing === true)

  function closeForPopoutSwitch() {
    if (panelLoader.item && panelLoader.item.opened) panelLoader.item.closeForPopoutSwitch()
    if (centerLoader.item && centerLoader.item.opened) centerLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    injectInto(panelLoader.item)
    injectInto(centerLoader.item)
  }

  function injectInto(target) {
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  // Per-minute ticks unless the format shows seconds ("Show seconds" in
  // System Settings); a seconds tick all the time would wake the bar for nothing.
  SystemClock {
    id: clock
    precision: Model.formatHasSeconds(root.activeFormat) ? SystemClock.Seconds : SystemClock.Minutes
    onDateChanged: root.displayDate = date
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  Loader {
    id: centerLoader
    active: true
    source: Qt.resolvedUrl("NotificationCenter.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "omarchy.clock"

    function refresh(): void { root.broadcast("refresh") }
    function cycleFormat(): void { root.cycleFormat() }
    function toggleWeekStart(): void { root.toggleWeekStart() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function calendar(): void { root.toggleCalendar() }
    function notifications(): void { root.togglePanel() }
    function timezone(): void { if (root.bar) root.bar.run("omarchy-menu-timezone") }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "" : root.displayText
    labelVisible: !root.vertical
    hasVisualContent: root.vertical ? root.verticalLines.length > 0 : text !== ""
    fixedHeight: root.vertical ? root.verticalLines.length * Style.bar.iconSlot : -1
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(b) {
      if (b === Qt.RightButton) root.cycleFormat()
      else if (b === Qt.MiddleButton) root.toggleCalendar()
      else root.togglePanel()
    }

    Column {
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalLines

        OpticalGlyph {
          required property string modelData
          width: button.width
          height: Style.bar.iconSlot
          text: modelData
          fontFamily: button.fontFamily
          fontSize: modelData.length > 3
            ? button.fontSize * 0.9
            : button.fontSize
          color: button.foreground
        }
      }
    }
  }
}
