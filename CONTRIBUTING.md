# Contributing

## Local setup

`omarchy plugin validate .` rejects a plugin folder that contains a
symlink, so a plain `ln -s` of this repo into
`~/.config/omarchy/plugins/` won't load. Clone it there instead
(a real, separate working copy — like `omarchy plugin add` would
leave):

```bash
git clone "$(pwd)" ~/.config/omarchy/plugins/vinicgobbi.remote-connections
omarchy plugin enable vinicgobbi.remote-connections
```

To pick up local edits without re-cloning, add this repo as a remote
in the installed copy and pull:

```bash
git -C ~/.config/omarchy/plugins/vinicgobbi.remote-connections remote add dev "$(pwd)"
git -C ~/.config/omarchy/plugins/vinicgobbi.remote-connections pull dev main
```

`BarWidget.qml` (the plugin's entry point, `ConnectionStore.qml` included)
hot-reloads on its own once the installed copy is updated.

**Adding a new `.qml` file** (or a new entry point) needs a full shell
restart: `omarchy restart shell`. The hot reload doesn't clear Qt's cached
directory listing of the plugin folder, so a file that didn't exist the first
time the folder was loaded fails with a misleading
`QuickConnect.qml: File name case mismatch` in `qs log -p $OMARCHY_PATH/shell`.
Edits to files that already existed reload fine.

Validate the manifest before publishing:

```bash
omarchy plugin validate .
```

## Structure

- `manifest.json` — plugin metadata: kinds `bar-widget` + `overlay`,
  `keepLoaded` so the launcher opens with the list already loaded
- `BarWidget.qml` — the bar icon and popup: filter, grouped connection
  list (favorite/edit/delete/connect), the inline add/edit form, and the
  install prompt when a protocol's client is missing
- `QuickConnect.qml` — the keyboard launcher (overlay), modeled on the
  built-in emoji picker; summoned with
  `omarchy-shell shell toggle vinicgobbi.remote-connections`
- `ConnectionStore.qml` — loads/saves
  `~/.config/omarchy/remote-connections/connections.json` (never
  overwriting a file that failed to parse), checks which clients are
  installed, reads `~/.ssh/config` hosts, launches connections and queues
  keyring operations. The bar widget and the launcher each have their own
  instance; they stay in sync through the file (watched for changes)
- `Model.js` — pure helpers (normalize, validate, sort, filter, the JSON
  handed to `rc-connect`); no QML types, so it can be tested with `node`
- `bin/rc-connect` — opens one connection: ssh in a terminal, FreeRDP with
  its arguments on stdin, TigerVNC with the password in its environment
- `bin/rc-ssh-hosts` — lists concrete `Host` aliases from `~/.ssh/config`
  and its `Include`s (read-only)
- `bin/rc-secret` — set/get/clear a password in the GNOME keyring via
  `secret-tool` (password on stdin, never argv)

## CI

`.github/workflows/ci.yml` runs on every push to `main` (and on pull
requests): it validates `manifest.json`, runs Shellcheck on any shell
scripts, and lints every `.qml` file with `qmllint`, so a syntax error
can't land on `main`.

## Commits and releases

Commits follow [Conventional Commits](https://www.conventionalcommits.org/)
and are checked with [Commitizen](https://commitizen-tools.github.io/commitizen/):

```bash
pipx install commitizen
cz commit   # interactive, conventional-commits-compliant commit
```

Releases are manual: run `.github/workflows/release.yml` from the
Actions tab (`Run workflow`, on `main`). It only runs when dispatched
against `main`, and uses Commitizen to bump `manifest.json`'s version
and the changelog based on the commit types since the last release,
tags it (`vX.Y.Z`), and publishes a GitHub Release with the changelog
entry. If there's nothing to bump (no `feat`/`fix`/`BREAKING CHANGE`
commits since the last release), it's a no-op — no tag, no release.
