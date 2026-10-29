import Quickshell
import QtQuick
import QtQuick.Effects
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui
import "TrayModel.js" as TrayModel
import "file:///home/henri/.local/share/velum/qml/Velum"

BarWidget {
  id: root
  moduleName: "omarchy.tray"

  property bool expanded: false
  property bool managePopupOpen: false
  property bool trayMenuOpen: false
  property var activeTrayItem: null
  property var activeTrayAnchor: null
  readonly property color foreground: bar ? bar.foreground : Theme.r.popover.ink
  readonly property var tray: Theme.core.surface.menubar.tray
  readonly property var pinnedIds: settings.pinned instanceof Array ? settings.pinned : []
  readonly property var hiddenIds: settings.hidden instanceof Array ? settings.hidden : []
  readonly property var pinnedItems: bucket("pinned")
  readonly property var drawerItems: bucket("drawer")
  readonly property var allItems: bucket("all")
  readonly property int drawerCount: drawerItems.length
  readonly property int trayItemExtent: tray.slot
  readonly property int trayItemGap: 0
  readonly property int trayJoinGap: 0
  readonly property int drawerExtent: drawerCount > 0 ? drawerCount * trayItemExtent + (drawerCount - 1) * trayItemGap : 0
  property real revealProgress: expanded ? 1 : 0
  readonly property real revealExtent: drawerExtent * revealProgress

  // Submenu drill-down state. QsMenuEntry.display() renders a *platform* menu,
  // which Quickshell refuses unless the shell root sets `//@ pragma
  // UseQApplication` - omarchy's shell.qml does not, so every submenu click was
  // a silent no-op ("Cannot display PlatformMenuEntry as quickshell was not
  // started in QApplication mode" in the shell log) and apps whose whole UI is
  // submenus, e.g. radiotray-ng's station list, were unusable. QsMenuEntry
  // inherits QsMenuHandle, so a child entry can feed a nested QsMenuOpener and
  // render inside this popup instead of going through the platform. Each level
  // keeps its own live opener: a child entry is owned by its parent opener's
  // model, so collapsing the stack to a single opener would destroy the very
  // entry being displayed (submenu turns up empty).
  property var submenuStack: []
  readonly property int submenuDepth: submenuStack.length
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  readonly property var currentChildren: submenuDepth > 0
    ? submenuStack[submenuDepth - 1].opener.children
    : trayMenuOpener.children

  // Changing level rebuilds the row delegates synchronously, so the next
  // row lands under a cursor that hasn't moved. Submenu clicks used to be
  // silent no-ops, which trained users to click them twice, and that second
  // click would now fire whatever entry took the spot. Ignore row clicks for
  // a beat after each level change; a deliberate follow-up click is slower.
  property bool menuLevelSettling: false

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  Timer {
    id: menuLevelSettleTimer
    interval: 250
    onTriggered: root.menuLevelSettling = false
  }

  function settleMenuLevel() {
    menuLevelSettling = true
    menuLevelSettleTimer.restart()
  }

  function resetTrayMenu() {
    menuLevelSettling = false
    menuLevelSettleTimer.stop()
    // Flickable keeps its offset across a model swap whenever the new content
    // is still tall enough to hold it, so a menu dismissed while scrolled
    // would otherwise reopen part-way down with its first entries off screen.
    trayMenuFlick.contentY = 0
    // Clear the reactive stack before tearing anything down, so no binding can
    // read a partially-destroyed opener while this runs. Then destroy deepest
    // first: an inner opener's menu entry is owned by its parent's children
    // model, so destroying a parent first would invalidate an entry a still-
    // live child opener references.
    var openers = submenuStack
    submenuStack = []
    for (var i = openers.length - 1; i >= 0; i--) openers[i].opener.destroy()
  }

  function enterSubmenu(entry, title) {
    var opener = submenuOpenerComponent.createObject(root, { menu: entry })
    if (!opener) return
    var stack = submenuStack.slice()
    stack.push({ opener: opener, title: title })
    submenuStack = stack
    settleMenuLevel()
  }

  function leaveSubmenu() {
    if (submenuStack.length === 0) return
    var stack = submenuStack.slice()
    var top = stack.pop()
    submenuStack = stack
    top.opener.destroy()
    settleMenuLevel()
  }

  function close() {
    managePopupOpen = false
    trayMenuOpen = false
  }

  function openTrayMenu(item, anchorItem, mouse) {
    if (!item || !item.menu) {
      var point = anchorItem.QsWindow.contentItem.mapFromItem(anchorItem, mouse.x, mouse.y)
      item.display(anchorItem.QsWindow.window, point.x, point.y)
      return
    }

    // Reset before switching items: trayMenuOpener.menu binds to
    // activeTrayItem.menu, so assigning a new item invalidates the old root's
    // children immediately, before any nested opener referencing them would
    // otherwise get torn down.
    resetTrayMenu()
    activeTrayItem = item
    activeTrayAnchor = anchorItem
    trayMenuOpen = true
  }

  function trayIconSource(icon) {
    // Quickshell already resolves the tray icon into a ready-to-use image://
    // URL, including a "?path=" fallback search dir for apps that ship their
    // tray icon outside a standard theme (e.g. Steam's flat public/ dir). Hand
    // it straight to IconImage; guessing a theme sub-directory here only broke
    // apps whose layout didn't match the guess.
    return String(icon || "")
  }

  // Symbolic icons ship a fixed fill (often near-white) that the host is meant
  // to recolor to its foreground; detect them by the freedesktop "-symbolic"
  // name suffix so they can be tinted instead of rendered as-is.
  function iconIsSymbolic(icon) {
    var name = String(icon || "").split("?")[0]
    return name.slice(-9) === "-symbolic"
  }

  function trayTooltip(item) {
    return item.tooltipTitle || item.title || item.id || ""
  }

  function classifyItem(item) {
    var iid = String(item.id || "")
    if (hiddenIds.indexOf(iid) !== -1) return "hidden"
    if (pinnedIds.indexOf(iid) !== -1) return "pinned"
    return "drawer"
  }

  function ownedByOmarchy(item) {
    var layout = root.bar && root.bar.layoutConfig ? root.bar.layoutConfig : null
    return TrayModel.ownedByOmarchy(item, layout)
  }

  function bucket(category) {
    var values = SystemTray.items.values
    var result = []
    for (var i = 0; i < values.length; i++) {
      var item = values[i]
      if (item.status === Status.Passive) continue
      if (ownedByOmarchy(item)) continue
      if (category === "all") {
        result.push(item)
        continue
      }
      if (classifyItem(item) === category) result.push(item)
    }
    return result
  }

  function persistTrayState(pinned, hidden) {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") return
    var id = root.moduleName || "omarchy.tray"
    // updateEntryInline replaces the whole entry: keep its other keys (a custom entry's `source`)
    var next = Object.assign({}, root.settings || {}, { id: id, pinned: pinned, hidden: hidden })
    root.bar.shell.updateEntryInline(id, next)
  }

  function togglePin(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = p.indexOf(iid)
    if (idx !== -1) p.splice(idx, 1)
    else {
      p.push(iid)
      var hi = h.indexOf(iid)
      if (hi !== -1) h.splice(hi, 1)
    }
    persistTrayState(p, h)
  }

  function toggleHide(iid) {
    var p = pinnedIds.slice(), h = hiddenIds.slice()
    var idx = h.indexOf(iid)
    if (idx !== -1) h.splice(idx, 1)
    else {
      h.push(iid)
      var pi = p.indexOf(iid)
      if (pi !== -1) p.splice(pi, 1)
    }
    persistTrayState(p, h)
  }

  visible: pinnedItems.length > 0 || drawerCount > 0
  clip: false
  implicitWidth: root.vertical ? root.barSize : trayContent.implicitWidth
  implicitHeight: root.vertical ? trayContent.implicitHeight : root.barSize

  // The drawer slides open like a panel (slow), closes faster.
  // Keyed on the Behavior's own targetValue so the timing is already right
  // when the animation starts (no binding-order race with `expanded`).
  Behavior on revealProgress {
    id: revealBehavior
    NumberAnimation {
      duration: revealBehavior.targetValue > 0.5 ? Theme.dur("slow") : Theme.exit(Theme.dur("slow"))
      easing.type: Easing.BezierSpline
      easing.bezierCurve: revealBehavior.targetValue > 0.5 ? Theme.curve("out") : Theme.curve("inOut")
    }
  }

  Loader {
    id: trayContent
    anchors.fill: parent
    sourceComponent: root.vertical ? verticalTray : horizontalTray
  }

  Component {
    id: horizontalTray

    Item {
      id: horizontalTrayRoot

      readonly property int pinnedWidth: pinnedRow.implicitWidth
      readonly property int drawerBlockWidth: root.allItems.length > 0 ? expandIcon.implicitWidth + root.drawerExtent : 0

      implicitWidth: pinnedWidth + drawerBlockWidth
      implicitHeight: root.barSize

      // Mask out the empty area the collapsed drawer reserves for its slide-in,
      // so hovering it doesn't trigger expand and clicks pass through.
      containmentMask: QtObject {
        function contains(point: point): bool {
          if (point.y < 0 || point.y > horizontalTrayRoot.height) return false
          // Drawer reveals leftward; chevron sits at the right end when collapsed
          // and slides left as it opens. The visible region starts at the chevron.
          var chevronX = root.drawerExtent - root.revealExtent
          if (point.x >= chevronX && point.x <= horizontalTrayRoot.drawerBlockWidth) return true
          // Pinned items, placed to the right of the drawer block.
          var pinnedStart = horizontalTrayRoot.drawerBlockWidth
          return point.x >= pinnedStart && point.x <= horizontalTrayRoot.implicitWidth
        }
      }

      Item {
        id: drawerArea
        x: 0
        width: horizontalTrayRoot.drawerBlockWidth
        height: root.barSize
        visible: root.allItems.length > 0

        HoverHandler {
          onHoveredChanged: root.expanded = hovered
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          width: implicitWidth
          height: implicitHeight
          x: root.drawerExtent - root.revealExtent
          slotSize: root.tray.slot
          iconComponent: Component {
            VIcon { name: "chevron.left"; weight: "bold"; size: Theme.core.surface.menubar.icon; color: root.foreground }
          }
          onPressed: function(button) {
            if (button !== Qt.RightButton) return
            root.manageAnchor = expandIcon
            root.managePopupOpen = !root.managePopupOpen
          }
        }

        Item {
          id: trayClip
          x: expandIcon.width
          anchors.verticalCenter: parent.verticalCenter
          width: root.drawerExtent
          height: root.barSize
          clip: true

          Row {
            id: trayIcons
            x: root.drawerExtent - root.revealExtent
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.trayItemGap
            layer.enabled: true

            Repeater {
              model: root.drawerItems
              TrayItem {}
            }
          }
        }
      }

      Row {
        id: pinnedRow
        x: drawerArea.x + horizontalTrayRoot.drawerBlockWidth
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.trayItemGap
        leftPadding: root.pinnedItems.length > 0 && root.allItems.length > 0 ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
      }
    }
  }

  Component {
    id: verticalTray

    Item {
      id: verticalTrayRoot

      readonly property int pinnedHeight: pinnedCol.implicitHeight
      readonly property int drawerBlockHeight: root.allItems.length > 0 ? expandIcon.implicitHeight + root.drawerExtent : 0

      implicitWidth: root.barSize
      implicitHeight: pinnedHeight + drawerBlockHeight

      containmentMask: QtObject {
        function contains(point: point): bool {
          if (point.x < 0 || point.x > verticalTrayRoot.width) return false
          var chevronY = root.drawerExtent - root.revealExtent
          if (point.y >= chevronY && point.y <= verticalTrayRoot.drawerBlockHeight) return true
          var pinnedStart = verticalTrayRoot.drawerBlockHeight
          return point.y >= pinnedStart && point.y <= verticalTrayRoot.implicitHeight
        }
      }

      Item {
        id: drawerArea
        y: 0
        width: root.barSize
        height: verticalTrayRoot.drawerBlockHeight
        visible: root.allItems.length > 0

        HoverHandler {
          onHoveredChanged: root.expanded = hovered
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          width: implicitWidth
          height: implicitHeight
          y: root.drawerExtent - root.revealExtent
          slotSize: root.tray.slot
          iconComponent: Component {
            VIcon { name: "chevron.left"; weight: "bold"; size: Theme.core.surface.menubar.icon; color: root.foreground; rotation: 90 }
          }
          onPressed: function(button) {
            if (button !== Qt.RightButton) return
            root.manageAnchor = expandIcon
            root.managePopupOpen = !root.managePopupOpen
          }
        }

        Item {
          id: trayClip
          y: expandIcon.height
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.barSize
          height: root.drawerExtent
          clip: true

          Column {
            id: trayIcons
            y: root.drawerExtent - root.revealExtent
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.trayItemGap
            layer.enabled: true

            Repeater {
              model: root.drawerItems
              TrayItem {}
            }
          }
        }
      }

      Column {
        id: pinnedCol
        y: drawerArea.y + verticalTrayRoot.drawerBlockHeight
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.trayItemGap
        topPadding: root.pinnedItems.length > 0 && root.allItems.length > 0 ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
      }
    }
  }

  // ── Tray Icons popover (right click on the chevron): which icons stay in the bar, which
  // never show. A bar popup (VBarPopup, motion.barPopup): grows out of the chevron, any click
  // outside closes it, the chevron's own click closes it too.
  property Item manageAnchor: null

  VBarPopup {
    id: managePopup
    kind: "panel"
    anchorItem: root.manageAnchor || root
    bar: root.bar
    open: root.managePopupOpen
    // padded like the Control Center and the other bar popups (layout.module)
    pad: Theme.layout.module.pad
    onDismissed: root.managePopupOpen = false
    onEscapePressed: root.managePopupOpen = false

    Column {
      id: manageColumn
      width: root.tray.manageWidth
      spacing: Theme.layout.list.gap

      // the title block stands a module gap above the rows
      Column {
        width: parent.width
        bottomPadding: Theme.layout.module.gap - Theme.layout.list.gap
        VText {
          width: parent.width
          text: "Tray Icons"
          font.weight: Font.DemiBold
          color: Theme.r.popover.ink
        }
        VText {
          width: parent.width
          wrapMode: Text.WordWrap
          text: "Pinned icons stay visible. Hidden icons never show."
          font.pixelSize: Theme.m.type.small
          color: Theme.r.popover.inkSecondary
        }
      }

      VText {
        visible: root.allItems.length === 0
        width: parent.width
        text: "No tray items reporting."
        color: Theme.r.popover.inkSecondary
      }

      Repeater {
        model: root.allItems
        delegate: Item {
          id: rowRoot
          required property var modelData
          required property int index
          width: manageColumn.width
          height: Math.max(Theme.m.menu.row, pinBtn.implicitHeight)

          readonly property string itemId: String(modelData.id || "")
          readonly property string displayName: {
            var t = String(modelData.title || "").trim()
            if (t) return t
            var tt = String(modelData.tooltipTitle || "").trim()
            if (tt) return tt
            var id = String(modelData.id || "")
            var slash = id.lastIndexOf("/")
            return slash !== -1 ? id.substring(slash + 1) : (id || "Unknown")
          }
          readonly property bool isPinned: root.pinnedIds.indexOf(itemId) !== -1
          readonly property bool isHidden: root.hiddenIds.indexOf(itemId) !== -1

          TrayIcon {
            id: rowIcon
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.layout.icon.regular
            height: Theme.layout.icon.regular
            icon: rowRoot.modelData.icon
            tint: Theme.r.popover.ink
          }

          VText {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            x: rowIcon.width + Theme.layout.menu.glyphGap
            width: hideBtn.x - x - Theme.layout.list.gap
            text: rowRoot.displayName
            color: rowRoot.isHidden ? Theme.r.popover.inkSecondary : Theme.r.popover.ink
          }

          VButton {
            id: hideBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: pinBtn.left
            anchors.rightMargin: Theme.layout.list.gap
            text: rowRoot.isHidden ? "Show" : "Hide"
            onClicked: root.toggleHide(rowRoot.itemId)
          }

          VButton {
            id: pinBtn
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            text: rowRoot.isPinned ? "Unpin" : "Pin"
            onClicked: root.togglePin(rowRoot.itemId)
          }
        }
      }
    }
  }

  QsMenuOpener {
    id: trayMenuOpener
    menu: root.activeTrayItem ? root.activeTrayItem.menu : null
  }

  // ── An app's tray menu: a Velum menu (menu roles and material). It opens with no transition,
  // the highlight jumps with the pointer or the keys (↑ ↓ ⏎ → into a submenu, ← back), a chosen
  // entry blinks once, then it fires and the menu fades out (menu.close × exit). A submenu is
  // drilled into in place, below a back row with its title.
  VBarWindow {
    id: trayMenuWindow
    anchorItem: root.activeTrayAnchor || root
    bar: root.bar
    open: root.trayMenuOpen
    onDismissed: root.trayMenuOpen = false
    onEscapePressed: root.trayMenuOpen = false
    onKeyPressed: function (e) { trayMenu.key(e) }

    Item {
      id: trayMenu
      readonly property real pad: Theme.m.menu.pad
      readonly property var hairline: (Theme.r.menu.shadow || []).filter(function (l) { return !l.inset && l.blur === 0 })[0]
      // the entry under the pointer or the keys: an index into the rows, or -2 for the back row
      property int highlighted: -1
      property bool flashOff: false
      property bool busy: false
      property var pending: null

      readonly property var entries: root.currentChildren ? root.currentChildren.values : []
      readonly property bool checkColumn: {
        for (var i = 0; i < entries.length; i++)
          if (entries[i] && !entries[i].isSeparator && entries[i].buttonType !== QsMenuButtonType.None) return true
        return false
      }
      readonly property bool iconColumn: {
        for (var i = 0; i < entries.length; i++)
          if (entries[i] && !entries[i].isSeparator && String(entries[i].icon || "") !== "") return true
        return false
      }
      // where a row's label starts (the check and icon columns in front of it)
      readonly property real labelX: Theme.layout.menu.itemPadX
        + (checkColumn ? Theme.layout.icon.small + Theme.layout.menu.glyphGap : 0)
        + (iconColumn ? Theme.layout.icon.regular + Theme.layout.menu.glyphGap : 0)
      readonly property real rowsWidth: {
        var w = backRow.visible ? backRow.implicitWidth : 0
        for (var i = 0; i < rows.count; i++) { var it = rows.itemAt(i); if (it) w = Math.max(w, it.implicitWidth) }
        return w
      }
      readonly property real headerHeight: menuHeader.visible ? menuHeader.implicitHeight : 0

      x: trayMenuWindow.clampX(width, trayMenuWindow.anchorX)
      y: trayMenuWindow.barStrip + trayMenuWindow.gap
      width: Math.min(trayMenuWindow.screenW - 2 * trayMenuWindow.margin, Math.max(Theme.m.menu.minWidth, rowsWidth + 2 * pad))
      height: Math.min(root.tray.menuMaxHeight, headerHeight + trayMenuColumn.implicitHeight + 2 * pad)
      opacity: 0
      visible: opacity > 0
      // The menu fades out with its submenu still showing; back to the root level only once it
      // is gone (a switch to another tray item resets at once, from openTrayMenu()).
      onVisibleChanged: if (!visible) root.resetTrayMenu()

      Connections {
        target: root
        function onTrayMenuOpenChanged() {
          if (root.trayMenuOpen) {
            fade.stop(); flash.stop()
            trayMenu.highlighted = -1; trayMenu.flashOff = false; trayMenu.busy = false; trayMenu.pending = null
            trayMenu.opacity = 1
          } else fade.restart()
        }
        function onSubmenuDepthChanged() { trayMenu.highlighted = -1 }
      }

      NumberAnimation {
        id: fade
        target: trayMenu; property: "opacity"; to: 0
        duration: Theme.exit(Theme.transitionMs("menu.close"))
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Theme.motion("menu.close").curve
      }

      function rowAt(i) { return i >= 0 ? rows.itemAt(i) : null }
      function selectable(i) {
        var it = rowAt(i)
        return !!it && !it.hiddenRow && !it.modelData.isSeparator && it.modelData.enabled
      }
      function step(dir) {
        var n = rows.count, i = highlighted < 0 ? (dir > 0 ? -1 : n) : highlighted
        for (var k = 0; k < n; k++) {
          i += dir
          if (i < 0 || i >= n) return
          if (selectable(i)) { highlighted = i; reveal(i); return }
        }
      }
      // keep a row picked by the keys inside the scrolled area
      function reveal(i) {
        var it = rowAt(i)
        if (!it) return
        if (it.y < trayMenuFlick.contentY) trayMenuFlick.contentY = it.y
        else if (it.y + it.height > trayMenuFlick.contentY + trayMenuFlick.height)
          trayMenuFlick.contentY = it.y + it.height - trayMenuFlick.height
      }
      function goBack() {
        if (root.menuLevelSettling || busy || root.submenuDepth === 0) return
        // reset before the model swap so the parent level shows from the top
        trayMenuFlick.contentY = 0
        root.leaveSubmenu()
      }
      function activate(i) {
        if (root.menuLevelSettling || busy || !selectable(i)) return
        var it = rowAt(i)
        if (it.modelData.hasChildren) {
          // reset scroll BEFORE swapping the model: the swap destroys this row synchronously
          trayMenuFlick.contentY = 0
          root.enterSubmenu(it.modelData, it.rowText)
          return
        }
        busy = true; highlighted = i; pending = it.modelData
        flash.restart()
      }
      function key(e) {
        if (e.key === Qt.Key_Down) { step(1); e.accepted = true }
        else if (e.key === Qt.Key_Up) { step(-1); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { activate(highlighted); e.accepted = true }
        else if (e.key === Qt.Key_Right && selectable(highlighted) && rowAt(highlighted).modelData.hasChildren) { activate(highlighted); e.accepted = true }
        else if ((e.key === Qt.Key_Left || e.key === Qt.Key_Backspace) && root.submenuDepth > 0) { goBack(); e.accepted = true }
      }

      // the NSMenu blink: off, on, then the entry fires and the menu fades out
      SequentialAnimation {
        id: flash
        ScriptAction { script: trayMenu.flashOff = true }
        PauseAnimation { duration: Theme.dur("flash") }
        ScriptAction { script: trayMenu.flashOff = false }
        PauseAnimation { duration: Theme.dur("flash") }
        ScriptAction {
          script: {
            // busy stays on until the next open: the highlight holds while the menu fades out
            var entry = trayMenu.pending
            trayMenu.pending = null
            try { if (entry) entry.triggered() } catch (err) {}
            root.close()
          }
        }
      }

      VShadow { layers: Theme.r.menu.shadow; radius: Theme.m.radius.menu }
      Rectangle {
        anchors.fill: parent
        radius: Theme.m.radius.menu
        color: Theme.reduceTransparency ? Theme.r.menu.bgOpaque : Theme.r.menu.bg
        border.width: trayMenu.hairline ? trayMenu.hairline.spread : 0
        border.color: trayMenu.hairline ? trayMenu.hairline.color : "transparent"
      }
      VLens { layers: Theme.r.menu.shadow; radius: Theme.m.radius.menu }

      // the rows sit inside this area: it stays hovered while a row is, so leaving a separator
      // for the row next to it never clears the highlight the row just set
      MouseArea {
        id: menuArea
        x: trayMenu.pad
        y: trayMenu.pad
        width: trayMenu.width - 2 * trayMenu.pad
        height: trayMenu.height - 2 * trayMenu.pad
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onExited: if (!trayMenu.busy) trayMenu.highlighted = -1

        // Header of a drilled-into submenu: names where we are and walks back out. Above the
        // scrolling rows, so the way back stays reachable in a submenu taller than the menu.
        Column {
          id: menuHeader
          visible: root.submenuDepth > 0
          width: parent.width

          Item {
            id: backRow
            readonly property bool lit: trayMenu.highlighted === -2 && !trayMenu.flashOff
            width: parent.width
            height: Theme.m.menu.row
            implicitWidth: backTitle.x + backTitle.implicitWidth + Theme.layout.menu.itemPadX

            Rectangle {
              visible: backRow.lit
              anchors.fill: parent
              radius: Theme.m.radius.menuRow
              gradient: Gradient {
                GradientStop { position: 0; color: Theme.r.menu.highlightTop }
                GradientStop { position: 1; color: Theme.r.menu.highlight }
              }
            }
            VIcon {
              id: backGlyph
              x: Theme.layout.menu.itemPadX
              anchors.verticalCenter: parent.verticalCenter
              name: "chevron.left"; weight: "bold"; size: Theme.layout.icon.small
              color: backRow.lit ? Theme.r.menu.highlightInk : Theme.r.menu.inkSecondary
            }
            Text {
              id: backTitle
              textFormat: Text.PlainText
              x: backGlyph.x + backGlyph.width + Theme.layout.menu.glyphGap
              width: parent.width - x - Theme.layout.menu.itemPadX
              height: parent.height
              verticalAlignment: Text.AlignVCenter
              elide: Text.ElideRight
              text: root.currentTitle
              font.family: Theme.font
              font.pixelSize: Theme.m.menu.font
              font.weight: Font.DemiBold
              color: backRow.lit ? Theme.r.menu.highlightInk : Theme.r.menu.ink
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: if (!trayMenu.busy && !root.menuLevelSettling) trayMenu.highlighted = -2
              onClicked: trayMenu.goBack()
            }
          }

          Item {
            width: parent.width
            height: 2 * Theme.layout.menu.separatorGap + Theme.layout.separator
            Rectangle {
              x: Theme.layout.menu.itemPadX; y: Theme.layout.menu.separatorGap
              width: parent.width - 2 * x; height: Theme.layout.separator
              color: Theme.r.menu.line
            }
          }
        }

        Flickable {
          id: trayMenuFlick
          y: trayMenu.headerHeight
          width: parent.width
          height: parent.height - trayMenu.headerHeight
          contentWidth: width
          contentHeight: trayMenuColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          flickDeceleration: Theme.core.motion.scroll.flickDeceleration
          maximumFlickVelocity: Theme.core.motion.scroll.maximumFlickVelocity

          Column {
            id: trayMenuColumn
            width: trayMenuFlick.width

            Repeater {
              id: rows
              model: root.currentChildren

              delegate: Item {
                id: menuRow
                required property var modelData
                required property int index

                readonly property string rowText: String(modelData.text || "")
                readonly property string activeTitle: root.activeTrayItem ? String(root.activeTrayItem.title || root.activeTrayItem.id || "") : ""
                // Both only ever describe the root menu; inside a submenu the first rows are real
                // entries and must not be swallowed.
                readonly property bool atRoot: root.submenuDepth === 0
                readonly property bool rootTitleEntry: atRoot && index === 0 && modelData.hasChildren && rowText.toLowerCase() === activeTitle.toLowerCase()
                readonly property bool leadingSeparator: atRoot && modelData.isSeparator && index <= 1
                readonly property bool hiddenRow: rootTitleEntry || leadingSeparator
                readonly property bool sep: modelData.isSeparator
                readonly property bool lit: index === trayMenu.highlighted && !trayMenu.flashOff
                readonly property color ink: lit ? Theme.r.menu.highlightInk : Theme.r.menu.ink

                visible: !hiddenRow
                width: trayMenuColumn.width
                height: hiddenRow ? 0 : sep ? 2 * Theme.layout.menu.separatorGap + Theme.layout.separator : Theme.m.menu.row
                implicitWidth: hiddenRow || sep ? 0 : trayMenu.labelX + label.implicitWidth
                  + (modelData.hasChildren ? Theme.layout.menu.keyGap + Theme.layout.icon.small : 0) + Theme.layout.menu.itemPadX

                Rectangle {
                  visible: menuRow.sep
                  x: Theme.layout.menu.itemPadX; y: Theme.layout.menu.separatorGap
                  width: parent.width - 2 * x; height: Theme.layout.separator
                  color: Theme.r.menu.line
                }
                // the highlight jumps (never glides)
                Rectangle {
                  visible: menuRow.lit && !menuRow.sep
                  anchors.fill: parent
                  radius: Theme.m.radius.menuRow
                  gradient: Gradient {
                    GradientStop { position: 0; color: Theme.r.menu.highlightTop }
                    GradientStop { position: 1; color: Theme.r.menu.highlight }
                  }
                }

                Item {
                  visible: !menuRow.sep
                  anchors.fill: parent
                  opacity: menuRow.modelData.enabled ? 1 : Theme.core.alpha.disabled

                  VIcon {
                    visible: trayMenu.checkColumn && menuRow.modelData.checkState === Qt.Checked
                    x: Theme.layout.menu.itemPadX
                    anchors.verticalCenter: parent.verticalCenter
                    name: "check"; weight: "bold"; size: Theme.layout.icon.small
                    color: menuRow.ink
                  }
                  Image {
                    visible: trayMenu.iconColumn && String(menuRow.modelData.icon || "") !== ""
                    x: trayMenu.labelX - Theme.layout.menu.glyphGap - width
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.layout.icon.regular
                    height: Theme.layout.icon.regular
                    fillMode: Image.PreserveAspectFit
                    // decode at physical pixels: the logical size leaves PNG icons blurry on HiDPI
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    source: menuRow.modelData.icon
                  }
                  Text {
                    id: label
                    textFormat: Text.PlainText
                    x: trayMenu.labelX
                    width: (submenuGlyph.visible ? submenuGlyph.x - Theme.layout.menu.glyphGap : parent.width - Theme.layout.menu.itemPadX) - x
                    height: parent.height
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                    text: menuRow.rowText
                    font.family: Theme.font
                    font.pixelSize: Theme.m.menu.font
                    font.weight: Theme.m.menu.weight
                    color: menuRow.ink
                  }
                  VIcon {
                    id: submenuGlyph
                    visible: menuRow.modelData.hasChildren
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.layout.menu.itemPadX
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron.right"; weight: "bold"; size: Theme.layout.icon.small
                    color: menuRow.lit ? Theme.r.menu.highlightInk : Theme.r.menu.inkSecondary
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: !menuRow.sep && !menuRow.hiddenRow
                  // rows rebuilt by a level change are created on top of each other under a still
                  // pointer and each reports an enter: none of them counts until the level settles
                  onEntered: if (!trayMenu.busy && !root.menuLevelSettling) trayMenu.highlighted = trayMenu.selectable(menuRow.index) ? menuRow.index : -1
                  onClicked: trayMenu.activate(menuRow.index)
                }
              }
            }
          }
        }
      }
    }
  }

  // Renders a tray icon, recoloring symbolic icons to the bar foreground so
  // they stay visible on any theme (a raw symbolic icon keeps its baked-in
  // fill and disappears against a matching background).
  component TrayIcon: Item {
    id: trayIconRoot
    required property var icon
    // the colour a symbolic icon takes: the bar's ink in the bar, the surface's ink in a popover
    property color tint: root.foreground
    readonly property bool symbolic: root.iconIsSymbolic(icon)

    Image {
      id: trayIconImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      // Decode at physical pixels: IconImage uses the logical size,
      // which leaves PNG icons upscaled and blurry on HiDPI displays.
      sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      source: root.trayIconSource(trayIconRoot.icon)
      // Kept as a hidden layer so the effect can sample it as a texture.
      visible: !trayIconRoot.symbolic
      layer.enabled: trayIconRoot.symbolic
    }

    MultiEffect {
      anchors.fill: trayIconImage
      source: trayIconImage
      visible: trayIconRoot.symbolic
      colorization: 1.0
      colorizationColor: trayIconRoot.tint
    }
  }

  component TrayItem: Item {
    id: trayItemRoot

    required property var modelData

    visible: modelData.status !== Status.Passive
    implicitWidth: visible ? root.trayItemExtent : 0
    implicitHeight: visible ? root.trayItemExtent : 0

    function displayMenu(mouse) {
      root.openTrayMenu(trayItemRoot.modelData, trayItemRoot, mouse)
    }

    TrayIcon {
      anchors.centerIn: parent
      width: Theme.core.surface.menubar.icon
      height: Theme.core.surface.menubar.icon
      icon: trayItemRoot.modelData.icon
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      // A held finger (or button) is a right click: the menu opens, the release activates nothing.
      pressAndHoldInterval: Theme.delay("longPress")
      property bool held: false
      onEntered: if (root.bar) root.bar.showTooltip(trayItemRoot, root.trayTooltip(modelData))
      onExited: if (root.bar) root.bar.hideTooltip(trayItemRoot)
      onPressAndHold: function(mouse) {
        if (mouse.button !== Qt.LeftButton) return
        held = true
        trayItemRoot.displayMenu(mouse)
      }
      onPressed: function(mouse) {
        held = false
        if (mouse.button === Qt.RightButton) {
          trayItemRoot.displayMenu(mouse)
          mouse.accepted = true
        }
      }
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton || held) {
          mouse.accepted = true
        } else if (mouse.button === Qt.MiddleButton) {
          trayItemRoot.modelData.secondaryActivate()
        } else if (trayItemRoot.modelData.onlyMenu) {
          trayItemRoot.displayMenu(mouse)
        } else {
          trayItemRoot.modelData.activate()
        }
      }
      onWheel: function(wheel) {
        trayItemRoot.modelData.scroll(wheel.angleDelta.y, false)
      }
    }

    readonly property bool tooltipHovered: visible && opacity > 0 && mouseArea.containsMouse
  }
}
