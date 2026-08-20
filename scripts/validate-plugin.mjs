// Mirrors the checks `omarchy plugin validate ./` performs, so a broken
// manifest is caught in CI on machines without Omarchy installed.
// Run with: node scripts/validate-plugin.mjs

import { readFileSync, readdirSync, lstatSync } from "node:fs"
import { dirname, join, relative } from "node:path"
import { fileURLToPath } from "node:url"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")
const errors = []

const check = (condition, message) => {
    if (!condition)
        errors.push(message)
}

let manifest
try {
    manifest = JSON.parse(readFileSync(join(root, "manifest.json"), "utf8"))
} catch (error) {
    console.error(`manifest.json is not readable JSON: ${error.message}`)
    process.exit(1)
}

check(manifest.schemaVersion === 1, "schemaVersion must be the number 1")
check(typeof manifest.id === "string" && /^[a-z0-9-]+\.[a-z0-9-]+$/.test(manifest.id),
      "id must look like <namespace>.<name>")
check(!String(manifest.id).startsWith("omarchy."), "the omarchy.* namespace is reserved")
check(typeof manifest.name === "string" && manifest.name.length > 0, "name is required")
check(/^\d+\.\d+\.\d+$/.test(String(manifest.version)), "version must be semver, e.g. 0.1.0")
check(Array.isArray(manifest.kinds) && manifest.kinds.length > 0, "kinds must be a non-empty array")

const ENTRY_POINT_FOR = { panel: "panel", "bar-widget": "barWidget", service: "service" }

for (const kind of manifest.kinds ?? []) {
    const key = ENTRY_POINT_FOR[kind]
    check(key !== undefined, `unknown kind: ${kind}`)
    if (!key)
        continue
    const entry = manifest.entryPoints?.[key]
    check(typeof entry === "string" && entry.length > 0, `kind "${kind}" needs entryPoints.${key}`)
    if (typeof entry === "string") {
        try {
            lstatSync(join(root, entry))
        } catch {
            errors.push(`entryPoints.${key} points at a missing file: ${entry}`)
        }
    }
}

// The CLI prints its own version, and there is no way for it to read the
// manifest at runtime — it talks to the shell, not to this folder. So the two
// are checked against each other here instead of drifting apart quietly.
const cli = readFileSync(join(root, "bin/omarchy-ledge"), "utf8")
const cliVersion = cli.match(/^VERSION="([^"]*)"/m)?.[1]
check(cliVersion !== undefined, "bin/omarchy-ledge has no VERSION= line")
check(cliVersion === undefined || cliVersion === String(manifest.version),
      `bin/omarchy-ledge says ${cliVersion}, manifest.json says ${manifest.version}`)

// The plugin folder is cloned or copied onto other machines, so a symlink
// *inside* the tree points at something that will not be there. (Linking the
// plugin directory itself into ~/.config/omarchy/plugins is fine and is the
// documented development workflow — that is a link to this tree, not in it.)
const walk = directory => {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
        if (entry.name === ".git")
            continue
        const path = join(directory, entry.name)
        if (entry.isSymbolicLink())
            errors.push(`symlinks are not allowed inside a plugin: ${relative(root, path)}`)
        else if (entry.isDirectory())
            walk(path)
    }
}
walk(root)

if (errors.length) {
    for (const error of errors)
        console.error(`error: ${error}`)
    process.exit(1)
}

console.log(`ok   manifest.json (${manifest.id} ${manifest.version}, kinds: ${manifest.kinds.join(", ")}, cli ${cliVersion})`)
