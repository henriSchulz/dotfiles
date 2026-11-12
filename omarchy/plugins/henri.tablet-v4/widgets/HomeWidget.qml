import QtQuick
import "file:///home/henri/.local/share/velum/qml/Velum"

// One home screen widget by its kind ("photos", "battery", "clock", "tablet"), at the size given.
// The home grid and the picker both use it.
//   HomeWidget { kind: "clock"; width: …; height: … }
// Widgets.js: kinds = the picker's list [[kind, name], …]; span(cells, kind) = [cols, rows].
Item {
  id: hw
  property string kind: ""
  Loader {
    anchors.fill: parent
    sourceComponent: hw.kind === "photos" ? photos : hw.kind === "battery" ? battery : hw.kind === "clock" ? clock : hw.kind === "tablet" ? tablet : blank
  }
  Component { id: photos; PhotosWidget {} }
  Component { id: battery; BatteryWidget {} }
  Component { id: clock; ClockWidget {} }
  Component { id: tablet; TabletWidget {} }
  Component { id: blank; WidgetCard {} }
}
