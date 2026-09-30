import QtQuick
import qs.Commons
import qs.Ui

// Setup (the gear in the popup's header): everything the plugin uses, what
// it's for and whether it's installed. Install or remove one item, or tick
// several and install them together — always through the review sheet
// (exact command, one password).
Column {
  id: view

  property var panel: null
  property var store: null
  property var host: null

  // Package ids ticked for a batch install. Needed-but-missing ones start
  // ticked.
  property var selected: ({})

  spacing: Style.space(10)

  readonly property var catalog: [
    { title: "NEEDED", items: [
      { pkg: "libsecret", name: "Password keyring", required: true,
        note: "Keeps RDP/VNC passwords out of plain files" },
      { pkg: "openssh", name: "SSH client and server", required: true,
        note: "SSH connections · " + store.protocolUse.ssh + " saved" }
    ]},
    { title: "TO CONNECT TO OTHER COMPUTERS", items: [
      { pkg: "freerdp", name: "RDP client", removable: true,
        note: "Windows desktops · " + store.protocolUse.rdp + " saved", needed: store.protocolUse.rdp > 0 },
      { pkg: "tigervnc", name: "VNC viewer", removable: true,
        note: "Other desktops over VNC · " + store.protocolUse.vnc + " saved", needed: store.protocolUse.vnc > 0 }
    ]},
    { title: "TO LET OTHERS REACH THIS COMPUTER", items: [
      { pkg: "wayvnc", name: "Screen sharing server", removable: true,
        note: "Share this Hyprland screen over VNC" },
      { pkg: "ufw", name: "Firewall", recommended: true,
        note: host.ufwEnabled ? "Active · limits who reaches SSH and screen sharing" : "Installed but off: everything you turn on is reachable from every network" },
      { pkg: "tailscale", name: "Tailscale",
        note: host.tailscaleIp !== "" ? "Connected · " + host.tailscaleIp : "Needed for “Tailscale only”; connect it from its bar icon" }
    ]}
  ]

  readonly property var missing: store.managedPackages.filter(function(p) { return store.packages[p] === false })
  readonly property var chosen: missing.filter(function(p) { return view.selected[p] === true })

  function reset() {
    var sel = {}
    store.neededMissing.forEach(function(p) { sel[p] = true })
    selected = sel
  }

  function toggle(pkg) {
    var next = Object.assign({}, selected)
    next[pkg] = !next[pkg]
    selected = next
  }

  function afterChange(ok) {
    host.refresh()
    if (ok) reset()
  }

  Connections {
    target: view.store
    function onPackagesChanged() { if (Object.keys(view.selected).length === 0) view.reset() }
  }

  Text {
    width: parent.width
    text: "Everything the plugin uses. Install only what you need; nothing is installed or removed without the review."
    wrapMode: Text.Wrap
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    visible: store.lastError !== ""
    width: parent.width
    text: store.lastError
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: panel.urgent
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: view.catalog
    delegate: Column {
      id: group
      required property var modelData
      width: view.width
      spacing: Style.space(4)

      PanelSectionHeader {
        text: group.modelData.title
        foreground: panel.foreground
        fontFamily: panel.fontFamily
      }

      Repeater {
        model: group.modelData.items
        delegate: Rectangle {
          id: item
          required property var modelData
          readonly property bool known: store.packagesChecked && store.packages[modelData.pkg] !== undefined
          readonly property bool installed: store.packages[modelData.pkg] === true
          readonly property bool isSelected: !installed && view.selected[modelData.pkg] === true
          width: group.width
          height: itemRow.implicitHeight + Style.space(14)
          radius: Style.cornerRadius
          color: "transparent"
          border.width: Style.normalBorderWidth
          border.color: isSelected ? Util.alpha(panel.accent, 0.55) : Util.alpha(panel.foreground, 0.12)

          Row {
            id: itemRow
            x: Style.space(10)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Style.space(20)
            spacing: Style.space(10)

            // checkbox for missing items, ✓ for installed ones
            Item {
              id: mark
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(16)
              height: width
              Rectangle {
                visible: item.known && !item.installed
                anchors.fill: parent
                radius: Style.space(4)
                color: item.isSelected ? panel.accent : "transparent"
                border.width: Style.normalBorderWidth
                border.color: item.isSelected ? panel.accent : panel.dim
                Text {
                  anchors.centerIn: parent
                  visible: item.isSelected
                  text: "✓"
                  color: Color.background
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: view.toggle(item.modelData.pkg)
                }
              }
              Text {
                visible: item.installed
                anchors.centerIn: parent
                text: "✓"
                color: panel.okColor
                font.family: panel.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            Column {
              width: parent.width - mark.width - actions.width - Style.space(20)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                width: parent.width
                text: item.modelData.name + "  · " + item.modelData.pkg
                  + (item.modelData.required ? " · required" : item.modelData.recommended ? " · recommended" : "")
                elide: Text.ElideRight
                color: panel.foreground
                font.family: panel.fontFamily
                font.pixelSize: Style.font.caption
              }
              Text {
                width: parent.width
                text: !item.known ? "Checking…"
                  : !item.installed && (item.modelData.required || item.modelData.needed) ? "Not installed · " + item.modelData.note
                  : item.modelData.note
                wrapMode: Text.Wrap
                color: item.known && !item.installed && (item.modelData.required || item.modelData.needed) ? panel.warnColor : panel.dim
                font.family: panel.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            Row {
              id: actions
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)
              Pill {
                visible: item.known && !item.installed
                text: "Install"
                tint: panel.accent
                enabled: !store.terminalBusy
                fontFamily: panel.fontFamily
                onClicked: store.installPackages([item.modelData.pkg], view.afterChange)
              }
              Pill {
                visible: item.installed && item.modelData.removable === true
                text: "Remove"
                tint: panel.dim
                enabled: !store.terminalBusy
                fontFamily: panel.fontFamily
                onClicked: store.removePackages([item.modelData.pkg], view.afterChange)
              }
            }
          }
        }
      }
    }
  }

  Rectangle {
    width: parent.width
    height: Style.normalBorderWidth
    color: Util.alpha(panel.foreground, 0.08)
  }

  Row {
    width: parent.width
    spacing: Style.space(8)
    Text {
      width: parent.width - installBtn.width - Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: view.missing.length === 0 ? "Everything is installed."
        : view.chosen.length === 0 ? "Tick what to install, or use each row's button."
        : view.chosen.length + " selected · one review, one password"
      wrapMode: Text.Wrap
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }
    Pill {
      id: installBtn
      visible: view.missing.length > 0
      anchors.verticalCenter: parent.verticalCenter
      filled: true
      tint: panel.accent
      enabled: view.chosen.length > 0 && !store.terminalBusy
      text: view.chosen.length === view.missing.length ? "Install all missing (" + view.missing.length + ")" : "Install selected (" + view.chosen.length + ")"
      fontFamily: panel.fontFamily
      onClicked: store.installPackages(view.chosen, view.afterChange)
    }
  }
}
