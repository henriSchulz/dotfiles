import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// macOS-style Apple menu. The Omarchy logo sits in the bar's left corner and
// opens a plain menu list; "Über diesen Computer" swaps the list for an About
// card, and restart / shut down / log out ask first on a confirm page, like
// the "…" items on macOS.
//
// Motion: rows cascade in on open, one highlight glides between rows, a
// chosen command blinks before it runs (as macOS does), pages cross-slide
// while the popup resizes, and the About logo springs in.
Panel {
  id: root
  moduleName: "henri.system-menu"
  ipcTarget: "henri.system-menu"
  manageIpc: false

  readonly property color fg: Color.popups.text
  readonly property color dimText: Qt.rgba(fg.r, fg.g, fg.b, 0.55)
  readonly property color separatorColor: Qt.rgba(fg.r, fg.g, fg.b, 0.12)
  readonly property color softFill: Qt.rgba(fg.r, fg.g, fg.b, 0.09)
  readonly property color softHover: Qt.rgba(fg.r, fg.g, fg.b, 0.16)
  readonly property color highlight: Color.accent
  readonly property color highlightText: Color.popups.background
  readonly property string textFont: Style.font.family
  readonly property string logo: ""
  readonly property int menuWidth: Style.space(250)
  readonly property int aboutWidth: Style.space(290)
  readonly property int rowHeight: Style.space(26)
  readonly property string userName: Quickshell.env("USER") || ""

  // "menu" | "about" | "confirm"
  property string page: "menu"
  property int selected: -1
  property var pending: null
  property var info: ({})
  // Drives the entrance cascade; flips true a frame after the popup maps.
  property bool revealed: false
  // Size changes animate only once the popup is up, so it opens at size.
  property bool sizeAnimated: false
  // While a chosen item blinks, input is ignored.
  property bool blinking: false

  readonly property var items: [
    { label: "Über diesen Computer", page: "about" },
    { separator: true },
    { label: "Systemeinstellungen …", cmd: "omarchy-menu toggle root" },
    { label: "App Store …", cmd: "xdg-terminal-exec --app-id=org.omarchy.terminal omarchy-pkg-install" },
    { separator: true },
    { label: "Sofort beenden …", cmd: "hyprctl kill" },
    { separator: true },
    { label: "Ruhezustand", cmd: "systemctl suspend" },
    { label: "Neustart …", cmd: "omarchy-system-reboot", title: "Möchtest du den Computer jetzt neu starten?", confirm: "Neustart" },
    { label: "Ausschalten …", cmd: "omarchy-system-shutdown", title: "Möchtest du den Computer jetzt ausschalten?", confirm: "Ausschalten" },
    { separator: true },
    { label: "Bildschirm sperren", cmd: "omarchy-system-lock" },
    { label: "Abmelden „" + userName + "“ …", cmd: "omarchy-system-logout", title: "Möchtest du dich jetzt abmelden?", confirm: "Abmelden" }
  ]

  function activate(index) {
    var item = items[index]
    if (!item || item.separator || blinking) return
    selected = index
    blinking = true
    blink.item = item
    blink.restart()
  }

  function perform(item) {
    if (item.page) { page = item.page; return }
    if (item.confirm) { pending = item; page = "confirm"; return }
    run(item.cmd)
  }

  // Close first so the popup's focus grab is gone before the command
  // (menus, lock screen, kill cursor) wants the keyboard or pointer.
  function run(cmd) {
    close()
    launch.cmd = cmd
    launch.restart()
  }
  Timer {
    id: launch
    property string cmd: ""
    interval: 150
    onTriggered: Quickshell.execDetached(["bash", "-c", cmd])
  }

  function moveSelection(delta) {
    var i = selected
    for (var n = 0; n < items.length; n++) {
      i = (i + delta + items.length) % items.length
      if (!items[i].separator) { selected = i; return }
    }
  }

  IpcHandler {
    target: "henri.system-menu"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Opens straight onto the "Über diesen Computer" card.
    function about(): void { root.page = "about"; root.open() }
  }

  onOpenedChanged: {
    if (opened) {
      if (page !== "about") page = "menu"
      selected = -1
      blinking = false
      revealTimer.restart()
      logoPulse.restart()
      if (!infoProc.running) infoProc.running = true
    } else {
      revealTimer.stop()
      revealed = false
      sizeAnimated = false
      resetPage.restart()
    }
  }
  // Back to the menu once the popup has faded, not while it still shows.
  Timer {
    id: resetPage
    interval: 250
    onTriggered: if (!root.opened) { root.page = "menu"; root.pending = null }
  }
  Timer {
    id: revealTimer
    interval: 16
    onTriggered: {
      root.revealed = true
      root.sizeAnimated = true
    }
  }

  // The macOS menu blinks the chosen item before acting on it.
  SequentialAnimation {
    id: blink
    property var item: null
    NumberAnimation { target: highlightBar; property: "blinkOpacity"; to: 0; duration: 55 }
    NumberAnimation { target: highlightBar; property: "blinkOpacity"; to: 1; duration: 55 }
    NumberAnimation { target: highlightBar; property: "blinkOpacity"; to: 0; duration: 55 }
    NumberAnimation { target: highlightBar; property: "blinkOpacity"; to: 1; duration: 55 }
    PauseAnimation { duration: 40 }
    ScriptAction {
      script: {
        root.blinking = false
        root.perform(blink.item)
      }
    }
  }

  Process {
    id: infoProc
    command: [Qt.resolvedUrl("info.sh").toString().replace("file://", "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = {}
        text.split("\n").forEach(function(line) {
          var eq = line.indexOf("=")
          if (eq > 0) next[line.slice(0, eq)] = line.slice(eq + 1)
        })
        root.info = next
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.logo
    fontFamily: "omarchy"
    tooltipText: ""
    onPressed: function(b) { root.toggle() }
  }

  // Squeeze-and-spring on the bar logo whenever the menu opens.
  SequentialAnimation {
    id: logoPulse
    NumberAnimation { target: button; property: "scale"; to: 0.78; duration: 90; easing.type: Easing.OutQuad }
    NumberAnimation { target: button; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 2.6 }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    padding: Style.space(6)

    readonly property real targetWidth: root.page === "menu" ? root.menuWidth : root.aboutWidth
    readonly property real targetHeight: root.page === "menu" ? menuColumn.implicitHeight
      : root.page === "about" ? aboutColumn.implicitHeight
      : confirmColumn.implicitHeight
    property real shownWidth: targetWidth
    property real shownHeight: targetHeight
    Behavior on shownWidth { enabled: root.sizeAnimated; NumberAnimation { duration: 340; easing.type: Easing.OutQuint } }
    Behavior on shownHeight { enabled: root.sizeAnimated; NumberAnimation { duration: 340; easing.type: Easing.OutQuint } }
    contentWidth: Math.round(shownWidth)
    contentHeight: panel.fittedContentHeight(Math.round(shownHeight))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.blinking
      onMoveRequested: function(dx, dy) { if (root.page === "menu" && dy !== 0) root.moveSelection(dy) }
      onActivateRequested: {
        if (root.page === "menu") root.activate(root.selected)
        else if (root.page === "confirm" && root.pending) root.run(root.pending.cmd)
      }
      onCloseRequested: root.page !== "menu" ? root.page = "menu" : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Item {
        anchors.fill: parent
        clip: true

        // -------------------------------------------------------- menu
        Item {
          id: menuPage
          readonly property bool current: root.page === "menu"
          width: root.menuWidth
          height: menuColumn.implicitHeight
          visible: opacity > 0.01
          opacity: current ? 1 : 0
          x: current ? 0 : -Style.space(36)
          Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
          Behavior on x { NumberAnimation { duration: 320; easing.type: Easing.OutQuint } }

          // One highlight for all rows: it glides to the hovered row and
          // fades away when the pointer leaves the list.
          Rectangle {
            id: highlightBar
            property real blinkOpacity: 1
            readonly property Item target: rows.count > 0 && root.selected >= 0 ? rows.itemAt(root.selected) : null
            property real lastY: 0
            onTargetChanged: if (target) lastY = target.y
            width: parent.width
            height: root.rowHeight
            y: target ? target.y : lastY
            radius: Style.space(5)
            color: root.highlight
            opacity: (target ? 1 : 0) * blinkOpacity
            scale: target ? 1 : 0.97
            Behavior on y { enabled: highlightBar.opacity > 0.05; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on opacity { enabled: !root.blinking; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
          }

          Column {
            id: menuColumn
            width: parent.width

            Repeater {
              id: rows
              model: root.items
              delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool isSelected: root.selected === index
                width: menuColumn.width
                height: modelData.separator ? Style.space(9) : root.rowHeight

                // Cascade: each row drops in a beat after the one above.
                opacity: root.revealed ? 1 : 0
                transform: Translate {
                  y: root.revealed ? 0 : -Style.space(8)
                  Behavior on y {
                    SequentialAnimation {
                      PauseAnimation { duration: root.revealed ? row.index * 22 : 0 }
                      NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.4 }
                    }
                  }
                }
                Behavior on opacity {
                  SequentialAnimation {
                    PauseAnimation { duration: root.revealed ? row.index * 22 : 0 }
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                  }
                }

                Rectangle {
                  visible: row.modelData.separator === true
                  anchors.verticalCenter: parent.verticalCenter
                  x: Style.space(8)
                  width: parent.width - Style.space(16)
                  height: 1
                  color: root.separatorColor
                }

                Text {
                  visible: !row.modelData.separator
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10) + (row.isSelected ? Style.space(2) : 0)
                  anchors.verticalCenter: parent.verticalCenter
                  text: row.modelData.label || ""
                  color: row.isSelected ? root.highlightText : root.fg
                  font.family: root.textFont
                  font.pixelSize: Style.font.subtitle
                  Behavior on color { ColorAnimation { duration: 120 } }
                  Behavior on anchors.leftMargin { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                }

                MouseArea {
                  enabled: !row.modelData.separator && !root.blinking
                  anchors.fill: parent
                  hoverEnabled: true
                  onEntered: root.selected = row.index
                  onExited: if (root.selected === row.index && !root.blinking) root.selected = -1
                  onClicked: root.activate(row.index)
                }
              }
            }
          }
        }

        // ------------------------------------------------------- about
        Column {
          id: aboutColumn
          readonly property bool current: root.page === "about"
          width: root.aboutWidth
          topPadding: Style.space(18)
          bottomPadding: Style.space(12)
          spacing: Style.space(4)
          visible: opacity > 0.01
          opacity: current ? 1 : 0
          x: current ? 0 : Style.space(36)
          Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
          Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutQuint } }

          Text {
            id: aboutLogo
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.logo
            font.family: "omarchy"
            font.pixelSize: Style.space(64)
            color: root.fg
            scale: aboutColumn.current ? 1 : 0.4
            rotation: aboutColumn.current ? 0 : -25
            Behavior on scale { NumberAnimation { duration: 560; easing.type: Easing.OutBack; easing.overshoot: 2.2 } }
            Behavior on rotation { NumberAnimation { duration: 620; easing.type: Easing.OutBack; easing.overshoot: 1.6 } }
          }
          Item { width: 1; height: Style.space(10) }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.info.model || "Omarchy"
            color: root.fg
            font.family: root.textFont
            font.pixelSize: Style.font.heading
            font.bold: true
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.info.host || ""
            color: root.dimText
            font.family: root.textFont
            font.pixelSize: Style.font.bodySmall
          }
          Item { width: 1; height: Style.space(12) }

          Repeater {
            model: [
              ["Chip", root.info.cpu],
              ["Speicher", root.info.memory],
              ["Grafik", root.info.gpu],
              ["Festplatte", root.info.disk],
              ["Omarchy", root.info.omarchy],
              ["Kernel", root.info.kernel],
              ["Laufzeit", root.info.uptime]
            ]
            delegate: Row {
              id: fact
              required property var modelData
              required property int index
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(8)
              // Facts slide up one after another once the card is in.
              opacity: aboutColumn.current ? 1 : 0
              transform: Translate {
                y: aboutColumn.current ? 0 : Style.space(10)
                Behavior on y {
                  SequentialAnimation {
                    PauseAnimation { duration: aboutColumn.current ? 140 + fact.index * 40 : 0 }
                    NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                  }
                }
              }
              Behavior on opacity {
                SequentialAnimation {
                  PauseAnimation { duration: aboutColumn.current ? 140 + fact.index * 40 : 0 }
                  NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                }
              }
              Text {
                width: Style.space(80)
                horizontalAlignment: Text.AlignRight
                text: fact.modelData[0]
                color: root.fg
                font.family: root.textFont
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
              Text {
                width: Style.space(180)
                text: fact.modelData[1] || "—"
                color: root.dimText
                font.family: root.textFont
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
          }

          Item { width: 1; height: Style.space(14) }
          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: moreLabel.implicitWidth + Style.space(24)
            height: Style.space(24)
            radius: height / 2
            color: moreArea.containsMouse ? root.softHover : root.softFill
            scale: moreArea.pressed ? 0.94 : 1
            Behavior on color { ColorAnimation { duration: 140 } }
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
            Text {
              id: moreLabel
              anchors.centerIn: parent
              text: "Weitere Infos …"
              color: root.fg
              font.family: root.textFont
              font.pixelSize: Style.font.bodySmall
            }
            MouseArea {
              id: moreArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.run("omarchy-launch-about")
            }
          }
        }

        // ----------------------------------------------------- confirm
        Column {
          id: confirmColumn
          readonly property bool current: root.page === "confirm"
          width: root.aboutWidth
          topPadding: Style.space(16)
          bottomPadding: Style.space(10)
          spacing: Style.space(14)
          visible: opacity > 0.01
          opacity: current ? 1 : 0
          x: current ? 0 : Style.space(36)
          Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
          Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutQuint } }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.logo
            font.family: "omarchy"
            font.pixelSize: Style.space(40)
            color: root.fg
            scale: confirmColumn.current ? 1 : 0.5
            Behavior on scale { NumberAnimation { duration: 480; easing.type: Easing.OutBack; easing.overshoot: 2.4 } }
          }
          Text {
            width: parent.width - Style.space(20)
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.pending ? root.pending.title : ""
            color: root.fg
            font.family: root.textFont
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(8)

            Repeater {
              model: [
                { label: "Abbrechen", primary: false },
                { label: root.pending ? root.pending.confirm : "", primary: true }
              ]
              delegate: Rectangle {
                id: choice
                required property var modelData
                required property int index
                width: Style.space(118)
                height: Style.space(28)
                radius: Style.space(7)
                color: modelData.primary ? root.highlight : (choiceArea.containsMouse ? root.softHover : root.softFill)
                opacity: modelData.primary && choiceArea.containsMouse ? 0.85 : 1
                scale: choiceArea.pressed ? 0.94 : 1
                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on opacity { NumberAnimation { duration: 140 } }
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                // Buttons rise in after the question.
                transform: Translate {
                  y: confirmColumn.current ? 0 : Style.space(12)
                  Behavior on y {
                    SequentialAnimation {
                      PauseAnimation { duration: confirmColumn.current ? 120 + choice.index * 60 : 0 }
                      NumberAnimation { duration: 360; easing.type: Easing.OutBack; easing.overshoot: 1.6 }
                    }
                  }
                }
                Text {
                  anchors.centerIn: parent
                  text: choice.modelData.label
                  color: choice.modelData.primary ? root.highlightText : root.fg
                  font.family: root.textFont
                  font.pixelSize: Style.font.body
                }
                MouseArea {
                  id: choiceArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: choice.modelData.primary ? root.run(root.pending.cmd) : root.page = "menu"
                }
              }
            }
          }
        }
      }
    }
  }
}
