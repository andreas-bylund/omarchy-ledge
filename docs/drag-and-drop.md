# Drag and drop under Wayland

Everything else in Ledge is straightforward QML. Drag and drop is the part
that decides whether the plugin works at all, so it gets its own note.

## What is implemented

| Direction | Mechanism | Status |
| --- | --- | --- |
| Drag **in**, on the bar icon | `DropArea` filling the bar widget, inside the bar's own layer-shell surface | works (Hyprland + Nautilus, 1 and 6 files at a time) |
| Drag **in**, on the open card | `DropArea` filling the card, accepts `urls` and falls back to dropped text | works (Hyprland + Nautilus) |
| Drag **out** | `Drag.dragType: Drag.Automatic` on each chip, `text/uri-list` mime data, started from the chip's `MouseArea` after a 10 px threshold | works — see the `Drag.active` note below |
| Fallback for drag out | click a chip → `wl-copy --type text/uri-list` → paste into the target app | always available |

The fallback is not dead code behind a flag: clicking a chip always copies it as
a file, the header has "copy all as files", and both are documented in the
README. Even where native drag-out is unreliable, the ledge is still useful.

## The bar icon is the primary drop target

The card can only take a drop while it is open, and opening it needs a free
hand — which you do not have once the file is already in mid-air. The bar icon
does not have that problem: it is always on screen, and it sits against a screen
edge you can throw the cursor at without aiming. So the widget itself is a
`DropArea`, the icon turns into a download arrow while a drag is over it, and a
drop there adds the files quietly (the icon fills up, the count moves).

Holding the drag still over the icon for 700 ms opens the card underneath —
spring-loading, the way a macOS Dock icon or a Finder folder opens under a
hovering drag — for when you want to see what is already on the ledge, or drop
into the list itself.

This also means the two targets share a failure mode: both live in layer-shell
surfaces, so a compositor that does not deliver drags to layer-shell surfaces
breaks both at once. Hyprland does deliver them.

## The card is deliberately not a normal popup

Dragging a file onto the ledge begins with a mouse press inside another window.
The shell's own popup base (`qs.Ui.KeyboardPanel`) claims the whole screen as
its input region and closes on any click outside the card, which would eat that
press before the drag ever starts. `LedgePopup.qml` therefore makes the surface
exactly as big as the card, and the ledge stays open until it is closed on
purpose. Anything that reintroduces a full-screen dismissal overlay breaks
drag-in, no matter how well the `DropArea` works.

## What was awkward

Both directions work on Hyprland with Qt 6.11 / Quickshell 0.3, from and to
layer-shell surfaces. Four things were worth writing down:

**The action a drop reports back is meaningless.** `Drag.onDragFinished` hands
you a `Qt.DropAction`, and here it is `Qt.IgnoreAction` (0) for *every* drag —
including a drop that Nautilus accepted and then moved the file out of. Any
branch on it is dead code, which is how the ledge carried a selection-clear that
never once ran, and a move-cleanup that left chips pointing at files that had
moved. Nothing reads it now; it is logged and ignored. What actually happened is
settled by looking at the files: after a drag out, a carried path that no longer
exists was moved by whoever took it, so its chip goes too (`settleAfterDrag` in
`BarWidget.qml`). The check runs on a short delay, because a same-filesystem
move is a rename that has to land first.

**`startDrag()` needs `Drag.active` first.** Qt refuses to start an automatic
drag on an attached object that is not already marked active, and it *warns*
instead of throwing:

```
QML LedgeChip: startDrag() drag must be active
```

Without the log line next to it this looks exactly like a dead mouse — the
press registers, the threshold is crossed, and nothing happens. So
`LedgeChip.beginDrag()` sets `Drag.active = true`, calls `startDrag()`, and
clears it again afterwards. Marking it active does not itself start anything
when `dragType` is `Drag.Automatic`.

**Nautilus offers more than `text/uri-list`.** A drop from Files carries
`application/x-gtk-local-dnd`, `text/plain`, `text/uri-list`,
`application/vnd.portal.filetransfer` and `application/vnd.portal.files`. Qt
resolves `drop.urls` from the uri-list, which is what the ledge reads; the
portal formats are for sandboxed clients and are ignored here on purpose,
since the ledge only ever stores plain local paths.

**The drag image is the file, not a thumbnail, unless you say so.** Pointing
`Drag.imageSource` at the file url drags a full-size image across the screen.
`Drag.imageSourceSize` bounds it, and each chip additionally grabs its own
thumbnail box (`grabToImage`, on hover, because the grab is asynchronous and
the drag has to start inside the mouse event that triggered it) so that file
types without an image get an icon too.

## Checking it after a change

None of this is reachable from the automated checks, so anything that touches
drag or drop behaviour is worth walking through by hand:

1. **Drag onto the bar icon.** Drag a file from Nautilus onto the ledge's bar
   icon. The icon turns into a download arrow while the drag is over it, and
   the count goes up on drop. This is the one that matters most — it is how the
   plugin is meant to be used.
2. **Drag in — file manager.** Open the ledge, then drag a file from Nautilus
   onto the card. It highlights while hovered and adds a chip on drop.
3. **Drag in — browser.** Drag an image out of Chromium/Firefox onto the ledge.
   Browsers often offer `text/uri-list` pointing at a temporary file, plus
   `text/plain` with the remote URL; remote URLs are ignored on purpose.
4. **Drag in — terminal.** `dragon --and-exit somefile.png`, drag onto the ledge.
5. **Drag in — multiple files.** Select three files, drag them at once; all
   three appear, duplicates are ignored.
6. **Drag out — upload form.** Open any page with `<input type="file">` and drag
   a chip onto it.
7. **Drag out — file manager.** Drag a chip into a Nautilus window.
8. **Drag out — chat app.** Drag a chip into Slack/Signal/Discord.
9. **Drag out with `allowMove` on.** Turn it on behind the gear, then drag a
   chip into a Nautilus window: the original leaves the source folder, and the
   chip leaves the ledge about a second later. With the setting off, the
   original stays and so does the chip.

Every drag that reaches either target logs what the source offered, which is
the difference between "the drop never arrived" and "it arrived in a format we
ignore":

```bash
journalctl --user -t omarchy-shell -f | grep omarchy-ledge
# omarchy-ledge: bar icon: drag entered urls=1 text=no formats=[text/uri-list,...]
# omarchy-ledge: bar icon: dropped urls=1 text=no formats=[text/uri-list,...]
```

Omarchy starts the shell as `systemd-cat -t omarchy-shell -- quickshell -n -p
$OMARCHY_PATH/shell`, so its output lands in the journal under that tag. A bare
`quickshell log` looks for a *default* config directory instead and gives up;
`quickshell -p /usr/share/omarchy/shell log -f` is the equivalent if you would
rather read it from quickshell itself.

Silence in that log while a drag is clearly over the icon means the compositor
is not delivering drags to layer-shell surfaces at all.

## Notes

- `Drag.mimeData` is only used when `dragType` is `Drag.Automatic`; a plain
  `Drag.active` toggle without it does an internal-only drag and will look like
  "nothing happens".
- `preventStealing: true` on the chip's `MouseArea` stops the `ListView` from
  swallowing the press when the ledge has enough files to scroll.
- Wayland requires a real input serial to start a drag, so it must begin from a
  press on the surface — starting a drag from a timer or a keyboard shortcut
  will not work.
- If a drop lands but no chip appears, log `drop.formats` in `onDropped`: the
  source may be offering something other than `text/uri-list`.
