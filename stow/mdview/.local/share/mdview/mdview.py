#!/usr/bin/env python3
"""mdview — fast, complete Markdown viewer (GTK 3 + WebKit).

Renders CommonMark/GFM plus Obsidian syntax (wikilinks, embeds, callouts,
properties, ==highlight==, %%comments%%, #tags), KaTeX math, Mermaid and
highlighted code. Works on any file, no vault needed. Stays resident for a
while after the last window closes so reopening is instant.

Assets live next to the real path of this script; bin/mdview is a thin
launcher that hands files to a running instance over D-Bus.
Colors follow the Omarchy theme, motion follows ~/.local/share/henri-ui.
"""

import json
import os
import re
import secrets
import subprocess
import sys
import time
import tomllib
from pathlib import Path
from urllib.parse import unquote, urlparse

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("WebKit2", "4.1")
from gi.repository import Gdk, Gio, GLib, Gtk, WebKit2  # noqa: E402

APP_ID = "dev.henri.MdView"
HOME = Path.home()
ASSETS = Path(os.path.realpath(__file__)).parent
THEME_DIR = HOME / ".local/state/omarchy/current"
MOTION_CSS = HOME / ".local/share/henri-ui/motion.css"
STATE_FILE = Path(GLib.get_user_state_dir()) / "mdview" / "state.json"
DEBUG = bool(os.environ.get("MDVIEW_DEBUG"))
RESIDENT_MS = 15 * 60 * 1000

MD_EXT = {".md", ".markdown", ".mdown", ".mkd", ".mkdn", ".mdx"}
IMG_EXT = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".svg", ".bmp", ".avif", ".ico"}
AUDIO_EXT = {".mp3", ".wav", ".ogg", ".m4a", ".flac", ".opus", ".webm"}
VIDEO_EXT = {".mp4", ".mkv", ".mov", ".ogv"}
SKIP_DIRS = {"node_modules", "__pycache__", "target", "venv", ".venv", "dist", "build"}
WIKI_RE = re.compile(r"!?\[\[([^\[\]\n]+?)\]\]")
EMBED_LIMIT = 256 * 1024

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
    def __init__(self, app, path):
        super().__init__(application=app, title="Markdown")
        self.app = app
        self.path = None
        self.shell_dir = None
        self.shell_ready = False
        self.loading_shell = False
        self.pending_fragment = None
        self.back, self.fwd = [], []
        self.monitor = None
        self.reload_id = 0
        self.resolver = None

        st = app.state
        self.set_default_size(st.get("width", 900), st.get("height", 1040))
        self.set_icon_name("text-markdown")
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

        if path:
            self.open_path(path, push=False)
        else:
            GLib.idle_add(self.choose_file)

    # -- loading --------------------------------------------------------

    def load_shell(self, force=False):
        target_dir = self.path.parent if self.path else HOME
        if self.shell_ready and not force and target_dir == self.shell_dir:
            self.render()
            return
        self.shell_dir = target_dir
        self.shell_ready = False
        self.loading_shell = True
        nonce = secrets.token_urlsafe(18)
        a = ASSETS.as_uri()
        csp = ("default-src 'none'; "
               f"script-src 'nonce-{nonce}'; "
               "style-src 'unsafe-inline' file: https:; "
               "img-src file: data: blob: https: http:; "
               "font-src file: data:; media-src file: https: http:")
        scripts = "".join(f'<script nonce="{nonce}" src="{a}/{s}"></script>' for s in SCRIPTS)
        html = (
            "<!doctype html><html lang='de'><head><meta charset='utf-8'>"
            f"<meta http-equiv='Content-Security-Policy' content=\"{csp}\">"
            f"<style id='henri-ui'>{self.app.motion_css}</style>"
            f"<style id='theme'>{theme_css(self.app.theme)}</style>"
            f"<link rel='stylesheet' href='{a}/vendor/katex/katex.min.css'>"
            f"<link rel='stylesheet' href='{a}/viewer.css'>"
            f"</head><body data-mode='{self.app.theme['mode']}'><main id='content'></main>"
            f"{scripts}</body></html>"
        )
        self.view.load_html(html, target_dir.as_uri() + "/")

    def on_load_changed(self, view, event):
        if event == WebKit2.LoadEvent.FINISHED:
            self.loading_shell = False
            self.shell_ready = True
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
            self.watch()
        if same and self.shell_ready:
            if fragment:
                self.js("MdView.scrollToFragment", fragment, True)
            return
        self.pending_fragment = fragment
        if self.shell_ready and path.parent == self.shell_dir:
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
            self.resolver = Resolver(self.path.parent)
            self.render(keep_scroll=True)
        return False

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

    def render(self, keep_scroll=False, fragment=None):
        if not self.shell_ready or not self.path:
            return
        try:
            text = read_text(self.path)
            error = None
        except FileNotFoundError:
            text, error = "", f"Datei nicht gefunden: {self.path}"
        except OSError as e:
            text, error = "", f"Datei kann nicht gelesen werden: {e.strerror}"
        payload = {
            "text": text,
            "name": self.path.name,
            "vault": bool(self.resolver and self.resolver.vault),
            "links": self.build_links(text) if "[[" in text else {},
            "keepScroll": keep_scroll,
            "fragment": fragment,
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
        elif t == "edit":
            self.edit()
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
            self.js("MdView.toast", f"Nicht gefunden: {p.name}")
        elif p.is_file() and p.suffix.lower() in MD_EXT:
            self.open_path(p, frag)
        else:
            launch_uri(p.as_uri())

    def open_wikilink(self, target):
        heading = target.split("#", 1)[1] if "#" in target else None
        p = self.resolver.resolve(target) if self.resolver else None
        if not p:
            self.js("MdView.toast", f"Notiz „{target.split('#')[0]}“ existiert nicht")
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
            self.js("MdView.toast", f"Speichern fehlgeschlagen: {e.strerror}")
            self.render(keep_scroll=True)

    def edit(self):
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
        dlg = Gtk.FileChooserNative.new("Markdown öffnen", self, Gtk.FileChooserAction.OPEN,
                                        "Öffnen", "Abbrechen")
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
        elif not self.path:
            self.close()
        dlg.destroy()
        return False

    def on_delete(self, *_):
        if not self.is_maximized():
            w, h = self.get_size()
            self.app.state.update(width=w, height=h)
            save_state(self.app.state)
        if self.monitor:
            self.monitor.cancel()
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

    def do_activate(self):
        ViewerWindow(self, None).show()

    def do_open(self, files, _n, _hint):
        for f in files:
            path = f.get_path()
            if not path:
                uri = f.get_uri()
                launch_uri(uri)
                continue
            p = Path(path).resolve()
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
