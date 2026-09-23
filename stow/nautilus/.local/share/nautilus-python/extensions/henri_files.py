# Files (Nautilus) the Finder way -- henri-ui.
#
# Runs inside the Nautilus process (nautilus-python), so besides menu items it
# can reach Nautilus's own GTK widgets:
#
#  * Return renames, like Finder. With a file selected in the view, Return
#    starts renaming instead of opening it. Ctrl+Return opens the selection
#    (as do double-click, Ctrl+O and Alt+Down, like Cmd+O / Cmd+Down on the
#    Mac). Return anywhere else (path bar, search, sidebar, dialogs) is left
#    alone.
#  * Super+Backspace moves the selection to the Trash (Cmd+Backspace).
#  * Inline rename. Nautilus renames in a popover (title, entry, button,
#    pointing at the item). It is turned into a bare field lying exactly over
#    the file's name: no title, no button, no arrow, text where the name was,
#    growing while typing. Return commits, Esc cancels, clicking elsewhere
#    commits (Finder) -- Nautilus would throw the edit away.
#  * Menus like macOS 26: a symbol before every item, and submenus open beside
#    the menu on hover instead of sliding in on a click.
#  * Context menu extras: Copy Path, Open in Terminal, Open in Claude Code, and
#    New File > (text, Markdown, document/spreadsheet/presentation, scripts,
#    web page, JSON, CSV) on the folder background; a new file is selected
#    and goes straight into renaming, like Finder's New Folder.
#
# Styles live in ~/.config/gtk-4.0/henri-files.css (.henri-inline-rename,
# .henri-menu-icon). Set HENRI_FILES_DEBUG=1 for a trace on stdout.

import os
import shutil

from gi import require_version

require_version("Nautilus", "4.1")
require_version("Gtk", "4.0")
require_version("Gdk", "4.0")

from gi.repository import Gdk, Gio, GLib, GObject, Gtk, Nautilus  # noqa: E402


# ── helpers ──────────────────────────────────────────────────────────────────

DEBUG = bool(os.environ.get("HENRI_FILES_DEBUG"))


def _dbg(*args):
    if DEBUG:
        print("henri_files:", *args, flush=True)


def _type_name(widget):
    return GObject.type_name(widget.__gtype__) if widget is not None else ""


def _ancestor(widget, type_name):
    while widget is not None:
        if _type_name(widget) == type_name:
            return widget
        widget = widget.get_parent()
    return None


def _children(widget):
    child = widget.get_first_child()
    while child is not None:
        yield child
        child = child.get_next_sibling()


def _walk(widget):
    for child in _children(widget):
        yield child
        yield from _walk(child)


def _bounds_in(widget, target):
    ok, rect = widget.compute_bounds(target)
    return rect if ok else None


# ── Return = rename ──────────────────────────────────────────────────────────

# Inline field geometry (px): CSS padding 3 + border 1 on each side, room for
# the caret after the last character, and a floor for very short names.
FIELD_INSET = 4
CARET_ROOM = 4
MIN_FIELD = 40

RETURN_KEYS = (Gdk.KEY_Return, Gdk.KEY_KP_Enter, Gdk.KEY_ISO_Enter)
MODIFIERS = (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK
             | Gdk.ModifierType.ALT_MASK | Gdk.ModifierType.SUPER_MASK)


def _on_window_key(controller, keyval, _keycode, state):
    # Super+Backspace = move to Trash (Cmd+Backspace). Hyprland owns that
    # chord (window transparency); while Files is focused it forwards Delete
    # instead (bindings.lua), which arrives with the held Super -- so both
    # chords land here. Plain Delete is Nautilus's own Trash key anyway.
    if keyval in (Gdk.KEY_BackSpace, Gdk.KEY_Delete) \
            and state & MODIFIERS == Gdk.ModifierType.SUPER_MASK:
        focus = controller.get_widget().get_focus()
        if focus is None or isinstance(focus, Gtk.Editable):
            return False
        if _ancestor(focus, "NautilusFilesView") is None:
            return False
        focus.activate_action("view.move-to-trash", None)
        return True
    # Ctrl+Return = open the selection. Plain Return renames (below), so the
    # opening key is the one the hand is already on -- Nautilus's own Ctrl+O
    # and Alt+Down keep working. Folders open in place, files in their app.
    if keyval in RETURN_KEYS \
            and state & MODIFIERS == Gdk.ModifierType.CONTROL_MASK:
        focus = controller.get_widget().get_focus()
        if focus is None or isinstance(focus, Gtk.Editable):
            return False
        if _ancestor(focus, "NautilusFilesView") is None:
            return False
        _dbg("ctrl+return -> open")
        focus.activate_action("view.open-with-default-application", None)
        return True
    if keyval not in RETURN_KEYS or state & MODIFIERS:
        return False
    window = controller.get_widget()
    focus = window.get_focus()
    if focus is None or isinstance(focus, Gtk.Editable):
        return False
    view = _ancestor(focus, "NautilusFilesView")
    if view is None:
        return False
    _install_in_view(view)
    _dbg("return -> rename")
    # Disabled (nothing selected, read-only folder) -> Return does nothing,
    # like Finder; it never falls back to opening.
    focus.activate_action("view.rename", None)
    return True


def _hook_window(window):
    if getattr(window, "_henri_files", False):
        return
    window._henri_files = True
    keys = Gtk.EventControllerKey()
    keys.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
    keys.connect("key-pressed", _on_window_key)
    window.add_controller(keys)
    window.connect("notify::focus-widget", _on_focus_changed)
    GLib.idle_add(_hook_sidebar, window)


def _hook_windows(model, position=0, _removed=0, added=None):
    count = model.get_n_items() if added is None else position + added
    for i in range(position, count):
        window = model.get_item(i)
        if _type_name(window) == "NautilusWindow":
            _hook_window(window)


# ── sidebar headings ─────────────────────────────────────────────────────────
# Finder labels its sidebar sections ("Favorites", "Locations"); Nautilus only
# draws a line between them. Its list box gets our header function instead,
# keyed by each row's section type (a private enum, read by its nick).

SIDEBAR_HEADINGS = (
    ("bookmark", "Favorites"),
    ("cloud", "Cloud"),
    ("mount", "Locations"),
    ("network", "Network"),
)


def _section_nick(row):
    try:
        value = row.get_property("section-type")
    except TypeError:
        return ""
    nick = getattr(value, "value_nick", None)
    if nick:
        return nick
    pspec = row.find_property("section-type")
    try:
        return pspec.enum_class.__enum_values__[int(value)].value_nick
    except (AttributeError, KeyError, ValueError):
        return str(int(value))


def _sidebar_header(row, before, *_args):
    nick = _section_nick(row)
    if before is not None and _section_nick(before) == nick:
        row.set_header(None)
        return
    title = next((t for key, t in SIDEBAR_HEADINGS if key in nick), None)
    if title is None:
        # The first block (Home, Recent, Starred, ...) has no heading, like
        # Finder's; an unknown later block keeps a plain separator.
        row.set_header(None if before is None else Gtk.Separator())
        return
    label = Gtk.Label(label=title, xalign=0)
    label.add_css_class("henri-sidebar-heading")
    row.set_header(label)


def _hook_sidebar(window, tries=50):
    """The sidebar is built after the window appears: retry until it is."""
    for widget in _walk(window):
        if _type_name(widget) == "NautilusSidebar":
            for child in _walk(widget):
                if isinstance(child, Gtk.ListBox) and child.get_row_at_index(0) is not None:
                    child.set_header_func(_sidebar_header)
                    child.invalidate_headers()
                    _dbg("sidebar headings", [_section_nick(child.get_row_at_index(i))
                                              for i in range(3)])
                    return False
    if tries > 0:
        GLib.timeout_add(100, _hook_sidebar, window, tries - 1)
    return False


# ── inline rename ────────────────────────────────────────────────────────────

class InlineRename:
    """Turns one NautilusRenameFilePopover into an inline field."""

    def __init__(self, popover):
        self.popover = popover
        self.entry = None
        self.box = None
        self.title = None
        self.button = None
        self.original = ""
        self.done = False       # committed with Return or cancelled with Esc
        self.width = -1
        self.placing = False
        self.placed_rect = None
        self.label = None
        self.grid = False
        popover.add_css_class("henri-inline-rename")
        popover.set_has_arrow(False)
        popover.set_position(Gtk.PositionType.BOTTOM)

        self.box = popover.get_child()
        for child in _children(self.box):
            if isinstance(child, Gtk.Entry):
                self.entry = child
            elif isinstance(child, Gtk.Button):
                self.button = child
            elif isinstance(child, Gtk.Label):
                self.title = child
        for side in ("start", "end", "top", "bottom"):
            getattr(self.box, "set_margin_" + side)(0)
        if self.title:
            self.title.set_visible(False)
        if self.button:
            self.button.set_visible(False)
        if self.entry is None:
            return
        self.entry.set_margin_bottom(0)
        self.entry.add_css_class("henri-inline-field")
        # Nautilus sizes the field to 30-50 characters after popping it up;
        # keep it at the width of the name instead.
        self.entry.connect("notify::width-chars", self._keep_width)

        keys = Gtk.EventControllerKey()
        keys.set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
        keys.connect("key-pressed", self._on_key)
        self.entry.add_controller(keys)
        self.entry.connect("activate", self._on_activate)
        self.entry.connect("changed", self._on_changed)
        # Nautilus sets the anchor right before popping up: lay the field out
        # then, so the popup is measured and placed as the bare field.
        popover.connect("notify::pointing-to", self._on_pointing_to)

    def _on_changed(self, _entry):
        if self.popover.get_visible() and not self.placing and self.width > 0:
            self._fit()

    def _on_activate(self, _entry):
        self.done = True

    def _on_key(self, _controller, keyval, _keycode, _state):
        if keyval == Gdk.KEY_Escape:
            self.done = True
        return False

    def _keep_width(self, entry, _pspec):
        if self.width > 0 and entry.get_width_chars() != 1:
            entry.set_width_chars(1)
            entry.set_max_width_chars(1)

    def _name_label(self, view, rect):
        """The label showing the file name inside the pointed-at item."""
        want = self.entry.get_text() if self.entry else ""
        cx, cy = rect.x + rect.width / 2, rect.y + rect.height / 2
        best = None
        for widget in _walk(view):
            if not isinstance(widget, Gtk.Label) or not widget.get_mapped():
                continue
            if widget.get_text() != want:
                continue
            b = _bounds_in(widget, view)
            if b is None:
                continue
            x, y = b.origin.x, b.origin.y
            w, h = b.size.width, b.size.height
            if rect.x - 1 <= x + w / 2 <= rect.x + rect.width + 1 and \
               rect.y - 1 <= y + h / 2 <= rect.y + rect.height + 1:
                d = abs(x + w / 2 - cx) + abs(y + h / 2 - cy)
                if best is None or d < best[0]:
                    best = (d, widget, b)
        return best

    def _on_pointing_to(self, popover, _pspec):
        ok, rect = popover.get_pointing_to()
        mine = self.placed_rect
        if ok and mine is not None and (rect.x, rect.y, rect.width, rect.height) == mine:
            return          # our own anchor echoing back
        self.show()

    def show(self):
        if self.entry is None or self.placing:
            return
        self.placing = True
        try:
            self._place()
        finally:
            self.placing = False

    def _place(self):
        _dbg("place", self.entry.get_text(), self.popover.get_pointing_to())
        self.done = False
        self.original = self.entry.get_text()
        view = self.popover.get_parent()
        ok, rect = self.popover.get_pointing_to()
        if view is None or not ok:
            return
        found = self._name_label(view, rect)
        if found is None:
            # Unknown layout: keep Nautilus's popover, just without the chrome.
            self.width = -1
            self.popover.set_offset(0, 0)
            return
        _d, label, b = found
        self._release_label()
        self.label = label
        label.add_css_class("henri-renaming")
        # Grid names are centred under the icon, list names start at the left.
        self.grid = _ancestor(label, "NautilusGridCell") is not None
        self.lx, self.ly = b.origin.x, b.origin.y
        self.lw, self.lh = b.size.width, b.size.height
        # Grid: the field may grow past the cell into the gaps, like Finder's; list:
        # up to the end of the view.
        self.cap = round(rect.width + 64 if self.grid else max(view.get_width() - self.lx - 8, 80))
        self.entry.set_alignment(0.5 if self.grid else 0.0)
        self.entry.set_width_chars(1)
        self.entry.set_max_width_chars(1)
        self.field_h = max(self.entry.measure(Gtk.Orientation.VERTICAL, -1)[1], self.lh)
        self._fit()
        self._anchor()
        # The popover hangs below the target; lift it so the field sits on the
        # name, vertically centred on it.
        self.popover.set_offset(0, -round(self.lh / 2 + self.field_h / 2))
        _dbg("placed", self.lx, self.ly, self.lw, self.lh, self.field_h)

    def _fit(self, *_args):
        """Field as wide as its text (+ caret room), growing while typing.

        The popup itself never changes size or place once it is up (GTK
        centres it on the anchor, and the compositor doesn't move an open
        popup): it is a fixed, invisible strip -- the cell in the grid, the
        rest of the row in the list -- and only the field inside it grows,
        centred on the name (grid) or from its left edge (list)."""
        text = self.entry.get_text() or " "
        text_w = self.entry.create_pango_layout(text).get_pixel_size()[0]
        w = round(min(max(text_w + 2 * FIELD_INSET + CARET_ROOM, MIN_FIELD), self.cap))
        self.width = w
        self.entry.set_size_request(w, -1)

    def _anchor(self):
        target = Gdk.Rectangle()
        if self.grid:
            target.x = round(self.lx + self.lw / 2 - self.cap / 2)
        else:
            target.x = round(self.lx - FIELD_INSET)
        target.y = round(self.ly)
        target.width = round(self.cap)
        target.height = round(self.lh)
        self.box.set_size_request(target.width, -1)
        self.entry.set_halign(Gtk.Align.CENTER if self.grid else Gtk.Align.START)
        self.placed_rect = (target.x, target.y, target.width, target.height)
        self.popover.set_pointing_to(target)

    def _release_label(self):
        label = self.label
        if label is not None:
            label.remove_css_class("henri-renaming")
        self.label = None

    def closing(self):
        """Popover is closing without Return/Esc (a click elsewhere): commit,
        like Finder -- Nautilus would drop the edit.

        Nautilus's own accept path can finish asynchronously, after the popover
        has already forgotten its file, so the rename is done here directly."""
        _dbg("closing", self.done)
        self._release_label()
        if self.done or self.entry is None:
            return
        self.done = True
        new = self.entry.get_text().strip()
        if not new or new == self.original or "/" in new or new in (".", ".."):
            return
        view = self.popover.get_parent()
        folder = view.get_property("location") if view is not None else None
        if folder is None or folder.get_path() is None:
            return              # search results, remote places: leave them be
        try:
            source = folder.get_child_for_display_name(self.original)
            if folder.get_child_for_display_name(new).query_exists(None):
                return          # never overwrite; Finder refuses too
            source.set_display_name_async(new, GLib.PRIORITY_DEFAULT, None, None)
        except GLib.Error:
            pass


_renames = {}


def _rename_for(popover):
    key = hash(popover)
    inline = _renames.get(key)
    if inline is None or inline.popover is not popover:
        inline = InlineRename(popover)
        _renames[key] = inline
        popover.connect("destroy", lambda p: _renames.pop(hash(p), None))
    return inline


def _install_in_view(view):
    for child in _children(view):
        if _type_name(child) == "NautilusRenameFilePopover":
            _rename_for(child)
        elif isinstance(child, Gtk.PopoverMenu):
            _nest(child)          # before its first popup, so it never rebuilds while open


def _on_focus_changed(window, _pspec):
    view = _ancestor(window.get_focus(), "NautilusFilesView")
    if view is not None and not getattr(view, "_henri_files", False):
        view._henri_files = True
        _install_in_view(view)


def _on_widget_show(widget, *_args):
    if isinstance(widget, Gtk.PopoverMenu) and _type_name(widget.get_root()) == "NautilusWindow":
        _decorate_menu(widget)
        return True
    # Fallback for a popover that opened before it was found: it is already
    # up with Nautilus's layout, so place it now (one late frame).
    if _type_name(widget) == "NautilusRenameFilePopover" and hash(widget) not in _renames:
        _rename_for(widget).show()
    return True


def _on_popover_closed(popover, *_args):
    if _type_name(popover) == "NautilusRenameFilePopover":
        _rename_for(popover).closing()
    return True


# ── menu icons ───────────────────────────────────────────────────────────────
# macOS 26 puts a small symbol in front of every menu item. Nautilus neither
# passes extension icons on nor can GTK4 popover menus show an icon next to a
# label, so each menu is decorated when it opens: a 16 px symbolic icon (or an
# equally wide gap, so all labels line up) before the label. Keyed by the
# English label; check/radio items keep their own indicator.

MENU_ICONS = {
    "Open": "document-open-symbolic",
    "Open With…": "document-open-symbolic",
    "Open in New Tab": "tab-new-symbolic",
    "Open in New Window": "window-new-symbolic",
    "Open Item Location": "folder-open-symbolic",
    "Run as a Program": "application-x-executable-symbolic",
    "Cut": "edit-cut-symbolic",
    "Copy": "edit-copy-symbolic",
    "Paste": "edit-paste-symbolic",
    "Paste Into Folder": "edit-paste-symbolic",
    "Move to…": "mail-forward-symbolic",
    "Copy to…": "edit-copy-symbolic",
    "Rename…": "document-edit-symbolic",
    "Compress…": "package-x-generic-symbolic",
    "Extract": "package-x-generic-symbolic",
    "Extract Here": "package-x-generic-symbolic",
    "Extract to…": "package-x-generic-symbolic",
    "Email…": "mail-send-symbolic",
    "Create Link": "emblem-symbolic-link-symbolic",
    "Move to Trash": "user-trash-symbolic",
    "Delete Permanently": "edit-delete-symbolic",
    "Delete Permanently…": "edit-delete-symbolic",
    "Restore From Trash": "edit-undo-symbolic",
    "Empty Trash": "user-trash-symbolic",
    "Empty Trash…": "user-trash-symbolic",
    "Star": "starred-symbolic",
    "Unstar": "non-starred-symbolic",
    "Set as Background…": "image-x-generic-symbolic",
    "Properties": "document-properties-symbolic",
    "New Folder…": "folder-new-symbolic",
    "New Folder With Selection…": "folder-new-symbolic",
    "Select All": "edit-select-all-symbolic",
    "Captions…": "format-justify-left-symbolic",
    "Visible Columns…": "view-list-symbolic",
    "Add to Bookmarks": "starred-symbolic",
    "Reload": "view-refresh-symbolic",
    "Undo": "edit-undo-symbolic",
    "Redo": "edit-redo-symbolic",
    "Mount": "drive-harddisk-symbolic",
    "Unmount": "media-eject-symbolic",
    "Eject": "media-eject-symbolic",
    "Scripts": "applications-system-symbolic",
    "Send via LocalSend": "send-to-symbolic",
    "Copy Path": "insert-link-symbolic",
    "Copy Paths": "insert-link-symbolic",
    "Open in Terminal": "utilities-terminal-symbolic",
    "Open in Claude Code": "claude-quick",
    "New File": "document-new-symbolic",
}
MENU_ICON_PREFIXES = (
    ("Open With ", "document-open-symbolic"),
    ("Transcode", "media-playback-start-symbolic"),
)
MENU_ICON_SIZE = 16


def _menu_icon_for(label, button):
    icon = button.get_property("icon")        # "Open With <App>" carries the app icon
    if icon is not None:
        return Gtk.Image.new_from_gicon(icon)
    name = MENU_ICONS.get(label) or next((spec[2] for spec in NEW_FILES if spec[1] == label), None)
    if name is None:
        for prefix, prefixed in MENU_ICON_PREFIXES:
            if label.startswith(prefix):
                name = prefixed
                break
    return Gtk.Image.new_from_icon_name(name) if name else None


# Where GTK puts a nested submenu vs. macOS: GTK overlaps the menu by ~11 px and
# drops it ~6 px; macOS sits it flush beside the menu (3 px of corner overlap)
# with its first item level with the item that opened it. Measured in Files.
SUBMENU_OFFSET = (8, -6)


def _nest(popover):
    """Submenus open beside the menu on hover (macOS), not by sliding in on a
    click. Changing the flags rebuilds the items, so do it before decorating."""
    nested = Gtk.PopoverMenuFlags.NESTED
    if not popover.get_flags() & nested:
        popover.set_flags(popover.get_flags() | nested)


def _decorate_menu(popover):
    _nest(popover)
    # Submenu popovers exist before they open; place them now, because an open
    # popup is never moved again.
    for sub in _walk(popover):
        if isinstance(sub, Gtk.PopoverMenu) and sub is not popover:
            sub.set_offset(*SUBMENU_OFFSET)
    for button in _walk(popover):
        if button.get_css_name() != "modelbutton" or getattr(button, "_henri_icon", False):
            continue
        if int(button.get_property("role")) != 0:   # GtkButtonRole NORMAL (private enum)
            continue
        label = next((c for c in _children(button) if isinstance(c, Gtk.Label)
                      and c.get_css_name() == "label" and "accelerator" not in c.get_css_classes()), None)
        if label is None or not label.get_text():
            continue
        button._henri_icon = True
        image = _menu_icon_for(label.get_text(), button)
        if image is None:
            image = Gtk.Image()                   # keeps the label column aligned
        image.set_pixel_size(MENU_ICON_SIZE)
        image.set_size_request(MENU_ICON_SIZE, MENU_ICON_SIZE)
        image.add_css_class("henri-menu-icon")
        image.insert_before(button, label)


# ── context menu ─────────────────────────────────────────────────────────────

def _local_path(item):
    location = item.get_location()
    return location.get_path() if location is not None else None


def _spawn_in(argv, cwd):
    launcher = Gio.SubprocessLauncher.new(Gio.SubprocessFlags.NONE)
    launcher.set_cwd(cwd)
    try:
        launcher.spawnv(argv)
    except GLib.Error:
        pass


def _terminal_argv(cwd, app_id=None, command=None):
    """Default terminal (xdg-terminal-exec) in `cwd`, as its own app unit."""
    argv = ["xdg-terminal-exec", "--dir=" + cwd]
    if app_id:
        argv.insert(1, "--app-id=" + app_id)
    if command:
        argv += ["-e"] + command
    return (["uwsm-app", "--"] if shutil.which("uwsm-app") else []) + argv


def _copy_to_clipboard(text):
    display = Gdk.Display.get_default()
    if display is not None:
        display.get_clipboard().set(text)


def _unique(folder, base, ext):
    name = base + ext
    n = 2
    while os.path.exists(os.path.join(folder, name)):
        name = "%s %d%s" % (base, n, ext)
        n += 1
    return os.path.join(folder, name)


# ── New File ─────────────────────────────────────────────────────────────────
# Empty OpenDocument files (LibreOffice's own format): the smallest package
# LibreOffice opens -- mimetype first and uncompressed, a manifest, content.

ODF_NS = ('xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
          'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
          'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
          'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
          'xmlns:presentation="urn:oasis:names:tc:opendocument:xmlns:presentation:1.0"')
ODF_BODY = {
    "text": "<office:text><text:p/></office:text>",
    "spreadsheet": ('<office:spreadsheet><table:table table:name="Sheet1">'
                    "<table:table-row><table:table-cell/></table:table-row>"
                    "</table:table></office:spreadsheet>"),
    "presentation": ('<office:presentation><draw:page draw:name="Slide 1"/>'
                     "</office:presentation>"),
}


def _write_odf(path, kind):
    import zipfile
    mime = "application/vnd.oasis.opendocument." + kind
    manifest = ('<?xml version="1.0" encoding="UTF-8"?>'
                '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" '
                'manifest:version="1.2">'
                '<manifest:file-entry manifest:full-path="/" manifest:version="1.2" '
                'manifest:media-type="%s"/>'
                '<manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>'
                "</manifest:manifest>" % mime)
    content = ('<?xml version="1.0" encoding="UTF-8"?>'
               '<office:document-content %s office:version="1.2"><office:body>%s'
               "</office:body></office:document-content>" % (ODF_NS, ODF_BODY[kind]))
    with zipfile.ZipFile(path, "x") as z:
        z.writestr(zipfile.ZipInfo("mimetype"), mime, compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/manifest.xml", manifest, compress_type=zipfile.ZIP_DEFLATED)
        z.writestr("content.xml", content, compress_type=zipfile.ZIP_DEFLATED)


HTML_PAGE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Untitled</title>
</head>
<body>

</body>
</html>
"""

# (key, label, icon, file name, extension, content | callable, executable)
NEW_FILES = (
    ("text", "Text File", "text-x-generic-symbolic", "Untitled", ".txt", "", False),
    ("markdown", "Markdown", "format-justify-left-symbolic", "Untitled", ".md", "", False),
    ("document", "Document", "x-office-document-symbolic", "Untitled", ".odt",
     lambda p: _write_odf(p, "text"), False),
    ("spreadsheet", "Spreadsheet", "x-office-spreadsheet-symbolic", "Untitled", ".ods",
     lambda p: _write_odf(p, "spreadsheet"), False),
    ("presentation", "Presentation", "x-office-presentation-symbolic", "Untitled", ".odp",
     lambda p: _write_odf(p, "presentation"), False),
    ("shell", "Shell Script", "utilities-terminal-symbolic", "script", ".sh",
     "#!/usr/bin/env bash\nset -euo pipefail\n\n", True),
    ("python", "Python Script", "applications-engineering-symbolic", "script", ".py",
     "#!/usr/bin/env python3\n\n", True),
    ("html", "Web Page", "view-grid-symbolic", "index", ".html", HTML_PAGE, False),
    ("json", "JSON", "preferences-system-details-symbolic", "Untitled", ".json", "{}\n", False),
    ("csv", "CSV Table", "view-list-symbolic", "Untitled", ".csv", "", False),
    ("empty", "Empty File", "text-x-generic-symbolic", "Untitled", "", "", False),
)


def _write_new_file(path, content, executable):
    if callable(content):
        content(path)
    else:
        with open(path, "x") as f:
            f.write(content)
    if executable:
        os.chmod(path, 0o755)


# ── reveal + rename a file that was just created (Finder's New Folder flow) ──

def _find_view(folder_path):
    """The files view showing `folder_path`, preferring the active window."""
    app = Gtk.Application.get_default()
    windows = []
    if app is not None and app.get_active_window() is not None:
        windows.append(app.get_active_window())
    toplevels = Gtk.Window.get_toplevels()
    windows += [toplevels.get_item(i) for i in range(toplevels.get_n_items())]
    for window in windows:
        for widget in _walk(window):
            if _type_name(widget) != "NautilusFilesView" or not widget.get_mapped():
                continue
            location = widget.get_property("location")
            if location is not None and location.get_path() == folder_path:
                return widget
    return None


def _item_name(row):
    item = row.get_property("item") if isinstance(row, Gtk.TreeListRow) else row
    file = item.get_property("file") if item is not None else None
    return file.get_name() if file is not None else None


def _rename_when_laid_out(view, name, tries=30):
    """Start renaming once the fresh item's name label has its real size --
    the field is laid over it, so it must not measure a half-built cell."""
    for widget in _walk(view):
        if isinstance(widget, Gtk.Label) and widget.get_text() == name and widget.get_mapped() \
                and widget.get_width() > 8 and widget.get_height() > 8:
            view.activate_action("view.rename", None)
            return False
    if tries > 0:
        GLib.timeout_add(30, _rename_when_laid_out, view, name, tries - 1)
    else:
        view.activate_action("view.rename", None)   # still select-and-rename
    return False


def _reveal_and_rename(folder_path, name, tries=40):
    """Select `name` once it shows up in the view, then start renaming it."""
    view = _find_view(folder_path)
    if view is None:
        return
    for widget in _walk(view):
        if isinstance(widget, (Gtk.GridView, Gtk.ColumnView)) and widget.get_mapped():
            model = widget.get_model()
            for pos in range(model.get_n_items()):
                if _item_name(model.get_item(pos)) == name:
                    flags = Gtk.ListScrollFlags.FOCUS | Gtk.ListScrollFlags.SELECT
                    widget.scroll_to(pos, None, flags, None) if isinstance(widget, Gtk.ColumnView) \
                        else widget.scroll_to(pos, flags, None)
                    _install_in_view(view)
                    _rename_when_laid_out(view, name)
                    return
            break
    if tries > 0:       # the directory monitor hasn't delivered it yet
        GLib.timeout_add(50, _reveal_and_rename, folder_path, name, tries - 1)


class HenriFilesMenu(GObject.GObject, Nautilus.MenuProvider):
    def __init__(self):
        super().__init__()
        GLib.idle_add(self._install)

    # Hooks into Nautilus's own widgets, once per process.
    def _install(self):
        if getattr(HenriFilesMenu, "_installed", False):
            return False
        HenriFilesMenu._installed = True
        GObject.add_emission_hook(Gtk.Widget, "show", _on_widget_show)
        GObject.add_emission_hook(Gtk.Popover, "closed", _on_popover_closed)
        toplevels = Gtk.Window.get_toplevels()
        toplevels.connect("items-changed", _hook_windows)
        _hook_windows(toplevels)
        return False

    # Selected items
    def get_file_items(self, items):
        paths = [p for p in (_local_path(i) for i in items) if p]
        if not paths:
            return []
        menu = []

        copy = Nautilus.MenuItem(name="HenriFiles::CopyPath",
                                 label="Copy Path" if len(paths) == 1 else "Copy Paths")
        copy.connect("activate", lambda _m: _copy_to_clipboard("\n".join(paths)))
        menu.append(copy)

        if len(paths) == 1:
            path = paths[0]
            folder = path if os.path.isdir(path) else os.path.dirname(path)
            menu += self._folder_items(folder, "Item")
        return menu

    # Folder background
    def get_background_items(self, folder):
        path = _local_path(folder)
        if not path:
            return []
        menu = self._folder_items(path, "Background")

        new = Nautilus.MenuItem(name="HenriFiles::NewFile", label="New File")
        sub = Nautilus.Menu()
        new.set_submenu(sub)
        for spec in NEW_FILES:
            entry = Nautilus.MenuItem(name="HenriFiles::New-" + spec[0], label=spec[1])
            entry.connect("activate", self._create, path, spec)
            sub.append_item(entry)
        menu.insert(0, new)

        copy = Nautilus.MenuItem(name="HenriFiles::CopyFolderPath", label="Copy Path")
        copy.connect("activate", lambda _m: _copy_to_clipboard(path))
        menu.append(copy)
        return menu

    def _folder_items(self, folder, where):
        items = []
        term = Nautilus.MenuItem(name="HenriFiles::Terminal-" + where, label="Open in Terminal")
        term.connect("activate", lambda _m: _spawn_in(_terminal_argv(folder), folder))
        items.append(term)
        if shutil.which("claude"):
            claude = Nautilus.MenuItem(name="HenriFiles::Claude-" + where, label="Open in Claude Code")
            claude.connect("activate", lambda _m: _spawn_in(_terminal_argv(
                folder, "org.omarchy.agent", ["claude", "--permission-mode", "auto"]), folder))
            items.append(claude)
        return items

    def _create(self, _item, folder, spec):
        _key, _label, _icon, base, ext, content, executable = spec
        target = _unique(folder, base, ext)
        try:
            _write_new_file(target, content, executable)
        except OSError:
            return
        _reveal_and_rename(folder, os.path.basename(target))
