# omarchy-plugin-remote-connections

An [Omarchy](https://omarchy.org/) bar widget that keeps your **SSH**, **RDP**
and **VNC** connections in one place and opens any of them with one click.
Passwords live in the GNOME keyring, never in a plain file.

## What it does

- **One place for every connection.** The bar icon's popup lists them in
  sections — *Recent*, *Favorites*, your groups, and hosts from
  `~/.ssh/config` — with search (`/`) and SSH/RDP/VNC filters. Each row shows
  whether the server answers (a quick TCP check of its port) and when you
  last used it.
- **One click to connect.** The row under the mouse (or picked with `↑`/`↓`)
  shows **Connect**; `⋯` (or right-click) has Edit, Favorite, Copy address,
  Duplicate, *Log in with a key* and Delete. Keys: `↵` connect, `e` edit,
  `f` favorite, `c` copy, `x` delete, `n` new.
- **Quick connect** from the keyboard: a centered launcher (like the emoji
  picker) where you type part of a name/host and hit Enter. Recently used
  connections come first. See [Keyboard shortcut](#keyboard-shortcut).
- **Hosts from `~/.ssh/config`** show up automatically (including files it
  `Include`s; wildcard entries are skipped). They connect with `ssh <alias>`,
  so all your ssh settings apply. The plugin only reads that file — use
  *Save as connection* on one to give it a group or make it a favorite.
- **New / edit connection** form: labeled fields, a **Test** button that
  checks the port answers (and shows the server's greeting, e.g. its SSH
  version), groups as chips, advanced options folded away:
  - **SSH**: pick one of your keys (or automatic), jump host (`-J`), and
    *Create a key and copy it to this server* (ssh-keygen + ssh-copy-id, in a
    terminal since it asks the server's password). Opens in your terminal; if
    ssh fails, the window stays open so you can read the error.
  - **RDP** (FreeRDP 3): domain, clipboard sharing, all monitors, dynamic
    resolution, connection bar, keyboard shortcuts.
  - **VNC** (TigerVNC): view-only mode.
- **Passwords** for RDP/VNC can be saved in the GNOME keyring. No saved
  password? Connect asks for it right in the row (or in Quick connect), with
  *Remember in keyring* — untick it to use the password once. Either way it
  reaches the client without ever showing up in the process list: FreeRDP
  reads its arguments from stdin, TigerVNC reads `VNC_PASSWORD` from its own
  environment.
- **Open sessions** show at the top of the list while an RDP or VNC window is
  open, with **Show** (bring it to the front) and **Disconnect** — a way out
  even when the remote window holds the keyboard.
- **RDP connection bar:** RDP opens with a Windows-style bar at the top of
  the window (minimize, pin, close), drawn by `xfreerdp3` through XWayland.
  Turn off *Connection bar* in a connection's Advanced options to use the
  native Wayland client (`sdl-freerdp3`) instead; there, **Right Shift + D**
  disconnects, **Right Shift + Enter** toggles fullscreen and
  **Right Shift + G** grabs/frees the keyboard. With fractional monitor
  scaling, XWayland may look slightly soft — that's when the native client
  is the better pick.
- **Getting out of a remote window:** when it opens, a notification says how
  to leave it. TigerVNC: **F8** opens its menu (Exit viewer, fullscreen). By
  default RDP windows **don't** grab the keyboard, so Omarchy shortcuts
  (Super+W, workspaces…) keep working; turn on *Send Omarchy shortcuts to the
  remote computer* in a connection's Advanced options to send them to Windows
  instead.
- Clients run in their own systemd unit (`uwsm-app`), so restarting the
  Omarchy shell doesn't drop an open session.

### Setup: the clients the plugin uses

The **gear** in the popup's header lists what the plugin needs — the
password keyring, the SSH client, the RDP and VNC clients — what each one is
for (and how many of your connections use it), and whether it's installed.
Install or remove one, or tick several and **Install all missing** at once.
The gear shows a number when a client one of your connections needs is
missing; on a fresh install, the first screen has an *Install what you need*
card that opens it.

### How installs are made

Installing or removing a client opens a **review sheet** in the middle of the
screen (where Omarchy's password dialog appears):

1. **what changes** and **how to undo it**, in plain words;
2. the **exact command** that will run (`omarchy pkg add …` / `omarchy pkg
   drop …`), always visible;
3. a warning to **only apply it if you understand what it does**;
4. **Authorize & apply**: Omarchy's own password dialog asks once and the
   command runs exactly as shown, in one `pkexec` (no helper script of the
   plugin runs as root), with live progress and output;
5. if it fails: its output, **Undo what ran**, **Retry** or **Try in
   terminal**.

Prefer to type it yourself? **Run in terminal instead** opens an Omarchy
terminal with the same command (run with `sudo`), and **Copy commands** puts
it on the clipboard.

## Install

```bash
omarchy plugin add https://github.com/vinicgobbi/omarchy-plugin-remote-connections
omarchy plugin enable vinicgobbi.remote-connections
```

After installing or **updating** the plugin, run `omarchy restart shell`:
the shell's automatic reload keeps running the previous version of the code
until it restarts.

### Used an earlier version's *This machine* tab?

Earlier versions could also let other computers reach this one (SSH server,
screen sharing). That's gone; anything you turned on there stays as it was.
To undo it by hand:

```bash
sudo systemctl disable --now sshd.service                                    # SSH server
sudo rm -f /etc/ssh/sshd_config.d/05-omarchy-remote-connections.conf \
           /etc/ssh/sshd_config.d/90-omarchy-remote-connections.conf         # "Require keys"
systemctl --user stop omarchy-remote-wayvnc.service                          # screen sharing
sudo ufw status numbered | grep omarchy-remote-connections                   # its firewall rules;
sudo ufw delete <number>                                                     #   delete each, highest number first
```

## Keyboard shortcut

The plugin doesn't touch your Hyprland config, so add the shortcut yourself
in `~/.config/hypr/bindings.lua` (`SUPER + ALT + R` is free in a default
Omarchy install):

```lua
o.bind("SUPER + ALT + R", "Remote connections", "omarchy-shell shell toggle vinicgobbi.remote-connections")
```

In the launcher: type to filter, `↑`/`↓` (or `Tab`, `Ctrl+J`/`Ctrl+K`) to
move, `Enter` to connect, `Esc` to clear the filter or close.

Optionally, add it to the Omarchy menu too, in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"remote": {"icon":"󰒍","label":"Remote","action":"omarchy-shell shell toggle vinicgobbi.remote-connections"},
```

## What this plugin will ask of you

Some steps need you to confirm something or type a password — the plugin
never does them silently. Here's what to expect:

| When | What happens | Why |
|---|---|---|
| First RDP or VNC connection | The row shows *Needs freerdp* (or `tigervnc`); installing it (or Setup) opens the [review sheet](#how-installs-are-made) with the `omarchy pkg add` command, and Omarchy's password dialog asks once | The plugin doesn't install anything without you seeing it |
| Connecting to RDP with no saved password | The row asks for the user and password, with *Remember in keyring* | FreeRDP's connection-bar client can't ask for it itself |
| Saving a password | The GNOME keyring may ask you to **unlock** it | Passwords live in the keyring, not in `connections.json` |
| Keyring locked when connecting | A notification says so, and the client asks for the password (or the row does) | Nothing is stored anywhere else as a fallback |
| First SSH connection to a host | The terminal asks you to confirm the host's **fingerprint** (`yes`) | Protection against man-in-the-middle; the plugin never turns it off |
| First RDP connection to a host | The server certificate is trusted on first use (`/cert:tofu`); if it **changes** later, the connection is refused | Same idea as SSH host keys |
| *Log in with a key* | A terminal runs `ssh-keygen` (only if you have no key) and `ssh-copy-id`, which asks the **server's password** once | Copying your key needs one password login |
| Quick-connect shortcut | You add the keybinding line yourself (see [Keyboard shortcut](#keyboard-shortcut)) | The plugin doesn't edit your Hyprland config |
| SSH login | SSH passwords aren't stored. Set up a key with *Log in with a key* (or `ssh-keygen` + `ssh-copy-id user@host`) | Keys are safer, and ssh-agent handles them for you |

## Where things are stored

| What | Where |
|---|---|
| Connections | `~/.config/omarchy/remote-connections/connections.json` (no passwords) |
| `~/.ssh/config` hosts | Read from `~/.ssh/config` every time the popup/launcher opens; never written |
| RDP/VNC passwords | GNOME keyring, under *Remote connection: &lt;name&gt;* (`service=omarchy-remote-connections`); a password used once waits there under a one-time id and is deleted as soon as the client gets it |
| Last client output (for troubleshooting) | `~/.local/state/omarchy-remote-connections/last-<protocol>.log` |

If `connections.json` has a syntax error, the plugin shows it and refuses to
save, so your file is never overwritten.

## Security

- **No hidden root.** Nothing of the plugin runs as root; the only privileged
  command is the install/remove the review sheet shows you, run exactly as
  shown in one `pkexec`. In the terminal path, text is stripped of terminal
  control codes and a step whose command contains any is refused, so the
  screen can't be made to show something other than what runs.
- **Connections are validated before any client starts**, also when
  `connections.json` was edited by hand or came from someone else: hosts
  can't start with `-` or contain `=`/spaces (TigerVNC reads `Name=value`
  arguments as settings), and no field may contain line breaks (FreeRDP reads
  its arguments one per line).
- **Passwords** stay in the GNOME keyring and never reach a command line.
  TigerVNC gets the VNC password through its environment, which only your
  user (and root) can read while it runs.
- **No stuck windows.** If FreeRDP still asks for something on a terminal it
  doesn't have (e.g. a domain the server requires), the plugin stops it and
  tells you what to change instead of leaving it hanging.
- **Your data** (`~/.config/omarchy/remote-connections/`, logs and session
  records) is created readable only by you.

Known limits:

- **First contact is trust-on-first-use.** RDP accepts the server
  certificate the first time (`/cert:tofu`) and refuses it if it changes
  later; SSH asks you to confirm the host key. A man-in-the-middle on that very
  first connection can't be detected by either.
- **Old VNC servers may not encrypt.** TigerVNC uses encryption when the
  server offers it; legacy servers (plain VNC password) send the screen and a
  weakly protected password in the clear. Prefer SSH tunnels or a VPN for
  those.
- **Reachability checks** open a TCP connection to each saved server (and
  resolve its name) when the popup opens and every 30 s while it stays open.

## Roadmap

- Discover hosts on the local network (mDNS) and import `.remmina`/`.rdp`
  files.

## License

MIT
