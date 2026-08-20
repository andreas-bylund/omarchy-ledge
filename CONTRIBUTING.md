# Contributing

Thanks for taking a look. Bug reports, ideas and pull requests are all welcome.

## Reporting a bug

Please include:

- your Omarchy version (`omarchy version`) and compositor,
- what you dragged, from which application, and what happened,
- relevant output from `journalctl --user -t omarchy-shell -n 200 | grep omarchy-ledge`.

Drag and drop behaves differently per application, so the source app matters —
mention it even if it seems irrelevant.

## Working on the code

Link your checkout into the plugin directory so the shell hot-reloads on save:

```bash
git clone https://github.com/andreas-bylund/omarchy-ledge.git ~/Projects/omarchy-ledge
ln -s ~/Projects/omarchy-ledge ~/.config/omarchy/plugins/bylund.ledge
```

Before opening a pull request:

```bash
node scripts/validate-plugin.mjs
node scripts/check-qml.mjs
node scripts/test-model.mjs
shellcheck bin/omarchy-ledge
omarchy plugin validate ./        # needs an Omarchy install
```

Anything that changes drag or drop behaviour should also be walked through the
checklist in [docs/drag-and-drop.md](docs/drag-and-drop.md), since none of that
can be covered by the automated checks.

## House style

- Code, comments, commit messages and documentation in English.
- Keep logic that does not need QML in `LedgeModel.js` — it is unit tested.
- Take colours from `LedgeTheme.qml`, never hard-code one: the plugin has to
  look right in every Omarchy theme.
- No new runtime dependencies beyond what Omarchy already ships.
