import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "file:///home/henri/.local/share/velum/qml/Velum"

// The keyboard in the menu bar: a finger's way to the on-screen keyboard on a machine with a
// touchscreen of its own (the tablet), where the window bar is only there in tablet mode. A tap
// toggles the keyboard on this bar's screen (the custom event Keyboard.qml takes from the window
// bar too). Hidden where no hardware touchscreen exists — ipadcast's and velum's virtual touch
// devices don't count: the cast screen has the window bar's keyboard button.
BarWidget {
  id: root
  moduleName: "henri.keyboard-v3"

  property bool hasTouch: false
  readonly property string screenName: QsWindow.window && QsWindow.window.screen ? QsWindow.window.screen.name : ""

  // udev marks touchscreens; a virtual one (uinput) lives under /devices/virtual
  Process {
    id: probe
    running: true
    command: ["sh", "-c", "for f in $(grep -l '^E:ID_INPUT_TOUCHSCREEN=1' /run/udev/data/c13:* 2>/dev/null); do "
      + "case $(readlink -f /sys/dev/char/${f##*/c}) in */virtual/*) ;; *) echo touch; exit 0 ;; esac; done"]
    stdout: StdioCollector { onStreamFinished: root.hasTouch = String(text).indexOf("touch") >= 0 }
  }

  function toggle() {
    if (!root.screenName) return
    var e = "velum-keyboard toggle " + root.screenName
    Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.event(\"" + e + "\")" : "event " + e)
  }

  visible: hasTouch
  implicitWidth: hasTouch ? button.implicitWidth : 0
  implicitHeight: hasTouch ? button.implicitHeight : 0

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        VIcon {
          anchors.centerIn: parent
          name: "keyboard"
          weight: "fill"
          size: Theme.core.surface.menubar.icon
          color: button ? button.foreground : Theme.r.popover.ink   // Velum's ink, never Omarchy's Color
        }
      }
    }
    tooltipText: ""
    onPressed: function (b) { root.toggle() }
  }
}
