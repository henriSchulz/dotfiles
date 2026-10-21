#!/bin/sh
# builds tests/vptr/vptr (binary and generated files are git-ignored)
set -e
cd "$(dirname "$0")"
wayland-scanner client-header wlr-virtual-pointer-unstable-v1.xml vp.h
wayland-scanner private-code wlr-virtual-pointer-unstable-v1.xml vp.c
cc -O2 -Wall -o vptr vptr.c vp.c $(pkg-config --cflags --libs wayland-client)
