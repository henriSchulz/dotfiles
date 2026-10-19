// Extra search words for installed applications.
//
// Spotlight already learns synonyms from each .desktop file (`Keywords=` and
// `GenericName=`), but most apps ship none: "browser" finds neither Chromium
// nor Helium, "notes" misses Obsidian, "photoshop" misses Pinta. This table
// fills that gap. Every key is a desktop id without the `.desktop` suffix
// (`omawrite`, `org.gnome.Nautilus`) or an application's visible name
// ("Files"); every value is the list of words that should also find it.
//
// Keys for apps that are not installed cost nothing -- they simply never
// match -- so the table also covers the usual suspects Henri may install
// later.
//
// Personal additions belong in ~/.config/omarchy/app-aliases.jsonc, which is
// watched: an edit there takes effect on the next keystroke, no restart. Its
// entries are added to the ones here; a word written with a leading "-"
// ("-photoshop") drops one of the defaults again.

var DEFAULTS = {
  // ------------------------------------------------------------- browsers
  "chromium": ["browser", "web", "internet", "chrome", "google", "surfen"],
  "helium": ["browser", "web", "internet", "surfen"],
  "firefox": ["browser", "web", "internet", "surfen"],
  "zen": ["browser", "web", "internet", "surfen"],
  "brave-browser": ["browser", "web", "internet", "surfen"],
  "google-chrome": ["browser", "web", "internet", "surfen"],

  // -------------------------------------------------------- communication
  "signal": ["chat", "messenger", "messages", "nachrichten", "texting"],
  "WhatsApp": ["chat", "messenger", "messages", "nachrichten", "wa"],
  "Discord": ["chat", "voice", "gaming", "server", "nachrichten"],
  "telegram-desktop": ["chat", "messenger", "messages", "nachrichten"],
  "slack": ["chat", "messenger", "work", "team"],
  "eu.betterbird.Betterbird": ["mail", "email", "e-mail", "inbox", "post", "thunderbird", "newsletter"],
  "thunderbird": ["mail", "email", "e-mail", "inbox", "post"],
  "us.zoom.Zoom": ["meeting", "call", "video call", "konferenz"],

  // ------------------------------------------------------ notes & writing
  "md.obsidian.obsidian": ["notes", "notizen", "markdown", "wiki", "vault", "zettelkasten", "second brain"],
  "omawrite": ["notes", "notizen", "write", "schreiben", "markdown", "text", "editor", "scratchpad"],
  "com.github.xournalpp.xournalpp": ["notes", "notizen", "handwriting", "handschrift", "annotate", "sketch", "pdf"],
  "mdview": ["markdown", "preview", "readme", "viewer"],
  "com.logseq.Logseq": ["notes", "notizen", "outline", "wiki"],
  "notion-app": ["notes", "notizen", "wiki", "docs"],

  // -------------------------------------------------------------- coding
  "code": ["editor", "ide", "develop", "programming", "programmieren", "vscode"],
  "nvim": ["editor", "vim", "code", "develop", "programmieren"],
  "dev.zed.Zed": ["editor", "ide", "code", "develop"],
  "sublime_text": ["editor", "ide", "code", "develop"],
  "jetbrains-idea": ["editor", "ide", "java", "develop"],
  "Docker": ["containers", "container", "compose", "images", "devops"],
  "dbeaver": ["database", "datenbank", "sql", "postgres", "mysql"],

  // -------------------------------------------------------------- office
  "libreoffice-writer": ["word", "doc", "docx", "document", "dokument", "schreiben", "text"],
  "libreoffice-calc": ["excel", "spreadsheet", "tabelle", "sheet", "xlsx", "tabellen"],
  "libreoffice-impress": ["powerpoint", "slides", "presentation", "präsentation", "ppt", "deck"],
  "libreoffice-draw": ["vector", "diagram", "drawing", "visio", "zeichnen"],
  "libreoffice-base": ["database", "datenbank", "access"],
  "libreoffice-startcenter": ["office", "documents", "dokumente"],
  "org.gnome.Papers": ["pdf", "document", "dokument", "reader", "viewer", "ebook", "lesen"],
  "calibre-gui": ["ebook", "books", "bücher", "epub", "library"],

  // --------------------------------------------------------------- media
  "mpv": ["video", "player", "movie", "film", "watch", "abspielen"],
  "cliamp": ["music", "musik", "audio", "player", "radio", "podcast", "songs"],
  "spotify": ["music", "musik", "audio", "player", "podcast", "songs"],
  "org.kde.kdenlive": ["video editor", "videoschnitt", "edit video", "schneiden", "movie", "cut"],
  "omacut": ["video", "trim", "cut", "clip", "schneiden", "kürzen"],
  "com.obsproject.Studio": ["record", "recording", "screen recording", "stream", "capture", "aufnahme", "bildschirmaufnahme"],
  "imv": ["image", "images", "photo", "photos", "bild", "bilder", "picture", "viewer", "ansehen"],
  "de.henri.IcloudPhotos": ["photos", "fotos", "bilder", "icloud", "pictures", "gallery", "galerie"],
  "com.github.PintaProject.Pinta": ["image editor", "photoshop", "paint", "malen", "edit image", "bild bearbeiten", "retouch"],
  "gimp": ["image editor", "photoshop", "paint", "edit image", "bild bearbeiten", "retouch"],
  "org.inkscape.Inkscape": ["vector", "svg", "illustrator", "draw", "zeichnen", "logo"],
  "dev.tensaku.Tensaku": ["screenshot", "annotate", "markup", "capture", "bildschirmfoto", "screen capture"],
  "YouTube": ["video", "watch", "yt", "stream", "videos"],
  "com.moonlight_stream.Moonlight": ["game streaming", "remote play", "sunshine", "games", "spiele"],
  "steam": ["games", "spiele", "gaming", "library"],

  // ------------------------------------------------------ files & system
  "de.henri.Finder": ["files", "dateien", "explorer", "folder", "ordner", "file manager", "dateimanager", "browse", "nautilus"],
  "org.gnome.Nautilus": ["files", "dateien", "explorer", "finder", "folder", "ordner", "file manager", "dateimanager", "browse"],
  "thunar": ["files", "dateien", "explorer", "finder", "file manager", "dateimanager"],
  "org.kde.dolphin": ["files", "dateien", "explorer", "finder", "file manager", "dateimanager"],
  "foot": ["terminal", "shell", "console", "konsole", "command line", "kommandozeile", "cli", "prompt"],
  "Alacritty": ["terminal", "shell", "console", "command line", "cli"],
  "com.mitchellh.ghostty": ["terminal", "shell", "console", "command line", "cli"],
  "kitty": ["terminal", "shell", "console", "command line", "cli"],
  "btop": ["task manager", "activity monitor", "system monitor", "processes", "prozesse", "cpu", "ram", "load"],
  "org.gnome.DiskUtility": ["disks", "drives", "partition", "format", "usb", "festplatte", "laufwerk", "smart"],
  "Disk Usage": ["disk usage", "storage", "speicher", "space", "platz", "baobab", "full"],
  "org.gnome.baobab": ["disk usage", "storage", "speicher", "space", "platz", "full"],
  "omarchy-settings": ["settings", "preferences", "einstellungen", "system settings", "systemeinstellungen", "config", "control panel", "systemsteuerung"],
  "omacalc": ["calculator", "calc", "rechner", "taschenrechner", "math", "rechnen"],
  "bitwarden": ["passwords", "passwörter", "password manager", "vault", "2fa", "otp", "login", "keychain", "schlüssel"],
  "org.keepassxc.KeePassXC": ["passwords", "passwörter", "password manager", "vault", "2fa", "otp", "login"],
  "localsend": ["airdrop", "share", "send files", "transfer", "dateien senden", "nearby", "teilen"],
  "com.github.wwmm.easyeffects": ["audio", "equalizer", "eq", "sound", "effects", "mikrofon", "mic", "klang"],
  "me.kavishdevar.librepods": ["airpods", "headphones", "kopfhörer", "bluetooth", "earbuds", "ohrhörer"],
  "voxtype-configure": ["dictation", "diktat", "voice", "speech to text", "transcribe", "sprache", "mic"],
  "aether": ["theme", "wallpaper", "colors", "appearance", "design", "hintergrund", "farben"],
  "system-config-printer": ["printer", "drucker", "print", "drucken", "cups"],
  "cups": ["printer", "drucker", "print", "drucken", "queue"],
  "claude-quick": ["ai", "assistant", "chat", "claude", "llm", "ki"],
  "org.quickshell": ["shell", "bar", "panel", "desktop shell"],
  "virtualbox": ["vm", "virtual machine", "virtualisierung", "emulator"]
}

function normalizeKey(value) {
  var key = String(value || "").trim().toLowerCase()
  if (key.slice(-8) === ".desktop") key = key.slice(0, -8)
  return key
}

function normalizeTerms(value) {
  var list = Array.isArray(value) ? value : (typeof value === "string" ? String(value).split(/[;,]/) : [])
  var out = []
  for (var i = 0; i < list.length; i++) {
    var term = String(list[i] || "").trim()
    if (term.length > 0) out.push(term)
  }
  return out
}

// Defaults keyed the way they are written above, so a lookup by desktop id or
// by visible name finds them regardless of case.
function normalizeTable(source) {
  var table = ({})
  for (var key in source) {
    var id = normalizeKey(key)
    if (!id) continue
    var terms = normalizeTerms(source[key])
    table[id] = (table[id] || []).concat(terms)
  }
  return table
}

// The user file is JSONC (the menu's own dialect: whole-line // comments and
// trailing commas), either a bare map or one under an "apps"/"aliases" key.
function parseUserTable(rawText, stripJsonc) {
  var stripped = typeof stripJsonc === "function" ? stripJsonc(rawText) : String(rawText || "")
  if (!String(stripped).trim()) return ({})
  var parsed
  try { parsed = JSON.parse(stripped) } catch (e) { return ({}) }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return ({})
  var source = parsed
  if (parsed.apps && typeof parsed.apps === "object" && !Array.isArray(parsed.apps)) source = parsed.apps
  else if (parsed.aliases && typeof parsed.aliases === "object" && !Array.isArray(parsed.aliases)) source = parsed.aliases
  return normalizeTable(source)
}

// User terms are added to the built-in ones; "-term" removes a built-in one.
function mergeTables(base, extra) {
  var merged = ({})
  var key
  for (key in base) merged[key] = base[key].slice()
  for (key in extra) {
    var terms = extra[key]
    var list = merged[key] || []
    for (var i = 0; i < terms.length; i++) {
      var term = terms[i]
      if (term.charAt(0) === "-" && term.length > 1) {
        var drop = term.slice(1).toLowerCase()
        list = list.filter(function(value) { return value.toLowerCase() !== drop })
      } else if (list.indexOf(term) < 0) {
        list = list.concat([term])
      }
    }
    merged[key] = list
  }
  return merged
}

function defaultTable() {
  return normalizeTable(DEFAULTS)
}

function tableFrom(rawUserText, stripJsonc) {
  return mergeTables(defaultTable(), parseUserTable(rawUserText, stripJsonc))
}

// Both the desktop id and the visible name are looked up, so "org.gnome.Nautilus"
// and "Files" are equally valid keys for the same app.
function aliasesFor(table, appId, name) {
  if (!table) return []
  var out = []
  var keys = [normalizeKey(appId), normalizeKey(name)]
  for (var i = 0; i < keys.length; i++) {
    if (!keys[i]) continue
    if (i > 0 && keys[i] === keys[0]) continue
    var terms = table[keys[i]]
    if (terms) out = out.concat(terms)
  }
  return out
}

// Applications that go to the top whenever the query names them. Without it
// System Settings ties with every menu and app that shares a prefix
// ("Setup", "System", "Signal", "Print Settings") and lands wherever the
// tie-break puts it. Same keys as DEFAULTS; the value is added to the fuzzy
// score (an exact title match is worth 1200, a title prefix around 900).
var PRIORITY = {
  "omarchy-settings": 600
}

function priorityFor(appId, name) {
  return PRIORITY[normalizeKey(appId)] || PRIORITY[normalizeKey(name)] || 0
}

// True when every word of the query begins a word of one of the names
// ("s", "sys", "system set", "einst"). Deliberately not fuzzy: the bonus is
// for naming the app, and "st" must still find Steam first. Keywords such as
// "bluetooth" are no names either -- there the Bluetooth action stays on top.
function namedBy(query, names) {
  var tokens = String(query || "").toLowerCase().split(/\s+/).filter(function(t) { return t.length > 0 })
  if (tokens.length === 0) return false
  var words = []
  for (var i = 0; i < names.length; i++) words = words.concat(String(names[i] || "").toLowerCase().split(/[\s\-_.]+/))
  for (var t = 0; t < tokens.length; t++) {
    var found = false
    for (var w = 0; w < words.length && !found; w++) found = words[w].indexOf(tokens[t]) === 0
    if (!found) return false
  }
  return true
}

// Keywords, GenericName and the table all contribute, and they overlap often
// (omawrite ships "notes" itself). Scoring the same word twice only costs
// time, so the row keeps one of each, in the order they were added.
function dedupe(values) {
  var seen = ({})
  var out = []
  for (var i = 0; i < values.length; i++) {
    var value = String(values[i] || "").trim()
    if (!value) continue
    var key = value.toLowerCase()
    if (seen[key]) continue
    seen[key] = true
    out.push(value)
  }
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    DEFAULTS: DEFAULTS,
    normalizeKey: normalizeKey,
    normalizeTerms: normalizeTerms,
    normalizeTable: normalizeTable,
    parseUserTable: parseUserTable,
    mergeTables: mergeTables,
    defaultTable: defaultTable,
    tableFrom: tableFrom,
    aliasesFor: aliasesFor,
    priorityFor: priorityFor,
    namedBy: namedBy,
    dedupe: dedupe
  }
}
