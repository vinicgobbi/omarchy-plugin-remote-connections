// Pure helpers for the saved-connection list. No QML/Quickshell types in
// here so every function stays testable with plain `node`/`qjs`.

var PROTOCOLS = ["ssh", "rdp", "vnc"]

var PROTOCOL_LABELS = { ssh: "SSH", rdp: "RDP", vnc: "VNC" }

var DEFAULT_PORTS = { ssh: 22, rdp: 3389, vnc: 5900 }

// The client each protocol needs, and the Arch package that ships it. The
// first binary found wins (sdl-freerdp3 is the native Wayland client and has
// its own credential/cert dialogs, so it's preferred over xfreerdp3).
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
      clipboard: rdp.clipboard !== false
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
  var parts = [protocolLabel(c.protocol), address(c)]
  if (c.group) parts.push(c.group)
  return parts.join(" · ")
}

// Case-insensitive match of every whitespace-separated term against name,
// host, user, group and protocol.
function matches(c, query) {
  var terms = clean(query).toLowerCase().split(/\s+/).filter(function(t) { return t !== "" })
  if (terms.length === 0) return true
  var hay = [c.name, c.host, c.user, c.group, c.protocol].join(" ").toLowerCase()
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
