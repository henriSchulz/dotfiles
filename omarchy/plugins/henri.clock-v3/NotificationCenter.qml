import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "file:///home/henri/.local/share/velum/qml/Velum"

// The Notification Center behind the clock: a column of floating cards at the
// right screen edge (spec-mitteilungszentrale-macos.md) — notification stacks
// per app, then widgets, then "Widgets bearbeiten". There is no continuous
// sheet; every card carries its own glass, the compositor blur on the popup
// namespace (ignore_alpha 0.3) only touches the cards.
//
// Velum (v3): cards are VFloatingCard (the variant's popover material), the
// column slides in through VEdgePanel, menus are VMenu; geometry from
// Theme.core.surface.notifications. Light/dark follows Theme (VelumSettings,
// owned by the Control Center v3 island).
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
  // the daemon: henri.notifications-v3 when it runs, else the one the shell knows as omarchy.notifications
  readonly property var notificationService: {
    if (!bar || !bar.shell || typeof bar.shell.firstPartyServiceFor !== "function") return null
    return bar.shell.firstPartyServiceFor("henri.notifications-v3") || bar.shell.firstPartyServiceFor("omarchy.notifications")
      || bar.shell.firstPartyServiceFor("henri.notifications")
  }

  // ---- Look: Velum. The banner (henri.notifications-v3) draws the same card, so a card
  //      in the Center looks like the toast it was.
  readonly property var nc: Theme.core.surface.notifications
  readonly property bool dark: Theme.dark
  readonly property string uiFont: Theme.font
  function pt(v) { return v }
  readonly property color ink: Theme.r.popover.ink
  readonly property color inkSecondary: Theme.r.popover.inkSecondary
  readonly property color cardInk: Theme.r.popover.ink
  readonly property color cardInkSecondary: Theme.r.popover.inkSecondary
  // text straight on the wallpaper (an expanded stack's app name): the shadow keeps it readable
  readonly property color deskInk: Theme.dark ? Theme.r.ink.primary : Theme.r.popover.ink

  // Icon/image reference from the daemon's file → URL (same rules as the banner).
  function iconUrl(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    if (value.indexOf("image://icon/") === 0) return Quickshell.iconPath(value.slice("image://icon/".length), true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  readonly property int columnWidth: pt(nc.width)
  readonly property int inset: pt(nc.edgeInset)
  readonly property int gap: pt(nc.gap)
  readonly property int smallW: Math.floor((columnWidth - gap) / 2)
  readonly property int smallH: smallW
  // The corner buttons (close / "Clear All", edit-mode minus) overhang a
  // card's top-left corner; the scroller clips, so the column keeps this
  // much room on its left and top for them.
  // ... and room for the cards' whole shadow (blur + offset), or the scroller's edge cuts it into a
  // visible line beside and under the cards (Henri saw it)
  readonly property int shadowRoom: {
    var l = Theme.r.popover.shadow || [], m = 0
    for (var i = 0; i < l.length; i++) if (!l[i].inset) m = Math.max(m, l[i].blur + Math.abs(l[i].offsetY) + l[i].spread)
    return Math.ceil(m)
  }
  readonly property int overhang: Math.max(shadowRoom, Math.ceil(nc.closeButton / 2 - Math.min(nc.closeCenterX, nc.closeCenterY)) + 1)

  function scrollBy(dy) {
    if (!scroller.interactive) return
    scroller.contentY = Math.max(0, Math.min(scroller.contentHeight - scroller.height, scroller.contentY - dy))
  }

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
  // Tablet mode: a finger pulls the panel down from the top edge (henri.bar-v3 → VGestures)
  Connections {
    target: VGestures
    function onPull(surface, screenName, phase, travel, velocity) {
      if (surface !== "notifications" || !panel.screen || panel.screen.name !== screenName) return
      if (phase === "move") {
        if (root.opened) return
        if (!panel.pulling) root.refresh()
        panel.pull = Math.max(0, travel)
        return
      }
      if (!panel.pulling) return
      if (phase === "end" && VGestures.commits(travel, panel.dropDistance, velocity)) root.open()
      panel.pull = -1
    }
  }
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
    photosSettle.restart()
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
        g = { key: key, app: String(e.app || "Notification"), items: [], sig: "" }
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

  function stackCount() { return stackModel.count }
  function stackInfo(i) { var g = stackModel.get(i); return { key: g.key, count: g.count, expanded: g.expanded } }
  function setExpanded(key, on) {
    var next = {}
    for (var k in expandedKeys) next[k] = expandedKeys[k]
    if (on) next[key] = true; else delete next[key]
    expandedKeys = next
    for (var i = 0; i < stackModel.count; i++) if (stackModel.get(i).key === key) stackModel.setProperty(i, "expanded", on)
  }

  // Timestamp like macOS: "now", "5m ago", "2h ago", "Yesterday", weekday, date.
  function relativeTime(t) {
    var diff = now - t
    var min = Math.floor(diff / 60000)
    if (min < 1) return "now"
    if (min < 60) return min + "m ago"
    var d = new Date(t), today = new Date(now)
    var loc = Qt.locale("en_US")
    if (d.toDateString() === today.toDateString()) return Math.floor(min / 60) + "h ago"
    var yesterday = new Date(now - 86400000)
    if (d.toDateString() === yesterday.toDateString()) return "Yesterday"
    if (diff < 6 * 86400000) return loc.toString(d, "dddd")
    return loc.toString(d, "MMM d")
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
  // Omarchy's own toasts (crash → "diagnose with AI", installers, …) carry their
  // click as an argv vector; run it like the toast does, else focus the sender.
  function entryArgv(it) {
    try {
      var argv = JSON.parse(String(it.execArgv || ""))
      if (!Array.isArray(argv) || argv.length === 0) return null
      for (var i = 0; i < argv.length; i++) if (typeof argv[i] !== "string") return null
      return argv[0] && argv[0].charAt(0) !== "-" ? argv : null
    } catch (e) {
      return null
    }
  }
  function openEntry(it) {
    var argv = entryArgv(it)
    if (argv) Util.execArgv(argv)
    else if (it.app) root.run(Util.shellQuote(Quickshell.env("OMARCHY_PATH") + "/bin/omarchy-hyprland-focus-app") + " " + Util.shellQuote(String(it.app)))
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

  // Only these three (Henri, 2026-09-27): Calendar, Batteries, Photos.
  readonly property var widgetCatalogue: [
    { id: "calendar", title: "Calendar", sizes: ["small", "medium", "large"] },
    { id: "battery", title: "Batteries", sizes: ["small", "medium"] },
    { id: "photos", title: "Photos", sizes: ["large"] }
  ]
  readonly property var defaultWidgets: [
    { id: "calendar", size: "small" }, { id: "battery", size: "small" }, { id: "photos", size: "large" }
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
  Component.onCompleted: { loadWidgets(); photosReader.reload() }

  // ---- Photos widget: one large tile with a random photo from the whole
  // iCloud Photos library — a new one every time the Center opens and every
  // photosCycle ms while it stays open.
  // Read-only query against the app's SQLite; the picture is the app's own
  // full-res copy when cached, else its thumbnail. Loaded once the Center
  // has settled after opening, never during the slide.
  readonly property string photosDb: Quickshell.env("HOME") + "/.local/share/icloud-photos/catalog.sqlite"
  // The app: its own install under ~/.local/share where there is one (the XPS), else the
  // packaged one on PATH (the M1: /usr/bin/icloud-photos). The old fixed path did not exist
  // here, so a click on the photo did nothing.
  readonly property string photosApp: 'app="$HOME/.local/share/icloud-photos/bin/icloud-photos"; [ -x "$app" ] || app=icloud-photos; '

  property var photo: null
  Process {
    id: photosReader
    running: false
    command: ["sqlite3", "-readonly", "-json", root.photosDb,
      "select id, case when is_orig_cached = 1 and orig_path is not null and orig_path != '' then orig_path else thumb_path end as src, " +
      "coalesce(asset_date, added_date) as taken from photos " +
      "where item_type = 'image' and thumb_path is not null and thumb_path != '' " +
      "order by random() limit 1"]
    stdout: StdioCollector { id: photosOut; waitForEnd: true }
    function reload() { photosReader.running = false; photosReader.running = true }
    onExited: function(code) {
      if (code !== 0) return
      var list = []
      try { list = JSON.parse(String(photosOut.text || "").trim() || "[]") } catch (e) { list = [] }
      var row = list.length > 0 ? list[0] : null
      root.photo = row && row.src ? { id: String(row.id || ""), src: String(row.src), taken: String(row.taken || "") } : null
    }
  }
  Timer { id: photosSettle; interval: Theme.delay("settle") + Theme.dur("slower"); onTriggered: photosReader.reload() }
  readonly property int photosCycle: 20000
  Timer { interval: root.photosCycle; repeat: true; running: root.opened; onTriggered: photosReader.reload() }
  // The photo the tile shows opens in the app (`icloud-photos --open <id>`):
  // a running instance takes the id over D-Bus and presents its window,
  // which Hyprland's focus_on_activate brings to the front. No photo → the
  // app just opens.
  function openPhotos() {
    var id = root.photo && root.photo.id ? String(root.photo.id) : ""
    if (id !== "") root.run(root.photosApp + 'setsid -f "$app" --open ' + Util.shellQuote(id))
    else root.run(root.photosApp + 'omarchy-launch-or-focus de.henri.IcloudPhotos "$app"')
    root.close()
  }

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

  // ---- The window ----------------------------------------------------------------------------

  VEdgePanel {
    id: panel
    anchorItem: root.anchorItem
    bar: root.bar
    open: root.opened
    namespace: "velum-surface"   // Hyprland: blur with ignore_alpha 0.6 (only the material, never the shadow), no layer animation
    panelWidth: root.columnWidth
    inset: root.inset
    overhang: root.overhang
    focusTarget: keyCatcher
    onDismissed: root.close()

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
        contentHeight: column.implicitHeight + 2 * root.overhang
        clip: true
        boundsBehavior: Flickable.DragAndOvershootBounds
        interactive: contentHeight > height

        // Two-finger swipe to the right closes the Center (spec 2.2).
        property real swipeX: 0
        WheelHandler {
          acceptedDevices: PointerDevice.TouchPad
          onWheel: function(ev) {
            var dx = ev.pixelDelta.x !== 0 ? ev.pixelDelta.x : ev.angleDelta.x / 4
            var dy = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : ev.angleDelta.y / 4
            // the handler takes every touchpad event, so vertical ones scroll the Center here
            if (Math.abs(dx) <= Math.abs(dy)) { root.scrollBy(dy); return }
            scroller.swipeX = Math.max(0, scroller.swipeX + dx)
            swipeSettle.restart()
          }
        }
        Timer {
          id: swipeSettle
          interval: Theme.delay("settle")
          onTriggered: {
            var closeIt = scroller.swipeX > root.columnWidth * 0.3
            scroller.swipeX = 0
            if (closeIt) root.close()
          }
        }
        transform: Translate { x: dragX.value }
        Spring { id: dragX; preset: Theme.spring("smooth"); reduced: Theme.reduceMotion; target: scroller.swipeX }

        Column {
          id: column
          x: root.overhang
          y: root.overhang
          width: root.columnWidth
          spacing: root.gap
          move: Transition {
            NumberAnimation { properties: "x,y"; duration: Theme.move(Theme.dur("base")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") }
          }

          // "Do Not Disturb" hint (spec §9, focus mode)
          NcCard {
            visible: root.notificationService ? root.notificationService.doNotDisturb : false
            width: column.width
            height: Theme.m.control.height + Theme.layout.list.gap
            radius: Theme.m.radius.row + Theme.layout.module.tileInset
            Row {
              anchors.centerIn: parent
              spacing: Theme.layout.list.gap
              VIcon { name: "focus"; weight: "fill"; size: Theme.layout.icon.small; color: root.inkSecondary; anchors.verticalCenter: parent.verticalCenter }
              VText { text: "Do Not Disturb is on"; font.pixelSize: Theme.m.type.small; color: root.inkSecondary; anchors.verticalCenter: parent.verticalCenter }
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
              NumberAnimation { properties: "x,y"; duration: Theme.move(Theme.dur("base")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") }
            }
            // no add transition (an interrupted one leaves items half transparent): widgets fade in themselves
            Repeater {
              model: widgetModel
              delegate: NcWidget {}
            }
          }

          // ---- Edit mode: what can still be added
          NcCard {
            visible: root.editing && root.hiddenWidgets().length > 0
            width: column.width
            height: galleryColumn.implicitHeight + nc.padding * 2
            Column {
              id: galleryColumn
              x: nc.padding; y: nc.padding
              width: parent.width - nc.padding * 2
              spacing: Theme.layout.list.gap
              VText { text: "Add Widgets"; font.pixelSize: Theme.m.type.small; font.weight: Font.DemiBold; color: root.inkSecondary }
              Repeater {
                model: root.editing ? root.hiddenWidgets() : []
                delegate: Row {
                  id: addRow
                  required property var modelData
                  spacing: Theme.layout.list.gap
                  height: Theme.layout.capsule.height
                  VText { text: addRow.modelData.title; color: root.ink; width: root.smallW / 2 + Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter }
                  Repeater {
                    model: addRow.modelData.sizes
                    delegate: VCapsule {
                      required property string modelData
                      readonly property string sizeId: modelData
                      anchors.verticalCenter: parent.verticalCenter
                      label: sizeId === "small" ? "Small" : sizeId === "medium" ? "Medium" : "Large"
                      onClicked: root.addWidget(addRow.modelData.id, sizeId)
                    }
                  }
                }
              }
            }
          }

          // ---- "Edit Widgets"
          Item {
            width: column.width
            height: nc.editButtonHeight + Theme.layout.module.tileInset
            NcGlassCapsule {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              height: nc.editButtonHeight
              label: root.editing ? "Done" : "Edit Widgets"
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
        scale: Theme.scale("lift")
        opacity: 1 - Theme.core.alpha.hover
        sourceComponent: widgetDrag.active ? ghostComponent : null
      }
      Component {
        id: ghostComponent
        NcWidgetFace {
          id: face
          readonly property var row: widgetDrag.index >= 0 && widgetDrag.index < widgetModel.count ? widgetModel.get(widgetDrag.index) : null
          width: row && row.size === "small" ? root.smallW : root.columnWidth
          height: row && row.size === "large" ? root.smallH * 2 + root.gap : root.smallH
          widgetId: row ? row.wid : ""
          size: row ? row.size : "small"
        }
      }

      // ---- Context menu (right click / Options): Velum's menu, opens with no transition.
      Item {
        id: contextMenu
        z: 60
        property bool open: false
        property var entries: []
        property var handler: null
        anchors.fill: parent
        visible: menu.visible
        function show(sceneX, sceneY, list, fn) {
          var p = keyCatcher.mapFromItem(null, sceneX, sceneY)
          entries = list.map(function(e) { return e.separator ? e : { text: e.text, disabled: e.enabled === false, danger: !!e.danger, id: e.id } })
          handler = fn
          menu.x = Math.min(p.x, keyCatcher.width - menu.implicitWidth - Theme.layout.module.tileInset)
          menu.y = Math.min(p.y, keyCatcher.height - menu.implicitHeight - Theme.layout.module.tileInset)
          open = true
        }
        function hide() { open = false }
        MouseArea { anchors.fill: parent; enabled: contextMenu.open; acceptedButtons: Qt.AllButtons; onPressed: contextMenu.hide() }
        VMenu {
          id: menu
          open: contextMenu.open
          model: contextMenu.entries
          onTriggered: function(index) {
            var e = contextMenu.entries[index]
            contextMenu.hide()
            if (contextMenu.handler) contextMenu.handler(e)
          }
        }
      }
    }
  }

  // ---- Components ----------------------------------------------------------------------------

  // A floating card: widgets, hints, notifications (Velum's popover material).
  component NcCard: VFloatingCard {}
  component NcNoteCard: VFloatingCard {}

  // A glass capsule on the desktop: "Show Less", the stack ✕, "Edit Widgets" — the card
  // material, so it stays readable on any wallpaper.
  component NcGlassCapsule: Item {
    id: cap
    property string label: ""
    property string icon: ""
    signal clicked()
    implicitHeight: Theme.layout.capsule.height
    implicitWidth: label === "" ? implicitHeight : capText.implicitWidth + 2 * Theme.layout.capsule.padX
    width: implicitWidth; height: implicitHeight
    VFloatingCard { anchors.fill: parent; radius: height / 2; tint: capMouse.containsMouse ? Theme.r.popover.bgOpaque : (Theme.reduceTransparency ? Theme.r.popover.bgOpaque : Theme.r.popover.bg) }
    VText { id: capText; visible: cap.label !== ""; anchors.centerIn: parent; text: cap.label; font.pixelSize: Theme.m.type.small; font.weight: Font.Medium; color: Theme.r.popover.ink }
    VIcon { visible: cap.label === ""; anchors.centerIn: parent; name: cap.icon; weight: "bold"; size: Theme.layout.icon.small * 0.75; color: Theme.r.popover.ink }
    scale: capMouse.pressed ? Theme.scale("press") : 1
    Behavior on scale { NumberAnimation { duration: Theme.dur("instant") } }
    MouseArea { id: capMouse; anchors.fill: parent; hoverEnabled: true; onClicked: cap.clicked() }
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
    implicitHeight: stackColumn.implicitHeight + (group && !expanded ? nc.stripOffset * 2 : 0)
    height: implicitHeight
    opacity: leaving ? 0 : 1
    transform: Translate { x: stack.leaving ? Theme.move(stack.width + root.inset) : 0
      Behavior on x { NumberAnimation { duration: Theme.exit(Theme.dur("slow")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("exit") } } }
    Behavior on opacity { NumberAnimation { duration: Theme.exit(Theme.dur("slow")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("exit") } }
    Behavior on height { NumberAnimation { duration: Theme.move(Theme.dur("base")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") } }

    function allItems() {
      var out = []
      for (var i = 0; i < items.count; i++) out.push(items.get(i))
      return out
    }
    function dismissAll() {
      stack.leaving = true
      dismissDelay.restart()
    }
    Timer { id: dismissDelay; interval: Theme.exit(Theme.dur("slow")); onTriggered: root.dismissEntries(stack.allItems()) }

    // Strips behind the top card (collapsed group): only the slice below the
    // card is drawn — the glass is translucent, a whole card behind it would
    // tint the front one's lower half.
    Item {
      y: topCard.h
      width: stack.width
      height: nc.stripOffset * 2
      clip: true
      z: -1
      Repeater {
        model: stack.group && !stack.expanded ? Math.min(2, stack.count - 1) : 0
        delegate: NcNoteCard {
          required property int index
          readonly property int level: index + 1
          readonly property real shrink: level === 1 ? nc.stripScale2 : nc.stripScale3
          shadowed: false
          width: Math.round(stack.width * shrink)
          x: Math.round((stack.width - width) / 2)
          height: nc.minHeight
          y: -height + nc.stripOffset * level
          opacity: level === 1 ? nc.stripAlpha2 : nc.stripAlpha3
          z: -level
          Behavior on opacity { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
        }
      }
    }

    Column {
      id: stackColumn
      width: stack.width
      spacing: root.gap
      move: Transition {
        NumberAnimation { properties: "x,y"; duration: Theme.move(Theme.dur("base")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") }
      }

      // Header while expanded
      Item {
        width: stackColumn.width
        height: visible ? Theme.layout.capsule.height : 0
        visible: stack.expanded
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.dur("base"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
        // The app name sits straight on the desktop (no card, like macOS), so it
        // carries a soft outline to stay readable on a bright wallpaper; the
        // capsules are glass for the same reason.
        VText {
          anchors.left: parent.left
          anchors.leftMargin: Theme.layout.module.tileInset
          anchors.verticalCenter: parent.verticalCenter
          text: stack.model.app
          font.pixelSize: Theme.m.type.title
          font.weight: Font.DemiBold
          color: root.deskInk
          style: Text.Outline
          styleColor: Theme.r.popover.bg
        }
        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Theme.layout.list.gap
          NcGlassCapsule { label: "Show Less"; onClicked: root.setExpanded(stack.key, false) }
          NcGlassCapsule { icon: "close"; onClicked: stack.dismissAll() }
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
    QtObject { id: topCard; readonly property real h: cardRepeater.count > 0 && cardRepeater.itemAt(0) ? cardRepeater.itemAt(0).height : nc.minHeight }
  }

  // A notification card: the banner's card (henri.notifications-v3) plus what only the
  // Center has — timestamp, stack count, swipe actions and the corner button that grows
  // into "Clear All" on a stack.
  component NcNotificationCard: Item {
    id: card
    property var entry: null
    property var stackItem: null
    property bool collapsedGroup: false
    property bool leaving: false
    property real swipeX: 0
    readonly property bool revealed: swipeX <= -nc.swipeActions + 1
    readonly property int padding: nc.padding
    readonly property int iconSize: nc.icon
    readonly property string iconSource: entry ? root.iconUrl(entry.appIcon) : ""
    readonly property string imageSource: entry && entry.image !== "" ? root.iconUrl(entry.image) : ""
    implicitHeight: Math.max(nc.minHeight, textColumn.implicitHeight + padding * 2)
    height: implicitHeight
    opacity: leaving ? 0 : 1
    transform: Translate { x: card.leaving ? Theme.move(card.width + root.inset) : 0
      Behavior on x { NumberAnimation { duration: Theme.exit(Theme.dur("slow")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("exit") } } }
    Behavior on opacity { NumberAnimation { duration: Theme.exit(Theme.dur("slow")); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("exit") } }
    // Appears: fade + slight settle from above (expanding a stack, a new notification).
    onVisibleChanged: if (visible) appear.from(0)
    Spring { id: appear; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: 1 }
    Component.onCompleted: appear.from(0)

    function dismiss() {
      if (card.collapsedGroup) { card.stackItem.dismissAll(); return }
      card.leaving = true
      dismissDelay.restart()
    }
    Timer { id: dismissDelay; interval: Theme.exit(Theme.dur("slow")); onTriggered: root.dismissEntries([card.entry]) }
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
      transform: Translate { y: (1 - appear.value) * -Theme.move(nc.settleY) }

      // Swipe actions behind the card
      Row {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        visible: card.swipeX < 0
        clip: true
        Rectangle {
          width: nc.swipeActions / 2; height: parent.height
          color: Theme.r.ink.tertiary
          topLeftRadius: Theme.m.radius.panel; bottomLeftRadius: Theme.m.radius.panel
          VText { anchors.centerIn: parent; text: "Options"; color: Theme.r.ink.onAccent; font.pixelSize: Theme.m.type.small; font.weight: Font.DemiBold }
          MouseArea { anchors.fill: parent; onClicked: function(m) { var p = mapToItem(null, m.x, m.y); card.showMenu(p.x, p.y) } }
        }
        Rectangle {
          width: nc.swipeActions / 2; height: parent.height
          color: Theme.r.danger
          topRightRadius: Theme.m.radius.panel; bottomRightRadius: Theme.m.radius.panel
          VText { anchors.centerIn: parent; text: "Clear"; color: Theme.r.ink.onAccent; font.pixelSize: Theme.m.type.small; font.weight: Font.DemiBold }
          MouseArea { anchors.fill: parent; onClicked: card.dismiss() }
        }
      }

      NcNoteCard {
        id: face
        anchors.fill: parent
        transform: Translate { x: slideX.value }
        Spring { id: slideX; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: card.swipeX }
        scale: press.pressed ? Theme.scale("press") : 1
        Behavior on scale { NumberAnimation { duration: press.pressed ? Theme.dur("instant") : Theme.dur("base"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }

        HoverHandler { id: hover }
        TapHandler {
          id: press
          acceptedButtons: Qt.LeftButton
          onTapped: if (!cardHold.fired) card.activate()
        }
        TapHandler {
          acceptedButtons: Qt.RightButton
          onTapped: function(ev) { var p = face.mapToItem(null, ev.position.x, ev.position.y); card.showMenu(p.x, p.y) }
        }
        // A finger held on the card is its right click (the menu); the release then opens nothing.
        TapHandler {
          id: cardHold
          property bool fired: false
          acceptedDevices: PointerDevice.TouchScreen
          longPressThreshold: Theme.delay("longPress") / 1000
          onPressedChanged: if (pressed) fired = false
          onLongPressed: { fired = true; var p = face.mapToItem(null, point.position.x, point.position.y); card.showMenu(p.x, p.y) }
        }
        WheelHandler {
          acceptedDevices: PointerDevice.TouchPad
          onWheel: function(ev) {
            var dx = ev.pixelDelta.x !== 0 ? ev.pixelDelta.x : ev.angleDelta.x / 4
            var dy = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : ev.angleDelta.y / 4
            // the handler takes every touchpad event, so vertical ones scroll the Center here
            if (Math.abs(dx) <= Math.abs(dy)) { root.scrollBy(dy); return }
            if (dx > 0 && card.swipeX >= 0) return   // swiping right on a closed card: the column takes it
            ev.accepted = true
            card.swipeX = Math.max(-card.width, Math.min(0, card.swipeX + dx))
            cardSwipeSettle.restart()
          }
        }
        Timer {
          id: cardSwipeSettle
          interval: Theme.delay("settle")
          onTriggered: {
            if (card.swipeX < -card.width * nc.swipeDelete) { card.swipeX = -card.width; card.dismiss(); return }
            card.swipeX = card.swipeX < -nc.swipeActions / 2 ? -nc.swipeActions : 0
          }
        }

        // App symbol, vertically centred — like the banner: a notification
        // picture takes the slot and the app icon becomes a small badge.
        Item {
          id: iconBox
          x: card.padding
          anchors.verticalCenter: parent.verticalCenter
          width: card.iconSize; height: card.iconSize
          Rectangle {
            anchors.fill: parent
            radius: width * nc.iconRadius
            gradient: Gradient { GradientStop { position: 0; color: Theme.r.accent.top } GradientStop { position: 1; color: Theme.r.accent.base } }
            visible: !picture.visible
            VText {
              visible: card.entry && card.entry.glyph !== ""
              anchors.centerIn: parent
              text: card.entry ? card.entry.glyph : ""
              font.family: Style.font.family
              font.pixelSize: Theme.layout.icon.large
              color: Theme.r.ink.onAccent
            }
            VIcon {
              visible: !card.entry || card.entry.glyph === ""
              anchors.centerIn: parent
              name: "notification"
              weight: "fill"
              size: Theme.layout.icon.large
              color: Theme.r.ink.onAccent
            }
          }
          Image {
            id: picture
            anchors.fill: parent
            source: card.imageSource !== "" ? card.imageSource : card.iconSource
            visible: status === Image.Ready
            fillMode: card.imageSource !== "" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            asynchronous: true
            smooth: true
          }
          Image {
            id: badge
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.rightMargin: -Theme.layout.separator * 2
            anchors.bottomMargin: -Theme.layout.separator * 2
            width: nc.badge; height: width
            source: card.imageSource !== "" ? card.iconSource : ""
            visible: card.imageSource !== "" && picture.visible && status === Image.Ready
            fillMode: Image.PreserveAspectFit
            sourceSize.width: width * 2
            sourceSize.height: height * 2
            asynchronous: true
            smooth: true
          }
        }

        Column {
          id: textColumn
          x: card.padding + card.iconSize + nc.iconGap
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - x - card.padding
          spacing: 0
          // Title line, timestamp on the right (the Center's addition to the banner).
          Item {
            width: parent.width
            height: nc.lineHeight
            VText {
              anchors.left: parent.left
              anchors.right: timeText.left
              anchors.rightMargin: Theme.layout.list.gap
              anchors.verticalCenter: parent.verticalCenter
              text: card.entry ? (card.entry.summary !== "" ? card.entry.summary : card.entry.app) : ""
              font.weight: Font.DemiBold
              color: root.cardInk
              elide: Text.ElideRight
              textFormat: Text.PlainText
            }
            VText {
              id: timeText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: card.entry ? root.relativeTime(card.entry.timestamp) : ""
              font.pixelSize: Theme.m.type.small
              color: root.cardInkSecondary
            }
          }
          VText {
            width: parent.width
            text: card.entry ? card.entry.body : ""
            lineHeight: nc.lineHeight
            lineHeightMode: Text.FixedHeight
            color: root.cardInk
            wrapMode: Text.WordWrap
            maximumLineCount: nc.bodyLines
            elide: Text.ElideRight
            textFormat: Text.PlainText
            visible: text !== ""
          }
          VText {
            visible: card.collapsedGroup
            text: (card.stackItem ? card.stackItem.count - 1 : 0) + " more " + ((card.stackItem && card.stackItem.count - 1 === 1) ? "notification" : "notifications")
            font.pixelSize: Theme.m.type.small
            lineHeight: nc.lineHeight
            lineHeightMode: Text.FixedHeight
            color: root.cardInkSecondary
          }
        }
      }

      // Close circle overlapping the top-left corner; on a stack it grows into "Clear All".
      VCornerButton {
        id: closer
        x: nc.closeCenterX - nc.closeButton / 2
        y: nc.closeCenterY - height / 2
        label: card.collapsedGroup ? "Clear All" : ""
        shown: hover.hovered || closer.hovered
        onClicked: card.dismiss()
      }
    }
  }

  function contextMenuFor(entry, sx, sy) {
    var list = [
      { text: "Mute for 1 Hour", id: "hour" },
      { text: "Mute for Today", id: "today" },
      { separator: true },
      { text: "Notification Settings…", id: "settings" }
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
    var sizes = [["small", "Small"], ["medium", "Medium"], ["large", "Large"]]
    for (var i = 0; i < sizes.length; i++)
      list.push({ text: sizes[i][1], id: "size:" + sizes[i][0], enabled: def.sizes.indexOf(sizes[i][0]) >= 0, checked: row.size === sizes[i][0] })
    list.push({ separator: true })
    list.push({ text: "Remove Widget", id: "remove", danger: true })
    list.push({ separator: true })
    list.push({ text: "Edit Widgets…", id: "edit" })
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
    opacity: (widgetDrag.active && widgetDrag.index === index ? Theme.core.alpha.disabled : 1) * tileIn.value
    Behavior on opacity { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
    // a widget added in edit mode grows in on the snappy spring (only after the Center is up)
    Spring { id: tileIn; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: 1 }
    Component.onCompleted: if (root.opened) tileIn.from(0)
    scale: Theme.scale("popoverFrom") + (1 - Theme.scale("popoverFrom")) * tileIn.value

    NcWidgetFace {
      id: face
      anchors.fill: parent
      widgetId: tile.widgetId
      size: tile.size
      scale: tap.pressed && !root.editing ? Theme.scale("press") : 1
      Behavior on scale { NumberAnimation { duration: tap.pressed ? Theme.dur("instant") : Theme.dur("base"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
      TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton
        enabled: !root.editing
        onTapped: {
          if (tileHold.fired) return
          if (tile.widgetId === "calendar") root.hostWidget && root.hostWidget.openCalendar ? root.hostWidget.openCalendar() : root.close()
          else if (tile.widgetId === "photos") root.openPhotos()
          else root.close()
        }
      }
      TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: function(ev) { var p = face.mapToItem(null, ev.position.x, ev.position.y); root.widgetMenuFor(tile.index, p.x, p.y) }
      }
      // A finger held on the widget is its right click (the widget menu); the release then opens nothing.
      TapHandler {
        id: tileHold
        property bool fired: false
        acceptedDevices: PointerDevice.TouchScreen
        longPressThreshold: Theme.delay("longPress") / 1000
        onPressedChanged: if (pressed) fired = false
        onLongPressed: { fired = true; var p = face.mapToItem(null, point.position.x, point.position.y); root.widgetMenuFor(tile.index, p.x, p.y) }
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
    VCornerButton {
      shown: root.editing && !(widgetDrag.active && widgetDrag.index === tile.index)
      x: -nc.minusButton / 4; y: -nc.minusButton / 4
      size: nc.minusButton
      icon: "minus"
      onClicked: root.removeWidget(tile.index)
    }
  }

  // The visible face of a widget: card material + content by id.
  component NcWidgetFace: NcCard {
    id: wface
    property string widgetId: ""
    property string size: "small"
    readonly property int pad: nc.widgetPad
    Loader {
      anchors.fill: parent
      // Photos run full-bleed to the card edge; everything else keeps the inset.
      anchors.margins: wface.widgetId === "photos" ? 0 : wface.pad
      sourceComponent: wface.widgetId === "calendar" ? calendarWidget
        : wface.widgetId === "battery" ? batteryWidget
        : wface.widgetId === "photos" ? photosWidget : null
      property string size: wface.size
    }
  }

  component WidgetCaption: VText {
    font.pixelSize: Theme.m.type.small
    color: root.inkSecondary
    elide: Text.ElideRight
  }
  component WidgetBig: VText {
    font.pixelSize: Theme.m.type.title * 2 + Theme.layout.list.gap
    font.weight: Font.Light
    color: root.ink
  }
  // the system colours of the palette (red day name, green battery ring), with a fallback
  function sysColor(name, fallback) {
    var c = Theme.core.color
    var p = c && c.apple ? c.apple[Theme.dark ? "dark" : "light"] : null
    return p && p[name] ? p[name] : fallback
  }

  Component {
    id: calendarWidget
    Column {
      id: cal
      readonly property string size: parent ? parent.size : "small"
      readonly property var upcoming: root.upcomingEvents(size === "large" ? 9 : size === "medium" ? 3 : 0)
      spacing: Theme.layout.separator * 2
      VText {
        text: Qt.locale("en_US").toString(new Date(root.now), "dddd").toUpperCase()
        font.pixelSize: Theme.m.type.small; font.weight: Font.Bold; color: root.sysColor("red", Theme.r.danger)
      }
      WidgetBig { text: Qt.locale("en_US").toString(new Date(root.now), "d") }
      Item { width: 1; height: Theme.layout.module.tileInset }
      Repeater {
        model: cal.upcoming
        delegate: Row {
          required property var modelData
          spacing: Theme.layout.list.gap
          height: Theme.layout.icon.large - Theme.layout.separator * 2
          Rectangle { width: Theme.layout.separator * 3; height: Theme.layout.icon.small - Theme.layout.separator; radius: width / 2; color: modelData.color !== "" ? modelData.color : Theme.r.accent.base; anchors.verticalCenter: parent.verticalCenter }
          VText {
            text: (modelData.day === 0 ? "" : modelData.day === 1 ? "Tomorrow " : Qt.locale("en_US").toString(new Date(root.now + modelData.day * 86400000), "ddd") + " ")
              + (modelData.allDay ? "" : String(modelData.start).slice(11, 16) + "  ") + modelData.summary
            font.pixelSize: Theme.m.type.small; color: root.ink
            width: cal.width - Theme.layout.list.gap - Theme.layout.separator * 3; elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
      WidgetCaption {
        visible: cal.size !== "small" && cal.upcoming.length === 0
        text: events.synced ? "No upcoming events" : "Calendar not synced"
      }
    }
  }

  Component {
    id: photosWidget
    PhotoTile {
      photo: root.photo
      radius: Theme.m.radius.panel
      placeholderColor: Theme.r.popover.tile
      placeholderInk: root.inkSecondary
      placeholderText: "No Photos"
      captionFont: Theme.font
      captionFontSize: Theme.m.type.body
      caption: {
        if (!root.photo || !root.photo.taken) return ""
        var d = new Date(root.photo.taken)
        return isNaN(d.getTime()) ? "" : Qt.locale("en_US").toString(d, "MMMM d, yyyy")
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
        spacing: Theme.layout.separator * 2
        WidgetCaption { text: "Battery" }
        WidgetBig { text: Math.round(level * 100) + " %" }
        WidgetCaption { text: charging ? "Charging" : dev && dev.state === UPowerDeviceState.FullyCharged ? "Fully Charged" : "On Battery" }
      }
      Item {
        anchors.right: parent.right; anchors.bottom: parent.bottom
        width: Theme.layout.module.quick + Theme.layout.module.pad + Theme.layout.module.tileInset; height: width
        Canvas {
          anchors.fill: parent
          readonly property real p: level
          onPChanged: requestPaint()
          readonly property bool darkNow: Theme.dark
          onDarkNowChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d"), c = width / 2, r = c - Theme.layout.module.tileInset
            ctx.reset(); ctx.clearRect(0, 0, width, height)
            ctx.lineWidth = Theme.layout.control.gap; ctx.lineCap = "round"
            ctx.beginPath(); ctx.arc(c, c, r, 0, Math.PI * 2); ctx.strokeStyle = String(Theme.r.popover.switchOff); ctx.stroke()
            ctx.beginPath(); ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * p); ctx.strokeStyle = String(p <= 0.2 ? root.sysColor("red", Theme.r.danger) : root.sysColor("green", Theme.r.accent.base)); ctx.stroke()
          }
        }
        VBattery { anchors.centerIn: parent; level: parent.parent.level; charging: parent.parent.charging; ink: root.ink; height: Theme.layout.icon.small * 0.8 }
      }
    }
  }
}
