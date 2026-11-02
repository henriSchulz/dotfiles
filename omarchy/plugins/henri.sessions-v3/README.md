# henri.sessions-v3

Claude Code in the menu bar, on Velum. New, not a fork.

- **Glyph** (`Panel.qml`, bar widget): SF `terminal` while any session runs, a dot on its top right —
  orange (`surface.sessions.attention`) while one waits for Henri, the accent while they work; hidden
  when nothing runs. A click (or the custom event `henri-sessions toggle`, on the focused monitor)
  opens a bar popup (`VBarPopup`, `motion.barPopup`): the running sessions, waiting ones first; a row
  brings its terminal forward (`sessions-backend focus`) or resumes / attaches it (`resume`); the
  footer opens the Sessions window (`~/Projects/sessions/bin/sessions present`).
- **Service** (`Service.qml`): polls `~/Projects/sessions/bin/sessions-backend live` every
  `surface.sessions.liveInterval`, titles from `index` every `bar.titleInterval`, writes the rows to
  `$XDG_RUNTIME_DIR/henri-sessions-<Hyprland instance>.json` for the glyphs (one poller for all bars).
- **Notifications** (`Sessions.js decide`, `node tests/sessions_test.js`): a session turning
  `blocked` at once ("Waiting for you"); a turn longer than `bar.notifyAfter` that ends ("Your turn").
  Never for the session whose terminal is the focused window. `notify-send -a Sessions -A open=Open`;
  Open = the Sessions window on that session.

IPC `henri-sessions`: `state`, `toggle`; rig only: `notices` (what would have been posted),
`pause true|false` (stops polling), `feed '{"live":[…]}' MS` (runs the rule on a made-up snapshot —
an object, `qs ipc call` splits an argument starting with `[`), `dark true|false`.

Needs `~/Projects/sessions` (the backend); without it the glyph stays hidden.
