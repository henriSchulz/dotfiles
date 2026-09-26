import QtQuick
import Quickshell
import Quickshell.Io
import "Apple.js" as Apple

// Helligkeit des Wallpapers unter einer Fläche (Standard: oben rechts, wo ein
// Bar-Popup hängt). Einmal beim Start und bei jedem Wallpaper-Wechsel gemessen
// (inotify auf ~/.local/state/omarchy/current), nie beim Öffnen — ein Fork in
// den ersten Frames kostet Bildrate (henri-ui §5).
//
//   AUi.Backdrop { id: backdrop }          → backdrop.dark, backdrop.luma
//   omarchy-shell <plugin> …               → set(v) / remeasure() zum Testen
Item {
  id: root
  property real luma: 1.0
  property real threshold: Apple.darkBelowLuma
  readonly property bool dark: luma < threshold
  // ImageMagick-Geometrie der gemessenen Region und ihr Anker.
  property string region: "22%x75%+0+0"
  property string gravity: "NorthEast"
  readonly property string omarchyCurrent: Quickshell.env("HOME") + "/.local/state/omarchy/current"
  property bool _pending: false

  function set(v) { root.luma = v }
  function remeasure() {
    if (lumaProc.running) _pending = true
    else lumaProc.running = true
  }

  Process {
    id: lumaProc
    command: ["magick", root.omarchyCurrent + "/background",
              "-gravity", root.gravity, "-crop", root.region, "+repage",
              "-scale", "1x1!", "-colorspace", "Gray", "-format", "%[fx:mean]", "info:"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var v = parseFloat(String(text || "").trim())
        if (isFinite(v)) root.luma = v
      }
    }
    onExited: if (root._pending) { root._pending = false; lumaProc.running = true }
  }

  Process {
    id: bgWatch
    command: ["inotifywait", "-m", "-q", "-e", "create,moved_to,delete,attrib", "--format", "%f", root.omarchyCurrent]
    stdout: SplitParser {
      onRead: function(line) { if (String(line).trim() === "background") root.remeasure() }
    }
  }

  Component.onCompleted: { lumaProc.running = true; bgWatch.running = true }
}
