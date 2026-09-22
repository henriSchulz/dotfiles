// The permission window. agent-guard is blocked inside the agent's tool call
// while this is up, so what happens here is the whole decision -- there is no
// second round anywhere, and nothing else gets asked before or after.
//
// A window of its own rather than a section of the card: it is a stop, and a
// stop should look like one. Scrim behind it, the exact command in front, two
// buttons. Cancel is the default -- Henri reaches here because something wanted
// to change his machine, and the safe answer should be the easy one.

import QtQuick
import Quickshell
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

HUi.Surface {
  id: sheet

  property var request: null                // {id, tool, title, detail}
  readonly property bool active: request !== null

  signal allowed()
  signal cancelled()

  role: "popups"
  kind: "panel"
  width: Style.space(520)
  radius: Style.space(Motion.radiusPanel)
  implicitHeight: body.height

  readonly property color ink: Color.popups.text
  readonly property color dimText: Util.alpha(ink, Motion.secondaryTextAlpha)
  readonly property real pad: Style.space(22)

  Column {
    id: body
    x: sheet.pad
    width: sheet.width - sheet.pad * 2
    topPadding: sheet.pad
    bottomPadding: sheet.pad
    spacing: Style.space(14)

    Text {
      width: parent.width
      text: sheet.request ? sheet.request.title + "?" : ""
      color: sheet.ink
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.weight: Font.DemiBold
      wrapMode: Text.Wrap
    }

    Text {
      width: parent.width
      text: "The assistant wants to do this. It is stopped until you answer."
      color: sheet.dimText
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
    }

    // Verbatim, never a summary: what is confirmed has to be what runs.
    Rectangle {
      width: parent.width
      height: detail.implicitHeight + Style.space(22)
      radius: Style.space(Motion.radiusControl)
      color: Util.alpha(sheet.ink, Motion.hoverAlpha)

      Text {
        id: detail
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        text: sheet.request ? sheet.request.detail : ""
        color: sheet.ink
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        wrapMode: Text.WrapAnywhere
      }
    }

    Item {
      width: parent.width
      height: buttons.height

      Row {
        id: buttons
        anchors.right: parent.right
        spacing: Style.space(10)

        HUi.Button {
          text: "Cancel"
          onClicked: sheet.cancelled()
        }
        HUi.Button {
          text: "Allow"
          prominent: true
          danger: true
          onClicked: sheet.allowed()
        }
      }
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignRight
      text: "↵  allow      Esc  cancel"
      color: sheet.dimText
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }
}
