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
  readonly property bool isWorkflow: LM.isWorkflow(itemId)
  readonly property var workflow: isWorkflow && launchpad ? ((launchpad.layout.workflows || {})[LM.workflowKey(itemId)] || null) : null
  property var steps: []                // the workflow's items while editing
  property string cover: ""
  readonly property var lp: Theme.core.surface.launchpad
  readonly property var folder: isFolder && launchpad ? (launchpad.layout.folders[LM.folderKey(itemId)] || null) : null
  readonly property bool isApp: LM.isApp(itemId)
  readonly property var override: isApp && launchpad ? (launchpad.layout.apps[itemId] || {}) : ({})
  readonly property var entry: isApp && launchpad ? (launchpad.entries[itemId] || null) : null
  function setIcon(path) { iconField.text = path }
  function setCover(path) { sheet.cover = path }

  // the edit, filled when the sheet opens
  property string color: ""
  property bool showTitle: true

  // the derived properties (isFolder, workflow …) update after this handler, so fill a tick later
  onItemIdChanged: Qt.callLater(sheet.fill)
  function fill() {
    if (itemId === "") return
    if (isFolder && folder) {
      nameField.text = folder.name
      emojiField.text = folder.emoji || ""
      sheet.color = folder.color || ""
      sheet.cover = folder.cover || ""
    } else if (isWorkflow && workflow) {
      nameField.text = workflow.name
      sheet.steps = workflow.items.slice()
    } else {
      nameField.text = override.name || ""
      iconField.text = override.icon || ""
      sheet.showTitle = !override.hideTitle
    }
    nameField.focusField()
  }

  function apply() {
    if (!launchpad || itemId === "") return
    if (isFolder) launchpad.commit(LM.styleFolder(launchpad.layout, itemId, { name: nameField.text, color: sheet.color || null, emoji: emojiField.text.trim() || null, cover: sheet.cover || null }))
    else if (isWorkflow) launchpad.commit(sheet.steps.length > 0 ? LM.editWorkflow(launchpad.layout, itemId, { name: nameField.text, items: sheet.steps }) : LM.removeWorkflow(launchpad.layout, itemId))
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
        visible: sheet.isApp
        width: Look.info.icon; height: Look.info.icon
        sourceSize.width: Look.info.icon * 2; sourceSize.height: Look.info.icon * 2
        source: sheet.isApp && sheet.launchpad && sheet.itemId ? sheet.launchpad.iconFor(sheet.itemId) : ""
        fillMode: Image.PreserveAspectFit; mipmap: true
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        VText { text: "Get Info"; font.weight: Font.DemiBold; font.pixelSize: Theme.m.type.title }
        VText {
          tone: "secondary"
          text: sheet.isFolder ? (sheet.folder ? sheet.folder.items.length + (sheet.folder.items.length === 1 ? " app" : " apps") : "")
                : sheet.isWorkflow ? "Workflow · starts everything below in one click"
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
          placeholder: sheet.isFolder ? "Folder" : sheet.isWorkflow ? "Workflow" : (sheet.entry ? sheet.entry.name : "")
          onAccepted: sheet.apply()
        }
      }
      VListRow {
        visible: sheet.isApp
        text: "Show title"
        VSwitch { checked: sheet.showTitle; onToggled: function(c) { sheet.showTitle = c } }
      }
      VListRow {
        visible: sheet.isApp
        text: "Icon"
        Row {
          spacing: Theme.layout.control.gap
          VField {
            id: iconField
            width: Look.info.field - Look.info.chooseButton - Theme.layout.control.gap
            placeholder: "Icon name or file"
            onAccepted: sheet.apply()
          }
          VButton { text: "Choose…"; onClicked: sheet.launchpad.choosePicture("icon") }
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
        text: "Cover"; detail: sheet.cover ? sheet.cover.slice(sheet.cover.lastIndexOf("/") + 1) : "None"
        Row {
          spacing: Theme.layout.control.gap
          VButton { visible: sheet.cover !== ""; text: "None"; onClicked: sheet.cover = "" }
          VButton { text: "Choose…"; onClicked: sheet.launchpad.choosePicture("cover") }
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

    // a workflow's steps, in order
    VGroup {
      visible: sheet.isWorkflow
      width: parent.width
      VListRow { visible: sheet.steps.length === 0; text: "No steps — Done removes the workflow"; ink: Theme.ink("window", "secondary") }
      Repeater {
        model: sheet.isWorkflow ? sheet.steps : []
        VListRow {
          required property var modelData
          required property int index
          text: sheet.launchpad ? sheet.launchpad.titleFor(modelData) : ""
          VButton { text: "Remove"; onClicked: { var n = sheet.steps.slice(); n.splice(index, 1); sheet.steps = n } }
        }
      }
    }

    Row {
      anchors.right: parent.right
      spacing: Theme.layout.control.gap
      VButton {
        visible: sheet.isApp
        text: "Reset"
        onClicked: { nameField.text = ""; iconField.text = ""; sheet.showTitle = true }
      }
      VButton { text: "Cancel"; onClicked: sheet.dismissed() }
      VButton { text: "Done"; kind: "primary"; onClicked: sheet.apply() }
    }
  }
}
