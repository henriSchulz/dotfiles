// The voice card. One row: microphone, waveform, and what it is doing.
//
// It used to hold a conversation -- the agent answered inside it, with pages,
// thinking dots and a permission window. That is gone on purpose: what is
// spoken now goes straight into a Claude Code session, so the card has nothing
// to show once the words are out and closes itself. A single row means the
// pill shape fits again, the way the dictation panel wears it.

import QtQuick
import Quickshell
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

HUi.Surface {
  id: card

  property bool listening: false
  property bool working: false               // transcribing, or handing over
  property var levels: []
  property int barCount: 34
  property real sweep: 0
  property string status: ""                 // right-hand label

  signal dismissed()

  role: "popups"
  kind: "panel"
  width: Style.space(560)
  height: Style.space(60)
  radius: height / 2

  readonly property color ink: Color.popups.text
  readonly property color dimText: Util.alpha(ink, Motion.secondaryTextAlpha)

  // The card takes the keyboard while it is up, so Esc has to land somewhere.
  focus: true
  Keys.onPressed: function (event) {
    if (event.key === Qt.Key_Escape) {
      card.dismissed()
      event.accepted = true
    }
  }

  HUi.MicGlyph {
    id: mic
    anchors.left: parent.left
    anchors.leftMargin: Style.space(22)
    anchors.verticalCenter: parent.verticalCenter
    height: Style.space(22)
    live: card.listening
  }

  HUi.Waveform {
    anchors.left: mic.right
    anchors.leftMargin: Style.space(16)
    anchors.right: label.left
    anchors.rightMargin: Style.space(14)
    anchors.verticalCenter: parent.verticalCenter
    height: Style.space(28)
    levels: card.levels
    barCount: card.barCount
    live: card.listening
    working: card.working
    sweep: card.sweep
  }

  HUi.CrossfadeText {
    id: label
    anchors.right: parent.right
    anchors.rightMargin: Style.space(22)
    anchors.verticalCenter: parent.verticalCenter
    // Sized for the longest thing it says, so the waveform keeps its width.
    width: Style.space(150)
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
    text: card.status
    color: card.dimText
    fontSize: Style.font.body
  }
}
