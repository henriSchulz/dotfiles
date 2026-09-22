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

-- Apple-artiger Workspace-Wechsel: weiches Gleiten statt hartem Sprung.
hl.curve("appleSlide", { type = "bezier", points = { { 0.25, 1 }, { 0.5, 1 } } })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "appleSlide", style = "slide" })

-- Eigene Menüleiste (henri.bar): Hintergrund weichzeichnen wie bei macOS.
hl.layer_rule({ match = { namespace = "omarchy-bar" }, blur = true, ignore_alpha = 0.3 })

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

-- Lautstärke-/Helligkeits-HUD (henri.osd) blendet sich selbst ein und aus.
hl.layer_rule({ match = { namespace = "henri-osd" }, no_anim = true, animation = "none" })

-- Diktat-Panel (henri.dictation) blendet sich selbst ein und aus, wie das
-- Lautstärke-HUD. Blur dahinter wie bei der Menüleiste: die Karte ist fast
-- deckend, der Weichzeichner trägt vor allem die runden Enden.
hl.layer_rule({ match = { namespace = "henri-dictation" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "henri-dictation" }, blur = true, ignore_alpha = 0.3 })
