import QtQuick
import Quickshell

// Compiles QML files (with qs.Commons / qs.Ui / henri-ui resolvable) without
// running them — catches syntax errors, unknown types and bad imports before a
// plugin goes live (the shell hot-reloads plugins on every file write).
//   HUI_CHECK="/path/A.qml:/path/B.qml" quickshell -p ~/.local/share/henri-ui/gallery/compilecheck.qml
// Prints "COMPILE OK <file>" / "COMPILE FAIL <file>: <errors>", then
// "COMPILE RESULT <n> failed".
ShellRoot {
  Component.onCompleted: {
    var files = String(Quickshell.env("HUI_CHECK") || "").split(":").filter(function(f) { return f.length > 0 })
    var failed = 0
    for (var i = 0; i < files.length; i++) {
      var c = Qt.createComponent("file://" + files[i], Component.PreferSynchronous)
      if (c.status === Component.Error) {
        failed++
        console.warn("COMPILE FAIL " + files[i] + ": " + c.errorString().replace(/\n/g, " | "))
      } else {
        console.warn("COMPILE OK " + files[i])
      }
    }
    console.warn("COMPILE RESULT " + failed + " failed")
    quitTimer.start()
  }
  // Qt.quit() straight from onCompleted is ignored while the shell is still loading.
  Timer { id: quitTimer; interval: 50; onTriggered: Qt.quit() }
}
