import QtQuick
import qs.Commons
import qs.Ui

// "This machine" tab: who can reach this computer and how. A live alert
// while the screen is being viewed, a one-line exposure summary, then one
// card per service (SSH server, screen sharing) with its switch, who can
// connect, the command to use from the other computer and its security
// state. Anything needing sudo goes through the command terminal
// (HostService → bin/rc-terminal); stopping screen sharing is immediate.
Column {
  id: tab

  property var panel: null
  property var store: null
  property var host: null

  property bool addingKey: false
  property bool editingVncPassword: false
  property bool startAfterPassword: false
  property string copied: ""

  spacing: Style.space(10)

  function reset() {
    addingKey = false
    editingVncPassword = false
    startAfterPassword = false
    keyField.text = ""
    vncPasswordField.text = ""
  }

  function copy(text) {
    store.copyText(text)
    copied = text
    copiedTimer.restart()
  }

  function addresses(scope) {
    if (scope === "local") return ["127.0.0.1"]
    if (scope === "tailscale") return host.tailscaleIp !== "" ? [host.tailscaleIp] : []
    return host.lanIps.concat(host.tailscaleIp !== "" ? [host.tailscaleIp] : [])
  }

  // "any" is an old rule open to every source; it counts as the LAN choice
  // (and is flagged below until SSH is turned off and on again).
  readonly property string sshScopeNow: host.sshActive
    ? (host.sshFirewall === "none" || host.sshFirewall === "any" ? "lan" : host.sshFirewall)
    : host.sshScope
  readonly property bool openToInternet: host.ufwEnabled
    && ((host.sshActive && host.sshFirewall === "any") || (host.vncActive && host.vncFirewall === "any"))

  readonly property string exposure: {
    var parts = []
    if (host.sshActive) parts.push("SSH")
    if (host.vncActive) parts.push("screen sharing")
    if (parts.length === 0) return "Nobody can reach this computer: SSH and screen sharing are off."
    var where
    if (!host.ufwEnabled) where = "every network you're on, the internet included if you have a public IPv6 (the firewall is off)"
    else if (openToInternet) where = "every network, the internet included"
    else {
      var scopes = []
      if (host.sshActive) scopes.push(sshScopeNow)
      if (host.vncActive) scopes.push(host.vncScope)
      where = scopes.indexOf("lan") >= 0 ? "private networks (your LAN)"
        : (scopes.indexOf("tailscale") >= 0 ? "your Tailscale devices" : "this computer only")
    }
    return "Reachable from " + where + " over " + parts.join(" and ") + "."
  }

  function toggleVnc() {
    if (host.vncActive) {
      host.stopVnc()
    } else if (!host.vncPasswordSet) {
      startAfterPassword = true
      editingVncPassword = true
      Qt.callLater(function() { vncPasswordField.forceActiveFocus() })
    } else {
      host.startVnc(host.vncScope, "")
    }
  }

  function saveVncPassword() {
    var pw = vncPasswordField.text
    if (pw === "") return
    if (startAfterPassword) host.startVnc(host.vncScope, pw)
    else host.setVncPassword(pw, null)
    vncPasswordField.text = ""
    editingVncPassword = false
    startAfterPassword = false
  }

  // Two/three-way picker used for "who can connect".
  component Segmented: Rectangle {
    id: seg
    property var options: []          // [{ id, label, enabled }]
    property string current: ""
    signal picked(string id)

    height: segRow.height + Style.space(6)
    radius: Style.cornerRadius
    color: Util.alpha(tab.panel.foreground, 0.06)

    Row {
      id: segRow
      x: Style.space(3)
      y: Style.space(3)
      width: parent.width - Style.space(6)
      spacing: Style.space(4)

      Repeater {
        model: seg.options
        delegate: Rectangle {
          id: segItem
          required property var modelData
          readonly property bool on: seg.current === modelData.id
          readonly property bool usable: modelData.enabled !== false
          width: (segRow.width - Style.space(4) * (seg.options.length - 1)) / seg.options.length
          height: Style.font.caption + Style.space(14)
          radius: Style.cornerRadius
          opacity: usable ? 1 : 0.4
          color: on ? Util.alpha(tab.panel.accent, 0.16) : (segMouse.containsMouse && usable ? Util.alpha(tab.panel.foreground, 0.05) : "transparent")

          Text {
            anchors.centerIn: parent
            width: parent.width - Style.space(6)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: segItem.modelData.label
            color: segItem.on ? tab.panel.accent : tab.panel.foreground
            font.family: tab.panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: segItem.on
          }

          MouseArea {
            id: segMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: segItem.usable && !segItem.on
            cursorShape: Qt.PointingHandCursor
            onClicked: seg.picked(segItem.modelData.id)
          }
        }
      }
    }
  }

  // A command to run on the other computer, with a copy button.
  component CommandLine: Row {
    id: cmdRow
    property string command: ""
    property string note: ""
    spacing: Style.space(6)

    Rectangle {
      width: cmdRow.width - cmdCopy.width - Style.space(6)
      height: cmdText.implicitHeight + Style.space(12)
      radius: Style.cornerRadius
      color: Util.alpha(tab.panel.foreground, 0.05)
      Text {
        id: cmdText
        x: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Style.space(16)
        text: cmdRow.command + (cmdRow.note !== "" ? "   " + cmdRow.note : "")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: tab.panel.accent
        font.family: tab.panel.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
    Pill {
      id: cmdCopy
      anchors.verticalCenter: parent.verticalCenter
      text: tab.copied === cmdRow.command ? "Copied" : "Copy"
      tint: tab.panel.foreground
      fontFamily: tab.panel.fontFamily
      onClicked: tab.copy(cmdRow.command)
    }
  }

  component SubHeader: Text {
    color: tab.panel.dim
    font.family: tab.panel.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
  }

  component Check: Row {
    id: check
    property bool ok: true
    property string text: ""
    spacing: Style.space(8)
    Text {
      text: check.ok ? "✓" : "!"
      color: check.ok ? tab.panel.okColor : tab.panel.warnColor
      font.family: tab.panel.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    Text {
      width: check.width - Style.space(20)
      text: check.text
      wrapMode: Text.Wrap
      color: tab.panel.foreground
      font.family: tab.panel.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Timer {
    id: copiedTimer
    interval: 1500
    onTriggered: tab.copied = ""
  }

  // ===== Live alert: someone is viewing the screen =====
  Rectangle {
    visible: host.screenBeingViewed
    width: parent.width
    height: alertRow.implicitHeight + Style.space(20)
    radius: Style.cornerRadius
    color: Util.alpha(panel.urgent, 0.14)
    border.width: Style.normalBorderWidth
    border.color: Util.alpha(panel.urgent, 0.6)

    Row {
      id: alertRow
      x: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(24)
      spacing: Style.space(10)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: "󰈈"
        color: panel.urgent
        font.family: panel.fontFamily
        font.pixelSize: Style.font.title
      }
      Column {
        width: parent.width - disconnectAll.width - Style.space(40)
        anchors.verticalCenter: parent.verticalCenter
        Text {
          text: "Your screen is being viewed"
          color: panel.urgent
          font.family: panel.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
          width: parent.width
          text: "from " + host.vncClients.join(", ") + (host.vncAllowControl ? " · can control" : " · view only")
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
      Pill {
        id: disconnectAll
        anchors.verticalCenter: parent.verticalCenter
        text: "Disconnect"
        filled: true
        tint: panel.urgent
        fontFamily: panel.fontFamily
        onClicked: host.disconnectVncClients()
      }
    }
  }

  Text {
    visible: host.lastError !== ""
    width: parent.width
    text: host.lastError
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: panel.urgent
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    width: parent.width
    text: tab.exposure
    wrapMode: Text.Wrap
    color: host.sshActive || host.vncActive ? panel.foreground : panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }

  // ===== SSH server =====
  Rectangle {
    width: parent.width
    height: sshCard.implicitHeight + Style.space(24)
    radius: Style.cornerRadius
    color: "transparent"
    border.width: Style.normalBorderWidth
    border.color: Util.alpha(panel.foreground, host.sshActive ? 0.25 : 0.12)

    Column {
      id: sshCard
      x: Style.space(12)
      y: Style.space(12)
      width: parent.width - Style.space(24)
      spacing: Style.space(10)

      Row {
        width: parent.width
        spacing: Style.space(10)
        Column {
          width: parent.width - sshSwitch.width - Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          Text {
            text: "SSH server"
            color: panel.foreground
            font.family: panel.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            width: parent.width
            text: !host.sshInstalled ? "openssh isn't installed"
              : host.busy === "ssh" ? "Waiting for the terminal…"
              : host.sshActive ? "● On · " + (host.sshEnabled ? "starts at boot" : "until reboot") + " · port " + host.sshPort
              : "Off"
            elide: Text.ElideRight
            color: host.sshActive ? panel.okColor : panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        ToggleSwitch {
          id: sshSwitch
          anchors.verticalCenter: parent.verticalCenter
          checked: host.sshActive
          busy: host.busy === "ssh"
          interactive: host.sshInstalled && host.busy === ""
          foreground: panel.foreground
          accent: panel.accent
          onToggled: host.sshActive ? host.disableSsh() : host.enableSsh(host.sshScope)
        }
      }

      SubHeader { text: "WHO CAN CONNECT" }
      Segmented {
        width: parent.width
        current: tab.sshScopeNow
        options: [
          { id: "lan", label: "Local network" },
          { id: "tailscale", label: "Tailscale only", enabled: host.tailscaleIp !== "" }
        ]
        onPicked: function(id) { host.chooseSshScope(id) }
      }
      Text {
        width: parent.width
        visible: text !== ""
        text: host.tailscaleIp === "" ? "Tailscale isn't connected, so \"Tailscale only\" isn't available."
          : host.sshActive ? "Changing this opens the command terminal." : ""
        wrapMode: Text.Wrap
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }

      SubHeader { visible: host.sshActive; text: "FROM THE OTHER COMPUTER" }
      Repeater {
        model: host.sshActive ? tab.addresses(tab.sshScopeNow) : []
        delegate: CommandLine {
          required property string modelData
          width: sshCard.width
          command: "ssh " + host.user + "@" + modelData + (host.sshPort !== 22 ? " -p " + host.sshPort : "")
        }
      }

      SubHeader { visible: host.sshInstalled; text: "SECURITY" }
      Check {
        visible: host.sshInstalled
        width: parent.width
        ok: host.ufwEnabled && !(host.sshActive && host.sshFirewall === "any")
        text: !host.ufwEnabled
          ? "Firewall (ufw) is off: whatever you turn on here is reachable from every network, the internet included over IPv6"
          : host.sshActive && host.sshFirewall === "any"
          ? "Port " + host.sshPort + " is open to every network, the internet included (a rule from an older version). Turn the SSH server off and on again to limit it to private networks."
          : host.sshActive ? "Firewall on: port " + host.sshPort + " open to " + (tab.sshScopeNow === "tailscale" ? "Tailscale only" : "private networks only (not the internet)")
          : "Firewall on"
      }
      Check {
        visible: host.sshInstalled
        width: parent.width
        ok: host.sshKeysOnly
        text: host.sshKeysOnly
            ? "Only SSH keys can log in (" + host.authorizedKeys + " allowed)" + (host.sshKeysManaged ? "" : " · set outside the plugin")
          : host.sshKeysManaged ? "Require keys is on, but another sshd setting turns passwords back on. Check /etc/ssh/sshd_config.d/."
          : host.authorizedKeys === 0 ? "Password logins are allowed. Add a key, then require keys."
          : host.authorizedKeys + " key(s) allowed, but passwords still work too."
      }
      Row {
        visible: host.sshInstalled
        spacing: Style.space(6)
        Pill {
          text: tab.addingKey ? "Hide" : "Add a key"
          iconText: "󰌆"
          tint: panel.foreground
          fontFamily: panel.fontFamily
          onClicked: tab.addingKey = !tab.addingKey
        }
        Pill {
          // Only offered when the plugin manages it; a keys-only setup made
          // by hand is left alone.
          visible: host.sshKeysManaged || !host.sshKeysOnly
          text: host.sshKeysManaged ? "Allow passwords again" : "Require keys"
          tooltip: host.authorizedKeys === 0 && !host.sshKeysManaged ? "Add a key first, or you'd lock yourself out" : "Opens the command terminal"
          enabled: host.busy === "" && (host.sshKeysManaged || host.authorizedKeys > 0)
          tint: panel.foreground
          fontFamily: panel.fontFamily
          onClicked: host.setKeysOnly(!host.sshKeysManaged)
        }
      }

      // Add a key: from the other computer, or paste its public key here.
      Column {
        visible: tab.addingKey
        width: parent.width
        spacing: Style.space(6)
        Text {
          width: parent.width
          text: "On the other computer (with SSH on here), run:"
          wrapMode: Text.Wrap
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
        CommandLine {
          width: parent.width
          command: "ssh-copy-id " + host.user + "@" + (tab.addresses(tab.sshScopeNow)[0] || "<this computer>")
        }
        Text {
          width: parent.width
          text: "…or paste its public key (the contents of ~/.ssh/id_ed25519.pub over there):"
          wrapMode: Text.Wrap
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
        Row {
          width: parent.width
          spacing: Style.space(6)
          TextField {
            id: keyField
            width: parent.width - addKeyBtn.width - Style.space(6)
            placeholderText: "ssh-ed25519 AAAA… you@laptop"
            foreground: panel.foreground
            accent: panel.accent
            onAccepted: addKeyBtn.clicked()
            Keys.onEscapePressed: tab.addingKey = false
          }
          Pill {
            id: addKeyBtn
            anchors.verticalCenter: parent.verticalCenter
            text: "Add"
            filled: true
            tint: panel.accent
            enabled: keyField.text.trim() !== "" && host.busy === ""
            fontFamily: panel.fontFamily
            onClicked: {
              host.authorizeKey(keyField.text)
              keyField.text = ""
              tab.addingKey = false
            }
          }
        }
      }
    }
  }

  // ===== Screen sharing =====
  Rectangle {
    width: parent.width
    height: vncCard.implicitHeight + Style.space(24)
    radius: Style.cornerRadius
    color: "transparent"
    border.width: Style.normalBorderWidth
    border.color: host.screenBeingViewed ? Util.alpha(panel.urgent, 0.6) : Util.alpha(panel.foreground, host.vncActive ? 0.25 : 0.12)

    Column {
      id: vncCard
      x: Style.space(12)
      y: Style.space(12)
      width: parent.width - Style.space(24)
      spacing: Style.space(10)

      Row {
        width: parent.width
        spacing: Style.space(10)
        Column {
          width: parent.width - vncControl.width - Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          Text {
            text: "Screen sharing"
            color: panel.foreground
            font.family: panel.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            width: parent.width
            text: !host.wayvncInstalled ? "Needs the wayvnc package"
              : host.busy === "vnc" ? "Working…"
              : host.vncActive ? "● On · VNC, encrypted · port " + host.vncPort
              : "Off"
            elide: Text.ElideRight
            color: !host.wayvncInstalled ? panel.warnColor : (host.vncActive ? panel.okColor : panel.dim)
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        Item {
          id: vncControl
          anchors.verticalCenter: parent.verticalCenter
          width: host.wayvncInstalled ? vncSwitch.width : installVnc.width
          height: Math.max(vncSwitch.height, installVnc.height)
          ToggleSwitch {
            id: vncSwitch
            visible: host.wayvncInstalled
            anchors.centerIn: parent
            checked: host.vncActive
            busy: host.busy === "vnc"
            interactive: host.busy === ""
            foreground: panel.foreground
            accent: panel.accent
            onToggled: tab.toggleVnc()
          }
          Pill {
            id: installVnc
            visible: !host.wayvncInstalled
            anchors.centerIn: parent
            text: "Install"
            tooltip: "Opens a terminal that shows the install command first"
            tint: panel.warnColor
            enabled: host.busy === ""
            fontFamily: panel.fontFamily
            onClicked: host.installPackage("wayvnc")
          }
        }
      }

      Text {
        width: parent.width
        visible: !host.wayvncInstalled
        text: "Shares your actual Hyprland screen with a VNC viewer (TigerVNC, Remmina, macOS Screen Sharing…). Always password-protected and encrypted."
        wrapMode: Text.Wrap
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }

      SubHeader { visible: host.wayvncInstalled; text: "WHO CAN CONNECT" }
      Segmented {
        visible: host.wayvncInstalled
        width: parent.width
        current: host.vncScope
        options: [
          { id: "local", label: "This PC only" },
          { id: "tailscale", label: "Tailscale", enabled: host.tailscaleIp !== "" },
          { id: "lan", label: "Local network" }
        ]
        onPicked: function(id) { host.chooseVncScope(id) }
      }
      Text {
        width: parent.width
        text: host.vncScope === "local" ? "Only through an SSH tunnel: ssh -L 5900:localhost:" + host.vncPort + " " + host.user + "@<this computer>"
          : host.vncActive ? "Changing this restarts sharing (viewers reconnect)" + (host.ufwEnabled ? " and opens the command terminal for the firewall." : ".")
          : (host.ufwEnabled ? "Turning it on opens the command terminal to open the firewall port." : "")
        visible: text !== "" && host.wayvncInstalled
        wrapMode: Text.Wrap
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: host.vncActive && host.vncFirewall === "any" && host.ufwEnabled
        width: parent.width
        text: "! Port " + host.vncPort + " is open to every network, the internet included (a rule from an older version). Turn sharing off and on again to limit it to private networks."
        wrapMode: Text.Wrap
        color: panel.warnColor
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }

      // Password
      Row {
        visible: host.wayvncInstalled && !tab.editingVncPassword
        width: parent.width
        spacing: Style.space(8)
        Text {
          width: parent.width - pwBtn.width - Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: host.vncPasswordSet ? "Password ••••••••  in your keyring · user “" + host.user + "”" : "No password yet: viewers need one"
          elide: Text.ElideRight
          color: host.vncPasswordSet ? panel.foreground : panel.warnColor
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
        Pill {
          id: pwBtn
          text: host.vncPasswordSet ? "Change" : "Set"
          tint: panel.foreground
          fontFamily: panel.fontFamily
          onClicked: {
            tab.startAfterPassword = false
            tab.editingVncPassword = true
            Qt.callLater(function() { vncPasswordField.forceActiveFocus() })
          }
        }
      }
      Column {
        visible: tab.editingVncPassword
        width: parent.width
        spacing: Style.space(6)
        Text {
          width: parent.width
          text: tab.startAfterPassword ? "Choose the password viewers will type, then sharing starts:" : "New password for viewers:"
          wrapMode: Text.Wrap
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
        Row {
          width: parent.width
          spacing: Style.space(6)
          TextField {
            id: vncPasswordField
            width: parent.width - pwCancel.width - pwSave.width - Style.space(12)
            password: true
            placeholderText: "Password"
            foreground: panel.foreground
            accent: panel.accent
            onAccepted: tab.saveVncPassword()
            Keys.onEscapePressed: {
              tab.editingVncPassword = false
              tab.startAfterPassword = false
            }
          }
          Pill {
            id: pwCancel
            anchors.verticalCenter: parent.verticalCenter
            text: "Cancel"
            tint: panel.foreground
            fontFamily: panel.fontFamily
            onClicked: {
              tab.editingVncPassword = false
              tab.startAfterPassword = false
              vncPasswordField.text = ""
            }
          }
          Pill {
            id: pwSave
            anchors.verticalCenter: parent.verticalCenter
            text: tab.startAfterPassword ? "Start" : "Save"
            filled: true
            tint: panel.accent
            enabled: vncPasswordField.text !== ""
            fontFamily: panel.fontFamily
            onClicked: tab.saveVncPassword()
          }
        }
        Text {
          width: parent.width
          text: "Kept in your GNOME keyring (it may ask to be unlocked)."
          wrapMode: Text.Wrap
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Toggle {
        visible: host.wayvncInstalled
        width: parent.width
        label: "Viewers can control mouse and keyboard"
        description: host.vncActive ? "Changing it restarts sharing." : "Off = view only."
        checked: host.vncAllowControl
        enabled: host.busy === ""
        foreground: panel.foreground
        accent: panel.accent
        fontFamily: panel.fontFamily
        onClicked: host.setVncAllowControl(!host.vncAllowControl)
      }

      SubHeader { visible: host.vncActive; text: "VIEWERS (" + host.vncViewers.length + ")" }
      Text {
        visible: host.vncActive && host.vncViewers.length === 0
        text: "Nobody is connected."
        color: panel.dim
        font.family: panel.fontFamily
        font.pixelSize: Style.font.caption
      }
      Repeater {
        model: host.vncActive ? host.vncViewers : []
        delegate: Rectangle {
          id: viewer
          required property var modelData
          width: vncCard.width
          height: viewerRow.implicitHeight + Style.space(12)
          radius: Style.cornerRadius
          color: Util.alpha(panel.urgent, 0.08)
          Row {
            id: viewerRow
            x: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(20)
            spacing: Style.space(8)
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(8)
              height: width
              radius: width / 2
              color: panel.urgent
            }
            Text {
              width: parent.width - kick.width - Style.space(24)
              anchors.verticalCenter: parent.verticalCenter
              text: viewer.modelData.address
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: panel.foreground
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
            }
            Pill {
              id: kick
              visible: viewer.modelData.id !== ""
              text: "Disconnect"
              tint: panel.urgent
              fontFamily: panel.fontFamily
              onClicked: host.disconnectViewer(viewer.modelData.id)
            }
          }
        }
      }

      SubHeader { visible: host.vncActive; text: "FROM THE OTHER COMPUTER" }
      Repeater {
        model: host.vncActive ? tab.addresses(host.vncScope) : []
        delegate: CommandLine {
          required property string modelData
          width: vncCard.width
          command: "vncviewer " + modelData + "::" + host.vncPort
        }
      }
    }
  }

  Text {
    width: parent.width
    text: "󰆍  Changes that need sudo open a terminal listing every command before anything runs. Turning screen sharing off is instant."
    wrapMode: Text.Wrap
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }
}
