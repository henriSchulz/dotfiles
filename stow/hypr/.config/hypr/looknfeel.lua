-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
hl.config({
  decoration = {
    -- Use round window corners.
    rounding = 12,
  },
})

-- hl.config({
--   decoration = {
--     -- Dim unfocused windows (0.0 = no dim, 1.0 = fully dimmed).
--     dim_inactive = true,
--     dim_strength = 0.15,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
-- hl.config({
--   animations = {
--     -- Disable all animations.
--     enabled = false,
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })

-- Fenster, Layer und Workspaces auf den Kurven der Mission-Control-Spec
-- (henri.missioncontrol/docs/ANIMATION-SPEC.md). speed in Zehntelsekunden:
-- 2 = 200 ms. Schließen ist immer schneller als Öffnen.
hl.curve("mcOut", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("mcIn", { type = "bezier", points = { { 0.4, 0 }, { 1, 1 } } })
hl.curve("mcInOut", { type = "bezier", points = { { 0.65, 0 }, { 0.35, 1 } } })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 2, bezier = "mcOut", style = "popin 96%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.4, bezier = "mcIn", style = "popin 98%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2, bezier = "mcInOut" })
hl.animation({ leaf = "fade", enabled = true, speed = 1.4, bezier = "mcOut" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 2, bezier = "mcOut", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.4, bezier = "mcIn", style = "fade" })
-- Workspaces: Tastatur-Wechsel mit derselben Feder wie die Wischgeste
-- (hyprswipe, ~/Projects/hyprswipe): k = (2π/0,35 s)² ≈ 322, kritisch gedämpft.
-- Hyprlands Feder läuft in Echtzeit und behält beim schnellen Nachdrücken die
-- Geschwindigkeit; `speed` ist bei Federn ohne Wirkung. 40 px Spalt wie im
-- Plugin (gap), damit Geste und Taste dieselbe Geometrie haben.
hl.curve("spacesSpring", { type = "spring", mass = 1, stiffness = 322, dampening = 35.889 })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1, spring = "spacesSpring", style = "slide" })
hl.config({ general = { gaps_workspaces = 40 } })

-- Maus bleibt, wo sie ist. Omarchy setzt warp_on_change_workspace = 1; beim
-- Zurückholen eines minimierten Fensters aus dem Dock springt der Zeiger damit
-- in dessen Mitte (gemessen: 768,497 -> 290,200). omadock vermeidet das schon,
-- wo es kann (silent move, follow = false) — die Wayland-Aktivierung danach
-- löst den Warp trotzdem aus, und die erwischt man nur hier. macOS bewegt den
-- Zeiger nie von selbst, also gilt das auch für den Workspace-Wechsel.
hl.config({ cursor = { no_warps = true } })

-- Zeiger sichtbar machen. Er bewegte sich nachweislich (hyprctl cursorpos
-- aenderte sich), war aber auf keinem Monitor zu sehen. Zwei Ursachen, beide
-- hier behoben:
--
-- enable_hyprcursor sucht ein hyprcursor-Thema; installiert ist keines
-- (kein manifest.hl unter /usr/share/icons oder ~/.local/share/icons), und
-- HYPRCURSOR_THEME ist leer. Statt auf XCursor zurueckzufallen wird dann
-- nichts gezeichnet.
--
-- Das XCursor-Thema stand ausserdem auf "default", was es auf diesem System
-- nicht gibt -- auch ~/.local/share/icons/default/index.theme fehlt. MacTahoe
-- ist installiert und passt zum Rest.
hl.config({ cursor = { enable_hyprcursor = false } })
hl.env("XCURSOR_THEME", "MacTahoe")
hl.env("XCURSOR_SIZE", "24")

-- Eigene Menüleiste (henri.bar): Hintergrund weichzeichnen wie bei macOS.
hl.layer_rule({ match = { namespace = "omarchy-bar" }, blur = true, ignore_alpha = 0.3 })

-- Dock (henri.dock, seit 2026-09-27 statt omadock): das macOS-Dock ist
-- Milchglas, kein Balken. Der Hintergrund ist eine eigene, dünne Layer-Fläche
-- (namespace henri-dock), nur die wird geblurt — helles Glas liegt bei Weiß
-- α 0.28 (Apple.dock), deshalb ignore_alpha 0.2 statt 0.3. Kacheln, Label,
-- Menüs und die Genie-Animation liegen im Overlay darüber und animieren
-- selbst; Hyprlands Layer-Fade würde beim Ein-/Ausblenden doppelt blenden.
hl.layer_rule({ match = { namespace = "henri-dock" }, blur = true, ignore_alpha = 0.2 })
hl.layer_rule({ match = { namespace = "henri-dock" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "henri-dock-overlay" }, no_anim = true, animation = "none" })

-- Mission Control animiert selbst (Fenster schrumpfen, eigener Crossfade).
-- Hyprlands Layer-Fade darüber lässt es ruckeln und doppelt blenden.
hl.layer_rule({ match = { namespace = "mission-control" }, no_anim = true, animation = "none" })

-- Super+Tab-Switcher (henri.workspace-switcher) animiert ebenfalls selbst.
-- Mit Hyprlands Layer-Fade lag beim Wechsel ein verblassendes Standbild des
-- Streifens über dem Workspace-Slide.
hl.layer_rule({ match = { namespace = "workspace-switcher" }, no_anim = true, animation = "none" })

-- Spotlight (henri.menu) blendet seine Karte selbst ein (Fade + gentle-Spring).
-- Hyprlands eigener Layer-Fade (layersIn, speed 4 = 400 ms) legte eine zweite
-- Blende darüber: nach dem Tastendruck stand die Karte spürbar lange halb da.
hl.layer_rule({ match = { namespace = "omarchy-menu" }, no_anim = true, animation = "none" })
-- Spotlight ist Milchglas (zwei Glasflächen bei α 0.70, spotlight-design-spec
-- §3): der Compositor-Blur macht aus der blassen Fläche erst Glas. ignore_alpha
-- lässt den fast durchsichtigen Rest der Vollbild-Ebene und den weichen
-- Schatten ungeblurt.
hl.layer_rule({ match = { namespace = "omarchy-menu" }, blur = true, ignore_alpha = 0.3 })

-- Lautstärke-/Helligkeits-HUD (henri.osd) blendet sich selbst ein und aus.
hl.layer_rule({ match = { namespace = "henri-osd" }, no_anim = true, animation = "none" })

-- Diktat-Panel (henri.dictation) blendet sich selbst ein und aus, wie das
-- Lautstärke-HUD. Blur dahinter wie bei der Menüleiste: die Karte ist fast
-- deckend, der Weichzeichner trägt vor allem die runden Enden.
hl.layer_rule({ match = { namespace = "henri-dictation" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "henri-dictation" }, blur = true, ignore_alpha = 0.3 })

-- Assistenten-Karte (henri.assistant) blendet sich selbst ein, wie das Diktat.
hl.layer_rule({ match = { namespace = "henri-assistant" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "henri-assistant" }, blur = true, ignore_alpha = 0.3 })

-- HUi.PopupPanel (jedes Plugin-Popup/-Panel, inkl. der echten Bildschirmtastatur,
-- die sich den Namespace teilt): blendet sich selbst ein und ist jetzt bewusst
-- halbdurchsichtig (Motion.glassPanelAlpha) statt fast deckend, seit dem
-- macOS-Big-Sur-Umbau von henri.control-center — der Weichzeichner trägt jetzt
-- echtes Milchglas, nicht nur die runden Ecken. Gilt für alle Plugins zentral.
hl.layer_rule({ match = { namespace = "omarchy-keyboard-panel" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "omarchy-keyboard-panel" }, blur = true, ignore_alpha = 0.3 })

-- Mitteilungs-Banner (henri.notifications, Apple-Look): Glas wie beim Control
-- Center. Die Karte gleitet mit eigener Animation von der Kante herein —
-- Hyprlands Layer-Fade auf dem Vollbild-Overlay würde doppelt laufen.
hl.layer_rule({ match = { namespace = "omarchy-notifications" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "omarchy-notifications" }, blur = true, ignore_alpha = 0.3 })

-- Quick Look (GNOME Sushi): Hyprland maps the window at a size of its own and
-- only a frame later gets the preview's real size, so the default pop-in
-- (87 %) reads as the card shrinking into place. Starting the pop-in from
-- almost nothing hides that correction: the preview grows out of the file,
-- like macOS.
hl.window_rule({ match = { class = "org.gnome.NautilusPreviewer" }, float = true, animation = "popin 10%" })

-- Finder (henri-ui macOS Finder clone, ~/Projects/finder): it draws its own
-- rounded card with traffic lights instead of a headerbar. It tiles like any
-- other window (it used to float, and so popped up over whatever was open);
-- the window mode "macos" in window-mode.lua still floats it along with
-- everything else. Its card is rounded 20 (apple-ui --apple-win-radius); with
-- the global 12 the active border cut across the card's corners, so the
-- border follows the card's own radius.
hl.window_rule({ match = { class = "de.henri.Finder" }, rounding = 20 })
-- Finder as another app's Open/Save panel (finder_app/picker.py): the one
-- Finder window that floats, centred, at the panel's own size. It is mapped
-- with this title and takes the asking app's title afterwards.
hl.window_rule({
  match = { class = "de.henri.Finder", initial_title = "^Finder Panel$" },
  float = true,
  center = true,
  size = { 1040, 640 },
})

-- Finder's Quick Look (finder_app/quicklook.py, titled "Quick Look"): the panel
-- animates itself — it grows out of its centre, glides between preview sizes
-- and shrinks away, resizing its window on every frame. Hyprland's own
-- animations have to stay out of it: windowsMove eases every one of those
-- resizes again, so the frame lagged behind the content and then jumped.
hl.window_rule({
  match = { class = "de.henri.Finder", initial_title = "^Quick Look$" },
  float = true,
  no_anim = true,
})

-- Low-power rendering, switched from Control Center → Experiments
-- (henri.control-center-v2/system/henri-render-power). The flag file is the
-- whole state: present = on. Measured 2026-09-26 on the XPS 13: Hyprland alone
-- kept the GPU 25–43 % busy, so the display never reached DC5/DC6 and the
-- package never PC8/PC10. Direct scanout hands a fullscreen window's buffer
-- straight to the display, two blur passes instead of three, and no color
-- management pass on this SDR panel.
local low_power_render = io.open((os.getenv("HOME") or "") .. "/.local/state/henri/low-power-render", "r")
if low_power_render then
  low_power_render:close()
  hl.config({
    render = { direct_scanout = 1, cm_enabled = false },
    decoration = { blur = { passes = 2, size = 8 } },
  })
end

-- No effects, switched from Control Center → Experiments (same helper, flag
-- no-effects). For the M1 power measurements in ~/Projects/m1-power: blur,
-- shadows and Hyprland's own animations off. Blur off also takes the glass
-- from the bar, dock and panels, so the helper sets noEffects in henri-ui's
-- Prefs.js and the menus turn solid; the shell plugins still animate themselves.
local no_effects = io.open((os.getenv("HOME") or "") .. "/.local/state/henri/no-effects", "r")
if no_effects then
  no_effects:close()
  hl.config({
    decoration = { blur = { enabled = false }, shadow = { enabled = false } },
    animations = { enabled = false },
  })
end

-- System Settings (omarchy-settings, ~/Projects/settings): a macOS-27-shaped
-- settings window. 868 × 768 = the 723 × 640 measured on macOS at the app's
-- own 1.2 scale. It tiles like any other window (it used to float and centre itself); its
-- sidebar is translucent, so it gets the compositor blur.
hl.window_rule({ match = { title = "^System Settings$" }, opacity = "1.0 override" })
