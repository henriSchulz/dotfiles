// The on-screen keyboard of the LUKS screen. Plymouth has no touch input and cannot run QML, so this
// runs next to it in the initramfs: it reads the touchscreen, tells the theme what to show through
// `plymouth update --status=kbd-…` (velum.script.in) and types through a uinput keyboard, so a key
// reaches the password prompt exactly as a key of the real keyboard does.
//
// Everything it knows about the board comes from osk-keys, which assemble writes from Generate.qml.
// Which key makes which character comes from the layout Plymouth uses too (/etc/vconsole.conf).
// Same behaviour as Velum's VKeyboard: the key under a finger types when the finger lifts, the nearest
// key counts, delete repeats while held, shift twice is caps, the grabber pulled down hides the board.
//
// Started by the initcpio hook velum-osk, stopped at its latehook. It must never stand in the way of
// the boot: if anything is missing it logs to stderr (/run/velum-osk.log) and the real keyboard still works.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/input.h>
#include <linux/uinput.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <xkbcommon/xkbcommon.h>
#include <xkbcommon/xkbcommon-keysyms.h>

#define KEYS_FILE "/usr/share/plymouth/themes/velum/osk-keys"
#define MAX_KEYS 256
#define MAX_SLOTS 10
#define BITS_LONG (8 * sizeof(long))
#define BIT(array, bit) ((array[(bit) / BITS_LONG] >> ((bit) % BITS_LONG)) & 1)

enum kind { K_CHAR, K_DELETE, K_RETURN, K_SHIFT, K_PAGE, K_HIDE };

struct key {
  char page[16];
  int x, y, w, h;
  enum kind kind;
  char out[16], upper[16], to[16];
};

struct finger {
  bool down, changed, on_button, on_grabber, ended;
  int x, y, start_y;
  struct key *key;
};

static struct key keys[MAX_KEYS];
static int key_count;
static int screen_w, screen_h, board_y;
static int card_x, card_y, card_w;
static int button_x, button_y, button_size;
static int gap, first_key_y;
static int caps_tap, repeat_delay, repeat_interval, dismiss_drag;

static int uinput_fd = -1, touch_fd = -1;
static int abs_x_min, abs_x_max, abs_y_min, abs_y_max;
static struct finger fingers[MAX_SLOTS];
static int slot;

static bool shown, shift, caps;
static char page[16] = "letters";
static long last_shift;
static struct key *repeat_key;
static long repeat_at;

static struct xkb_keymap *keymap;

static long now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1000L + t.tv_nsec / 1000000L;
}

// ---- to the theme -------------------------------------------------------------------------------

static void status(const char *format, ...) {
  char text[128], arg[140];
  va_list args;
  va_start(args, format);
  vsnprintf(text, sizeof text, format, args);
  va_end(args);
  snprintf(arg, sizeof arg, "--status=%s", text);
  char *argv[] = {"plymouth", "update", arg, NULL};
  char *envp[] = {NULL};
  pid_t pid;
  // one at a time: a press and its release must not overtake each other
  if (posix_spawn(&pid, "/usr/bin/plymouth", NULL, NULL, argv, envp) == 0) waitpid(pid, NULL, 0);
}

static void show_page(void) {
  const char *name = page;
  if (!strcmp(page, "letters")) name = caps ? "caps" : shift ? "shift" : "letters";
  status("kbd-page %s", name);
}

static void show_down(int index, const struct key *k) {
  status("kbd-down %d %05d %05d %05d %05d", index, k->x, k->y - board_y, k->w, k->h);
}

// ---- to the password prompt ---------------------------------------------------------------------

static void emit(int type, int code, int value) {
  struct input_event event = {.type = type, .code = code, .value = value};
  if (write(uinput_fd, &event, sizeof event) != sizeof event) perror("uinput write");
}

static void press_mods(bool down, bool with_shift, bool with_altgr) {
  if (with_shift) emit(EV_KEY, KEY_LEFTSHIFT, down);
  if (with_altgr) emit(EV_KEY, KEY_RIGHTALT, down);
  if (with_shift || with_altgr) emit(EV_SYN, SYN_REPORT, 0);
}

static void tap_code(int code, bool with_shift, bool with_altgr) {
  press_mods(true, with_shift, with_altgr);
  emit(EV_KEY, code, 1);
  emit(EV_SYN, SYN_REPORT, 0);
  emit(EV_KEY, code, 0);
  emit(EV_SYN, SYN_REPORT, 0);
  press_mods(false, with_shift, with_altgr);
}

// The key and modifiers that make `sym` in the layout's first group; only shift and AltGr count.
static bool find_sym(xkb_keysym_t sym, bool by_char, uint32_t cp, int *code, bool *with_shift, bool *with_altgr) {
  xkb_mod_mask_t shift_mask = 1u << xkb_keymap_mod_get_index(keymap, XKB_MOD_NAME_SHIFT);
  xkb_mod_mask_t altgr_mask = 1u << xkb_keymap_mod_get_index(keymap, "Mod5");
  for (xkb_keycode_t kc = xkb_keymap_min_keycode(keymap); kc <= xkb_keymap_max_keycode(keymap); kc++) {
    if (kc < 8) continue;
    int levels = xkb_keymap_num_levels_for_key(keymap, kc, 0);
    for (int level = 0; level < levels; level++) {
      const xkb_keysym_t *syms;
      if (xkb_keymap_key_get_syms_by_level(keymap, kc, 0, level, &syms) != 1) continue;
      if (by_char ? xkb_keysym_to_utf32(syms[0]) != cp : syms[0] != sym) continue;
      xkb_mod_mask_t masks[8];
      size_t count = xkb_keymap_key_get_mods_for_level(keymap, kc, 0, level, masks, 8);
      for (size_t i = 0; i < count; i++) {
        if (masks[i] & ~(shift_mask | altgr_mask)) continue;
        *code = kc - 8;
        *with_shift = masks[i] & shift_mask;
        *with_altgr = masks[i] & altgr_mask;
        return true;
      }
    }
  }
  return false;
}

static uint32_t first_codepoint(const char *s) {
  const unsigned char *u = (const unsigned char *)s;
  if (u[0] < 0x80) return u[0];
  if (u[0] < 0xe0) return (u[0] & 0x1f) << 6 | (u[1] & 0x3f);
  if (u[0] < 0xf0) return (u[0] & 0x0f) << 12 | (u[1] & 0x3f) << 6 | (u[2] & 0x3f);
  return (u[0] & 0x07) << 18 | (u[1] & 0x3f) << 12 | (u[2] & 0x3f) << 6 | (u[3] & 0x3f);
}

static void type_text(const char *text) {
  uint32_t cp = first_codepoint(text);
  int code;
  bool with_shift, with_altgr;
  if (cp == ' ') {
    tap_code(KEY_SPACE, false, false);
  } else if (find_sym(0, true, cp, &code, &with_shift, &with_altgr)) {
    tap_code(code, with_shift, with_altgr);
  } else {
    // on a German layout these exist only as dead keys: the dead key and a space make the character,
    // except the acute, which comes out as an apostrophe that way and needs the dead key twice (Compose)
    xkb_keysym_t dead = cp == 0xb4 ? XKB_KEY_dead_acute : cp == '`' ? XKB_KEY_dead_grave
                      : cp == '^' ? XKB_KEY_dead_circumflex : cp == '~' ? XKB_KEY_dead_tilde : XKB_KEY_NoSymbol;
    if (dead != XKB_KEY_NoSymbol && find_sym(dead, false, 0, &code, &with_shift, &with_altgr)) {
      tap_code(code, with_shift, with_altgr);
      if (cp == 0xb4) tap_code(code, with_shift, with_altgr);
      else tap_code(KEY_SPACE, false, false);
    } else {
      fprintf(stderr, "no key for U+%04X in this layout\n", cp);
    }
  }
}

// ---- the keys -----------------------------------------------------------------------------------

// As Layout.keyAt: the nearest key, so the gaps belong to the neighbours; none beyond two gaps away.
static struct key *key_at(int x, int y) {
  struct key *best = NULL;
  long best_distance = -1;
  for (int i = 0; i < key_count; i++) {
    struct key *k = &keys[i];
    if (strcmp(k->page, page)) continue;
    long dx = x < k->x ? k->x - x : x > k->x + k->w ? x - k->x - k->w : 0;
    long dy = y < k->y ? k->y - y : y > k->y + k->h ? y - k->y - k->h : 0;
    long distance = dx * dx + dy * dy;
    if (best_distance < 0 || distance < best_distance) {
      best_distance = distance;
      best = k;
    }
  }
  return best_distance >= 0 && best_distance <= 4L * gap * gap ? best : NULL;
}

static void clear_fingers(void) {
  for (int i = 0; i < MAX_SLOTS; i++) {
    if (fingers[i].key) status("kbd-up %d", i);
    fingers[i].key = NULL;
    fingers[i].on_button = fingers[i].on_grabber = false;
  }
  repeat_key = NULL;
}

static void set_shown(bool on) {
  clear_fingers();
  shown = on;
  if (on) {
    strcpy(page, "letters");
    shift = caps = false;
    show_page();
    status("kbd-show");
  } else {
    status("kbd-hide");
  }
}

static void press_key(struct key *k) {
  switch (k->kind) {
  case K_SHIFT: {
    long t = now_ms();
    if (shift && t - last_shift < caps_tap) caps = shift = true;
    else if (caps) caps = shift = false;
    else shift = !shift;
    last_shift = t;
    show_page();
    break;
  }
  case K_PAGE:
    strcpy(page, k->to);
    shift = caps = false;
    show_page();
    break;
  case K_HIDE:
    set_shown(false);
    break;
  case K_DELETE:
    tap_code(KEY_BACKSPACE, false, false);
    break;
  case K_RETURN:
    tap_code(KEY_ENTER, false, false);
    break;
  case K_CHAR: {
    bool letter = strcmp(k->out, k->upper) != 0;
    type_text(shift && letter ? k->upper : k->out);
    if (shift && !caps && letter) {
      shift = false;
      show_page();
    }
    break;
  }
  }
}

// ---- fingers ------------------------------------------------------------------------------------

static void finger_began(int index, struct finger *f) {
  f->start_y = f->y;
  f->on_button = f->on_grabber = false;
  f->key = NULL;
  if (!shown) {
    // only here: with the board up, positions in a log would be the password
    fprintf(stderr, "touch at %d %d, button at %d %d\n", f->x, f->y, button_x, button_y);
    f->on_button = f->x >= button_x && f->x < button_x + button_size && f->y >= button_y && f->y < button_y + button_size;
    return;
  }
  if (f->x >= card_x && f->x < card_x + card_w && f->y >= card_y && f->y < first_key_y - gap) {
    f->on_grabber = true;
    return;
  }
  f->key = key_at(f->x, f->y);
  if (!f->key) return;
  show_down(index, f->key);
  if (f->key->kind == K_DELETE) {
    press_key(f->key);
    repeat_key = f->key;
    repeat_at = now_ms() + repeat_delay;
  }
}

static void finger_moved(int index, struct finger *f) {
  if (!f->key || repeat_key == f->key) return;
  struct key *k = key_at(f->x, f->y);
  if (k && k != f->key) {
    f->key = k;
    show_down(index, k);
  }
}

static void finger_ended(int index, struct finger *f) {
  if (f->on_button) {
    f->on_button = false;
    if (f->x >= button_x && f->x < button_x + button_size && f->y >= button_y && f->y < button_y + button_size) set_shown(true);
    return;
  }
  if (f->on_grabber) {
    f->on_grabber = false;
    if (f->y - f->start_y > dismiss_drag) set_shown(false);
    return;
  }
  struct key *k = f->key;
  if (!k) return;
  f->key = NULL;
  status("kbd-up %d", index);
  if (k == repeat_key) repeat_key = NULL;
  else press_key(k);
}

static void handle_report(void) {
  for (int i = 0; i < MAX_SLOTS; i++) {
    struct finger *f = &fingers[i];
    if (!f->changed) continue;
    f->changed = false;
    if (f->ended) {
      f->ended = false;
      f->down = false;
      finger_ended(i, f);
    } else if (!f->down) {
      f->down = true;
      finger_began(i, f);
    } else {
      finger_moved(i, f);
    }
  }
}

static void handle_event(const struct input_event *event) {
  if (event->type == EV_SYN) {
    if (event->code == SYN_REPORT) handle_report();
    else if (event->code == SYN_DROPPED) {
      clear_fingers();
      memset(fingers, 0, sizeof fingers);
    }
    return;
  }
  if (event->type != EV_ABS) return;
  if (event->code == ABS_MT_SLOT) {
    slot = event->value >= 0 && event->value < MAX_SLOTS ? event->value : 0;
    return;
  }
  struct finger *f = &fingers[slot];
  if (event->code == ABS_MT_TRACKING_ID) {
    f->changed = true;
    f->ended = event->value < 0;
  } else if (event->code == ABS_MT_POSITION_X) {
    f->x = (long)(event->value - abs_x_min) * screen_w / (abs_x_max - abs_x_min + 1);
    f->changed = true;
  } else if (event->code == ABS_MT_POSITION_Y) {
    f->y = (long)(event->value - abs_y_min) * screen_h / (abs_y_max - abs_y_min + 1);
    f->changed = true;
  }
}

// ---- devices ------------------------------------------------------------------------------------

// The first direct-touch multitouch device. Its driver may still be loading: main comes back here.
static void find_touch(void) {
  DIR *dir = opendir("/dev/input");
  if (!dir) return;
  struct dirent *entry;
  while (touch_fd < 0 && (entry = readdir(dir))) {
    if (strncmp(entry->d_name, "event", 5)) continue;
    char path[300];
    snprintf(path, sizeof path, "/dev/input/%s", entry->d_name);
    int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
    if (fd < 0) continue;
    unsigned long abs[ABS_MAX / BITS_LONG + 1] = {0}, props[INPUT_PROP_MAX / BITS_LONG + 1] = {0};
    struct input_absinfo x, y;
    if (ioctl(fd, EVIOCGBIT(EV_ABS, sizeof abs), abs) >= 0 && ioctl(fd, EVIOCGPROP(sizeof props), props) >= 0
        && BIT(abs, ABS_MT_POSITION_X) && BIT(abs, ABS_MT_SLOT) && BIT(props, INPUT_PROP_DIRECT)
        && ioctl(fd, EVIOCGABS(ABS_MT_POSITION_X), &x) >= 0 && ioctl(fd, EVIOCGABS(ABS_MT_POSITION_Y), &y) >= 0) {
      touch_fd = fd;
      abs_x_min = x.minimum; abs_x_max = x.maximum;
      abs_y_min = y.minimum; abs_y_max = y.maximum;
      char name[128] = "";
      ioctl(fd, EVIOCGNAME(sizeof name), name);
      fprintf(stderr, "touch: %s (%s) x %d..%d y %d..%d\n", path, name, abs_x_min, abs_x_max, abs_y_min, abs_y_max);
    } else {
      close(fd);
    }
  }
  closedir(dir);
}

static bool open_uinput(void) {
  uinput_fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK | O_CLOEXEC);
  if (uinput_fd < 0) {
    perror("/dev/uinput");
    return false;
  }
  ioctl(uinput_fd, UI_SET_EVBIT, EV_KEY);
  ioctl(uinput_fd, UI_SET_EVBIT, EV_SYN);
  for (int code = 1; code < 249; code++) ioctl(uinput_fd, UI_SET_KEYBIT, code);
  struct uinput_setup setup = {.id = {.bustype = BUS_VIRTUAL, .vendor = 0x1209, .product = 0x0001}};
  strcpy(setup.name, "Velum on-screen keyboard");
  if (ioctl(uinput_fd, UI_DEV_SETUP, &setup) < 0 || ioctl(uinput_fd, UI_DEV_CREATE) < 0) {
    perror("uinput create");
    return false;
  }
  return true;
}

// The value of NAME= in /etc/vconsole.conf, as Plymouth reads it
static char *vconsole(const char *name) {
  static char values[4][128];
  static int next;
  char *out = values[next++ % 4];
  out[0] = 0;
  FILE *file = fopen("/etc/vconsole.conf", "r");
  if (!file) return out;
  char line[256];
  size_t length = strlen(name);
  while (fgets(line, sizeof line, file)) {
    if (strncmp(line, name, length) || line[length] != '=') continue;
    char *value = line + length + 1;
    value[strcspn(value, "\r\n")] = 0;
    if (*value == '"') {
      value++;
      value[strcspn(value, "\"")] = 0;
    }
    snprintf(out, sizeof values[0], "%s", value);
  }
  fclose(file);
  return out;
}

static bool load_keymap(void) {
  struct xkb_context *context = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
  if (!context) return false;
  struct xkb_rule_names names = {.rules = NULL, .model = vconsole("XKBMODEL"), .layout = vconsole("XKBLAYOUT"), .variant = vconsole("XKBVARIANT"), .options = NULL};
  keymap = xkb_keymap_new_from_names(context, &names, XKB_KEYMAP_COMPILE_NO_FLAGS);
  if (!keymap) fprintf(stderr, "no keymap for layout '%s'\n", names.layout);
  return keymap != NULL;
}

static bool load_keys(void) {
  FILE *file = fopen(KEYS_FILE, "r");
  if (!file) {
    perror(KEYS_FILE);
    return false;
  }
  char line[256], word[16];
  while (fgets(line, sizeof line, file)) {
    if (sscanf(line, "%15s", word) != 1) continue;
    if (!strcmp(word, "screen")) sscanf(line, "%*s %d %d %d", &screen_w, &screen_h, &board_y);
    else if (!strcmp(word, "card")) sscanf(line, "%*s %d %d %d %d", &card_x, &card_y, &card_w, &first_key_y);
    else if (!strcmp(word, "button")) sscanf(line, "%*s %d %d %d", &button_x, &button_y, &button_size);
    else if (!strcmp(word, "timing")) sscanf(line, "%*s %d %d %d %d %d", &gap, &caps_tap, &repeat_delay, &repeat_interval, &dismiss_drag);
    else if (!strcmp(word, "key") && key_count < MAX_KEYS) {
      struct key *k = &keys[key_count];
      char kind[16], a[16], b[16];
      if (sscanf(line, "%*s %15s %d %d %d %d %15s %15s %15s", k->page, &k->x, &k->y, &k->w, &k->h, kind, a, b) != 8) continue;
      k->kind = !strcmp(kind, "delete") ? K_DELETE : !strcmp(kind, "return") ? K_RETURN : !strcmp(kind, "shift") ? K_SHIFT
              : !strcmp(kind, "page") ? K_PAGE : !strcmp(kind, "hide") ? K_HIDE : K_CHAR;
      if (k->kind == K_PAGE) snprintf(k->to, sizeof k->to, "%s", a);
      if (!strcmp(kind, "space")) strcpy(k->out, " "), strcpy(k->upper, " ");
      else if (k->kind == K_CHAR) snprintf(k->out, sizeof k->out, "%s", a), snprintf(k->upper, sizeof k->upper, "%s", b);
      key_count++;
    }
  }
  fclose(file);
  return key_count > 0 && screen_w > 0;
}

int main(void) {
  setvbuf(stderr, NULL, _IOLBF, 0);
  signal(SIGCHLD, SIG_DFL);
  if (!load_keys() || !load_keymap() || !open_uinput()) return 1;
  fprintf(stderr, "ready: %d keys\n", key_count);

  for (;;) {
    if (touch_fd < 0) find_touch();
    struct pollfd pfd = {.fd = touch_fd, .events = POLLIN};
    int timeout = touch_fd < 0 ? 300 : -1;
    if (repeat_key) {
      long left = repeat_at - now_ms();
      timeout = left < 0 ? 0 : (int)left;
    }
    int ready = poll(&pfd, touch_fd < 0 ? 0 : 1, timeout);
    if (repeat_key && now_ms() >= repeat_at) {
      press_key(repeat_key);
      repeat_at = now_ms() + repeat_interval;
    }
    if (ready <= 0 || touch_fd < 0) continue;
    struct input_event events[64];
    ssize_t got = read(touch_fd, events, sizeof events);
    if (got < 0 && errno == ENODEV) {
      close(touch_fd);
      touch_fd = -1;
      continue;
    }
    for (ssize_t i = 0; i < got / (ssize_t)sizeof events[0]; i++) handle_event(&events[i]);
  }
}
