import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Owns connections.json: loads it, keeps the in-memory list, writes changes
// back, and launches connections through bin/rc-connect. Passwords are
// handled here only in transit to bin/rc-secret (keyring) — they're never
// written to the JSON file.
Item {
  id: root

  readonly property string configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/remote-connections"
  readonly property string filePath: configDir + "/connections.json"

  property var connections: []
  property bool loaded: false
  // A connections.json that failed to parse is never overwritten: the user
  // gets the error and their file stays as it was.
  property bool writable: true
  property string lastError: ""

  // Read-only hosts from ~/.ssh/config (bin/rc-ssh-hosts), see
  // Model.parseSshHosts. Never written to connections.json.
  property var sshHosts: []

  // Which client binaries are installed (see Model.allClientBinaries()).
  property var availableClients: []
  property bool clientsChecked: false

  readonly property bool secretBusy: secretProcess.running

  // Reachability, by connection id: { state: "up"|"down"|"checking"|"unknown", ms }.
  // Filled by bin/rc-probe (a TCP connect to host:port, no data sent).
  property var reach: ({})
  // SSH private keys with a .pub in ~/.ssh (bin/rc-ssh-keys), e.g. "~/.ssh/id_ed25519".
  property var sshKeys: []
  // Last result of testTarget(): { state, ms, banner, host, port }.
  property var testResult: null
  // RDP/VNC windows opened by the plugin that are still running
  // (bin/rc-sessions): [{ id, pid, protocol, started, name }].
  property var sessions: []
  property bool watchSessions: false

  function bundledPath(name) {
    return decodeURIComponent(String(Qt.resolvedUrl(name)).replace(/^file:\/\//, ""))
  }

  function find(id) {
    for (var i = 0; i < connections.length; i++)
      if (connections[i].id === id) return connections[i]
    return null
  }

  // Saved connection or ~/.ssh/config host.
  function findAny(id) {
    var c = find(id)
    if (c) return c
    for (var i = 0; i < sshHosts.length; i++)
      if (sshHosts[i].id === id) return sshHosts[i]
    return null
  }

  function save(next) {
    if (!writable) {
      lastError = "connections.json has errors; fix or remove it before saving changes."
      return false
    }
    connections = next
    file.setText(Model.serialize(next))
    return true
  }

  // Inserts or replaces by id. Returns the stored (normalized) connection.
  function upsert(draft) {
    var c = Model.normalize(draft)
    var next = connections.slice()
    var replaced = false
    for (var i = 0; i < next.length; i++) {
      if (next[i].id === c.id) {
        // lastUsed is bookkeeping, not something the form edits.
        c.lastUsed = next[i].lastUsed
        next[i] = c
        replaced = true
        break
      }
    }
    if (!replaced) next.push(c)
    return save(next) ? c : null
  }

  function remove(id) {
    var c = find(id)
    if (!c) return
    if (save(connections.filter(function(x) { return x.id !== id })) && c.hasSecret)
      runSecret(["clear", id], "", null)
  }

  function setField(id, key, value) {
    var c = find(id)
    if (!c) return
    var copy = JSON.parse(JSON.stringify(c))
    copy[key] = value
    upsert(copy)
  }

  function toggleFavorite(id) {
    var c = find(id)
    if (c) setField(id, "favorite", !c.favorite)
  }

  function hasClient(protocol) {
    return Model.clientFor(protocol, availableClients) !== ""
  }

  // RDP through xfreerdp3 (the client with the connection bar) can't ask
  // for a password itself — it would prompt on a terminal it doesn't have —
  // so the popup asks first when none is saved. sdl-freerdp3 and TigerVNC
  // have their own dialogs.
  function needsPassword(c) {
    if (!c || c.protocol !== "rdp" || c.hasSecret) return false
    if (c.rdp && c.rdp.connectionBar === false && availableClients.indexOf("sdl-freerdp3") >= 0) return false
    return availableClients.indexOf("xfreerdp3") >= 0
  }

  // Connect with a password typed in the popup. remember: keep it in the
  // keyring for next time; otherwise it waits there under a one-time id that
  // bin/rc-connect reads and deletes. Never on a command line either way.
  function connectWithPassword(id, user, password, remember, done) {
    var c = find(id)
    if (!c || password === "") { if (done) done(false); return }
    if (user !== undefined && user !== null && Model.clean(user) !== c.user) setField(id, "user", Model.clean(user))
    if (remember) {
      runSecret(["set", id, c.name], password + "\n", function(ok) {
        if (!ok) { root.lastError = "Couldn't save the password in the keyring (is it locked?)."; if (done) done(false); return }
        setField(id, "hasSecret", true)
        if (done) done(root.connect(id))
      })
    } else {
      runSecret(["set", "once-" + id, c.name + " (one-time)"], password + "\n", function(ok) {
        if (!ok) { root.lastError = "Couldn't hand the password over through the keyring (is it locked?)."; if (done) done(false); return }
        if (done) done(root.connect(id, true))
      })
    }
  }

  function connect(id, oncePassword) {
    var c = findAny(id)
    if (!c) return false
    if (clientsChecked && !hasClient(c.protocol)) {
      lastError = Model.protocolLabel(c.protocol) + " needs the '" + Model.clientPackage(c.protocol) + "' package."
      return false
    }
    lastError = ""
    // uwsm-app puts the client in its own systemd unit, so an omarchy-shell
    // restart doesn't take an open RDP/VNC/SSH session down with it.
    Quickshell.execDetached(["uwsm-app", "--", bundledPath("bin/rc-connect"), Model.connectPayload(c, oncePassword === true)])
    if (!Model.isSshConfigEntry(c)) setField(id, "lastUsed", Date.now())
    sessionsRecheck.restart()
    return true
  }

  function copyText(text) {
    Quickshell.execDetached(["wl-copy", "--", String(text)])
  }

  // Packages for the clients that saved connections need but aren't
  // installed, e.g. ["freerdp", "tigervnc"].
  readonly property var missingPackages: {
    if (!clientsChecked) return []
    var out = []
    for (var i = 0; i < connections.length; i++) {
      var pkg = Model.clientPackage(connections[i].protocol)
      if (!hasClient(connections[i].protocol) && out.indexOf(pkg) < 0) out.push(pkg)
    }
    return out
  }

  // ChangeSheet that reviews and applies installs/removals (and hands
  // interactive steps like ssh-copy-id to the terminal).
  property var changes: null
  readonly property bool terminalBusy: terminalProcess.running || (changes !== null && changes.busy)
  readonly property bool installBusy: terminalBusy

  // Everything the Setup view manages, and whether it's installed
  // (bin/rc-packages): { libsecret: true, tigervnc: false, … }.
  readonly property var managedPackages: ["libsecret", "openssh", "freerdp", "tigervnc", "wayvnc", "ufw", "tailscale"]
  property var packages: ({})
  property bool packagesChecked: false

  // How many saved connections use each protocol.
  readonly property var protocolUse: {
    var out = { ssh: 0, rdp: 0, vnc: 0 }
    for (var i = 0; i < connections.length; i++) out[connections[i].protocol] = (out[connections[i].protocol] || 0) + 1
    return out
  }

  // Missing packages that matter now: always-needed ones, plus the client
  // of any protocol a saved connection uses. Drives the gear's badge.
  readonly property var neededMissing: {
    if (!packagesChecked) return []
    var needed = ["libsecret", "openssh"]
    if (protocolUse.rdp > 0) needed.push("freerdp")
    if (protocolUse.vnc > 0) needed.push("tigervnc")
    return needed.filter(function(p) { return packages[p] === false })
  }

  function installClient(protocol) {
    installPackages([Model.clientPackage(protocol)])
  }

  // Opens a terminal showing the install command (omarchy pkg add) and asking before it runs
  // (bin/rc-terminal); re-checks the clients once it's closed.
  function installPackages(pkgs, done) {
    var list = (pkgs || []).filter(function(p) { return p !== "" })
    if (list.length === 0) return
    reviewChange("Install " + list.join(", "), ["install"].concat(list), done)
  }

  function removePackages(pkgs, done) {
    var list = (pkgs || []).filter(function(p) { return p !== "" })
    if (list.length === 0) return
    reviewChange("Remove " + list.join(", "), ["remove"].concat(list), done)
  }

  // Through the review sheet when there is one, else the terminal.
  function reviewChange(title, args, done) {
    lastError = ""
    if (!changes) { runInTerminal(title, args); return }
    changes.request(title, args, function(ok, code, message) {
      if (!ok && code !== 2 && message) root.lastError = message
      root.refresh()
      if (done) done(ok, code, message)
    })
  }

  // Create an SSH key if there's none and copy it to the connection's
  // server (ssh-keygen + ssh-copy-id, shown in the terminal first).
  function setupSshKey(c) {
    if (!c || c.protocol !== "ssh" || Model.isSshConfigEntry(c)) return
    var target = (c.user ? c.user + "@" : "") + c.host
    var args = ["ssh-key-setup", target]
    if (c.port && c.port !== 22) args.push(String(c.port))
    reviewChange("Log in to " + c.name + " with a key", args, null)
  }

  // Opens the command terminal (bin/rc-terminal) for `args`; re-checks
  // clients and keys once it's closed.
  function runInTerminal(title, args) {
    if (terminalProcess.running) return
    lastError = ""
    terminalProcess.command = [bundledPath("bin/rc-terminal"), title].concat(args)
    terminalProcess.running = true
  }

  // --- Keyring (bin/rc-secret). One operation at a time; the password goes
  // over stdin, never argv. ---
  property var _secretQueue: []

  function storeSecret(id, name, password) {
    runSecret(["set", id, name], password + "\n", function(ok) {
      if (ok) setField(id, "hasSecret", true)
      else lastError = "Couldn't save the password in the keyring (is it locked?). The client will ask for it instead."
    })
  }

  function clearSecret(id) {
    runSecret(["clear", id], "", function(ok) {
      if (ok) setField(id, "hasSecret", false)
    })
  }

  function runSecret(args, stdinText, callback) {
    _secretQueue = _secretQueue.concat([{ args: args, stdin: stdinText, callback: callback }])
    if (!secretProcess.running) _nextSecret()
  }

  function _nextSecret() {
    if (_secretQueue.length === 0) return
    var job = _secretQueue[0]
    _secretQueue = _secretQueue.slice(1)
    secretProcess.callback = job.callback
    secretProcess.pendingStdin = job.stdin
    secretProcess.command = [bundledPath("bin/rc-secret")].concat(job.args)
    secretProcess.running = true
  }

  // Re-checks installed clients and re-reads ~/.ssh/config; cheap, so it
  // runs every time the panel or the overlay opens.
  function refresh() {
    clientCheck.running = true
    sshHostsProcess.running = true
    sshKeysProcess.running = true
    if (!packagesProcess.running) packagesProcess.running = true
  }

  // Probe every saved connection and ~/.ssh/config host that can be checked
  // directly (not ones behind a jump host).
  function probeAll() {
    if (probeProcess.running) return
    var args = []
    var next = {}
    var all = connections.concat(Model.unsavedSshHosts(connections, sshHosts))
    for (var i = 0; i < all.length; i++) {
      var t = Model.probeTarget(all[i])
      var prev = reach[all[i].id]
      if (!t) { next[all[i].id] = { state: "unknown", ms: 0 }; continue }
      next[all[i].id] = prev && prev.state !== "unknown" ? prev : { state: "checking", ms: 0 }
      args.push(all[i].id, t.host, String(t.port))
    }
    reach = next
    if (args.length === 0) return
    probeProcess.command = [bundledPath("bin/rc-probe")].concat(args)
    probeProcess.running = true
  }

  function refreshSessions() {
    if (!sessionsProcess.running) sessionsProcess.running = true
  }

  function disconnectSession(id) {
    Quickshell.execDetached([bundledPath("bin/rc-sessions"), "stop", String(id)])
    sessionsRecheck.restart()
  }

  function focusSession(id) {
    Quickshell.execDetached([bundledPath("bin/rc-sessions"), "focus", String(id)])
  }

  function reachOf(id) {
    return reach[id] || { state: "unknown", ms: 0 }
  }

  // The form's Test button: connect once, and read the greeting if any.
  function testTarget(host, port) {
    if (testProcess.running) return
    testResult = { state: "checking", ms: 0, banner: "", host: host, port: port }
    testProcess.command = [bundledPath("bin/rc-probe"), "--banner", "test", String(host), String(port)]
    testProcess.running = true
  }

  // A copy named "<name> (copy)", not a favorite, never used, no password.
  function duplicate(id) {
    var c = find(id)
    if (!c) return null
    var copy = JSON.parse(JSON.stringify(c))
    copy.id = Model.newId()
    copy.name = c.name + " (copy)"
    copy.favorite = false
    copy.lastUsed = 0
    copy.hasSecret = false
    return upsert(copy)
  }

  Component.onCompleted: {
    // Private: it lists your hosts and users (never passwords).
    Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && chmod 700 "$1"', "sh", root.configDir])
    refresh()
  }

  FileView {
    id: file
    path: root.filePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var r = Model.parseList(text())
      root.connections = r.connections
      root.writable = r.ok
      root.lastError = r.error
      root.loaded = true
    }
    onLoadFailed: {
      // Missing file: first run, nothing saved yet.
      root.connections = []
      root.writable = true
      root.loaded = true
    }
  }

  Process {
    id: clientCheck
    running: false
    command: ["sh", "-c", "for b in \"$@\"; do command -v \"$b\" >/dev/null 2>&1 && echo \"$b\"; done", "sh"].concat(Model.allClientBinaries())
    stdout: StdioCollector { id: clientOut; waitForEnd: true }
    onExited: {
      root.availableClients = String(clientOut.text || "").split("\n").filter(function(s) { return s !== "" })
      root.clientsChecked = true
    }
  }

  Process {
    id: terminalProcess
    running: false
    command: []
    stderr: StdioCollector { id: terminalErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 1) root.lastError = String(terminalErr.text || "").trim() || "It failed in the terminal."
      root.refresh()
    }
  }

  Process {
    id: packagesProcess
    running: false
    command: [root.bundledPath("bin/rc-packages")].concat(root.managedPackages)
    stdout: StdioCollector { id: packagesOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var next = {}
      String(packagesOut.text || "").split("\n").forEach(function(l) {
        var f = l.split("\t")
        if (f.length === 2) next[f[0]] = f[1] === "yes"
      })
      root.packages = next
      root.packagesChecked = true
    }
  }

  Process {
    id: sessionsProcess
    running: false
    command: [root.bundledPath("bin/rc-sessions"), "list"]
    stdout: StdioCollector { id: sessionsOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      root.sessions = String(sessionsOut.text || "").split("\n").filter(function(l) { return l !== "" }).map(function(l) {
        var f = l.split("\t")
        return { id: f[0], pid: f[1], protocol: f[2], started: parseInt(f[3], 10) || 0, name: f[4] || f[0] }
      })
    }
  }

  // Poll while someone is looking (popup open), and shortly after a
  // connect/disconnect so the list catches up.
  Timer {
    interval: 3000
    repeat: true
    running: root.watchSessions
    triggeredOnStart: true
    onTriggered: root.refreshSessions()
  }

  Timer {
    id: sessionsRecheck
    interval: 1500
    onTriggered: root.refreshSessions()
  }

  Process {
    id: probeProcess
    running: false
    command: []
    stdout: StdioCollector { id: probeOut; waitForEnd: true }
    onExited: {
      var next = {}
      for (var k in root.reach) next[k] = root.reach[k]
      var lines = String(probeOut.text || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var f = lines[i].split("\t")
        if (f.length >= 3) next[f[0]] = { state: f[1], ms: parseInt(f[2], 10) || 0 }
      }
      root.reach = next
    }
  }

  Process {
    id: testProcess
    running: false
    command: []
    stdout: StdioCollector { id: testOut; waitForEnd: true }
    onExited: {
      var f = String(testOut.text || "").replace(/\n$/, "").split("\t")
      var prev = root.testResult || {}
      root.testResult = {
        state: f[1] === "up" ? "up" : "down",
        ms: parseInt(f[2], 10) || 0,
        banner: f[3] || "",
        host: prev.host,
        port: prev.port
      }
    }
  }

  Process {
    id: sshKeysProcess
    running: false
    command: [root.bundledPath("bin/rc-ssh-keys")]
    stdout: StdioCollector { id: sshKeysOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.sshKeys = String(sshKeysOut.text || "").split("\n").filter(function(l) { return l !== "" })
    }
  }

  Process {
    id: sshHostsProcess
    running: false
    command: [root.bundledPath("bin/rc-ssh-hosts")]
    stdout: StdioCollector { id: sshHostsOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.sshHosts = Model.parseSshHosts(sshHostsOut.text)
    }
  }

  Process {
    id: secretProcess
    running: false
    stdinEnabled: true
    property string pendingStdin: ""
    property var callback: null
    command: []
    stderr: StdioCollector { id: secretErr; waitForEnd: true }
    onStarted: {
      if (pendingStdin !== "") {
        write(pendingStdin)
        pendingStdin = ""
      }
    }
    onExited: function(exitCode) {
      var cb = callback
      callback = null
      if (cb) cb(exitCode === 0)
      Qt.callLater(root._nextSecret)
    }
  }
}
