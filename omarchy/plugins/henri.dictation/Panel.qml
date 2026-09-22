// The dictation card. Pure visuals: everything it draws comes in as a
// property, so it can be rendered offscreen against fake levels and looked at
// without starting a recording (probe.qml in the plugin's scratchpad).
//
// Split out from Service.qml because the assistant panel will be this same
// card with pages in it -- keeping the drawing separate from the daemon
// plumbing is what makes that a change of content rather than a rewrite.

import QtQuick
import Quickshell
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

HUi.Surface {
  id: card

  // ── Input ───────────────────────────────────────────────────────────────
  property bool listening: false
  property bool working: false
  property var levels: []                   // 0…1 per bar, oldest first
  property int barCount: 34
  property real sweep: 0                    // 0…1, travels while transcribing
  property string readoutText: "0:00"
  property real barWidth: Style.space(3)
  property real barHeight: Style.space(26)

  role: "popups"
  kind: "panel"
  width: Style.space(320)
  height: Style.space(52)

  // A pill, not a rounded rectangle: fully rounded ends are what the macOS
  // voice surfaces look like, and it gives the assistant panel somewhere to go
  // -- a pill that grows into a card reads as one object opening, the way a
  // rounded rectangle growing into a bigger rounded rectangle never does.
  // `height / 2` is a shape relation, not a hand-picked radius; if a second
  // plugin ever wants it, it belongs in HUi.Surface as `kind: "pill"`.
  radius: height / 2

  readonly property color ink: Color.popups.text
  readonly property color dimText: Util.alpha(ink, Motion.secondaryTextAlpha)
  readonly property color live: Color.accent

  // ── Mic ─────────────────────────────────────────────────────────────────
  // Rebuilt from SF Symbols' `mic.fill` proportions rather than shipped as a
  // glyph: capsule, an arc that is the bottom half of a stroked circle, and a
  // stem. Same approach as HUi.BatteryGlyph, and for the same reason.
  Item {
    id: mic
    readonly property real s: Style.space(20)
    readonly property real stroke: Math.max(1.5, s * 0.095)

    anchors.left: parent.left
    anchors.leftMargin: Style.space(16)
    anchors.verticalCenter: parent.verticalCenter
    width: s
    height: s

    opacity: card.listening ? 1 : Motion.disabledOpacity
    Behavior on opacity {
      NumberAnimation {
        duration: Motion.fast
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.easeOut
      }
    }

    Rectangle {                              // capsule
      width: mic.s * 0.34
      height: mic.s * 0.5
      radius: width / 2
      x: (mic.s - width) / 2
      y: mic.s * 0.06
      color: card.live
      antialiasing: true
    }

    Item {                                   // arc: lower half of a stroked circle
      width: mic.s * 0.64
      height: mic.s * 0.32
      x: (mic.s - width) / 2
      y: mic.s * 0.44
      clip: true
      Rectangle {
        width: parent.width
        height: parent.width
        y: -parent.width / 2
        radius: width / 2
        color: "transparent"
        border.width: mic.stroke
        border.color: card.live
        antialiasing: true
      }
    }

    Rectangle {                              // stem
      width: mic.stroke
      height: mic.s * 0.16
      radius: width / 2
      x: (mic.s - width) / 2
      y: mic.s * 0.76
      color: card.live
      antialiasing: true
    }
  }

  // ── Waveform ────────────────────────────────────────────────────────────
  Row {
    id: wave
    readonly property real barW: card.barWidth
    readonly property real maxH: card.barHeight
    readonly property real minH: card.barWidth
    readonly property real floorScale: minH / maxH

    anchors.left: mic.right
    anchors.leftMargin: Style.space(14)
    anchors.right: readout.left
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    height: maxH
    spacing: (width - barW * card.barCount) / (card.barCount - 1)

    Repeater {
      model: card.barCount

      Rectangle {
        id: bar
        required property int index

        readonly property real level: card.levels[index] || 0
        readonly property real target: card.listening
          ? Math.max(wave.floorScale, level)
          : wave.floorScale

        // Distance from the travelling sweep, 0 at its centre. Only read while
        // transcribing; while listening the bars light with their own level.
        readonly property real reach: Math.abs(index / (card.barCount - 1) - card.sweep)
        readonly property real glow: Math.max(0, 1 - reach / 0.22)

        width: wave.barW
        height: wave.maxH
        radius: width / 2
        color: card.live
        antialiasing: true

        opacity: Motion.disabledOpacity + (1 - Motion.disabledOpacity)
          * (card.working ? glow : Math.min(1, level * 2))
        Behavior on opacity {
          NumberAnimation {
            duration: Motion.instant
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.easeOut
          }
        }

        // The full-height bar is squeezed by a transform, never by its height:
        // nothing in this Row is re-laid out while the waveform moves.
        transform: Scale {
          origin.x: wave.barW / 2
          origin.y: wave.maxH / 2
          xScale: 1
          yScale: bar.target
          // A tick is shorter than `instant`, so a bar is always still
          // travelling when its next value lands: the steps smooth into one
          // continuous movement instead of stepping once per tick.
          Behavior on yScale {
            NumberAnimation {
              duration: Motion.instant
              easing.type: Easing.BezierSpline
              easing.bezierCurve: Motion.easeOut
            }
          }
        }
      }
    }
  }

  // ── Readout ─────────────────────────────────────────────────────────────
  HUi.CrossfadeText {
    id: readout
    anchors.right: parent.right
    anchors.rightMargin: Style.space(16)
    anchors.verticalCenter: parent.verticalCenter
    // Wide enough for the longest string it ever shows ("Transcribing…"), so
    // the waveform keeps its width when the state changes and nothing elides.
    width: Style.space(96)
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
    text: card.readoutText
    color: card.dimText
    fontSize: Style.font.bodySmall
  }
}
