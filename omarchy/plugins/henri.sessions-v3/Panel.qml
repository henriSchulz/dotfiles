import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "file:///home/henri/.local/share/velum/qml/Velum"

// Claude Code in the menu bar: a terminal glyph while any session runs, with a dot at its corner —
// orange (surface.sessions.attention) while one waits for Henri, the accent while they work.
// Hidden when nothing runs. A click opens a bar popup (motion.barPopup) with the running sessions,
// the waiting ones first: a row brings its terminal forward (or resumes / attaches it), the
// footer opens the Sessions window. The rows come from Service.qml through the runtime file.
BarWidget {
  id: root
  moduleName: "henri.sessions-v3"
  readonly property var s: Theme.core.surface.sessions
  readonly property var b: s.bar
  readonly property string backend: (Quickshell.env("HOME") || "") + "/Projects/sessions/bin/sessions-backend"
  readonly property string app: (Quickshell.env("HOME") || "") + "/Projects/sessions/bin/sessions"
  readonly property bool inRig: (Quickshell.env("VELUM_SHELL_RIG") || "") !== ""

  property var rows: []
  FileView {
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/henri-sessions-" + Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") + ".json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: { try { root.rows = JSON.parse(text()).rows || [] } catch (e) {} }
  }
  readonly property int waiting: rows.filter(function (r) { return r.status === "attention" }).length
  readonly property int working: rows.filter(function (r) { return r.status === "working" }).length
  readonly property int idle: rows.length - waiting - working
  // the dot: orange while one waits, the accent while one works, none while they only sit idle
  readonly property color dotColor: waiting ? s.attention : Theme.r.accent.base

  property bool popupOpen: false
  onRowsChanged: if (!rows.length) popupOpen = false

  // `henri-sessions toggle` as a Hyprland custom event (a key binding, or Service's IPC `toggle`):
  // the bar on the focused monitor opens its popup
  readonly property string screenName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "custom" || String(event.data) !== "henri-sessions toggle") return
      if (root.visible && Hyprland.focusedMonitor && Hyprland.focusedMonitor.name === root.screenName) root.popupOpen = !root.popupOpen
    }
  }

  visible: rows.length > 0
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        VIcon {
          id: glyph
          anchors.centerIn: parent
          name: "terminal"
          weight: "fill"
          size: Theme.core.surface.menubar.icon
          color: button ? button.foreground : Theme.r.popover.ink   // Velum's ink, never Omarchy's Color
          // the status dot on the glyph's top right (the bar may be clear over the wallpaper: no cut-out ring)
          Rectangle {
            x: parent.width - width / 2
            y: -height / 2
            width: root.b.badge; height: width; radius: width / 2
            visible: root.waiting > 0 || root.working > 0
            color: root.dotColor
          }
        }
      }
    }
    tooltipText: ""
    onPressed: function (btn) { root.popupOpen = !root.popupOpen }
  }

  function choose(r) {
    popupOpen = false
    if (inRig) return
    Quickshell.execDetached([backend, r.window ? "focus" : "resume", r.id])
  }
  function openApp() {
    popupOpen = false
    if (inRig) return
    Quickshell.execDetached([app, "present"])
  }

  VBarPopup {
    id: popup
    kind: "panel"
    anchorItem: button
    bar: root.bar
    open: root.popupOpen
    pad: Theme.layout.module.pad
    onDismissed: root.popupOpen = false
    onEscapePressed: root.popupOpen = false

    Column {
      width: root.b.popupWidth
      spacing: Theme.layout.list.gap

      // title + what runs, its text on the rows' inset
      Column {
        x: Theme.layout.list.padX
        width: parent.width - 2 * x
        VText { width: parent.width; text: "Claude Code"; font.weight: Font.DemiBold; color: Theme.r.popover.ink }
        VText {
          width: parent.width
          font.pixelSize: Theme.m.type.small
          color: Theme.r.popover.inkSecondary
          text: [root.waiting ? root.waiting + " waiting for you" : "", root.working ? root.working + " working" : "", root.idle ? root.idle + " idle" : ""].filter(function (x) { return x }).join(" · ")
        }
      }

      ListView {
        id: list
        width: parent.width
        height: Math.min(count, root.b.maxRows) * root.b.rowHeight
        interactive: count > root.b.maxRows
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.rows
        delegate: Item {
          id: row
          required property var modelData
          width: list.width; height: root.b.rowHeight
          Rectangle {
            anchors.fill: parent
            radius: Theme.m.radius.menuRow
            color: Theme.r.popover.fillHover
            visible: hover.containsMouse
          }
          Rectangle {
            id: dot
            x: Theme.layout.list.padX
            anchors.verticalCenter: parent.verticalCenter
            width: root.s.dot; height: width; radius: width / 2
            color: row.modelData.status === "attention" ? root.s.attention : row.modelData.status === "working" ? Theme.r.accent.base : Theme.r.popover.inkSecondary
          }
          Column {
            x: dot.x + dot.width + Theme.layout.list.padX
            width: parent.width - x - Theme.layout.list.padX
            anchors.verticalCenter: parent.verticalCenter
            VText { width: parent.width; text: row.modelData.title; color: Theme.r.popover.ink; font.weight: Font.Medium }
            VText {
              width: parent.width
              text: row.modelData.folder + " · " + row.modelData.statusText
              font.pixelSize: Theme.m.type.small
              color: Theme.r.popover.inkSecondary
            }
          }
          MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; onClicked: root.choose(row.modelData) }
        }
      }

      Rectangle { width: parent.width; height: 1 / Screen.devicePixelRatio; color: Theme.r.popover.line }
      VListRow {
        width: parent.width
        surface: "popover"
        clickable: true
        text: "Open Sessions…"
        onClicked: root.openApp()
      }
    }
  }
}
