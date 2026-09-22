// The dictation card. Pure visuals: everything it draws comes in as a
// property, so it can be rendered offscreen against fake levels and looked at
// without starting a recording (probe.qml in the plugin's scratchpad).
//
// The mic and the waveform live in henri-ui, not here: henri.assistant draws
// the same two things, and a shared building block is what makes a change to
// the waveform's behaviour reach both plugins instead of one.

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

  role: "popups"
  kind: "panel"
  width: Style.space(320)
  height: Style.space(52)

  // A pill, not a rounded rectangle: fully rounded ends are what the macOS
  // voice surfaces look like, and it gives the assistant panel somewhere to go
  // -- a pill that grows into a card reads as one object opening, the way a
  // rounded rectangle growing into a bigger rounded rectangle never does.
  // `height / 2` is a shape relation, not a hand-picked radius; if a third
  // surface ever wants it, it belongs in HUi.Surface as `kind: "pill"`.
  radius: height / 2

  readonly property color ink: Color.popups.text
  readonly property color dimText: Util.alpha(ink, Motion.secondaryTextAlpha)

  HUi.MicGlyph {
    id: mic
    anchors.left: parent.left
    anchors.leftMargin: Style.space(16)
    anchors.verticalCenter: parent.verticalCenter
    height: Style.space(20)
    live: card.listening
  }

  HUi.Waveform {
    id: wave
    anchors.left: mic.right
    anchors.leftMargin: Style.space(14)
    anchors.right: readout.left
    anchors.rightMargin: Style.space(12)
    anchors.verticalCenter: parent.verticalCenter
    height: Style.space(26)
    levels: card.levels
    barCount: card.barCount
    live: card.listening
    working: card.working
    sweep: card.sweep
  }

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
