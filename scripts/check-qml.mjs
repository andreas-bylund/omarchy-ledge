// A cheap structural sanity check for the QML files: balanced brackets and a
// non-empty import block. It is not a QML parser — `qmllint` (Qt) or simply
// reloading the plugin in the shell is the real check — but it catches typos
// in CI on machines without Qt.
// Run with: node scripts/check-qml.mjs

import { readdirSync, readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")
const PAIRS = { "}": "{", ")": "(", "]": "[" }
let failed = 0

// Strips comments and string literals so their brackets are not counted.
const strip = source => {
    let out = ""
    let index = 0
    let quote = null

    while (index < source.length) {
        const char = source[index]
        const next = source[index + 1]

        if (quote) {
            if (char === "\\") {
                index += 2
                continue
            }
            if (char === quote)
                quote = null
            index++
            continue
        }
        if (char === '"' || char === "'" || char === "`") {
            quote = char
            index++
            continue
        }
        if (char === "/" && next === "/") {
            while (index < source.length && source[index] !== "\n")
                index++
            continue
        }
        if (char === "/" && next === "*") {
            index += 2
            while (index < source.length && !(source[index] === "*" && source[index + 1] === "/"))
                index++
            index += 2
            continue
        }
        out += char
        index++
    }
    return out
}

for (const name of readdirSync(root).filter(file => file.endsWith(".qml")).sort()) {
    const source = readFileSync(join(root, name), "utf8")
    const problems = []

    const stack = []
    let line = 1
    for (const char of strip(source)) {
        if (char === "\n")
            line++
        else if ("{([".includes(char))
            stack.push({ char, line })
        else if (char in PAIRS) {
            const open = stack.pop()
            if (!open || open.char !== PAIRS[char])
                problems.push(`unbalanced "${char}" on line ${line}`)
        }
    }
    if (stack.length)
        problems.push(`unclosed "${stack[stack.length - 1].char}" from line ${stack[stack.length - 1].line}`)

    if (!/^\s*import\s+\S+/m.test(source))
        problems.push("no import statements")

    if (problems.length) {
        failed++
        console.error(`FAIL ${name}\n     ${problems.join("\n     ")}`)
    } else {
        console.log(`ok   ${name}`)
    }
}

process.exit(failed ? 1 : 0)
