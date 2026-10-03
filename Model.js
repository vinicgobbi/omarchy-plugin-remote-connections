// Pure helpers for the saved-connection list. No QML/Quickshell types in
// here so every function stays testable with plain `node`/`qjs`.

var PROTOCOLS = ["ssh", "rdp", "vnc"]

var PROTOCOL_LABELS = { ssh: "SSH", rdp: "RDP", vnc: "VNC" }

var DEFAULT_PORTS = { ssh: 22, rdp: 3389, vnc: 5900 }

// The client each protocol needs, and the Arch package that ships it (any
// of the binaries will do; for RDP, bin/rc-connect picks xfreerdp3 or
// sdl-freerdp3 depending on the connection-bar option).
var CLIENTS = {
  ssh: { binaries: ["ssh"], pkg: "openssh" },
  rdp: { binaries: ["sdl-freerdp3", "xfreerdp3"], pkg: "freerdp" },
  vnc: { binaries: ["vncviewer"], pkg: "tigervnc" }
}

function defaultPort(protocol) {
  return DEFAULT_PORTS[protocol] || 0
}

function protocolLabel(protocol) {
  return PROTOCOL_LABELS[protocol] || String(protocol || "").toUpperCase()
}

function newId() {
  // RFC 4122 v4 shape; Math.random is fine here, the id only has to be
  // unique within one user's list (it's also the keyring lookup key).
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c) {
    var r = Math.random() * 16 | 0
    return (c === "x" ? r : (r & 0x3 | 0x8)).toString(16)
  })
}

// Same rule as bin/rc-connect: no leading "-" (read as an option), no "="
// (TigerVNC reads "Name=value" arguments as settings), no spaces/quotes.
var HOST_RE = /^[A-Za-z0-9_][A-Za-z0-9._:-]*$/

// Strips every control character (line breaks would add arguments to
// FreeRDP's one-per-line input; escape codes could garble a terminal).
function clean(value) {
  return String(value === undefined || value === null ? "" : value).replace(/[\u0000-\u001f\u007f]/g, " ").trim()
}

// For text shown by Text items that may interpret rich text (section
// headers): no markup.
function plainLabel(value) {
  return clean(value).replace(/[<>&]/g, "")
}

function toPort(value, protocol) {
  var n = parseInt(String(value), 10)
  return (isFinite(n) && n > 0 && n < 65536) ? n : defaultPort(protocol)
}

function normalize(raw) {
  var c = raw && typeof raw === "object" ? raw : {}
  var protocol = PROTOCOLS.indexOf(c.protocol) >= 0 ? c.protocol : "ssh"
  var rdp = c.rdp && typeof c.rdp === "object" ? c.rdp : {}
  var vnc = c.vnc && typeof c.vnc === "object" ? c.vnc : {}
  var host = clean(c.host)
  return {
    id: clean(c.id) || newId(),
    name: clean(c.name) || host,
    protocol: protocol,
    host: host,
    port: toPort(c.port, protocol),
    user: clean(c.user),
    group: folderPath(c.group),
    favorite: c.favorite === true,
    lastUsed: typeof c.lastUsed === "number" && isFinite(c.lastUsed) ? c.lastUsed : 0,
    hasSecret: c.hasSecret === true,
    identityFile: clean(c.identityFile),
    jumpHost: clean(c.jumpHost),
    rdp: {
      domain: clean(rdp.domain),
      multimon: rdp.multimon === true,
      clipboard: rdp.clipboard !== false,
      // Send Omarchy's shortcuts (Super…) to the remote instead of Hyprland.
      grabKeyboard: rdp.grabKeyboard === true,
      // Windows-style connection bar (minimize/pin/close). Only xfreerdp3
      // (X11, through XWayland) draws it; off uses the native sdl-freerdp3.
      connectionBar: rdp.connectionBar !== false
    },
    vnc: {
      viewOnly: vnc.viewOnly === true
    }
  }
}

function parseList(text) {
  var data
  try {
    data = JSON.parse(String(text || "").trim() || "{}")
  } catch (e) {
    return { ok: false, connections: [], folders: [], error: "connections.json is not valid JSON: " + e.message }
  }
  var list = Array.isArray(data) ? data : (data && Array.isArray(data.connections) ? data.connections : [])
  var seen = {}
  var out = []
  for (var i = 0; i < list.length; i++) {
    var c = normalize(list[i])
    if (c.host === "" || seen[c.id]) continue
    seen[c.id] = true
    out.push(c)
  }
  var folders = data && Array.isArray(data.folders) ? normalizeFolders(data.folders) : []
  return { ok: true, connections: out, folders: folders, error: "" }
}

function serialize(connections, folders) {
  return JSON.stringify({ version: 1, folders: folders || [], connections: connections || [] }, null, 2) + "\n"
}

// Returns "" when the draft is acceptable, otherwise a message for the form.
function validate(draft) {
  var d = draft || {}
  var host = clean(d.host)
  if (host === "") return "Host is required."
  if (!HOST_RE.test(host)) return "Host can only use letters, digits and . _ : - (no spaces, no \"=\", not starting with -)."
  if (/^-/.test(clean(d.user)) || /^-/.test(clean(d.jumpHost)))
    return "User and jump host can't start with '-'."
  if (d.protocol === "ssh" && clean(d.user) !== "" && !/^[A-Za-z0-9._][A-Za-z0-9._@-]*$/.test(clean(d.user)))
    return "SSH user can only use letters, digits and . _ @ -."
  var jump = clean(d.jumpHost)
  if (jump !== "" && !/^([A-Za-z0-9._-]+@)?[A-Za-z0-9_][A-Za-z0-9._-]*(:[0-9]+)?(,([A-Za-z0-9._-]+@)?[A-Za-z0-9_][A-Za-z0-9._-]*(:[0-9]+)?)*$/.test(jump))
    return "Jump host should look like user@host or user@host:port."
  var portText = clean(d.port)
  if (portText !== "") {
    var n = parseInt(portText, 10)
    if (!/^\d+$/.test(portText) || n < 1 || n > 65535) return "Port must be between 1 and 65535."
  }
  if (PROTOCOLS.indexOf(d.protocol) < 0) return "Unknown protocol."
  return ""
}

// --- Folders ---
// A connection's `group` is the path of the folder it lives in, one segment
// per level: "Work/Servers" is the folder Servers inside Work, "" the top
// level. A folder exists while something lives in it, or while it's listed
// in connections.json's "folders" (that's how an empty one survives).

// "  Work / Servers/ " -> "Work/Servers"; control characters and empty
// segments go away, so a path never starts or ends with "/".
function folderPath(value) {
  return clean(value).split("/")
    .map(function(s) { return s.trim() })
    .filter(function(s) { return s !== "" })
    .join("/")
}

function parentFolder(path) {
  var i = path.lastIndexOf("/")
  return i < 0 ? "" : path.slice(0, i)
}

function folderName(path) {
  return path.slice(path.lastIndexOf("/") + 1)
}

// "Work/Servers" -> "Work › Servers", for display.
function folderLabel(path) {
  return path === "" ? "" : path.split("/").join(" › ")
}

// True for the folder itself and everything below it ("" holds everything).
function isInside(path, folder) {
  return folder === "" || path === folder || path.indexOf(folder + "/") === 0
}

function byName(a, b) {
  var na = a.toLowerCase(), nb = b.toLowerCase()
  return na < nb ? -1 : (na > nb ? 1 : 0)
}

// Unique, normalized, sorted paths, each with all its parents.
function normalizeFolders(list) {
  var seen = {}
  var out = []
  for (var i = 0; i < (list || []).length; i++) {
    var p = folderPath(list[i])
    while (p !== "" && !seen[p]) {
      seen[p] = true
      out.push(p)
      p = parentFolder(p)
    }
  }
  return out.sort(byName)
}

// Every folder: the saved ones plus where connections live.
function allFolders(connections, folders) {
  var paths = (folders || []).slice()
  for (var i = 0; i < (connections || []).length; i++)
    if (connections[i].group !== "") paths.push(connections[i].group)
  return normalizeFolders(paths)
}

// The folders directly inside `parent`, with what's in each (counting
// subfolders) and which protocols show up there.
function childFolders(connections, folders, parent) {
  var all = allFolders(connections, folders)
  var out = []
  for (var i = 0; i < all.length; i++) {
    if (parentFolder(all[i]) !== parent) continue
    var path = all[i]
    var inside = (connections || []).filter(function(c) { return isInside(c.group, path) })
    var protocols = PROTOCOLS.filter(function(p) { return inside.some(function(c) { return c.protocol === p }) })
    out.push({
      path: path,
      name: folderName(path),
      count: inside.length,
      folders: all.filter(function(f) { return parentFolder(f) === path }).length,
      protocols: protocols
    })
  }
  return out.sort(function(a, b) { return byName(a.name, b.name) })
}

// "All › Work › Servers": one entry per level, the top level first.
function breadcrumbs(path) {
  var out = [{ name: "All", path: "" }]
  var parts = path === "" ? [] : path.split("/")
  for (var i = 0; i < parts.length; i++)
    out.push({ name: parts[i], path: parts.slice(0, i + 1).join("/") })
  return out
}

// Moves `from` (and everything below it) to `to`. Returns the new lists.
function moveFolder(connections, folders, from, to) {
  var swap = function(p) { return isInside(p, from) && from !== "" ? to + p.slice(from.length) : p }
  return {
    connections: (connections || []).map(function(c) {
      if (!isInside(c.group, from) || c.group === "" ) return c
      var copy = JSON.parse(JSON.stringify(c))
      copy.group = folderPath(swap(c.group))
      return copy
    }),
    folders: normalizeFolders((folders || []).map(swap))
  }
}

// Deletes a folder without deleting what's in it: its connections and
// subfolders move up one level. Returns the new lists.
function removeFolder(connections, folders, path) {
  var parent = parentFolder(path)
  var up = function(p) {
    if (!isInside(p, path) || path === "") return p
    var rest = p.slice(path.length + 1)
    return parent === "" ? rest : (rest === "" ? parent : parent + "/" + rest)
  }
  return {
    connections: (connections || []).map(function(c) {
      if (c.group === "" || !isInside(c.group, path)) return c
      var copy = JSON.parse(JSON.stringify(c))
      copy.group = folderPath(up(c.group))
      return copy
    }),
    folders: normalizeFolders((folders || []).filter(function(f) { return f !== path }).map(up))
  }
}

// "" when `name` works as a folder name next to its siblings in `parent`.
function validateFolderName(name, parent, existing, current) {
  var n = clean(name)
  if (n === "") return "Give the folder a name."
  if (n.indexOf("/") >= 0) return "Folder names can't contain \"/\"."
  var path = parent === "" ? n : parent + "/" + n
  if (path !== current && (existing || []).indexOf(path) >= 0) return "There's already a folder called “" + n + "” here."
  return ""
}

function address(c) {
  if (!c) return ""
  var target = (c.user ? c.user + "@" : "") + c.host
  return c.port && c.port !== defaultPort(c.protocol) ? target + ":" + c.port : target
}

function subtitle(c) {
  if (!c) return ""
  if (isSshConfigEntry(c)) return "SSH · " + c.display + " · ~/.ssh/config"
  var parts = [protocolLabel(c.protocol), address(c)]
  if (c.group) parts.push(folderLabel(c.group))
  return parts.join(" · ")
}

// Case-insensitive match of every whitespace-separated term against name,
// host, user, group and protocol.
function matches(c, query) {
  var terms = clean(query).toLowerCase().split(/\s+/).filter(function(t) { return t !== "" })
  if (terms.length === 0) return true
  var hay = [c.name, c.host, c.user, c.group, c.protocol, c.display || ""].join(" ").toLowerCase()
  for (var i = 0; i < terms.length; i++)
    if (hay.indexOf(terms[i]) < 0) return false
  return true
}

function clientFor(protocol, availableBinaries) {
  var spec = CLIENTS[protocol]
  if (!spec) return ""
  var avail = availableBinaries || []
  for (var i = 0; i < spec.binaries.length; i++)
    if (avail.indexOf(spec.binaries[i]) >= 0) return spec.binaries[i]
  return ""
}

function clientPackage(protocol) {
  return CLIENTS[protocol] ? CLIENTS[protocol].pkg : ""
}

function allClientBinaries() {
  var out = []
  for (var i = 0; i < PROTOCOLS.length; i++)
    out = out.concat(CLIENTS[PROTOCOLS[i]].binaries)
  return out
}

// What gets handed to bin/rc-connect: the connection minus bookkeeping, so
// the script never sees anything it doesn't need. Never contains a secret;
// oncePassword only says one is waiting in the keyring for this connection.
function connectPayload(c, oncePassword) {
  return JSON.stringify({
    oncePassword: oncePassword === true,
    id: c.id,
    name: c.name,
    protocol: c.protocol,
    host: c.host,
    port: c.port,
    user: c.user,
    hasSecret: c.hasSecret,
    identityFile: c.identityFile,
    jumpHost: c.jumpHost,
    rdp: c.rdp,
    vnc: c.vnc
  })
}

// --- ~/.ssh/config hosts (bin/rc-ssh-hosts output) ---
// They're read-only entries: connecting runs `ssh <alias>` and lets ssh apply
// the real config, so only the alias matters; hostname/user/port are shown
// for reference.
var SSH_CONFIG_PREFIX = "ssh-config:"

function isSshConfigEntry(c) {
  return !!c && c.source === "ssh-config"
}

function parseSshHosts(text) {
  var out = []
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var f = lines[i].split("\t")
    var alias = clean(f[0])
    if (!HOST_RE.test(alias)) continue
    var c = normalize({ id: SSH_CONFIG_PREFIX + alias, name: alias, protocol: "ssh", host: alias })
    c.source = "ssh-config"
    var real = { user: clean(f[2]), host: clean(f[1]) || alias, port: toPort(f[3], "ssh"), protocol: "ssh" }
    c.display = address(real)
    // What to probe for "is it up": the real hostname/port, not the alias.
    c.probeHost = real.host
    c.probePort = real.port
    out.push(c)
  }
  return out
}

// ssh-config hosts that aren't already saved as an SSH connection to the
// same alias (the saved one wins; it can carry a group/favorite).
function unsavedSshHosts(connections, sshHosts) {
  var saved = {}
  for (var i = 0; i < (connections || []).length; i++)
    if (connections[i].protocol === "ssh") saved[connections[i].host] = true
  return (sshHosts || []).filter(function(h) { return !saved[h.host] })
}

// Ordering for the quick-connect overlay. With no query: recently used
// first, then favorites, then by name. With a query: names starting with it
// first, then the same order.
function quickList(connections, sshHosts, query) {
  var all = (connections || []).concat(unsavedSshHosts(connections, sshHosts))
  var q = clean(query).toLowerCase()
  var list = all.filter(function(c) { return matches(c, query) })
  return list.sort(function(a, b) {
    if (q !== "") {
      var pa = a.name.toLowerCase().indexOf(q) === 0, pb = b.name.toLowerCase().indexOf(q) === 0
      if (pa !== pb) return pa ? -1 : 1
    }
    if (a.lastUsed !== b.lastUsed) return b.lastUsed - a.lastUsed
    if (a.favorite !== b.favorite) return a.favorite ? -1 : 1
    var na = a.name.toLowerCase(), nb = b.name.toLowerCase()
    return na < nb ? -1 : (na > nb ? 1 : 0)
  })
}

// --- Connect tab ---

// Host/port to check for reachability, or null when a direct TCP check
// wouldn't mean anything (only reachable through a jump host).
function probeTarget(c) {
  if (!c || c.jumpHost) return null
  if (isSshConfigEntry(c)) return { host: c.probeHost, port: c.probePort }
  return { host: c.host, port: c.port }
}

function protocolCounts(connections, sshHosts) {
  var all = (connections || []).concat(unsavedSshHosts(connections, sshHosts))
  var counts = { all: all.length, ssh: 0, rdp: 0, vnc: 0 }
  for (var i = 0; i < all.length; i++) counts[all[i].protocol] = (counts[all[i].protocol] || 0) + 1
  return counts
}

// Pseudo-folder holding the ~/.ssh/config hosts. A real folder path can't
// start with "/" (folderPath drops empty segments), so it never collides.
var SSH_CONFIG_FOLDER = "/ssh-config"

function byConnectionName(a, b) {
  return byName(a.name, b.name)
}

// What the Connect tab shows, as sections of { id, title, kind, rows }
// (kind "folder" rows come from childFolders, "connection" rows are
// connections). Searching or filtering by protocol gives one flat RESULTS
// list across every folder (ranked like the launcher). Otherwise it's the
// folder `path`: at the top level FAVORITES and RECENT (the last 3 used, once
// there's more than a handful) first, then its folders, then the
// connections that live right there.
function browse(connections, folders, sshHosts, path, query, protocol) {
  var proto = PROTOCOLS.indexOf(protocol) >= 0 ? protocol : ""
  var saved = connections || []
  if (clean(query) !== "" || proto !== "") {
    var hits = quickList(saved, sshHosts, query).filter(function(c) { return proto === "" || c.protocol === proto })
    return hits.length > 0 ? [{ id: "results", title: "RESULTS", kind: "connection", rows: hits }] : []
  }
  var cfg = unsavedSshHosts(saved, sshHosts)
  if (path === SSH_CONFIG_FOLDER)
    return cfg.length > 0 ? [{ id: "ssh-config", title: "", kind: "connection", rows: cfg }] : []

  var sections = []
  if (path === "") {
    var favorites = saved.filter(function(c) { return c.favorite }).sort(byConnectionName)
    if (favorites.length > 0) sections.push({ id: "favorites", title: "FAVORITES", kind: "connection", rows: favorites })
    var recent = saved.filter(function(c) { return c.lastUsed > 0 && !c.favorite })
      .sort(function(a, b) { return b.lastUsed - a.lastUsed }).slice(0, 3)
    if (recent.length > 0 && saved.length > 5) sections.push({ id: "recent", title: "RECENT", kind: "connection", rows: recent })
  }
  var sub = childFolders(saved, folders, path)
  if (path === "" && cfg.length > 0)
    sub.push({ path: SSH_CONFIG_FOLDER, name: "~/.ssh/config", count: cfg.length, folders: 0, protocols: ["ssh"], readOnly: true })
  if (sub.length > 0) sections.push({ id: "folders", title: "FOLDERS", kind: "folder", rows: sub })
  var here = saved.filter(function(c) { return c.group === path }).sort(byConnectionName)
  // With nothing else in the view the breadcrumb already says where these
  // are, so they go without a header.
  if (here.length > 0)
    sections.push({ id: "here", title: sections.length > 0 ? "CONNECTIONS" : "", kind: "connection", rows: here })
  return sections
}

function relativeTime(ts, now) {
  if (!ts) return "never"
  var s = Math.max(0, Math.round(((now || Date.now()) - ts) / 1000))
  if (s < 60) return "just now"
  var m = Math.round(s / 60)
  if (m < 60) return m + " min ago"
  var h = Math.round(m / 60)
  if (h < 24) return h + " h ago"
  var d = Math.round(h / 24)
  if (d === 1) return "yesterday"
  if (d < 30) return d + " days ago"
  var mo = Math.round(d / 30)
  return mo < 12 ? mo + " mo ago" : Math.round(mo / 12) + " y ago"
}
