import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "vinicgobbi.remote-connections"
  ipcTarget: "vinicgobbi.remote-connections"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string barIcon: "󰒍"
  // Bar icon: urgent while someone is viewing the screen, accent while this
  // machine accepts remote access (SSH server or screen sharing on).
  readonly property bool hostReachable: host.sshActive || host.vncActive
  readonly property color barIconColor: host.screenBeingViewed ? urgent : (hostReachable ? accent : barForeground)
  readonly property var protocolIcons: ({ ssh: "󰣀", rdp: "󰍹", vnc: "󰢹" })
  readonly property string tooltipText: {
    var lines = [store.connections.length === 0
      ? "Remote Connections: nothing saved yet"
      : "Remote Connections: " + store.connections.length + " saved"]
    if (host.screenBeingViewed) lines.push("Your screen is being viewed from " + host.vncClients.join(", "))
    else if (host.vncActive) lines.push("Screen sharing is on")
    if (host.sshActive) lines.push("SSH server is on")
    return lines.join("\n")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      store.refresh()
    } else {
      cancelForm()
      cancelDelete()
      cancelHostConfirm()
      filterText = ""
    }
  }

  property string filterText: ""

  // Flat model for the list: a header row before each group, then the
  // connections in it (favorites are pulled out into their own group).
  readonly property var listRows: {
    var list = Model.sorted(store.connections).filter(function(c) { return Model.matches(c, root.filterText) })
    var rows = []
    var current = null
    for (var i = 0; i < list.length; i++) {
      var c = list[i]
      var group = c.favorite ? "FAVORITES" : (c.group !== "" ? c.group.toUpperCase() : "CONNECTIONS")
      if (group !== current) {
        rows.push({ header: group, conn: null })
        current = group
      }
      rows.push({ header: "", conn: c })
    }
    var sshHosts = Model.unsavedSshHosts(store.connections, store.sshHosts)
      .filter(function(c) { return Model.matches(c, root.filterText) })
    for (var j = 0; j < sshHosts.length; j++) {
      if (j === 0) rows.push({ header: "~/.SSH/CONFIG", conn: null })
      rows.push({ header: "", conn: sshHosts[j] })
    }
    return rows
  }

  // --- Add/edit form state. editingId: "" = closed, "new" = adding. ---
  property string editingId: ""
  property string draftName: ""
  property string draftProtocol: "ssh"
  property string draftHost: ""
  property string draftPort: ""
  property string draftUser: ""
  property string draftGroup: ""
  property string draftIdentity: ""
  property string draftJump: ""
  property string draftDomain: ""
  property bool draftClipboard: true
  property bool draftMultimon: false
  property bool draftViewOnly: false
  property string draftPassword: ""
  property bool draftHasSecret: false
  property bool draftForgetPassword: false
  property string formError: ""

  readonly property bool formOpen: editingId !== ""

  function openForm(c) {
    cancelDelete()
    var d = c || Model.normalize({ host: "-", protocol: "ssh" })
    editingId = c ? c.id : "new"
    draftName = c ? d.name : ""
    draftProtocol = d.protocol
    draftHost = c ? d.host : ""
    draftPort = c && d.port !== Model.defaultPort(d.protocol) ? String(d.port) : ""
    draftUser = d.user
    draftGroup = d.group
    draftIdentity = d.identityFile
    draftJump = d.jumpHost
    draftDomain = d.rdp.domain
    draftClipboard = d.rdp.clipboard
    draftMultimon = d.rdp.multimon
    draftViewOnly = d.vnc.viewOnly
    draftPassword = ""
    draftHasSecret = c ? d.hasSecret : false
    draftForgetPassword = false
    formError = ""
  }

  // Pre-fills a new SSH connection from a ~/.ssh/config host, so it can get
  // a group/favorite. Host stays the alias: ssh still applies the config.
  function saveSshHost(entry) {
    openForm(null)
    draftName = entry.name
    draftHost = entry.host
  }

  function cancelForm() {
    editingId = ""
    draftPassword = ""
    formError = ""
  }

  function submitForm() {
    var draft = {
      protocol: draftProtocol,
      host: draftHost,
      port: draftPort,
      user: draftUser,
      jumpHost: draftJump
    }
    var err = Model.validate(draft)
    if (err !== "") { formError = err; return }

    var existing = editingId === "new" ? null : store.find(editingId)
    var saved = store.upsert({
      id: existing ? existing.id : Model.newId(),
      name: draftName,
      protocol: draftProtocol,
      host: draftHost,
      port: draftPort,
      user: draftUser,
      group: draftGroup,
      favorite: existing ? existing.favorite : false,
      hasSecret: existing ? existing.hasSecret && !draftForgetPassword : false,
      identityFile: draftProtocol === "ssh" ? draftIdentity : "",
      jumpHost: draftProtocol === "ssh" ? draftJump : "",
      rdp: { domain: draftDomain, clipboard: draftClipboard, multimon: draftMultimon },
      vnc: { viewOnly: draftViewOnly }
    })
    if (!saved) { formError = store.lastError; return }

    // SSH never stores a password (keys/agent instead); switching a saved
    // RDP/VNC connection over to SSH drops the one it had.
    var dropSecret = existing && existing.hasSecret && (draftForgetPassword || draftProtocol === "ssh")
    if (dropSecret) store.clearSecret(saved.id)
    else if (draftProtocol !== "ssh" && draftPassword !== "") store.storeSecret(saved.id, saved.name, draftPassword)
    cancelForm()
  }

  // --- Delete confirmation ---
  property string pendingDeleteId: ""

  function requestDelete(c) {
    cancelForm()
    pendingDeleteId = c.id
  }

  function cancelDelete() {
    pendingDeleteId = ""
  }

  function confirmDelete() {
    if (pendingDeleteId !== "") store.remove(pendingDeleteId)
    cancelDelete()
  }

  // --- "This machine": every privileged action is confirmed inline first,
  // with a note that it will ask for the admin password. ---
  // hostConfirm: "" | ssh-on | ssh-off | keys-on | keys-off | vnc-on | vnc-off
  property string hostConfirm: ""
  property string confirmSshScope: "lan"
  property string confirmVncScope: "local"
  property string confirmVncPassword: ""

  readonly property var vncScopeLabels: ({ local: "This computer only", tailscale: "Tailscale", lan: "Local network" })

  function requestHost(what) {
    cancelForm()
    cancelDelete()
    confirmSshScope = host.sshScope === "tailscale" && host.tailscaleIp !== "" ? "tailscale" : "lan"
    confirmVncScope = host.vncScope === "tailscale" && host.tailscaleIp === "" ? "local" : host.vncScope
    confirmVncPassword = ""
    hostConfirm = what
  }

  function cancelHostConfirm() {
    hostConfirm = ""
    confirmVncPassword = ""
  }

  function confirmHost() {
    var what = hostConfirm
    if (what === "ssh-on") host.enableSsh(confirmSshScope)
    else if (what === "ssh-off") host.disableSsh()
    else if (what === "keys-on") host.setKeysOnly(true)
    else if (what === "keys-off") host.setKeysOnly(false)
    else if (what === "vnc-on") {
      if (!host.vncPasswordSet && confirmVncPassword === "") return
      host.startVnc(confirmVncScope, confirmVncPassword)
    } else if (what === "vnc-off") host.stopVnc()
    cancelHostConfirm()
  }

  // Whether confirming `what` will bring up the admin-password dialog.
  function hostNeedsAdmin(what) {
    if (what === "vnc-on") return (confirmVncScope !== "local" && host.ufwEnabled) || host.vncFirewall !== "none"
    if (what === "vnc-off") return host.vncFirewall !== "none"
    return what !== ""
  }

  function hostConfirmText(what) {
    if (what === "ssh-on")
      return "Start the SSH server so you can log in to this machine remotely"
        + (host.ufwEnabled ? ", and open its port in the firewall" : "") + "."
    if (what === "ssh-off") return "Stop the SSH server" + (host.sshFirewall !== "none" ? " and close its firewall port" : "") + "."
    if (what === "keys-on") return "Turn off password logins over SSH. Only the " + host.authorizedKeys + " key(s) in ~/.ssh/authorized_keys will be able to log in."
    if (what === "keys-off") return "Allow password logins over SSH again."
    if (what === "vnc-on") return "Share this screen over VNC. Anyone with the password can see and control it."
    if (what === "vnc-off") return "Stop sharing this screen" + (host.vncFirewall !== "none" ? " and close its firewall port" : "") + "."
    return ""
  }

  // Where to reach this machine, given the firewall scope in effect.
  function hostAddresses(scope) {
    if (scope === "local") return ["127.0.0.1"]
    if (scope === "tailscale") return host.tailscaleIp !== "" ? [host.tailscaleIp] : []
    return host.lanIps.concat(host.tailscaleIp !== "" ? [host.tailscaleIp] : [])
  }

  function connectTo(c) {
    if (store.connect(c.id)) root.close()
  }

  // Inline confirmation shared by every host action: what will happen and,
  // when it applies, that the admin-password dialog comes next. Shown right
  // under the row it belongs to.
  Component {
    id: hostConfirmBox
    Rectangle {
      width: parent ? parent.width : 0
      radius: Style.cornerRadius
      color: "transparent"
      border.width: Style.normalBorderWidth
      border.color: root.accent
      height: hostConfirmColumn.implicitHeight + Style.space(20)

      Column {
        id: hostConfirmColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(6)

        Text {
          width: parent.width
          text: root.hostConfirmText(root.hostConfirm)
          wrapMode: Text.Wrap
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          visible: root.hostNeedsAdmin(root.hostConfirm)
          width: parent.width
          text: "󰌾 This will ask for your admin password."
          wrapMode: Text.Wrap
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          anchors.right: parent.right
          spacing: Style.space(6)

          PanelActionButton {
            iconText: "󰅖"
            tooltipText: "Cancel"
            foreground: root.foreground
            hoverColor: root.urgent
            fontFamily: root.fontFamily
            onClicked: root.cancelHostConfirm()
          }

          PanelActionButton {
            enabled: root.hostConfirm !== "vnc-on" || host.vncPasswordSet || root.confirmVncPassword !== ""
            iconText: "󰄬"
            tooltipText: "Confirm"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.confirmHost()
          }
        }
      }
    }
  }

  ConnectionStore {
    id: store
  }

  HostService {
    id: host
    store: store
    panelOpen: root.opened
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.statusSlot
    tooltipText: root.tooltipText
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: root.barIcon
          color: root.barIconColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
        }
      }
    }
    onPressed: function(code) { if (code === Qt.LeftButton) root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: {
        if (root.formOpen) root.cancelForm()
        else if (root.pendingDeleteId !== "") root.cancelDelete()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "n" || t === "N") root.openForm(null)
        else if (t === "/") filterField.forceActiveFocus()
      }

      Flickable {
        anchors.fill: parent
        contentWidth: width; contentHeight: content.implicitHeight
        clip: true; boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: parent.width
          spacing: Style.space(14)

          // --- Title + add button ---
          Row {
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width - addButton.width - Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: "Remote Connections"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            PanelActionButton {
              id: addButton
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰐕"
              tooltipText: "Add connection (n)"
              foreground: root.foreground
              hoverColor: root.accent
              fontFamily: root.fontFamily
              enabled: !root.formOpen && store.writable
              onClicked: root.openForm(null)
            }
          }

          Text {
            visible: store.lastError !== ""
            width: parent.width
            text: store.lastError
            textFormat: Text.PlainText
            color: root.urgent
            wrapMode: Text.Wrap
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // --- Add/edit form ---
          Rectangle {
            width: parent.width
            visible: root.formOpen
            radius: Style.cornerRadius
            color: "transparent"
            border.width: Style.normalBorderWidth
            border.color: root.accent
            height: formColumn.implicitHeight + Style.space(20)

            Column {
              id: formColumn
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(10)
              anchors.rightMargin: Style.space(10)
              spacing: Style.space(6)

              PanelSectionHeader {
                text: root.editingId === "new" ? "NEW CONNECTION" : "EDIT CONNECTION"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                Repeater {
                  model: Model.PROTOCOLS
                  delegate: Button {
                    required property string modelData
                    width: (formColumn.width - Style.space(12)) / 3
                    text: Model.protocolLabel(modelData)
                    iconText: root.protocolIcons[modelData]
                    selected: root.draftProtocol === modelData
                    bordered: true
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    onClicked: root.draftProtocol = modelData
                  }
                }
              }

              TextField {
                id: hostField
                width: parent.width
                placeholderText: "Host or IP"
                text: root.draftHost
                foreground: root.foreground
                accent: root.accent
                onTextChanged: root.draftHost = text
                onAccepted: root.submitForm()
                Keys.onEscapePressed: root.cancelForm()
                onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                TextField {
                  width: (parent.width - Style.space(6)) * 0.62
                  placeholderText: "User (optional)"
                  text: root.draftUser
                  foreground: root.foreground
                  accent: root.accent
                  onTextChanged: root.draftUser = text
                  onAccepted: root.submitForm()
                  Keys.onEscapePressed: root.cancelForm()
                }

                TextField {
                  width: (parent.width - Style.space(6)) * 0.38
                  placeholderText: "Port " + Model.defaultPort(root.draftProtocol)
                  text: root.draftPort
                  inputMethodHints: Qt.ImhDigitsOnly
                  foreground: root.foreground
                  accent: root.accent
                  onTextChanged: root.draftPort = text
                  onAccepted: root.submitForm()
                  Keys.onEscapePressed: root.cancelForm()
                }
              }

              TextField {
                width: parent.width
                placeholderText: "Name (defaults to host)"
                text: root.draftName
                foreground: root.foreground
                accent: root.accent
                onTextChanged: root.draftName = text
                onAccepted: root.submitForm()
                Keys.onEscapePressed: root.cancelForm()
              }

              TextField {
                width: parent.width
                placeholderText: "Group (optional)"
                text: root.draftGroup
                foreground: root.foreground
                accent: root.accent
                onTextChanged: root.draftGroup = text
                onAccepted: root.submitForm()
                Keys.onEscapePressed: root.cancelForm()
              }

              // --- SSH-only ---
              TextField {
                visible: root.draftProtocol === "ssh"
                width: parent.width
                placeholderText: "Identity file, e.g. ~/.ssh/id_ed25519 (optional)"
                text: root.draftIdentity
                foreground: root.foreground
                accent: root.accent
                onTextChanged: root.draftIdentity = text
                onAccepted: root.submitForm()
                Keys.onEscapePressed: root.cancelForm()
              }

              TextField {
                visible: root.draftProtocol === "ssh"
                width: parent.width
                placeholderText: "Jump host, e.g. user@bastion (optional)"
                text: root.draftJump
                foreground: root.foreground
                accent: root.accent
                onTextChanged: root.draftJump = text
                onAccepted: root.submitForm()
                Keys.onEscapePressed: root.cancelForm()
              }

              Text {
                visible: root.draftProtocol === "ssh"
                width: parent.width
                text: "SSH passwords aren't stored. Use a key: ssh-keygen, then ssh-copy-id user@host."
                wrapMode: Text.Wrap
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              // --- RDP-only ---
              TextField {
                visible: root.draftProtocol === "rdp"
                width: parent.width
                placeholderText: "Domain (optional)"
                text: root.draftDomain
                foreground: root.foreground
                accent: root.accent
                onTextChanged: root.draftDomain = text
                onAccepted: root.submitForm()
                Keys.onEscapePressed: root.cancelForm()
              }

              Toggle {
                visible: root.draftProtocol === "rdp"
                width: parent.width
                label: "Share clipboard"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                checked: root.draftClipboard
                onClicked: root.draftClipboard = !root.draftClipboard
              }

              Toggle {
                visible: root.draftProtocol === "rdp"
                width: parent.width
                label: "Use all monitors"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                checked: root.draftMultimon
                onClicked: root.draftMultimon = !root.draftMultimon
              }

              // --- VNC-only ---
              Toggle {
                visible: root.draftProtocol === "vnc"
                width: parent.width
                label: "View only"
                description: "Don't send keyboard or mouse input."
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                checked: root.draftViewOnly
                onClicked: root.draftViewOnly = !root.draftViewOnly
              }

              // --- Password (RDP/VNC) → keyring ---
              TextField {
                visible: root.draftProtocol !== "ssh" && !root.draftForgetPassword
                width: parent.width
                placeholderText: root.draftHasSecret ? "Password saved — type to replace" : "Password (optional, saved in keyring)"
                password: true
                text: root.draftPassword
                foreground: root.foreground
                accent: root.accent
                onTextChanged: root.draftPassword = text
                onAccepted: root.submitForm()
                Keys.onEscapePressed: root.cancelForm()
              }

              Toggle {
                visible: root.draftProtocol !== "ssh" && root.draftHasSecret
                width: parent.width
                label: "Forget saved password"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                checked: root.draftForgetPassword
                onClicked: root.draftForgetPassword = !root.draftForgetPassword
              }

              Text {
                visible: root.draftProtocol !== "ssh" && root.draftPassword !== ""
                width: parent.width
                text: "Your keyring may ask to be unlocked to save it."
                wrapMode: Text.Wrap
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                visible: root.formError !== ""
                width: parent.width
                text: root.formError
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Row {
                anchors.right: parent.right
                spacing: Style.space(6)

                PanelActionButton {
                  iconText: "󰅖"
                  tooltipText: "Cancel"
                  foreground: root.foreground
                  hoverColor: root.urgent
                  fontFamily: root.fontFamily
                  onClicked: root.cancelForm()
                }

                PanelActionButton {
                  enabled: root.draftHost.trim() !== ""
                  iconText: "󰄬"
                  tooltipText: "Save"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.submitForm()
                }
              }
            }
          }

          // --- Filter ---
          TextField {
            id: filterField
            visible: (store.connections.length > 0 || store.sshHosts.length > 0) && !root.formOpen
            width: parent.width
            placeholderText: "Filter (/)"
            text: root.filterText
            foreground: root.foreground
            accent: root.accent
            onTextChanged: root.filterText = text
            Keys.onEscapePressed: {
              if (text !== "") text = ""
              else keys.forceActiveFocus()
            }
            onAccepted: {
              var first = root.listRows.filter(function(r) { return r.conn })[0]
              if (first) root.connectTo(first.conn)
            }
          }

          // --- Empty state ---
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: store.loaded && store.connections.length === 0 && store.sshHosts.length === 0 && !root.formOpen

            Text {
              width: parent.width
              text: "No saved connections yet."
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              width: parent.width
              text: "Add one with + (or press n). SSH works right away; RDP needs the 'freerdp' package and VNC needs 'tigervnc' — you'll be offered to install them the first time."
              wrapMode: Text.Wrap
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Text {
            visible: root.filterText !== "" && root.listRows.length === 0
            width: parent.width
            text: "Nothing matches “" + root.filterText + "”."
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // --- Connection list ---
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: !root.formOpen

            Repeater {
              model: root.listRows
              delegate: Column {
                id: rowItem
                required property var modelData
                readonly property var conn: modelData.conn
                readonly property bool clientMissing: conn !== null && store.clientsChecked && !store.hasClient(conn.protocol)
                readonly property bool fromSshConfig: Model.isSshConfigEntry(conn)
                width: content.width
                spacing: Style.space(6)

                PanelSectionHeader {
                  visible: rowItem.modelData.header !== ""
                  text: rowItem.modelData.header
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                CursorSurface {
                  visible: rowItem.conn !== null
                  width: parent.width
                  height: rowColumn.implicitHeight + Style.space(16)
                  hasCursor: rowHover.hovered
                  foreground: root.foreground
                  accent: root.accent

                  HoverHandler { id: rowHover }

                  // Click anywhere on the row (outside the buttons) to connect.
                  MouseArea {
                    anchors.fill: parent
                    enabled: rowItem.conn !== null && !rowItem.clientMissing && root.pendingDeleteId !== rowItem.conn.id
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.connectTo(rowItem.conn)
                  }

                  Column {
                    id: rowColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(6)
                    spacing: Style.space(6)

                    Row {
                      width: parent.width
                      spacing: Style.space(10)

                      Text {
                        id: protoIcon
                        anchors.verticalCenter: parent.verticalCenter
                        text: rowItem.conn ? root.protocolIcons[rowItem.conn.protocol] : ""
                        color: rowItem.clientMissing ? root.dim : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.title
                      }

                      Column {
                        width: parent.width - protoIcon.width - rowActions.width - Style.space(20)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        Text {
                          width: parent.width
                          text: rowItem.conn ? rowItem.conn.name : ""
                          textFormat: Text.PlainText
                          color: root.foreground
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.body
                          elide: Text.ElideRight
                        }
                        Text {
                          width: parent.width
                          text: !rowItem.conn ? ""
                            : rowItem.clientMissing ? "Needs the '" + Model.clientPackage(rowItem.conn.protocol) + "' package"
                            : Model.subtitle(rowItem.conn) + (rowItem.conn.hasSecret ? " · 󰌾" : "")
                          textFormat: Text.PlainText
                          color: rowItem.clientMissing ? root.urgent : root.dim
                          font.family: root.fontFamily
                          font.pixelSize: Style.font.caption
                          elide: Text.ElideRight
                        }
                      }

                      Row {
                        id: rowActions
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(2)

                        PanelActionButton {
                          visible: rowItem.fromSshConfig
                          iconText: "󰆓"
                          tooltipText: "Save as connection (to add a group or favorite)"
                          foreground: root.foreground
                          hoverColor: root.accent
                          fontFamily: root.fontFamily
                          enabled: store.writable
                          onClicked: root.saveSshHost(rowItem.conn)
                        }

                        PanelActionButton {
                          visible: !rowItem.fromSshConfig
                          iconText: rowItem.conn && rowItem.conn.favorite ? "󰓎" : "󰓒"
                          tooltipText: rowItem.conn && rowItem.conn.favorite ? "Unfavorite" : "Favorite"
                          foreground: rowItem.conn && rowItem.conn.favorite ? root.accent : root.dim
                          hoverColor: root.accent
                          fontFamily: root.fontFamily
                          onClicked: store.toggleFavorite(rowItem.conn.id)
                        }

                        PanelActionButton {
                          visible: !rowItem.fromSshConfig
                          iconText: "󰏫"
                          tooltipText: "Edit"
                          foreground: root.foreground
                          hoverColor: root.foreground
                          fontFamily: root.fontFamily
                          enabled: store.writable
                          onClicked: root.openForm(rowItem.conn)
                        }

                        PanelActionButton {
                          visible: !rowItem.fromSshConfig
                          iconText: "󰆴"
                          tooltipText: "Delete"
                          foreground: root.foreground
                          hoverColor: root.urgent
                          fontFamily: root.fontFamily
                          enabled: store.writable
                          onClicked: root.requestDelete(rowItem.conn)
                        }

                        PanelActionButton {
                          iconText: rowItem.clientMissing ? "󰇚" : "󰌘"
                          tooltipText: rowItem.clientMissing
                            ? "Install " + Model.clientPackage(rowItem.conn ? rowItem.conn.protocol : "") + " (asks for your password in a terminal)"
                            : "Connect"
                          foreground: rowItem.clientMissing ? root.urgent : root.accent
                          hoverColor: root.accent
                          fontFamily: root.fontFamily
                          onClicked: {
                            if (rowItem.clientMissing) {
                              store.installClient(rowItem.conn.protocol)
                              root.close()
                            } else {
                              root.connectTo(rowItem.conn)
                            }
                          }
                        }
                      }
                    }

                    // --- inline delete confirmation ---
                    Column {
                      width: parent.width
                      spacing: Style.space(6)
                      visible: rowItem.conn !== null && root.pendingDeleteId === rowItem.conn.id

                      PanelSeparator {
                        foreground: root.foreground
                      }

                      Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: rowItem.conn
                          ? "Delete “" + rowItem.conn.name + "”?" + (rowItem.conn.hasSecret ? " Its saved password is removed from the keyring too." : "")
                          : ""
                        wrapMode: Text.Wrap
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }

                      Row {
                        anchors.right: parent.right
                        spacing: Style.space(6)

                        PanelActionButton {
                          iconText: "󰅖"
                          tooltipText: "Cancel"
                          foreground: root.foreground
                          hoverColor: root.foreground
                          fontFamily: root.fontFamily
                          onClicked: root.cancelDelete()
                        }

                        PanelActionButton {
                          iconText: "󰆴"
                          tooltipText: "Delete"
                          foreground: root.foreground
                          hoverColor: root.urgent
                          fontFamily: root.fontFamily
                          onClicked: root.confirmDelete()
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          // --- THIS MACHINE: SSH server + screen sharing ---
          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: !root.formOpen && host.loaded

            PanelSeparator {
              foreground: root.foreground
            }

            PanelSectionHeader {
              text: "THIS MACHINE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: host.lastError !== ""
              width: parent.width
              text: host.lastError
              textFormat: Text.PlainText
              color: root.urgent
              wrapMode: Text.Wrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            // --- SSH server row ---
            CursorSurface {
              width: parent.width
              height: Style.space(46)
              hasCursor: sshRowHover.hovered
              foreground: root.foreground
              accent: root.accent

              HoverHandler { id: sshRowHover }

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(10)

                Column {
                  width: parent.width - sshSwitch.width - Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0
                  Text {
                    width: parent.width
                    text: "SSH server"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: !host.sshInstalled ? "openssh isn't installed"
                      : !host.sshActive ? "Off — nobody can log in to this machine over SSH"
                      : "On · " + (host.sshFirewall === "tailscale" ? "Tailscale only"
                                   : host.sshFirewall === "lan" ? "local network"
                                   : host.ufwEnabled ? "blocked by the firewall" : "any network (firewall off)")
                        + (host.sshKeysOnly ? " · keys only" : "")
                    color: host.sshActive && host.sshFirewall === "none" && host.ufwEnabled ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                ToggleSwitch {
                  id: sshSwitch
                  anchors.verticalCenter: parent.verticalCenter
                  checked: host.sshActive
                  busy: host.busy === "ssh"
                  interactive: host.sshInstalled && host.busy === ""
                  foreground: root.foreground
                  accent: root.accent
                  onToggled: root.requestHost(host.sshActive ? "ssh-off" : "ssh-on")
                }
              }
            }

            // SSH scope picker (only when turning it on)
            Row {
              visible: root.hostConfirm === "ssh-on"
              width: parent.width
              spacing: Style.space(6)

              Button {
                width: (parent.width - Style.space(6)) / 2
                text: "Local network"
                selected: root.confirmSshScope === "lan"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: root.confirmSshScope = "lan"
              }
              Button {
                width: (parent.width - Style.space(6)) / 2
                text: host.tailscaleIp !== "" ? "Tailscale only" : "Tailscale (not connected)"
                enabled: host.tailscaleIp !== ""
                selected: root.confirmSshScope === "tailscale"
                bordered: true
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.caption
                onClicked: root.confirmSshScope = "tailscale"
              }
            }

            // Where to connect from, once it's on.
            Repeater {
              model: host.sshActive ? root.hostAddresses(host.sshFirewall === "none" ? "lan" : host.sshFirewall) : []
              delegate: Row {
                required property string modelData
                readonly property string command: "ssh " + host.user + "@" + modelData
                width: parent.width
                spacing: Style.space(6)
                Text {
                  width: parent.width - copySsh.width - Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  leftPadding: Style.space(10)
                  text: parent.command
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
                PanelActionButton {
                  id: copySsh
                  iconText: "󰆏"
                  tooltipText: "Copy"
                  foreground: root.dim
                  hoverColor: root.accent
                  fontFamily: root.fontFamily
                  onClicked: store.copyText(parent.command)
                }
              }
            }

            Toggle {
              visible: host.sshActive
              width: parent.width
              label: "Keys only"
              description: host.authorizedKeys === 0
                ? "Add a public key to ~/.ssh/authorized_keys first (ssh-copy-id from the other machine), or you'd lock yourself out."
                : "Turn off password logins; " + host.authorizedKeys + " key(s) in ~/.ssh/authorized_keys."
              enabled: host.busy === "" && (host.sshKeysOnly || host.authorizedKeys > 0)
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              checked: host.sshKeysOnly
              onClicked: root.requestHost(host.sshKeysOnly ? "keys-off" : "keys-on")
            }

            Loader {
              width: parent.width
              active: root.hostConfirm === "ssh-on" || root.hostConfirm === "ssh-off" || root.hostConfirm === "keys-on" || root.hostConfirm === "keys-off"
              visible: active
              sourceComponent: hostConfirmBox
            }

            // --- Screen sharing row ---
            CursorSurface {
              width: parent.width
              height: Style.space(46)
              hasCursor: vncRowHover.hovered
              foreground: root.foreground
              accent: root.accent

              HoverHandler { id: vncRowHover }

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(10)

                Column {
                  width: parent.width - vncControl.width - Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0
                  Text {
                    width: parent.width
                    text: "Screen sharing (VNC)"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    text: !host.wayvncInstalled ? "Needs the 'wayvnc' package"
                      : !host.vncActive ? "Off"
                      : host.screenBeingViewed ? "Being viewed from " + host.vncClients.join(", ")
                      : "On · " + root.vncScopeLabels[host.vncScope] + " · port " + host.vncPort + " · no viewers"
                    color: !host.wayvncInstalled || host.screenBeingViewed ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Item {
                  id: vncControl
                  anchors.verticalCenter: parent.verticalCenter
                  width: host.wayvncInstalled ? vncSwitch.width : vncInstall.width
                  height: Math.max(vncSwitch.height, vncInstall.height)

                  ToggleSwitch {
                    id: vncSwitch
                    visible: host.wayvncInstalled
                    anchors.centerIn: parent
                    checked: host.vncActive
                    busy: host.busy === "vnc"
                    interactive: host.busy === ""
                    foreground: root.foreground
                    accent: root.accent
                    onToggled: root.requestHost(host.vncActive ? "vnc-off" : "vnc-on")
                  }

                  PanelActionButton {
                    id: vncInstall
                    visible: !host.wayvncInstalled
                    anchors.centerIn: parent
                    iconText: "󰇚"
                    tooltipText: "Install wayvnc (asks for your password in a terminal)"
                    foreground: root.urgent
                    hoverColor: root.accent
                    fontFamily: root.fontFamily
                    onClicked: {
                      host.installPackage("wayvnc")
                      root.close()
                    }
                  }
                }
              }
            }

            // Screen-sharing options (only when turning it on)
            Column {
              visible: root.hostConfirm === "vnc-on"
              width: parent.width
              spacing: Style.space(6)

              Row {
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: ["local", "tailscale", "lan"]
                  delegate: Button {
                    required property string modelData
                    width: (parent.width - Style.space(12)) / 3
                    text: root.vncScopeLabels[modelData]
                    enabled: modelData !== "tailscale" || host.tailscaleIp !== ""
                    selected: root.confirmVncScope === modelData
                    bordered: true
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.caption
                    onClicked: root.confirmVncScope = modelData
                  }
                }
              }

              Text {
                width: parent.width
                text: root.confirmVncScope === "local"
                  ? "Only reachable from this computer — e.g. through an SSH tunnel: ssh -L 5900:localhost:" + host.vncPort + " " + host.user + "@<this machine>"
                  : root.confirmVncScope === "tailscale" ? "Reachable from devices on your tailnet."
                  : "Reachable from any device on the networks you're connected to."
                wrapMode: Text.Wrap
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              TextField {
                width: parent.width
                placeholderText: host.vncPasswordSet ? "Password saved — type to change it" : "Password viewers must type (required)"
                password: true
                text: root.confirmVncPassword
                foreground: root.foreground
                accent: root.accent
                onTextChanged: root.confirmVncPassword = text
                onAccepted: root.confirmHost()
                Keys.onEscapePressed: root.cancelHostConfirm()
              }

              Text {
                width: parent.width
                text: "Viewers log in as “" + host.user + "” with this password; it's kept in your keyring (which may ask to be unlocked)."
                wrapMode: Text.Wrap
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Loader {
              width: parent.width
              active: root.hostConfirm === "vnc-on" || root.hostConfirm === "vnc-off"
              visible: active
              sourceComponent: hostConfirmBox
            }

            // How to connect + disconnect viewers, once it's on.
            Repeater {
              model: host.vncActive ? root.hostAddresses(host.vncScope) : []
              delegate: Row {
                required property string modelData
                readonly property string command: "vncviewer " + modelData + "::" + host.vncPort
                width: parent.width
                spacing: Style.space(6)
                Text {
                  width: parent.width - copyVnc.width - Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  leftPadding: Style.space(10)
                  text: parent.command + "  (user: " + host.user + ")"
                  textFormat: Text.PlainText
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
                PanelActionButton {
                  id: copyVnc
                  iconText: "󰆏"
                  tooltipText: "Copy"
                  foreground: root.dim
                  hoverColor: root.accent
                  fontFamily: root.fontFamily
                  onClicked: store.copyText(parent.command)
                }
              }
            }

            Button {
              visible: host.screenBeingViewed
              width: parent.width
              text: "Disconnect all viewers"
              iconText: "󰅖"
              bordered: true
              foreground: root.urgent
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              enabled: host.busy === ""
              onClicked: host.disconnectVncClients()
            }

            Text {
              visible: !host.ufwEnabled && (host.sshActive || (host.vncActive && host.vncScope !== "local"))
              width: parent.width
              text: "The firewall (ufw) is off, so anything turned on here is reachable from every network you're on."
              wrapMode: Text.Wrap
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

        }
      }
    }
  }
}
