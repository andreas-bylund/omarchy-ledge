// Loads LedgeModel.js (a QML `.pragma library` file) as a plain JS module so
// the pure helpers can be unit tested in CI, where Qt is not available.

import { readFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")

const EXPORTS = [
    "STATE_VERSION", "ICONS", "EXTENSIONS", "isImageKind", "baseName",
    "extensionOf", "kindOf", "iconFor", "pathFromUrl", "urlFromPath",
    "uriList", "makeItem", "itemsFromDrop", "serialize", "deserialize",
    "stateDir", "stateFile", "boolSetting", "intSetting"
]

export function loadModel() {
    const source = readFileSync(join(root, "LedgeModel.js"), "utf8")
        .replace(/^\s*\.(pragma|import)\b.*$/gm, "")
    return new Function(`${source}\nreturn { ${EXPORTS.join(", ")} }`)()
}
