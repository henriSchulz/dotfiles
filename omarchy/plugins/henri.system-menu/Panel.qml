import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

// macOS-style Apple menu. The Omarchy logo sits in the bar's left corner and
// opens a plain menu list; "Über diesen Computer" swaps the list for an About
// card, and restart / shut down / log out ask first on a confirm page, like
// the "…" items on macOS.
//
// Motion (henri-ui tokens): rows cascade in on open, the row highlight jumps
// instantly like NSMenu, a chosen command blinks once before it runs (as
// macOS does), pages cross-slide while the popup resizes, and the About logo
// springs in.
Panel {
  id: root
  moduleName: "henri.system-menu"
  ipcTarget: "henri.system-menu"
  manageIpc: false

  readonly property color fg: Color.popups.text
  readonly property color dimText: Util.alpha(fg, Motion.secondaryTextAlpha)
  readonly property color separatorColor: Util.alpha(fg, Motion.hairlineAlpha)
  readonly property color softFill: Util.alpha(fg, Motion.hoverAlpha)
  readonly property color softHover: Util.alpha(fg, Motion.pressedAlpha)
  // Menu selection is theme-authored (cupertino: blue + white text).
  readonly property color highlight: Color.menu.selectedBackground
  readonly property color highlightText: Color.menu.selectedText
  // Primary button on the confirm page.
  readonly property color accent: Color.accent
  readonly property color accentText: Motion.onColor(Color.accent)
  readonly property string textFont: Style.font.family
  readonly property string logo: ""
  readonly property int menuWidth: Style.space(250)
  readonly property int aboutWidth: Style.space(290)
  readonly property int rowHeight: Style.space(Motion.menuItemHeight)
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
  // Blink phase: highlight momentarily off.
  property bool blinkOff: false
  // Bar logo press-squeeze on open (released by logoPulse).
  property bool logoSqueezed: false

  readonly property var items: [
    { icon: "󰋽", label: "Über diesen Computer", page: "about" },
    { separator: true },
    { icon: "󰢻", label: "Systemeinstellungen …", cmd: "omarchy-menu toggle root" },
    { icon: "󱃁", label: "App Store …", cmd: "xdg-terminal-exec --app-id=org.omarchy.terminal omarchy-pkg-install" },
    { separator: true },
    { icon: "󰅝", label: "Sofort beenden …", cmd: "hyprctl kill" },
    { separator: true },
    { icon: "󰖔", label: "Ruhezustand", cmd: "systemctl suspend" },
    { icon: "󰜉", label: "Neustart …", cmd: "omarchy-system-reboot", title: "Möchtest du den Computer jetzt neu starten?", confirm: "Neustart" },
    { icon: "󰐥", label: "Ausschalten …", cmd: "omarchy-system-shutdown", title: "Möchtest du den Computer jetzt ausschalten?", confirm: "Ausschalten" },
    { separator: true },
    { icon: "󰍁", label: "Bildschirm sperren", cmd: "omarchy-system-lock" },
    { icon: "󰍃", label: "Abmelden „" + userName + "“ …", cmd: "omarchy-system-logout", title: "Möchtest du dich jetzt abmelden?", confirm: "Abmelden" }
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
      blinkOff = false
      revealTimer.restart()
      logoSqueezed = true
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
    interval: Motion.exit(Motion.slow)
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

  // The macOS menu blinks the chosen item before acting on it (NSMenu:
  // highlight off, on, then fire).
  SequentialAnimation {
    id: blink
    property var item: null
    ScriptAction { script: root.blinkOff = true }
    PauseAnimation { duration: Motion.flashDuration }
    ScriptAction { script: root.blinkOff = false }
    PauseAnimation { duration: Motion.flashDuration }
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
    scale: logoScale.value
  }

  // Press feedback on the bar logo whenever the menu opens: squeeze
  // (instant), then spring back (snappy).
  HUi.SpringValue { id: logoScale; preset: Motion.snappy; to: root.logoSqueezed ? Motion.pressScale : 1 }
  Timer {
    id: logoPulse
    interval: Motion.instant
    onTriggered: root.logoSqueezed = false
  }

  HUi.PopupPanel {
    id: panel
    kind: "popover"
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
    Behavior on shownWidth { enabled: root.sizeAnimated; NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }
    Behavior on shownHeight { enabled: root.sizeAnimated; NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }
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
          Behavior on opacity { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
          Behavior on x { NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }

          // One highlight for all rows: it jumps to the hovered row and
          // vanishes when the pointer leaves the list — instantly, like NSMenu.
          HUi.Highlight {
            id: highlightBar
            glide: false
            color: root.highlight
            suppressed: root.blinkOff
            target: rows.count > 0 && root.selected >= 0 ? rows.itemAt(root.selected) : null
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
                readonly property bool isSelected: root.selected === index && !root.blinkOff
                width: menuColumn.width
                height: modelData.separator ? Style.space(9) : root.rowHeight

                // Cascade: each row drops in a beat after the one above.
                opacity: root.revealed ? 1 : 0
                transform: Translate {
                  y: root.revealed ? 0 : -Style.space(8)
                  Behavior on y {
                    SequentialAnimation {
                      PauseAnimation { duration: root.revealed ? Motion.stagger(row.index) : 0 }
                      NumberAnimation { duration: root.revealed ? Motion.base : Motion.exit(Motion.base); easing.type: Easing.BezierSpline; easing.bezierCurve: root.revealed ? Motion.easeOut : Motion.easeExit }
                    }
                  }
                }
                Behavior on opacity {
                  SequentialAnimation {
                    PauseAnimation { duration: root.revealed ? Motion.stagger(row.index) : 0 }
                    NumberAnimation { duration: root.revealed ? Motion.base : Motion.exit(Motion.base); easing.type: Easing.BezierSpline; easing.bezierCurve: root.revealed ? Motion.easeOut : Motion.easeExit }
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

                // Symbol column, fixed width so the labels line up.
                Text {
                  id: rowIcon
                  visible: !row.modelData.separator
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(18)
                  horizontalAlignment: Text.AlignHCenter
                  text: row.modelData.icon || ""
                  color: row.isSelected ? root.highlightText : root.fg
                  font.family: Style.font.family
                  font.pixelSize: Style.font.icon
                }

                Text {
                  visible: !row.modelData.separator
                  anchors.left: rowIcon.right
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  text: row.modelData.label || ""
                  // Switches with the highlight, no fade (NSMenu).
                  color: row.isSelected ? root.highlightText : root.fg
                  font.family: root.textFont
                  font.pixelSize: Style.font.subtitle
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
          Behavior on opacity { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
          Behavior on x { NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }

          Text {
            id: aboutLogo
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.logo
            font.family: "omarchy"
            font.pixelSize: Style.space(64)
            color: root.fg
            scale: aboutLogoScale.value
            HUi.SpringValue { id: aboutLogoScale; preset: Motion.snappy; to: aboutColumn.current ? 1 : Motion.popoverFromScale }
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
                    PauseAnimation { duration: aboutColumn.current ? Motion.fast + Motion.stagger(fact.index) : 0 }
                    NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
                  }
                }
              }
              Behavior on opacity {
                SequentialAnimation {
                  PauseAnimation { duration: aboutColumn.current ? Motion.fast + Motion.stagger(fact.index) : 0 }
                  NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
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
            scale: moreScale.value
            HUi.SpringValue { id: moreScale; preset: Motion.snappy; to: moreArea.pressed ? Motion.pressScale : 1 }
            Behavior on color { ColorAnimation { duration: moreArea.containsMouse ? Motion.instant : Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
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
          Behavior on opacity { NumberAnimation { duration: Motion.base; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
          Behavior on x { NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeInOut } }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.logo
            font.family: "omarchy"
            font.pixelSize: Style.space(40)
            color: root.fg
            scale: confirmLogoScale.value
            HUi.SpringValue { id: confirmLogoScale; preset: Motion.snappy; to: confirmColumn.current ? 1 : Motion.popoverFromScale }
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
                radius: Style.space(Motion.radiusControl)
                color: modelData.primary ? root.accent : (choiceArea.containsMouse ? root.softHover : root.softFill)
                opacity: modelData.primary && choiceArea.containsMouse ? 0.85 : 1
                scale: choiceScale.value
                HUi.SpringValue { id: choiceScale; preset: Motion.snappy; to: choiceArea.pressed ? Motion.pressScale : 1 }
                Behavior on color { ColorAnimation { duration: choiceArea.containsMouse ? Motion.instant : Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
                Behavior on opacity { NumberAnimation { duration: choiceArea.containsMouse ? Motion.instant : Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut } }
                // Buttons rise in after the question.
                transform: Translate {
                  y: confirmColumn.current ? 0 : Style.space(12)
                  Behavior on y {
                    SequentialAnimation {
                      PauseAnimation { duration: confirmColumn.current ? Motion.fast + Motion.stagger(choice.index) : 0 }
                      NumberAnimation { duration: Motion.slow; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.easeOut }
                    }
                  }
                }
                Text {
                  anchors.centerIn: parent
                  text: choice.modelData.label
                  color: choice.modelData.primary ? root.accentText : root.fg
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
