# Active mode — analysis of the existing app (M0)

Milestone 0 of `SPEC-Aktiv-Modus.md`: what exists, what gets reused, which
engine and parser the active mode is built on, and where the spec collides
with the app as it is. Written before any code.

## 1. What mdview is

| | |
|---|---|
| Runtime | Python 3 + GTK 3 + **WebKit2GTK 4.1** (2.52). One `WebView` per window, one HTML shell per window. Not a browser, not Electron, not Tauri. Linux only |
| Files | `mdview.py` (1237 lines: windows, files, D-Bus, theme), `viewer.js` (1732 lines: renderer, source editor, sidebar, chrome), `viewer.css` (731 lines), `vendor/` (minified libraries), `bin/mdview` (launcher) |
| Framework | None. Vanilla JS in one IIFE, no modules, no bundler, no build step. State lives in closure variables (`current`, `mode`, `edPath`, `savedText` …) |
| Page ↔ Python | Python calls `MdView.<fn>(json…)`; the page posts JSON to `window.webkit.messageHandlers.mdview` |
| Security | CSP `default-src 'none'`, scripts only with a per-load nonce. Document HTML is rendered unsanitised (`html: true`); the CSP is what keeps scripts in a note from running |
| Look | Colours from the Omarchy theme (`--c-*`, live reload), motion from `~/.local/share/henri-ui/motion.css` (injected, live reload). `viewer.css` carries no motion numbers of its own |
| Tests, docs, settings dialog, i18n | None of them exist. UI strings are English, inline |

### Libraries in use

| Purpose | Library | Notes |
|---|---|---|
| Markdown | **markdown-it 14.1.0** | `html: true, linkify: true, typographer: false`; `breaks: true` inside an Obsidian vault |
| Plugins | footnote, deflist, mark (`==x==`), sub, sup, abbr, emoji (`:smile:`) | |
| Math | **KaTeX** (`throwOnError: false, strict: "ignore", output: "html"`) | own inline rule (`$…$`, `$$…$$` with the Pandoc money checks) and block rule; ` ```math ` fences too |
| Code | **highlight.js**, colours mapped onto the theme's ANSI palette | |
| Diagrams | Mermaid, loaded on demand (2.7 MB), cached per source | |
| Frontmatter | js-yaml → "Properties" table (`<details class="props">`) | stripped before parsing |

### What the reading view renders beyond CommonMark + GFM (spec §21.1)

Wikilinks `[[note#heading|alias]]`, embeds `![[file]]` (images, audio, video,
transcluded notes up to depth 2), `#tags`, callouts (`> [!note]+ Title`,
Obsidian and GitHub, foldable), task states other than `x` (`[/]`, `[-]`, `[?]`
…), `==highlight==`, `~sub~`, `^sup^`, definition lists, abbreviations, emoji
shortcodes, footnotes, `%%comments%%` (removed before parsing), Mermaid,
` ```math `, block ids (`^id`). Section 6 below decides inline vs. island for
each.

### The two modes today

- **Read** (`#content`): `md.render()` → `innerHTML`. Every block carries
  `data-line` (source line), which anchors the scroll position across reloads
  and mode switches. Clickable: links, wikilinks, task checkboxes (Python
  rewrites that one line of the file), copy button on code.
- **Edit** (`#editor`): a transparent `<textarea>` with a syntax-coloured
  backdrop, one `<div class="ln">` per source line. Native caret, IME and
  undo; `Ctrl+B/I/K`, Tab indent, Enter continues lists.
- **Switching**: one toolbar button (pencil, `aria-pressed`) and `Ctrl+E`.
  The two views crossfade (`--dur-fast`), the top visible source line stays in
  place, the caret lands on that line on first entry. Not kept: caret ↔
  rendered position, undo across the switch, last mode (always opens reading).

### Loading, saving, integrity

- Load: Python reads bytes, decodes UTF-8 with `errors="replace"`; a file that
  is not valid UTF-8, not writable or over 2 MB is read-only.
- The page normalises `\r\n` and lone `\r` to `\n` on load. On save Python
  writes CRLF everywhere if the old file contained any CRLF. **Mixed line
  endings and lone `\r` are therefore not preserved today** (spec §13).
- A BOM survives (it stays in the text as U+FEFF), but frontmatter behind a
  BOM is not recognised.
- Save: autosave 800 ms after the last keystroke, on blur, on mode switch, on
  leaving the note or window. Written in place (no temp file + rename).
  `Ctrl+S` flushes and shows a "Saved" toast.
- External change: file monitor → re-render keeping scroll. While editing:
  adopted if there are no unsaved edits, otherwise "keeping your edits".
- Reading mode writes the file in two cases: task toggle, image pasted with
  `Ctrl+V` (appended to the end).
- Images: pasted images are saved next to the note (`pasted-<date>.png`,
  `![](…)`) or into the vault's attachment folder (`![[Pasted image ….png]]`).
  No Base64. This stays as it is (spec §7.5, §21.4).
- Undo: only the textarea's native stack. Nothing to hook a shared history
  into (spec §21.3).

## 2. Engine and parser

**ProseMirror** (model, state, view, transform, history, keymap, inputrules,
commands, gapcursor, schema-list, tables) as the spec recommends. No Tiptap
(no framework here) and no Milkdown (it is remark-based, see below).

**Parser: markdown-it, the same instance configuration as the reading view —
not remark.** The spec recommends remark for the model and allows the
alternative of reusing the view's pipeline. Reasons for deviating:

- The reading view's output is defined by markdown-it plus nine custom rules
  (math, wikilinks, embeds, tags, callouts, task states, anchors, fences,
  links) and seven plugins. A remark model would mean a second implementation
  of every one of them, and principle 2.4 (active looks exactly like reading)
  would rest on two parsers agreeing on every edge case.
- `prosemirror-markdown` builds its document from markdown-it tokens, so one
  parse feeds both the reading view and the editor model.
- The price: markdown-it gives block positions as line ranges (`token.map`)
  and no inline positions. Block ranges are all the source-preservation layer
  needs (blocks are line-aligned). For inline fidelity the tokens already
  carry the delimiter used (`markup`: `*` vs `_`, `**` vs `__`, fence
  characters, list markers) and, with the `text_join` rule switched off for
  the model parse, the original spelling of escapes and entities. Our own
  inline rules (wikilink, math, tag) get the raw source added to their token.

**Dialog editor: CodeMirror 6** (spec recommendation). The existing edit mode
is a textarea, so there is no editor to reuse.

**How they get into an app without a build step:** the same way Mermaid
already is — one prebuilt, minified file per library group in `vendor/`
(`prosemirror.min.js`, `codemirror.min.js`), built by a script in `tools/`
with pinned npm versions and esbuild, the output committed. Both load on
demand the first time the active mode (or a dialog) is opened, so reading and
editing start exactly as fast as today. The build needs node/npm (present,
via mise); running the app does not.

## 3. Architecture in this codebase

```
Python (unchanged roles)            page
  bytes ── text + exact flag ──►  Document store: source string, per-line
  ◄── save {text, exact} ──────   endings, final newline, dirty
                                     │ split (markdown-it token.map)
                                     ▼
                                  Blocks: [{id, type, from, to, raw, dirty}]
                                  + separator slices between them
                                     │ per block: tokens → ProseMirror nodes
                                     ▼
                                  ProseMirror view in #active
                                  text blocks editable, islands = NodeViews
                                  that call the reading view's own renderer
```

- **Source preservation**: the store keeps the file's text split into block
  slices and separator slices that concatenate to the original. A transaction
  marks the top-level blocks it touches as dirty; serialising writes `raw` for
  every clean block and the serializer's output for dirty ones. Lists and
  block quotes apply the same rule to their children.
- **Islands render through `md.renderer`** with the block's own source, so
  code, math, Mermaid, properties, HTML blocks and embeds are identical to the
  reading view by construction, including the caches.
- **Text blocks** use the same tags and classes the markdown-it renderer
  emits (`p`, `h1`–`h6`, `ul.contains-task-list`, `li.task-item`, `.callout`,
  `.table-wrap > table` …), so `viewer.css` applies unchanged.
- **Line endings**: the active mode needs byte-exact saving. The store keeps
  the ending of every line and re-applies it; Python gets an `exact` flag and
  then writes the text as given. The existing edit-mode save path (CRLF
  heuristic) is left alone.
- New files: `active/*.js` (store, blocks, schema, serializer, input rules,
  dialogs), `active.css`, `strings.js` (all new UI texts), `tests/`, `tools/`.
  `viewer.js` gains the third mode in `setMode`/`swapView` and the segmented
  control; nothing in the read or edit code paths is rewritten.

## 4. Conflicts between the spec and the app

Each with the resolution chosen under spec §0.6. The first three are Henri's
call and easy to flip; the choice made here is the one that keeps the app
consistent with itself.

| # | Spec says | App / standing rule | Resolution |
|---|---|---|---|
| 1 | UI language German | Every existing string is English; Henri's rule is English UI text | All new strings go into `strings.js` with an `en` and a `de` table. Default **en**, so the app does not mix languages; switching is one line. **Open for Henri** |
| 2 | Own durations and curves (220 ms, `cubic-bezier(0.32, 0.72, 0, 1)`, 12 px radius …) | henri-ui is the single source for motion and radii; "no hand-picked values" | henri-ui tokens. They sit inside the spec's ranges (hover 90/160 ms, popover 240/270 ms). Springs settle visually in ~300 ms. Missing tokens (dialog zoom, island hover tint) are added centrally in henri-ui, not here |
| 3 | macOS semantic colours, `prefers-color-scheme`, system accent | Colours come from the Omarchy theme, switched live | Theme colours. The spec's variable names map onto the existing `--fg`, `--fg2`, `--fg3`, `--line`, `--accent` |
| 4 | Segmented control with three segments | One toggle button | The toggle becomes a three-segment control (Edit · Active · Read). This is the one visible change to the existing chrome; the modes themselves are untouched |
| 5 | `Ctrl+E` may toggle Active ↔ View | `Ctrl+E` toggles Read ↔ Edit today | `Ctrl+E` keeps doing what it does. New: `Ctrl+Alt+1/2/3` (free in Hyprland here) |
| 6 | remark for the model | markdown-it with custom rules | markdown-it, see §2 |
| 7 | Playwright, Chromium + WebKit | The app only ever runs in WebKitGTK; Playwright is not installed | Logic tests (round trip, serializer, input rules, property tests) run in node. End-to-end and screenshot tests run the real app in the nested-compositor rig, driven through a debug hook |
| 8 | VoiceOver, ⌘ shortcuts, system dictionary lookup, Force Touch, Electron vibrancy, native menus | Linux, GTK, WebKitGTK | `Ctrl` for `⌘`. ARIA roles as specified; a screen-reader pass would be Orca. The macOS-only items do not apply |
| 9 | Native spell checking in text blocks | WebKitGTK can do it through enchant, but no hunspell dictionary is installed | Wired up and off until dictionaries are installed (`hunspell-en_us`, `hunspell-de`). **Needs a package install — Henri's call** |
| 10 | One undo history across all modes | Edit mode uses the textarea's native undo | A source-level history in the store. Edit mode keeps native undo and falls back to the shared history only when its own stack is empty, which covers "undo the last active-mode change after switching to the editor" |
| 11 | Settings in the existing settings dialog | There is no settings dialog | The few switches (§18) live in `state.json`; a small preferences popover comes with M5 |
| 12 | `./assets/` for pasted images | Next to the note, or the vault's attachment folder | Existing behaviour stays, as the spec itself says |
| 13 | Clicking a task in View only if it works today | It works today | Unchanged |

## 5. Risks

- **`%%comments%%`** are deleted before parsing. A clean block keeps them (its
  raw slice is untouched); a dirty block would lose them. The model parse
  therefore keeps them as invisible atoms, and a comment spanning several
  blocks turns those blocks into one island.
- **`breaks: true` in vaults**: a soft break shows as a line break there. The
  model keeps soft and hard breaks apart so both serialise back unchanged.
- **Transclusions and embeds** depend on link resolution done in Python
  before rendering; an edited wikilink needs a new resolution round, as the
  edit → read switch does today.
- **Size**: ProseMirror ≈ 250 KB and CodeMirror with languages ≈ 600 KB–1 MB
  minified, both lazy.
- **Where this lives**: tests, a fixture corpus and build tooling are a lot
  for a stow package inside the dotfiles. Moving mdview to its own repository
  would be cleaner; until Henri decides, everything stays under
  `.local/share/mdview/` (`docs/`, `tests/`, `tools/`; `node_modules` ignored).

## 6. Inline or island (spec §21.1)

| Element | In the active mode |
|---|---|
| Wikilink `[[…]]` | Inline atom, popover to edit target and alias (like links) |
| Embed `![[…]]` | Island: image embeds like images, note transclusions with a raw-text dialog |
| `#tag` | Inline text; rendered as a chip once complete |
| `==highlight==`, `~sub~`, `^sup^` | Inline marks |
| Callout | Editable like a block quote; type, fold and title in a small popover on the title |
| Custom task states | Inline; a click cycles ` ` ↔ `x`, other states are kept as written |
| Emoji shortcode | Inline atom, source kept |
| Definition list, abbreviation definition | Island with raw-text dialog (rare, hard to round-trip) |
| Mermaid, ` ```math ` | Island, code dialog with live preview |
| `%%comment%%` | Invisible atom, never dropped |
| Block id `^id` | Kept as trailing text of its block |
| Properties (frontmatter) | Island, YAML dialog |

## 7. Answers to the open points (spec §21)

1. Extensions: listed in §1 and decided in §6.
2. Neither browser, Electron nor Tauri: GTK + WebKitGTK on Linux. No native
   menus from the page; the existing custom menu (`.ui-menu`) is reused.
3. No undo history to attach to; see conflict 10.
4. Images: relative paths against the note's folder, vault attachment folder
   for pastes; see §1.
5. Autosave exists (800 ms). With a dialog open it saves the document without
   the unconfirmed dialog content, as spec §13 asks.

## 8. Plan

Milestones as in spec §17. Development happens on a branch in a separate
worktree and runs under its own D-Bus session, so the installed app keeps
working as it is; a milestone is merged when its tests are green.

Reusable as is: the markdown-it setup and every custom rule, the KaTeX and
highlight.js configuration, the Mermaid loader and cache, scroll anchoring by
`data-line`, the menu/popover/toast components, the find bar, the autosave and
file-watch plumbing, the image-paste path.
