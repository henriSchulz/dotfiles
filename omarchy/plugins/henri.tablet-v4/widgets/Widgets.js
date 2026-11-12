.pragma library
// The home screen widgets: their kinds in the picker's order with their names, and their span on the
// home grid (from surface.material.widgets.cells, passed in as `cells`).
var kinds = [["photos", "Photos"], ["battery", "Battery"], ["clock", "Clock"], ["tablet", "Tablet"]]
function span(cells, kind) {
  return [cells[kind + "Cols"] || cells.clockCols, cells[kind + "Rows"] || cells.clockRows]
}
