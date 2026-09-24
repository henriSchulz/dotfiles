.pragma library
// Experimental macOS mode — the one switch the Control Center flips.
//
// Motion.js imports this file and, while `on` is true, replaces the tokens
// below with these values. Every plugin imports Motion.js, so the whole shell
// follows at once: bar popups, menus, Control Center, Spotlight, Mission
// Control, the switcher, the HUD.
//
// The numbers are macOS Tahoe's, read off MacTahoe's src/sass/_variables.scss
// ($wm_radius 26, $po_radius 16, $mn_radius 14, $bd_radius 10, $bt_radius 6,
// $menuitem_size 32). Shape and size only — motion stays henri-ui's, because
// MacTahoe's own curves are Material Design (0.4, 0, 0.2, 1 at 100/150 ms),
// not macOS, and would undo the seven motion laws rather than extend them.
//
// This table is meant to be edited: tune a number, save, the shell restarts
// itself (henri-ui-sync watches this folder) and you see it. The switch only
// ever rewrites the `on` line, so nothing here is lost by toggling.
//
// Add a token: put it here AND in the apply block at the end of Motion.js —
// a .pragma library cannot assign to its own variables by name.

var on = true

var tokens = {
    // ── Shape. Tahoe is markedly rounder than what henri-ui set for Sonoma.
    radiusPanel: 26,      // default 14 — panels, sheets, big surfaces
    radiusPopover: 16,    // default 10 — popovers and menus
    radiusControl: 10,    // default 8  — buttons, fields
    radiusRow: 8,         // default 6  — menu and list rows
    radiusChip: 6,        // default 5  — small chips

    // ── Size. Tahoe menus and controls are roomier.
    menuItemHeight: 32,   // default 26
    controlHeight: 32,    // default 28

    // ── Material.
    hairlineAlpha: 0.12   // default 0.10 — MacTahoe's divider alpha
}
