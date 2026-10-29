import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "file:///home/henri/.local/share/velum/qml/Velum"

// System menu v3 (Velum) — the macOS Apple menu, laid out like the Control
// Center. The apps glyph sits on the bar's left island (as in the Opal lab); a click grows that
// island into a panel of tiles (VIslandWindow): the computer (opens About),
// Sleep / Restart / Shut Down / Lock as round badges, then settings, App Store,
// Force Quit and Log Out as rows. Restart, shut down and log out ask first on
// a confirm card, like the "…" items on macOS. While a tablet casts this Mac's
// screen (mac-cast) and can follow, a fifth badge Sleep Both sleeps the tablet
// first and then the Mac (ipadcast, type 12 to mac-cast-kms); the Mac is woken
// by its power key, the tablet by its own.
Panel {
  id: root
  moduleName: "henri.system-menu-v3"
  ipcTarget: "henri.system-menu"
  manageIpc: false

  readonly property string logo: "\ue900"   // the Omarchy logo in the omarchy font
  readonly property string userName: Quickshell.env("USER") || ""

  // "menu" | "about" | "confirm"
  property string page: "menu"
  property var pending: null
  property var info: ({})
  property bool logoSqueezed: false

  // the power badges, then the rows (choose(i) over IPC counts about, power, rows in this order;
  // Sleep Both, when shown, is the second and moves the ones after it)
  readonly property var about: ({ text: "About This Computer", page: "about" })
  readonly property var sleepBoth: ({ text: "Sleep Both", icon: "sleep-pair", cmd: "hyprctl dispatch 'hl.dsp.event(\"ipadcast sleep\")'" })
  readonly property var power: [
    { text: "Sleep", icon: "sleep", cmd: "systemctl suspend" }
  ].concat(castSleeps ? [sleepBoth] : []).concat([
    { text: "Restart", icon: "restart", cmd: "omarchy-system-reboot", title: "Are you sure you want to restart your computer now?", confirm: "Restart" },
    { text: "Shut Down", icon: "power", cmd: "omarchy-system-shutdown", title: "Are you sure you want to shut down your computer now?", confirm: "Shut Down" },
    { text: "Lock", icon: "lock", cmd: "omarchy-system-lock" }
  ])
  readonly property var rows: [
    { text: "System Settings…", icon: "settings", cmd: "omarchy-menu toggle root" },
    { text: "App Store…", icon: "store", cmd: "xdg-terminal-exec --app-id=org.omarchy.terminal omarchy-pkg-install" },
    { text: "Force Quit…", icon: "force-quit", cmd: "hyprctl kill" }
  ]
  readonly property var logout: ({ text: "Log Out " + userName + "…", icon: "logout", cmd: "omarchy-system-logout", title: "Are you sure you want to log out now?", confirm: "Log Out" })
  readonly property var items: [about].concat(power, rows, [logout])

  // ---- the tablet that casts: ipadcast writes $XDG_RUNTIME_DIR/ipadcast/cast.json every 2 s while one
  // is connected and removes it after; sleepTablet says its mac-cast-kms follows a Sleep Both. Read here
  // and not from henri.cast-v3: plugins share no service objects. VELUM_CAST_JSON names another file (rig).
  property var cast: null
  property real castNow: Date.now() / 1000
  readonly property bool castSleeps: !!cast && cast.sleepTablet === true && castNow - cast.time < 8
  FileView {
    id: castFile
    property bool missing: true
    path: Quickshell.env("VELUM_CAST_JSON") || (Quickshell.env("XDG_RUNTIME_DIR") + "/ipadcast/cast.json")
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      let j = null
      try { j = JSON.parse(text() || "null") } catch (e) {}
      missing = false
      root.cast = j
    }
    onLoadFailed: { root.cast = null; missing = true }
  }
  // a watch can't see a file that does not exist yet: look again now and then; the clock ends a cast
  // whose reports stopped
  Timer {
    interval: 2000; repeat: true; running: true
    onTriggered: {
      root.castNow = Date.now() / 1000
      if (castFile.missing || !root.castSleeps) castFile.reload()
    }
  }

  function perform(item) {
    if (item.page) { page = item.page; return }
    if (item.confirm) { pending = item; page = "confirm"; return }
    run(item.cmd)
  }
  // Close first so the window's keyboard focus is gone before the command
  // (menus, lock screen, kill cursor) wants the keyboard or pointer.
  function run(cmd) {
    close()
    launch.cmd = cmd
    launch.restart()
  }
  Timer {
    id: launch
    property string cmd: ""
    interval: Theme.dur("slow") / 2
    onTriggered: Quickshell.execDetached(["bash", "-c", cmd])
  }

  IpcHandler {
    target: "henri.system-menu"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Opens straight onto the About card.
    function about(): void { root.page = "about"; root.open() }
    function state(): string { return JSON.stringify({ opened: root.opened, page: root.page }) }
    function choose(i: int): void { if (root.items[i]) root.perform(root.items[i]) }
  }

  onOpenedChanged: {
    if (opened) {
      if (page !== "about") page = "menu"
      logoSqueezed = true
      logoPulse.restart()
      if (!infoProc.running) infoProc.running = true
    } else {
      resetPage.restart()
    }
  }
  // Back to the menu once the cards have faded, not while they still show.
  Timer {
    id: resetPage
    interval: Theme.exit(Theme.dur("slow"))
    onTriggered: if (!root.opened) { root.page = "menu"; root.pending = null }
  }

  Process {
    id: infoProc
    command: [Qt.resolvedUrl("info.sh").toString().replace("file://", "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = {}
        text.split("\n").forEach(function(line) {
          var eq = line.indexOf("=")
          if (eq > 0) next[line.slice(0, eq)] = line.slice(eq + 1)
        })
        root.info = next
      }
    }
  }

  // Velum: beside the logo the active app's name, as macOS's bold app name on the left of the menu
  // bar (the Opal lab's "Notes"). Hidden on an empty workspace (the home screen): Hyprland's
  // activeToplevel keeps the last window there.
  readonly property var activeWin: Hyprland.activeToplevel
  readonly property var activeIpc: activeWin ? activeWin.lastIpcObject : null
  readonly property bool workspaceHasWindows: { var ws = Hyprland.focusedWorkspace, o = ws ? ws.lastIpcObject : null; return !!(o && (o.windows || 0) > 0) }
  readonly property string appName: {
    if (!activeIpc || !workspaceHasWindows) return ""
    var c = String(activeIpc.class || ""), e = null
    try { e = DesktopEntries.byId(c) || DesktopEntries.heuristicLookup(c) } catch (err) {}
    return e && e.name ? e.name : c
  }
  readonly property var mb: Theme.core.surface.menubar

  implicitWidth: button.implicitWidth + (appLabel.visible ? root.mb.island.gap + appLabel.implicitWidth : 0)
  implicitHeight: button.implicitHeight

  // the lab's left island: the apps glyph (fill) at the menu bar's icon size, as wide as the glyph,
  // so the island's padX and gap are the only space around it (the Omarchy slot added ~10 px a side)
  BarIconButton {
    id: button
    width: implicitWidth; height: parent.height
    bar: root.bar
    fixedWidth: root.bar && root.bar.vertical ? -1 : root.mb.icon
    opticalSize: root.mb.icon
    iconComponent: Component {
      VIcon { anchors.centerIn: parent; name: "apps"; weight: "fill"; size: root.mb.icon; surface: "popover"
              color: root.bar ? root.bar.foreground : Theme.r.popover.ink }
    }
    tooltipText: ""
    onPressed: function(b) { root.toggle() }
    scale: logoScale.value
  }
  VText {
    id: appLabel
    visible: root.appName !== ""
    x: button.width + root.mb.island.gap; anchors.verticalCenter: parent.verticalCenter
    text: root.appName
    color: root.bar ? root.bar.foreground : Theme.r.popover.ink
    font.pixelSize: root.mb.font.size; font.weight: Font.Bold
    MouseArea { anchors.fill: parent; onClicked: root.toggle() }
  }
  // Press feedback on the bar logo whenever the menu opens: squeeze, then spring back.
  Spring { id: logoScale; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: root.logoSqueezed ? Theme.scale("press") : 1 }
  Timer { id: logoPulse; interval: Theme.dur("instant") || 1; onTriggered: root.logoSqueezed = false }

  // A Dynamic Island: the left island of the bar (the logo) grows into the menu, and on into the
  // About or confirm card (it keeps its left and top edge, and morphs between the pages).
  VIslandWindow {
    id: win
    anchorItem: button
    bar: root.bar
    open: root.opened
    namespace: "velum-surface"   // Hyprland: blur with ignore_alpha 0.6 (only the material, never the shadow), no layer animation
    align: "left"
    focusTarget: keys
    readonly property bool onMenu: root.page === "menu"
    pad: Theme.layout.module.pad
    cornerRadius: Theme.m.radius.panel + Theme.layout.module.tileInset
    toWidth: (onMenu ? grid.width : root.page === "about" ? aboutCol.width : confirmCol.width) + 2 * pad
    contentHeight: onMenu ? grid.implicitHeight : root.page === "about" ? aboutCol.implicitHeight : confirmCol.implicitHeight
    onDismissed: root.close()
    onReopenRequested: root.open()

    Item {
      id: keys
      focus: true
      Keys.onPressed: function (e) {
        if (e.key === Qt.Key_Escape) { if (root.page !== "menu") root.page = "menu"; else root.close(); e.accepted = true; return }
        if (root.page === "confirm" && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && root.pending) {
          root.run(root.pending.cmd); e.accepted = true
        }
        if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) { root.switchPanel(e.key === Qt.Key_Backtab ? -1 : 1); e.accepted = true }
      }
    }

    // ------------------------------------------------------------- menu
    Column {
      id: grid
      readonly property bool shown: root.opened && root.page === "menu"
      visible: shown
      width: Theme.layout.module.width * 3 / 4
      spacing: Theme.layout.module.gap

      // the computer: logo, model, Omarchy version — opens About
      VTile {
        id: hero
        width: parent.width; height: Theme.layout.meter.card
        Spring { id: heroPress; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: heroMouse.pressed ? Theme.scale("press") : 1 }
        scale: heroPress.value
        Rectangle { anchors.fill: parent; radius: parent.radius; color: Theme.r.popover.fillHover; visible: heroMouse.containsMouse }
        Text {
          id: heroLogo
          x: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter
          text: root.logo; font.family: "omarchy"; font.pixelSize: Theme.layout.module.quick; color: Theme.r.popover.ink
        }
        Column {
          x: heroLogo.x + heroLogo.width + Theme.layout.module.pad; width: chev.x - x - Theme.layout.module.pad
          anchors.verticalCenter: parent.verticalCenter
          VText { width: parent.width; elide: Text.ElideRight; text: root.info.model || "Omarchy"; color: Theme.r.popover.ink; font.weight: Font.DemiBold }
          VText { width: parent.width; elide: Text.ElideRight; tone: "secondary"; font.pixelSize: Theme.m.type.small
            text: root.info.omarchy ? "Omarchy " + root.info.omarchy : (root.info.host || "") }
        }
        VIcon { id: chev; anchors.right: parent.right; anchors.rightMargin: Theme.layout.module.pad; anchors.verticalCenter: parent.verticalCenter
          name: "chevron.right"; weight: "bold"; color: Theme.r.popover.inkSecondary }
        MouseArea { id: heroMouse; anchors.fill: parent; hoverEnabled: true; onClicked: root.perform(root.about) }
      }

      // sleep, restart, shut down, lock: round badges with their names under them
      VTile {
        width: parent.width; height: powerRow.height + 2 * Theme.layout.module.pad
        Row {
          id: powerRow
          x: Theme.layout.module.pad; y: Theme.layout.module.pad; width: parent.width - 2 * x
          Repeater {
            model: root.power
            delegate: Column {
              required property var modelData
              width: powerRow.width / root.power.length
              spacing: Theme.layout.list.gap
              VBadge { anchors.horizontalCenter: parent.horizontalCenter; size: Theme.layout.module.quick; on: false; icon: modelData.icon
                onTapped: root.perform(modelData) }
              VText { width: parent.width; horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight; text: modelData.text
                font.pixelSize: Theme.m.type.small; color: Theme.r.popover.ink }
            }
          }
        }
      }

      // settings, App Store, Force Quit | Log Out
      VTile {
        width: parent.width; height: rowsCol.height + 2 * Theme.layout.module.tileInset
        Column {
          id: rowsCol
          y: Theme.layout.module.tileInset; width: parent.width
          Repeater {
            model: root.rows
            delegate: VModuleRow { required property var modelData; width: rowsCol.width; icon: modelData.icon; text: modelData.text
              onClicked: root.perform(modelData) }
          }
          VModuleSep { width: parent.width }
          VModuleRow { width: parent.width; icon: root.logout.icon; text: root.logout.text; onClicked: root.perform(root.logout) }
        }
      }
    }

    // ------------------------------------------------------------ about
    Column {
      id: aboutCol
      readonly property bool shown: root.opened && root.page === "about"
      visible: shown
      width: Theme.layout.module.width * 2 / 3
      spacing: Theme.layout.list.gap / 2
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.logo
        font.family: "omarchy"
        font.pixelSize: Theme.layout.module.toggle + Theme.layout.module.pad
        color: Theme.r.popover.ink
        scale: aboutLogo.value
        Spring { id: aboutLogo; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: aboutCol.shown ? 1 : Theme.scale("exitTo") }
      }
      Item { width: 1; height: Theme.layout.list.gap }
      VText { anchors.horizontalCenter: parent.horizontalCenter; text: root.info.model || "Omarchy"; color: Theme.r.popover.ink
        font.pixelSize: Theme.m.type.title; font.weight: Font.Bold }
      VText { anchors.horizontalCenter: parent.horizontalCenter; text: root.info.host || ""; tone: "secondary"; font.pixelSize: Theme.m.type.small }
      Item { width: 1; height: Theme.layout.list.gap }
      Repeater {
        model: [["Chip", root.info.cpu], ["Memory", root.info.memory], ["Graphics", root.info.gpu], ["Disk", root.info.disk],
                ["Omarchy", root.info.omarchy], ["Kernel", root.info.kernel], ["Uptime", root.info.uptime]]
        delegate: Row {
          required property var modelData
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Theme.layout.list.gap
          VText { width: aboutCol.width * 0.32; horizontalAlignment: Text.AlignRight; text: modelData[0]; color: Theme.r.popover.ink
            font.pixelSize: Theme.m.type.small; font.weight: Font.DemiBold }
          VText { width: aboutCol.width * 0.6; text: modelData[1] || "—"; tone: "secondary"; font.pixelSize: Theme.m.type.small; elide: Text.ElideRight }
        }
      }
      Item { width: 1; height: Theme.layout.list.gap }
      VButton { anchors.horizontalCenter: parent.horizontalCenter; text: "More Info…"; onClicked: root.run("omarchy-launch-about") }
    }

    // ---------------------------------------------------------- confirm
    Column {
      id: confirmCol
      readonly property bool shown: root.opened && root.page === "confirm"
      visible: shown
      width: Theme.layout.module.width * 2 / 3
      spacing: Theme.layout.module.pad
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.logo
        font.family: "omarchy"
        font.pixelSize: Theme.layout.module.toggle
        color: Theme.r.popover.ink
        scale: confirmLogo.value
        Spring { id: confirmLogo; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: confirmCol.shown ? 1 : Theme.scale("exitTo") }
      }
      VText {
        width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap
        text: root.pending ? root.pending.title : ""; color: Theme.r.popover.ink; font.weight: Font.DemiBold
      }
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Theme.layout.list.gap
        VButton { width: (confirmCol.width - Theme.layout.list.gap) / 2 - Theme.layout.module.pad; text: "Cancel"; onClicked: root.page = "menu" }
        VButton { width: (confirmCol.width - Theme.layout.list.gap) / 2 - Theme.layout.module.pad; kind: "primary"; text: root.pending ? root.pending.confirm : ""
          onClicked: if (root.pending) root.run(root.pending.cmd) }
      }
    }
  }
}
