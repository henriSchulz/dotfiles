// Notification banner in the macOS 26 Tahoe look. Geometry and material come
// from apple-ui (Apple.banner, measured on Apple's own support screenshot),
// motion from henri-ui. Pure presentational — no service, Notification, or
// ListModel references; the popup container drives lifetime and actions.

import QtQuick
import Quickshell
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "file:///home/henri/.local/share/apple-ui/Apple.js" as Apple
import "file:///home/henri/.local/share/apple-ui" as AUi
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
  // Apple.banner.radius and SF Pro instead.
  property int cornerRadius: 0
  property string fontFamily: ""
  // Light or dark glass, after the wallpaper under the banner column.
  property bool dark: false
  // [{ id, text }]: the sender's libnotify actions besides "default". They
  // sit behind the "Options ⌄" capsule, like a macOS banner with actions.
  property var actions: []

  readonly property var palette: Apple.bannerPalette(dark)
  readonly property var bn: Apple.banner
  // Forces the hover state (close circle, Options capsule) — for previews and
  // the headless probe, where no pointer ever arrives.
  property bool showControls: false
  readonly property bool hovered: showControls || hover.hovered || closeButton.hovered || optionsButton.hovered || menu.open
  readonly property bool menuOpen: menu.open

  signal closeRequested()
  signal cardClicked()
  signal actionRequested(string identifier)

  function pt(v) { return Style.space(v) }
  function sf(cp) { return String.fromCodePoint(cp) }

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

  implicitWidth: pt(bn.width)
  implicitHeight: Math.max(pt(bn.minHeight), textColumn.implicitHeight + pt(bn.padding) * 2)

  AUi.NcCard {
    id: face
    anchors.fill: parent
    palette: root.palette
    radius: root.pt(root.bn.radius)
    scale: press.pressed ? Motion.pressScale : 1
    Behavior on scale { NumberAnimation { duration: press.pressed ? Motion.instant : Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }

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
      x: root.pt(root.bn.padding)
      anchors.verticalCenter: parent.verticalCenter
      width: root.pt(root.bn.icon)
      height: width

      Rectangle {
        anchors.fill: parent
        radius: width * Apple.notificationCenter.iconRadius
        color: root.palette.capsule
        visible: !picture.visible
        Text {
          anchors.centerIn: parent
          text: root.effectiveGlyph !== "" ? root.effectiveGlyph : root.sf(0x1002DA)
          font.family: root.effectiveGlyph !== "" ? Style.font.family : Apple.symbolFont
          font.pixelSize: root.pt(16)
          color: root.palette.textPrimary
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
        anchors.rightMargin: -root.pt(2)
        anchors.bottomMargin: -root.pt(2)
        width: root.pt(root.bn.badge)
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
      x: root.pt(root.bn.padding) + root.pt(root.bn.icon) + root.pt(root.bn.iconGap)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - x - root.pt(root.bn.padding) - (root.hasActions ? root.pt(root.bn.capsuleReserve) : 0)
      spacing: 0

      // "TIME SENSITIVE": what macOS puts over a notification that must not
      // wait — the counterpart of urgency=critical, which never expires here.
      Text {
        width: parent.width
        visible: root.critical
        text: "TIME SENSITIVE"
        font.family: Apple.uiFont
        font.pixelSize: root.pt(root.bn.overlineFont)
        font.weight: Font.DemiBold
        font.letterSpacing: root.pt(0.6)
        lineHeight: root.pt(root.bn.lineHeight)
        lineHeightMode: Text.FixedHeight
        color: root.palette.textSecondary
        elide: Text.ElideRight
        textFormat: Text.PlainText
      }
      Text {
        // The spec defines the summary as a single line of plain text, so
        // AutoText could only ever promote a hostile string to rich text.
        width: parent.width
        visible: text.length > 0
        text: root.titleText.length > 0 ? root.titleText : root.app
        font.family: Apple.uiFont
        font.pixelSize: root.pt(root.bn.titleFont)
        font.weight: Font.DemiBold
        lineHeight: root.pt(root.bn.lineHeight)
        lineHeightMode: Text.FixedHeight
        color: root.palette.textPrimary
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: 2
        textFormat: Text.PlainText
      }
      Text {
        // StyledText on purpose (Service.qml advertises body-markup); image
        // tags are stripped in NotificationLogic before the renderer sees them.
        width: parent.width
        visible: root.sanitizedBody.length > 0
        text: root.styledBody
        textFormat: Text.StyledText
        font.family: Apple.uiFont
        font.pixelSize: root.pt(root.bn.bodyFont)
        lineHeight: root.pt(root.bn.lineHeight)
        lineHeightMode: Text.FixedHeight
        color: root.palette.textPrimary
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: root.bn.bodyLines
      }
    }

    // "Options ⌄" — only when the sender registered actions; appears on hover.
    HUi.Pressable {
      id: optionsButton
      anchors.right: parent.right
      anchors.rightMargin: root.pt(root.bn.capsuleRight)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: root.pt(root.bn.capsuleBottom)
      height: root.pt(root.bn.capsuleHeight)
      width: optionsRow.implicitWidth + root.pt(root.bn.capsulePadX) * 2
      radius: height / 2
      showFill: false
      tint: root.palette.textPrimary
      opacity: root.hasActions && root.hovered ? 1 : 0
      visible: root.hasActions && opacity > 0.01
      Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      Rectangle {
        anchors.fill: parent
        radius: optionsButton.radius
        color: optionsButton.hovered ? root.palette.capsuleHover : root.palette.capsule
        Behavior on color { ColorAnimation { duration: optionsButton.hovered ? Motion.instant : Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
      }
      Row {
        id: optionsRow
        anchors.centerIn: parent
        spacing: root.pt(5)
        Text { text: "Options"; font.family: Apple.uiFont; font.pixelSize: root.pt(root.bn.bodyFont); color: root.palette.textPrimary; anchors.verticalCenter: parent.verticalCenter }
        Text { text: root.sf(0x100188); font.family: Apple.symbolFont; font.pixelSize: root.pt(9); font.weight: Font.Bold; color: root.palette.textPrimary; anchors.verticalCenter: parent.verticalCenter }
      }
      onClicked: menu.open = !menu.open
    }
  }

  // Close circle overlapping the top-left corner, like the Notification Center card.
  AUi.NcCornerButton {
    id: closeButton
    palette: root.palette
    size: root.pt(root.bn.closeButton)
    x: root.pt(root.bn.closeCenterX) - width / 2
    y: root.pt(root.bn.closeCenterY) - height / 2
    opacity: root.hovered ? 1 : 0
    scale: root.hovered ? 1 : Motion.iconFromScale
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
    onClicked: root.closeRequested()
  }

  // The actions menu under the capsule: the shared henri-ui menu.
  HUi.Reveal {
    id: menu
    kind: "menu"
    origin: Item.TopRight
    anchors.right: parent.right
    anchors.rightMargin: root.pt(root.bn.capsuleRight)
    anchors.top: parent.bottom
    anchors.topMargin: root.pt(4)
    width: menuSurface.implicitWidth
    height: menuSurface.implicitHeight
    closeOnOutsideClick: true
    onDismissRequested: open = false
    AUi.NcCard {
      id: menuSurface
      anchors.fill: parent
      palette: root.palette
      radius: Style.space(Motion.radiusPopover)
      readonly property int padding: Style.space(5)
      implicitWidth: menuList.implicitWidth + padding * 2
      implicitHeight: menuList.implicitHeight + padding * 2
      HUi.MenuList {
        id: menuList
        x: menuSurface.padding; y: menuSurface.padding
        width: parent.width - menuSurface.padding * 2
        focus: menu.open
        fontFamily: Apple.uiFont
        textColor: root.palette.textPrimary
        selectedBackground: Apple.accent
        selectedText: "#ffffff"
        hairline: root.palette.borderOuter
        model: root.hasActions ? root.actions.map(function(a) { return { text: a.text, id: a.id } }) : []
        onActivated: function(index, entry) {
          menu.open = false
          root.actionRequested(String(entry.id))
        }
      }
    }
  }
}
