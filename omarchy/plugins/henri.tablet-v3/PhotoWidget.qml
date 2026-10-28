import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "file:///home/henri/.local/share/velum/qml/Velum"

// The Photos widget of the home screen (iPadOS): one photo at a time, full bleed with the icons'
// corner radius, its place and date over a soft shade at the bottom; another one fades in every
// `rotateEvery` (the same one on every screen: it is picked by the clock, from midnight on). The photos come from
// bin/velum-photo-picks (~/.cache/velum/photo-widget/picks.json + copies without metadata).
Item {
  id: pw
  property var cfg               // surface.tablet.home.widget
  property real radius: 0
  readonly property string dir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/velum/photo-widget"
  property var photos: []
  property string made: ""
  property int shownAt: -1
  property bool frontB: false    // which of the two images is in front
  readonly property var current: shownAt >= 0 && shownAt < photos.length ? photos[shownAt] : null

  // the tool swaps the whole directory in, so a file watch would hang on to the old one (or wait
  // for a file that was not there yet): read it again with every tick instead (a small file)
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
      pw.shownAt = -1
      pw.pick()
    }
    onLoadFailed: pw.photos = []
  }
  function pick() {
    if (!photos.length) return
    // counted from midnight: the day starts with the picks' first ones ("on this day")
    var now = new Date(), midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    var i = Math.floor((now - midnight) / cfg.rotateEvery) % photos.length
    if (i === shownAt) return
    shownAt = i
    var url = "file://" + dir + "/" + photos[i].file + "#" + made   // a new pick set is a new URL
    if (frontB) a.source = url; else b.source = url
  }
  Timer { interval: pw.cfg.tick; repeat: true; running: true; onTriggered: { picks.reload(); pw.pick() } }

  Item {
    id: body
    anchors.fill: parent
    layer.enabled: true
    layer.effect: MultiEffect { maskEnabled: true; maskSource: mask; maskThresholdMin: 0.5; maskSpreadAtMin: 1 }
    Rectangle { anchors.fill: parent; color: pw.cfg.empty }
    // two images: the new one loads behind, then fades in over the old
    Image {
      id: a
      anchors.fill: parent
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      opacity: !pw.frontB ? 1 : 0
      onStatusChanged: if (status === Image.Ready && pw.frontB) pw.frontB = false
      Behavior on opacity { NumberAnimation { duration: pw.cfg.fade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") } }
    }
    Image {
      id: b
      anchors.fill: parent
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      sourceSize.width: width * 2
      sourceSize.height: height * 2
      opacity: pw.frontB ? 1 : 0
      onStatusChanged: if (status === Image.Ready && !pw.frontB) pw.frontB = true
      Behavior on opacity { NumberAnimation { duration: pw.cfg.fade; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("inOut") } }
    }
    // the caption's shade
    Rectangle {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: parent.height * pw.cfg.shadeShare
      visible: pw.current !== null
      gradient: Gradient {
        GradientStop { position: 0; color: pw.cfg.shadeTop }
        GradientStop { position: 1; color: pw.cfg.shade }
      }
    }
  }
  Item {
    id: mask
    anchors.fill: parent
    layer.enabled: true
    visible: false
    Rectangle { anchors.fill: parent; radius: pw.radius; color: pw.cfg.maskInk }
  }
  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: pw.cfg.captionPad
    visible: pw.current !== null
    // the place over the date, or the date alone
    readonly property string when: pw.current ? Qt.locale("en_US").toString(new Date(pw.current.date + "T12:00:00"), "MMM d, yyyy") : ""
    VText {
      width: parent.width
      text: pw.current && pw.current.place ? pw.current.place : parent.when
      elide: Text.ElideRight
      font.pixelSize: Theme.m.type.body
      font.weight: Font.DemiBold
      color: pw.cfg.ink
    }
    VText {
      width: parent.width
      visible: !!(pw.current && pw.current.place)
      text: parent.when
      elide: Text.ElideRight
      font.pixelSize: Theme.m.type.small
      color: pw.cfg.inkSoft
    }
  }
  // nothing to show yet (or no photos on this machine)
  Column {
    anchors.centerIn: parent
    spacing: pw.cfg.captionPad / 2
    visible: pw.photos.length === 0
    VIcon { anchors.horizontalCenter: parent.horizontalCenter; name: "image"; weight: "fill"; size: pw.cfg.emptyIcon; color: pw.cfg.inkSoft }
    VText { anchors.horizontalCenter: parent.horizontalCenter; text: "No Photos"; font.pixelSize: Theme.m.type.small; color: pw.cfg.inkSoft }
  }
}
