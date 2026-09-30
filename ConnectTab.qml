import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// "Connect" tab: search + protocol chips, then the connections in sections
// (recent, favorites, groups, ~/.ssh/config). The row under the mouse, or
// the one picked with ↑/↓, shows its actions; everything else shows reachability and when it was
// last used. With nothing saved yet, it shows the first-run cards instead.
Column {
  id: tab

  property var panel: null
  property var store: null
  property var flickable: null

  property string query: ""
  property string protoFilter: ""        // "" | ssh | rdp | vnc
  // Keyboard cursor (↑/↓). The mouse doesn't set it: hovering highlights a
  // row only while the pointer is on it (hoveredId), and moving over the
  // list hands the highlight back to the mouse.
  property string selectedId: ""
  property string hoveredId: ""
  property string menuId: ""             // row whose ⋯ actions are open
  property string pendingDeleteId: ""
  property string copiedId: ""
  property real now: Date.now()

  readonly property var sections: Model.connectSections(store.connections, store.sshHosts, query, protoFilter)
  readonly property var flatRows: {
    var out = []
    for (var i = 0; i < sections.length; i++) out = out.concat(sections[i].rows)
    return out
  }
  readonly property var counts: Model.protocolCounts(store.connections, store.sshHosts)
  readonly property bool firstRun: store.loaded && store.connections.length === 0 && store.sshHosts.length === 0

  spacing: Style.space(10)

  function reset() {
    query = ""
    protoFilter = ""
    menuId = ""
    pendingDeleteId = ""
    selectedId = ""
    hoveredId = ""
    searchField.text = ""
  }

  // Closes the ⋯ actions and the delete confirmation (tab switch, form).
  function closeMenus() {
    menuId = ""
    pendingDeleteId = ""
    selectedId = ""
    hoveredId = ""
  }

  function toggleMenu(id) {
    pendingDeleteId = ""
    menuId = menuId === id ? "" : id
  }

  // Esc peels one layer at a time; returns false when there's nothing left
  // to close so the popup itself closes.
  function handleEscape() {
    if (pendingDeleteId !== "") { pendingDeleteId = ""; return true }
    if (menuId !== "") { menuId = ""; return true }
    if (query !== "" || protoFilter !== "") { searchField.text = ""; protoFilter = ""; return true }
    return false
  }

  // The row keyboard shortcuts act on: the open menu's, the keyboard
  // cursor's, or the one under the mouse.
  readonly property string activeId: menuId !== "" ? menuId : (selectedId !== "" ? selectedId : hoveredId)

  function indexOfSelected() {
    for (var i = 0; i < flatRows.length; i++) if (flatRows[i].id === activeId) return i
    return -1
  }

  function selected() {
    var i = indexOfSelected()
    return i >= 0 ? flatRows[i] : null
  }

  function moveCursor(dy) {
    if (flatRows.length === 0) return
    var i = indexOfSelected()
    i = i < 0 ? (dy > 0 ? 0 : flatRows.length - 1) : Math.max(0, Math.min(flatRows.length - 1, i + dy))
    selectedId = flatRows[i].id
    hoveredId = ""
    menuId = ""
  }

  function activateCursor() {
    var c = selected() || flatRows[0]
    if (c) primaryAction(c)
  }

  function deleteCursor() {
    var c = selected()
    if (c && !Model.isSshConfigEntry(c)) { menuId = ""; pendingDeleteId = c.id }
  }

  function textKey(t) {
    var c = selected()
    if (t === "/") searchField.forceActiveFocus()
    else if (!c) return
    else if (t === "e" && !Model.isSshConfigEntry(c)) panel.openForm(c.id, null)
    else if (t === "f" && !Model.isSshConfigEntry(c)) store.toggleFavorite(c.id)
    else if (t === "c") copyAddress(c)
    else if (t === ".") toggleMenu(c.id)
  }

  function clientMissing(c) {
    return store.clientsChecked && !store.hasClient(c.protocol)
  }

  function primaryAction(c) {
    if (clientMissing(c)) {
      store.installClient(c.protocol)
      panel.close()
    } else if (store.connect(c.id)) {
      panel.close()
    }
  }

  function copyAddress(c) {
    store.copyText(Model.isSshConfigEntry(c) ? c.host : Model.address(c))
    copiedId = c.id
    copiedTimer.restart()
  }

  function statusText(c) {
    var r = store.reachOf(c.id)
    if (r.state === "up") return "● up · " + r.ms + " ms"
    if (r.state === "down") return "● down"
    if (r.state === "checking") return "● …"
    return c.jumpHost ? "via " + c.jumpHost : ""
  }

  function statusColor(c) {
    var r = store.reachOf(c.id)
    return r.state === "up" ? panel.okColor : (r.state === "down" ? panel.urgent : panel.dim)
  }

  function subtitle(c) {
    if (clientMissing(c)) return "Needs " + Model.clientPackage(c.protocol) + " · " + Model.address(c)
    return Model.subtitle(c) + (c.hasSecret ? " · 󰌾" : "")
  }

  Timer {
    id: copiedTimer
    interval: 1500
    onTriggered: tab.copiedId = ""
  }

  Timer {
    interval: 30000
    repeat: true
    running: tab.visible
    onTriggered: tab.now = Date.now()
  }

  onVisibleChanged: if (visible) now = Date.now()

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

  // ===== First run =====
  Column {
    visible: tab.firstRun
    width: parent.width
    spacing: Style.space(8)

    Text {
      width: parent.width
      text: "Reach your servers with one click, and let others reach this computer when you choose to."
      wrapMode: Text.Wrap
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: [
        { icon: "󰐕", title: "Add a connection", text: "SSH, RDP (Windows) or VNC. Passwords stay in your keyring.", action: "new" },
        { icon: "󰒃", title: "Let others reach this computer", text: "SSH and screen sharing are off. Turn them on for your local network or Tailscale only; you'll see every command first.", action: "machine" }
      ]
      delegate: CursorSurface {
        id: card
        required property var modelData
        width: parent.width
        height: cardRow.implicitHeight + Style.space(20)
        hasCursor: cardHover.hovered
        foreground: panel.foreground
        accent: panel.accent

        HoverHandler { id: cardHover }

        Row {
          id: cardRow
          x: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(24)
          spacing: Style.space(12)

          Rectangle {
            width: Style.space(34)
            height: width
            radius: Style.cornerRadius
            color: Util.alpha(panel.accent, 0.14)
            Text {
              anchors.centerIn: parent
              text: card.modelData.icon
              color: panel.accent
              font.family: panel.fontFamily
              font.pixelSize: Style.font.title
            }
          }

          Column {
            width: parent.width - Style.space(46)
            spacing: Style.space(3)
            Text {
              text: card.modelData.title
              color: panel.foreground
              font.family: panel.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              width: parent.width
              text: card.modelData.text
              wrapMode: Text.Wrap
              color: panel.dim
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: card.modelData.action === "new" ? panel.openForm("new", null) : panel.showTab("machine")
        }
      }
    }

    Rectangle {
      width: parent.width
      height: tipColumn.implicitHeight + Style.space(20)
      radius: Style.cornerRadius
      color: Util.alpha(panel.foreground, 0.05)

      Column {
        id: tipColumn
        x: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Style.space(24)
        spacing: Style.space(6)

        Text {
          width: parent.width
          text: "Tip · open Quick connect from anywhere with a shortcut. Add this line to ~/.config/hypr/bindings.lua (the plugin never edits your config):"
          wrapMode: Text.Wrap
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }

        Row {
          width: parent.width
          spacing: Style.space(6)
          Text {
            id: bindLine
            width: parent.width - copyBind.width - Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: 'o.bind("SUPER + ALT + R", "Remote connections", "omarchy-shell shell toggle vinicgobbi.remote-connections")'
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: panel.accent
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }
          Pill {
            id: copyBind
            text: tab.copiedId === "bind" ? "Copied" : "Copy"
            tint: panel.foreground
            fontFamily: panel.fontFamily
            onClicked: {
              store.copyText(bindLine.text)
              tab.copiedId = "bind"
              copiedTimer.restart()
            }
          }
        }
      }
    }
  }

  // ===== Active sessions: always a way out of a window holding the keyboard =====
  Column {
    visible: store.sessions.length > 0
    width: parent.width
    spacing: Style.space(4)

    PanelSectionHeader {
      text: "ACTIVE"
      foreground: panel.foreground
      fontFamily: panel.fontFamily
    }

    Repeater {
      model: store.sessions
      delegate: Rectangle {
        id: session
        required property var modelData
        width: tab.width
        height: sessionRow.implicitHeight + Style.space(14)
        radius: Style.cornerRadius
        color: Util.alpha(panel.okColor, 0.08)
        border.width: Style.normalBorderWidth
        border.color: Util.alpha(panel.okColor, 0.35)

        Row {
          id: sessionRow
          x: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(16)
          spacing: Style.space(10)

          Rectangle {
            id: sessionTile
            anchors.verticalCenter: parent.verticalCenter
            width: Style.space(30)
            height: width
            radius: Style.cornerRadius
            color: Util.alpha(panel.protocolColors[session.modelData.protocol] || panel.accent, 0.14)
            Text {
              anchors.centerIn: parent
              text: panel.protocolIcons[session.modelData.protocol] || ""
              color: panel.protocolColors[session.modelData.protocol] || panel.accent
              font.family: panel.fontFamily
              font.pixelSize: Style.font.body
            }
          }

          Column {
            width: parent.width - sessionTile.width - sessionActions.width - Style.space(20)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            Text {
              width: parent.width
              text: session.modelData.name
              textFormat: Text.PlainText
              elide: Text.ElideRight
              color: panel.foreground
              font.family: panel.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              width: parent.width
              text: "● connected " + Model.relativeTime(session.modelData.started, tab.now).replace(" ago", "").replace("just now", "now")
                + (session.modelData.protocol === "vnc" ? " · F8 menu" : "")
              elide: Text.ElideRight
              color: panel.okColor
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Row {
            id: sessionActions
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)
            Pill {
              text: "Show"
              tooltip: "Bring its window to the front"
              tint: panel.foreground
              fontFamily: panel.fontFamily
              onClicked: {
                store.focusSession(session.modelData.id)
                panel.close()
              }
            }
            Pill {
              text: "Disconnect"
              filled: true
              tint: panel.urgent
              fontFamily: panel.fontFamily
              onClicked: store.disconnectSession(session.modelData.id)
            }
          }
        }
      }
    }
  }

  // ===== Search + protocol chips =====
  TextField {
    id: searchField
    visible: !tab.firstRun
    width: parent.width
    placeholderText: "Search name, host or user   /"
    foreground: panel.foreground
    accent: panel.accent
    onTextChanged: {
      tab.query = text
      tab.selectedId = ""
      tab.menuId = ""
    }
    onAccepted: tab.activateCursor()
    Keys.onEscapePressed: {
      if (text !== "") text = ""
      else panel.focusKeys()
    }
    Keys.onDownPressed: tab.moveCursor(1)
    Keys.onUpPressed: tab.moveCursor(-1)
  }

  Row {
    visible: !tab.firstRun
    spacing: Style.space(6)
    Repeater {
      model: [
        { id: "", label: "All" },
        { id: "ssh", label: "SSH" },
        { id: "rdp", label: "RDP" },
        { id: "vnc", label: "VNC" }
      ]
      delegate: Pill {
        required property var modelData
        readonly property int count: tab.counts[modelData.id === "" ? "all" : modelData.id] || 0
        visible: modelData.id === "" || count > 0
        text: modelData.label + " " + count
        tint: tab.protoFilter === modelData.id ? panel.accent : panel.foreground
        bold: tab.protoFilter === modelData.id
        fontFamily: panel.fontFamily
        onClicked: {
          tab.protoFilter = modelData.id
          tab.selectedId = ""
        }
      }
    }
  }

  // ===== Missing clients =====
  Pill {
    visible: !tab.firstRun && store.missingPackages.length > 0
    width: parent.width
    iconText: "󰇚"
    text: store.installBusy ? "Waiting for the review…" : "Install missing clients: " + store.missingPackages.join(", ")
    tooltip: "Opens a review of the install command (omarchy pkg add) first"
    tint: panel.warnColor
    enabled: !store.installBusy
    fontFamily: panel.fontFamily
    onClicked: store.installPackages(store.missingPackages)
  }

  Text {
    visible: !tab.firstRun && tab.sections.length === 0
    width: parent.width
    text: tab.query !== "" ? "Nothing matches “" + tab.query + "”. New connection (below) starts from it." : "No connections of this type."
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }

  // ===== Sections =====
  Repeater {
    model: tab.firstRun ? [] : tab.sections
    delegate: Column {
      id: section
      required property var modelData
      width: tab.width
      spacing: Style.space(2)

      PanelSectionHeader {
        text: section.modelData.title
        foreground: panel.foreground
        fontFamily: panel.fontFamily
      }

      Repeater {
        model: section.modelData.rows
        delegate: Column {
          id: rowItem
          required property var modelData
          readonly property var conn: modelData
          readonly property bool fromConfig: Model.isSshConfigEntry(conn)
          readonly property bool isSelected: tab.selectedId === conn.id || tab.hoveredId === conn.id
          readonly property bool menuOpen: tab.menuId === conn.id
          // The actions stay on screen while this row's menu is open, so its
          // ✕ can always close it.
          readonly property bool showActions: isSelected || menuOpen
          readonly property bool missing: tab.clientMissing(conn)
          width: section.width
          spacing: Style.space(4)

          Rectangle {
            width: parent.width
            height: rowLine.implicitHeight + Style.space(14)
            radius: Style.cornerRadius
            color: rowItem.showActions ? Util.alpha(panel.accent, 0.12) : "transparent"
            border.width: rowItem.showActions ? Style.normalBorderWidth : 0
            border.color: Util.alpha(panel.accent, 0.35)

            HoverHandler {
              onHoveredChanged: {
                if (hovered) {
                  // While a menu is open, other rows don't light up.
                  if (tab.menuId !== "" && !rowItem.menuOpen) return
                  tab.hoveredId = rowItem.conn.id
                  tab.selectedId = ""
                } else if (tab.hoveredId === rowItem.conn.id) {
                  tab.hoveredId = ""
                }
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                  tab.toggleMenu(rowItem.conn.id)
                } else if (tab.menuId !== "" && !rowItem.menuOpen) {
                  // A menu is open elsewhere: this click just closes it.
                  tab.menuId = ""
                  tab.hoveredId = rowItem.conn.id
                } else {
                  tab.primaryAction(rowItem.conn)
                }
              }
            }

            Row {
              id: rowLine
              x: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(16)
              spacing: Style.space(10)

              Rectangle {
                id: tile
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(30)
                height: width
                radius: Style.cornerRadius
                color: Util.alpha(panel.protocolColors[rowItem.conn.protocol], 0.14)
                Text {
                  anchors.centerIn: parent
                  text: panel.protocolIcons[rowItem.conn.protocol] || ""
                  color: panel.protocolColors[rowItem.conn.protocol]
                  font.family: panel.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              Column {
                width: parent.width - tile.width - rightSide.width - Style.space(20)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Text {
                  width: parent.width
                  text: (rowItem.conn.favorite ? "★ " : "") + rowItem.conn.name
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: panel.foreground
                  font.family: panel.fontFamily
                  font.pixelSize: Style.font.body
                }
                Text {
                  width: parent.width
                  text: tab.subtitle(rowItem.conn)
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: rowItem.missing ? panel.warnColor : panel.dim
                  font.family: panel.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Item {
                id: rightSide
                anchors.verticalCenter: parent.verticalCenter
                width: rowItem.showActions ? actions.implicitWidth : status.implicitWidth
                height: Math.max(actions.implicitHeight, status.implicitHeight)

                Column {
                  id: status
                  visible: !rowItem.showActions
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)
                  Text {
                    anchors.right: parent.right
                    text: tab.statusText(rowItem.conn)
                    color: tab.statusColor(rowItem.conn)
                    font.family: panel.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                  Text {
                    anchors.right: parent.right
                    text: rowItem.fromConfig ? "ssh config" : Model.relativeTime(rowItem.conn.lastUsed, tab.now)
                    color: panel.dim
                    font.family: panel.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Row {
                  id: actions
                  visible: rowItem.showActions
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(4)

                  Pill {
                    text: rowItem.menuOpen ? "✕" : "⋯"
                    tooltip: rowItem.menuOpen ? "Close actions (Esc)" : "More actions (right-click, or .)"
                    tint: rowItem.menuOpen ? panel.accent : panel.foreground
                    fontFamily: panel.fontFamily
                    onClicked: tab.toggleMenu(rowItem.conn.id)
                  }
                  Pill {
                    filled: true
                    tint: rowItem.missing ? panel.warnColor : panel.accent
                    text: rowItem.missing ? "Install " + Model.clientPackage(rowItem.conn.protocol) : "Connect ↵"
                    tooltip: rowItem.missing ? "Opens a review of the install command first" : ""
                    fontFamily: panel.fontFamily
                    onClicked: tab.primaryAction(rowItem.conn)
                  }
                }
              }
            }
          }

          // ⋯ actions
          Flow {
            visible: rowItem.menuOpen
            width: parent.width
            leftPadding: Style.space(48)
            spacing: Style.space(6)

            Pill {
              visible: !rowItem.fromConfig
              text: "Edit"
              iconText: "󰏫"
              tint: panel.foreground
              fontFamily: panel.fontFamily
              onClicked: panel.openForm(rowItem.conn.id, null)
            }
            Pill {
              visible: rowItem.fromConfig
              text: "Save as connection"
              iconText: "󰆓"
              tooltip: "Copy it into your saved connections to give it a group or make it a favorite"
              tint: panel.foreground
              fontFamily: panel.fontFamily
              onClicked: panel.openForm("new", { name: rowItem.conn.name, host: rowItem.conn.host, protocol: "ssh" })
            }
            Pill {
              visible: !rowItem.fromConfig
              text: rowItem.conn.favorite ? "Unfavorite" : "Favorite"
              iconText: rowItem.conn.favorite ? "󰓎" : "󰓒"
              tint: panel.foreground
              fontFamily: panel.fontFamily
              onClicked: store.toggleFavorite(rowItem.conn.id)
            }
            Pill {
              text: tab.copiedId === rowItem.conn.id ? "Copied" : "Copy address"
              iconText: "󰆏"
              tint: panel.foreground
              fontFamily: panel.fontFamily
              onClicked: tab.copyAddress(rowItem.conn)
            }
            Pill {
              visible: !rowItem.fromConfig
              text: "Duplicate"
              iconText: "󰆑"
              tint: panel.foreground
              fontFamily: panel.fontFamily
              onClicked: {
                var copy = store.duplicate(rowItem.conn.id)
                if (copy) panel.openForm(copy.id, null)
              }
            }
            Pill {
              visible: rowItem.conn.protocol === "ssh" && !rowItem.fromConfig && !rowItem.conn.jumpHost
              text: "Log in with a key"
              iconText: "󰌆"
              tooltip: "Opens a terminal (it asks the server's password): ssh-keygen if you have no key, then ssh-copy-id"
              tint: panel.foreground
              enabled: !store.terminalBusy
              fontFamily: panel.fontFamily
              onClicked: store.setupSshKey(rowItem.conn)
            }
            Pill {
              visible: !rowItem.fromConfig
              text: "Delete"
              iconText: "󰆴"
              tint: panel.urgent
              fontFamily: panel.fontFamily
              onClicked: {
                tab.menuId = ""
                tab.pendingDeleteId = rowItem.conn.id
              }
            }
          }

          // Delete confirmation
          Row {
            visible: tab.pendingDeleteId === rowItem.conn.id
            width: parent.width
            leftPadding: Style.space(48)
            spacing: Style.space(6)

            Text {
              width: parent.width - Style.space(48) - keepBtn.width - deleteBtn.width - Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: "Delete “" + rowItem.conn.name + "”?" + (rowItem.conn.hasSecret ? " Its password leaves the keyring too." : "")
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              color: panel.foreground
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
            }
            Pill {
              id: keepBtn
              text: "Keep"
              tint: panel.foreground
              fontFamily: panel.fontFamily
              onClicked: tab.pendingDeleteId = ""
            }
            Pill {
              id: deleteBtn
              text: "Delete"
              filled: true
              tint: panel.urgent
              fontFamily: panel.fontFamily
              onClicked: {
                store.remove(rowItem.conn.id)
                tab.pendingDeleteId = ""
              }
            }
          }
        }
      }
    }
  }

  // ===== Footer =====
  Rectangle {
    visible: !tab.firstRun
    width: parent.width
    height: Style.normalBorderWidth
    color: Util.alpha(panel.foreground, 0.08)
  }

  Pill {
    visible: !tab.firstRun
    width: parent.width
    iconText: "󰐕"
    text: "New connection"
    tint: panel.accent
    enabled: store.writable
    fontFamily: panel.fontFamily
    onClicked: panel.openForm("new", tab.query !== "" ? { name: tab.query, host: tab.query.indexOf(" ") < 0 ? tab.query : "" } : null)
  }

  Text {
    visible: !tab.firstRun
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    text: "↑↓ select · ↵ connect · e edit · f favorite · c copy · x delete · n new"
    wrapMode: Text.Wrap
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }
}
