#!/usr/bin/env python3
"""mdview — fast, complete Markdown viewer and editor (GTK 3 + WebKit).

Renders CommonMark/GFM plus Obsidian syntax (wikilinks, embeds, callouts,
properties, ==highlight==, %%comments%%, #tags), KaTeX math, Mermaid and
highlighted code. Works on any file, no vault needed. Stays resident for a
while after the last window closes so reopening is instant.

Ctrl+E switches between reading and editing the source in place; edits are
saved automatically (the page sends the text, this side writes the file).
Ctrl+V with an image on the clipboard saves it as a file and embeds it: at the
caret while editing, at the end of the note while reading.

Opened on a folder (or started without arguments, which reopens the last
folder) the window gets a sidebar listing the folder's notes, by file name or
by title (first H1), and can create, rename and trash them.

Assets live next to the real path of this script; bin/mdview is a thin
launcher that hands files to a running instance over D-Bus.
Colors follow the Omarchy theme, motion follows ~/.local/share/henri-ui.
"""

import html
import json
import os
import re
import secrets
import subprocess
import sys
import time
import tomllib
from pathlib import Path
from urllib.parse import quote, unquote, urlparse

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("WebKit2", "4.1")
from gi.repository import Gdk, Gio, GLib, Gtk, WebKit2  # noqa: E402

APP_ID = "dev.henri.MdView"
HOME = Path.home()
SOURCE = Path(os.path.realpath(__file__))
ASSETS = SOURCE.parent
SOURCE_STAMP = SOURCE.stat().st_mtime_ns
THEME_DIR = HOME / ".local/state/omarchy/current"
MOTION_CSS = HOME / ".local/share/henri-ui/motion.css"
STATE_FILE = Path(GLib.get_user_state_dir()) / "mdview" / "state.json"
DEBUG = bool(os.environ.get("MDVIEW_DEBUG"))
RESIDENT_MS = 15 * 60 * 1000

MD_EXT = {".md", ".markdown", ".mdown", ".mkd", ".mkdn", ".mdx"}
IMG_EXT = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp", ".avif", ".ico"}
AUDIO_EXT = {".mp3", ".wav", ".ogg", ".m4a", ".flac", ".opus", ".webm"}
VIDEO_EXT = {".mp4", ".mkv", ".mov", ".ogv"}
# clipboard formats kept as they are when pasted; anything else is saved as PNG
PASTE_MIME = (("image/png", ".png"), ("image/jpeg", ".jpg"), ("image/webp", ".webp"),
              ("image/gif", ".gif"), ("image/avif", ".avif"), ("image/svg+xml", ".svg"))
SKIP_DIRS = {"node_modules", "__pycache__", "target", "venv", ".venv", "dist", "build"}
WIKI_RE = re.compile(r"!?\[\[([^\[\]\n]+?)\]\]")
EMBED_LIMIT = 256 * 1024
EDIT_LIMIT = 2 * 1024 * 1024
TITLE_SCAN = 16 * 1024    # a note's title (first H1) is looked for this far in
NOTE_LIMIT = 5000         # notes listed in the sidebar at most
WATCH_LIMIT = 400         # directories watched below an open folder
SIDEBAR_WIDTH = 260       # extra default width of a folder window; matches --sb-w
FENCE_RE = re.compile(r"^\s*(`{3,}|~{3,})(.*)$")
H1_RE = re.compile(r"^ {0,3}#[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*$")

SCRIPTS = [
    "vendor/markdown-it.min.js",
    "vendor/footnote.min.js",
    "vendor/deflist.min.js",
    "vendor/mark.min.js",
    "vendor/sub.min.js",
    "vendor/sup.min.js",
    "vendor/abbr.min.js",
    "vendor/emoji.min.js",
    "vendor/js-yaml.min.js",
    "vendor/highlight.min.js",
    "vendor/katex/katex.min.js",
    "viewer.js",
]
THEME_KEYS = (
    "background", "foreground", "accent", "muted", "selection",
    "red", "green", "yellow", "orange", "blue", "cyan", "magenta", "brown",
    "bright_red", "bright_green", "bright_yellow", "bright_blue",
    "bright_magenta", "bright_cyan",
)
LIGHT_FALLBACK = {"background": "#ffffff", "foreground": "#1d1d1f", "accent": "#0071e3",
                  "muted": "#8e8e93", "selection": "#b4d5fe"}


# ---------------------------------------------------------------- helpers

def luminance(hex_color):
    h = hex_color.lstrip("#")[:6]
    try:
        r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    except ValueError:
        return 1.0
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def load_theme():
    try:
        data = tomllib.loads((THEME_DIR / "theme/colors.toml").read_text())
    except (OSError, tomllib.TOMLDecodeError):
        data = {}
    colors = dict(LIGHT_FALLBACK)
    colors.update({k: data[k] for k in THEME_KEYS if isinstance(data.get(k), str)})
    mode = data.get("mode")
    if mode not in ("light", "dark"):
        mode = "light" if luminance(colors["background"]) > 0.5 else "dark"
    return {"mode": mode, "colors": colors}


def theme_css(theme):
    body = ";".join(f"--c-{k.replace('_', '-')}:{v}" for k, v in theme["colors"].items())
    return f":root{{{body};color-scheme:{theme['mode']}}}"


def read_text(path, limit=None):
    with open(path, "rb") as f:
        raw = f.read(limit) if limit else f.read()
    return raw.decode("utf-8", errors="replace")


def readonly_reason(path, raw):
    """Why the file can't be edited in place, or None if it can."""
    if raw is None:
        return None if os.access(path.parent, os.W_OK) else "folder is read-only"
    if not os.access(path, os.W_OK):
        return "file is read-only"
    if len(raw) > EDIT_LIMIT:
        return "file is too large"
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError:
        return "file is not UTF-8"
    return None


def note_title(path):
    """First H1 of a note (frontmatter and code blocks skipped), or None."""
    try:
        lines = read_text(path, TITLE_SCAN).splitlines()
    except OSError:
        return None
    start = 0
    if lines and lines[0].strip() == "---":
        for i in range(1, len(lines)):
            if lines[i].strip() in ("---", "..."):
                start = i + 1
                break
    fence = None
    for line in lines[start:]:
        m = FENCE_RE.match(line)
        if fence:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not m.group(2).strip():
                fence = None
            continue
        if m:
            fence = m.group(1)
            continue
        m = H1_RE.match(line)
        if m:
            t = re.sub(r"!?\[\[(?:[^\]|]*\|)?([^\]]*)\]\]", r"\1", m.group(1))
            t = re.sub(r"!?\[([^\]]*)\]\([^)]*\)", r"\1", t)
            t = re.sub(r"(\*\*|__|~~|==|[*`])", "", t).strip()
            return t or None
    return None


def clean_name(name):
    """A typed note name as a safe file name stem part (no path, not hidden)."""
    return re.sub(r"[/\\\x00-\x1f]", " ", str(name or "")).strip().lstrip(". ")


def natural_key(name):
    return [int(t) if t.isdigit() else t for t in re.split(r"(\d+)", name.lower())]


def scan_folder(root, cache, titles):
    """The notes below root as a tree, plus every directory walked (to watch).
    Hidden entries and SKIP_DIRS are left out, as are folders without notes.
    Titles are only read when asked for; cache maps path -> (stat key, title)."""
    walked, count = [], 0
    deadline = time.monotonic() + 1.5

    def walk(d, depth):
        nonlocal count
        node = {"name": d.name, "path": str(d), "dirs": [], "notes": []}
        walked.append(d)
        try:
            entries = sorted(os.scandir(d), key=lambda e: natural_key(e.name))
        except OSError:
            return node
        for e in entries:
            if e.name.startswith("."):
                continue
            try:
                if e.is_dir(follow_symlinks=False):
                    if e.name in SKIP_DIRS or depth >= 12 or count >= NOTE_LIMIT \
                            or time.monotonic() > deadline:
                        continue
                    sub = walk(Path(e.path), depth + 1)
                    if sub["dirs"] or sub["notes"]:
                        node["dirs"].append(sub)
                elif os.path.splitext(e.name)[1].lower() in MD_EXT and e.is_file() \
                        and count < NOTE_LIMIT:
                    title = None
                    if titles:
                        st = e.stat()
                        key = (st.st_mtime_ns, st.st_size)
                        hit = cache.get(e.path)
                        if not hit or hit[0] != key:
                            hit = cache[e.path] = (key, note_title(e.path))
                        title = hit[1]
                    node["notes"].append({"name": os.path.splitext(e.name)[0], "path": e.path,
                                          "real": os.path.realpath(e.path), "title": title})
                    count += 1
            except OSError:
                continue
        return node

    return walk(root, 0), walked


def tree_notes(node):
    for n in node["notes"]:
        yield n
    for d in node["dirs"]:
        yield from tree_notes(d)


def load_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except (OSError, ValueError):
        return {}


def save_state(state):
    try:
        STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        STATE_FILE.write_text(json.dumps(state))
    except OSError:
        pass


def file_kind(path):
    ext = path.suffix.lower()
    if ext in MD_EXT:
        return "md"
    if ext in IMG_EXT:
        return "image"
    if ext in AUDIO_EXT:
        return "audio"
    if ext in VIDEO_EXT:
        return "video"
    if ext == ".pdf":
        return "pdf"
    return "file"


def clipboard_image():
    """The image on the clipboard as (bytes, file extension), or None."""
    cb = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
    ok, atoms = cb.wait_for_targets()
    have = {a.name() for a in atoms} if ok else set()
    for mime, ext in PASTE_MIME:
        if mime in have:
            sel = cb.wait_for_contents(Gdk.Atom.intern(mime, False))
            data = sel.get_data() if sel else None
            if data:
                return bytes(data), ext
    pixbuf = cb.wait_for_image() if cb.wait_is_image_available() else None
    if pixbuf:
        ok, data = pixbuf.save_to_bufferv("png", [], [])
        if ok:
            return bytes(data), ".png"
    return None


def launch_uri(uri):
    try:
        Gio.AppInfo.launch_default_for_uri(uri, None)
    except GLib.Error:
        subprocess.Popen(["xdg-open", uri], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class Resolver:
    """Resolves Obsidian wikilink targets like Obsidian does: next to the
    note, at the vault root, then anywhere below the root by file name.
    The root is the nearest ancestor holding .obsidian, else the note's dir."""

    def __init__(self, note_dir):
        self.note_dir = note_dir
        self.vault = None
        for p in (note_dir, *note_dir.parents):
            if (p / ".obsidian").is_dir():
                self.vault = p
                break
            if p == HOME:
                break
        self._index = None

    def index(self):
        if self._index is None:
            idx, count = {}, 0
            deadline = time.monotonic() + 0.3
            for dirpath, dirnames, filenames in os.walk(self.vault or self.note_dir):
                dirnames[:] = [d for d in dirnames if not d.startswith(".") and d not in SKIP_DIRS]
                for f in filenames:
                    idx.setdefault(f.lower(), []).append(os.path.join(dirpath, f))
                count += len(filenames)
                if count > 60000 or time.monotonic() > deadline:
                    break
            self._index = idx
        return self._index

    def resolve(self, target):
        name = re.split(r"[#^]", target, maxsplit=1)[0].strip()
        if not name:
            return None
        cands = [name] if Path(name).suffix.lower() in MD_EXT else [name + ".md", name]
        bases = [self.note_dir] + ([self.vault] if self.vault else [])
        for c in cands:
            for b in bases:
                p = b / c
                if p.is_file():
                    return p.resolve()
        idx = self.index()
        here = str(self.note_dir)
        for c in cands:
            hits = idx.get(Path(c).name.lower())
            if not hits:
                continue
            if "/" in c:
                hits = [h for h in hits if h.lower().endswith("/" + c.lower())] or hits
            best = min(hits, key=lambda h: (not h.startswith(here), h.count(os.sep), h))
            return Path(best)
        return None


# ---------------------------------------------------------------- window

class ViewerWindow(Gtk.ApplicationWindow):
    def __init__(self, app, path, folder=None):
        super().__init__(application=app, title="Markdown")
        self.app = app
        self.path = None
        self.folder = None          # set: this window browses a folder (sidebar)
        self.tree = None
        self.tree_json = None
        self.note_paths = set()
        self.title_cache = {}
        self.dir_monitors = []
        self.rescan_id = 0
        self.shell_ready = False
        self.loading_shell = False
        self.pending_fragment = None
        self.back, self.fwd = [], []
        self.monitor = None
        self.reload_id = 0
        self.resolver = None
        self.editing = False
        self.own_text = None
        self.own_write = None       # bytes just written here: the reload for them is skipped
        self.closing = False
        self.close_id = 0

        st = app.state
        if folder:
            self.set_default_size(st.get("folder_width", st.get("width", 900) + SIDEBAR_WIDTH),
                                  st.get("folder_height", st.get("height", 1040)))
        else:
            self.set_default_size(st.get("width", 900), st.get("height", 1040))
        self.set_icon_name("mdview")
        bg = Gdk.RGBA()
        bg.parse(app.theme["colors"]["background"])
        self.override_background_color(Gtk.StateFlags.NORMAL, bg)

        ucm = WebKit2.UserContentManager()
        ucm.register_script_message_handler("mdview")
        ucm.connect("script-message-received::mdview", self.on_message)
        self.view = WebKit2.WebView.new_with_user_content_manager(ucm)
        self.view.set_settings(app.web_settings)
        self.view.set_background_color(bg)
        self.view.set_zoom_level(st.get("zoom", 1.0))
        self.view.connect("load-changed", self.on_load_changed)
        self.view.connect("decide-policy", self.on_decide_policy)
        self.view.connect("context-menu", self.on_context_menu)
        self.view.connect("web-process-terminated", lambda *_: self.load_shell(force=True))
        self.add(self.view)
        self.connect("delete-event", self.on_delete)
        self.view.show()

        if folder:
            self.set_folder(folder)
        elif path:
            self.open_path(path, push=False)
        else:
            GLib.idle_add(self.choose_file)

    # -- loading --------------------------------------------------------

    def load_shell(self, force=False):
        if self.shell_ready and not force:
            self.render()
            return
        # One shell per window. Relative links and images resolve against
        # <base>, which the page points at the directory of the note shown.
        target_dir = self.path.parent if self.path else self.folder or HOME
        self.tree_json = None
        self.shell_ready = False
        self.loading_shell = True
        self.editing = False
        nonce = secrets.token_urlsafe(18)
        a = ASSETS.as_uri()
        csp = ("default-src 'none'; "
               f"script-src 'nonce-{nonce}'; "
               "style-src 'unsafe-inline' file: https:; "
               "img-src file: data: blob: https: http:; "
               "font-src file: data:; media-src file: https: http:")
        scripts = "".join(f'<script nonce="{nonce}" src="{a}/{s}"></script>' for s in SCRIPTS)
        page = (
            "<!doctype html><html lang='en'><head><meta charset='utf-8'>"
            f"<meta http-equiv='Content-Security-Policy' content=\"{csp}\">"
            f"<base href='{html.escape(target_dir.as_uri(), quote=True)}/'>"
            f"<style id='henri-ui'>{self.app.motion_css}</style>"
            f"<style id='theme'>{theme_css(self.app.theme)}</style>"
            f"<link rel='stylesheet' href='{a}/vendor/katex/katex.min.css'>"
            f"<link rel='stylesheet' href='{a}/viewer.css'>"
            f"</head><body data-mode='{self.app.theme['mode']}'><main id='content'></main>"
            f"{scripts}</body></html>"
        )
        self.view.load_html(page, target_dir.as_uri() + "/")

    def on_load_changed(self, view, event):
        if event == WebKit2.LoadEvent.FINISHED:
            self.loading_shell = False
            self.shell_ready = True
            self.send_folder()
            self.render(fragment=self.pending_fragment)
            self.pending_fragment = None

    def open_path(self, path, fragment=None, push=True):
        path = Path(path).expanduser()
        try:
            path = path.resolve()
        except OSError:
            pass
        if push and self.path and path != self.path:
            self.back.append(self.path)
            self.fwd.clear()
        same = path == self.path
        self.path = path
        self.set_title(path.name)
        self.resolver = Resolver(path.parent)
        if not same:
            self.own_text = None
            self.watch()
            if self.folder and path.is_relative_to(self.folder):
                last = self.app.state.setdefault("last_notes", {})
                last.pop(str(self.folder), None)
                last[str(self.folder)] = str(path)
                for old in list(last)[:-20]:
                    del last[old]
                save_state(self.app.state)
        if same and self.shell_ready:
            if fragment:
                self.js("MdView.scrollToFragment", fragment, True)
            return
        self.pending_fragment = fragment
        if self.shell_ready:
            self.render(fragment=fragment)
            self.pending_fragment = None
        else:
            self.load_shell()

    def watch(self):
        if self.monitor:
            self.monitor.cancel()
        try:
            self.monitor = Gio.File.new_for_path(str(self.path)).monitor_file(
                Gio.FileMonitorFlags.WATCH_MOVES, None)
            self.monitor.set_rate_limit(80)
            self.monitor.connect("changed", self.on_file_changed)
        except GLib.Error:
            self.monitor = None

    def on_file_changed(self, _mon, _file, _other, event):
        if event in (Gio.FileMonitorEvent.ATTRIBUTE_CHANGED, Gio.FileMonitorEvent.PRE_UNMOUNT):
            return
        if self.reload_id:
            GLib.source_remove(self.reload_id)
        # Editors save by delete + rename; wait for the dust to settle.
        self.reload_id = GLib.timeout_add(90, self.reload_after_change)

    def reload_after_change(self):
        self.reload_id = 0
        if self.path and self.path.exists():
            own, self.own_write = self.own_write, None
            if own is not None:
                try:
                    with open(self.path, "rb") as f:
                        if f.read() == own:
                            return False  # already on screen
                except OSError:
                    pass
            if self.editing and self.own_text is not None:
                try:
                    if read_text(self.path).replace("\r\n", "\n") == self.own_text:
                        return False  # our own save; the editor already has it
                except OSError:
                    pass
            self.resolver = Resolver(self.path.parent)
            self.render(keep_scroll=True)
        return False

    # -- folder (sidebar) ---------------------------------------------------

    def set_folder(self, folder):
        folder = Path(folder).expanduser()
        try:
            folder = folder.resolve()
        except OSError:
            pass
        self.folder = folder
        self.tree_json = None
        self.title_cache = {}
        self.app.state["folder"] = str(folder)
        save_state(self.app.state)
        self.rescan()
        notes = {n["real"]: n for n in tree_notes(self.tree)}
        last = self.app.state.get("last_notes", {}).get(str(folder))
        first = last if last in notes else next(iter(notes), None)
        if self.path and str(self.path) in notes:
            return
        if first:
            self.open_path(first, push=bool(self.path))
        else:
            self.show_nothing()

    def show_nothing(self):
        """Nothing to show: an empty folder, or its last note is gone."""
        if self.monitor:
            self.monitor.cancel()
            self.monitor = None
        self.path = None
        self.back.clear()
        self.fwd.clear()
        self.set_title(self.folder.name or str(self.folder))
        if self.shell_ready:
            self.js("MdView.clear")
        else:
            self.load_shell()

    def rescan(self):
        self.rescan_id = 0
        if not self.folder:
            return False
        titles = bool(self.app.state.get("sidebar_titles"))
        self.tree, walked = scan_folder(self.folder, self.title_cache, titles)
        self.note_paths = {n["path"] for n in tree_notes(self.tree)}
        have = {m.dir for m in self.dir_monitors}
        want = set(walked[:WATCH_LIMIT])
        for mon in [m for m in self.dir_monitors if m.dir not in want]:
            mon.cancel()
            self.dir_monitors.remove(mon)
        for d in want - have:
            try:
                mon = Gio.File.new_for_path(str(d)).monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)
            except GLib.Error:
                continue
            mon.dir = d
            mon.connect("changed", self.on_dir_changed)
            self.dir_monitors.append(mon)
        self.send_folder()
        return False

    def on_dir_changed(self, _mon, _file, _other, event):
        if event == Gio.FileMonitorEvent.ATTRIBUTE_CHANGED:
            return
        if self.rescan_id:
            GLib.source_remove(self.rescan_id)
        self.rescan_id = GLib.timeout_add(300, self.rescan)

    def send_folder(self):
        if not self.folder or not self.shell_ready:
            return
        st = self.app.state
        payload = {
            "root": str(self.folder),
            "name": self.folder.name or str(self.folder),
            "tree": self.tree,
            "titles": bool(st.get("sidebar_titles")),
            "visible": st.get("sidebar", True),
        }
        blob = json.dumps(payload, sort_keys=True)
        if blob != self.tree_json:
            self.tree_json = blob
            self.js("MdView.setFolder", payload)

    def open_note(self, path):
        if self.folder and path in self.note_paths:
            self.open_path(path)

    def new_note(self, name, where):
        if not self.folder:
            return
        target = Path(where) if where else self.folder
        try:
            target = target.resolve()
        except OSError:
            target = self.folder
        if not target.is_dir() or not target.is_relative_to(self.folder):
            target = self.folder
        name = clean_name(name) or "Untitled"
        stem = name[:-3].rstrip() if name.lower().endswith(".md") else name
        path = target / f"{stem or 'Untitled'}.md"
        try:
            with open(path, "x", encoding="utf-8") as f:
                f.write(f"# {stem}\n\n")
        except FileExistsError:
            self.js("MdView.toast", f"“{path.name}” already exists")
            if path.is_file():
                self.rescan()
                self.open_path(path)
            return
        except OSError as e:
            self.js("MdView.toast", f"Couldn't create note: {e.strerror}")
            return
        self.rescan_now()
        self.open_path(path)
        self.js("MdView.setMode", "edit", "end")

    def rescan_now(self):
        if self.rescan_id:
            GLib.source_remove(self.rescan_id)
        self.rescan()

    def rename_note(self, path, name):
        if not self.folder or path not in self.note_paths:
            return
        old = Path(path)
        stem = clean_name(name)
        if stem.lower().endswith(old.suffix.lower()):
            stem = stem[:-len(old.suffix)].rstrip()
        new = old.with_name(stem + old.suffix)
        if not stem or new == old:
            return
        try:
            if os.path.lexists(new) and not os.path.samefile(old, new):
                self.js("MdView.toast", f"“{new.name}” already exists")
                return
            old_real = os.path.realpath(old)
            os.rename(old, new)
        except OSError as e:
            self.js("MdView.toast", f"Couldn't rename: {e.strerror}")
            return
        new_real = os.path.realpath(new)
        swap = lambda p: Path(new_real) if str(p) == old_real else p
        self.back = [swap(p) for p in self.back]
        self.fwd = [swap(p) for p in self.fwd]
        if self.path and str(self.path) == old_real and new_real != old_real:
            # the note on screen: it stays as it is (also mid-edit), under its new name
            self.path = Path(new_real)
            self.set_title(self.path.name)
            self.watch()
            last = self.app.state.setdefault("last_notes", {})
            last[str(self.folder)] = new_real
            save_state(self.app.state)
        self.js("MdView.noteRenamed", {"old": str(old), "path": str(new), "oldReal": old_real,
                                       "real": new_real, "name": Path(new_real).name})
        self.rescan_now()

    def trash_note(self, path):
        if not self.folder or path not in self.note_paths:
            return
        real = os.path.realpath(path)
        nxt = None
        if self.path and str(self.path) == real:
            notes = list(tree_notes(self.tree))
            i = next((k for k, n in enumerate(notes) if n["path"] == path), -1)
            rest = notes[i + 1:i + 2] or notes[max(i - 1, 0):i]
            nxt = rest[0]["real"] if rest else None
        try:
            Gio.File.new_for_path(path).trash(None)
        except GLib.Error as e:
            self.js("MdView.toast", f"Couldn't move to Trash: {e.message}")
            return
        self.back = [p for p in self.back if str(p) != real]
        self.fwd = [p for p in self.fwd if str(p) != real]
        self.js("MdView.toast", f"Moved “{Path(path).name}” to Trash")
        was_current = self.path and str(self.path) == real
        self.rescan_now()
        if was_current:
            if nxt:
                self.open_path(nxt, push=False)
            else:
                self.show_nothing()

    def sidebar_pref(self, msg):
        st = self.app.state
        if "visible" in msg:
            st["sidebar"] = bool(msg["visible"])
        if "titles" in msg:
            st["sidebar_titles"] = bool(msg["titles"])
        save_state(st)
        for w in self.app.windows():
            if w.folder:
                w.rescan()

    def choose_folder(self):
        dlg = Gtk.FileChooserNative.new("Open Folder", self, Gtk.FileChooserAction.SELECT_FOLDER,
                                        "Open", "Cancel")
        if self.folder or self.path:
            dlg.set_current_folder(str(self.folder or self.path.parent))
        if dlg.run() == Gtk.ResponseType.ACCEPT:
            self.set_folder(dlg.get_filename())
        dlg.destroy()

    def build_links(self, text):
        links = {}
        seen_texts = [text]
        while seen_texts:
            chunk = seen_texts.pop()
            for m in WIKI_RE.finditer(chunk):
                target = m.group(1).split("|", 1)[0].strip()
                if target in links or target.startswith("#"):
                    continue
                p = self.resolver.resolve(target)
                if not p:
                    links[target] = None
                    continue
                kind = file_kind(p)
                info = {"path": str(p), "url": p.as_uri(), "kind": kind}
                if kind == "md" and m.group(0).startswith("!") and len(links) < 400:
                    try:
                        info["text"] = read_text(p, EMBED_LIMIT)
                        seen_texts.append(info["text"])
                    except OSError:
                        pass
                links[target] = info
        return links

    def render(self, keep_scroll=False, fragment=None, end=False):
        if not self.shell_ready or not self.path:
            return
        raw = None
        try:
            with open(self.path, "rb") as f:
                raw = f.read()
            text, error = raw.decode("utf-8", errors="replace"), None
            readonly = readonly_reason(self.path, raw)
        except FileNotFoundError:
            text, error = "", f"File not found: {self.path}"
            readonly = readonly_reason(self.path, None)
        except OSError as e:
            text, error = "", f"Can't read file: {e.strerror}"
            readonly = "file can't be read"
        payload = {
            "text": text,
            "name": self.path.name,
            "path": str(self.path),
            "base": self.path.parent.as_uri() + "/",
            "readonly": readonly,
            "vault": bool(self.resolver and self.resolver.vault),
            "links": self.build_links(text) if "[[" in text else {},
            "keepScroll": keep_scroll,
            "fragment": fragment,
            "toEnd": end,
            "error": error,
            "canBack": bool(self.back),
        }
        self.js("MdView.render", payload)

    def js(self, fn, *args):
        script = f"{fn}({','.join(json.dumps(a, ensure_ascii=False) for a in args)})"
        self.view.evaluate_javascript(script, -1, None, None, None, None, None)

    # -- web view policy --------------------------------------------------

    def on_decide_policy(self, view, decision, kind):
        if kind == WebKit2.PolicyDecisionType.RESPONSE:
            return False
        action = decision.get_navigation_action()
        nav = action.get_navigation_type()
        uri = action.get_request().get_uri()
        if self.loading_shell or nav == WebKit2.NavigationType.RELOAD:
            return False
        if kind == WebKit2.PolicyDecisionType.NAVIGATION_ACTION and not action.is_user_gesture() \
                and nav == WebKit2.NavigationType.OTHER and uri.startswith("file:") \
                and urlparse(uri).path.endswith("/"):
            return False  # the shell itself (load_html)
        decision.ignore()
        if uri and not uri.startswith("about:"):
            self.handle_link(uri)
        return True

    def on_context_menu(self, view, menu, _event, _hit):
        keep = {
            WebKit2.ContextMenuAction.COPY,
            WebKit2.ContextMenuAction.COPY_LINK_TO_CLIPBOARD,
            WebKit2.ContextMenuAction.COPY_IMAGE_TO_CLIPBOARD,
            WebKit2.ContextMenuAction.COPY_IMAGE_URL_TO_CLIPBOARD,
            WebKit2.ContextMenuAction.SELECT_ALL,
            WebKit2.ContextMenuAction.CUT,
            WebKit2.ContextMenuAction.PASTE,
        }
        if DEBUG:
            keep.add(WebKit2.ContextMenuAction.INSPECT_ELEMENT)
        for item in list(menu.get_items()):
            if item.get_stock_action() not in keep:
                menu.remove(item)
        return menu.get_n_items() == 0

    # -- actions -----------------------------------------------------------

    def on_message(self, _ucm, result):
        try:
            value = result.get_js_value() if hasattr(result, "get_js_value") else result
            msg = json.loads(value.to_string())
        except (ValueError, AttributeError):
            return
        t = msg.get("type")
        if t == "link":
            self.handle_link(msg.get("href", ""))
        elif t == "wikilink":
            self.open_wikilink(msg.get("target", ""))
        elif t == "toggle":
            self.toggle_task(int(msg.get("line", -1)), bool(msg.get("checked")))
        elif t == "copy":
            cb = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
            cb.set_text(msg.get("text", ""), -1)
            cb.store()
        elif t == "mode":
            self.editing = bool(msg.get("edit"))
        elif t == "save":
            # a late autosave must not land in whatever note is open by now
            if msg.get("path") in (None, str(self.path)):
                self.save_text(msg.get("text"))
        elif t == "pasteimage":
            self.paste_image(msg.get("path"), bool(msg.get("append")))
        elif t == "external":
            self.open_external()
        elif t == "note":
            self.open_note(msg.get("path"))
        elif t == "newnote":
            self.new_note(msg.get("name"), msg.get("dir"))
        elif t == "rename":
            self.rename_note(msg.get("path"), msg.get("name"))
        elif t == "trash":
            self.trash_note(msg.get("path"))
        elif t == "sidebar":
            self.sidebar_pref(msg)
        elif t == "folder":
            self.choose_folder()
        elif t == "open":
            self.choose_file()
        elif t == "reload":
            self.resolver = Resolver(self.path.parent) if self.path else None
            self.render(keep_scroll=True)
        elif t == "zoom":
            self.zoom(msg.get("step", 0))
        elif t == "print":
            WebKit2.PrintOperation.new(self.view).run_dialog(self)
        elif t == "close":
            self.close()
        elif t == "back":
            self.go(self.back, self.fwd)
        elif t == "forward":
            self.go(self.fwd, self.back)
        elif t == "log" and DEBUG:
            print("[js]", msg.get("text"), file=sys.stderr)

    def handle_link(self, href):
        u = urlparse(href)
        if u.scheme != "file":
            if u.scheme:
                launch_uri(href)
            return
        p = Path(unquote(u.path))
        frag = unquote(u.fragment) or None
        if not p.exists() and p.suffix.lower() not in MD_EXT:
            alt = p.with_name(p.name + ".md")
            if alt.exists():
                p = alt
        if self.path and p == self.path:
            if frag:
                self.js("MdView.scrollToFragment", frag, True)
            return
        if not p.exists():
            self.js("MdView.toast", f"Not found: {p.name}")
        elif p.is_file() and p.suffix.lower() in MD_EXT:
            self.open_path(p, frag)
        else:
            launch_uri(p.as_uri())

    def open_wikilink(self, target):
        heading = target.split("#", 1)[1] if "#" in target else None
        p = self.resolver.resolve(target) if self.resolver else None
        if not p:
            self.js("MdView.toast", f"Note “{target.split('#')[0]}” doesn't exist")
        elif file_kind(p) == "md":
            self.open_path(p, heading)
        else:
            launch_uri(p.as_uri())

    def toggle_task(self, line, checked):
        if not self.path or line < 0:
            return
        try:
            text = read_text(self.path)
        except OSError:
            return
        lines = text.split("\n")
        if line >= len(lines):
            return
        m = re.match(r"^([\s>]*(?:[-*+]|\d+[.)])\s+\[)(.)(\])", lines[line])
        if not m:
            self.render(keep_scroll=True)
            return
        lines[line] = m.group(1) + ("x" if checked else " ") + lines[line][m.end(2):]
        try:
            with open(self.path, "w", encoding="utf-8", newline="") as f:
                f.write("\n".join(lines))
        except OSError as e:
            self.js("MdView.toast", f"Couldn't save: {e.strerror}")
            self.render(keep_scroll=True)

    def save_text(self, text):
        if not self.path or not isinstance(text, str):
            return
        try:
            try:
                with open(self.path, "rb") as f:
                    old = f.read()
            except FileNotFoundError:
                old = b""
            # Written in place (no temp file + rename), so symlinked files and
            # their permissions stay what they are. Line endings are kept.
            data = (text.replace("\n", "\r\n") if b"\r\n" in old else text).encode("utf-8")
            if data != old:
                with open(self.path, "wb") as f:
                    f.write(data)
            self.own_text = text
        except OSError as e:
            self.js("MdView.saveFailed", e.strerror or str(e))

    # -- pasted images ----------------------------------------------------

    def attachment_dir(self, vault):
        """Where a pasted image goes: next to the note, or wherever the
        Obsidian vault keeps its attachments (default: the vault root)."""
        if not vault:
            return self.path.parent
        try:
            conf = json.loads((vault / ".obsidian/app.json").read_text()).get("attachmentFolderPath")
        except (OSError, ValueError, AttributeError):
            conf = None
        if not isinstance(conf, str) or not conf.strip("/"):
            return vault
        d = self.path.parent / conf[2:] if conf.startswith("./") else vault / conf
        d = Path(os.path.normpath(d))
        return d if d.is_relative_to(vault) else vault

    def paste_image(self, path, append):
        """Save the clipboard image as a file and embed it: the page inserts
        the Markdown at the caret (editing), or it goes to the end of the note
        (reading)."""
        if not self.path or path != str(self.path):
            return
        img = clipboard_image()
        if not img:
            return
        data, ext = img
        old = b""
        if append:
            try:
                with open(self.path, "rb") as f:
                    old = f.read()
            except OSError as e:
                self.js("MdView.toast", f"Couldn't add image: {e.strerror}")
                return
            reason = readonly_reason(self.path, old)
            if reason:
                self.js("MdView.toast", f"Can't edit: {reason}")
                return
        vault = self.resolver.vault if self.resolver else None
        stem = time.strftime("Pasted image %Y%m%d%H%M%S" if vault else "pasted-%Y%m%d-%H%M%S")
        try:
            folder = self.attachment_dir(vault)
            folder.mkdir(parents=True, exist_ok=True)
            for n in range(1, 100):
                target = folder / f"{stem}{'' if n == 1 else f'-{n}'}{ext}"
                try:
                    with open(target, "xb") as f:
                        f.write(data)
                    break
                except FileExistsError:
                    continue
            else:
                raise FileExistsError(17, "File exists")
        except OSError as e:
            self.js("MdView.toast", f"Couldn't save image: {e.strerror}")
            return
        markup = f"![[{target.name}]]" if vault else f"![]({quote(target.name)})"
        if not append:
            self.js("MdView.insertImage", {"path": str(self.path), "markup": markup})
            return
        nl = b"\r\n" if b"\r\n" in old else b"\n"
        body = old.rstrip(b"\r\n")
        new = (body + nl * 2 if body else b"") + markup.encode("utf-8") + nl
        try:
            with open(self.path, "wb") as f:
                f.write(new)
        except OSError as e:
            self.js("MdView.toast", f"Couldn't save: {e.strerror}")
            try:
                target.unlink()
            except OSError:
                pass
            return
        self.own_write = new
        self.resolver = Resolver(self.path.parent)
        self.render(end=True)

    def open_external(self):
        if not self.path:
            return
        for cmd in (["omarchy-launch-editor", str(self.path)], ["xdg-open", str(self.path)]):
            try:
                subprocess.Popen(cmd, start_new_session=True,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return
            except FileNotFoundError:
                continue

    def zoom(self, step):
        level = 1.0 if step == 0 else self.view.get_zoom_level() + 0.1 * step
        level = round(min(2.5, max(0.5, level)), 2)
        self.view.set_zoom_level(level)
        self.app.state["zoom"] = level
        save_state(self.app.state)
        self.js("MdView.toast", f"{round(level * 100)} %")

    def go(self, src, dst):
        if not src:
            return
        if self.path:
            dst.append(self.path)
        self.open_path(src.pop(), push=False)

    def choose_file(self):
        dlg = Gtk.FileChooserNative.new("Open Markdown", self, Gtk.FileChooserAction.OPEN,
                                        "Open", "Cancel")
        flt = Gtk.FileFilter()
        flt.set_name("Markdown")
        flt.add_mime_type("text/markdown")
        for ext in MD_EXT:
            flt.add_pattern("*" + ext)
        dlg.add_filter(flt)
        if self.path:
            dlg.set_current_folder(str(self.path.parent))
        if dlg.run() == Gtk.ResponseType.ACCEPT:
            self.open_path(dlg.get_filename())
        elif not self.path and not self.folder:
            self.close()
        dlg.destroy()
        return False

    def close_now(self):
        self.close_id = 0
        self.close()
        return False

    def on_delete(self, *_):
        if self.editing and self.shell_ready and not self.closing:
            # Let the page hand over unsaved text first; it answers with "close".
            self.closing = True
            self.js("MdView.flush", True)
            self.close_id = GLib.timeout_add(400, self.close_now)
            return True
        if self.close_id:
            GLib.source_remove(self.close_id)
            self.close_id = 0
        if not self.is_maximized():
            w, h = self.get_size()
            if self.folder:
                self.app.state.update(folder_width=w, folder_height=h)
            else:
                self.app.state.update(width=w, height=h)
            save_state(self.app.state)
        if self.monitor:
            self.monitor.cancel()
        for mon in self.dir_monitors:
            mon.cancel()
        if self.rescan_id:
            GLib.source_remove(self.rescan_id)
            self.rescan_id = 0
        return False


# ---------------------------------------------------------------- app

class MdViewApp(Gtk.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.HANDLES_OPEN)
        self.state = load_state()
        self.theme = load_theme()
        self.motion_css = self.read_motion()
        self.web_settings = None
        self.monitors = []
        self.theme_id = 0

    def read_motion(self):
        try:
            return MOTION_CSS.read_text().replace("</", "<\\/")
        except OSError:
            return ""

    def do_startup(self):
        Gtk.Application.do_startup(self)
        self.set_inactivity_timeout(RESIDENT_MS)
        ctx = WebKit2.WebContext.get_default()
        ctx.set_cache_model(WebKit2.CacheModel.DOCUMENT_VIEWER)
        s = WebKit2.Settings()
        s.set_allow_file_access_from_file_urls(True)
        s.set_allow_universal_access_from_file_urls(False)
        s.set_enable_smooth_scrolling(True)
        s.set_enable_developer_extras(DEBUG)
        s.set_enable_write_console_messages_to_stdout(DEBUG)
        s.set_javascript_can_open_windows_automatically(False)
        s.set_enable_page_cache(False)
        s.set_enable_back_forward_navigation_gestures(False)
        s.set_default_font_family("Inter")
        s.set_sans_serif_font_family("Inter")
        s.set_monospace_font_family("JetBrainsMono Nerd Font")
        s.set_default_font_size(16)
        s.set_default_monospace_font_size(14)
        self.web_settings = s
        for path, cb in ((THEME_DIR / "theme.name", self.on_theme_changed),
                         (THEME_DIR / "theme/colors.toml", self.on_theme_changed),
                         (MOTION_CSS, self.on_motion_changed)):
            try:
                mon = Gio.File.new_for_path(str(path)).monitor_file(Gio.FileMonitorFlags.NONE, None)
                mon.connect("changed", cb)
                self.monitors.append(mon)
            except GLib.Error:
                pass

    def windows(self):
        return [w for w in self.get_windows() if isinstance(w, ViewerWindow)]

    def on_theme_changed(self, *_):
        if self.theme_id:
            GLib.source_remove(self.theme_id)
        self.theme_id = GLib.timeout_add(150, self.apply_theme)

    def apply_theme(self):
        self.theme_id = 0
        self.theme = load_theme()
        bg = Gdk.RGBA()
        bg.parse(self.theme["colors"]["background"])
        for w in self.windows():
            w.override_background_color(Gtk.StateFlags.NORMAL, bg)
            w.view.set_background_color(bg)
            w.js("MdView.setTheme", theme_css(self.theme), self.theme["mode"])
        return False

    def on_motion_changed(self, *_):
        self.motion_css = self.read_motion()
        for w in self.windows():
            w.js("MdView.setMotion", self.motion_css)

    def restart_if_stale(self, args):
        """The process stays resident, the page (viewer.js) is read fresh for
        every window: after an update the two would not match. With no window
        open, start over from the new source instead."""
        if self.windows():
            return
        try:
            if SOURCE.stat().st_mtime_ns == SOURCE_STAMP:
                return
        except OSError:
            return
        os.execv(sys.executable, [sys.executable, str(SOURCE), *args])

    def open_folder(self, folder):
        existing = next((w for w in self.windows() if w.folder == folder), None)
        if existing:
            existing.present()
        else:
            ViewerWindow(self, None, folder=folder).show()

    def do_activate(self):
        self.restart_if_stale([])
        # Started bare: back to the folder that was open last, if there was one.
        last = self.state.get("folder")
        if last and Path(last).is_dir():
            self.open_folder(Path(last))
        else:
            ViewerWindow(self, None).show()

    def do_open(self, files, _n, _hint):
        self.restart_if_stale([f.get_path() or f.get_uri() for f in files])
        for f in files:
            path = f.get_path()
            if not path:
                uri = f.get_uri()
                launch_uri(uri)
                continue
            p = Path(path).resolve()
            if p.is_dir():
                self.open_folder(p)
                continue
            existing = next((w for w in self.windows() if w.path == p), None)
            if existing:
                existing.present()
            else:
                ViewerWindow(self, p).show()


def main():
    GLib.set_prgname(APP_ID)
    GLib.set_application_name("Markdown")
    return MdViewApp().run(sys.argv)


if __name__ == "__main__":
    sys.exit(main())
