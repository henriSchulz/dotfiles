// The search field as a line of text that can be edited anywhere: a caret that
// moves, a selection, words, cut and paste, undo. The field itself is a string
// the key catcher drives (Menu.qml) — this is what a key does to it.
//
// A state is { text, caret, anchor }: the caret is where typing goes, the
// anchor where a selection began (equal: nothing selected). Every function
// takes a state and returns a new one; none looks at anything else, so they
// run under node as they do in the shell (tests/query_edit_test.js).
.pragma library

function state(text, caret, anchor) {
  var t = String(text || ""), c = Math.max(0, Math.min(t.length, caret === undefined ? t.length : caret))
  return { text: t, caret: c, anchor: Math.max(0, Math.min(t.length, anchor === undefined ? c : anchor)) }
}
function hasSelection(s) { return s.caret !== s.anchor }
function selStart(s) { return Math.min(s.caret, s.anchor) }
function selEnd(s) { return Math.max(s.caret, s.anchor) }
function selected(s) { return s.text.slice(selStart(s), selEnd(s)) }

// Words as a text field counts them: runs of letters and digits, runs of
// anything else that is not blank. Going left lands at a word's start, going
// right at its end.
function isWord(ch) { return /[\p{L}\p{N}_]/u.test(ch) }
function isBlank(ch) { return /\s/.test(ch) }
function wordLeft(text, pos) {
  var i = pos
  while (i > 0 && isBlank(text.charAt(i - 1))) i--
  if (i > 0) {
    var word = isWord(text.charAt(i - 1))
    while (i > 0 && !isBlank(text.charAt(i - 1)) && isWord(text.charAt(i - 1)) === word) i--
  }
  return i
}
function wordRight(text, pos) {
  var i = pos, n = text.length
  while (i < n && isBlank(text.charAt(i))) i++
  if (i < n) {
    var word = isWord(text.charAt(i))
    while (i < n && !isBlank(text.charAt(i)) && isWord(text.charAt(i)) === word) i++
  }
  return i
}
// A character is not always one unit of the string (emoji, rare letters):
// the caret never stops inside one.
function charLeft(text, pos) {
  if (pos <= 0) return 0
  var c = text.charCodeAt(pos - 1)
  return pos >= 2 && c >= 0xDC00 && c <= 0xDFFF && text.charCodeAt(pos - 2) >= 0xD800 && text.charCodeAt(pos - 2) <= 0xDBFF ? pos - 2 : pos - 1
}
function charRight(text, pos) {
  if (pos >= text.length) return text.length
  var c = text.charCodeAt(pos)
  return c >= 0xD800 && c <= 0xDBFF && pos + 1 < text.length ? pos + 2 : pos + 1
}

// The caret somewhere else; extend keeps the anchor (Shift held).
function moveTo(s, pos, extend) {
  var c = Math.max(0, Math.min(s.text.length, pos))
  return { text: s.text, caret: c, anchor: extend ? s.anchor : c }
}
// ← and →: a selection collapses to its near end first, as text fields do.
function left(s, extend, byWord) {
  if (!extend && hasSelection(s) && !byWord) return moveTo(s, selStart(s), false)
  return moveTo(s, byWord ? wordLeft(s.text, s.caret) : charLeft(s.text, s.caret), extend)
}
function right(s, extend, byWord) {
  if (!extend && hasSelection(s) && !byWord) return moveTo(s, selEnd(s), false)
  return moveTo(s, byWord ? wordRight(s.text, s.caret) : charRight(s.text, s.caret), extend)
}
function home(s, extend) { return moveTo(s, 0, extend) }
function end(s, extend) { return moveTo(s, s.text.length, extend) }
function selectAll(s) { return { text: s.text, caret: s.text.length, anchor: 0 } }
function selectWordAt(s, pos) {
  var p = Math.max(0, Math.min(s.text.length, pos))
  // (a double click between words takes the word before it, at the line's end too)
  var from = p < s.text.length && !isBlank(s.text.charAt(p)) ? wordLeft(s.text, charRight(s.text, p)) : wordLeft(s.text, p)
  return { text: s.text, caret: wordRight(s.text, from), anchor: from }
}

function replace(s, from, to, put) {
  var text = s.text.slice(0, from) + put + s.text.slice(to), c = from + put.length
  return { text: text, caret: c, anchor: c }
}
// Typed or pasted: in the selection's place, else at the caret.
function insert(s, put) { return replace(s, selStart(s), selEnd(s), String(put || "")) }
// ⌫ and ⌦: the selection if there is one, else a character (byWord: a word).
function backspace(s, byWord) {
  if (hasSelection(s)) return replace(s, selStart(s), selEnd(s), "")
  return replace(s, byWord ? wordLeft(s.text, s.caret) : charLeft(s.text, s.caret), s.caret, "")
}
function del(s, byWord) {
  if (hasSelection(s)) return replace(s, selStart(s), selEnd(s), "")
  return replace(s, s.caret, byWord ? wordRight(s.text, s.caret) : charRight(s.text, s.caret), "")
}
// Ctrl+U: everything before the caret.
function clearToStart(s) { return replace(s, 0, selEnd(s), "") }
function same(a, b) { return a.text === b.text && a.caret === b.caret && a.anchor === b.anchor }
