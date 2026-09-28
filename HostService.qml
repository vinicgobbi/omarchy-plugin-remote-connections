import QtQuick
import Quickshell
import Quickshell.Io

// "This machine": state of the SSH server and screen sharing (wayvnc), and
// the actions that change them. Anything that needs sudo or installs a
// package opens an Omarchy terminal (bin/rc-terminal) that shows the exact
// commands and only runs them once the user confirms there; screen sharing
// itself runs as the user (bin/rc-vnc). Jobs run one at a time.
Item {
  id: root

  // ConnectionStore, for keyring access (the screen-sharing password).
  property var store: null
  property bool panelOpen: false

  readonly property string stateDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/remote-connections"

  // --- Snapshot from bin/rc-host-status ---
  property bool loaded: false
  property bool sshInstalled: false
  property bool sshActive: false
  property bool sshEnabled: false
  property bool sshKeysOnly: false
  property string sshFirewall: "none"      // none | lan | tailscale
  property int authorizedKeys: 0
  property bool ufwEnabled: false
  property var lanIps: []
  property string tailscaleIp: ""
  property string user: Quickshell.env("USER") || ""
  property bool wayvncInstalled: false
  property bool vncActive: false
  property string vncFirewall: "none"
  property var vncClients: []

  // --- Persisted preferences (host.json) ---
  property string vncScope: "local"        // local | tailscale | lan
  property int vncPort: 5900
  property bool vncPasswordSet: false
  property string sshScope: "lan"          // lan | tailscale

  // --- Jobs ---
  property string busy: ""                 // label of the running job, "" when idle
  property string lastError: ""
  property var _jobs: []
  property bool _inFlight: false

  readonly property bool screenBeingViewed: vncActive && vncClients.length > 0

  function bundledPath(name) {
    return decodeURIComponent(String(Qt.resolvedUrl(name)).replace(/^file:\/\//, ""))
  }

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
  }

  // Queue a command. done(ok, stderrText) runs when it exits. Every job in
  // a chain shares one label so the UI can show a single spinner.
  function run(label, command, done) {
    _jobs = _jobs.concat([{ label: label, command: command, done: done || null }])
    if (!_inFlight) Qt.callLater(_next)
  }

  function _next() {
    if (_inFlight) return
    if (_jobs.length === 0) {
      busy = ""
      refresh()
      return
    }
    var job = _jobs[0]
    _jobs = _jobs.slice(1)
    busy = job.label
    _inFlight = true
    jobProcess.done = job.done
    jobProcess.command = job.command
    jobProcess.running = true
  }

  // Runs `args` (see bin/rc-steps) in a terminal that shows the commands
  // and asks before running them.
  function inTerminal(title, args) {
    return [bundledPath("bin/rc-terminal"), title].concat(args)
  }

  // Exit codes from bin/rc-terminal.
  function describeFailure(exitCode, errText, what) {
    if (exitCode === 2) return what + " was canceled in the terminal; nothing was changed."
    if (exitCode === 3) return what + ": the terminal was closed before it finished. Check the state below."
    if (exitCode === 4) return what + " finished with some steps skipped."
    return errText !== "" ? errText : what + " failed (exit code " + exitCode + ")."
  }

  function savePrefs() {
    prefsFile.setText(JSON.stringify({
      version: 1,
      sshScope: sshScope,
      vncScope: vncScope,
      vncPort: vncPort,
      vncPasswordSet: vncPasswordSet
    }, null, 2) + "\n")
  }

  // --- SSH server ---
  function enableSsh(scope) {
    lastError = ""
    sshScope = scope === "tailscale" ? "tailscale" : "lan"
    savePrefs()
    run("ssh", inTerminal("Turn on the SSH server", ["ssh-enable", sshScope]), function(ok, code, err) {
      if (!ok) lastError = describeFailure(code, err, "Turning on the SSH server")
    })
  }

  function disableSsh() {
    lastError = ""
    run("ssh", inTerminal("Turn off the SSH server", ["ssh-disable"]), function(ok, code, err) {
      if (!ok) lastError = describeFailure(code, err, "Turning off the SSH server")
    })
  }

  function setKeysOnly(on) {
    lastError = ""
    run("keys", inTerminal(on ? "SSH: keys only" : "SSH: allow passwords again", [on ? "keys-on" : "keys-off"]), function(ok, code, err) {
      if (!ok) lastError = describeFailure(code, err, "Changing password logins")
    })
  }

  // --- Screen sharing ---
  function setVncPassword(password, then) {
    if (!store || password === "") { if (then) then(false); return }
    store.runSecret(["set", "host-vnc", "Screen sharing (this machine)"], password + "\n", function(ok) {
      if (ok) {
        vncPasswordSet = true
        savePrefs()
      } else {
        lastError = "Couldn't save the screen-sharing password in the keyring (is it locked?)."
      }
      if (then) then(ok)
    })
  }

  function startVnc(scope, password) {
    lastError = ""
    vncScope = ["local", "tailscale", "lan"].indexOf(scope) >= 0 ? scope : "local"
    savePrefs()
    if (password !== "") setVncPassword(password, function(ok) { if (ok) _startVnc() })
    else _startVnc()
  }

  function _startVnc() {
    var scope = vncScope
    var port = String(vncPort)
    run("vnc", [bundledPath("bin/rc-vnc"), "start", scope, port], function(ok, code, err) {
      if (!ok) {
        lastError = describeFailure(code, err, "Starting screen sharing")
        return
      }
      // Local-only needs no firewall change; otherwise open the port (and
      // drop any rule for another scope). If that's canceled, don't leave a
      // server running that the user thinks is unreachable.
      if (scope === "local") {
        if (vncFirewall !== "none") run("vnc", inTerminal("Close the old screen-sharing port", ["vnc-firewall", "close"]), null)
        return
      }
      if (!ufwEnabled) return
      run("vnc", inTerminal("Open the firewall for screen sharing", ["vnc-firewall", scope, port]), function(fwOk, fwCode, fwErr) {
        if (fwOk) return
        lastError = describeFailure(fwCode, fwErr, "Opening the firewall for screen sharing") + " Screen sharing was stopped."
        run("vnc", [bundledPath("bin/rc-vnc"), "stop"], null)
      })
    })
  }

  // Stopping is immediate (no terminal): only closing the firewall port,
  // if one was opened, goes through the terminal afterwards.
  function stopVnc() {
    lastError = ""
    run("vnc", [bundledPath("bin/rc-vnc"), "stop"], null)
    if (vncFirewall !== "none")
      run("vnc", inTerminal("Close the screen-sharing port", ["vnc-firewall", "close"]), function(ok, code, err) {
        if (!ok) lastError = describeFailure(code, err, "Closing the screen-sharing firewall port") + " The port stays open, but nothing is listening on it."
      })
  }

  function disconnectVncClients() {
    run("vnc", [bundledPath("bin/rc-vnc"), "disconnect-all"], null)
  }

  function installPackage(pkg) {
    lastError = ""
    run("install", inTerminal("Install " + pkg, ["install", pkg]), function(ok, code, err) {
      if (!ok) lastError = describeFailure(code, err, "Installing " + pkg)
    })
  }

  function applyStatus(text) {
    var map = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var tab = lines[i].indexOf("\t")
      if (tab > 0) map[lines[i].slice(0, tab)] = lines[i].slice(tab + 1)
    }
    function list(v) { return String(v || "").split(",").filter(function(s) { return s !== "" }) }
    sshInstalled = map.ssh_installed === "yes"
    sshActive = map.ssh_active === "active"
    sshEnabled = map.ssh_enabled === "enabled"
    sshKeysOnly = map.ssh_keys_only === "yes"
    sshFirewall = map.ssh_firewall || "none"
    authorizedKeys = parseInt(map.authorized_keys, 10) || 0
    ufwEnabled = map.ufw_enabled === "yes"
    lanIps = list(map.lan_ips)
    tailscaleIp = map.tailscale_ip || ""
    if (map.user) user = map.user
    wayvncInstalled = map.wayvnc_installed === "yes"
    vncActive = map.vnc_active === "active"
    vncFirewall = map.vnc_firewall || "none"
    vncClients = list(map.vnc_clients)
    loaded = true
  }

  Component.onCompleted: refresh()

  // Faster while the popup is open; slower in the background, just enough to
  // keep the bar icon's "your screen is being viewed" indicator current.
  Timer {
    interval: root.panelOpen ? 4000 : 15000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  onPanelOpenChanged: if (panelOpen) refresh()

  FileView {
    id: prefsFile
    path: root.stateDir + "/host.json"
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var p = JSON.parse(text())
        if (["local", "tailscale", "lan"].indexOf(p.vncScope) >= 0) root.vncScope = p.vncScope
        var port = parseInt(p.vncPort, 10)
        if (isFinite(port) && port > 0 && port < 65536) root.vncPort = port
        root.vncPasswordSet = p.vncPasswordSet === true
        if (p.sshScope === "tailscale" || p.sshScope === "lan") root.sshScope = p.sshScope
      } catch (e) {
        // Keep defaults; the file is rewritten on the next change.
      }
    }
  }

  Process {
    id: statusProcess
    running: false
    command: [root.bundledPath("bin/rc-host-status")]
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) root.applyStatus(statusOut.text)
    }
  }

  Process {
    id: jobProcess
    running: false
    property var done: null
    command: []
    stderr: StdioCollector { id: jobErr; waitForEnd: true }
    onExited: function(exitCode) {
      var cb = done
      done = null
      // Callbacks may queue follow-up jobs; those start after this one is
      // fully done, never alongside it.
      if (cb) cb(exitCode === 0, exitCode, String(jobErr.text || "").trim())
      root._inFlight = false
      Qt.callLater(root._next)
    }
  }
}
