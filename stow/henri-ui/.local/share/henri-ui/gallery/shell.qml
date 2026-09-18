import QtQuick
import Quickshell
import qs.Commons
import "file:///home/henri/.local/share/henri-ui/Motion.js" as Motion
import "file:///home/henri/.local/share/henri-ui" as HUi

// Henri UI gallery — every shared component in one window, to feel and tune them.
//   quickshell -p ~/.local/share/henri-ui/gallery/shell.qml
// Edit Motion.js / a component, then restart the gallery.
ShellRoot {
  id: shell
  property bool autotest: Quickshell.env("HUI_AUTOTEST") === "1"

  FloatingWindow {
    id: win
    title: "Henri UI Gallery"
    implicitWidth: 760
    implicitHeight: 560
    color: Color.background

    Item {
    id: canvas
    anchors.fill: parent
    Rectangle { anchors.fill: parent; color: Color.background }

    Column {
      id: page
      x: 24; y: 24
      width: parent.width - 48
      spacing: 18

      Text { text: "Henri UI"; color: Color.foreground; font.family: Style.font.family; font.pixelSize: Style.font.display; font.weight: Font.DemiBold }

      // Menu-bar glyphs: battery (normal · charging · plugged · low)
      Row {
        id: batteries
        spacing: 18
        HUi.BatteryGlyph { height: 12; level: 0.82 }
        HUi.BatteryGlyph { height: 12; level: 0.55; charging: true }
        HUi.BatteryGlyph { height: 12; level: 0.8; plugged: true }
        HUi.BatteryGlyph { height: 12; level: 0.12 }
        HUi.BatteryGlyph { height: 36; level: 0.55; charging: true }
        HUi.BatteryGlyph { height: 36; level: 0.8; plugged: true }
      }

      // Buttons
      Row {
        spacing: 10
        HUi.Button { id: plainBtn; text: "Plain"; onClicked: counter.value++ }
        HUi.Button { text: "Primary"; prominent: true; onClicked: counter.value++ }
        HUi.Button { icon: "󰐕"; onClicked: counter.value++ }
        HUi.Button { text: "Disabled"; enabled: false }
        HUi.Toggle { id: toggle; anchors.verticalCenter: parent.verticalCenter; onToggled: function(on) { details.expanded = on } }
        HUi.CrossfadeText { id: counter; property int value: 0; text: "Klicks: " + value; anchors.verticalCenter: parent.verticalCenter }
      }

      // Collapse
      HUi.Collapse {
        id: details
        expanded: false
        width: page.width
        Column {
          width: parent.width
          spacing: 6
          Repeater {
            model: 3
            Rectangle { width: parent.width; height: 28; radius: Style.space(Motion.radiusRow); color: Util.alpha(Color.foreground, 0.06)
              Text { anchors.centerIn: parent; text: "Details-Zeile " + (index + 1); color: Color.foreground; font.pixelSize: Style.font.body } }
          }
        }
      }

      Row {
        spacing: 10
        HUi.Button { id: menuBtn; text: "Menü öffnen ▾"; onClicked: { menuReveal.place(); menuReveal.open = !menuReveal.open } }
        HUi.Button { id: popBtn; text: "Popover mit Drill-in"; onClicked: { popReveal.place(); popReveal.open = !popReveal.open } }
        HUi.Button { text: "Kacheln neu"; onClicked: { tiles.active = false; Qt.callLater(function() { tiles.active = true }) } }
        HUi.Button { text: "Toast"; onClicked: { toast.open = true; toastTimer.restart() } }
      }

      // Stagger tiles
      Grid {
        id: tiles
        property bool active: true
        columns: 6
        spacing: 8
        Repeater {
          model: 12
          HUi.StaggerIn {
            active: tiles.active
            index: model.index
            width: 110; height: 56
            HUi.Pressable {
              anchors.fill: parent
              radius: Style.space(Motion.radiusControl)
              Rectangle { anchors.fill: parent; radius: Style.space(Motion.radiusControl); color: Util.alpha(Color.foreground, 0.05); z: -1 }
              Text { anchors.centerIn: parent; text: "Kachel " + (model.index + 1); color: Color.foreground; font.pixelSize: Style.font.body }
            }
          }
        }
      }
    }

    // Menu (anchored under its button, grows from the top)
    HUi.Reveal {
      id: menuReveal
      kind: "menu"
      onDismissRequested: open = false
      origin: Item.Top
      function place() { var p = menuBtn.mapToItem(canvas, 0, 0); x = p.x; y = p.y + menuBtn.height + 4 }
      width: menuSurface.implicitWidth; height: menuSurface.implicitHeight
      z: 10
      HUi.Surface {
        id: menuSurface
        role: "menu"; kind: "menu"
        padding: 5
        implicitWidth: menuList.implicitWidth + padding * 2
        implicitHeight: menuList.implicitHeight + padding * 2
        anchors.fill: parent
        HUi.MenuList {
          id: menuList
          x: menuSurface.contentLeftInset; y: menuSurface.contentTopInset
          width: parent.width - menuSurface.contentLeftInset - menuSurface.contentRightInset
          focus: menuReveal.open
          model: [
            { text: "Neues Fenster", icon: "󰖲", shortcut: "Super N" },
            { text: "Duplizieren", icon: "󰆏", shortcut: "Super D" },
            { separator: true },
            { text: "Nicht verfügbar", enabled: false },
            { text: "Löschen", icon: "󰆴", danger: true }
          ]
          onActivated: function(index, entry) { menuReveal.open = false; counter.value++ }
        }
      }
    }

    // Popover with drill-in pages
    HUi.Reveal {
      id: popReveal
      kind: "popover"
      onDismissRequested: open = false
      origin: Item.Top
      function place() { var p = popBtn.mapToItem(canvas, 0, 0); x = p.x; y = p.y + popBtn.height + 6 }
      width: 300; height: popSurface.implicitHeight
      z: 10
      HUi.Surface {
        id: popSurface
        kind: "panel"
        padding: 10
        width: parent.width
        implicitHeight: pages.implicitHeight + padding * 2
        HUi.PageStack {
          id: pages
          x: 10; y: 10
          width: parent.width - 20
          initialItem: mainPage
        }
      }
    }

    Component {
      id: mainPage
      Column {
        spacing: 6
        Text { text: "Einstellungen"; color: Color.foreground; font.pixelSize: Style.font.title; font.weight: Font.DemiBold }
        Repeater {
          model: ["WLAN", "Bluetooth", "Ton"]
          HUi.Pressable {
            id: row
            width: parent.width; height: Style.space(Motion.controlHeight)
            onClicked: pages.push(subPage, { title: modelData })
            Text { x: 8; anchors.verticalCenter: parent.verticalCenter; text: modelData + "  ›"; color: row.contentColor; font.pixelSize: Style.font.body }
          }
        }
      }
    }
    Component {
      id: subPage
      Column {
        id: sub
        property string title
        spacing: 8
        HUi.PageHeader { width: parent.width; title: sub.title; onBack: pages.pop() }
        Repeater { model: 5; Text { text: title + " Option " + (index + 1); color: Util.alpha(Color.foreground, Motion.secondaryTextAlpha); font.pixelSize: Style.font.body } }
      }
    }

    // Toast from the bottom edge
    HUi.Reveal {
      id: toast
      kind: "toast"
      fromY: Motion.toastOffset
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: 20
      width: 260; height: 44
      HUi.Surface {
        anchors.fill: parent
        role: "notifications"; kind: "popover"
        Text { anchors.centerIn: parent; text: "Gespeichert"; color: Color.foreground; font.pixelSize: Style.font.body }
      }
    }
    Timer { id: toastTimer; interval: 1800; onTriggered: toast.open = false }
    }
  }

  // Scripted run for automated checks (HUI_AUTOTEST=1)
  SequentialAnimation {
    running: shell.autotest
    PauseAnimation { duration: 400 }
    ScriptAction { script: { menuReveal.place(); menuReveal.open = true } }
    PauseAnimation { duration: 120 }
    ScriptAction { script: { menuReveal.open = false } }      // interrupt mid-open
    PauseAnimation { duration: 60 }
    ScriptAction { script: { menuReveal.open = true } }       // reopen mid-close
    PauseAnimation { duration: 600 }
    ScriptAction { script: { menuList.move(1); menuList.move(1); console.warn("HUI menu current", menuList.currentIndex) } }
    PauseAnimation { duration: 500 }
    ScriptAction { script: { canvas.grabToImage(function(r) { r.saveToFile(Quickshell.env("HUI_SHOT") + "-menu.png") }) } }
    PauseAnimation { duration: 200 }
    ScriptAction { script: menuList.activate(menuList.currentIndex) }
    PauseAnimation { duration: 700 }
    ScriptAction { script: { console.warn("HUI after activate: menu open", menuReveal.open, "visible", menuReveal.visible, "clicks", counter.value); toggle.flip(); popReveal.place(); popReveal.open = true } }
    PauseAnimation { duration: 700 }
    ScriptAction { script: { popReveal.place(); canvas.grabToImage(function(r) { r.saveToFile(Quickshell.env("HUI_SHOT") + "-page1.png") }) } }
    PauseAnimation { duration: 200 }
    ScriptAction { script: pages.push(subPage, { title: "WLAN" }) }
    PauseAnimation { duration: 180 }
    ScriptAction { script: canvas.grabToImage(function(r) { r.saveToFile(Quickshell.env("HUI_SHOT") + "-mid.png") }) }
    PauseAnimation { duration: 720 }
    ScriptAction { script: { console.warn("HUI page depth", pages.depth, "popover h", popSurface.implicitHeight.toFixed(1), "details h", details.implicitHeight.toFixed(1)); toast.open = true; canvas.grabToImage(function(r) { r.saveToFile(Quickshell.env("HUI_SHOT") + "-popover.png") }) } }
    PauseAnimation { duration: 600 }
    ScriptAction { script: { console.warn("HUI done"); Qt.quit() } }
  }
}
