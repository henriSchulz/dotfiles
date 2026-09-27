import QtQuick
import Quickshell.Io

// Contents of one pinned folder for a stack: listed once at start and again
// whenever inotify sees a change, never when the stack opens (a fork in the
// first frames of an animation costs frame rate — henri-ui §5).
Item {
  id: watcher
  property string path: ""
  property var entries: []        // { name, path, icon: [names], mime, modified, created, added, isDir }
  property bool loaded: false

  function refresh() {
    if (!path) return
    if (lister.running) { pending = true; return }
    lister.running = true
  }
  property bool pending: false

  Process {
    id: lister
    command: ["python3", "-c",
      "import sys, os, json\n" +
      "import gi\n" +
      "gi.require_version('Gio', '2.0')\n" +
      "from gi.repository import Gio\n" +
      "p = sys.argv[1]\n" +
      "out = []\n" +
      "try:\n" +
      "    d = Gio.File.new_for_path(p)\n" +
      "    en = d.enumerate_children('standard::name,standard::display-name,standard::icon,standard::content-type,standard::type,standard::is-hidden,time::modified,time::created', Gio.FileQueryInfoFlags.NONE, None)\n" +
      "    for i in en:\n" +
      "        if i.get_is_hidden(): continue\n" +
      "        ic = i.get_icon()\n" +
      "        names = list(ic.get_names()) if ic is not None and hasattr(ic, 'get_names') else []\n" +
      "        full = os.path.join(p, i.get_name())\n" +
      "        try: added = int(os.stat(full).st_ctime)\n" +
      "        except Exception: added = 0\n" +
      "        out.append({'name': i.get_display_name(), 'path': full, 'icon': names, 'mime': i.get_content_type() or '', 'modified': int(i.get_attribute_uint64('time::modified') or 0), 'created': int(i.get_attribute_uint64('time::created') or 0), 'added': added, 'isDir': i.get_file_type() == Gio.FileType.DIRECTORY})\n" +
      "except Exception as e:\n" +
      "    pass\n" +
      "print(json.dumps(out))\n", watcher.path]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { watcher.entries = JSON.parse(String(text || "[]")) } catch (e) { watcher.entries = [] }
        watcher.loaded = true
      }
    }
    onExited: if (watcher.pending) { watcher.pending = false; lister.running = true }
  }

  Process {
    id: notify
    command: ["inotifywait", "-m", "-q", "-e", "create,delete,moved_to,moved_from,close_write,attrib", "--format", "%f", watcher.path]
    stdout: SplitParser { onRead: function (line) { debounce.restart() } }
  }
  Timer { id: debounce; interval: 400; onTriggered: watcher.refresh() }

  onPathChanged: { if (notify.running) notify.running = false; if (path) { refresh(); notify.running = true } }
  Component.onCompleted: if (path) { refresh(); notify.running = true }
}
