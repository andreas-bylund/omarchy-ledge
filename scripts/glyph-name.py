#!/usr/bin/env python3
"""Look up Nerd Font glyph names by codepoint, or codepoints by name.

The Material Design range is dense enough that an off-by-one codepoint renders
as a different, plausible-looking icon rather than as a missing box, so every
glyph Ledge uses is checked against the font itself. The font's `post` table
carries the glyph names; this reads them straight out of the file, no
dependencies.

    python3 scripts/glyph-name.py F1296 F0120
    python3 scripts/glyph-name.py --find tray
    python3 scripts/glyph-name.py --font /path/to/font.ttf F1296
"""

import argparse
import struct
import subprocess
import sys

MAC_GLYPH_NAMES = 258


def default_font():
    return subprocess.run(["fc-match", "-f", "%{file}", "monospace"],
                          capture_output=True, text=True, check=True).stdout.strip()


def tables(data):
    count = struct.unpack(">H", data[4:6])[0]
    found = {}
    for index in range(count):
        offset = 12 + index * 16
        tag = data[offset:offset + 4].decode("latin1")
        start, length = struct.unpack(">II", data[offset + 8:offset + 16])
        found[tag] = (start, length)
    return found


def glyph_names(data, table):
    start, length = table
    if struct.unpack(">I", data[start:start + 4])[0] != 0x00020000:
        return {}
    count = struct.unpack(">H", data[start + 32:start + 34])[0]
    indexes = struct.unpack(">%dH" % count, data[start + 34:start + 34 + count * 2])
    cursor = start + 34 + count * 2
    end = start + length
    custom = []
    while cursor < end:
        size = data[cursor]
        custom.append(data[cursor + 1:cursor + 1 + size].decode("latin1"))
        cursor += 1 + size
    names = {}
    for glyph, index in enumerate(indexes):
        if index >= MAC_GLYPH_NAMES and index - MAC_GLYPH_NAMES < len(custom):
            names[glyph] = custom[index - MAC_GLYPH_NAMES]
    return names


def codepoints(data, table):
    start, _ = table
    count = struct.unpack(">H", data[start + 2:start + 4])[0]
    subtable = None
    for index in range(count):
        offset = start + 4 + index * 8
        _, _, position = struct.unpack(">HHI", data[offset:offset + 8])
        if struct.unpack(">H", data[start + position:start + position + 2])[0] == 12:
            subtable = start + position
    if subtable is None:
        sys.exit("no format 12 cmap subtable — is this a Nerd Font?")
    mapping = {}
    groups = struct.unpack(">I", data[subtable + 12:subtable + 16])[0]
    for group in range(groups):
        offset = subtable + 16 + group * 12
        first, last, glyph = struct.unpack(">III", data[offset:offset + 12])
        for code in range(first, last + 1):
            mapping[code] = glyph + (code - first)
    return mapping


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("codepoints", nargs="*", help="hex codepoints, e.g. F1296 or U+F1296")
    parser.add_argument("--find", metavar="TEXT", help="list every glyph whose name contains TEXT")
    parser.add_argument("--font", help="font file to read (default: fc-match monospace)")
    args = parser.parse_args()

    path = args.font or default_font()
    data = open(path, "rb").read()
    found = tables(data)
    names = glyph_names(data, found["post"])
    cmap = codepoints(data, found["cmap"])

    if args.find:
        needle = args.find.lower()
        for code in sorted(cmap):
            name = names.get(cmap[code], "")
            if needle in name.lower():
                print("U+%05X  %s" % (code, name))
        return

    if not args.codepoints:
        parser.print_help()
        return

    for raw in args.codepoints:
        code = int(raw.lower().replace("u+", "").replace("0x", ""), 16)
        glyph = cmap.get(code)
        print("%-8s %s" % (raw.upper(), names.get(glyph, "not in this font") if glyph else "not in this font"))


if __name__ == "__main__":
    main()
