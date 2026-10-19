// node tests/query_edit_test.js — the search field's editing, key by key.
const fs = require("fs"), path = require("path"), assert = require("assert"), vm = require("vm");
const src = fs.readFileSync(path.join(__dirname, "..", "QueryEdit.js"), "utf8").replace(/^\.pragma library$/m, "");
const E = {};
vm.runInNewContext(src + "\nObject.assign(out, { state, hasSelection, selected, left, right, home, end, selectAll, selectWordAt, insert, backspace, del, clearToStart, moveTo, wordLeft, wordRight });", { out: E });
const st = (text, caret, anchor) => E.state(text, caret, anchor);
const is = (s, text, caret, anchor = caret) => assert.deepStrictEqual({ ...s }, { text, caret, anchor });

// typing in the middle, and over a selection
is(E.insert(st("helo", 3), "l"), "hello", 4);
is(E.insert(st("hello world", 11, 6), "there"), "hello there", 11);
is(E.insert(st("abc", 0, 3), "x"), "x", 1);
// the caret: by character, by word, to the ends; a selection collapses first
is(E.left(st("abc", 2)), "abc", 1);
is(E.left(st("abc", 0)), "abc", 0);
is(E.right(st("abc", 3)), "abc", 3);
is(E.left(st("abcdef", 5, 2)), "abcdef", 2);
is(E.right(st("abcdef", 2, 5)), "abcdef", 5);
is(E.left(st("open the  file.txt", 18), false, true), "open the  file.txt", 15);  // txt
is(E.left(st("open the  file.txt", 15), false, true), "open the  file.txt", 14);  // .
is(E.left(st("open the  file.txt", 10), false, true), "open the  file.txt", 5);   // over the blanks to "the"
is(E.right(st("open the  file.txt", 4), false, true), "open the  file.txt", 8);
is(E.right(st("größe ändern", 0), false, true), "größe ändern", 5);               // letters of any language are a word
is(E.home(st("abc", 2)), "abc", 0);
is(E.end(st("abc", 1)), "abc", 3);
// selecting: Shift keeps the anchor
is(E.left(st("abc", 3), true), "abc", 2, 3);
is(E.left(E.left(st("abc", 3), true), true), "abc", 1, 3);
is(E.right(st("abc", 1, 3), true), "abc", 2, 3);
is(E.home(st("abc", 2), true), "abc", 0, 2);
is(E.left(st("one two", 7), true, true), "one two", 4, 7);
is(E.selectAll(st("abc", 1)), "abc", 3, 0);
assert.strictEqual(E.selected(st("hello world", 11, 6)), "world");
is(E.selectWordAt(st("open the file", 0), 6), "open the file", 8, 5);
is(E.selectWordAt(st("open the file", 0), 13), "open the file", 13, 9);
is(E.selectWordAt(st("open the file", 0), 4), "open the file", 4, 0); // between words: the one before
// deleting
is(E.backspace(st("abc", 2)), "ac", 1);
is(E.backspace(st("abc", 0)), "abc", 0);
is(E.backspace(st("hello world", 11, 5)), "hello", 5);
is(E.backspace(st("open the file", 13), true), "open the ", 9);
is(E.backspace(st("open the ", 9), true), "open ", 5);
is(E.del(st("abc", 1)), "ac", 1);
is(E.del(st("abc", 3)), "abc", 3);
is(E.del(st("open the file", 5), true), "open  file", 5);
is(E.clearToStart(st("hello world", 6)), "world", 0);
// a character of two units is one step, and one deletion
is(E.left(st("a😀b", 3)), "a😀b", 1);
is(E.right(st("a😀b", 1)), "a😀b", 3);
is(E.backspace(st("a😀b", 3)), "ab", 1);
is(E.del(st("a😀b", 1)), "ab", 1);
// out of range is brought in
is(st("abc", 99, -4), "abc", 3, 0);
console.log("query edit: ok");
