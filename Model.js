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

function clean(value) {
  return String(value === undefined || value === null ? "" : value).replace(/[\r\n\t]/g, " ").trim()
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
    group: clean(c.group),
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
    return { ok: false, connections: [], error: "connections.json is not valid JSON: " + e.message }
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
  return { ok: true, connections: out, error: "" }
}

function serialize(connections) {
  return JSON.stringify({ version: 1, connections: connections || [] }, null, 2) + "\n"
}

// Returns "" when the draft is acceptable, otherwise a message for the form.
function validate(draft) {
  var d = draft || {}
  var host = clean(d.host)
  if (host === "") return "Host is required."
  if (/\s/.test(host)) return "Host can't contain spaces."
  if (/^-/.test(host) || /^-/.test(clean(d.user)) || /^-/.test(clean(d.jumpHost)))
    return "Host, user and jump host can't start with '-'."
  var portText = clean(d.port)
  if (portText !== "") {
    var n = parseInt(portText, 10)
    if (!/^\d+$/.test(portText) || n < 1 || n > 65535) return "Port must be between 1 and 65535."
  }
  if (PROTOCOLS.indexOf(d.protocol) < 0) return "Unknown protocol."
  return ""
}

// Favorites first, then by group (ungrouped last), then by name.
function sorted(connections) {
  return (connections || []).slice().sort(function(a, b) {
    if (a.favorite !== b.favorite) return a.favorite ? -1 : 1
    var ga = a.group.toLowerCase(), gb = b.group.toLowerCase()
    if (ga !== gb) {
      if (ga === "") return 1
      if (gb === "") return -1
      return ga < gb ? -1 : 1
    }
    var na = a.name.toLowerCase(), nb = b.name.toLowerCase()
    return na < nb ? -1 : (na > nb ? 1 : 0)
  })
}

function groups(connections) {
  var seen = {}
  var out = []
  for (var i = 0; i < (connections || []).length; i++) {
    var g = connections[i].group
    if (g !== "" && !seen[g]) { seen[g] = true; out.push(g) }
  }
  return out.sort()
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
  if (c.group) parts.push(c.group)
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
// the script never sees anything it doesn't need. Never contains a secret.
function connectPayload(c) {
  return JSON.stringify({
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
    if (alias === "" || /^-/.test(alias)) continue
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

// Sections for the Connect tab. Searching or filtering by protocol gives a
// flat RESULTS list (ranked like the launcher); otherwise RECENT (the last
// 3 used), FAVORITES, one section per group, CONNECTIONS (ungrouped) and
// FROM ~/.SSH/CONFIG, each connection appearing once.
function connectSections(connections, sshHosts, query, protocol) {
  var proto = PROTOCOLS.indexOf(protocol) >= 0 ? protocol : ""
  var byProto = function(c) { return proto === "" || c.protocol === proto }
  if (clean(query) !== "" || proto !== "") {
    var hits = quickList(connections, sshHosts, query).filter(byProto)
    return hits.length > 0 ? [{ title: "RESULTS", rows: hits }] : []
  }
  var saved = connections || []
  var used = {}
  var sections = []
  var recent = saved.filter(function(c) { return c.lastUsed > 0 })
    .sort(function(a, b) { return b.lastUsed - a.lastUsed }).slice(0, 3)
  recent.forEach(function(c) { used[c.id] = true })
  if (recent.length > 0 && saved.length > 3) sections.push({ title: "RECENT", rows: recent })
  else used = {}
  var rest = sorted(saved.filter(function(c) { return !used[c.id] }))
  var favorites = rest.filter(function(c) { return c.favorite })
  if (favorites.length > 0) sections.push({ title: "FAVORITES", rows: favorites })
  var groupNames = groups(rest.filter(function(c) { return !c.favorite }))
  groupNames.forEach(function(g) {
    sections.push({ title: g.toUpperCase(), rows: rest.filter(function(c) { return !c.favorite && c.group === g }) })
  })
  var ungrouped = rest.filter(function(c) { return !c.favorite && c.group === "" })
  if (ungrouped.length > 0) sections.push({ title: groupNames.length > 0 || favorites.length > 0 ? "OTHER" : "CONNECTIONS", rows: ungrouped })
  var cfg = unsavedSshHosts(saved, sshHosts)
  if (cfg.length > 0) sections.push({ title: "FROM ~/.SSH/CONFIG", rows: cfg })
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
