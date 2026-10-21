/* A real pointer for the Launchpad rig: a virtual pointer in the compositor named by WAYLAND_DISPLAY (the
 * nested rig, never the live session), bound to one output so absolute positions are that output's pixels.
 * Adapted from mdview's dev/vptr.
 *   vptr OUTPUT W H  m X Y | g X Y STEPS MS | d | u | rd | ru | s MS | w ±1 N MS | f DX DY STEPS MS …
 * m: move to; g: glide to X Y in STEPS, MS apart; d/u: left button, rd/ru: right; s: sleep;
 * w: wheel N notches; f: two-finger scroll of DX DY pixels in STEPS (touchpad), then axis stop. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include "vp.h"

static struct zwlr_virtual_pointer_manager_v1 *manager;
static struct wl_output *outputs[16];
static char names[16][64];
static int nout;
static void out_geometry(void *d, struct wl_output *o, int32_t x, int32_t y, int32_t pw, int32_t ph, int32_t s, const char *mk, const char *md, int32_t t) {
  (void)d; (void)o; (void)x; (void)y; (void)pw; (void)ph; (void)s; (void)mk; (void)md; (void)t; }
static void out_mode(void *d, struct wl_output *o, uint32_t f, int32_t w, int32_t h, int32_t r) { (void)d; (void)o; (void)f; (void)w; (void)h; (void)r; }
static void out_done(void *d, struct wl_output *o) { (void)d; (void)o; }
static void out_scale(void *d, struct wl_output *o, int32_t f) { (void)d; (void)o; (void)f; }
static void out_name(void *d, struct wl_output *o, const char *name) {
  (void)o; snprintf(names[(intptr_t)d], sizeof names[0], "%s", name); }
static void out_desc(void *d, struct wl_output *o, const char *s) { (void)d; (void)o; (void)s; }
static const struct wl_output_listener out_listener = { out_geometry, out_mode, out_done, out_scale, out_name, out_desc };
static void global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t v) {
  (void)d;
  if (!strcmp(iface, zwlr_virtual_pointer_manager_v1_interface.name)) manager = wl_registry_bind(r, name, &zwlr_virtual_pointer_manager_v1_interface, v < 2 ? v : 2);
  else if (!strcmp(iface, wl_output_interface.name) && nout < 16 && v >= 4) {
    outputs[nout] = wl_registry_bind(r, name, &wl_output_interface, 4);
    wl_output_add_listener(outputs[nout], &out_listener, (void *)(intptr_t)nout);
    nout++;
  }
}
static void gone(void *d, struct wl_registry *r, uint32_t name) { (void)d; (void)r; (void)name; }
static const struct wl_registry_listener listener = { global, gone };
static uint32_t now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint32_t)(t.tv_sec * 1000 + t.tv_nsec / 1000000); }

int main(int argc, char **argv) {
  if (argc < 5) { fprintf(stderr, "vptr OUTPUT W H commands…\n"); return 2; }
  struct wl_display *dpy = wl_display_connect(NULL);
  if (!dpy) { fprintf(stderr, "vptr: no display\n"); return 1; }
  struct wl_registry *reg = wl_display_get_registry(dpy);
  wl_registry_add_listener(reg, &listener, NULL);
  wl_display_roundtrip(dpy);
  wl_display_roundtrip(dpy);
  if (!manager) { fprintf(stderr, "vptr: the compositor has no virtual pointer\n"); return 1; }
  struct wl_output *target = NULL;
  for (int i = 0; i < nout; i++) if (!strcmp(names[i], argv[1])) target = outputs[i];
  if (!target) { fprintf(stderr, "vptr: no output %s\n", argv[1]); return 1; }
  struct zwlr_virtual_pointer_v1 *p = zwlr_virtual_pointer_manager_v1_create_virtual_pointer_with_output(manager, NULL, target);
  uint32_t W = (uint32_t)atoi(argv[2]), H = (uint32_t)atoi(argv[3]);
  double x = 0, y = 0;
  #define MOVE(nx, ny) do { x = (nx); y = (ny); zwlr_virtual_pointer_v1_motion_absolute(p, now(), (uint32_t)(x + 0.5), (uint32_t)(y + 0.5), W, H); zwlr_virtual_pointer_v1_frame(p); wl_display_roundtrip(dpy); } while (0)
  for (int i = 4; i < argc; i++) {
    const char *c = argv[i];
    if (!strcmp(c, "m") && i + 2 < argc) { MOVE(atof(argv[i + 1]), atof(argv[i + 2])); i += 2; }
    else if (!strcmp(c, "g") && i + 4 < argc) {
      double tx = atof(argv[i + 1]), ty = atof(argv[i + 2]), sx = x, sy = y; int n = atoi(argv[i + 3]), ms = atoi(argv[i + 4]);
      for (int k = 1; k <= n; k++) { MOVE(sx + (tx - sx) * k / n, sy + (ty - sy) * k / n); usleep(ms * 1000); }
      i += 4;
    }
    else if (!strcmp(c, "d") || !strcmp(c, "u")) { zwlr_virtual_pointer_v1_button(p, now(), 0x110, c[0] == 'd'); zwlr_virtual_pointer_v1_frame(p); wl_display_roundtrip(dpy); }
    else if (!strcmp(c, "rd") || !strcmp(c, "ru")) { zwlr_virtual_pointer_v1_button(p, now(), 0x111, c[1] == 'd'); zwlr_virtual_pointer_v1_frame(p); wl_display_roundtrip(dpy); }
    else if (!strcmp(c, "s") && i + 1 < argc) { usleep(atoi(argv[++i]) * 1000); }
    else if (!strcmp(c, "w") && i + 3 < argc) {
      int dir = atoi(argv[i + 1]) < 0 ? -1 : 1, n = atoi(argv[i + 2]), ms = atoi(argv[i + 3]);
      for (int k = 0; k < n; k++) {
        zwlr_virtual_pointer_v1_axis_source(p, WL_POINTER_AXIS_SOURCE_WHEEL);
        zwlr_virtual_pointer_v1_axis_discrete(p, now(), WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_double(15.0 * dir), dir);
        zwlr_virtual_pointer_v1_frame(p); wl_display_roundtrip(dpy); usleep(ms * 1000);
      }
      i += 3;
    }
    else if (!strcmp(c, "f") && i + 4 < argc) {
      double dx = atof(argv[i + 1]), dy = atof(argv[i + 2]); int n = atoi(argv[i + 3]), ms = atoi(argv[i + 4]);
      for (int k = 0; k < n; k++) {
        zwlr_virtual_pointer_v1_axis_source(p, WL_POINTER_AXIS_SOURCE_FINGER);
        if (dx != 0) zwlr_virtual_pointer_v1_axis(p, now(), WL_POINTER_AXIS_HORIZONTAL_SCROLL, wl_fixed_from_double(dx / n));
        if (dy != 0) zwlr_virtual_pointer_v1_axis(p, now(), WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_double(dy / n));
        zwlr_virtual_pointer_v1_frame(p); wl_display_roundtrip(dpy); usleep(ms * 1000);
      }
      zwlr_virtual_pointer_v1_axis_source(p, WL_POINTER_AXIS_SOURCE_FINGER);
      zwlr_virtual_pointer_v1_axis_stop(p, now(), WL_POINTER_AXIS_HORIZONTAL_SCROLL);
      zwlr_virtual_pointer_v1_axis_stop(p, now(), WL_POINTER_AXIS_VERTICAL_SCROLL);
      zwlr_virtual_pointer_v1_frame(p); wl_display_roundtrip(dpy);
      i += 4;
    }
    else { fprintf(stderr, "vptr: what is %s?\n", c); return 2; }
  }
  zwlr_virtual_pointer_v1_destroy(p);
  wl_display_roundtrip(dpy);
  return 0;
}
