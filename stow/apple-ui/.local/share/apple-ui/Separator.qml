import QtQuick
import "Apple.js" as Apple

// Haarlinie zwischen Listenabschnitten.
Rectangle {
  readonly property var m: Apple.material(this)
  width: parent ? parent.width : 0
  height: 1
  color: m.hairline
}
