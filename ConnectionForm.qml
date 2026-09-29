import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Add/edit form. Takes over the popup while panel.formId is set ("new" or a
// connection id; panel.formSeed prefills a new one). Labeled fields, a Test
// button that checks the port answers, key or password sign-in, groups as
// chips, and the rarely needed options folded under Advanced.
Column {
  id: form

  property var panel: null
  property var store: null

  readonly property bool isNew: panel.formId === "new"
  property var existing: null

  property string dProtocol: "ssh"
  property string dHost: ""
  property string dPort: ""
  property string dUser: ""
  property string dName: ""
  property string dGroup: ""
  property bool dFavorite: false
  property string dIdentity: ""
  property string dJump: ""
  property string dDomain: ""
  property bool dClipboard: true
  property bool dMultimon: false
  property bool dViewOnly: false
  property string dPassword: ""
  property bool dForgetPassword: false

  property bool showAdvanced: false
  property bool addingGroup: false
  property string error: ""

  spacing: Style.space(10)

  readonly property var groupChoices: {
    var list = Model.groups(store.connections)
    if (dGroup !== "" && list.indexOf(dGroup) < 0) list = list.concat([dGroup])
    return list
  }
  readonly property int effectivePort: {
    var n = parseInt(dPort, 10)
    return isFinite(n) && n > 0 ? n : Model.defaultPort(dProtocol)
  }
  readonly property bool testMatches: store.testResult !== null
    && store.testResult.host === dHost.trim() && String(store.testResult.port) === String(effectivePort)

  function load() {
    var c = isNew ? null : store.find(panel.formId)
    existing = c
    var seed = panel.formSeed || {}
    var d = Model.normalize(c || { host: "x", protocol: seed.protocol || "ssh" })
    dProtocol = d.protocol
    dHost = c ? d.host : (seed.host || "")
    dPort = c && d.port !== Model.defaultPort(d.protocol) ? String(d.port) : ""
    dUser = d.user
    dName = c ? d.name : (seed.name || "")
    dGroup = d.group
    dFavorite = d.favorite
    dIdentity = d.identityFile
    dJump = d.jumpHost
    dDomain = d.rdp.domain
    dClipboard = d.rdp.clipboard
    dMultimon = d.rdp.multimon
    dViewOnly = d.vnc.viewOnly
    dPassword = ""
    dForgetPassword = false
    showAdvanced = dJump !== "" || dDomain !== "" || dMultimon || dViewOnly || !dClipboard
      || (dIdentity !== "" && store.sshKeys.indexOf(dIdentity) < 0)
    addingGroup = false
    error = ""
    Qt.callLater(function() { hostField.forceActiveFocus() })
  }

  Connections {
    target: form.panel
    function onFormIdChanged() { if (form.panel.formId !== "") form.load() }
  }

  function draft() {
    return {
      id: existing ? existing.id : Model.newId(),
      name: dName,
      protocol: dProtocol,
      host: dHost,
      port: dPort,
      user: dUser,
      group: dGroup,
      favorite: dFavorite,
      hasSecret: existing ? existing.hasSecret && !dForgetPassword && dProtocol !== "ssh" : false,
      identityFile: dProtocol === "ssh" ? dIdentity : "",
      jumpHost: dProtocol === "ssh" ? dJump : "",
      rdp: { domain: dDomain, clipboard: dClipboard, multimon: dMultimon },
      vnc: { viewOnly: dViewOnly }
    }
  }

  function save(andConnect) {
    var d = draft()
    var err = Model.validate(d)
    if (err !== "") { error = err; return }
    var saved = store.upsert(d)
    if (!saved) { error = store.lastError; return }
    if (existing && existing.hasSecret && (dForgetPassword || dProtocol === "ssh")) store.clearSecret(saved.id)
    else if (dProtocol !== "ssh" && dPassword !== "") store.storeSecret(saved.id, saved.name, dPassword)
    panel.closeForm()
    if (andConnect && store.connect(saved.id)) panel.close()
  }

  component Label: Text {
    color: form.panel.foreground
    font.family: form.panel.fontFamily
    font.pixelSize: Style.font.caption
  }

  component Hint: Text {
    wrapMode: Text.Wrap
    color: form.panel.dim
    font.family: form.panel.fontFamily
    font.pixelSize: Style.font.caption
  }

  component SubHeader: Text {
    color: form.panel.dim
    font.family: form.panel.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1
  }

  // One selectable line (radio-like), used for the key picker.
  component Choice: Rectangle {
    id: choice
    property string text: ""
    property string detail: ""
    property bool on: false
    signal picked()
    height: choiceRow.implicitHeight + Style.space(14)
    radius: Style.cornerRadius
    color: on ? Util.alpha(form.panel.accent, 0.12) : (choiceMouse.containsMouse ? Util.alpha(form.panel.foreground, 0.04) : "transparent")
    border.width: Style.normalBorderWidth
    border.color: on ? Util.alpha(form.panel.accent, 0.6) : Util.alpha(form.panel.foreground, 0.12)
    Row {
      id: choiceRow
      x: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(20)
      spacing: Style.space(8)
      Text {
        text: choice.on ? "●" : "○"
        color: choice.on ? form.panel.accent : form.panel.dim
        font.family: form.panel.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        width: parent.width - Style.space(20)
        text: choice.text + (choice.detail !== "" ? "   " + choice.detail : "")
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: form.panel.foreground
        font.family: form.panel.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
    MouseArea {
      id: choiceMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: choice.picked()
    }
  }

  // ===== Header =====
  Row {
    width: parent.width
    spacing: Style.space(8)
    Pill {
      anchors.verticalCenter: parent.verticalCenter
      text: "←"
      tooltip: "Back (Esc)"
      tint: panel.foreground
      fontFamily: panel.fontFamily
      onClicked: panel.closeForm()
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: form.isNew ? "New connection" : "Edit connection"
      color: panel.foreground
      font.family: panel.fontFamily
      font.pixelSize: Style.font.title
      font.bold: true
    }
  }

  // ===== Protocol =====
  Row {
    width: parent.width
    spacing: Style.space(6)
    Repeater {
      model: [
        { id: "ssh", label: "SSH", text: "Terminal" },
        { id: "rdp", label: "RDP", text: "Windows desktop" },
        { id: "vnc", label: "VNC", text: "Any desktop" }
      ]
      delegate: Rectangle {
        id: protoCard
        required property var modelData
        readonly property bool on: form.dProtocol === modelData.id
        width: (form.width - Style.space(12)) / 3
        height: protoCol.implicitHeight + Style.space(16)
        radius: Style.cornerRadius
        color: on ? Util.alpha(panel.accent, 0.12) : (protoMouse.containsMouse ? Util.alpha(panel.foreground, 0.04) : "transparent")
        border.width: Style.normalBorderWidth
        border.color: on ? Util.alpha(panel.accent, 0.7) : Util.alpha(panel.foreground, 0.12)
        Column {
          id: protoCol
          x: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(20)
          spacing: Style.space(2)
          Text {
            text: panel.protocolIcons[protoCard.modelData.id]
            color: panel.protocolColors[protoCard.modelData.id]
            font.family: panel.fontFamily
            font.pixelSize: Style.font.title
          }
          Text {
            text: protoCard.modelData.label
            color: panel.foreground
            font.family: panel.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            width: parent.width
            text: protoCard.modelData.text
            elide: Text.ElideRight
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        MouseArea {
          id: protoMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: form.dProtocol = protoCard.modelData.id
        }
      }
    }
  }

  // ===== Server =====
  SubHeader { text: "SERVER" }
  Label { text: "Host" }
  Row {
    width: parent.width
    spacing: Style.space(6)
    TextField {
      id: hostField
      width: parent.width - testBtn.width - Style.space(6)
      placeholderText: "192.168.0.10 or server.example.com"
      text: form.dHost
      foreground: panel.foreground
      accent: panel.accent
      onTextChanged: form.dHost = text
      onAccepted: form.save(false)
      Keys.onEscapePressed: panel.closeForm()
    }
    Pill {
      id: testBtn
      anchors.verticalCenter: parent.verticalCenter
      text: "Test"
      tooltip: "Check that port " + form.effectivePort + " answers (a plain TCP connect)"
      tint: panel.foreground
      enabled: form.dHost.trim() !== "" && !(store.testResult && store.testResult.state === "checking")
      fontFamily: panel.fontFamily
      onClicked: store.testTarget(form.dHost.trim(), form.effectivePort)
    }
  }
  Text {
    visible: form.testMatches
    width: parent.width
    wrapMode: Text.Wrap
    text: !form.testMatches ? ""
      : store.testResult.state === "checking" ? "● Checking port " + form.effectivePort + "…"
      : store.testResult.state === "up" ? "● Port " + form.effectivePort + " answers · " + store.testResult.ms + " ms" + (store.testResult.banner !== "" ? " · " + store.testResult.banner : "")
      : "● No answer on port " + form.effectivePort + " (host down, wrong port, or a firewall in the way)"
    textFormat: Text.PlainText
    color: !form.testMatches ? panel.dim
      : store.testResult.state === "up" ? panel.okColor
      : store.testResult.state === "down" ? panel.urgent : panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }

  Row {
    width: parent.width
    spacing: Style.space(8)
    Column {
      width: (parent.width - Style.space(8)) * 0.62
      spacing: Style.space(4)
      Label { text: "User" }
      TextField {
        width: parent.width
        placeholderText: form.dProtocol === "ssh" ? "same as here" : "optional"
        text: form.dUser
        foreground: panel.foreground
        accent: panel.accent
        onTextChanged: form.dUser = text
        onAccepted: form.save(false)
        Keys.onEscapePressed: panel.closeForm()
      }
    }
    Column {
      width: (parent.width - Style.space(8)) * 0.38
      spacing: Style.space(4)
      Label { text: "Port" }
      TextField {
        width: parent.width
        placeholderText: String(Model.defaultPort(form.dProtocol))
        text: form.dPort
        inputMethodHints: Qt.ImhDigitsOnly
        foreground: panel.foreground
        accent: panel.accent
        onTextChanged: form.dPort = text
        onAccepted: form.save(false)
        Keys.onEscapePressed: panel.closeForm()
      }
    }
  }

  Label { text: "Name" }
  TextField {
    width: parent.width
    placeholderText: form.dHost !== "" ? form.dHost : "defaults to the host"
    text: form.dName
    foreground: panel.foreground
    accent: panel.accent
    onTextChanged: form.dName = text
    onAccepted: form.save(false)
    Keys.onEscapePressed: panel.closeForm()
  }

  // ===== Sign in =====
  SubHeader { text: "SIGN IN WITH" }

  Column {
    visible: form.dProtocol === "ssh"
    width: parent.width
    spacing: Style.space(4)
    Choice {
      width: parent.width
      text: "Automatic"
      detail: "ssh-agent, ~/.ssh/config, or asks for the password"
      on: form.dIdentity === ""
      onPicked: form.dIdentity = ""
    }
    Repeater {
      model: store.sshKeys
      delegate: Choice {
        required property string modelData
        width: form.width
        text: "Key " + modelData
        on: form.dIdentity === modelData
        onPicked: form.dIdentity = modelData
      }
    }
    Row {
      spacing: Style.space(8)
      Pill {
        text: store.sshKeys.length === 0 ? "Create a key and copy it to this server" : "Copy my key to this server"
        iconText: "󰌆"
        tooltip: "Opens a terminal: ssh-keygen (only if you have no key) and ssh-copy-id, shown before they run"
        tint: panel.foreground
        enabled: form.dHost.trim() !== "" && !store.terminalBusy
        fontFamily: panel.fontFamily
        onClicked: {
          var d = Model.normalize(form.draft())
          if (d.name === "") d.name = d.host
          store.setupSshKey(d)
        }
      }
    }
    Hint {
      width: parent.width
      text: "SSH passwords are never stored; ssh asks for them in the terminal."
    }
  }

  Column {
    visible: form.dProtocol !== "ssh"
    width: parent.width
    spacing: Style.space(6)
    TextField {
      visible: !form.dForgetPassword
      width: parent.width
      password: true
      placeholderText: form.existing && form.existing.hasSecret ? "Password saved in keyring · type to replace" : "Password (optional, saved in your keyring)"
      text: form.dPassword
      foreground: panel.foreground
      accent: panel.accent
      onTextChanged: form.dPassword = text
      onAccepted: form.save(false)
      Keys.onEscapePressed: panel.closeForm()
    }
    Toggle {
      visible: form.existing !== null && form.existing.hasSecret
      width: parent.width
      label: "Forget the saved password"
      checked: form.dForgetPassword
      foreground: panel.foreground
      accent: panel.accent
      fontFamily: panel.fontFamily
      onClicked: form.dForgetPassword = !form.dForgetPassword
    }
    Hint {
      width: parent.width
      text: "Left empty, the " + Model.protocolLabel(form.dProtocol) + " client asks each time. Saving may ask to unlock your keyring."
    }
  }

  // ===== Organize =====
  SubHeader { text: "ORGANIZE" }
  Flow {
    width: parent.width
    spacing: Style.space(6)

    Pill {
      text: "No group"
      tint: form.dGroup === "" ? panel.accent : panel.foreground
      bold: form.dGroup === ""
      fontFamily: panel.fontFamily
      onClicked: form.dGroup = ""
    }
    Repeater {
      model: form.groupChoices
      delegate: Pill {
        required property string modelData
        text: modelData
        tint: form.dGroup === modelData ? panel.accent : panel.foreground
        bold: form.dGroup === modelData
        fontFamily: panel.fontFamily
        onClicked: form.dGroup = modelData
      }
    }
    Pill {
      visible: !form.addingGroup
      text: "+ New group"
      tint: panel.dim
      fontFamily: panel.fontFamily
      onClicked: {
        form.addingGroup = true
        Qt.callLater(function() { groupField.forceActiveFocus() })
      }
    }
    TextField {
      id: groupField
      visible: form.addingGroup
      width: Style.space(140)
      placeholderText: "Group name"
      foreground: panel.foreground
      accent: panel.accent
      onAccepted: {
        if (text.trim() !== "") form.dGroup = text.trim()
        text = ""
        form.addingGroup = false
      }
      Keys.onEscapePressed: {
        text = ""
        form.addingGroup = false
      }
    }
  }
  Toggle {
    width: parent.width
    label: "Favorite"
    description: "Keep it at the top of the list"
    checked: form.dFavorite
    foreground: panel.foreground
    accent: panel.accent
    fontFamily: panel.fontFamily
    onClicked: form.dFavorite = !form.dFavorite
  }

  // ===== Advanced =====
  Pill {
    width: parent.width
    text: (form.showAdvanced ? "▾ " : "▸ ") + "Advanced · " + (form.dProtocol === "ssh" ? "jump host, key file" : form.dProtocol === "rdp" ? "domain, clipboard, monitors" : "view only")
    tint: panel.foreground
    bold: false
    fontFamily: panel.fontFamily
    onClicked: form.showAdvanced = !form.showAdvanced
  }

  Column {
    visible: form.showAdvanced
    width: parent.width
    spacing: Style.space(6)

    Label { visible: form.dProtocol === "ssh"; text: "Jump host" }
    TextField {
      visible: form.dProtocol === "ssh"
      width: parent.width
      placeholderText: "user@bastion (ssh -J)"
      text: form.dJump
      foreground: panel.foreground
      accent: panel.accent
      onTextChanged: form.dJump = text
      Keys.onEscapePressed: panel.closeForm()
    }
    Label { visible: form.dProtocol === "ssh"; text: "Key file (if it isn't listed above)" }
    TextField {
      visible: form.dProtocol === "ssh"
      width: parent.width
      placeholderText: "~/.ssh/work_key"
      text: form.dIdentity
      foreground: panel.foreground
      accent: panel.accent
      onTextChanged: form.dIdentity = text
      Keys.onEscapePressed: panel.closeForm()
    }

    Label { visible: form.dProtocol === "rdp"; text: "Domain" }
    TextField {
      visible: form.dProtocol === "rdp"
      width: parent.width
      placeholderText: "optional"
      text: form.dDomain
      foreground: panel.foreground
      accent: panel.accent
      onTextChanged: form.dDomain = text
      Keys.onEscapePressed: panel.closeForm()
    }
    Toggle {
      visible: form.dProtocol === "rdp"
      width: parent.width
      label: "Share clipboard"
      checked: form.dClipboard
      foreground: panel.foreground
      accent: panel.accent
      fontFamily: panel.fontFamily
      onClicked: form.dClipboard = !form.dClipboard
    }
    Toggle {
      visible: form.dProtocol === "rdp"
      width: parent.width
      label: "Use all monitors"
      checked: form.dMultimon
      foreground: panel.foreground
      accent: panel.accent
      fontFamily: panel.fontFamily
      onClicked: form.dMultimon = !form.dMultimon
    }
    Toggle {
      visible: form.dProtocol === "vnc"
      width: parent.width
      label: "View only"
      description: "Don't send keyboard or mouse input"
      checked: form.dViewOnly
      foreground: panel.foreground
      accent: panel.accent
      fontFamily: panel.fontFamily
      onClicked: form.dViewOnly = !form.dViewOnly
    }
  }

  Text {
    visible: form.error !== ""
    width: parent.width
    text: form.error
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: panel.urgent
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }

  // ===== Footer =====
  Row {
    width: parent.width
    spacing: Style.space(6)
    layoutDirection: Qt.RightToLeft
    Pill {
      text: "Save & connect"
      filled: true
      tint: panel.accent
      enabled: form.dHost.trim() !== ""
      fontFamily: panel.fontFamily
      onClicked: form.save(true)
    }
    Pill {
      text: "Save"
      tint: panel.accent
      enabled: form.dHost.trim() !== ""
      fontFamily: panel.fontFamily
      onClicked: form.save(false)
    }
    Pill {
      text: "Cancel"
      tint: panel.foreground
      fontFamily: panel.fontFamily
      onClicked: panel.closeForm()
    }
  }
}
