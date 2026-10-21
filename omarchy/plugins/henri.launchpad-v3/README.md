# henri.launchpad-v3

Full-screen app launcher on Velum, a rebuild of LaunchMe's / macOS Launchpad's
core loop for Omarchy. Spec, recon and design: `~/Projects/launchpad/replica/`.

- every installed app (`DesktopEntries`, minus Omarchy's launcher hides) on the
  blurred wallpaper, paged (`columns × rows`), page dots
- type to search (Spotlight's fuzzy ranking + alias table), ↑↓ Enter
- folders: drop an app on an app, open, rename, drag out (the last app out dissolves it)
- edit mode: long-press or context menu; drag to reorder and across pages (screen edge),
  badge hides an app; hidden apps stay searchable and come back from Settings
- settings sheet: grid, icon size, titles, search position, background, blur, hidden apps
- layout in `~/.config/omarchy/launchpad/layout.json` (atomic writes, never written when
  unreadable, `.bak-<ts>` on a version change)

Colours, motion: `surface.launchpad` in `tokens/surfaces/surfaces.tokens.json`.
Geometry: `Look.js`. Model: `LayoutModel.js` (pure, `node tests/layout_model_test.js`).
`FuzzySearch.js` / `AppAliases.js` are copies of henri.menu-v3's.

## Calls

```sh
omarchy-shell shell toggle henri.launchpad-v3 '{}'          # the bind
omarchy-shell shell call henri.launchpad-v3 state ""        # JSON state
# tests: setQuery, goPage, edit, folderOpen, select, showSettings, layoutJson,
#        testMove "app:a 1 0" | "app:a onto app:b", testHide, testUnhide, testContext
```

Payload `{"query":"…"}` starts with a search, `{"screen":"NAME"}` picks an output.

## Not live yet

Release on Henri's word: enable in shell.json, Hyprland bind (e.g. via a `custom`
event like henri.menu-v3 for the lowest latency), sync to dotfiles.
