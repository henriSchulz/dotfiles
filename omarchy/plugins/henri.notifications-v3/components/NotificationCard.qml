// Notification banner on Velum (v3): the variant's popover material
// (VFloatingCard), geometry from Theme.core.surface.notifications (after the
// measured Tahoe banner), Velum motion. The Notification Center draws the same
// card. Pure presentational — no service, Notification, or ListModel
// references; the popup container drives lifetime and actions.

import QtQuick
import Quickshell
import qs.Commons
import "file:///home/henri/.local/share/velum/qml/Velum"
import "../NotificationLogic.js" as NotificationLogic

Item {
  id: root

  property string app: ""
  property string appIcon: ""
  property string summary: ""
  property string body: ""
  property string image: ""
  // Nerd Font glyph rendered in the icon slot when no real icon is set
  // (omarchy-notification-send -g).
  property string glyph: ""
  // NotificationUrgency: Low=0, Normal=1, Critical=2 (upstream).
  property int urgency: 1
  property double timestamp: 0
  // Kept for API compatibility with the stock card; the banner draws with
  // Velum's panel radius and font instead.
  property int cornerRadius: 0
  property string fontFamily: ""
  // Kept for API compatibility: light or dark follows Theme.dark.
  property bool dark: Theme.dark
  // [{ id, text }]: the sender's libnotify actions besides "default". They
  // sit behind the "Options ⌄" capsule, like a macOS banner with actions.
  property var actions: []

  readonly property var bn: Theme.core.surface.notifications
  // Forces the hover state (close circle, Options capsule) — for previews and
  // the headless probe, where no pointer ever arrives.
  property bool showControls: false
  readonly property bool hovered: showControls || hover.hovered || closeButton.hovered || optionsButton.hovered || menu.open
  readonly property bool menuOpen: menu.open
  // bumped by the container on a click outside: an open actions menu closes
  property int closeMenusTick: 0
  onCloseMenusTickChanged: menu.open = false

  signal closeRequested()
  signal cardClicked()
  signal actionRequested(string identifier)

  function pt(v) { return v }

  function iconUrl(icon) {
    var value = String(icon || "")
    if (value.length === 0) return ""
    // A themed icon name that Quickshell already wrapped (an app_icon lands in
    // the image role as image://icon/<name>): the icon provider answers even
    // for a missing name — with Qt's magenta placeholder, status Ready — so
    // the existence check has to happen here. Missing → the symbol tile.
    if (value.indexOf("image://icon/") === 0) return Quickshell.iconPath(value.slice("image://icon/".length), true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  readonly property string sanitizedBody: NotificationLogic.sanitizeBody(body, app, appIcon)
  readonly property string styledBody: NotificationLogic.styledBody(body, app, appIcon)
  readonly property bool critical: urgency === 2
  readonly property bool hasActions: !!actions && actions.length > 0
  readonly property string iconSource: iconUrl(appIcon)
  readonly property string imageSource: image.length > 0 ? iconUrl(image) : ""
  // Omarchy's own toasts put a Nerd glyph plus two spaces in front of the
  // summary; that glyph becomes the icon and leaves the title clean.
  readonly property bool summaryStartsWithGlyph: glyph.length === 0 && NotificationLogic.summaryStartsWithGlyph(summary)
  readonly property string effectiveGlyph: glyph.length > 0 ? glyph
    : (summaryStartsWithGlyph ? String.fromCodePoint(summary.replace(/^\s+/, "").codePointAt(0)) : "")
  readonly property string titleText: summaryStartsWithGlyph
    ? summary.replace(/^\s+/, "").slice(String.fromCodePoint(summary.replace(/^\s+/, "").codePointAt(0)).length).replace(/^\s+/, "")
    : summary

  implicitWidth: bn.bannerWidth
  implicitHeight: Math.max(bn.minHeight, textColumn.implicitHeight + bn.padding * 2)

  VFloatingCard {
    id: face
    anchors.fill: parent
    scale: press.pressed ? Theme.scale("press") : 1
    Behavior on scale { NumberAnimation { duration: press.pressed ? Theme.dur("instant") : Theme.dur("base"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }

    HoverHandler { id: hover }
    TapHandler {
      id: press
      acceptedButtons: Qt.LeftButton
      onTapped: root.cardClicked()
    }
    TapHandler {
      acceptedButtons: Qt.RightButton
      onTapped: root.closeRequested()
    }

    // App symbol, vertically centred. A notification picture (avatar, media,
    // or the app icon a client sent as image data) takes the same slot; a
    // themed app icon beside it becomes a small badge.
    Item {
      id: iconBox
      x: root.bn.padding
      anchors.verticalCenter: parent.verticalCenter
      width: root.bn.icon
      height: width

      Rectangle {
        anchors.fill: parent
        radius: width * root.bn.iconRadius
        gradient: Gradient { GradientStop { position: 0; color: Theme.r.accent.top } GradientStop { position: 1; color: Theme.r.accent.base } }
        visible: !picture.visible
        Text {
          visible: root.effectiveGlyph !== ""
          anchors.centerIn: parent
          text: root.effectiveGlyph
          font.family: Style.font.family
          font.pixelSize: Theme.layout.icon.large
          color: Theme.r.ink.onAccent
        }
        VIcon {
          visible: root.effectiveGlyph === ""
          anchors.centerIn: parent
          name: "notification"
          weight: "fill"
          size: Theme.layout.icon.large
          color: Theme.r.ink.onAccent
        }
      }
      Image {
        id: picture
        anchors.fill: parent
        source: root.imageSource !== "" ? root.imageSource : root.iconSource
        visible: status === Image.Ready
        fillMode: root.imageSource !== "" ? Image.PreserveAspectCrop : Image.PreserveAspectFit
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
        asynchronous: true
        smooth: true
      }
      Image {
        id: badge
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -Theme.layout.separator * 2
        anchors.bottomMargin: -Theme.layout.separator * 2
        width: root.bn.badge
        height: width
        source: root.imageSource !== "" ? root.iconSource : ""
        visible: root.imageSource !== "" && picture.visible && status === Image.Ready
        fillMode: Image.PreserveAspectFit
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
        asynchronous: true
        smooth: true
      }
    }

    Column {
      id: textColumn
      x: root.bn.padding + root.bn.icon + root.bn.iconGap
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x - root.bn.padding - (root.hasActions ? optionsButton.width + Theme.layout.list.gap : 0)
      spacing: 0

      // "TIME SENSITIVE": what macOS puts over a notification that must not
      // wait — the counterpart of urgency=critical, which never expires here.
      VText {
        width: parent.width
        visible: root.critical
        text: "TIME SENSITIVE"
        font.pixelSize: Theme.m.type.small
        font.weight: Font.DemiBold
        lineHeight: root.bn.lineHeight
        lineHeightMode: Text.FixedHeight
        color: Theme.r.popover.inkSecondary
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
      VText {
        // The spec defines the summary as a single line of plain text, so
        // AutoText could only ever promote a hostile string to rich text.
        width: parent.width
        visible: text.length > 0
        text: root.titleText.length > 0 ? root.titleText : root.app
        font.weight: Font.DemiBold
        lineHeight: root.bn.lineHeight
        lineHeightMode: Text.FixedHeight
        color: Theme.r.popover.ink
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: 2
        textFormat: Text.PlainText
      }
      VText {
        // StyledText on purpose (Service.qml advertises body-markup); image
        // tags are stripped in NotificationLogic before the renderer sees them.
        width: parent.width
        visible: root.sanitizedBody.length > 0
        text: root.styledBody
        textFormat: Text.StyledText
        lineHeight: root.bn.lineHeight
        lineHeightMode: Text.FixedHeight
        color: Theme.r.popover.ink
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: root.bn.bodyLines
      }
    }

    // "Options ⌄" — only when the sender registered actions; appears on hover.
    VCapsule {
      id: optionsButton
      anchors.right: parent.right
      anchors.rightMargin: root.bn.padding - Theme.layout.module.tileInset / 2
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Theme.layout.list.gap - Theme.layout.separator * 2
      label: "Options"
      opacity: root.hasActions && root.hovered ? 1 : 0
      visible: root.hasActions && opacity > 0.01
      Behavior on opacity { NumberAnimation { duration: Theme.dur("fast"); easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.curve("out") } }
      onClicked: menu.open = !menu.open
    }
  }

  // Close circle overlapping the top-left corner, like the Notification Center card.
  VCornerButton {
    id: closeButton
    x: root.bn.closeCenterX - root.bn.closeButton / 2
    y: root.bn.closeCenterY - height / 2
    shown: root.hovered
    onClicked: root.closeRequested()
  }

  // The actions menu under the capsule: Velum's menu, opens with no transition.
  VMenu {
    id: menu
    anchors.right: parent.right
    anchors.rightMargin: root.bn.padding - Theme.layout.module.tileInset / 2
    anchors.top: parent.bottom
    anchors.topMargin: Theme.layout.module.tileInset
    model: root.hasActions ? root.actions.map(function(a) { return { text: a.text, id: a.id } }) : []
    onTriggered: function(index) {
      menu.open = false
      root.actionRequested(String(root.actions[index].id))
    }
  }
}
