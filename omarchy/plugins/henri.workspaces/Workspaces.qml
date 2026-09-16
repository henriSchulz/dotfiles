import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // Only workspaces that hold windows, plus the focused one.
  function workspaceIds() {
    var ids = []
    var values = Hyprland.workspaces.values
    var focusedId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : -1

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0 || id > 10 || ids.indexOf(id) !== -1) continue
      if (values[i].toplevels.values.length > 0 || id === focusedId) ids.push(id)
    }
    if (focusedId > 0 && focusedId <= 10 && ids.indexOf(focusedId) === -1) ids.push(focusedId)

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        text: String(modelData)
        opacity: focused ? 1 : 0.6
        useActiveColor: false

        // Focused workspace: soft rounded highlight, like a selected macOS menu item.
        Rectangle {
          z: -1
          anchors.centerIn: parent
          width: Style.space(18)
          height: Style.space(18)
          radius: Style.space(5)
          color: Qt.rgba(root.bar ? root.bar.barForeground.r : 1,
            root.bar ? root.bar.barForeground.g : 1,
            root.bar ? root.bar.barForeground.b : 1, 0.18)
          visible: parent.focused
        }
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }
}
