# omarchy-plugin-remote-connections

An [Omarchy](https://omarchy.org/) bar widget that keeps your **SSH**, **RDP**
and **VNC** connections in one place and opens any of them with one click.
Passwords live in the GNOME keyring, never in a plain file.

## What it does

- One bar icon with two tabs: **Connect** (reach other machines) and **This
  machine** (let others reach this one). A dot on the icon means this
  computer accepts remote access; it turns into a red eye while someone is
  viewing your screen.
- **Connect** tab: search (`/`) and filter by SSH/RDP/VNC; connections in
  sections — *Recent*, *Favorites*, your groups, and hosts from
  `~/.ssh/config`. Each row shows whether the server answers (a quick TCP
  check of its port) and when you last used it. The selected row (hover or
  `↑`/`↓`) shows **Connect**; `⋯` (or right-click) has Edit, Favorite, Copy
  address, Duplicate, *Log in with a key* and Delete. Keys: `↵` connect,
  `e` edit, `f` favorite, `c` copy, `x` delete, `n` new, `←`/`→` switch tabs.
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
    *Create a key and copy it to this server* (ssh-keygen + ssh-copy-id in the
    command terminal). Opens in your terminal; if ssh fails, the window stays
    open so you can read the error.
  - **RDP** (FreeRDP 3): domain, clipboard sharing, all monitors, dynamic
    resolution.
  - **VNC** (TigerVNC): view-only mode.
- **Active sessions** show at the top of the Connect tab while an RDP or VNC
  window is open, with **Show** (bring it to the front) and **Disconnect** —
  a way out even when the remote window holds the keyboard.
- **RDP connection bar:** RDP opens with a Windows-style bar at the top of
  the window (minimize, pin, close), drawn by `xfreerdp3` through XWayland.
  Turn off *Connection bar* in a connection's Advanced options to use the
  native Wayland client (`sdl-freerdp3`) instead; there, **Right Shift + D**
  disconnects, **Right Shift + Enter** toggles fullscreen and
  **Right Shift + G** grabs/frees the keyboard. With fractional monitor
  scaling, XWayland may look slightly soft — that's when the native client
  is the better pick.
- **Getting out of a remote window:** when it opens, a notification lists
  how to leave it. TigerVNC (VNC): **F8** opens its menu (Exit viewer,
  fullscreen). By default RDP windows **don't** grab the keyboard, so Omarchy
  shortcuts (Super+W, workspaces…) keep working; turn on *Send Omarchy
  shortcuts to the remote computer* in a connection's Advanced options to
  send them to Windows instead.
- **Passwords for RDP/VNC** are stored in the GNOME keyring (via
  `secret-tool`) and handed to the client without ever showing up in the
  process list: FreeRDP reads its arguments from stdin, TigerVNC reads
  `VNC_PASSWORD` from its own environment.
- Missing client? The row says which package it needs and offers to install
  it.
- Clients run in their own systemd unit (`uwsm-app`), so restarting the
  Omarchy shell doesn't drop an open session.

### Remote access to this machine

The *This machine* section of the popup turns remote access **to this
computer** on and off:

- A one-line summary of who can reach this computer right now.
- **SSH server**: starts/stops `sshd` and opens its port in the firewall
  (ufw) either for the **local network** — private address ranges only
  (10/8, 172.16/12, 192.168/16, IPv6 link-local and ULA), never the
  internet, even if your connection has a public IPv6 address — or for
  **Tailscale only**. Shows the
  `ssh user@address` to use from the other machine, with a copy button, and a
  security checklist (firewall, password logins). **Add a key** shows the
  `ssh-copy-id` to run from the other computer, or lets you paste its public
  key. **Require keys** turns password logins off — only offered once
  `~/.ssh/authorized_keys` has a key, so you can't lock yourself out.
- **Screen sharing (VNC)** with [wayvnc](https://github.com/any1/wayvnc):
  shares your actual Hyprland session. Choose who can reach it: **this
  computer only** (use an SSH tunnel), **Tailscale**, or the **local
  network**. A password is always required, and the connection is encrypted
  (RSA-AES or TLS, whichever the viewer supports). Choose whether viewers
  can control mouse and keyboard or only watch.
- While someone is viewing your screen, an alert tops the tab and the bar
  icon turns red; you can disconnect one viewer or all of them.
- Nothing that needs root runs behind your back: see
  [How system changes are made](#how-system-changes-are-made).

### How system changes are made

Anything that needs administrator rights — installing or removing a
package, turning the SSH server on/off, *Require keys*, opening/closing a
firewall port — opens a **review sheet** in the middle of the screen (where
Omarchy's password dialog appears):

1. **What changes** and **how to undo it**, in plain words;
2. the **exact commands** that will run, always visible — untick a step to
   leave it out;
3. a warning to **only apply them if you understand what they do**;
4. **Authorize & apply**: Omarchy's own password dialog asks once, and every
   ticked command runs exactly as shown, in one `pkexec` (no helper script of
   the plugin runs as root). Each step shows its progress and output live;
   you can hide the sheet and get a notification when it's done;
5. if a step fails: its output, **Undo what ran**, **Retry** or **Try in
   terminal**.

Prefer to type it yourself? **Run in terminal instead** opens an Omarchy
terminal with the same commands (run with `sudo`), and **Copy commands**
puts them on the clipboard. Steps that need a terminal anyway — creating an
SSH key, `ssh-copy-id` (which asks the server's password) — open there
directly.

### Setup

The **gear** in the popup's header lists everything the plugin uses —
the password keyring, the SSH/RDP/VNC clients, the screen-sharing server,
the firewall, Tailscale — what each one is for, and whether it's
installed. Install or remove one item, or tick several and **Install all
missing** at once (one review, one password). The gear shows a number when
something you need (e.g. the client for a saved connection) is missing.

## Install

```bash
omarchy plugin add https://github.com/vinicgobbi/omarchy-plugin-remote-connections
omarchy plugin enable vinicgobbi.remote-connections
```

After installing or **updating** the plugin, run `omarchy restart shell`:
the shell's automatic reload keeps running the previous version of the code
until it restarts.

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
| First RDP or VNC connection | The row shows *Needs the 'freerdp' package* (or `tigervnc`); install (or the Setup gear) opens the [review sheet](#how-system-changes-are-made) with the `omarchy pkg add` command, and Omarchy's password dialog asks once | The plugin doesn't install anything without you seeing it |
| Saving an RDP/VNC password | The GNOME keyring may ask you to **unlock** it | The password is stored in the keyring, not in `connections.json` |
| Keyring locked when connecting | A notification says so, and the RDP/VNC client asks for the password itself | Nothing is stored anywhere else as a fallback |
| First SSH connection to a host | The terminal asks you to confirm the host's **fingerprint** (`yes`) | Protection against man-in-the-middle; the plugin never turns it off |
| First RDP connection to a host | The server certificate is trusted on first use (`/cert:tofu`); if it **changes** later, the connection is refused | Same idea as SSH host keys |
| Turning the SSH server on/off, *Keys only*, or screen sharing beyond this computer | You pick the options in the popup, then the [review sheet](#how-system-changes-are-made) shows the exact commands; you apply them (untick any you don't want) and Omarchy's **password dialog** asks once | Starting `sshd`, editing its config and changing firewall rules need root |
| Turning on *Keys only* | Needs at least one key in `~/.ssh/authorized_keys` first (run `ssh-copy-id you@this-machine` from the other computer) | Otherwise you'd lock yourself out |
| First screen sharing | Install `wayvnc` (through the review sheet) and choose a **password** viewers must type | wayvnc always runs with authentication on |
| Someone views your screen | The bar icon turns **red**; nothing hides it | You should always know when your screen is being watched |
| Quick-connect shortcut | You add the keybinding line yourself (see [Keyboard shortcut](#keyboard-shortcut)) | The plugin doesn't edit your Hyprland config |
| SSH login | SSH passwords aren't stored. Set up a key: `ssh-keygen`, then `ssh-copy-id user@host` | Keys are safer, and ssh-agent handles them for you |

## Where things are stored

| What | Where |
|---|---|
| Connections | `~/.config/omarchy/remote-connections/connections.json` (no passwords) |
| `~/.ssh/config` hosts | Read from `~/.ssh/config` every time the popup/launcher opens; never written |
| RDP/VNC passwords | GNOME keyring, under *Remote connection: &lt;name&gt;* (`service=omarchy-remote-connections`) |
| Screen-sharing password | GNOME keyring (*Screen sharing (this machine)*); written to a temporary 0600 file in `$XDG_RUNTIME_DIR` only while wayvnc starts, then deleted |
| Screen-sharing keys (RSA/TLS) | `~/.local/state/omarchy-remote-connections/wayvnc/` |
| Sharing preferences (scope, port) | `~/.config/omarchy/remote-connections/host.json` |
| SSH *Require keys* setting | `/etc/ssh/sshd_config.d/05-omarchy-remote-connections.conf` (read before other drop-ins so nothing turns passwords back on; delete it to undo by hand) |
| Firewall rules | ufw rules commented `omarchy-remote-connections ssh`/`vnc`; the plugin only ever removes rules with that comment |
| Last client output (for troubleshooting) | `~/.local/state/omarchy-remote-connections/last-<protocol>.log` |

If `connections.json` has a syntax error, the plugin shows it and refuses to
save, so your file is never overwritten.

## Security

What the plugin does to stay safe, and what it can't do for you:

- **No hidden root.** Nothing of the plugin runs as root; the only
  privileged commands are the ones the review sheet shows you, run exactly
  as shown in one `pkexec`. In the terminal path, text is stripped of
  terminal control codes and a step whose command contains any is refused,
  so the screen can't be made to show something other than what runs.
- **Firewall scopes mean what they say.** *Local network* opens the port to
  private ranges only; *Tailscale only* to the `tailscale0` interface. The
  plugin only ever removes firewall rules carrying its own comment. If an
  older version left a rule open to every source, the *This machine* tab
  flags it. With ufw **off**, everything you turn on is reachable from every
  network — the tab says so.
- **Require keys is verified, not assumed.** The tab shows what sshd will
  really use (the first `PasswordAuthentication` it reads), and the terminal
  prints `sshd -T`'s answer after the change.
- **Connections are validated before any client starts**, also when
  `connections.json` was edited by hand or came from someone else: hosts
  can't start with `-` or contain `=`/spaces (TigerVNC reads `Name=value`
  arguments as settings), and no field may contain line breaks (FreeRDP reads
  its arguments one per line).
- **Passwords** stay in the GNOME keyring and never reach a command line.
  TigerVNC gets the VNC password through its environment, which only your
  user (and root) can read while it runs.
- **Screen sharing** always requires a password and encrypts the session; the
  password is on disk only for the instant wayvnc starts (tmpfs, mode 600).
- **Your data** (`~/.config/omarchy/remote-connections/`, logs and session
  records) is created readable only by you.

Known limits:

- **First contact is trust-on-first-use.** RDP accepts the server
  certificate the first time (`/cert:tofu`) and refuses it if it changes
  later; SSH asks you to confirm the host key. A man-in-the-middle on that very
  first connection can't be detected by either.
- **Old VNC servers may not encrypt.** TigerVNC uses encryption when the
  server offers it; legacy servers (plain VNC password) send the screen and a
  weakly protected password in the clear. Prefer SSH tunnels or Tailscale
  for those.
- **Reachability checks** open a TCP connection to each saved server (and
  resolve its name) when the popup opens and every 30 s while it stays open.

## Roadmap

- Discover hosts on the local network (mDNS) and import `.remmina`/`.rdp`
  files.
- RDP access to this machine (experimental; a separate session via xrdp,
  since no RDP server can share a Hyprland session).

## License

MIT
