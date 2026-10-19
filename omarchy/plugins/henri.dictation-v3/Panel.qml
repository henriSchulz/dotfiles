// The dictation pill on Velum. Pure visuals: everything it draws comes in as a
// property, so it can be shown against fake levels without a recording
// (IPC preview in Service.qml).
//
// The mic and the waveform are Velum parts (VMicGlyph, VWaveform):
// henri.assistant-v3 draws the same two, so a change reaches both.

import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

VFloatingCard {
  id: card

  // ── Input ───────────────────────────────────────────────────────────────
  property bool listening: false
  property bool working: false
  property var levels: []                   // 0…1 per bar, oldest first
  property int barCount: Theme.layout.voice.bars
  property real sweep: 0                    // 0…1, travels while transcribing
  property string readoutText: "0:00"

  readonly property var dims: Theme.layout.voice.dictation
  width: dims.width
  height: dims.height

  // A pill, not a rounded rectangle: fully rounded ends are what the macOS
  // voice surfaces look like, and it gives the assistant pill somewhere to go.
  radius: height / 2

  VMicGlyph {
    id: mic
    anchors.left: parent.left
    anchors.leftMargin: card.dims.padX
    anchors.verticalCenter: parent.verticalCenter
    height: card.dims.glyph
    live: card.listening
  }

  VWaveform {
    anchors.left: mic.right
    anchors.leftMargin: card.dims.gap
    anchors.right: readout.left
    anchors.rightMargin: card.dims.gap - Theme.layout.separator * 2
    anchors.verticalCenter: parent.verticalCenter
    height: card.dims.wave
    levels: card.levels
    barCount: card.barCount
    live: card.listening
    working: card.working
    sweep: card.sweep
  }

  VCrossfadeText {
    id: readout
    anchors.right: parent.right
    anchors.rightMargin: card.dims.padX
    anchors.verticalCenter: parent.verticalCenter
    // Wide enough for the longest string it ever shows ("Transcribing…"), so
    // the waveform keeps its width when the state changes and nothing elides.
    width: card.dims.readout
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
    text: card.readoutText
    tone: "secondary"
    pixelSize: Theme.m.type.small
  }
}
