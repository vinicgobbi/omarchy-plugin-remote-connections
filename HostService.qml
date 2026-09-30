import QtQuick
import Quickshell
import Quickshell.Io

// "This machine": state of the SSH server and screen sharing (wayvnc), and
// the actions that change them. Anything that needs administrator rights
// goes through the review sheet (ChangeSheet.qml: exact commands, one
// password, live progress); screen sharing itself runs as the user
// (bin/rc-vnc). Jobs run one at a time.
Item {
  id: root

  // ConnectionStore, for keyring access (the screen-sharing password).
  property var store: null
  // ChangeSheet that reviews and applies privileged changes.
  property var changes: null
  property bool panelOpen: false

  readonly property string stateDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/remote-connections"

  // --- Snapshot from bin/rc-host-status ---
  property bool loaded: false
  property bool sshInstalled: false
  property bool sshActive: false
  property bool sshEnabled: false
  property bool sshKeysOnly: false         // effective: sshd refuses passwords
  property bool sshKeysManaged: false      // the plugin's drop-in is present
  property string sshFirewall: "none"      // none | lan | tailscale | any (open to every source)
  property int authorizedKeys: 0
  property int sshPort: 22
  property bool ufwEnabled: false
  property var lanIps: []
  property string tailscaleIp: ""
  property string user: Quickshell.env("USER") || ""
  property bool wayvncInstalled: false
  property bool vncActive: false
  property string vncFirewall: "none"
  property var vncClients: []              // addresses, for the tooltip
  property var vncViewers: []              // [{ id, address }]

  // --- Persisted preferences (host.json) ---
  property string vncScope: "local"        // local | tailscale | lan
  property int vncPort: 5900
  property bool vncPasswordSet: false
  property string sshScope: "lan"          // lan | tailscale
  property bool vncAllowControl: true

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
    if (job.command && job.command.review) {
      // A privileged change: the review sheet runs it (or hands it to the
      // terminal) and reports back with the same codes as bin/rc-terminal.
      if (!changes) { _jobDone(job.done, false, 1, "The review sheet isn't available.") ; return }
      changes.request(job.command.title, job.command.args, function(ok, code, message) {
        root._jobDone(job.done, ok, code, message)
      })
      return
    }
    jobProcess.done = job.done
    jobProcess.command = job.command
    jobProcess.running = true
  }

  function _jobDone(cb, ok, code, message) {
    if (cb) cb(ok, code, message || "")
    _inFlight = false
    Qt.callLater(_next)
  }

  // A change reviewed in the sheet before it runs (see bin/rc-steps for args).
  function review(title, args) {
    return { review: true, title: title, args: args }
  }

  // Codes from the sheet / bin/rc-terminal. Canceling isn't an error: the
  // user chose not to apply it.
  function describeFailure(exitCode, errText, what) {
    if (exitCode === 2) return ""
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
      vncPasswordSet: vncPasswordSet,
      vncAllowControl: vncAllowControl
    }, null, 2) + "\n")
  }

  // --- SSH server ---
  function enableSsh(scope) {
    lastError = ""
    sshScope = scope === "tailscale" ? "tailscale" : "lan"
    savePrefs()
    run("ssh", review("Turn on the SSH server", ["ssh-enable", sshScope]), function(ok, code, err) {
      if (!ok) lastError = describeFailure(code, err, "Turning on the SSH server")
    })
  }

  // Picking who can connect: remembered for next time while SSH is off,
  // applied right away (through the review sheet) while it's on.
  function chooseSshScope(scope) {
    if (scope !== "lan" && scope !== "tailscale") return
    if (sshActive && (scope !== sshFirewall || sshFirewall === "any") && ufwEnabled) {
      enableSsh(scope)
    } else {
      sshScope = scope
      savePrefs()
    }
  }

  // Adds a public key to ~/.ssh/authorized_keys (reviewed; runs as you).
  function authorizeKey(pubkey) {
    lastError = ""
    run("keys", review("Allow a key to log in", ["authorize-key", String(pubkey).trim()]), function(ok, code, err) {
      if (!ok) lastError = describeFailure(code, err, "Adding the key")
    })
  }

  function disableSsh() {
    lastError = ""
    run("ssh", review("Turn off the SSH server", ["ssh-disable"]), function(ok, code, err) {
      if (!ok) lastError = describeFailure(code, err, "Turning off the SSH server")
    })
  }

  function setKeysOnly(on) {
    lastError = ""
    run("keys", review(on ? "Require SSH keys" : "Allow SSH passwords again", [on ? "keys-on" : "keys-off"]), function(ok, code, err) {
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
    run("vnc", [bundledPath("bin/rc-vnc"), "start", scope, port, vncAllowControl ? "control" : "view-only"], function(ok, code, err) {
      if (!ok) {
        lastError = describeFailure(code, err, "Starting screen sharing")
        return
      }
      // Local-only needs no firewall change; otherwise open the port (and
      // drop any rule for another scope). If that's canceled, don't leave a
      // server running that the user thinks is unreachable.
      if (scope === "local") {
        if (vncFirewall !== "none") run("vnc", review("Close the old screen-sharing port", ["vnc-firewall", "close"]), null)
        return
      }
      if (!ufwEnabled) return
      run("vnc", review("Open the firewall for screen sharing", ["vnc-firewall", scope, port]), function(fwOk, fwCode, fwErr) {
        if (fwOk) return
        lastError = fwCode === 2
          ? "Screen sharing was stopped: the firewall change was canceled, so nobody could have reached it."
          : describeFailure(fwCode, fwErr, "Opening the firewall for screen sharing") + " Screen sharing was stopped."
        run("vnc", [bundledPath("bin/rc-vnc"), "stop"], null)
      })
    })
  }

  // Stopping is immediate: only closing the firewall port, if one was
  // opened, goes through the review sheet afterwards.
  function stopVnc() {
    lastError = ""
    run("vnc", [bundledPath("bin/rc-vnc"), "stop"], null)
    if (vncFirewall !== "none")
      run("vnc", review("Close the screen-sharing port", ["vnc-firewall", "close"]), function(ok, code, err) {
        if (!ok) lastError = "Screen sharing is off. " + (code === 2 ? "The firewall port was left open (canceled), but nothing is listening on it." : describeFailure(code, err, "Closing its firewall port"))
      })
  }

  // Picking who can reach screen sharing: remembered while it's off,
  // applied right away (restarting wayvnc, which drops viewers) while on.
  function chooseVncScope(scope) {
    if (["local", "tailscale", "lan"].indexOf(scope) < 0) return
    vncScope = scope
    savePrefs()
    if (vncActive) startVnc(scope, "")
  }

  function setVncAllowControl(allow) {
    vncAllowControl = allow
    savePrefs()
    if (vncActive) startVnc(vncScope, "")
  }

  function disconnectViewer(id) {
    run("vnc", [bundledPath("bin/rc-vnc"), "disconnect", String(id)], null)
  }

  function disconnectVncClients() {
    run("vnc", [bundledPath("bin/rc-vnc"), "disconnect-all"], null)
  }

  function installPackage(pkg) {
    lastError = ""
    run("install", review("Install " + pkg, ["install", pkg]), function(ok, code, err) {
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
    sshKeysOnly = map.ssh_password_auth === "no"
    sshKeysManaged = map.ssh_keys_managed === "yes"
    sshFirewall = map.ssh_firewall || "none"
    authorizedKeys = parseInt(map.authorized_keys, 10) || 0
    sshPort = parseInt(map.ssh_port, 10) || 22
    ufwEnabled = map.ufw_enabled === "yes"
    lanIps = list(map.lan_ips)
    tailscaleIp = map.tailscale_ip || ""
    if (map.user) user = map.user
    wayvncInstalled = map.wayvnc_installed === "yes"
    vncActive = map.vnc_active === "active"
    vncFirewall = map.vnc_firewall || "none"
    vncViewers = list(map.vnc_clients).map(function(entry) {
      var eq = entry.indexOf("=")
      return eq > 0 ? { id: entry.slice(0, eq), address: entry.slice(eq + 1) } : { id: "", address: entry }
    })
    vncClients = vncViewers.map(function(v) { return v.address })
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
        root.vncAllowControl = p.vncAllowControl !== false
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
      root._jobDone(cb, exitCode === 0, exitCode, String(jobErr.text || "").trim())
    }
  }
}
