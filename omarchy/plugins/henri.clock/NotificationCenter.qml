import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "file:///home/henri/.local/share/apple-ui/Apple.js" as Apple
import "file:///home/henri/.local/share/apple-ui" as AUi

// The Notification Center behind the clock: a column of floating cards at the
// right screen edge (spec-mitteilungszentrale-macos.md) — notification stacks
// per app, then widgets, then "Widgets bearbeiten". There is no continuous
// sheet; every card carries its own glass, the compositor blur on the popup
// namespace (ignore_alpha 0.3) only touches the cards.
//
// Data: the shell's own notification daemon keeps every notification as a
// JSON file (live toasts in ~/.local/state/omarchy/notifications/, older ones
// in history/). This reads those files, groups them per app, and deletes
// them when a card is dismissed — so what the Center shows is exactly what the
// daemon knows, without a second store.
Panel {
  id: root
  moduleName: "omarchy.clock"
  ipcTarget: "henri.notification-center"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property var notificationService: bar && bar.shell && typeof bar.shell.firstPartyServiceFor === "function"
    ? bar.shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property var mediaService: bar && bar.shell && typeof bar.shell.firstPartyServiceFor === "function"
    ? bar.shell.firstPartyServiceFor("omarchy.media") : null

  // ---- Material: light or dark glass after the wallpaper under the column.
  AUi.Backdrop { id: backdrop; region: "30%x100%+0+0"; gravity: "NorthEast" }
  readonly property bool dark: backdrop.dark
  readonly property var nc: Apple.notificationCenter
  readonly property var pal: Apple.ncPalette(dark)
  readonly property string uiFont: Apple.uiFont
  readonly property string symbolFont: Apple.symbolFont
  function pt(v) { return Style.space(v) }
  function sf(cp) { return String.fromCodePoint(cp) }
  readonly property color ink: pal.textPrimary
  readonly property color inkSecondary: pal.textSecondary

  readonly property int columnWidth: pt(nc.width)
  readonly property int inset: pt(nc.edgeInset)
  readonly property int gap: pt(nc.gap)
  readonly property int smallW: Math.floor((columnWidth - gap) / 2)
  readonly property int smallH: pt(nc.widgetSmall)

  // ---- open / close (same contract as the calendar Panel)
  function open() {
    refresh()
    root.controller.show()
    Qt.callLater(function() { if (root.opened) setCenterHoverRevealSuppressed(true) })
  }
  function close() {
    setCenterHoverRevealSuppressed(false)
    root.editing = false
    contextMenu.hide()
    root.controller.hide()
  }
  function toggle() { opened ? close() : open() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar) root.bar.centerHoverRevealSuppressed = value
  }
  function run(cmd) { if (root.bar) root.bar.run(cmd) }

  // ---- Notifications ---------------------------------------------------------------

  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/notifications/"
  property var entries: []
  property var expandedKeys: ({})
  property double now: Date.now()
  property bool editing: false

  // One row per app (thread): the newest entry on top, the rest behind it.
  ListModel { id: stackModel }

  function refresh() {
    root.now = Date.now()
    reader.reload()
    events.refresh()
  }

  Process {
    id: reader
    running: false
    // One line per file: "<relative path>\t<json without newlines>".
    command: ["sh", "-c",
      "cd " + Util.shellQuote(root.stateDir) + " 2>/dev/null || exit 0; " +
      "for f in *.json history/*.json; do [ -f \"$f\" ] || continue; printf '%s\\t' \"$f\"; tr -d '\\n' < \"$f\"; echo; done"]
    stdout: StdioCollector { id: readerOut; waitForEnd: true }
    function reload() { reader.running = false; reader.running = true }
    onExited: function(code) {
      if (code !== 0) return
      var list = []
      var lines = String(readerOut.text || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i]
        var tab = line.indexOf("\t")
        if (tab < 0) continue
        var file = line.slice(0, tab)
        var entry
        try { entry = JSON.parse(line.slice(tab + 1)) } catch (e) { continue }
        if (!entry || typeof entry !== "object") continue
        entry.file = file
        entry.live = file.indexOf("history/") !== 0
        entry.timestamp = Number(entry.timestamp || 0)
        list.push(entry)
      }
      list.sort(function(a, b) { return b.timestamp - a.timestamp })
      root.entries = list
      root.syncStacks()
    }
  }

  // The daemon's model is not reachable through the plugin proxy, so while the
  // Center is open the files are re-read every few seconds (a toast arriving or
  // expiring moves one) and the relative timestamps tick with them.
  Timer { interval: 5000; repeat: true; running: root.opened; onTriggered: { root.now = Date.now(); reader.reload() } }

  function stackKey(e) { return String(e.app || "") }

  // Diff the grouped entries into stackModel so untouched stacks keep their
  // delegates (and with them their animations); only what changed is rewritten.
  function syncStacks() {
    var groups = [], byKey = {}
    for (var i = 0; i < entries.length; i++) {
      var e = entries[i]
      var key = stackKey(e)
      var g = byKey[key]
      if (!g) {
        g = { key: key, app: String(e.app || "Mitteilung"), items: [], sig: "" }
        byKey[key] = g
        groups.push(g)
      }
      g.items.push({
        file: String(e.file), live: !!e.live, app: String(e.app || ""), appIcon: String(e.appIcon || ""),
        summary: String(e.summary || ""), body: String(e.body || ""), image: String(e.image || ""),
        glyph: String(e.glyph || ""), execArgv: String(e.execArgv || ""), originalId: Number(e.originalId || 0),
        timestamp: e.timestamp
      })
      g.sig += e.file + ";"
    }
    for (var r = stackModel.count - 1; r >= 0; r--) if (!byKey[stackModel.get(r).key]) stackModel.remove(r)
    for (var n = 0; n < groups.length; n++) {
      var grp = groups[n]
      var at = -1
      for (var m = 0; m < stackModel.count; m++) if (stackModel.get(m).key === grp.key) { at = m; break }
      var row = { key: grp.key, app: grp.app, sig: grp.sig, count: grp.items.length, expanded: !!expandedKeys[grp.key], items: grp.items }
      if (at === -1) stackModel.insert(n, row)
      else {
        if (at !== n) stackModel.move(at, n, 1)
        if (stackModel.get(n).sig !== grp.sig) stackModel.set(n, row)
        else stackModel.setProperty(n, "expanded", row.expanded)
      }
    }
  }

  function setExpanded(key, on) {
    var next = {}
    for (var k in expandedKeys) next[k] = expandedKeys[k]
    if (on) next[key] = true; else delete next[key]
    expandedKeys = next
    for (var i = 0; i < stackModel.count; i++) if (stackModel.get(i).key === key) stackModel.setProperty(i, "expanded", on)
  }

  function relativeTime(t) {
    var diff = now - t
    var min = Math.floor(diff / 60000)
    if (min < 1) return "jetzt"
    if (min < 60) return "vor " + min + " Min."
    var d = new Date(t), today = new Date(now)
    var loc = Qt.locale("de_DE")
    if (d.toDateString() === today.toDateString()) return loc.toString(d, "HH:mm")
    var yesterday = new Date(now - 86400000)
    if (d.toDateString() === yesterday.toDateString()) return "gestern"
    if (diff < 6 * 86400000) return loc.toString(d, "dddd")
    return loc.toString(d, "d. MMM")
  }

  // Dismissing removes the daemon's file (history) or dismisses the live toast
  // through the daemon, which archives it — so the archive is deleted right after.
  function removeFiles(files) {
    if (files.length === 0) return
    var cmd = "cd " + Util.shellQuote(root.stateDir) + " && rm -f"
    for (var i = 0; i < files.length; i++) {
      var f = String(files[i])
      cmd += " " + Util.shellQuote(f) + " " + Util.shellQuote("history/" + f.replace(/^history\//, ""))
      cmd += " " + Util.shellQuote("images/" + f.replace(/^history\//, "").replace(/\.json$/, "") + ".*")
    }
    remover.command = ["sh", "-c", cmd]
    remover.running = true
  }
  Process { id: remover; running: false; onExited: reader.reload() }

  // A live toast's file goes too; the daemon's later archive of it finds
  // nothing to move and the toast simply expires on screen.
  function dismissEntries(items) {
    var files = []
    for (var i = 0; i < items.length; i++) files.push(items[i].file)
    removeFiles(files)
  }

  // Opening a notification focuses its sender, like the daemon's own click
  // fallback (the helper matches the window class case-insensitively).
  function openEntry(it) {
    if (it.app) root.run(Util.shellQuote(Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-hyprland-focus-app") + " " + Util.shellQuote(String(it.app)))
    dismissEntries([it])
    root.close()
  }

  // ---- Do-not-disturb helpers for the context menu (the daemon has one global switch).
  Timer {
    id: muteTimer
    repeat: false
    onTriggered: if (root.notificationService) root.notificationService.setDoNotDisturb(false)
  }
  function mute(ms) {
    if (!root.notificationService) return
    root.notificationService.setDoNotDisturb(true)
    muteTimer.interval = ms
    muteTimer.restart()
  }
  function muteUntilMidnight() {
    var d = new Date(); d.setHours(24, 0, 0, 0)
    mute(Math.max(60000, d.getTime() - Date.now()))
  }

  // ---- Widgets -----------------------------------------------------------------------------

  readonly property var widgetCatalogue: [
    { id: "calendar", title: "Kalender", sizes: ["small", "medium", "large"] },
    { id: "clock", title: "Uhr", sizes: ["small"] },
    { id: "media", title: "Wiedergabe", sizes: ["medium"] },
    { id: "battery", title: "Batterie", sizes: ["small", "medium"] }
  ]
  readonly property var defaultWidgets: [
    { id: "calendar", size: "small" }, { id: "clock", size: "small" },
    { id: "media", size: "medium" }, { id: "battery", size: "small" }
  ]
  ListModel { id: widgetModel }
  function catalogueEntry(id) {
    for (var i = 0; i < widgetCatalogue.length; i++) if (widgetCatalogue[i].id === id) return widgetCatalogue[i]
    return null
  }
  function loadWidgets() {
    var cfg = setting("widgets", null)
    if (!Array.isArray(cfg)) cfg = defaultWidgets
    widgetModel.clear()
    for (var i = 0; i < cfg.length; i++) {
      var w = cfg[i]
      var def = w && catalogueEntry(String(w.id))
      if (!def) continue
      var size = def.sizes.indexOf(String(w.size)) >= 0 ? String(w.size) : def.sizes[0]
      widgetModel.append({ wid: def.id, size: size, title: def.title })
    }
  }
  function widgetsConfig() {
    var out = []
    for (var i = 0; i < widgetModel.count; i++) out.push({ id: widgetModel.get(i).wid, size: widgetModel.get(i).size })
    return out
  }
  function saveWidgets() { persistSettings({ widgets: widgetsConfig() }) }
  function removeWidget(index) { widgetModel.remove(index); saveWidgets() }
  function setWidgetSize(index, size) { widgetModel.setProperty(index, "size", size); saveWidgets() }
  function addWidget(id, size) {
    for (var i = widgetModel.count - 1; i >= 0; i--) if (widgetModel.get(i).wid === id) widgetModel.remove(i)
    var def = catalogueEntry(id)
    if (!def) return
    widgetModel.insert(0, { wid: id, size: size, title: def.title })
    saveWidgets()
  }
  function hiddenWidgets() {
    var shown = {}
    for (var i = 0; i < widgetModel.count; i++) shown[widgetModel.get(i).wid] = true
    return widgetCatalogue.filter(function(d) { return !shown[d.id] })
  }
  onSettingsChanged: loadWidgets()
  Component.onCompleted: loadWidgets()

  // Same write path as the calendar panel: the widget entry in shell.json.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Calendar widget data: today and the week after, from the synced iCloud vdir.
  EventService {
    id: events
    rangeFrom: Qt.locale("en_US").toString(new Date(root.now), "yyyy-MM-dd")
    rangeTo: Qt.locale("en_US").toString(new Date(root.now + 7 * 86400000), "yyyy-MM-dd")
  }
  function upcomingEvents(max) {
    var out = []
    for (var d = 0; d < 8 && out.length < max; d++) {
      var day = new Date(root.now + d * 86400000)
      var key = Qt.locale("en_US").toString(day, "yyyy-MM-dd")
      var list = events.eventsOn(key)
      for (var i = 0; i < list.length && out.length < max; i++) {
        var ev = list[i]
        out.push({ day: d, summary: ev.summary || "", start: ev.start || "", allDay: !!ev.allDay, color: ev.color || "" })
      }
    }
    return out
  }
  SystemClock { id: clock; precision: SystemClock.Seconds }

  // ---- The window ----------------------------------------------------------------------------

  HUi.PopupPanel {
    id: panel
    kind: "toast"                      // slides, no scaling — the column comes in from the right edge
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    margin: root.inset
    gap: root.inset
    padding: 0
    cardColor: "transparent"
    borderSpec: Border.none()
    contentWidth: panel.fittedContentWidth(root.columnWidth)
    contentHeight: panel.availableCardHeight > 0 ? Math.round(panel.availableCardHeight) : root.pt(600)
    revealFromX: root.columnWidth + root.inset

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (contextMenu.open) contextMenu.hide()
        else if (root.editing) root.editing = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: scroller
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + root.inset
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        flickDeceleration: Motion.flickDeceleration
        maximumFlickVelocity: Motion.maximumFlickVelocity
        interactive: contentHeight > height

        // Two-finger swipe to the right closes the Center (spec 2.2).
        property real swipeX: 0
        WheelHandler {
          acceptedDevices: PointerDevice.TouchPad
          onWheel: function(ev) {
            var dx = ev.pixelDelta.x !== 0 ? ev.pixelDelta.x : ev.angleDelta.x / 4
            var dy = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : ev.angleDelta.y / 4
            if (Math.abs(dx) <= Math.abs(dy)) return
            scroller.swipeX = Math.max(0, scroller.swipeX + dx)
            swipeSettle.restart()
          }
        }
        Timer {
          id: swipeSettle
          interval: 120
          onTriggered: {
            var closeIt = scroller.swipeX > root.columnWidth * 0.3
            scroller.swipeX = 0
            if (closeIt) root.close()
          }
        }
        transform: Translate { x: dragX.value }
        HUi.SpringValue { id: dragX; to: scroller.swipeX; preset: Motion.smooth }

        Column {
          id: column
          width: scroller.width
          spacing: root.gap
          move: Transition {
            NumberAnimation { properties: "x,y"; duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut }
          }

          // "Nicht stören" hint (spec §9, Fokus-Modus)
          NcCard {
            visible: root.notificationService ? root.notificationService.doNotDisturb : false
            width: column.width
            height: root.pt(32)
            radius: root.pt(12)
            Row {
              anchors.centerIn: parent
              spacing: root.pt(8)
              Text { text: root.sf(0x1002DD); font.family: root.symbolFont; font.pixelSize: root.pt(12); color: root.inkSecondary; anchors.verticalCenter: parent.verticalCenter }
              Text { text: "„Nicht stören“ ist aktiv"; font.family: root.uiFont; font.pixelSize: root.pt(nc.metaFont); color: root.inkSecondary; anchors.verticalCenter: parent.verticalCenter }
            }
          }

          // ---- Notification stacks
          Repeater {
            model: stackModel
            delegate: NcStack { width: column.width }
          }

          // ---- Widgets: small ones pair up left to right, medium/large take the full width.
          Item { width: 1; height: root.gap / 2; visible: stackModel.count > 0 }
          Flow {
            id: widgetFlow
            width: column.width
            spacing: root.gap
            move: Transition {
              enabled: !widgetDrag.active
              NumberAnimation { properties: "x,y"; duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut }
            }
            add: Transition {
              NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
              NumberAnimation { property: "scale"; from: 0.9; to: 1; duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
            }
            Repeater {
              model: widgetModel
              delegate: NcWidget {}
            }
          }

          // ---- Edit mode: what can still be added
          NcCard {
            visible: root.editing && root.hiddenWidgets().length > 0
            width: column.width
            height: galleryColumn.implicitHeight + root.pt(nc.cardPadding) * 2
            Column {
              id: galleryColumn
              x: root.pt(nc.cardPadding); y: root.pt(nc.cardPadding)
              width: parent.width - root.pt(nc.cardPadding) * 2
              spacing: root.pt(6)
              Text { text: "Widgets hinzufügen"; font.family: root.uiFont; font.pixelSize: root.pt(nc.metaFont); font.weight: Font.DemiBold; color: root.inkSecondary }
              Repeater {
                model: root.editing ? root.hiddenWidgets() : []
                delegate: Row {
                  required property var modelData
                  spacing: root.pt(6)
                  height: root.pt(nc.capsuleHeight)
                  Text { text: modelData.title; font.family: root.uiFont; font.pixelSize: root.pt(nc.bodyFont); color: root.ink; width: root.pt(100); anchors.verticalCenter: parent.verticalCenter }
                  Repeater {
                    model: modelData.sizes
                    delegate: NcCapsule {
                      required property string modelData
                      required property int index
                      readonly property string sizeId: modelData
                      label: sizeId === "small" ? "Klein" : sizeId === "medium" ? "Mittel" : "Groß"
                      onClicked: root.addWidget(parent.modelData.id, sizeId)
                    }
                  }
                }
              }
            }
          }

          // ---- "Widgets bearbeiten"
          Item {
            width: column.width
            height: root.pt(nc.editButtonHeight) + root.pt(4)
            NcCapsule {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              height: root.pt(nc.editButtonHeight)
              radius: height / 2
              label: root.editing ? "Fertig" : "Widgets bearbeiten"
              fontWeight: Font.Medium
              fontSize: root.pt(nc.bodyFont)
              glass: true
              onClicked: root.editing = !root.editing
            }
          }
        }
      }

      // ---- Dragged widget ghost (edit mode): the real tile stays in the Flow as
      //      a placeholder; the ghost follows the pointer and neighbours make room.
      QtObject {
        id: widgetDrag
        property bool active: false
        property int index: -1
        property real grabX: 0
        property real grabY: 0
      }
      Loader {
        id: ghost
        visible: widgetDrag.active
        z: 50
        property real px: 0
        property real py: 0
        x: px - widgetDrag.grabX
        y: py - widgetDrag.grabY
        scale: Motion.liftScale
        opacity: 0.92
        sourceComponent: widgetDrag.active ? ghostComponent : null
      }
      Component {
        id: ghostComponent
        NcWidgetFace {
          id: face
          readonly property var row: widgetDrag.index >= 0 && widgetDrag.index < widgetModel.count ? widgetModel.get(widgetDrag.index) : null
          widgetId: row ? row.wid : ""
          size: row ? row.size : "small"
        }
      }

      // ---- Context menu (right click / Optionen): the shared henri-ui menu.
      HUi.Reveal {
        id: contextMenu
        kind: "menu"
        origin: Item.TopLeft
        z: 60
        property var entries: []
        property var handler: null
        function show(sceneX, sceneY, list, fn) {
          var p = keyCatcher.mapFromItem(null, sceneX, sceneY)
          entries = list
          handler = fn
          x = Math.min(p.x, keyCatcher.width - menuSurface.implicitWidth - root.pt(4))
          y = Math.min(p.y, keyCatcher.height - menuSurface.implicitHeight - root.pt(4))
          open = true
        }
        function hide() { open = false }
        onDismissRequested: hide()
        closeOnOutsideClick: true
        width: menuSurface.implicitWidth
        height: menuSurface.implicitHeight
        HUi.Surface {
          id: menuSurface
          anchors.fill: parent
          role: "menu"; kind: "menu"
          padding: Style.space(5)
          implicitWidth: menuList.implicitWidth + padding * 2
          implicitHeight: menuList.implicitHeight + padding * 2
          HUi.MenuList {
            id: menuList
            x: menuSurface.contentLeftInset; y: menuSurface.contentTopInset
            width: parent.width - menuSurface.contentLeftInset - menuSurface.contentRightInset
            focus: contextMenu.open
            model: contextMenu.entries
            onActivated: function(index, entry) {
              contextMenu.hide()
              if (contextMenu.handler) contextMenu.handler(entry)
            }
          }
        }
      }
    }
  }

  // ---- Components ----------------------------------------------------------------------------

  // A floating card: tint, inner highlight hairline, outer hairline, contact shadow.
  component NcCard: Item {
    id: card
    property real radius: root.pt(nc.radiusCard)
    property alias color: fill.color
    default property alias content: fill.data
    Rectangle {
      // Shadow stand-in (no blur: a soft plate slightly below the card).
      anchors.fill: fill
      anchors.topMargin: root.pt(3)
      anchors.leftMargin: root.pt(1)
      anchors.rightMargin: root.pt(1)
      radius: card.radius
      color: pal.shadow
    }
    Rectangle {
      id: fill
      anchors.fill: parent
      radius: card.radius
      color: Motion.glass ? pal.tint : pal.opaque
      border.width: 1
      border.color: pal.borderOuter
      antialiasing: true
      Behavior on color { ColorAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: parent.radius - 1
        color: "transparent"
        border.width: 1
        border.color: pal.borderInner
        antialiasing: true
      }
    }
  }

  // Capsule button: "Weniger anzeigen", "Alle löschen", "Widgets bearbeiten".
  component NcCapsule: HUi.Pressable {
    id: cap
    property string label: ""
    property string symbol: ""
    property int fontWeight: Font.DemiBold
    property int fontSize: root.pt(12)
    property bool glass: false
    property bool danger: false
    implicitHeight: root.pt(nc.capsuleHeight)
    implicitWidth: capRow.implicitWidth + root.pt(label !== "" ? 20 : 12)
    radius: height / 2
    tint: root.ink
    showFill: false
    Rectangle {
      anchors.fill: parent
      radius: cap.radius
      color: cap.danger ? Apple.systemRed : cap.glass ? (Motion.glass ? pal.tint : pal.opaque) : (cap.hovered ? pal.capsuleHover : pal.capsule)
      border.width: cap.glass ? 1 : 0
      border.color: pal.borderOuter
      Behavior on color { ColorAnimation { duration: cap.hovered ? Motion.instant : Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    }
    Row {
      id: capRow
      anchors.centerIn: parent
      spacing: root.pt(4)
      Text { visible: cap.symbol !== ""; text: cap.symbol; font.family: root.symbolFont; font.pixelSize: cap.fontSize; color: cap.danger ? "#ffffff" : root.ink; anchors.verticalCenter: parent.verticalCenter }
      Text { visible: cap.label !== ""; text: cap.label; font.family: root.uiFont; font.pixelSize: cap.fontSize; font.weight: cap.fontWeight; color: cap.danger ? "#ffffff" : root.ink; anchors.verticalCenter: parent.verticalCenter }
    }
  }

  // Round close/minus button that overlaps a card's top-left corner.
  component NcCornerButton: HUi.Pressable {
    id: corner
    property string label: ""
    property string symbol: root.sf(0x100184)
    property bool grey: false
    property real size: root.pt(nc.closeButton)
    implicitHeight: size
    implicitWidth: size + (label !== "" && corner.hovered ? labelText.implicitWidth + root.pt(10) : 0)
    radius: height / 2
    showFill: false
    tint: root.ink
    Behavior on implicitWidth { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    Rectangle {
      anchors.fill: parent
      radius: corner.radius
      color: corner.grey ? Apple.systemGray : (Motion.glass ? pal.tint : pal.opaque)
      border.width: 1
      border.color: pal.borderOuter
      Rectangle { anchors.fill: parent; anchors.margins: 1; radius: parent.radius - 1; color: "transparent"; border.width: 1; border.color: pal.borderInner }
    }
    Text {
      x: (corner.size - width) / 2
      anchors.verticalCenter: parent.verticalCenter
      text: corner.symbol
      font.family: root.symbolFont
      font.pixelSize: corner.size * 0.5
      font.weight: Font.Bold
      color: corner.grey ? "#ffffff" : root.ink
    }
    Text {
      id: labelText
      x: corner.size - root.pt(2)
      anchors.verticalCenter: parent.verticalCenter
      text: corner.label
      font.family: root.uiFont
      font.pixelSize: root.pt(11)
      font.weight: Font.DemiBold
      color: root.ink
      opacity: corner.label !== "" && corner.hovered ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    }
  }

  // One app's notifications: collapsed = newest card + up to two strips; expanded = header + all.
  component NcStack: Item {
    id: stack
    required property var model
    required property int index
    readonly property string key: model.key
    readonly property bool expanded: model.expanded
    readonly property int count: model.count
    readonly property var items: model.items
    readonly property bool group: count > 1
    property bool leaving: false
    implicitHeight: stackColumn.implicitHeight + (group && !expanded ? root.pt(nc.stripOffset * 2) : 0)
    height: implicitHeight
    opacity: leaving ? 0 : 1
    transform: Translate { x: stack.leaving ? stack.width + root.inset : 0
      Behavior on x { NumberAnimation { duration: Motion.exit(Motion.slow); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeExit } } }
    Behavior on opacity { NumberAnimation { duration: Motion.exit(Motion.slow); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeExit } }
    Behavior on height { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }

    function allItems() {
      var out = []
      for (var i = 0; i < items.count; i++) out.push(items.get(i))
      return out
    }
    function dismissAll() {
      stack.leaving = true
      dismissDelay.restart()
    }
    Timer { id: dismissDelay; interval: Motion.exit(Motion.slow); onTriggered: root.dismissEntries(stack.allItems()) }

    // Strips behind the top card (collapsed group).
    Repeater {
      model: stack.group && !stack.expanded ? Math.min(2, stack.count - 1) : 0
      delegate: NcCard {
        required property int index
        readonly property int level: index + 1
        width: stack.width
        height: root.pt(nc.cardMinHeight)
        y: topCard.h - height + root.pt(nc.stripOffset) * level
        transformOrigin: Item.Top
        scale: level === 1 ? nc.stripScale2 : nc.stripScale3
        opacity: level === 1 ? nc.stripAlpha2 : nc.stripAlpha3
        z: -level
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      }
    }

    Column {
      id: stackColumn
      width: stack.width
      spacing: root.gap
      move: Transition {
        NumberAnimation { properties: "x,y"; duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut }
      }

      // Header while expanded
      Item {
        width: stackColumn.width
        height: visible ? root.pt(nc.capsuleHeight) : 0
        visible: stack.expanded
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        Text {
          anchors.left: parent.left
          anchors.leftMargin: root.pt(4)
          anchors.verticalCenter: parent.verticalCenter
          text: stack.model.app
          font.family: root.uiFont
          font.pixelSize: root.pt(nc.titleFont)
          font.weight: Font.DemiBold
          color: root.ink
        }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: root.pt(6)
          NcCapsule { label: "Weniger anzeigen"; onClicked: root.setExpanded(stack.key, false) }
          NcCapsule { symbol: root.sf(0x100184); onClicked: stack.dismissAll() }
        }
      }

      Repeater {
        id: cardRepeater
        model: stack.items
        delegate: NcNotificationCard {
          required property var model
          required property int index
          stackItem: stack
          entry: model
          width: stackColumn.width
          visible: index === 0 || stack.expanded
          collapsedGroup: stack.group && !stack.expanded
        }
      }
    }
    QtObject { id: topCard; readonly property real h: cardRepeater.count > 0 && cardRepeater.itemAt(0) ? cardRepeater.itemAt(0).height : root.pt(nc.cardMinHeight) }
  }

  // A notification card. Hover shows the close button; swipe reveals Optionen/Löschen.
  component NcNotificationCard: Item {
    id: card
    property var entry: null
    property var stackItem: null
    property bool collapsedGroup: false
    property bool leaving: false
    property real swipeX: 0
    readonly property bool revealed: swipeX <= -root.pt(nc.swipeActions) + 1
    readonly property int padding: root.pt(nc.cardPadding)
    readonly property int iconSize: root.pt(nc.icon)
    implicitHeight: Math.max(root.pt(nc.cardMinHeight), textColumn.implicitHeight + padding * 2)
    height: implicitHeight
    opacity: leaving ? 0 : 1
    transform: Translate { x: card.leaving ? card.width + root.inset : 0
      Behavior on x { NumberAnimation { duration: Motion.exit(Motion.slow); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeExit } } }
    Behavior on opacity { NumberAnimation { duration: Motion.exit(Motion.slow); easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeExit } }
    // Appears: fade + slight settle from above (expanding a stack, a new notification).
    onVisibleChanged: if (visible) { appear.snap(0); appear.to = 1 }
    HUi.SpringValue { id: appear; to: 1; preset: Motion.snappy }
    Component.onCompleted: { appear.snap(0); appear.to = 1 }

    function dismiss() {
      if (card.collapsedGroup) { card.stackItem.dismissAll(); return }
      card.leaving = true
      dismissDelay.restart()
    }
    Timer { id: dismissDelay; interval: Motion.exit(Motion.slow); onTriggered: root.dismissEntries([card.entry]) }
    function activate() {
      if (card.revealed) { card.swipeX = 0; return }
      if (card.collapsedGroup) root.setExpanded(card.stackItem.key, true)
      else root.openEntry(card.entry)
    }
    function showMenu(sx, sy) {
      root.contextMenuFor(card.entry, sx, sy)
    }

    Item {
      anchors.fill: parent
      opacity: appear.value
      transform: Translate { y: (1 - appear.value) * -root.pt(8) }

      // Swipe actions behind the card
      Row {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        visible: card.swipeX < 0
        clip: true
        Rectangle {
          width: root.pt(nc.swipeActions) / 2; height: parent.height
          color: Apple.systemGray
          topLeftRadius: root.pt(nc.radiusCard); bottomLeftRadius: root.pt(nc.radiusCard)
          Text { anchors.centerIn: parent; text: "Optionen"; color: "#ffffff"; font.family: root.uiFont; font.pixelSize: root.pt(12); font.weight: Font.DemiBold }
          MouseArea { anchors.fill: parent; onClicked: function(m) { var p = mapToItem(null, m.x, m.y); card.showMenu(p.x, p.y) } }
        }
        Rectangle {
          width: root.pt(nc.swipeActions) / 2; height: parent.height
          color: Apple.systemRed
          topRightRadius: root.pt(nc.radiusCard); bottomRightRadius: root.pt(nc.radiusCard)
          Text { anchors.centerIn: parent; text: "Löschen"; color: "#ffffff"; font.family: root.uiFont; font.pixelSize: root.pt(12); font.weight: Font.DemiBold }
          MouseArea { anchors.fill: parent; onClicked: card.dismiss() }
        }
      }

      NcCard {
        id: face
        anchors.fill: parent
        transform: Translate { x: slideX.value }
        HUi.SpringValue { id: slideX; to: card.swipeX; preset: Motion.snappy }
        scale: press.pressed ? Motion.pressScale : 1
        Behavior on scale { NumberAnimation { duration: press.pressed ? Motion.instant : Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }

        HoverHandler { id: hover }
        TapHandler {
          id: press
          acceptedButtons: Qt.LeftButton
          onTapped: card.activate()
        }
        TapHandler {
          acceptedButtons: Qt.RightButton
          onTapped: function(ev) { var p = face.mapToItem(null, ev.position.x, ev.position.y); card.showMenu(p.x, p.y) }
        }
        WheelHandler {
          acceptedDevices: PointerDevice.TouchPad
          onWheel: function(ev) {
            var dx = ev.pixelDelta.x !== 0 ? ev.pixelDelta.x : ev.angleDelta.x / 4
            var dy = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : ev.angleDelta.y / 4
            if (Math.abs(dx) <= Math.abs(dy)) return
            if (dx > 0 && card.swipeX >= 0) return   // swiping right on a closed card: the column takes it
            ev.accepted = true
            card.swipeX = Math.max(-card.width, Math.min(0, card.swipeX + dx))
            cardSwipeSettle.restart()
          }
        }
        Timer {
          id: cardSwipeSettle
          interval: 120
          onTriggered: {
            if (card.swipeX < -card.width * nc.swipeDelete) { card.swipeX = -card.width; card.dismiss(); return }
            card.swipeX = card.swipeX < -root.pt(60) ? -root.pt(nc.swipeActions) : 0
          }
        }

        // App symbol
        Item {
          id: iconBox
          x: card.padding; y: card.padding
          width: card.iconSize; height: card.iconSize
          Rectangle {
            anchors.fill: parent
            radius: width * nc.iconRadius
            color: pal.capsule
            visible: !appImage.visible
            Text {
              anchors.centerIn: parent
              text: card.entry && card.entry.glyph !== "" ? card.entry.glyph : root.sf(0x1002DA)
              font.family: card.entry && card.entry.glyph !== "" ? Style.font.family : root.symbolFont
              font.pixelSize: root.pt(16)
              color: root.ink
            }
          }
          Image {
            id: appImage
            anchors.fill: parent
            source: card.entry && card.entry.appIcon !== "" ? (card.entry.appIcon.indexOf("/") === 0 ? "file://" + card.entry.appIcon : Quickshell.iconPath(card.entry.appIcon, true)) : ""
            visible: status === Image.Ready
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            smooth: true
          }
        }

        Column {
          id: textColumn
          x: card.padding + card.iconSize + root.pt(nc.iconGap)
          y: card.padding
          width: parent.width - x - card.padding - (thumb.visible ? thumb.width + root.pt(10) : 0)
          spacing: root.pt(1)
          Item {
            width: parent.width
            height: root.pt(nc.lineHeight)
            Text {
              anchors.left: parent.left
              anchors.right: timeText.left
              anchors.rightMargin: root.pt(8)
              anchors.verticalCenter: parent.verticalCenter
              text: card.entry ? (card.entry.summary !== "" ? card.entry.summary : card.entry.app) : ""
              font.family: root.uiFont
              font.pixelSize: root.pt(nc.titleFont)
              font.weight: Font.DemiBold
              color: root.ink
              elide: Text.ElideRight
            }
            Text {
              id: timeText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: card.entry ? root.relativeTime(card.entry.timestamp) : ""
              font.family: root.uiFont
              font.pixelSize: root.pt(nc.metaFont)
              color: root.inkSecondary
            }
          }
          Text {
            width: parent.width
            text: card.entry ? card.entry.body : ""
            font.family: root.uiFont
            font.pixelSize: root.pt(nc.bodyFont)
            lineHeight: root.pt(nc.lineHeight)
            lineHeightMode: Text.FixedHeight
            color: root.ink
            wrapMode: Text.Wrap
            maximumLineCount: nc.bodyLines
            elide: Text.ElideRight
            textFormat: Text.PlainText
            visible: text !== ""
          }
          Text {
            visible: card.collapsedGroup
            text: (card.stackItem ? card.stackItem.count - 1 : 0) + " weitere " + ((card.stackItem && card.stackItem.count - 1 === 1) ? "Mitteilung" : "Mitteilungen")
            font.family: root.uiFont
            font.pixelSize: root.pt(nc.metaFont)
            color: root.inkSecondary
          }
        }

        Image {
          id: thumb
          anchors.right: parent.right
          anchors.rightMargin: card.padding
          anchors.top: parent.top
          anchors.topMargin: card.padding
          width: root.pt(nc.thumb); height: width
          source: card.entry && card.entry.image !== "" ? (card.entry.image.indexOf("/") === 0 ? "file://" + card.entry.image : card.entry.image) : ""
          visible: status === Image.Ready
          fillMode: Image.PreserveAspectCrop
          sourceSize.width: width * 2
          sourceSize.height: height * 2
        }
      }

      // Close button, overlapping the top-left corner; on a stack it grows into "Alle löschen".
      NcCornerButton {
        x: -root.pt(6); y: -root.pt(6)
        label: card.collapsedGroup ? "Alle löschen" : ""
        opacity: hover.hovered || hovered ? 1 : 0
        scale: hover.hovered || hovered ? 1 : 0.8
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
        onClicked: card.dismiss()
      }
    }
  }

  function contextMenuFor(entry, sx, sy) {
    var list = [
      { text: "Für 1 Stunde stummschalten", id: "hour" },
      { text: "Heute stummschalten", id: "today" },
      { separator: true },
      { text: "Mitteilungseinstellungen …", id: "settings" }
    ]
    contextMenu.show(sx, sy, list, function(e) {
      if (e.id === "hour") root.mute(3600000)
      else if (e.id === "today") root.muteUntilMidnight()
      else if (e.id === "settings") root.run("omarchy-launch-or-focus omarchy-menu 'omarchy-menu setup'")
    })
  }

  function widgetMenuFor(index, sx, sy) {
    var row = widgetModel.get(index)
    var def = catalogueEntry(row.wid)
    var list = []
    var sizes = [["small", "Klein"], ["medium", "Mittel"], ["large", "Groß"]]
    for (var i = 0; i < sizes.length; i++)
      list.push({ text: sizes[i][1], id: "size:" + sizes[i][0], enabled: def.sizes.indexOf(sizes[i][0]) >= 0, checked: row.size === sizes[i][0] })
    list.push({ separator: true })
    list.push({ text: "Widget entfernen", id: "remove", danger: true })
    list.push({ separator: true })
    list.push({ text: "Widgets bearbeiten …", id: "edit" })
    contextMenu.show(sx, sy, list, function(e) {
      if (String(e.id).indexOf("size:") === 0) root.setWidgetSize(index, String(e.id).slice(5))
      else if (e.id === "remove") root.removeWidget(index)
      else if (e.id === "edit") root.editing = true
    })
  }

  // A widget tile in the Flow (size from the model), with edit-mode minus and drag.
  component NcWidget: Item {
    id: tile
    required property var model
    required property int index
    readonly property string widgetId: model.wid
    readonly property string size: model.size
    width: size === "small" ? root.smallW : root.columnWidth
    height: size === "large" ? root.smallH * 2 + root.gap : root.smallH
    opacity: widgetDrag.active && widgetDrag.index === index ? 0.3 : 1
    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }

    NcWidgetFace {
      id: face
      anchors.fill: parent
      widgetId: tile.widgetId
      size: tile.size
      scale: tap.pressed && !root.editing ? Motion.pressScale : 1
      Behavior on scale { NumberAnimation { duration: tap.pressed ? Motion.instant : Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton
        enabled: !root.editing
        onTapped: {
          if (tile.widgetId === "calendar") root.hostWidget && root.hostWidget.openCalendar ? root.hostWidget.openCalendar() : root.close()
          else if (tile.widgetId === "media") root.run("omarchy-launch-or-focus spotify")
          else root.close()
        }
      }
      TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: function(ev) { var p = face.mapToItem(null, ev.position.x, ev.position.y); root.widgetMenuFor(tile.index, p.x, p.y) }
      }
      // Edit mode: press and drag reorders; the ghost follows the pointer.
      DragHandler {
        id: dragger
        enabled: root.editing
        target: null
        onActiveChanged: {
          if (active) {
            var p = tile.mapToItem(keyCatcher, centroid.pressPosition.x, centroid.pressPosition.y)
            var origin = tile.mapToItem(keyCatcher, 0, 0)
            widgetDrag.grabX = p.x - origin.x
            widgetDrag.grabY = p.y - origin.y
            widgetDrag.index = tile.index
            ghost.px = p.x; ghost.py = p.y
            widgetDrag.active = true
          } else {
            widgetDrag.active = false
            widgetDrag.index = -1
            root.saveWidgets()
          }
        }
        onCentroidChanged: {
          if (!active) return
          var p = tile.mapToItem(keyCatcher, centroid.position.x, centroid.position.y)
          ghost.px = p.x; ghost.py = p.y
          // The tile under the pointer takes this one's place.
          var fp = keyCatcher.mapToItem(widgetFlow, p.x, p.y)
          var over = widgetFlow.childAt(fp.x, fp.y)
          if (over && over !== tile && over.index !== undefined && over.index !== widgetDrag.index) {
            widgetModel.move(widgetDrag.index, over.index, 1)
            widgetDrag.index = over.index
          }
        }
      }
    }
    NcCornerButton {
      visible: root.editing && !(widgetDrag.active && widgetDrag.index === tile.index)
      x: -root.pt(6); y: -root.pt(6)
      size: root.pt(nc.minusButton)
      symbol: "–"
      grey: true
      opacity: visible ? 1 : 0
      Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      onClicked: root.removeWidget(tile.index)
    }
  }

  // The visible face of a widget: card material + content by id.
  component NcWidgetFace: NcCard {
    id: wface
    property string widgetId: ""
    property string size: "small"
    radius: root.pt(nc.radiusWidget)
    readonly property int pad: root.pt(14)
    Loader {
      anchors.fill: parent
      anchors.margins: wface.pad
      sourceComponent: wface.widgetId === "calendar" ? calendarWidget
        : wface.widgetId === "clock" ? clockWidget
        : wface.widgetId === "media" ? mediaWidget
        : wface.widgetId === "battery" ? batteryWidget : null
      property string size: wface.size
    }
  }

  component WidgetCaption: Text {
    font.family: root.uiFont
    font.pixelSize: root.pt(11)
    color: root.inkSecondary
    elide: Text.ElideRight
  }
  component WidgetBig: Text {
    font.family: root.uiFont
    font.pixelSize: root.pt(34)
    font.weight: Font.Light
    color: root.ink
  }

  Component {
    id: calendarWidget
    Column {
      id: cal
      readonly property string size: parent ? parent.size : "small"
      readonly property var upcoming: root.upcomingEvents(size === "large" ? 9 : size === "medium" ? 3 : 0)
      spacing: root.pt(2)
      Text {
        text: Qt.locale("de_DE").toString(new Date(root.now), "dddd").toUpperCase()
        font.family: root.uiFont; font.pixelSize: root.pt(11); font.weight: Font.Bold; color: Apple.systemRed
      }
      WidgetBig { text: Qt.locale("de_DE").toString(new Date(root.now), "d") }
      Item { width: 1; height: root.pt(4) }
      Repeater {
        model: cal.upcoming
        delegate: Row {
          required property var modelData
          spacing: root.pt(8)
          height: root.pt(18)
          Rectangle { width: root.pt(3); height: root.pt(13); radius: root.pt(1.5); color: modelData.color !== "" ? modelData.color : Apple.accent; anchors.verticalCenter: parent.verticalCenter }
          Text {
            text: (modelData.day === 0 ? "" : modelData.day === 1 ? "Mo. " : Qt.locale("de_DE").toString(new Date(root.now + modelData.day * 86400000), "ddd") + " ")
              + (modelData.allDay ? "" : String(modelData.start).slice(11, 16) + "  ") + modelData.summary
            font.family: root.uiFont; font.pixelSize: root.pt(12); color: root.ink
            width: cal.width - root.pt(11); elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
      WidgetCaption {
        visible: cal.size !== "small" && cal.upcoming.length === 0
        text: events.synced ? "Keine Termine in den nächsten Tagen" : "Kalender nicht synchronisiert"
      }
    }
  }

  Component {
    id: clockWidget
    Item {
      Canvas {
        id: faceCanvas
        anchors.centerIn: parent
        width: Math.min(parent.width, parent.height)
        height: width
        readonly property date t: clock.date
        onTChanged: requestPaint()
        onPaint: {
          var ctx = getContext("2d")
          var w = width, c = w / 2
          ctx.reset()
          ctx.clearRect(0, 0, w, w)
          ctx.beginPath(); ctx.arc(c, c, c - 1, 0, Math.PI * 2); ctx.fillStyle = pal.face; ctx.fill()
          ctx.strokeStyle = root.inkSecondary; ctx.lineWidth = Math.max(1, w / 60); ctx.lineCap = "round"
          for (var i = 0; i < 12; i++) {
            var a = i * Math.PI / 6
            ctx.beginPath(); ctx.moveTo(c + Math.cos(a) * c * 0.8, c + Math.sin(a) * c * 0.8); ctx.lineTo(c + Math.cos(a) * c * 0.9, c + Math.sin(a) * c * 0.9); ctx.stroke()
          }
          function hand(angle, len, width, color) {
            var r = (angle - 90) * Math.PI / 180
            ctx.beginPath(); ctx.moveTo(c, c); ctx.lineTo(c + Math.cos(r) * c * len, c + Math.sin(r) * c * len)
            ctx.strokeStyle = color; ctx.lineWidth = width; ctx.stroke()
          }
          var h = (t.getHours() % 12 + t.getMinutes() / 60) * 30
          hand(h, 0.5, Math.max(2, w / 28), root.ink)
          hand(t.getMinutes() * 6 + t.getSeconds() / 10, 0.72, Math.max(2, w / 36), root.ink)
          hand(t.getSeconds() * 6, 0.8, Math.max(1, w / 90), Apple.systemOrange)
          ctx.beginPath(); ctx.arc(c, c, Math.max(2, w / 40), 0, Math.PI * 2); ctx.fillStyle = root.ink; ctx.fill()
        }
      }
    }
  }

  Component {
    id: mediaWidget
    Row {
      id: media
      width: parent ? parent.width : 0
      readonly property var svc: root.mediaService
      readonly property var player: svc && svc.activePlayer ? svc.activePlayer
        : (Mpris.players && Mpris.players.values.length > 0 ? Mpris.players.values[0] : null)
      readonly property bool has: !!(player && (player.trackTitle || player.trackArtist))
      readonly property string artUrl: player && player.trackArtUrl ? String(player.trackArtUrl) : ""
      spacing: root.pt(12)
      Rectangle {
        width: root.pt(56); height: width
        radius: root.pt(10)
        color: pal.capsule
        anchors.verticalCenter: parent.verticalCenter
        Image {
          anchors.fill: parent
          source: media.artUrl
          visible: status === Image.Ready
          fillMode: Image.PreserveAspectCrop
          layer.enabled: visible
        }
        Text { anchors.centerIn: parent; visible: media.artUrl === ""; text: root.sf(0x1002A8); font.family: root.symbolFont; font.pixelSize: root.pt(22); color: root.inkSecondary }
      }
      Column {
        width: media.width - root.pt(56) - root.pt(12) - transportRow.width - root.pt(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.pt(2)
        Text { width: parent.width; text: media.has ? String(media.player.trackTitle || "") : "Nichts in Wiedergabe"; font.family: root.uiFont; font.pixelSize: root.pt(13); font.weight: Font.DemiBold; color: root.ink; elide: Text.ElideRight }
        WidgetCaption { width: parent.width; text: media.has ? String(media.player.trackArtist || "") : "" }
      }
      Row {
        id: transportRow
        spacing: root.pt(2)
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
          model: [[0x10028A, "previous"], [-1, "toggle"], [0x10028C, "next"]]
          delegate: HUi.Pressable {
            required property var modelData
            width: root.pt(28); height: root.pt(28)
            radius: width / 2
            tint: root.ink
            enabled: !!media.player
            Text {
              anchors.centerIn: parent
              text: modelData[0] === -1 ? (media.player && media.player.isPlaying ? root.sf(0x100286) : root.sf(0x100284)) : root.sf(modelData[0])
              font.family: root.symbolFont; font.pixelSize: root.pt(13); color: root.ink
            }
            onClicked: {
              var p = media.player
              if (!p) return
              if (modelData[1] === "toggle") p.togglePlaying()
              else if (modelData[1] === "next") p.next()
              else p.previous()
            }
          }
        }
      }
    }
  }

  Component {
    id: batteryWidget
    Item {
      readonly property var dev: UPower.displayDevice
      readonly property real level: dev && dev.isPresent ? dev.percentage : 0
      readonly property bool charging: dev ? dev.state === UPowerDeviceState.Charging : false
      Column {
        anchors.left: parent.left; anchors.top: parent.top
        spacing: root.pt(2)
        WidgetCaption { text: "Batterie" }
        WidgetBig { text: Math.round(level * 100) + " %" }
        WidgetCaption { text: charging ? "Lädt" : dev && dev.state === UPowerDeviceState.FullyCharged ? "Voll geladen" : "Entlädt" }
      }
      Item {
        anchors.right: parent.right; anchors.bottom: parent.bottom
        width: root.pt(56); height: width
        Canvas {
          anchors.fill: parent
          readonly property real p: level
          onPChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d"), c = width / 2, r = c - root.pt(4)
            ctx.reset(); ctx.clearRect(0, 0, width, height)
            ctx.lineWidth = root.pt(6); ctx.lineCap = "round"
            ctx.beginPath(); ctx.arc(c, c, r, 0, Math.PI * 2); ctx.strokeStyle = pal.capsule; ctx.stroke()
            ctx.beginPath(); ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * p); ctx.strokeStyle = p <= 0.2 ? Apple.systemRed : Apple.systemGreen; ctx.stroke()
          }
        }
        HUi.BatteryGlyph { anchors.centerIn: parent; level: parent.parent.level; charging: parent.parent.charging; ink: root.ink; height: root.pt(12) }
      }
    }
  }
}
