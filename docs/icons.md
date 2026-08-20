# Icons

Every icon in Ledge is a Nerd Font glyph from the font Omarchy already uses
for its own bar (`fc-match monospace` — JetBrainsMono Nerd Font on a default
install). No image assets, so the icons follow the user's font and theme.

## Codepoints are checked, not guessed

The Material Design range is dense: `U+F0995` is *progress_check*, `U+F0BA9` is
*library_shelves*, `U+F0225` is *file_jpg_box* where *file_video* is `U+F022B`.
A codepoint that is one off does not render as a box — it renders as a
completely different, perfectly plausible-looking picture, which is exactly the
kind of thing that survives review and shows up in the demo GIF.

The font's own `post` table carries the glyph names, so every codepoint used
here was read back out of the font file itself:

```bash
python3 scripts/glyph-name.py F1296 F0120 F022B
# F1296  md-tray_full
# F0120  md-tray_arrow_down
# F022B  md-file_video
```

`scripts/glyph-name.py` also takes names, so it works in both directions:

```bash
python3 scripts/glyph-name.py --find tray
```

## What is used where

| Glyph | Name | Where |
| --- | --- | --- |
| `U+F1294` | `md-tray` | Bar icon, empty ledge |
| `U+F1296` | `md-tray_full` | Bar icon and card header, ledge with files |
| `U+F0120` | `md-tray_arrow_down` | Empty state ("Drop files here") |
| `U+F0222` | `md-file_multiple` | Copy all as files |
| `U+F01B4` | `md-delete` | Clear ledge, remove file |
| `U+F0156` | `md-close` | Close |
| `U+F0493` | `md-cog` | Settings |
| `U+F018F` | `md-content_copy` | Copy path |
| `U+F03CC` | `md-open_in_new` | Open |
| `U+F02EE` | `md-image_broken_variant` | Image that no longer loads |
| `U+F0214` | `md-file` | Fallback file type |
| `U+F021F` | `md-file_image` | Images |
| `U+F022B` | `md-file_video` | Video |
| `U+F0223` | `md-file_music` | Audio |
| `U+F0226` | `md-file_pdf_box` | PDF |
| `U+F0219` | `md-file_document` | Documents |
| `U+F06EB` | `md-folder_zip` | Archives |
| `U+F022E` | `md-file_code` | Source files |
| `U+F024B` | `md-folder` | Folders |

The file-type glyphs live in `LedgeModel.js`; the rest are named properties at
the top of `BarWidget.qml` and in `LedgeChip.qml`.
