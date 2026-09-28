# omarchy-plugin-remote-connections

An [Omarchy](https://omarchy.org/) bar widget that keeps your **SSH**, **RDP**
and **VNC** connections in one place and opens any of them with one click.
Passwords live in the GNOME keyring, never in a plain file.

## What it does

- One bar icon; its popup lists your saved connections, grouped (with
  favorites on top), with a filter field (`/`) — Enter connects to the first
  match.
- **Quick connect** from the keyboard: a centered launcher (like the emoji
  picker) where you type part of a name/host and hit Enter. Recently used
  connections come first. See [Keyboard shortcut](#keyboard-shortcut).
- **Hosts from `~/.ssh/config`** show up automatically (including files it
  `Include`s; wildcard entries are skipped). They connect with `ssh <alias>`,
  so all your ssh settings apply. The plugin only reads that file — use
  *Save as connection* on one to give it a group or make it a favorite.
- **Add / edit / delete** connections inline (`n` opens a new one):
  - **SSH**: user, port, identity file, jump host (`-J`). Opens in your
    terminal; if ssh fails, the window stays open so you can read the error.
  - **RDP** (FreeRDP 3): domain, clipboard sharing, all monitors, dynamic
    resolution.
  - **VNC** (TigerVNC): view-only mode.
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

- **SSH server**: starts/stops `sshd` and opens its port in the firewall
  (ufw) either for the **local network** or for **Tailscale only**. Shows the
  `ssh user@address` to use from the other machine, with a copy button.
  **Keys only** turns password logins off — only offered once
  `~/.ssh/authorized_keys` has a key, so you can't lock yourself out.
- **Screen sharing (VNC)** with [wayvnc](https://github.com/any1/wayvnc):
  shares your actual Hyprland session. Choose who can reach it: **this
  computer only** (use an SSH tunnel), **Tailscale**, or the **local
  network**. A password is always required, and the connection is encrypted
  (RSA-AES or TLS, whichever the viewer supports).
- While someone is viewing your screen, the bar icon turns red and its
  tooltip says from where; one click disconnects every viewer.
- Everything that needs root is confirmed in the popup first, telling you it
  will ask for your admin password.

## Install

```bash
omarchy plugin add https://github.com/vinicgobbi/omarchy-plugin-remote-connections
omarchy plugin enable vinicgobbi.remote-connections
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
| First RDP or VNC connection | The row shows *Needs the 'freerdp' package* (or `tigervnc`); clicking install opens a terminal that asks for your **sudo** password | The plugin doesn't install anything without you seeing it |
| Saving an RDP/VNC password | The GNOME keyring may ask you to **unlock** it | The password is stored in the keyring, not in `connections.json` |
| Keyring locked when connecting | A notification says so, and the RDP/VNC client asks for the password itself | Nothing is stored anywhere else as a fallback |
| First SSH connection to a host | The terminal asks you to confirm the host's **fingerprint** (`yes`) | Protection against man-in-the-middle; the plugin never turns it off |
| First RDP connection to a host | The server certificate is trusted on first use (`/cert:tofu`); if it **changes** later, the connection is refused | Same idea as SSH host keys |
| Turning the SSH server on/off, *Keys only*, or screen sharing beyond this computer | The popup asks you to confirm, then the **polkit dialog asks for your admin password** (once per action) | Starting `sshd`, editing its config and changing firewall rules need root |
| Turning on *Keys only* | Needs at least one key in `~/.ssh/authorized_keys` first (run `ssh-copy-id you@this-machine` from the other computer) | Otherwise you'd lock yourself out |
| First screen sharing | Install `wayvnc` (terminal asks for **sudo**) and choose a **password** viewers must type | wayvnc always runs with authentication on |
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
| SSH *Keys only* setting | `/etc/ssh/sshd_config.d/90-omarchy-remote-connections.conf` (delete it to undo by hand) |
| Firewall rules | ufw rules commented `omarchy-remote-connections ssh`/`vnc`; the plugin only ever removes rules with that comment |
| Last client output (for troubleshooting) | `~/.local/state/omarchy-remote-connections/last-<protocol>.log` |

If `connections.json` has a syntax error, the plugin shows it and refuses to
save, so your file is never overwritten.

## Roadmap

- Discover hosts on the local network (mDNS) and import `.remmina`/`.rdp`
  files.
- RDP access to this machine (experimental; a separate session via xrdp,
  since no RDP server can share a Hyprland session).

## License

MIT
