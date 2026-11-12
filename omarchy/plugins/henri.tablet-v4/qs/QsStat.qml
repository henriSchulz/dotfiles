import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// A value with its name above (Health, Cycles, Latency …), lab QsPages.jsx Stat.
Column {
  id: s
  property string label: ""
  property string value: ""
  MText { width: s.width; text: s.label; size: "caption"; tone: "secondary" }
  MText { width: s.width; text: s.value !== "" ? s.value : "—"; medium: true }
}
