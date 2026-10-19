import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "file:///home/henri/.local/share/velum/qml/Velum"

// System menu v3 (Velum) — the macOS Apple menu. The Omarchy logo sits in the
// bar's left corner and opens a plain menu (VMenu: no transition, the
// highlight jumps, a chosen item blinks once, then it acts). "About This
// Computer" swaps the menu for an About card; restart, shut down and log out
// ask first on a confirm card, like the "…" items on macOS. Cards are
// VPopovers in the same window (VBarWindow), under the logo.
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

  readonly property var items: [
    { text: "About This Computer", page: "about" },
    { separator: true },
    { text: "System Settings…", cmd: "omarchy-menu toggle root" },
    { text: "App Store…", cmd: "xdg-terminal-exec --app-id=org.omarchy.terminal omarchy-pkg-install" },
    { separator: true },
    { text: "Force Quit…", cmd: "hyprctl kill" },
    { separator: true },
    { text: "Sleep", cmd: "systemctl suspend" },
    { text: "Restart…", cmd: "omarchy-system-reboot", title: "Are you sure you want to restart your computer now?", confirm: "Restart" },
    { text: "Shut Down…", cmd: "omarchy-system-shutdown", title: "Are you sure you want to shut down your computer now?", confirm: "Shut Down" },
    { separator: true },
    { text: "Lock Screen", cmd: "omarchy-system-lock" },
    { text: "Log Out " + userName + "…", cmd: "omarchy-system-logout", title: "Are you sure you want to log out now?", confirm: "Log Out" }
  ]

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
    function state(): string { return JSON.stringify({ opened: root.opened, page: root.page, menu: menu.open, highlighted: menu.highlighted }) }
    function hl(i: int): void { menu.highlighted = i }
    function choose(i: int): void { menu.choose(i) }
  }

  // the menu shows on the menu page only; VMenu closes itself after a choice, so it is set, not bound
  function syncMenu() { menu.open = root.opened && root.page === "menu" }
  onPageChanged: syncMenu()
  onOpenedChanged: {
    if (opened) {
      if (page !== "about") page = "menu"
      logoSqueezed = true
      logoPulse.restart()
      if (!infoProc.running) infoProc.running = true
    } else {
      resetPage.restart()
    }
    syncMenu()
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

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.logo
    fontFamily: "omarchy"
    tooltipText: ""
    onPressed: function(b) { root.toggle() }
    scale: logoScale.value
  }
  // Press feedback on the bar logo whenever the menu opens: squeeze, then spring back.
  Spring { id: logoScale; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: root.logoSqueezed ? Theme.scale("press") : 1 }
  Timer { id: logoPulse; interval: Theme.dur("instant") || 1; onTriggered: root.logoSqueezed = false }

  VBarWindow {
    id: win
    anchorItem: button
    bar: root.bar
    open: root.opened
    namespace: "velum-surface"   // Hyprland: blur with ignore_alpha 0.6 (only the material, never the shadow), no layer animation
    onDismissed: root.close()
    onEscapePressed: root.page !== "menu" ? root.page = "menu" : root.close()
    onKeyPressed: function (e) {
      if (root.page === "menu") {
        if (e.key === Qt.Key_Down) { menu.step(1); e.accepted = true }
        else if (e.key === Qt.Key_Up) { menu.step(-1); e.accepted = true }
        else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { menu.choose(menu.highlighted); e.accepted = true }
      } else if (root.page === "confirm" && (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && root.pending) {
        root.run(root.pending.cmd); e.accepted = true
      }
      if (e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab) { root.switchPanel(e.key === Qt.Key_Backtab ? -1 : 1); e.accepted = true }
    }

    // like the Apple menu: the menu's left edge under the logo
    readonly property real cardX: win.anchorX - Theme.layout.menu.itemPadX
    readonly property real cardY: win.barStrip + win.gap

    VMenu {
      id: menu
      x: win.clampX(width, win.cardX)
      y: win.cardY
      model: root.items
      onTriggered: function (i) { root.perform(root.items[i]) }
    }

    // ------------------------------------------------------------ about
    VPopover {
      id: about
      x: win.clampX(width, win.cardX)
      y: win.cardY
      open: root.opened && root.page === "about"
      kind: "panel"   // motion.barPopup, as every popup at the menu bar
      MouseArea { width: aboutCol.width; height: aboutCol.height }   // clicks on the card never close it
      Column {
        id: aboutCol
        width: Theme.layout.module.width * 2 / 3
        spacing: Theme.layout.list.gap / 2
        topPadding: Theme.layout.module.pad
        bottomPadding: Theme.layout.module.tileInset
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.logo
          font.family: "omarchy"
          font.pixelSize: Theme.layout.module.toggle + Theme.layout.module.pad
          color: Theme.r.popover.ink
          scale: aboutLogo.value
          Spring { id: aboutLogo; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: about.open ? 1 : Theme.scale("exitTo") }
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
    }

    // ---------------------------------------------------------- confirm
    VPopover {
      id: confirm
      x: win.clampX(width, win.cardX)
      y: win.cardY
      open: root.opened && root.page === "confirm"
      kind: "panel"   // motion.barPopup, as every popup at the menu bar
      MouseArea { width: confirmCol.width; height: confirmCol.height }
      Column {
        id: confirmCol
        width: Theme.layout.module.width * 2 / 3
        spacing: Theme.layout.module.pad
        topPadding: Theme.layout.module.pad
        bottomPadding: Theme.layout.module.tileInset
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: root.logo
          font.family: "omarchy"
          font.pixelSize: Theme.layout.module.toggle
          color: Theme.r.popover.ink
          scale: confirmLogo.value
          Spring { id: confirmLogo; preset: Theme.spring("snappy"); reduced: Theme.reduceMotion; target: confirm.open ? 1 : Theme.scale("exitTo") }
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
}
