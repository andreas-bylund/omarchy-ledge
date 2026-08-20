# Ledge

A file drop zone for [Omarchy](https://omarchy.org) that hangs off the bar —
drop files on it from anywhere, then drag them back out into any window later.

![Four files picked up from two different folders, carried across, and dragged
out together into a third](assets/demo.gif)

*Collect from wherever you happen to be — the bar icon takes the drop without
opening anything — then drag the lot back out where it needs to go.*

## Why

Drag and drop between two windows is painful in a tiling window manager: the
source and the target are rarely on screen at the same time, and you lose the
drag the moment you switch workspace. Ledge gives you a place to park files
in between — open it, drop, switch to wherever the file needs to go, open it
again, drag out. It is inspired by [Dropover](https://dropoverapp.com) on macOS.

## Features

- **Drop straight on the bar icon.** By the time you want somewhere to put a
  file you are already dragging it, with no free hand to open anything — so the icon
  in the bar is itself the drop zone. Hold the drag on it for a moment and the
  ledge opens under it.
- **Drop anything on it** — from a file manager, a browser, or `dragon` in a
  terminal.
- **Drag files back out** into any window — one at a time, or ctrl-click several
  and drag them together — with **copy as file** as a fallback for apps that do
  not take drops (click a chip, then paste).
- **Survives workspace switches, hides and shell restarts** — the ledge lives in
  the long-running shell process and its contents are saved to disk.
- **Thumbnails** for images, file-type icons for everything else.
- **Per-file actions**: copy path, open, remove.
- **Lives on the bar**: an icon that fills up as files land on it, and a card
  that opens right under it — no floating window to chase.
- **Stays open while you work.** Unlike the other bar popups it does not close
  when you click another window, because that click is usually the start of the
  drag that brings a file to it.
- **CLI**: `omarchy-ledge add report.pdf` from any terminal or script.
- **Themed by Omarchy** — every colour comes from the active theme, so it looks
  first-party in all of them.

## Install

```bash
omarchy plugin add https://github.com/andreas-bylund/omarchy-ledge.git
omarchy plugin enable bylund.ledge
```

The ledge rides on its bar widget, so make sure **Ledge** is in a bar section
(`omarchy bar put bylund.ledge`). That icon is both the counter and the way
to open the ledge.

Then bind a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + L", "Ledge", "omarchy-shell bylund.ledge toggle")
```

To get the `omarchy-ledge` command, put its directory on your `PATH` (or copy
the script into `~/.local/bin`):

```bash
cp ~/.config/omarchy/plugins/bylund.ledge/bin/omarchy-ledge ~/.local/bin/
```

### Removing it

```bash
omarchy plugin remove bylund.ledge
rm -f ~/.local/bin/omarchy-ledge      # if you copied the CLI onto your PATH
rm -rf ~/.local/state/omarchy-ledge   # the files the ledge remembered
```

`omarchy plugin remove` takes the widget off the bar — the settings live in that
bar entry and go with it — and deletes the plugin directory. Those two paths are
everything else Ledge ever wrote; a keybinding you added to
`~/.config/hypr/bindings.lua` is yours to take back out. Removing the plugin
never touches the files that were on the ledge, only the list of where they are.

## Using it

![The open card: a thumbnail per image, a file-type icon for everything else,
and the file count and header actions along the top](preview.png)

| Action | What happens |
| --- | --- |
| Drag files onto the bar icon | They land on the ledge without opening anything — the icon fills up and the count moves |
| Hold a drag on the bar icon | The ledge opens under it after a moment, so you can see what is there or drop into the list |
| Click the bar icon | Opens the ledge under it (click again to close) |
| Right-click the bar icon | Copies everything on the ledge as files, ready to paste |
| Drop files on the open card | They are added as chips (duplicates are ignored) |
| Drag a chip out | The file is **copied** into the target window — the original stays where it is, and the chip stays on the ledge so you can drop it somewhere else too. Moving can be turned on (see Settings) |
| Ctrl-click chips | Marks them; dragging any one of them carries the whole selection, and the ledge stays open while any are marked |
| Shift-click a chip | Marks the run from where the selection started to here, replacing what was marked. Ctrl-shift-click adds the run instead |
| Click a chip | Drops the selection and copies that one file to the clipboard — paste it into any app that accepts files |
| Hover a chip | Copy path · Open · Remove |
| Header buttons | Copy · Remove · Settings · Close — the first two act on the selection when there is one, on the whole ledge otherwise |
| Move the pointer away | The ledge closes itself a few seconds later (see Settings) |
| `Esc` | Closes the ledge, once the card has the keyboard (click it first) |

The card puts itself away a few seconds after the pointer leaves it, and stays
put while you use it — for as long as a drag out of it is in flight, and for as
long as chips are marked, since a selection is a drag you have not made yet.
It closes on pointer-leave rather than on the outside click every other bar
popup uses, because that dismissal is a screen-wide input region and this window
is a drag *source*: a surface covering the screen would catch the drop of a chip
dragged out of the ledge instead of the application you aimed it at.

For the same reason the ledge never takes the keyboard on its own — a popup that
grabs input is a popup that eats the mouse press starting your next drag — so
`Esc` only reaches it after you have clicked the card. The ✕, the bar icon, and
a keybinding on `omarchy-ledge toggle` close it from anywhere.

### Command line

```bash
omarchy-ledge add ~/Pictures/screenshot.png   # add and open the ledge
omarchy-ledge add --no-show ./report.pdf      # add quietly
omarchy-ledge list                            # print the ledge contents
omarchy-ledge count
omarchy-ledge clear
omarchy-ledge toggle                          # show / hide the ledge
```

Handy with other tools:

```bash
omarchy-ledge add "$(ls -t ~/Downloads/* | head -1)"   # shelve the newest download
find . -name '*.log' -newermt '-1 hour' | xargs omarchy-ledge add --no-show
```

## Settings

| Setting | Default | What it does |
| --- | --- | --- |
| `autoClose` | on | Close the ledge once the pointer has left both the card and the bar icon. Off keeps it up until you close it. |
| `allowMove` | off | Let the application you drop into move the files instead of copying them. Off, a drag out is always a copy. See below before turning it on. |
| `autoCloseSeconds` | 3 | How long that takes. A drag out of the ledge, a drag hovering the bar icon, and a standing selection all hold it open regardless. |

The clock only starts once the pointer has actually been on the ledge, so a
ledge summoned from the keyboard while the mouse is elsewhere waits to be used
instead of vanishing on its own.

`allowMove` has a toggle behind the gear in the card's header. Any of them can
also be set from the command line:

```bash
omarchy bar set bylund.ledge allowMove true
omarchy bar set bylund.ledge autoCloseSeconds 5
```

Settings live next to the widget's `id` in `~/.config/omarchy/shell.json`, so
they can be edited there too:

```json
{ "id": "bylund.ledge", "allowMove": true }
```

`omarchy bar set` stores the value as a string unless you add `--json`. Ledge
treats `true` and `"true"` the same, so both spellings work.

## Where state is kept

`~/.local/state/omarchy-ledge/ledge.json` — or `$XDG_STATE_HOME/omarchy-ledge/`
if your session sets that. A plain list of paths. Delete it to reset the
ledge. Only file paths are stored, never file contents — putting a file on
the ledge does not copy, move or upload it, and dragging one back out copies it
unless you have turned on `allowMove`.

Ledge never deletes a file itself, in either mode. With `allowMove` on it hands
the target application both options and that application does the moving. What
Ledge does afterwards is look: a file that is no longer at its path was moved,
so its chip goes too. So the worst either mode can get wrong is a chip that
lingers — never a file.

A file that disappears from disk while it is on the ledge keeps its chip (with a
generic icon) until you remove it — it may be on a drive you unplugged. The one
exception is a file that has gone missing right after being dragged out, which
is a move: that chip is dropped for you.

## Troubleshooting

**A drop does not land.** Every drag that reaches the ledge logs what the
source offered, which says whether the drop arrived at all and in which format:

```bash
journalctl --user -t omarchy-shell -f | grep omarchy-ledge
```

**Dragging out does nothing in some app.** Click the chip instead — it copies
the file to the clipboard as `text/uri-list`, which most apps accept on paste.
See [docs/drag-and-drop.md](docs/drag-and-drop.md) for the details and for the
verification checklist.

**Nothing is copied.** The clipboard actions shell out to `wl-copy`; install
`wl-clipboard` if it is missing.

**Icons show as boxes.** The chips use Nerd Font glyphs from Omarchy's default
shell font; make sure it is still configured.

**The ledge does not appear.** It opens under its own bar icon, so the widget
has to be on the bar. Check that the plugin is enabled and answering:

```bash
omarchy plugin list
omarchy bar put bylund.ledge     # put the widget back on the bar
omarchy-shell bylund.ledge toggle
journalctl --user -t omarchy-shell -n 50   # what the shell made of the plugin
```

## Development

Link your checkout into the plugin directory — saving a file hot-reloads the
shell:

```bash
git clone https://github.com/andreas-bylund/omarchy-ledge.git ~/Projects/omarchy-ledge
ln -s ~/Projects/omarchy-ledge ~/.config/omarchy/plugins/bylund.ledge
cd ~/Projects/omarchy-ledge
omarchy plugin validate ./
```

Checks that run without an Omarchy session (and in CI):

```bash
node scripts/validate-plugin.mjs   # manifest rules
node scripts/check-qml.mjs         # QML structural sanity
node scripts/test-model.mjs        # unit tests for LedgeModel.js
shellcheck bin/omarchy-ledge
```

| File | Role |
| --- | --- |
| `BarWidget.qml` | The plugin: bar button, ledge state, persistence, IPC, card contents |
| `LedgePopup.qml` | The card itself: a layer-shell surface placed under the bar icon |
| `LedgeChip.qml` | One file: thumbnail, drag-out, per-file actions |
| `LedgeIconButton.qml` | Small icon button with a tooltip |
| `LedgeTheme.qml` | Maps Omarchy theme colours to the roles used here |
| `LedgeModel.js` | Pure helpers: paths, urls, icons, serialisation |
| `bin/omarchy-ledge` | CLI front end, talks to the plugin over shell IPC |

Bar widgets are rebuilt from their component, so a saved file is not always
enough while developing the button or the card — `omarchy-restart-shell` is the
reliable reload.

Further reading:

- [docs/drag-and-drop.md](docs/drag-and-drop.md) — how drag and drop works here
  and how to verify it
- [docs/icons.md](docs/icons.md) — where the Nerd Font codepoints come from and
  how to check one

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
