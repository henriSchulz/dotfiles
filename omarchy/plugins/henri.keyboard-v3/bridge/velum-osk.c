/*
 * velum-osk — the bridge between Velum's on-screen keyboard (henri.keyboard-v3) and fcitx5.
 *
 *   velum-osk [LAYOUT [VARIANT]]      (default "de"; the compositor's keymap, Hyprland input.kb_layout)
 *
 * fcitx5 owns the seat's input method on Hyprland (zwp_input_method_v2), so the keyboard cannot be
 * one itself. fcitx5 has its own way for an on-screen keyboard instead, the "virtualkeyboard" UI:
 *
 *   - this process owns org.fcitx.Fcitx5.VirtualKeyboard (object /org/fcitx/virtualkeyboard/impanel);
 *     fcitx5's Show / Hide calls on focus changes are answered but not followed: the keyboard opens
 *     only when asked (the window bar's keyboard button) — following them, every tap on a terminal
 *     opened it again;
 *   - "open" puts fcitx5 into on-screen-keyboard mode (show and hide at once), where fcitx5 owns
 *     org.fcitx.Fcitx5.VirtualKeyboardBackend: a key sent to its ProcessKeyEvent goes to the focused
 *     text field as a virtual key and does not end the mode;
 *   - a key from a real keyboard ends the mode (fcitx5 releases the backend name): the keyboard hides,
 *     as on an iPad when a keyboard is attached.
 *
 * Lines in (stdin):
 *     touch                a finger was lifted on the cast screen (ignored)
 *     text UTF8            type these characters
 *     key NAME             press a key by its keysym name (BackSpace, Return, Tab, Left, …)
 *     combo MODS KEY       a key combo: MODS ctrl+alt+shift+super or "-", KEY a keysym name or one
 *                          character ("combo ctrl+shift c"); through our own virtual keyboard, see press_combo
 *     open | close         the keyboard opened or closed by hand (open enters the mode)
 *     hold on|off          a dictation runs: voxtype's paste (wtype) must not close the keyboard
 *     field                is a text field focused? answered with "field N" (fcitx5's Controller1.State)
 * Lines out (stdout):
 *     show | hide          the keyboard should appear / go
 *     mode osk|physical    fcitx5's input method mode
 *     field 0|1|2          no text field focused | one, input method off | on (the edit menu asks)
 *
 * Text goes through fcitx5 while a text field there has the focus: a character as its keysym alone,
 * which fcitx5 commits as text (needs waylandim PreferKeyEvent=False), a key without a character by
 * the compositor's key code for it. Without a focused text field (an app without text-input, or
 * none) it goes through wtype instead.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <systemd/sd-bus.h>
#include <time.h>
#include <unistd.h>
#include <sys/mman.h>
#include <wayland-client.h>
#include <xkbcommon/xkbcommon.h>
#include "virtual-keyboard-unstable-v1-client-protocol.h"

extern char **environ;

#define FCITX "org.fcitx.Fcitx5"
#define BACKEND "org.fcitx.Fcitx5.VirtualKeyboardBackend"
#define BACKEND_IFACE "org.fcitx.Fcitx5.VirtualKeyboardBackend1"
#define PANEL "org.fcitx.Fcitx5.VirtualKeyboard"
#define PANEL_IFACE "org.fcitx.Fcitx5.VirtualKeyboard1"

static sd_bus *bus;
static struct xkb_keymap *keymap;
static bool osk_mode, shown, by_hand;
/* a combo went through wtype until then: fcitx5 takes it for a real key and leaves on-screen-keyboard
 * mode, which must not close the keyboard — the mode is entered again instead (rearm) */
static uint64_t combo_grace;
static bool rearm;
/* a dictation runs (and for a moment after it): voxtype pastes with wtype, which ends the mode just the
 * same; the keyboard stays up as on an iPad */
static bool hold;
/* another keyboard can have reached fcitx5 since our last key (the mode ended, the keyboard opened, a
 * wtype of ours): its keymap may be that keyboard's, see own_keymap */
static bool keymap_dirty = true;
#define HOLD_AFTER_MS 1500

static uint64_t now_ms(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return (uint64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static void out(const char *line)
{
	printf("%s\n", line);
	fflush(stdout);
}

static void set_shown(bool on)
{
	if (shown == on)
		return;
	shown = on;
	out(on ? "show" : "hide");
}

/* ---- fcitx5 calls on our panel object ---------------------------------------------------- */

/* fcitx5's own show / hide on focus in and out are not followed: the keyboard comes only when asked
 * (the window bar's keyboard button). Following them, every tap on a terminal opened it again, also
 * the tap that had just closed it (Henri, 2026-10-25). */
static int m_show(sd_bus_message *m, void *u, sd_bus_error *e)
{
	(void)u, (void)e;
	return sd_bus_reply_method_return(m, NULL);
}

static int m_hide(sd_bus_message *m, void *u, sd_bus_error *e)
{
	(void)u, (void)e;
	return sd_bus_reply_method_return(m, NULL);
}

static int m_ignore(sd_bus_message *m, void *u, sd_bus_error *e)
{
	(void)u, (void)e;
	return sd_bus_reply_method_return(m, NULL);
}

static const sd_bus_vtable panel_vtable[] = {
	SD_BUS_VTABLE_START(0),
	SD_BUS_METHOD("ShowVirtualKeyboard", "", "", m_show, 0),
	SD_BUS_METHOD("HideVirtualKeyboard", "", "", m_hide, 0),
	SD_BUS_METHOD("UpdatePreeditCaret", "i", "", m_ignore, 0),
	SD_BUS_METHOD("UpdatePreeditArea", "s", "", m_ignore, 0),
	SD_BUS_METHOD("UpdateCandidateArea", "asbbii", "", m_ignore, 0),
	SD_BUS_METHOD("NotifyIMActivated", "s", "", m_ignore, 0),
	SD_BUS_METHOD("NotifyIMDeactivated", "s", "", m_ignore, 0),
	SD_BUS_METHOD("NotifyIMListChanged", "", "", m_ignore, 0),
	SD_BUS_VTABLE_END,
};

/* fcitx5 entered or left on-screen-keyboard mode: it owns the backend name only in that mode */
static void set_mode(bool on)
{
	if (osk_mode == on)
		return;
	osk_mode = on;
	out(on ? "mode osk" : "mode physical");
	if (!on)
		keymap_dirty = true;
	if (!on && shown && (hold || now_ms() < combo_grace)) { /* our own combo or a dictation's paste, not a real key */
		rearm = true;
		return;
	}
	if (!on) { /* a real key was pressed */
		by_hand = false;
		set_shown(false);
	}
}

static int on_owner(sd_bus_message *m, void *u, sd_bus_error *e)
{
	(void)u, (void)e;
	const char *name, *old, *new;
	if (sd_bus_message_read(m, "sss", &name, &old, &new) >= 0 && !strcmp(name, BACKEND))
		set_mode(new && *new);
	return 0;
}

static bool has_owner(const char *name)
{
	sd_bus_message *r = NULL;
	int has = 0;
	if (sd_bus_call_method(bus, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
			       "NameHasOwner", NULL, &r, "s", name) >= 0)
		sd_bus_message_read(r, "b", &has);
	sd_bus_message_unref(r);
	return has;
}

/* 0: no text field has the focus, 1: one has, input method off, 2: on (Controller1.State) */
static int fcitx_state(void)
{
	sd_bus_message *r = NULL;
	int st = 0;
	if (sd_bus_call_method(bus, FCITX, "/controller", "org.fcitx.Fcitx.Controller1", "State", NULL, &r, "") >= 0)
		sd_bus_message_read(r, "i", &st);
	sd_bus_message_unref(r);
	return st;
}

static void fcitx_vk(const char *method)
{
	sd_bus_call_method(bus, FCITX, "/virtualkeyboard", "org.fcitx.Fcitx.VirtualKeyboard1", method, NULL, NULL, "");
}

/* ---- keys ------------------------------------------------------------------------------------- */

/* the key code and X modifier state that make SYM on the first group of the keymap */
static bool find_key(xkb_keysym_t sym, xkb_keycode_t *code, uint32_t *state)
{
	xkb_keycode_t lo = xkb_keymap_min_keycode(keymap), hi = xkb_keymap_max_keycode(keymap);
	if (hi > 255)
		hi = 255; /* the keys a real keyboard has; € also sits on an extra code above */
	for (int pass = 0; pass < 2; pass++) /* lowest level first: 'a' plain before anything shifted */
		for (xkb_keycode_t k = lo; k <= hi; k++) {
			xkb_level_index_t levels = xkb_keymap_num_levels_for_key(keymap, k, 0);
			for (xkb_level_index_t l = pass ? 1 : 0; l < (pass ? levels : levels > 0 ? 1 : 0); l++) {
				const xkb_keysym_t *syms;
				if (xkb_keymap_key_get_syms_by_level(keymap, k, 0, l, &syms) != 1 || syms[0] != sym)
					continue;
				xkb_mod_mask_t masks[4];
				size_t n = xkb_keymap_key_get_mods_for_level(keymap, k, 0, l, masks, 4);
				if (l > 0 && n == 0)
					continue;
				/* the core modifiers have the X bit order (Shift, Lock, Control, Mod1..Mod5) */
				*code = k;
				*state = n ? masks[0] & 0xff : 0;
				return true;
			}
		}
	return false;
}

static void wtype(const char *flag, const char *arg)
{
	char *argv[] = { "wtype", (char *)flag, (char *)arg, NULL };
	if (!flag)
		argv[1] = (char *)arg, argv[2] = NULL;
	pid_t pid;
	if (posix_spawnp(&pid, "wtype", NULL, NULL, argv, environ) == 0)
		waitpid(pid, NULL, 0);
	keymap_dirty = true;
}

/* fcitx5 commits a character as text (text-input) but a key as a key (its virtual keyboard): sent too
 * close together a key overtook the text before it, and a commit right after another replaced it
 * (Hyprland's relay keeps one pending string). A tap is never this quick; a test feed is. */
#define SPACING_MS 25
static uint64_t last_sent;

static bool backend_key(xkb_keysym_t sym, xkb_keycode_t code, uint32_t state, bool up)
{
	uint64_t t = now_ms();
	if (!up && t < last_sent + SPACING_MS)
		usleep((last_sent + SPACING_MS - t) * 1000);
	if (!up)
		last_sent = now_ms();
	return sd_bus_call_method(bus, BACKEND, "/virtualkeyboard", BACKEND_IFACE, "ProcessKeyEvent", NULL, NULL,
				  "uuubu", sym, code, state, up, (uint32_t)now_ms()) >= 0;
}

/* A character goes as its keysym with no key code and no modifiers: fcitx5 then commits it as text
 * (mayCommitAsText), whatever the layout — it forwards only a key code, never the Shift or AltGr that
 * came with it, so 'H' or '@' sent by their keys arrived as 'h' and 'q'. A key without a character
 * (BackSpace, Return, the arrows) goes by its key code. */
static bool fcitx_char(xkb_keysym_t sym)
{
	return backend_key(sym, 0, 0, false) && backend_key(sym, 0, 0, true);
}

static bool vk_ready(void);
static struct wl_display *wl;
static struct zwp_virtual_keyboard_v1 *vk;

/* fcitx5 forwards a key code with the keymap of the keyboard it last saw: after wtype (voxtype pastes
 * with it, tablet-v3 sends the Enter after a dictation with it) that is wtype's own keymap, where
 * Return's code means nothing — Enter stayed dead after a dictation (Henri, 2026-10-29). A modifiers
 * event from our virtual keyboard makes it the seat's keyboard again, and Hyprland hands fcitx5 its
 * keymap, the compositor's own. fcitx5 takes it in on its own time: a key sent at once was still lost,
 * so the next one waits KEYMAP_SETTLE_MS — only when another keyboard can have been in between
 * (keymap_dirty), so a held delete still repeats at its pace. */
#define KEYMAP_SETTLE_MS 60
static void own_keymap(void)
{
	if (!keymap_dirty || !vk_ready())
		return;
	zwp_virtual_keyboard_v1_modifiers(vk, 0, 0, 0, 0);
	wl_display_roundtrip(wl);
	usleep(KEYMAP_SETTLE_MS * 1000);
	keymap_dirty = false;
}

static bool fcitx_key(xkb_keysym_t sym)
{
	xkb_keycode_t code;
	uint32_t state;
	if (!find_key(sym, &code, &state))
		return false;
	own_keymap();
	return backend_key(sym, code, 0, false) && backend_key(sym, code, 0, true);
}

/* through fcitx5 while a text field there has the focus, else wtype */
static void type_text(const char *s)
{
	bool fx = osk_mode && fcitx_state() > 0;
	const char *p = s;
	while (*p) {
		uint32_t cp;
		unsigned char c = *p;
		int n = c < 0x80 ? 1 : (c >> 5) == 6 ? 2 : (c >> 4) == 14 ? 3 : (c >> 3) == 30 ? 4 : 1;
		cp = n == 1 ? c : c & (0x7f >> n);
		for (int i = 1; i < n && p[i]; i++)
			cp = cp << 6 | (p[i] & 0x3f);
		char one[8] = { 0 };
		memcpy(one, p, n);
		p += n;
		xkb_keysym_t sym = cp == '\n' ? XKB_KEY_Return : xkb_utf32_to_keysym(cp);
		bool sent = fx && sym != XKB_KEY_NoSymbol && (sym == XKB_KEY_Return ? fcitx_key(sym) : fcitx_char(sym));
		if (!sent)
			wtype(NULL, one);
	}
}

static bool vk_tap(xkb_keycode_t code, uint32_t mods);

/* a named key: through fcitx5 while a text field there has the focus, else our virtual keyboard (wtype's
 * own keymap made Hyprland's binds read its keys as Escape, see press_combo), wtype only as the last way */
static void press_key(const char *name)
{
	xkb_keysym_t sym = xkb_keysym_from_name(name, XKB_KEYSYM_NO_FLAGS);
	if (sym == XKB_KEY_NoSymbol)
		return;
	if (osk_mode && fcitx_state() > 0 && fcitx_key(sym))
		return;
	xkb_keycode_t code;
	uint32_t state;
	if (!(find_key(sym, &code, &state) && vk_tap(code, state)))
		wtype("-k", name);
}

/* A combo goes through a virtual keyboard of our own that carries the compositor's keymap (the one this
 * process compiled from LAYOUT). Not through fcitx5: it forwards a virtual key with the real keyboard's
 * modifiers, so Control or Super never reach the app. Not through wtype: wtype uploads a keymap of its
 * own that gives its first key the code 9, and Hyprland matches binds by code against the seat's keymap
 * — Command+Space became Super+Escape, the system menu (Henri, 2026-10-27). With the same keymap the
 * codes mean what they say for Hyprland's binds, for fcitx5's grab and for the app. fcitx5 takes it for
 * a real key and leaves on-screen-keyboard mode, which set_mode() then enters again. */
static struct wl_seat *seat;
static struct zwp_virtual_keyboard_manager_v1 *vk_manager;

static void reg_global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t ver)
{
	(void)d, (void)ver;
	if (!strcmp(iface, wl_seat_interface.name) && !seat)
		seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
	else if (!strcmp(iface, zwp_virtual_keyboard_manager_v1_interface.name))
		vk_manager = wl_registry_bind(r, name, &zwp_virtual_keyboard_manager_v1_interface, 1);
}
static void reg_remove(void *d, struct wl_registry *r, uint32_t name) { (void)d, (void)r, (void)name; }
static const struct wl_registry_listener reg_listener = { reg_global, reg_remove };

static bool vk_ready(void)
{
	if (vk)
		return wl_display_get_error(wl) == 0;
	if (!(wl = wl_display_connect(NULL)))
		return false;
	struct wl_registry *reg = wl_display_get_registry(wl);
	wl_registry_add_listener(reg, &reg_listener, NULL);
	wl_display_roundtrip(wl);
	if (!seat || !vk_manager)
		return false;
	vk = zwp_virtual_keyboard_manager_v1_create_virtual_keyboard(vk_manager, seat);
	char *map = xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
	size_t size = strlen(map) + 1;
	int fd = memfd_create("velum-osk-keymap", MFD_CLOEXEC);
	if (fd < 0 || ftruncate(fd, size) < 0 || write(fd, map, size) != (ssize_t)size) {
		free(map);
		return false;
	}
	free(map);
	zwp_virtual_keyboard_v1_keymap(vk, WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1, fd, size);
	close(fd);
	wl_display_roundtrip(wl);
	return wl_display_get_error(wl) == 0;
}

/* press and release the key `code` (xkb) with the modifier mask `mods` held */
static bool vk_tap(xkb_keycode_t code, uint32_t mods)
{
	if (!vk_ready())
		return false;
	uint32_t t = (uint32_t)now_ms(), evdev = code - 8;
	zwp_virtual_keyboard_v1_modifiers(vk, mods, 0, 0, 0);
	zwp_virtual_keyboard_v1_key(vk, t, evdev, WL_KEYBOARD_KEY_STATE_PRESSED);
	wl_display_roundtrip(wl);
	usleep(SPACING_MS * 1000);
	zwp_virtual_keyboard_v1_key(vk, t + SPACING_MS, evdev, WL_KEYBOARD_KEY_STATE_RELEASED);
	zwp_virtual_keyboard_v1_modifiers(vk, 0, 0, 0, 0);
	wl_display_roundtrip(wl);
	return true;
}

static void press_combo(char *spec)
{
	char *key = strchr(spec, ' ');
	if (!key)
		return;
	*key++ = 0;
	const unsigned char *u = (const unsigned char *)key;
	int n = *u < 0x80 ? 1 : (*u >> 5) == 6 ? 2 : (*u >> 4) == 14 ? 3 : (*u >> 3) == 30 ? 4 : 0;
	xkb_keysym_t sym = XKB_KEY_NoSymbol;
	if (n && (int)strlen(key) == n) { /* one character: its keysym */
		uint32_t cp = n == 1 ? *u : *u & (0x7f >> n);
		for (int i = 1; i < n; i++)
			cp = cp << 6 | (u[i] & 0x3f);
		sym = xkb_utf32_to_keysym(cp);
	} else
		sym = xkb_keysym_from_name(key, XKB_KEYSYM_NO_FLAGS);
	xkb_keycode_t code;
	uint32_t level_state;
	if (sym == XKB_KEY_NoSymbol || !find_key(sym, &code, &level_state))
		return;

	/* the modifiers as this keymap numbers them, plus whatever level the key's symbol needs (AltGr) */
	static const char *known[][2] = { { "ctrl", XKB_MOD_NAME_CTRL }, { "alt", XKB_MOD_NAME_ALT },
					  { "shift", XKB_MOD_NAME_SHIFT }, { "super", XKB_MOD_NAME_LOGO } };
	uint32_t mods = level_state;
	for (char *m = strtok(spec, "+"); m; m = strtok(NULL, "+"))
		for (int i = 0; i < 4; i++)
			if (!strcmp(m, known[i][0])) {
				xkb_mod_index_t ix = xkb_keymap_mod_get_index(keymap, known[i][1]);
				if (ix != XKB_MOD_INVALID)
					mods |= 1u << ix;
			}
	if (osk_mode)
		combo_grace = now_ms() + 1000;
	if (!vk_tap(code, mods))
		fprintf(stderr, "velum-osk: no virtual keyboard for a combo\n");
}

/* ---- input from the plugin ------------------------------------------------------------------ */

static void line(char *l)
{
	if (!strcmp(l, "open") && !osk_mode && !has_owner(BACKEND)) {
		/* into on-screen-keyboard mode (shown and hidden at once), so keys reach the focused field as
		 * fcitx5's virtual keys and do not end the mode */
		fcitx_vk("ShowVirtualKeyboard");
		fcitx_vk("HideVirtualKeyboard");
	}
	if (!strcmp(l, "touch"))
		; /* a finger on the cast screen: nothing opens by itself any more */
	else if (!strncmp(l, "text ", 5))
		type_text(l + 5);
	else if (!strncmp(l, "key ", 4))
		press_key(l + 4);
	else if (!strncmp(l, "combo ", 6))
		press_combo(l + 6);
	else if (!strcmp(l, "open")) {
		by_hand = true;
		keymap_dirty = true;
		set_shown(true);
	} else if (!strcmp(l, "field")) {
		char ans[16];
		snprintf(ans, sizeof ans, "field %d", fcitx_state());
		out(ans);
	} else if (!strcmp(l, "hold on"))
		hold = true;
	else if (!strcmp(l, "hold off")) {
		hold = false;
		combo_grace = now_ms() + HOLD_AFTER_MS; /* voxtype says idle as it pastes; the Enter after it comes later */
	} else if (!strcmp(l, "close")) {
		by_hand = false;
		set_shown(false);
	}
}

int main(int argc, char **argv)
{
	struct xkb_rule_names names = { .layout = argc > 1 ? argv[1] : "de", .variant = argc > 2 ? argv[2] : NULL };
	struct xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
	keymap = ctx ? xkb_keymap_new_from_names(ctx, &names, XKB_KEYMAP_COMPILE_NO_FLAGS) : NULL;
	if (!keymap) {
		fprintf(stderr, "velum-osk: no keymap for %s\n", names.layout);
		return 1;
	}
	if (getenv("VELUM_OSK_MAP")) { /* test: the key each character of $VELUM_OSK_MAP takes */
		for (const unsigned char *c = (const unsigned char *)getenv("VELUM_OSK_MAP"); *c;) {
			int n = *c < 0x80 ? 1 : (*c >> 5) == 6 ? 2 : (*c >> 4) == 14 ? 3 : 4;
			uint32_t cp = n == 1 ? *c : *c & (0x7f >> n);
			for (int i = 1; i < n; i++)
				cp = cp << 6 | (c[i] & 0x3f);
			xkb_keycode_t code = 0;
			uint32_t state = 0;
			bool ok = find_key(xkb_utf32_to_keysym(cp), &code, &state);
			printf("%.*s %s code %u state 0x%x\n", n, c, ok ? "ok" : "none", code, state);
			c += n;
		}
		return 0;
	}
	if (sd_bus_open_user(&bus) < 0) {
		fprintf(stderr, "velum-osk: no session bus\n");
		return 1;
	}
	sd_bus_slot *slot = NULL;
	if (sd_bus_add_object_vtable(bus, &slot, "/org/fcitx/virtualkeyboard/impanel", PANEL_IFACE, panel_vtable, NULL) < 0 ||
	    sd_bus_request_name(bus, PANEL, 0) < 0) {
		fprintf(stderr, "velum-osk: %s is taken\n", PANEL);
		return 1;
	}
	sd_bus_match_signal(bus, NULL, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
			    "NameOwnerChanged", on_owner, NULL);
	set_mode(has_owner(BACKEND));

	char buf[4096];
	size_t have = 0;
	for (;;) {
		while (sd_bus_process(bus, NULL) > 0)
			;
		if (rearm) { /* back into on-screen-keyboard mode after our own combo */
			rearm = false;
			fcitx_vk("ShowVirtualKeyboard");
			fcitx_vk("HideVirtualKeyboard");
			continue;
		}
		int wait = -1;
		struct pollfd p[2] = { { .fd = 0, .events = POLLIN }, { .fd = sd_bus_get_fd(bus), .events = sd_bus_get_events(bus) } };
		uint64_t usec;
		if (sd_bus_get_timeout(bus, &usec) >= 0 && usec != UINT64_MAX) {
			struct timespec ts;
			clock_gettime(CLOCK_MONOTONIC, &ts);
			uint64_t nowu = (uint64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
			int bw = usec > nowu ? (int)((usec - nowu) / 1000) + 1 : 0;
			if (wait < 0 || bw < wait)
				wait = bw;
		}
		if (poll(p, 2, wait) < 0 && errno != EINTR)
			return 1;
		if (p[0].revents & (POLLIN | POLLHUP)) {
			ssize_t n = read(0, buf + have, sizeof buf - 1 - have);
			if (n <= 0)
				return 0; /* the plugin went away */
			have += n;
			buf[have] = 0;
			char *s = buf, *nl;
			while ((nl = strchr(s, '\n'))) {
				*nl = 0;
				line(s);
				s = nl + 1;
			}
			have = strlen(s);
			memmove(buf, s, have);
			if (have == sizeof buf - 1)
				have = 0; /* a line that long is no line of ours */
		}
	}
}
