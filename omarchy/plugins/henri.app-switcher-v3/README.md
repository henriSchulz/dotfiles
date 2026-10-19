# App Switcher

macOS-style Cmd+Tab for Omarchy, on **Alt+Tab**.

Hold Alt and press Tab: a row of app icons appears, most recently used first,
the app in front on the left. Every further Tab moves the selection
(Shift+Tab goes back), letting go of Alt switches, Esc cancels. A quick tap
switches straight to the previous app without the row ever flashing up — the
same muscle memory as Cmd+Tab on a Mac.

## Why Alt

Fn is not bindable on this machine. The keyboard controller handles it
internally and it never reaches the kernel as a key of its own: measured on the
XPS 13, Fn+Tab sends exactly the same code as Tab alone (`code=15 TAB`, no
event on `Dell WMI hotkeys` or `Intel HID events`), so Hyprland cannot tell the
two apart.

Alt is the better key anyway. On a Mac keyboard, Command sits directly left of
the space bar — on this keyboard that key is Alt. Cmd+Tab and Alt+Tab are the
same hand movement.

## Apps, not windows

Windows are grouped by their `appId`, so an app with five windows is one icon.
Switching goes to that app's most recently used window, wherever it lives:

* **on another workspace** the switch carries the workspace with it. Wayland
  activation alone only hands over focus and does not follow the window, which
  made every app outside the current workspace look dead — so the switch goes
  through Hyprland's focus dispatcher on the window address, which does both.
* **minimized** (the dock parks minimized windows on `special:minimized`) it is
  moved back onto the workspace you are on and focused, the way clicking a
  minimized app in the macOS Dock unminimizes it. Opening the special workspace
  instead would be a different thing entirely.

The order is the switcher's own most-recently-used list, fed by every focus
change while the shell runs. Hyprland's `focusHistoryID` only arrives with an
IPC refresh and would leave the row one gesture behind; it is used as a
fallback for windows the list has not seen yet, so the first Alt+Tab after a
shell restart is already in the right order.

## Keys

Hyprland owns them (`~/.config/hypr/bindings.lua`):

| Key | Event |
|---|---|
| `ALT + TAB` | `custom>>app-switcher next` |
| `ALT + SHIFT + TAB` | `custom>>app-switcher prev` |
| `ALT + ESCAPE` | `custom>>app-switcher cancel` |
| `ALT` released | `custom>>app-switcher commit` |

They travel as Hyprland events, not as a process per keystroke, so there is no
launch latency and they always arrive in the order they happened. The release
bind needs `transparent = true`: after Alt+Tab, Hyprland shadows every binding
on the still-held Alt key, and without the flag the release never fires.

The row never takes the keyboard. With Alt held, Hyprland's binds win anyway,
and holding focus would make Hyprland refocus the window the row let go of.
The overlay is mapped only while the gesture runs — a permanently mapped
click-through overlay breaks the click-outside close of every other popup
(Hyprland focus grab).

## Mouse

Hovering an icon preselects it, a click switches, a click next to the card
cancels.

## IPC

```bash
omarchy-shell app-switcher status     # { armed, shown, selected, apps }
omarchy-shell app-switcher next       # same as pressing Alt+Tab
omarchy-shell app-switcher prev
omarchy-shell app-switcher commit
omarchy-shell app-switcher cancel
```

## Motion

Follows `henri-ui`: the row reveals like a menu from the centre
(`HUi.Reveal kind: "menu"`), appearing only after `Motion.switcherDelay` of
holding. The selection jumps instantly — this is a frequent, fast interaction
and a gliding highlight would lag behind the keystroke. Only the app name under
the row crossfades.
