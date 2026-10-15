import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion

// btpad (~/Projects/btpad) lends this Mac's keyboard and trackpad to another
// computer. While they work over there, the bar says so ("󰌌 MW408"); while
// they are back here and the other computer stays connected (Super+Shift+F11),
// the same label sits dimmed and a click switches over again. Nothing shows
// while the mode is off.
//
// State comes from btpadd's control socket ("watch" streams one JSON line per
// change), so there is no polling and no process per update.
BarWidget {
  id: root
  moduleName: "henri.btpad"

  readonly property string socketPath: "/run/btpad/btpad.sock"
  property var btState: ({ state: "off" })
  readonly property string mode: btState.state || "off"
  readonly property bool remote: mode === "waiting" || mode === "pairing" || mode === "connected"
  readonly property bool shown: remote || mode === "local"

  readonly property string hostName: btState.host || ""
  readonly property string label: {
    if (mode === "pairing") return "󰌌  Pairing"
    if (mode === "waiting") return "󰌌  Connecting"
    if (mode === "local") return hostName ? "󰌌  " + hostName : "󰌌"
    return "󰌌  → " + (hostName || "…")
  }
  // Kept through the fade-out, cleared once it has finished so the slot goes.
  property string shownLabel: ""

  readonly property string tooltip: {
    if (mode === "local")
      return (hostName || "The other computer") + " stays connected · click or Super+Shift+F11 to work on it"
    if (mode === "pairing") return "Waiting for a new computer to pair · Super+Shift+F12 ends"
    if (mode === "waiting") return "Keyboard and trackpad are waiting for the other computer · Super+Shift+F11 switches back"
    return "Keyboard and trackpad work " + (hostName || "the other computer") + " · Super+Shift+F11 switches back"
  }

  onLabelChanged: if (shown) shownLabel = label
  onShownChanged: {
    if (shown) {
      clearTimer.stop()
      shownLabel = label
    } else {
      clearTimer.restart()
    }
  }

  Timer {
    id: clearTimer
    interval: Motion.exit(Motion.fast) + 40
    onTriggered: if (!root.shown) root.shownLabel = ""
  }

  Socket {
    id: sock
    path: root.socketPath
    connected: true
    onConnectionStateChanged: {
      if (connected) {
        write("watch\n")
        flush()
      } else {
        root.btState = { state: "off" }
        retry.restart()
      }
    }
    // btpadd not running yet (boot, install): try again
    onError: function(error) {
      sock.connected = false
      retry.restart()
    }
    parser: SplitParser {
      onRead: function(line) {
        try {
          root.btState = JSON.parse(line)
        } catch (e) {
        }
      }
    }
  }

  // btpadd restarts (install, bluetoothd coming back): reconnect quietly.
  Timer {
    id: retry
    interval: 3000
    onTriggered: sock.connected = true
  }

  Process {
    id: switchProc
    command: ["btpad", "switch"]
  }

  visible: shownLabel !== ""
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.shownLabel
    fontSize: Style.font.caption
    horizontalMargin: 6
    concealed: !root.shown
    dimmed: root.mode === "local"
    tooltipText: root.shown ? root.tooltip : ""
    // only reachable while input is here; over there the trackpad is grabbed
    onPressed: function() { if (!switchProc.running) switchProc.running = true }
  }
}
