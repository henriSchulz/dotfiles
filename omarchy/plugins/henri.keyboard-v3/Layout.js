.pragma library
// The keys of the on-screen keyboard (German, as on an iPad) and where they sit. Pure: Keyboard.qml
// draws what place() returns and asks keyAt() which key a finger is on; tests/layout_test.js runs it
// under node.
//
// A key: { label, out } types text, { key } presses a named key (velum-osk: BackSpace, Left …),
// { act } is the keyboard's own (shift, page, hide). w = width in units of a letter key.

function L(c) { return { label: c, out: c, letter: true } }
function K(chars) { return chars.split(" ").map(function (c) { return { label: c, out: c } }) }

var rows = {
  letters: [
    "q w e r t z u i o p ü".split(" ").map(L).concat([{ act: "delete", key: "BackSpace", icon: "delete.left", w: 1.5, fn: true }]),
    "a s d f g h j k l ö ä".split(" ").map(L).concat([{ act: "return", key: "Return", label: "return", w: 1.8, fn: true }]),
    [{ act: "shift", icon: "shift", w: 1.4, fn: true }].concat("y x c v b n m".split(" ").map(L), K(", ."), [{ act: "shift", icon: "shift", w: 1.4, fn: true }]),
    null   // the bottom row, below
  ],
  numbers: [
    K("1 2 3 4 5 6 7 8 9 0").concat([{ act: "delete", key: "BackSpace", icon: "delete.left", w: 1.5, fn: true }]),
    K("- / : ; ( ) € & @ \"").concat([{ act: "return", key: "Return", label: "return", w: 1.8, fn: true }]),
    [{ act: "page", to: "symbols", label: "#+=", w: 1.4, fn: true }].concat(K(". , ? ! ' _ * + ="), [{ act: "page", to: "symbols", label: "#+=", w: 1.4, fn: true }]),
    null
  ],
  symbols: [
    K("[ ] { } # % ^ ~ | \\").concat([{ act: "delete", key: "BackSpace", icon: "delete.left", w: 1.5, fn: true }]),
    K("< > $ £ § ° ß ` ´ …").concat([{ act: "return", key: "Return", label: "return", w: 1.8, fn: true }]),
    [{ act: "page", to: "numbers", label: "123", w: 1.4, fn: true }].concat(K(". , ? ! ' \" - / &"), [{ act: "page", to: "numbers", label: "123", w: 1.4, fn: true }]),
    null
  ]
}

function bottom(page) {
  var other = page === "letters" ? { act: "page", to: "numbers", label: "123" } : { act: "page", to: "letters", label: "ABC" }
  return [
    Object.assign({ w: 1.6, fn: true }, other),
    { key: "Left", icon: "chevron.left", w: 1, fn: true },
    { key: "Right", icon: "chevron.right", w: 1, fn: true },
    { act: "space", out: " ", label: "", w: 5.6 },
    Object.assign({ w: 1.6, fn: true }, other),
    { act: "hide", icon: "keyboard", w: 1.4, fn: true }
  ]
}

// Every key of a page with its box: { key…, id, x, y, w, h } in px of a keyboard `width` wide.
// The rows fill the width; their keys share it by units, `gap` apart.
function place(page, width, s) {
  var list = (rows[page] || rows.letters).slice(0, 3).concat([bottom(page)])
  var out = []
  for (var r = 0; r < list.length; r++) {
    var row = list[r], units = 0
    for (var i = 0; i < row.length; i++) units += row[i].w || 1
    var unit = (width - 2 * s.padX - (row.length - 1) * s.gap) / units
    var x = s.padX, y = s.padTop + r * (s.keyHeight + s.gap)
    for (var j = 0; j < row.length; j++) {
      var k = Object.assign({}, row[j]), w = (k.w || 1) * unit
      k.id = page + ":" + r + ":" + j
      k.x = x; k.y = y; k.w = w; k.h = s.keyHeight
      out.push(k)
      x += w + s.gap
    }
  }
  return out
}

function height(s) { return s.padTop + 4 * s.keyHeight + 3 * s.gap + s.padBottom }

// The key under a point: the nearest one, so the gaps between keys belong to their neighbours
// (a finger between two keys still types). Null outside the keyboard's rows.
function keyAt(keys, x, y, s) {
  var best = null, bd = Infinity
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i]
    var dx = x < k.x ? k.x - x : x > k.x + k.w ? x - k.x - k.w : 0
    var dy = y < k.y ? k.y - y : y > k.y + k.h ? y - k.y - k.h : 0
    var d = dx * dx + dy * dy
    if (d < bd) { bd = d; best = k }
  }
  return bd <= s.gap * s.gap * 4 ? best : null
}

// What a key types with shift as given: letters in capitals, the rest as they are.
function text(k, shifted) {
  if (!k.out) return ""
  return k.letter && shifted ? k.out.toUpperCase() : k.out
}
