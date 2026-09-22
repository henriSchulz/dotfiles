// The assistant card. Pure visuals plus key handling: state comes in as
// properties, intent goes out as signals, so Service.qml owns the daemon and
// the agent and this file owns nothing but the surface.
//
// It is the dictation pill grown up. Empty, it IS that pill -- same height,
// same rounded ends, the same mic and waveform. The moment there is something
// to show it becomes a card: the radius eases to the panel corner, the width
// springs out, and the conversation glides open underneath. One object
// opening, not a second window appearing.

import QtQuick
import Quickshell
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

HUi.Surface {
  id: card

  // ── Input ───────────────────────────────────────────────────────────────
  property var turns: []                    // [{question, answer}] — settled
  property string pendingQuestion: ""       // the turn being answered
  property string streamed: ""              // its answer so far
  property string draft: ""                 // composer text
  property string note: ""                  // why an empty answer was empty

  property bool listening: false
  property bool transcribing: false
  property bool thinking: false

  property var levels: []
  property int barCount: 34
  property real sweep: 0

  // ── Output ──────────────────────────────────────────────────────────────
  signal submitted()
  signal dismissed()
  signal draftEdited(string text)

  // ── Shape ───────────────────────────────────────────────────────────────
  // Compact means "nothing but the composer": the surface stays the pill.
  readonly property bool compact: turns.length === 0 && pendingQuestion === "" && note === ""

  role: "popups"
  kind: "panel"

  HUi.SpringValue { id: w; preset: Motion.smooth; to: card.compact ? Style.space(520) : Style.space(720) }
  width: Motion.reduceMotion ? w.to : w.value

  // A card from the first frame, not the dictation pill grown up. Once the
  // hint line is always there the compact state is two rows tall, and
  // `height / 2` on that is a stadium, not a pill -- the shape would be
  // fighting the content. The growth is carried by the width spring instead.
  radius: Style.space(Motion.radiusPanel)

  readonly property color ink: Color.popups.text
  readonly property color dimText: Util.alpha(ink, Motion.secondaryTextAlpha)
  readonly property real pad: Style.space(20)
  // The composer row sets the compact card's height, so it is the pill.
  readonly property real rowHeight: Style.space(60)

  property string status: ""                // e.g. a recording that heard nothing

  // Heartbeat for the thinking dots. Targeted rather than `NumberAnimation on
  // pulse`, so the value is a plain property the probe can park.
  property real pulse: 0
  NumberAnimation {
    target: card; property: "pulse"
    running: card.thinking && card.streamed === ""
    from: 0; to: 1
    duration: Motion.thinkingCycle
    loops: Animation.Infinite
  }

  readonly property string hint: listening ? "↵  send      Super A  stop      Esc  cancel"
    : transcribing ? "…"
    : thinking ? "Working…"
    : "↵  send      Super A  dictate      Esc  close"

  implicitHeight: body.height

  // ── Body ────────────────────────────────────────────────────────────────
  Column {
    id: body
    x: card.pad
    width: card.width - card.pad * 2
    spacing: 0

    // Conversation. Collapse keeps the height on the smooth spring, so the
    // card grows with the answer instead of jumping a line at a time.
    HUi.Collapse {
      id: conversation
      width: parent.width
      expanded: !card.compact

      Column {
        width: conversation.width

      Item {
        width: conversation.width
        implicitHeight: Math.min(scroll.contentHeight + card.pad * 2, Style.space(460))

        Flickable {
          id: scroll
          anchors.fill: parent
          anchors.topMargin: card.pad
          anchors.bottomMargin: card.pad
          contentWidth: width
          contentHeight: stack.implicitHeight
          clip: true
          boundsBehavior: Flickable.OvershootBounds
          flickDeceleration: Motion.flickDeceleration
          maximumFlickVelocity: Motion.maximumFlickVelocity

          // Streaming text grows downward; follow it unless the reader has
          // scrolled up themselves.
          property bool pinned: true
          onContentHeightChanged: if (pinned) contentY = Math.max(0, contentHeight - height)
          onMovementStarted: pinned = false
          onContentYChanged: if (!moving && contentY >= contentHeight - height - 1) pinned = true

          Column {
            id: stack
            width: scroll.width
            spacing: Style.space(16)

            Repeater {
              model: card.turns
              delegate: Column {
                required property var modelData
                width: stack.width
                spacing: Style.space(6)
                Text {
                  width: parent.width
                  text: modelData.question
                  color: card.ink
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  font.weight: Font.DemiBold
                  wrapMode: Text.Wrap
                }
                Text {
                  width: parent.width
                  text: modelData.answer
                  color: card.ink
                  font.family: Style.font.family
                  font.pixelSize: Style.font.subtitle
                  textFormat: Text.MarkdownText
                  wrapMode: Text.Wrap
                }
              }
            }

            // The turn in flight: its answer is the stream, so it is drawn
            // here rather than pushed into `turns` on every delta -- that
            // would rebuild the whole list for each word.
            Column {
              width: stack.width
              spacing: Style.space(6)
              visible: card.pendingQuestion !== "" || card.note !== ""

              Text {
                width: parent.width
                text: card.pendingQuestion
                color: card.ink
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
                visible: text !== ""
              }
              // Thinking: three dots where the answer will start, so the wait
              // happens in the place the eye is already on. Each one rides the
              // same heartbeat a fifth of a turn apart. Opacity and scale only.
              Row {
                id: dots
                height: Style.font.subtitle * 1.4
                spacing: Style.space(5)
                visible: card.thinking && card.streamed === ""

                Repeater {
                  model: 3
                  Item {
                    required property int index
                    width: Style.space(6)
                    height: dots.height

                    // A raised cosine: each dot swells once per turn, a fifth
                    // of a turn behind the one before it.
                    readonly property real phase: {
                      var t = card.pulse - index * 0.2
                      t = t - Math.floor(t)
                      return 0.5 - 0.5 * Math.cos(t * 2 * Math.PI)
                    }

                    Rectangle {
                      anchors.centerIn: parent
                      width: parent.width
                      height: width
                      radius: width / 2
                      color: card.ink
                      opacity: Motion.disabledOpacity
                        + (1 - Motion.disabledOpacity) * parent.phase
                      scale: Motion.reduceMotion ? 1 : 0.8 + 0.2 * parent.phase
                    }
                  }
                }
              }

              Text {
                width: parent.width
                text: card.streamed
                color: card.ink
                font.family: Style.font.family
                font.pixelSize: Style.font.subtitle
                textFormat: Text.MarkdownText
                wrapMode: Text.Wrap
                visible: text !== ""
              }
              Text {
                width: parent.width
                text: card.note
                color: card.dimText
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                wrapMode: Text.Wrap
                visible: text !== ""
              }
            }
          }
        }
      }

      // Hairline between the conversation and the composer. Inside the
      // collapse, so a compact card is exactly the composer row tall.
      Rectangle {
        width: conversation.width
        height: 1
        color: Util.alpha(card.ink, Motion.hairlineAlpha)
      }
      }
    }

    // ── Composer ──────────────────────────────────────────────────────────
    Item {
      id: composer
      width: parent.width
      height: Math.max(card.rowHeight, input.implicitHeight + card.pad * 2)

      HUi.MicGlyph {
        id: mic
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: (card.rowHeight - height) / 2
        height: Style.space(22)
        live: card.listening
      }

      // Listening shows the waveform in the composer's place; the text takes
      // over as soon as there are words. One crossfade, no layout jump.
      HUi.Waveform {
        anchors.left: mic.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: (card.rowHeight - height) / 2
        height: Style.space(28)
        levels: card.levels
        barCount: card.barCount
        live: card.listening
        working: card.transcribing
        sweep: card.sweep
        opacity: (card.listening || card.transcribing) ? 1 : 0
        Behavior on opacity {
          NumberAnimation {
            duration: Motion.fast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.easeOut
          }
        }
      }

      TextEdit {
        id: input
        anchors.left: mic.right
        anchors.leftMargin: Style.space(14)
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: (card.rowHeight - Style.font.subtitle * 1.4) / 2
        color: card.ink
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        selectionColor: Color.accent
        selectedTextColor: Motion.onColor(Color.accent)
        wrapMode: TextEdit.Wrap
        text: card.draft
        opacity: (card.listening || card.transcribing) ? 0 : 1
        // Stays enabled while the waveform is up: ↵ ends the recording, so the
        // key has to reach this handler even when the field is invisible.
        enabled: true
        Behavior on opacity {
          NumberAnimation {
            duration: Motion.fast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.easeOut
          }
        }

        // The property is the source of truth; echoing every keystroke back
        // through it would fight the cursor, so only real edits are reported.
        onTextChanged: if (text !== card.draft) card.draftEdited(text)

        Keys.onPressed: function (event) {
          if (event.key === Qt.Key_Escape) {
            card.dismissed()
            event.accepted = true
          } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                     && !(event.modifiers & Qt.ShiftModifier)) {
            card.submitted()
            event.accepted = true
          }
        }

        Text {
          anchors.fill: parent
          text: card.status !== "" ? card.status : "Ask anything"
          color: card.dimText
          font: input.font
          visible: input.text === "" && !card.listening && !card.transcribing
        }
      }
    }

    // ── Hint ──────────────────────────────────────────────────────────────
    Item {
      width: parent.width
      implicitHeight: label.implicitHeight + Style.space(12)
      HUi.CrossfadeText {
        id: label
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(12)
        horizontalAlignment: Text.AlignRight
        text: card.hint
        color: card.dimText
        fontSize: Style.font.body
      }
    }
  }

  function focusInput() { input.forceActiveFocus() }
  function caretToEnd() { input.cursorPosition = input.length }
}
