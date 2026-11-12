import QtQuick
import Quickshell
import Quickshell.Io
import "file:///home/henri/.local/share/velum/qml/Velum"

// The Photos widget (lab Widgets.jsx Photos): one photo at a time, full bleed, its place and date over
// a shade at the bottom; the next pick fades in every photo.every. The photos come from
// bin/velum-photo-picks (~/.cache/velum/photo-widget/picks.json + copies without metadata); the file
// is read again every photo.reread (the tool swaps the whole directory in, so no file watch).
// Images load at the widget's size (sourceSize); two images crossfade (opacity only).
// API: width, height (from the home grid; 3 × 2 cells by default); current (read only) = the pick
// shown { file, id, date, place } or null.
WidgetCard {
  id: pw
  tone: "photo"
  readonly property var w: Theme.core.surface.material.widgets
  readonly property var pc: w.photo
  readonly property string family: w.font[0]
  readonly property string dir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/velum/photo-widget"
  property var photos: []
  property string made: ""
  property int at: 0
  property bool frontB: false
  readonly property var current: photos.length ? photos[at % photos.length] : null

  FileView {
    id: picks
    path: pw.dir + "/picks.json"
    printErrors: false
    onLoaded: {
      var d = {}
      try { d = JSON.parse(text()) } catch (e) {}
      if (String(d.made || "") === pw.made && pw.photos.length) return
      pw.photos = Array.isArray(d.photos) ? d.photos : []
      pw.made = String(d.made || "")
      pw.show()
    }
    onLoadFailed: pw.photos = []
  }
  Timer { interval: pw.pc.reread; repeat: true; running: pw.visible; onTriggered: picks.reload() }
  Timer { interval: pw.pc.every; repeat: true; running: pw.visible && pw.photos.length > 1; onTriggered: { pw.at = (pw.at + 1) % pw.photos.length; pw.show() } }

  // the next one loads behind, then fades in over the old
  function show() {
    if (!current) return
    var url = "file://" + dir + "/" + current.file + "#" + made
    if (frontB) a.source = url; else b.source = url
  }

  Image {
    id: a
    anchors.fill: parent
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    sourceSize.width: width
    sourceSize.height: height
    opacity: pw.frontB ? 0 : 1
    onStatusChanged: if (status === Image.Ready && pw.frontB) pw.frontB = false
    Behavior on opacity { NumberAnimation { duration: pw.pc.fade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") } }
  }
  Image {
    id: b
    anchors.fill: parent
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    sourceSize.width: width
    sourceSize.height: height
    opacity: pw.frontB ? 1 : 0
    onStatusChanged: if (status === Image.Ready && !pw.frontB) pw.frontB = true
    Behavior on opacity { NumberAnimation { duration: pw.pc.fade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") } }
  }
  Rectangle {
    anchors.fill: parent
    gradient: Gradient {
      GradientStop { position: pw.pc.shadeFrom; color: pw.pc.shadeTop }
      GradientStop { position: 1; color: pw.pc.shade }
    }
  }
  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: pw.pc.left
    anchors.rightMargin: pw.pc.left
    anchors.bottomMargin: pw.pc.bottom
    readonly property string when: pw.current && pw.current.date ? Qt.locale("en_GB").toString(new Date(pw.current.date + "T12:00:00"), "d MMMM yyyy") : ""
    Text {
      width: parent.width
      text: pw.current && pw.current.place ? pw.current.place : "Photos"
      elide: Text.ElideRight
      color: pw.pc.ink
      font.family: pw.family
      font.pixelSize: pw.w.type.subtitle
      font.weight: pw.w.weight.medium
    }
    Text {
      width: parent.width
      text: pw.current ? parent.when : "No photos yet"
      elide: Text.ElideRight
      color: pw.pc.ink
      opacity: pw.pc.inkSoft
      font.family: pw.family
      font.pixelSize: pw.w.type.caption
    }
  }
}
