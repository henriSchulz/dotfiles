import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.active-window"


  readonly property var toplevel: ToplevelManager.activeToplevel
  readonly property string title: toplevel ? (toplevel.title || toplevel.appId || "") : ""
  // Show the app's name like the macOS menu bar does ("Firefox"), not the
  // window title. The desktop entry has the proper name; otherwise prettify
  // the app id (org.gnome.Nautilus -> Nautilus, foot -> Foot).
  readonly property string appName: {
    var id = toplevel ? String(toplevel.appId || "") : ""
    if (id === "") return title
    var entry = DesktopEntries.heuristicLookup(id)
    if (entry && entry.name) return entry.name
    var last = id.split(".").pop().replace(/[-_]+/g, " ")
    return last.charAt(0).toUpperCase() + last.slice(1)
  }
  readonly property int maxLabelWidth: Number(setting("maxWidth", 280))

  visible: appName !== "" && !vertical
  implicitWidth: visible ? Math.min(maxLabelWidth, labelText.implicitWidth) + Style.spacing.controlPaddingX * 2 : 0
  implicitHeight: barSize

  Behavior on implicitWidth {
    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
  }

  Item {
    anchors.fill: parent
    anchors.leftMargin: Style.space(8)
    anchors.rightMargin: Style.space(8)
    clip: true

    Text {
      id: labelText
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      width: parent.width
      text: root.appName
      color: root.bar ? root.bar.barForeground : Color.foreground
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      font.weight: Font.DemiBold
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor

    onClicked: function(mouse) {
      if (!root.toplevel) return
      if (mouse.button === Qt.MiddleButton) {
        root.toplevel.close()
      } else if (mouse.button === Qt.RightButton) {
        root.toplevel.close()
      } else {
        // Like the app menu on macOS: open this app's settings.
        root.toplevel.activate()
        Util.execArgv([Quickshell.env("HOME") + "/.local/bin/app-settings", root.toplevel.appId || ""])
      }
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.title + "\nKlicken: Einstellungen")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }
}
