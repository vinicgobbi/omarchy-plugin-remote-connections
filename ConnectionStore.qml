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

  function connect(id) {
    var c = findAny(id)
    if (!c) return false
    if (clientsChecked && !hasClient(c.protocol)) {
      lastError = Model.protocolLabel(c.protocol) + " needs the '" + Model.clientPackage(c.protocol) + "' package."
      return false
    }
    lastError = ""
    // uwsm-app puts the client in its own systemd unit, so an omarchy-shell
    // restart doesn't take an open RDP/VNC/SSH session down with it.
    Quickshell.execDetached(["uwsm-app", "--", bundledPath("bin/rc-connect"), Model.connectPayload(c)])
    if (!Model.isSshConfigEntry(c)) setField(id, "lastUsed", Date.now())
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

  readonly property bool installBusy: installProcess.running

  function installClient(protocol) {
    installPackages([Model.clientPackage(protocol)])
  }

  // Opens a terminal showing the install command (omarchy pkg add) and asking before it runs
  // (bin/rc-terminal); re-checks the clients once it's closed.
  function installPackages(pkgs) {
    var list = (pkgs || []).filter(function(p) { return p !== "" })
    if (list.length === 0 || installProcess.running) return
    lastError = ""
    installProcess.command = [bundledPath("bin/rc-terminal"), "Install " + list.join(", "), "install"].concat(list)
    installProcess.running = true
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
  }

  Component.onCompleted: {
    Quickshell.execDetached(["mkdir", "-p", root.configDir])
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
    id: installProcess
    running: false
    command: []
    stderr: StdioCollector { id: installErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 1) root.lastError = String(installErr.text || "").trim() || "The install failed."
      root.refresh()
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
