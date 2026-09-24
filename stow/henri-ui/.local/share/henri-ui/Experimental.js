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

var on = false

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

    // ── Material. This is the part that breaks a rule on purpose: henri-ui
    // keeps surfaces at the theme's 0.97 because see-through panels looked
    // wrong. Tahoe's whole point is that they are not, so the experiment
    // turns them into glass and leans on the compositor's blur.
    hairlineAlpha: 0.14,  // default 0.10 — a glass edge catches more light

    glass: true,
    // MacTahoe's own $blur_opacity / $side_blur_opacity. Menus stay denser
    // than panels: they hold small text over whatever is behind them.
    glassAlpha: 0.65,     // panels, popovers, cards
    glassMenuAlpha: 0.75, // menus and their rows
    // Specular top edge — Tahoe has it, GTK cannot draw it, so this number is
    // mine. White veil at the top of a surface, gone by 45 % of its height.
    glassSheen: 0.14,
    // Tiles inside a glass panel are frosted, not a dark wash: the panel's own
    // colour again, so a dark theme gets a dark tile and a light one a light.
    glassTileAlpha: 0.55,
    glassTileHoverAlpha: 0.72,
    // Secondary text has to get darker on glass. Measured: at the usual 0.65
    // it is 3.3:1 over a glass panel sitting on black content, well under the
    // 4.5:1 henri-ui requires; 0.85 is the lowest value that clears it (5.0:1),
    // and it stays a readable 9.5:1 on the normal near-opaque surface.
    secondaryTextAlpha: 0.85
}
