# velum-osk: the on-screen keyboard's bridge to fcitx5 (see velum-osk.c).
#   make            build here
#   make install    to ~/.local/lib/velum/velum-osk, where henri.keyboard-v3 starts it
PREFIX ?= $(HOME)/.local
CFLAGS ?= -O2 -Wall -Wextra
PKGS = libsystemd xkbcommon

velum-osk: velum-osk.c
	$(CC) $(CFLAGS) -o $@ $< $$(pkg-config --cflags --libs $(PKGS))

install: velum-osk
	install -Dm755 velum-osk $(PREFIX)/lib/velum/velum-osk

clean:
	rm -f velum-osk

.PHONY: install clean
