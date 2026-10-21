import QtQuick
import Quickshell.Io
import "file:///home/henri/.local/share/velum/qml/Velum"
import "Look.js" as Look

// Choose an image (app icon, folder cover, background): thumbnails of the
// pictures in ~/Pictures and ~/Downloads, or any path. Emits picked(path).
VSheet {
  id: sheet
  property var launchpad: null
  property string title: "Choose Image"
  property bool video: false           // list videos instead (background video)
  signal picked(string path)
  property var found: []

  onOpenChanged: if (open) { pathField.text = ""; sheet.scan() }

  function scan() {
    if (!launchpad) return
    var x = launchpad.xdgDirs
    var roots = [x.PICTURES || (launchpad.home + "/Pictures"), x.DOWNLOAD || (launchpad.home + "/Downloads")]
    var exts = sheet.video ? ["mp4", "mov", "mkv", "webm", "avi"] : ["png", "jpg", "jpeg", "webp", "svg", "gif"]
    var cmd = ["fd", "--max-results", String(Look.picker.maxResults), "--color", "never", "--absolute-path", "--type", "f"]
    for (var i = 0; i < exts.length; i++) cmd.push("-e", exts[i])
    cmd.push(".")
    for (var r = 0; r < roots.length; r++) cmd.push(roots[r])
    proc.running = false
    proc.command = cmd
    proc.running = true
  }
  Process {
    id: proc
    stdout: StdioCollector {
      onStreamFinished: sheet.found = String(text || "").split("\n").filter(function(l) { return l.charAt(0) === "/" }).sort()
    }
  }
  function choose(path) {
    var p = String(path || "").trim().replace(/^~/, launchpad ? launchpad.home : "")
    if (p.charAt(0) !== "/") return
    sheet.picked(p)
    sheet.dismissed()
  }

  Keys.onEscapePressed: function(event) { sheet.dismissed(); event.accepted = true }

  Column {
    width: parent.width
    spacing: Theme.layout.sheet.gap

    VText { text: sheet.title; font.weight: Font.DemiBold; font.pixelSize: Theme.m.type.title }

    Flickable {
      id: flick
      width: parent.width
      height: Math.min(Look.picker.maxHeight, grid.height)
      contentHeight: grid.height
      clip: true
      visible: sheet.found.length > 0
      Flow {
        id: grid
        width: flick.width
        spacing: Theme.layout.control.gap
        Repeater {
          model: sheet.found
          Item {
            required property var modelData
            width: (grid.width - (Look.picker.columns - 1) * grid.spacing) / Look.picker.columns
            height: width
            Accessible.role: Accessible.Button
            Accessible.name: String(modelData).slice(String(modelData).lastIndexOf("/") + 1)
            Rectangle {
              anchors.fill: parent
              radius: Theme.m.radius.control
              color: Theme.r.fill.field
              clip: true
              Image {
                anchors.fill: parent
                visible: !sheet.video
                source: sheet.video ? "" : "file://" + modelData
                sourceSize.width: Look.picker.thumb * 2; sourceSize.height: Look.picker.thumb * 2
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }
              VIcon { anchors.centerIn: parent; visible: sheet.video; name: "film"; size: Theme.layout.icon.large }
              VText {
                visible: sheet.video
                anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 2 * Theme.layout.row.padX
                horizontalAlignment: Text.AlignHCenter
                tone: "secondary"; font.pixelSize: Theme.core.type.caption
                text: String(modelData).slice(String(modelData).lastIndexOf("/") + 1)
              }
            }
            MouseArea { anchors.fill: parent; onClicked: sheet.choose(modelData) }
          }
        }
      }
    }
    VText {
      visible: sheet.found.length === 0
      tone: "secondary"
      text: sheet.video ? "No videos in Pictures or Downloads." : "No pictures in Pictures or Downloads."
    }

    VGroup {
      width: parent.width
      VListRow {
        text: "File"
        VField {
          id: pathField
          width: Look.info.field
          placeholder: sheet.video ? "~/Videos/loop.mp4" : "~/Pictures/image.png"
          onAccepted: sheet.choose(pathField.text)
        }
      }
    }

    Row {
      anchors.right: parent.right
      spacing: Theme.layout.control.gap
      VButton { text: "Cancel"; onClicked: sheet.dismissed() }
      VButton { text: "Choose"; kind: "primary"; enabled: pathField.text.trim() !== ""; onClicked: sheet.choose(pathField.text) }
    }
  }
}
