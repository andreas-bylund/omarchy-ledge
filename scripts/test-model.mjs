// Unit tests for LedgeModel.js. Run with: node scripts/test-model.mjs

import assert from "node:assert/strict"
import { loadModel } from "./load-model.mjs"

const model = loadModel()
const tests = []

const test = (name, fn) => tests.push([name, fn])

test("baseName handles spaces and trailing slashes", () => {
    assert.equal(model.baseName("/home/me/a b.png"), "a b.png")
    assert.equal(model.baseName("/home/me/docs/"), "docs")
    assert.equal(model.baseName("plain.txt"), "plain.txt")
})

test("extensionOf ignores dotfiles and extensionless names", () => {
    assert.equal(model.extensionOf("/tmp/a.TAR.GZ"), "gz")
    assert.equal(model.extensionOf("/tmp/.bashrc"), "")
    assert.equal(model.extensionOf("/tmp/Makefile"), "")
    assert.equal(model.extensionOf("/tmp/weird."), "")
})

test("kindOf maps known extensions and falls back to file", () => {
    assert.equal(model.kindOf("/tmp/a.png"), "image")
    assert.equal(model.kindOf("/tmp/a.MP4"), "video")
    assert.equal(model.kindOf("/tmp/a.7z"), "archive")
    assert.equal(model.kindOf("/tmp/a.qml"), "code")
    assert.equal(model.kindOf("/tmp/a.unknown"), "file")
    assert.equal(model.kindOf("/tmp/dir/"), "folder")
})

test("every kind has an icon", () => {
    for (const kind of new Set(Object.values(model.EXTENSIONS)))
        assert.ok(model.ICONS[kind], `missing icon for ${kind}`)
    assert.equal(model.iconFor("/tmp/a.unknown"), model.ICONS.file)
})

test("pathFromUrl decodes file urls and rejects other schemes", () => {
    assert.equal(model.pathFromUrl("file:///home/me/a%20b.png"), "/home/me/a b.png")
    assert.equal(model.pathFromUrl("file:///tmp/100%25.txt"), "/tmp/100%.txt")
    assert.equal(model.pathFromUrl("https://example.com/a.png"), "")
    assert.equal(model.pathFromUrl("/already/a/path"), "/already/a/path")
})

test("urlFromPath escapes and round trips", () => {
    const path = "/home/me/a b&c#d.png"
    assert.equal(model.urlFromPath(path), "file:///home/me/a%20b%26c%23d.png")
    assert.equal(model.pathFromUrl(model.urlFromPath(path)), path)
})

test("uriList is CRLF terminated per RFC 2483", () => {
    assert.equal(model.uriList(["/a.txt", "/b.txt"]), "file:///a.txt\r\nfile:///b.txt\r\n")
})

test("itemsFromDrop filters, converts and deduplicates", () => {
    const items = model.itemsFromDrop([
        "file:///home/me/a%20b.png",
        "file:///home/me/a%20b.png", // duplicate
        "https://example.com/remote.png", // not a local file
        "# comment line from a uri-list",
        "",
        "/home/me/notes.md"
    ], 42)

    assert.deepEqual(items.map(item => item.path), ["/home/me/a b.png", "/home/me/notes.md"])
    assert.equal(items[0].fileName, "a b.png")
    assert.equal(items[0].isImage, true)
    assert.equal(items[0].addedAt, 42)
    assert.equal(items[1].isImage, false)
    assert.equal(items[1].icon, model.ICONS.document)
})

test("serialize/deserialize round trips", () => {
    const items = model.itemsFromDrop(["/home/me/a b.png", "/home/me/notes.md"], 7)
    const restored = model.deserialize(model.serialize(items))
    assert.deepEqual(restored.map(item => item.path), items.map(item => item.path))
    assert.equal(restored[0].addedAt, 7)
    assert.equal(JSON.parse(model.serialize(items)).version, model.STATE_VERSION)
})

test("deserialize survives junk instead of losing the ledge", () => {
    assert.deepEqual(model.deserialize(""), [])
    assert.deepEqual(model.deserialize("not json at all"), [])
    assert.deepEqual(model.deserialize('{"items":"nope"}'), [])
    assert.deepEqual(model.deserialize('["/a.txt","relative.txt"]').map(i => i.path), ["/a.txt"])
    assert.deepEqual(model.deserialize('[{"path":"/a.txt","extra":1}]').map(i => i.path), ["/a.txt"])
})

test("boolSetting accepts the strings omarchy bar set writes", () => {
    // `omarchy bar set <id> <key> <value>` without --json stores a string.
    assert.equal(model.boolSetting("true", false), true)
    assert.equal(model.boolSetting("false", true), false)
    assert.equal(model.boolSetting("TRUE", false), true)
    assert.equal(model.boolSetting(" off ", true), false)
    // --json, and shell.json edited by hand, give real booleans.
    assert.equal(model.boolSetting(true, false), true)
    assert.equal(model.boolSetting(false, true), false)
    // Unset or unintelligible falls back rather than guessing.
    assert.equal(model.boolSetting(undefined, true), true)
    assert.equal(model.boolSetting(null, false), false)
    assert.equal(model.boolSetting("perhaps", true), true)
    assert.equal(model.boolSetting("perhaps", false), false)
})

test("intSetting refuses to hand a timer a NaN", () => {
    // `omarchy bar set <id> autoCloseSeconds 5` stores the string "5", and
    // checks it against neither the manifest's type nor its min/max.
    assert.equal(model.intSetting("5", 3, 1, 15), 5)
    assert.equal(model.intSetting(" 5 ", 3, 1, 15), 5)
    assert.equal(model.intSetting(5, 3, 1, 15), 5)
    assert.equal(model.intSetting("2.6", 3, 1, 15), 3)
    // Out of the range the manifest advertises: clamped to it, not obeyed.
    assert.equal(model.intSetting("0", 3, 1, 15), 1)
    assert.equal(model.intSetting("-4", 3, 1, 15), 1)
    assert.equal(model.intSetting("900", 3, 1, 15), 15)
    // Unintelligible falls back rather than reaching a Timer as NaN, which
    // would fire at once and shut the ledge the moment it opened.
    assert.equal(model.intSetting("abc", 3, 1, 15), 3)
    assert.equal(model.intSetting("", 3, 1, 15), 3)
    assert.equal(model.intSetting("  ", 3, 1, 15), 3)
    assert.equal(model.intSetting(undefined, 3, 1, 15), 3)
    assert.equal(model.intSetting(null, 3, 1, 15), 3)
    assert.equal(model.intSetting(true, 3, 1, 15), 3)
    assert.equal(model.intSetting(NaN, 3, 1, 15), 3)
    assert.equal(model.intSetting(Infinity, 3, 1, 15), 3)
    // Unbounded is allowed: both bounds are optional.
    assert.equal(model.intSetting("900", 3), 900)
})

test("state file lives under XDG state home", () => {
    assert.equal(model.stateDir("/home/me"), "/home/me/.local/state/omarchy-ledge")
    assert.equal(model.stateFile("/home/me"), "/home/me/.local/state/omarchy-ledge/ledge.json")
    // $XDG_STATE_HOME wins over the default when the session sets it.
    assert.equal(model.stateFile("/home/me", "/home/me/.state"), "/home/me/.state/omarchy-ledge/ledge.json")
    // Nowhere private to write means no persistence at all. /tmp is shared and
    // predictable, so it is not the answer to a missing home.
    assert.equal(model.stateDir(""), "")
    assert.equal(model.stateFile(""), "")
    assert.equal(model.stateFile("", ""), "")
})

let failed = 0
for (const [name, fn] of tests) {
    try {
        fn()
        console.log(`ok   ${name}`)
    } catch (error) {
        failed++
        console.error(`FAIL ${name}\n     ${error.message}`)
    }
}

console.log(`\n${tests.length - failed}/${tests.length} passed`)
process.exit(failed ? 1 : 0)
