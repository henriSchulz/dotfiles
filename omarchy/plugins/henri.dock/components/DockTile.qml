import QtQuick
import QtQuick.Effects
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi
import "file:///home/henri/.local/share/apple-ui/Apple.js" as Apple

// One entry of the dock: app, folder, file, minimized window, trash — or a
// separator. Geometry comes from the dock's layout pass (main-axis centre in
// `main`, size from the magnification spring); the icon is drawn once at
// `dock.iconBase` px and scaled, so magnification only moves a quad and the
// shadow texture never re-renders per frame.
Item {
  id: tile
  required property int index
  required property string itemId
  required property string kind
  property var dock

  readonly property var item: dock.items[itemId] || null
  readonly property bool isSeparator: kind === "separator"
  readonly property bool gone: item === null || item.gone === true

  // Layout inputs / outputs
  property real main: 0
  property real targetSize: dock.tileSize
  readonly property real curSize: sizeSpring.value
  readonly property real enter: enterSpring.value
  readonly property real visSize: isSeparator ? dock.tileSize : curSize * enter
  readonly property real mainExtent: isSeparator ? dock.separatorWidth * enter : visSize
  readonly property bool pressed: dock.pressedIndex === index && !dock.dragging
  readonly property bool dragged: dock.dragIndex === index
  readonly property bool focused: dock.kbMode && dock.kbIndex === index
  readonly property bool hovered: dock.hoverIndex === index && dock.hovering
  property real hop: 0
  property real pulse: 1
  property int attentionCount: 0

  readonly property var r: dock.rectFor(main, dock.dockBaseline, mainExtent, visSize)
  x: r.x
  y: r.y
  width: r.w
  height: r.h
  visible: !isSeparator || enter > 0.01
  opacity: dragged ? 0 : 1

  Accessible.role: isSeparator ? Accessible.Separator : Accessible.Button
  Accessible.name: dock.accessibleName(item)

  HUi.SpringValue {
    id: sizeSpring
    to: tile.targetSize
    preset: Motion.dock.magnify
    epsilon: 0.05
    onRunningChanged: dock.springRunning(running)
  }
  HUi.SpringValue {
    id: enterSpring
    to: tile.gone ? 0 : 1
    preset: Motion.dock.gap
    epsilon: 0.003
    onRunningChanged: dock.springRunning(running)
    onValueChanged: if (tile.gone && value <= 0.003 && !running) dock.finalizeRemove(tile.itemId)
  }
  Component.onCompleted: {
    if (!isSeparator && dock.ready) enterSpring.snap(0)
    dock.layoutDirty()
  }
  onGoneChanged: if (gone) dock.layoutDirty()

  // ------------------------------------------------------------ separator
  Rectangle {
    visible: tile.isSeparator
    readonly property real len: dock.tileSize * Apple.dock.separatorFraction
    width: dock.horizontal ? 1 : len
    height: dock.horizontal ? len : 1
    anchors.centerIn: parent
    color: dock.palette.separator
  }

  // ------------------------------------------------------------ icon
  // Fixed-size art scaled to the tile; grows from the dock dockBaseline because
  // the tile rect itself is anchored there.
  Item {
    id: art
    visible: !tile.isSeparator
    width: dock.iconBase
    height: dock.iconBase
    scale: tile.visSize / dock.iconBase
    transformOrigin: Item.TopLeft
    // hidden while the genie/scale effect draws this window's snapshot itself
    opacity: dock.effectTargetId === tile.itemId && dock.effectRunning && tile.kind === "minimizedWindow" ? 0 : tile.pulse
    transform: Translate { x: dock.hopX(tile.hop); y: dock.hopY(tile.hop) }

    readonly property real body: dock.iconBase * Apple.dock.iconBody
    readonly property real inset: (dock.iconBase - body) / 2

    Item {
      id: artContent
      anchors.fill: parent
      visible: false

      // App / file / folder-as-folder / trash icon
      Image {
        id: icon
        visible: tile.item !== null && tile.kind !== "minimizedWindow" && !(tile.kind === "folder" && tile.item.displayAs === "stack" && stackPeek.count > 0)
        x: art.inset; y: art.inset
        width: art.body; height: art.body
        source: tile.item ? (tile.item.icon || "") : ""
        sourceSize: Qt.size(256, 256)
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        asynchronous: true
      }

      // Folder shown as a stack: the newest three files fanned on top of each other
      Repeater {
        id: stackPeek
        model: tile.kind === "folder" && tile.item && tile.item.displayAs === "stack" ? (tile.item.peek || []) : []
        delegate: Image {
          required property int index
          required property var modelData
          readonly property int n: stackPeek.count
          readonly property real s: art.body * 0.78
          x: art.inset + (art.body - s) / 2 + (n - 1 - index) * art.body * 0.05
          y: art.inset + (art.body - s) - (n - 1 - index) * art.body * 0.06
          width: s; height: s
          z: index
          source: modelData
          sourceSize: Qt.size(192, 192)
          fillMode: Image.PreserveAspectFit
          smooth: true; mipmap: true; asynchronous: true
        }
      }

      // Minimized window: snapshot taken at minimize time, app icon bottom right
      Item {
        id: thumbHost
        visible: tile.kind === "minimizedWindow"
        anchors.fill: parent
        readonly property var snap: tile.item && tile.item.snapshot ? tile.item.snapshot : null
        readonly property bool hasSnap: snap !== null && snap !== undefined && snap.hasContent === true
        readonly property real aspect: snap && snap.width > 0 && snap.height > 0 ? snap.height / snap.width : 0.66
        readonly property real w: aspect <= 1 ? art.body : art.body / aspect
        readonly property real h: aspect <= 1 ? art.body * aspect : art.body
        Rectangle {
          x: (art.width - thumbHost.w) / 2; y: art.inset + art.body - thumbHost.h
          width: thumbHost.w; height: thumbHost.h
          radius: Style.space(6)
          color: dock.palette.pill
          border.width: 1; border.color: dock.palette.hairline
          antialiasing: true
          clip: true
          ShaderEffectSource {
            anchors.fill: parent
            anchors.margins: 1
            visible: thumbHost.hasSnap
            sourceItem: thumbHost.snap
            live: false
            hideSource: false
            mipmap: true
            Component.onCompleted: scheduleUpdate()
          }
          Image {
            // No snapshot (window minimized before the shell started): the app icon
            visible: !thumbHost.hasSnap
            anchors.centerIn: parent
            width: parent.height * 0.6; height: width
            source: tile.item ? (tile.item.icon || "") : ""
            sourceSize: Qt.size(128, 128)
            fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
          }
        }
        Image {
          readonly property real s: dock.iconBase * Apple.dock.thumbBadge
          x: art.inset + art.body - s + art.inset * 0.5
          y: art.inset + art.body - s + art.inset * 0.5
          width: s; height: s
          source: tile.item ? (tile.item.appIcon || "") : ""
          sourceSize: Qt.size(128, 128)
          fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
        }
      }

      // Badge (spec §8.2): red pill top right, scales with the icon
      Rectangle {
        id: badge
        readonly property string label: tile.item ? dock.badgeText(tile.item.badge) : ""
        visible: label.length > 0
        readonly property real h: Math.max(dock.iconBase * Apple.dock.badgeFraction, Style.space(Apple.dock.badgeMin) * dock.iconBase / dock.tileSize)
        height: h
        width: Math.max(h, badgeLabel.implicitWidth + Style.space(Apple.dock.badgePadX) * 2 * dock.iconBase / dock.tileSize)
        radius: h / 2
        x: art.inset + art.body - width + h * 0.25
        y: art.inset - h * 0.25
        color: Apple.dock.badge
        scale: badgeSpring.value
        transformOrigin: Item.Center
        HUi.SpringValue { id: badgeSpring; to: badge.visible ? 1 : 0; preset: Motion.dock.badgeIn; epsilon: 0.002 }
        Text {
          id: badgeLabel
          anchors.centerIn: parent
          text: badge.label
          color: Apple.dock.badgeText
          font.family: Apple.uiFont
          font.pixelSize: Style.space(Apple.dock.badgeFont) * dock.iconBase / dock.tileSize
          font.weight: Font.Medium
        }
      }
    }

    MultiEffect {
      id: artFx
      anchors.fill: artContent
      source: artContent
      shadowEnabled: true
      shadowBlur: 0.25
      shadowVerticalOffset: Apple.dock.iconShadowY * dock.iconBase / dock.tileSize
      shadowOpacity: Apple.dock.iconShadowAlpha
      brightness: tile.pressed || tile.dropTarget ? Motion.dock.pressedBrightness - 1 : 0
      autoPaddingEnabled: true
    }

    // Keyboard focus ring (§17): only while the dock is driven from the keyboard
    Rectangle {
      visible: tile.focused
      x: art.inset - Style.space(Apple.dock.focusRing) * 1.5
      y: art.inset - Style.space(Apple.dock.focusRing) * 1.5
      width: art.body + Style.space(Apple.dock.focusRing) * 3
      height: width
      radius: width * 0.24
      color: "transparent"
      border.width: Style.space(Apple.dock.focusRing) * dock.iconBase / dock.tileSize
      border.color: dock.accent
      antialiasing: true
    }
  }
  property bool dropTarget: dock.dropIndex === index

  // ------------------------------------------------------------ running indicator (§8.1)
  Rectangle {
    id: dot
    readonly property real d: dock.indicatorSize
    readonly property var dr: dock.rectFor(tile.main, dock.edgeGap + Style.space(Apple.dock.indicatorGap), d, d)
    x: dr.x - tile.x
    y: dr.y - tile.y
    width: d; height: d
    radius: d / 2
    color: dock.palette.indicator
    visible: opacity > 0
    opacity: dock.showIndicators && tile.item && tile.kind === "app" && tile.item.running && !tile.gone ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.dock.indicatorFade; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
  }

  // ------------------------------------------------------------ bounces (§7.3, §7.4)
  readonly property bool launching: !!(item && item.launching) && dock.animateOpeningApps && !isSeparator
  readonly property bool attention: !!(item && item.attention) && !isSeparator
  readonly property bool reduce: dock.reduceMotion

  SequentialAnimation {
    id: launchBounce
    NumberAnimation { target: tile; property: "hop"; to: dock.tileSize * Motion.dock.bounceHeight; duration: Motion.dock.bounceUp; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.dock.bounceUpCurve }
    NumberAnimation { target: tile; property: "hop"; to: 0; duration: Motion.dock.bounceDown; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.dock.bounceDownCurve }
    onFinished: if (tile.launching && !tile.reduce) launchBounce.restart()
  }
  SequentialAnimation {
    id: attentionBounce
    NumberAnimation { target: tile; property: "hop"; to: dock.tileSize * Motion.dock.attentionHeight; duration: Motion.dock.attentionUp; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.dock.bounceUpCurve }
    NumberAnimation { target: tile; property: "hop"; to: 0; duration: Motion.dock.attentionDown; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.dock.bounceDownCurve }
    PauseAnimation { duration: Motion.dock.attentionPause }
    onFinished: {
      tile.attentionCount += 1
      if (tile.attention && tile.attentionCount < dock.attentionRepeats(tile.itemId) && !tile.reduce) attentionBounce.restart()
      else dock.clearAttention(tile.itemId)
    }
  }
  // Reduce motion: a soft opacity pulse instead of the hop
  SequentialAnimation {
    id: pulseAnim
    NumberAnimation { target: tile; property: "pulse"; to: 0.45; duration: Motion.dock.bounceUp; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut }
    NumberAnimation { target: tile; property: "pulse"; to: 1; duration: Motion.dock.bounceDown; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut }
    onFinished: {
      if (tile.attention) tile.attentionCount += 1
      if (tile.launching || (tile.attention && tile.attentionCount < dock.attentionRepeats(tile.itemId))) pulseAnim.restart()
      else if (tile.attention) dock.clearAttention(tile.itemId)
    }
  }
  onLaunchingChanged: if (launching) { if (reduce) { if (!pulseAnim.running) pulseAnim.restart() } else if (!launchBounce.running && !attentionBounce.running) launchBounce.restart() }
  onAttentionChanged: {
    if (attention) {
      attentionCount = 0
      if (reduce) { if (!pulseAnim.running) pulseAnim.restart() }
      else if (!attentionBounce.running) { if (launchBounce.running) launchBounce.stop(); attentionBounce.restart() }
    }
  }
}
