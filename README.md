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
  (ufw) either for the **local network** or for **Tailscale only**. Shows the
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

Anything that needs `sudo` — installing a client, turning the SSH server
on/off, *Keys only*, opening/closing a firewall port — opens an **Omarchy
floating terminal** that:

1. lists every step with the **exact command** it will run (the text you see
   is what executes — no hidden helper runs as root);
2. warns that these commands change your system and that you should **only
   run them if you know what they do**;
3. says what will be true **after** it runs and **how to undo** it;
4. lets you **run all steps**, **confirm each step** (and skip any), or
   **cancel** without changing anything.

`sudo` asks for your password in that terminal. Several changes at once
(e.g. *Install missing clients* installs every client your saved
connections need) show up as one list.

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
| First RDP or VNC connection | The row shows *Needs the 'freerdp' package* (or `tigervnc`); install opens the [command terminal](#how-system-changes-are-made) with the `omarchy pkg add` command, and **sudo** asks for your password | The plugin doesn't install anything without you seeing it |
| Saving an RDP/VNC password | The GNOME keyring may ask you to **unlock** it | The password is stored in the keyring, not in `connections.json` |
| Keyring locked when connecting | A notification says so, and the RDP/VNC client asks for the password itself | Nothing is stored anywhere else as a fallback |
| First SSH connection to a host | The terminal asks you to confirm the host's **fingerprint** (`yes`) | Protection against man-in-the-middle; the plugin never turns it off |
| First RDP connection to a host | The server certificate is trusted on first use (`/cert:tofu`); if it **changes** later, the connection is refused | Same idea as SSH host keys |
| Turning the SSH server on/off, *Keys only*, or screen sharing beyond this computer | You pick the options in the popup, then the [command terminal](#how-system-changes-are-made) shows the exact commands; you choose to run them all, one by one, or cancel, and **sudo** asks for your password | Starting `sshd`, editing its config and changing firewall rules need root |
| Turning on *Keys only* | Needs at least one key in `~/.ssh/authorized_keys` first (run `ssh-copy-id you@this-machine` from the other computer) | Otherwise you'd lock yourself out |
| First screen sharing | Install `wayvnc` (through the command terminal) and choose a **password** viewers must type | wayvnc always runs with authentication on |
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
