.pragma library

// Ledge — pure helpers for the ledge item list.
//
// Kept free of QML object references so the pure logic can be unit tested
// without Qt (scripts/test-model.mjs). Everything here is a plain function
// over plain data.
//
// An item is: { path, fileName, ext, kind, icon, isImage, addedAt }

var STATE_VERSION = 1

// Nerd Font (Material Design) glyphs, shipped with Omarchy's default font.
// Names are nf-md-*, and every codepoint below is checked against the font's
// own glyph names (see docs/icons.md) — the numbering is dense enough that a
// neighbouring codepoint is a completely unrelated picture.
var ICONS = {
    file: "\u{F0214}",    // nf-md-file
    image: "\u{F021F}",   // nf-md-file_image
    video: "\u{F022B}",   // nf-md-file_video
    audio: "\u{F0223}",   // nf-md-file_music
    pdf: "\u{F0226}",     // nf-md-file_pdf_box
    document: "\u{F0219}",// nf-md-file_document
    archive: "\u{F06EB}", // nf-md-folder_zip
    code: "\u{F022E}",    // nf-md-file_code
    folder: "\u{F024B}"   // nf-md-folder
}

var EXTENSIONS = {
    // images (rendered as real thumbnails, not as a glyph)
    png: "image", jpg: "image", jpeg: "image", gif: "image", webp: "image",
    bmp: "image", svg: "image", avif: "image", ico: "image", tiff: "image",
    // media
    mp4: "video", mkv: "video", webm: "video", mov: "video", avi: "video",
    mp3: "audio", flac: "audio", ogg: "audio", wav: "audio", m4a: "audio", opus: "audio",
    // documents
    pdf: "pdf",
    doc: "document", docx: "document", odt: "document", rtf: "document",
    txt: "document", md: "document", csv: "document", xlsx: "document", ods: "document",
    // archives
    zip: "archive", tar: "archive", gz: "archive", xz: "archive", zst: "archive",
    bz2: "archive", "7z": "archive", rar: "archive",
    // code
    js: "code", ts: "code", qml: "code", json: "code", yaml: "code", yml: "code",
    toml: "code", sh: "code", bash: "code", py: "code", rb: "code", rs: "code",
    go: "code", c: "code", h: "code", cpp: "code", lua: "code", html: "code", css: "code"
}

function isImageKind(kind) {
    return kind === "image"
}

// "/home/me/a b.png" -> "a b.png"
function baseName(path) {
    var clean = String(path).replace(/\/+$/, "")
    var slash = clean.lastIndexOf("/")
    return slash === -1 ? clean : clean.slice(slash + 1)
}

function extensionOf(path) {
    var name = baseName(path)
    var dot = name.lastIndexOf(".")
    if (dot <= 0 || dot === name.length - 1)
        return ""
    return name.slice(dot + 1).toLowerCase()
}

function kindOf(path) {
    if (String(path).slice(-1) === "/")
        return "folder"
    var kind = EXTENSIONS[extensionOf(path)]
    return kind ? kind : "file"
}

function iconFor(path) {
    var icon = ICONS[kindOf(path)]
    return icon ? icon : ICONS.file
}

// "file:///home/me/a%20b.png" -> "/home/me/a b.png". Non-file URLs return "".
function pathFromUrl(url) {
    var text = String(url)
    if (text.indexOf("file://") === 0)
        text = text.slice("file://".length)
    else if (text.indexOf("://") !== -1)
        return ""
    var hash = text.indexOf("#")
    if (hash !== -1)
        text = text.slice(0, hash)
    try {
        text = decodeURIComponent(text)
    } catch (e) {
        // Leave percent-escapes in place rather than dropping the file.
    }
    return text.indexOf("/") === 0 ? text : ""
}

// "/home/me/a b.png" -> "file:///home/me/a%20b.png"
function urlFromPath(path) {
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
}

// text/uri-list payload for a drag or for the clipboard (CRLF per RFC 2483).
function uriList(paths) {
    return paths.map(urlFromPath).join("\r\n") + "\r\n"
}

function makeItem(path, addedAt) {
    var kind = kindOf(path)
    return {
        path: path,
        fileName: baseName(path),
        ext: extensionOf(path),
        kind: kind,
        icon: iconFor(path),
        isImage: isImageKind(kind),
        addedAt: addedAt ? addedAt : 0
    }
}

// Accepts urls (from a drop) or plain paths (from the CLI); returns clean,
// deduplicated items, skipping anything that is not a local file.
function itemsFromDrop(entries, addedAt) {
    var seen = {}
    var items = []
    for (var i = 0; i < entries.length; i++) {
        var raw = String(entries[i]).trim()
        if (!raw || raw.indexOf("#") === 0)
            continue
        var path = raw.indexOf("/") === 0 ? raw : pathFromUrl(raw)
        if (!path || seen[path])
            continue
        seen[path] = true
        items.push(makeItem(path, addedAt))
    }
    return items
}

function serialize(items) {
    var plain = items.map(function (item) {
        return { path: item.path, addedAt: item.addedAt }
    })
    return JSON.stringify({ version: STATE_VERSION, items: plain }, null, 2) + "\n"
}

// Tolerates an empty file, a bare array, and unknown extra fields.
function deserialize(text) {
    if (!text || !String(text).trim())
        return []
    var parsed
    try {
        parsed = JSON.parse(text)
    } catch (e) {
        return []
    }
    var list = Array.isArray(parsed) ? parsed : (parsed && Array.isArray(parsed.items) ? parsed.items : [])
    var items = []
    for (var i = 0; i < list.length; i++) {
        var entry = list[i]
        var path = typeof entry === "string" ? entry : (entry && entry.path)
        if (!path || String(path).indexOf("/") !== 0)
            continue
        items.push(makeItem(String(path), entry && entry.addedAt ? entry.addedAt : 0))
    }
    return items
}

// Bar settings arrive as real JSON from shell.json, but `omarchy bar set
// <id> <key> <value>` writes the *string* "true"/"false" unless the caller
// remembers --json. Both spellings have to mean the same thing: otherwise the
// most obvious way to change a setting silently does nothing at all.
function boolSetting(value, fallback) {
    if (value === undefined || value === null)
        return fallback
    if (typeof value === "boolean")
        return value
    var text = String(value).trim().toLowerCase()
    if (text === "true" || text === "1" || text === "yes" || text === "on")
        return true
    if (text === "false" || text === "0" || text === "no" || text === "off")
        return false
    return fallback
}

// The integer counterpart to boolSetting, with the same problem behind it:
// `omarchy bar set` writes a string, and nothing checks it against the `min`
// and `max` the manifest advertises, so "abc" arrives intact. Reading that with
// Number() alone yields NaN, and a NaN timer interval is a timer that fires
// immediately — the ledge would slam shut the instant it opened. So anything
// unintelligible falls back, and anything out of range is clamped to the bounds
// the manifest promised rather than obeyed.
function intSetting(value, fallback, min, max) {
    if (value === undefined || value === null || typeof value === "boolean")
        return fallback
    var text = typeof value === "number" ? value : String(value).trim()
    if (text === "")
        return fallback
    var number = Number(text)
    if (!isFinite(number))
        return fallback
    number = Math.round(number)
    if (min !== undefined && number < min)
        return min
    if (max !== undefined && number > max)
        return max
    return number
}

// $XDG_STATE_HOME when the session sets one, ~/.local/state otherwise — the
// default the spec names. With neither there is nowhere private to write, and
// /tmp is no substitute: it is shared, world-writable and entirely predictable,
// so somebody else can be sitting on the path first. An empty string means "do
// not persist", and the ledge still works for as long as the shell runs.
function stateDir(home, stateHome) {
    var base = stateHome ? String(stateHome)
                         : (home ? String(home) + "/.local/state" : "")
    return base ? base + "/omarchy-ledge" : ""
}

function stateFile(home, stateHome) {
    var dir = stateDir(home, stateHome)
    return dir ? dir + "/ledge.json" : ""
}
