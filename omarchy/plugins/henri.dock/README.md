# henri.dock

The macOS Dock for the Omarchy shell (Quickshell on Hyprland), built after
`docs/dock-spec.md`. Look from **apple-ui** (`Apple.dock`, `Apple.dockPalette`),
motion from **henri-ui** (`Motion.dock` springs and durations, `HUi.*` components).
Replaces omadock.

## What it does

- App area: file manager first (locked), pinned apps (`~/.config/omarchy/dock.json`,
  `pinned`), running apps, then a separator, up to three recent apps, then the
  document area: folder stacks, files, minimized windows, Trash (locked).
- Magnification with the spec's cosine falloff against the unmagnified layout,
  overdamped spring (400/30/0.4), icons grow away from the screen edge, the glass
  background widens with them and stays centred.
- Hover label with arrow, launch bounce, attention bounce (`urgent` windows or
  `omarchy-shell dock requestAttention <app>`), running indicator, badges
  (`omarchy-shell dock setBadge <id> <text>`).
- Drag to reorder (gap opens with a spring, tile glides into the slot), drag out to
  remove ("Remove" label after 400 ms), external files dropped on apps / folders /
  Trash / the document area.
- Context menus for apps, folders, files, separator, Trash and minimized windows,
  with submenus; Alt turns "Quit" into "Force Quit" live.
- Folder stacks as fan, grid or list; "Automatic" picks fan up to 12 entries.
- Minimize (`Super+M`, `omarchy-shell dock minimizeActive`): the window is parked on
  `special:minimized` and its snapshot flows into the dock with the genie effect (48
  strips through a funnel) or the scale effect; the tile shows the snapshot with the
  app icon; click or "Restore" plays it back. `minimizeActiveSlow` = 10× slower.
  "Minimize into application icon" targets the app tile instead.
- Auto-hide (`Super+Alt+D`) with a 3 px trigger zone at the edge; position bottom,
  left or right (the dock slides out at the old edge and in at the new one).
- Drag the separator to resize (Alt snaps to 16/32/48/64/128; Shift + drag to a
  screen edge moves the dock there).
- Keyboard: `Ctrl+F3` focuses the dock, ←/→ (↑/↓ vertical) move with magnification,
  ⏎/Space activate, ↑ opens the menu, Esc leaves. Accessible names on every tile.
- Settings popover (separator menu → Dock Settings…, `omarchy-shell dock openSettings`),
  persisted in `~/.config/omarchy/henri.dock.json`. Reduce motion: hops become
  opacity pulses, magnification snaps, minimize crossfades, auto-hide fades.

## Architecture

Two layer surfaces on the dock's screen: `henri-dock` is only the glass background
(thin, click-through, blurred by the `layer_rule` in `looknfeel.lua`);
`henri-dock-overlay` is full-screen, unblurred and input-masked to the dock zone
and open popups — it carries tiles, label, menus, stacks, settings, the drag ghost
and the minimize effect. Everything is computed along a main axis and a cross
axis and mapped in `rectFor()`, so all three positions share one code path.

Layout runs once per frame only while something moves (pointer, springs, drag,
hide); tiles keep their identity in a `ListModel` of ids, the data lives in
`items`, so springs survive every rebuild.

## Testing without touching the live shell

`~/.cache/henri-dock-rig/rig.sh start|sync|shell|call dock <fn>|shot <name>|stop`
runs a nested Hyprland + shell on a headless output with a fake HOME. IPC probes:
`probeNoGrab` (the focus grab clears at once on headless outputs), `probeHover x y`,
`probePress/Move/Release`, `probeMenu i`, `probeStack i`, `probeLaunching i`,
`probeKey next|prev|activate|menu`, `probeReveal`, `probeFx`, `probeMenuState`,
`state`.
