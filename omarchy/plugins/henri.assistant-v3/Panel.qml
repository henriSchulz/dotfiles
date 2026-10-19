// The voice card on Velum. One row: microphone, waveform, and what it is doing.
//
// What is spoken goes straight into a Claude Code session, so the card has
// nothing to show once the words are out and closes itself. A single row means
// the pill shape fits, the way the dictation pill wears it.

import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

VFloatingCard {
  id: card

  property bool listening: false
  property bool working: false               // transcribing, or handing over
  property var levels: []
  property int barCount: Theme.layout.voice.bars
  property real sweep: 0
  property string status: ""                 // right-hand label

  signal dismissed()

  readonly property var dims: Theme.layout.voice.assistant
  width: dims.width
  height: dims.height
  radius: height / 2

  // The card takes the keyboard while it is up, so Esc has to land somewhere.
  focus: true
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      card.dismissed()
      event.accepted = true
    }
  }

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
    anchors.right: label.left
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
    id: label
    anchors.right: parent.right
    anchors.rightMargin: card.dims.padX
    anchors.verticalCenter: parent.verticalCenter
    // Sized for the longest thing it says, so the waveform keeps its width.
    width: card.dims.readout
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
    text: card.status
    tone: "secondary"
  }
}
