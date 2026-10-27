# velum-osk: the on-screen keyboard's bridge to fcitx5 (see velum-osk.c).
#   make            build here
#   make install    to ~/.local/lib/velum/velum-osk, where henri.keyboard-v3 starts it
PREFIX ?= $(HOME)/.local
CFLAGS ?= -O2 -Wall -Wextra
PKGS = libsystemd xkbcommon wayland-client
VK = virtual-keyboard-unstable-v1

velum-osk: velum-osk.c $(VK)-protocol.c $(VK)-client-protocol.h
	$(CC) $(CFLAGS) -I. -o $@ velum-osk.c $(VK)-protocol.c $$(pkg-config --cflags --libs $(PKGS))

$(VK)-client-protocol.h: $(VK).xml
	wayland-scanner client-header $< $@
$(VK)-protocol.c: $(VK).xml
	wayland-scanner private-code $< $@

install: velum-osk
	install -Dm755 velum-osk $(PREFIX)/lib/velum/velum-osk

clean:
	rm -f velum-osk $(VK)-protocol.c $(VK)-client-protocol.h

.PHONY: install clean
