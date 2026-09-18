import QtQuick
import QtTest
import Quickshell
import "file:///home/henri/.local/share/henri-ui" as HUi

// Input test with real key/mouse events: Esc closes, Esc in drill-in goes back
// first, click outside closes, clicks on the surface still work.
//   QT_QPA_PLATFORM=offscreen quickshell -p ~/.local/share/henri-ui/gallery/keytest.qml
// Must end with "RESULT ALL PASS".
ShellRoot {
  FloatingWindow {
    id: win
    implicitWidth: 400; implicitHeight: 400
    Item { id: bg; anchors.fill: parent }

    HUi.Reveal {
      id: menu
      kind: "menu"
      property int dismissals: 0
      onDismissRequested: { dismissals++; open = false }
      width: 200; height: 150
      property int activations: 0
      HUi.MenuList { id: list; width: 200; focus: true; model: [{ text: "A" }, { text: "B" }]; onActivated: menu.activations++ }
    }

    HUi.Reveal {
      id: pop
      kind: "popover"
      property int dismissals: 0
      onDismissRequested: { dismissals++; open = false }
      width: 200; height: 200
      HUi.PageStack { id: pages; width: 200; focus: true; initialItem: Item { implicitHeight: 50 } }
    }
    Component { id: sub; Item { implicitHeight: 80 } }
  }

  TestEvent { id: ev }
  property var failures: []
  function check(cond, msg) { console.warn((cond ? "PASS " : "FAIL ") + msg); if (!cond) failures.push(msg) }
  function key(k) { ev.keyClick(k, Qt.NoModifier, -1) }

  SequentialAnimation {
    running: true
    PauseAnimation { duration: 300 }
    ScriptAction { script: { menu.open = true } }
    PauseAnimation { duration: 100 }
    ScriptAction { script: {
      check(list.activeFocus, "menu list has keyboard focus when opened")
      var before = list.currentIndex
      key(Qt.Key_Down)
      check(list.currentIndex !== before, "arrow keys reach the list")
      key(Qt.Key_Escape)
      check(menu.dismissals === 1 && !menu.open, "Esc closes the menu")
    } }
    PauseAnimation { duration: 600 }
    ScriptAction { script: {
      check(!menu.visible, "menu hidden after fade-out")
      key(Qt.Key_Escape)
      check(menu.dismissals === 1, "Esc on a closed menu does nothing")
      pop.open = true
    } }
    PauseAnimation { duration: 100 }
    ScriptAction { script: pages.push(sub) }
    PauseAnimation { duration: 700 }
    ScriptAction { script: {
      check(pages.depth === 2, "drill-in pushed")
      key(Qt.Key_Escape)
    } }
    PauseAnimation { duration: 700 }
    ScriptAction { script: {
      check(pages.depth === 1 && pop.dismissals === 0 && pop.open, "first Esc goes back a page, popover stays")
      key(Qt.Key_Escape)
      check(pop.dismissals === 1 && !pop.open, "second Esc closes the popover")
    } }
    PauseAnimation { duration: 600 }
    ScriptAction { script: { menu.open = true } }
    PauseAnimation { duration: 400 }
    ScriptAction { script: {
      ev.mouseClick(bg, 350, 350, Qt.LeftButton, Qt.NoModifier, -1)
      check(menu.dismissals === 2 && !menu.open, "click outside closes the menu")
    } }
    PauseAnimation { duration: 600 }
    ScriptAction { script: {
      ev.mouseClick(bg, 350, 350, Qt.LeftButton, Qt.NoModifier, -1)
      check(menu.dismissals === 2, "click outside a closed menu does nothing")
      menu.open = true
    } }
    PauseAnimation { duration: 400 }
    ScriptAction { script: { ev.mouseClick(bg, 30, 10, Qt.LeftButton, Qt.NoModifier, -1) } }
    PauseAnimation { duration: 300 }
    ScriptAction { script: {
      check(menu.activations === 1, "click on a menu entry activates it")
      check(menu.dismissals === 2, "…and is not treated as outside")
      console.warn("RESULT", failures.length === 0 ? "ALL PASS" : failures.length + " FAILED")
      Qt.quit()
    } }
  }
}
