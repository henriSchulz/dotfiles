import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"
import "LayoutModel.js" as LM
import "Look.js" as Look

// Settings (S07, S08, S11): grid, icons, titles, search position, background,
// hidden apps. Changes apply live and are saved with the layout.
VSheet {
  id: sheet
  property var launchpad: null
  readonly property var s: launchpad ? launchpad.settings : LM.DEFAULT_SETTINGS
  function set(patch) { launchpad.commit(LM.setSettings(launchpad.layout, patch)) }

  Column {
    width: parent.width
    spacing: Theme.layout.sheet.gap

    VText { text: "Launchpad"; font.weight: Font.DemiBold; font.pixelSize: Theme.m.type.title }

    VGroup {
      width: parent.width
      VListRow {
        text: "Columns"; detail: String(sheet.s.columns)
        VSlider { width: Look.settings.sliderWidth; from: LM.LIMITS.columns[0]; to: LM.LIMITS.columns[1]; value: sheet.s.columns
          onMoved: function(v) { if (Math.round(v) !== sheet.s.columns) sheet.set({ columns: Math.round(v) }) } }
      }
      VListRow {
        text: "Rows"; detail: String(sheet.s.rows)
        VSlider { width: Look.settings.sliderWidth; from: LM.LIMITS.rows[0]; to: LM.LIMITS.rows[1]; value: sheet.s.rows
          onMoved: function(v) { if (Math.round(v) !== sheet.s.rows) sheet.set({ rows: Math.round(v) }) } }
      }
      VListRow {
        text: "Icon size"
        VSlider { width: Look.settings.sliderWidth; from: LM.LIMITS.iconSize[0]; to: LM.LIMITS.iconSize[1]; value: sheet.s.iconSize
          onMoved: function(v) { if (Math.round(v) !== sheet.s.iconSize) sheet.set({ iconSize: Math.round(v) }) } }
      }
      VListRow {
        text: "Folder columns"
        VSegment { model: ["3", "4", "5"]; currentIndex: sheet.s.folderGrid[0] - 3
          onActivated: function(i) { sheet.set({ folderGrid: [i + 3, sheet.s.folderGrid[1]] }) } }
      }
      VListRow {
        text: "Folder rows"; detail: String(sheet.s.folderGrid[1])
        VSlider { width: Look.settings.sliderWidth; from: 3; to: 8; value: sheet.s.folderGrid[1]
          onMoved: function(v) { if (Math.round(v) !== sheet.s.folderGrid[1]) sheet.set({ folderGrid: [sheet.s.folderGrid[0], Math.round(v)] }) } }
      }
      VListRow {
        text: "Show titles"
        VSwitch { checked: sheet.s.showTitles; onToggled: function(c) { sheet.set({ showTitles: c }) } }
      }
      VListRow {
        text: "Categories page"
        VSwitch { checked: sheet.s.categoriesPage; onToggled: function(c) { sheet.set({ categoriesPage: c }) } }
      }
      VListRow {
        text: "Search field"
        VSegment { model: ["Top", "Centre"]; currentIndex: sheet.s.searchPosition === "center" ? 1 : 0
          onActivated: function(i) { sheet.set({ searchPosition: i === 1 ? "center" : "top" }) } }
      }
    }

    VGroup {
      width: parent.width
      VListRow {
        text: "Background"
        VSegment { model: ["Desktop", "Image", "Solid"]; currentIndex: sheet.s.wallpaper.kind === "solid" ? 2 : (sheet.s.wallpaper.kind === "image" ? 1 : 0)
          onActivated: function(i) { sheet.set({ wallpaper: { kind: ["desktop", "image", "solid"][i] } }) } }
      }
      VListRow {
        visible: sheet.s.wallpaper.kind === "image"
        text: "Image file"
        VField {
          id: imageField
          width: Look.info.field
          placeholder: "~/Pictures/background.jpg"
          text: sheet.s.wallpaper.path || ""
          onAccepted: sheet.set({ wallpaper: { kind: "image", path: imageField.text.trim().replace(/^~/, sheet.launchpad.home) || null } })
        }
      }
      VListRow {
        text: "Blur"
        VSlider { width: Look.settings.sliderWidth; from: 0; to: 100; value: sheet.s.wallpaper.blur
          onMoved: function(v) { sheet.set({ wallpaper: { blur: Math.round(v) } }) } }
      }
    }

    VGroup {
      width: parent.width
      VListRow { text: "Open"; detail: "F4 · pinch with three fingers" }
    }

    VSectionHeader { text: "Hidden Apps" }
    VGroup {
      width: parent.width
      VListRow {
        visible: !sheet.launchpad || sheet.launchpad.layout.hidden.length === 0
        text: "No hidden apps"; ink: Theme.ink("window", "secondary")
      }
      Repeater {
        model: sheet.launchpad ? sheet.launchpad.layout.hidden.slice(0, Look.settings.hiddenMaxRows * 4) : []
        VListRow {
          required property var modelData
          text: sheet.launchpad.titleFor(modelData)
          VButton { text: "Show"; onClicked: sheet.launchpad.commit(LM.unhide(sheet.launchpad.layout, modelData)) }
        }
      }
    }

    Row {
      anchors.right: parent.right
      spacing: Theme.layout.control.gap
      VButton { text: "Sort by Name"; onClicked: sheet.launchpad.commit(LM.reset(sheet.launchpad.layout, sheet.launchpad.desktopIds)) }
      VButton { text: "Done"; kind: "primary"; onClicked: sheet.dismissed() }
    }
  }
}
