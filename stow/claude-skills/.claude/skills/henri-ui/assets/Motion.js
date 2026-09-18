.pragma library
// Henri UI motion tokens — copy into the plugin root and import:
//   import "Motion.js" as Motion
// Values mirror SKILL.md; change them there first, then here.

// Durations (ms)
var instant = 90
var fast = 160
var base = 240
var slow = 380
var slower = 520

function exit(ms) { return Math.round(ms * 0.7) }

// Bezier curves for `easing.type: Easing.BezierSpline` (Qt wants the end point 1,1 appended)
var easeOut = [0.22, 1, 0.36, 1, 1, 1]
var easeInOut = [0.45, 0, 0.15, 1, 1, 1]
var easeExit = [0.4, 0, 0.7, 0.2, 1, 1]

// Press feedback
var pressScale = 0.97
// Enter/exit scale for menus and popovers
var menuFromScale = 0.96
var popoverFromScale = 0.95
var exitToScale = 0.98
var menuOffsetY = -4

// List stagger
var staggerStep = 15
var staggerMax = 10
function stagger(index) { return Math.min(index, staggerMax) * staggerStep }
