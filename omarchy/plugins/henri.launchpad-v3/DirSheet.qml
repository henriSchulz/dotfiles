import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"
import "LayoutModel.js" as LM
import "Look.js" as Look

// Add Folder Tile (S06): one of the XDG folders or any path; the tile opens a
// panel with the files inside.
VSheet {
  id: sheet
  property var launchpad: null
  readonly property var choices: {
    if (!launchpad) return []
    var x = launchpad.xdgDirs
    var order = [["DOWNLOAD", "Downloads"], ["DOCUMENTS", "Documents"], ["DESKTOP", "Desktop"], ["PICTURES", "Pictures"],
                 ["MUSIC", "Music"], ["VIDEOS", "Videos"]]
    var out = []
    for (var i = 0; i < order.length; i++) if (x[order[i][0]] && x[order[i][0]] !== launchpad.home) out.push({ name: order[i][1], path: x[order[i][0]] })
    out.push({ name: "Home", path: launchpad.home })
    return out
  }
  function add(path, name) {
    if (!launchpad || String(path).charAt(0) !== "/") return
    launchpad.commit(LM.addDir(launchpad.layout, path, name))
    sheet.dismissed()
  }
  onOpenChanged: if (open) { pathField.text = ""; Qt.callLater(pathField.focusField) }

  Keys.onEscapePressed: function(event) { sheet.dismissed(); event.accepted = true }

  Column {
    width: parent.width
    spacing: Theme.layout.sheet.gap

    VText { text: "Add Folder Tile"; font.weight: Font.DemiBold; font.pixelSize: Theme.m.type.title }
    VText { width: parent.width; tone: "secondary"; wrapMode: Text.WordWrap; elide: Text.ElideNone
      text: "A tile on the last page that shows the files inside." }

    VGroup {
      width: parent.width
      Repeater {
        model: sheet.choices
        VListRow {
          required property var modelData
          text: modelData.name
          clickable: true
          onClicked: sheet.add(modelData.path, modelData.name)
          VText { tone: "secondary"; text: sheet.launchpad ? sheet.launchpad.prettyPath(modelData.path) : "" }
        }
      }
    }

    VGroup {
      width: parent.width
      VListRow {
        text: "Other"
        VField {
          id: pathField
          width: Look.info.field
          placeholder: "/path/to/folder"
          onAccepted: sheet.add(pathField.text.trim().replace(/^~/, sheet.launchpad.home), "")
        }
      }
    }

    Row {
      anchors.right: parent.right
      spacing: Theme.layout.control.gap
      VButton { text: "Cancel"; onClicked: sheet.dismissed() }
      VButton { text: "Add"; kind: "primary"; enabled: pathField.text.trim() !== ""
        onClicked: sheet.add(pathField.text.trim().replace(/^~/, sheet.launchpad.home), "") }
    }
  }
}
