import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"
import "LayoutModel.js" as LM
import "Look.js" as Look

// Get Info (S05, S09): an app's title, whether it shows, its icon; a folder's
// name, colour and emoji. Edits apply on Done, Cancel or Esc drops them.
VSheet {
  id: sheet
  property var launchpad: null
  property string itemId: ""
  open: itemId !== ""
  readonly property bool isFolder: LM.isFolder(itemId)
  readonly property var lp: Theme.core.surface.launchpad
  readonly property var folder: isFolder && launchpad ? (launchpad.layout.folders[LM.folderKey(itemId)] || null) : null
  readonly property var override: !isFolder && launchpad && itemId !== "" ? (launchpad.layout.apps[itemId] || {}) : ({})
  readonly property var entry: !isFolder && launchpad ? (launchpad.entries[itemId] || null) : null

  // the edit, filled when the sheet opens
  property string color: ""
  property bool showTitle: true

  onItemIdChanged: {
    if (itemId === "") return
    if (isFolder && folder) {
      nameField.text = folder.name
      emojiField.text = folder.emoji || ""
      sheet.color = folder.color || ""
    } else {
      nameField.text = override.name || ""
      iconField.text = override.icon || ""
      sheet.showTitle = !override.hideTitle
    }
    Qt.callLater(nameField.focusField)
  }

  function apply() {
    if (!launchpad || itemId === "") return
    if (isFolder) launchpad.commit(LM.styleFolder(launchpad.layout, itemId, { name: nameField.text, color: sheet.color || null, emoji: emojiField.text.trim() || null }))
    else launchpad.commit(LM.setOverride(launchpad.layout, itemId, { name: nameField.text.trim(), icon: iconField.text.trim(), hideTitle: !sheet.showTitle }))
    sheet.dismissed()
  }

  function swatchCenter(n) {
    var it = swatches.itemAt(n)
    return it ? it.mapToItem(sheet, it.width / 2, it.height / 2) : null
  }

  // Tab / Shift+Tab walk the sheet's fields (TextInput hands Tab on unhandled)
  function fields() { return sheet.isFolder ? [nameField, emojiField] : [nameField, iconField] }
  function cycle(d) {
    var f = fields()
    var at = 0
    for (var i = 0; i < f.length; i++) if (f[i].editing) at = i
    f[(at + d + f.length) % f.length].focusField()
  }
  Keys.onTabPressed: function(event) { cycle(1); event.accepted = true }
  Keys.onBacktabPressed: function(event) { cycle(-1); event.accepted = true }

  Keys.onEscapePressed: function(event) { sheet.dismissed(); event.accepted = true }

  Column {
    width: parent.width
    spacing: Theme.layout.sheet.gap

    Row {
      spacing: Theme.layout.sheet.gap
      Image {
        visible: !sheet.isFolder
        width: Look.info.icon; height: Look.info.icon
        sourceSize.width: Look.info.icon * 2; sourceSize.height: Look.info.icon * 2
        source: !sheet.isFolder && sheet.launchpad && sheet.itemId ? sheet.launchpad.iconFor(sheet.itemId) : ""
        fillMode: Image.PreserveAspectFit; mipmap: true
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        VText { text: "Get Info"; font.weight: Font.DemiBold; font.pixelSize: Theme.m.type.title }
        VText {
          tone: "secondary"
          text: sheet.isFolder ? (sheet.folder ? sheet.folder.items.length + (sheet.folder.items.length === 1 ? " app" : " apps") : "")
                : (sheet.entry ? sheet.entry.name + " · " + sheet.entry.desktopId : "")
        }
      }
    }

    VGroup {
      width: parent.width
      VListRow {
        text: "Name"
        VField {
          id: nameField
          width: Look.info.field
          placeholder: sheet.isFolder ? "Folder" : (sheet.entry ? sheet.entry.name : "")
          onAccepted: sheet.apply()
        }
      }
      VListRow {
        visible: !sheet.isFolder
        text: "Show title"
        VSwitch { checked: sheet.showTitle; onToggled: function(c) { sheet.showTitle = c } }
      }
      VListRow {
        visible: !sheet.isFolder
        text: "Icon"
        VField {
          id: iconField
          width: Look.info.field
          placeholder: "Icon name or file"
          onAccepted: sheet.apply()
        }
      }
      VListRow {
        visible: sheet.isFolder
        text: "Colour"
        Row {
          spacing: Theme.layout.control.gap
          // "none" first, then the palette
          Repeater {
            id: swatches
            model: [""].concat(Object.keys(sheet.lp.folderPalette))
            Rectangle {
              required property var modelData
              readonly property string hex: modelData === "" ? "" : String(sheet.lp.folderPalette[modelData])
              readonly property bool chosen: sheet.color.toLowerCase() === hexRgb(hex)
              function hexRgb(h) { return h === "" ? "" : "#" + h.slice(-6).toLowerCase() }
              width: Look.info.swatch; height: Look.info.swatch; radius: width / 2
              color: hex === "" ? sheet.lp.folderTile : hex
              border.width: chosen ? Look.info.swatchRing : 0
              border.color: Theme.ink("window", "primary")
              VIcon { anchors.centerIn: parent; visible: modelData === ""; name: "close"; weight: "bold"; size: Look.info.swatch / 2; color: Theme.ink("window", "secondary") }
              MouseArea { anchors.fill: parent; onClicked: sheet.color = parent.hexRgb(parent.hex) }
              Accessible.role: Accessible.RadioButton
              Accessible.name: modelData === "" ? "No colour" : modelData
            }
          }
        }
      }
      VListRow {
        visible: sheet.isFolder
        text: "Emoji"
        VField {
          id: emojiField
          width: Look.info.emojiField
          placeholder: "None"
          onAccepted: sheet.apply()
        }
      }
    }

    Row {
      anchors.right: parent.right
      spacing: Theme.layout.control.gap
      VButton {
        visible: !sheet.isFolder
        text: "Reset"
        onClicked: { nameField.text = ""; iconField.text = ""; sheet.showTitle = true }
      }
      VButton { text: "Cancel"; onClicked: sheet.dismissed() }
      VButton { text: "Done"; kind: "primary"; onClicked: sheet.apply() }
    }
  }
}
