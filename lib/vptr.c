// A tiny virtual-pointer client: moves and clicks a Wayland compositor's pointer over its own socket
// (WAYLAND_DISPLAY), so input reaches that compositor and no other. Used by the tour recorder to drive a
// nested session that your own mouse cannot touch. ydotool cannot do this: it writes to the kernel, which
// only reaches your real seat.
//
//   vptr move X Y W H        put the pointer at X,Y on an output W by H pixels
//   vptr click X Y W H       move there, press and release the left button
//   vptr press X Y W H       move there, press the left button
//   vptr release X Y W H     move there, release the left button
//   vptr drag X Y W H DX DY  move there, press the left button, move by DX,DY in ten steps, release
//   vptr rclick X Y W H      move there, press and release the right button
//   vptr scroll X Y W H N    move there, turn the wheel N notches (positive scrolls down, negative up)
//   vptr probe               only the socket check below (the session runs it before wtype)
//   vptr names NAME...       no socket: exit 0 if every NAME is an output name a nested compositor has (HEADLESS-n, WAYLAND-n), else 3
//
// Every verb first checks the socket it was given and exits 3 unless it belongs to a nested compositor: WAYLAND_DISPLAY must be set and
// not equal DEVKIT_HOST_WAYLAND_DISPLAY (your own), and every wl_output the compositor lists must be named HEADLESS-n or WAYLAND-n, which
// is what a nested or headless Hyprland calls its outputs. Your own compositor lists real ones (eDP-1, DP-2 ...), so it is refused even
// when the variable names the wrong socket. With DEVKIT_ONLY_SOCKET_UNDER=DIR (the headless backend sets it) WAYLAND_DISPLAY must also be
// an absolute path inside DIR, the session's private runtime folder: a socket by name, which is looked for in your own, is refused.
//
// Built with lib/build-vptr.sh.
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>
#include "wlr-virtual-pointer-unstable-v1-client-protocol.h"

static struct wl_seat *seat;
static int n_outputs, n_bad_outputs;
static struct zwlr_virtual_pointer_manager_v1 *manager;

// A name is `PREFIX-` and digits only.
static int nested_name(const char *name) {
  static const char *const prefixes[] = { "HEADLESS-", "WAYLAND-" };
  for (unsigned i = 0; i < sizeof prefixes / sizeof *prefixes; i++) {
    size_t n = strlen(prefixes[i]);
    if (strncmp(name, prefixes[i], n)) continue;
    const char *d = name + n;
    if (!*d) return 0;
    for (; *d; d++) if (*d < '0' || *d > '9') return 0;
    return 1;
  }
  return 0;
}
static void output_name(void *data, struct wl_output *o, const char *name) {
  (void)data; (void)o;
  n_outputs++;
  if (!nested_name(name)) { n_bad_outputs++; fprintf(stderr, "vptr: refusing: output '%s' is not a nested one (HEADLESS-n or WAYLAND-n)\n", name); }
}
static void output_geometry(void *d, struct wl_output *o, int32_t x, int32_t y, int32_t pw, int32_t ph, int32_t sp, const char *mk, const char *md, int32_t tr) { (void)d; (void)o; (void)x; (void)y; (void)pw; (void)ph; (void)sp; (void)mk; (void)md; (void)tr; }
static void output_mode(void *d, struct wl_output *o, uint32_t f, int32_t w, int32_t h, int32_t r) { (void)d; (void)o; (void)f; (void)w; (void)h; (void)r; }
static void output_done(void *d, struct wl_output *o) { (void)d; (void)o; }
static void output_scale(void *d, struct wl_output *o, int32_t f) { (void)d; (void)o; (void)f; }
static void output_description(void *d, struct wl_output *o, const char *t) { (void)d; (void)o; (void)t; }
static const struct wl_output_listener output_listener = { output_geometry, output_mode, output_done, output_scale, output_name, output_description };

static void global(void *data, struct wl_registry *reg, uint32_t name, const char *iface, uint32_t version) {
  (void)data; (void)version;
  if (!strcmp(iface, wl_output_interface.name)) {
    if (version < 4) { n_outputs++; n_bad_outputs++; fprintf(stderr, "vptr: refusing: an output too old to say its name\n"); return; }
    struct wl_output *o = wl_registry_bind(reg, name, &wl_output_interface, 4);
    wl_output_add_listener(o, &output_listener, NULL);
  } else if (!strcmp(iface, wl_seat_interface.name)) seat = wl_registry_bind(reg, name, &wl_seat_interface, 1);
  else if (!strcmp(iface, zwlr_virtual_pointer_manager_v1_interface.name))
    manager = wl_registry_bind(reg, name, &zwlr_virtual_pointer_manager_v1_interface, 1);
}
static void global_remove(void *data, struct wl_registry *reg, uint32_t name) { (void)data; (void)reg; (void)name; }
static const struct wl_registry_listener listener = { global, global_remove };

static uint32_t now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);
}

int main(int argc, char **argv) {
  if (argc >= 2 && !strcmp(argv[1], "names")) {
    for (int i = 2; i < argc; i++) if (!nested_name(argv[i])) { fprintf(stderr, "vptr: '%s' is not a nested output name\n", argv[i]); return 3; }
    return argc > 2 ? 0 : 2;
  }
  const char *wd = getenv("WAYLAND_DISPLAY"), *host = getenv("DEVKIT_HOST_WAYLAND_DISPLAY");
  if (!wd || !*wd) { fprintf(stderr, "vptr: refusing: WAYLAND_DISPLAY is empty (it would be your own compositor)\n"); return 3; }
  if (host && *host && !strcmp(wd, host)) { fprintf(stderr, "vptr: refusing: WAYLAND_DISPLAY is your own compositor's socket (%s)\n", wd); return 3; }
  const char *only = getenv("DEVKIT_ONLY_SOCKET_UNDER");
  if (only && *only) {
    size_t n = strlen(only);
    if (strncmp(wd, only, n) || wd[n] != '/' || strstr(wd, "/../")) { fprintf(stderr, "vptr: refusing: WAYLAND_DISPLAY (%s) is not a socket inside %s\n", wd, only); return 3; }
  }
  int probe = argc == 2 && !strcmp(argv[1], "probe");
  if (!probe && argc != 6 && argc != 7 && argc != 8) { fprintf(stderr, "usage: vptr probe | move|click|rclick|press|release X Y W H | scroll X Y W H N | drag X Y W H DX DY\n"); return 2; }
  const char *verb = argv[1];
  uint32_t x = 0, y = 0, w = 0, h = 0;
  if (!probe) { x = (uint32_t)atoi(argv[2]); y = (uint32_t)atoi(argv[3]); w = (uint32_t)atoi(argv[4]); h = (uint32_t)atoi(argv[5]); }

  struct wl_display *display = wl_display_connect(NULL);
  if (!display) { fprintf(stderr, "vptr: cannot connect to WAYLAND_DISPLAY\n"); return 1; }
  struct wl_registry *registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &listener, NULL);
  wl_display_roundtrip(display);
  wl_display_roundtrip(display);   // the outputs' names arrive after they are bound
  if (n_outputs == 0 || n_bad_outputs > 0) { fprintf(stderr, "vptr: refusing: %s\n", n_outputs ? "this is not a nested compositor" : "the compositor lists no outputs"); return 3; }
  if (probe) { wl_display_disconnect(display); return 0; }
  if (!manager) { fprintf(stderr, "vptr: the compositor has no virtual-pointer protocol\n"); return 1; }

  struct zwlr_virtual_pointer_v1 *ptr = zwlr_virtual_pointer_manager_v1_create_virtual_pointer(manager, seat);
  zwlr_virtual_pointer_v1_motion_absolute(ptr, now_ms(), x, y, w, h);
  zwlr_virtual_pointer_v1_frame(ptr);
  const uint32_t BTN_LEFT = 0x110, BTN_RIGHT = 0x111;
  if (!strcmp(verb, "rclick")) {
    wl_display_roundtrip(display);
    usleep(60000);
    zwlr_virtual_pointer_v1_button(ptr, now_ms(), BTN_RIGHT, WL_POINTER_BUTTON_STATE_PRESSED);
    zwlr_virtual_pointer_v1_frame(ptr);
    wl_display_roundtrip(display);
    usleep(60000);
    zwlr_virtual_pointer_v1_button(ptr, now_ms(), BTN_RIGHT, WL_POINTER_BUTTON_STATE_RELEASED);
    zwlr_virtual_pointer_v1_frame(ptr);
  }
  if (!strcmp(verb, "scroll") && argc == 7) {
    // One notch is 15 units of smooth scrolling and one discrete step, as a wheel sends them; a pause between notches.
    int n = atoi(argv[6]), dir = n < 0 ? -1 : 1;
    wl_display_roundtrip(display);
    for (int i = 0; i < abs(n); i++) {
      usleep(70000);
      zwlr_virtual_pointer_v1_axis_source(ptr, WL_POINTER_AXIS_SOURCE_WHEEL);
      zwlr_virtual_pointer_v1_axis_discrete(ptr, now_ms(), WL_POINTER_AXIS_VERTICAL_SCROLL, wl_fixed_from_int(15 * dir), dir);
      zwlr_virtual_pointer_v1_frame(ptr);
      wl_display_roundtrip(display);
    }
  }
  if (!strcmp(verb, "drag") && argc == 8) {
    int dx = atoi(argv[6]), dy = atoi(argv[7]);
    wl_display_roundtrip(display);
    usleep(80000);
    zwlr_virtual_pointer_v1_button(ptr, now_ms(), BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
    zwlr_virtual_pointer_v1_frame(ptr);
    // Eased (slow, quick, slow), with the odd pixel of wobble and an uneven pace, like a hand.
    srand((unsigned)now_ms());
    for (int i = 1; i <= 14; i++) {
      double t = i / 14.0, e = t * t * t * (10 - 15 * t + 6 * t * t);   /* minimum jerk */
      int wx = (i < 14) ? rand() % 3 - 1 : 0, wy = (i < 14) ? rand() % 3 - 1 : 0;
      wl_display_roundtrip(display);
      usleep(35000 + (unsigned)(rand() % 40000));
      zwlr_virtual_pointer_v1_motion_absolute(ptr, now_ms(), (uint32_t)((int)x + (int)(dx * e) + wx), (uint32_t)((int)y + (int)(dy * e) + wy), w, h);
      zwlr_virtual_pointer_v1_frame(ptr);
    }
    wl_display_roundtrip(display);
    usleep(80000);
    zwlr_virtual_pointer_v1_button(ptr, now_ms(), BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
    zwlr_virtual_pointer_v1_frame(ptr);
  }
  if (!strcmp(verb, "click") || !strcmp(verb, "press")) {
    wl_display_roundtrip(display);
    usleep(60000);
    zwlr_virtual_pointer_v1_button(ptr, now_ms(), BTN_LEFT, WL_POINTER_BUTTON_STATE_PRESSED);
    zwlr_virtual_pointer_v1_frame(ptr);
  }
  if (!strcmp(verb, "click") || !strcmp(verb, "release")) {
    wl_display_roundtrip(display);
    usleep(60000);
    zwlr_virtual_pointer_v1_button(ptr, now_ms(), BTN_LEFT, WL_POINTER_BUTTON_STATE_RELEASED);
    zwlr_virtual_pointer_v1_frame(ptr);
  }
  wl_display_roundtrip(display);
  zwlr_virtual_pointer_v1_destroy(ptr);
  wl_display_roundtrip(display);
  wl_display_disconnect(display);
  return 0;
}
