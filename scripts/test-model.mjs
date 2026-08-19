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

test("state file lives under XDG state home", () => {
    assert.equal(model.stateFile("/home/me"), "/home/me/.local/state/omarchy-ledge/ledge.json")
    assert.equal(model.stateDir(""), "/tmp/.local/state/omarchy-ledge")
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
