# Window Switcher

Alt+Tab through the windows of the **current workspace**, with live miniatures.

Hold Alt and press Tab: a row of window previews appears, the window in front
on the left, then the one used before it. Every further Tab moves the selection
(Shift+Tab goes back), letting go of Alt switches, Esc cancels. A quick tap
switches straight to the previous window without the row ever flashing up.

It used to be a macOS-style app switcher (one icon per app, across all
workspaces). It became a window switcher for one case: several fullscreen or
zoomed windows lying on top of each other on one workspace, where only the top
one is visible. The row shows all of them, the same tile look as the workspace
switcher on Super+Tab. Other workspaces stay Super+Tab's job, minimized windows
(`special:minimized`) the dock's.

The plugin id (`henri.app-switcher-v3`), the IPC target and the Hyprland events
stayed `app-switcher`, so no bind had to move.

## Switching

The switch goes through Hyprland's focus dispatcher on the window address.
Focusing a window under a fullscreen one hands the fullscreen over to it
(`misc:on_focus_under_fullscreen = 1`); a floating window comes to the top.

The order is the switcher's own most-recently-used list, fed by every focus
change while the shell runs. Hyprland's `focusHistoryID` is the fallback for
windows the list has not seen yet (right after a shell restart).

## Keys

Hyprland owns them (`~/.config/hypr/bindings.lua`):

| Key | Event |
|---|---|
| `ALT + TAB` | `custom>>app-switcher next` |
| `ALT + SHIFT + TAB` | `custom>>app-switcher prev` |
| `ALT + ESCAPE` | `custom>>app-switcher cancel` |
| `ALT` released | `custom>>app-switcher commit` |

The release bind needs `transparent = true`: after Alt+Tab, Hyprland shadows
every binding on the still-held Alt key, and without the flag the release never
fires. The row never takes the keyboard, and it is mapped only while the gesture
runs (a permanently mapped overlay breaks other popups' click-outside close).

## Mouse

Hovering a preview preselects it, a click switches, a click next to the card
cancels.

## IPC

```bash
omarchy-shell app-switcher status     # { armed, shown, selected, windows }
omarchy-shell app-switcher next       # same as pressing Alt+Tab
omarchy-shell app-switcher prev
omarchy-shell app-switcher commit
omarchy-shell app-switcher cancel
```

## Look and motion (Velum)

Popover material card (`velum-surface`), out of the centre on the smooth spring
from `launcherFrom`, leaving faster than it came. Tiles have the monitor's
aspect, the window fitted inside with rounded corners, app icon and title
underneath. The selection ring jumps — a gliding highlight would lag the key.
Previews are captured only while the card is visible.
