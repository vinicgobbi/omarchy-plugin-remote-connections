import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One connection in the Connect tab: protocol tile with a reachability dot,
// name and address, and — while it has the mouse or the keyboard cursor —
// its actions. Below it, when asked for: the ⋯ actions, the folder picker
// (Move to), the RDP password prompt and the delete confirmation. All the
// state lives in the tab (keyed by `rowKey`, since one connection can show
// up twice: in Favorites and in its folder).
Column {
  id: row

  property var view: null
  property var panel: null
  property var store: null
  property var conn: null
  property string rowKey: ""
  // Name the folder in the subtitle (Favorites, Recent, search results);
  // inside the folder itself it would just repeat the breadcrumb.
  property bool showFolder: true

  readonly property bool fromConfig: Model.isSshConfigEntry(conn)
  readonly property bool isSelected: view.selectedKey === rowKey || view.hoveredKey === rowKey
  readonly property bool menuOpen: view.menuKey === rowKey
  readonly property bool moving: view.moveKey === rowKey
  readonly property bool askingPassword: view.passwordKey === rowKey
  readonly property bool confirmingDelete: view.pendingDeleteKey === rowKey
  // The actions stay on screen while this row's menu is open, so its ✕ can
  // always close it.
  readonly property bool showActions: isSelected || menuOpen || moving || askingPassword
  readonly property bool missing: view.clientMissing(conn)
  readonly property var reach: store.reachOf(conn.id)

  spacing: Style.space(4)
  z: menuOpen ? 10 : 0

  Rectangle {
    width: parent.width
    height: rowLine.implicitHeight + Style.space(14)
    radius: Style.cornerRadius
    color: row.showActions ? Util.alpha(panel.accent, 0.12) : "transparent"
    border.width: row.showActions ? Style.normalBorderWidth : 0
    border.color: Util.alpha(panel.accent, 0.35)

      // ⋯ actions
      ActionMenu {
        visible: row.menuOpen
        y: parent.height
        width: parent.width
        panel: row.panel
        bounds: view
        onOverflowChanged: if (visible) view.menuOverflow = overflow
        actions: [
          { id: "edit", icon: "󰏫", text: "Edit", hint: "e", visible: !row.fromConfig },
          { id: "save", icon: "󰆓", text: "Save as connection", detail: "To put it in a folder or make it a favorite", visible: row.fromConfig },
          { id: "move", icon: "󰉒", text: "Move to folder…", hint: "m", visible: !row.fromConfig },
          { id: "favorite", icon: row.conn.favorite ? "󰓎" : "󰓒", text: row.conn.favorite ? "Remove from favorites" : "Add to favorites", hint: "f", visible: !row.fromConfig },
          { id: "copy", icon: view.copiedId === row.rowKey ? "󰄬" : "󰆏", text: view.copiedId === row.rowKey ? "Copied" : "Copy address", hint: "c" },
          { id: "duplicate", icon: "󰆑", text: "Duplicate", visible: !row.fromConfig },
          { id: "key", icon: "󰌆", text: "Log in with a key", detail: "Copies your SSH key to the server (asks its password once)",
            visible: row.conn.protocol === "ssh" && !row.fromConfig && !row.conn.jumpHost, enabled: !store.terminalBusy },
          { id: "delete", icon: "󰆴", text: "Delete…", hint: "x", danger: true, visible: !row.fromConfig }
        ]
        onTriggered: function(id) {
          if (id === "edit") panel.openForm(row.conn.id, null)
          else if (id === "save") panel.openForm("new", { name: row.conn.name, host: row.conn.host, protocol: "ssh" })
          else if (id === "move") view.startMove(row.rowKey)
          else if (id === "favorite") store.toggleFavorite(row.conn.id)
          else if (id === "copy") view.copyAddress(row.conn, row.rowKey)
          else if (id === "duplicate") {
            var copy = store.duplicate(row.conn.id)
            if (copy) panel.openForm(copy.id, null)
          } else if (id === "key") store.setupSshKey(row.conn)
          else if (id === "delete") {
            view.closeMenus()
            view.pendingDeleteKey = row.rowKey
            view.selectedKey = row.rowKey
          }
        }
      }

    HoverHandler {
      onHoveredChanged: {
        if (hovered) {
          if (view.busyElsewhere(row.rowKey)) return
          view.hoveredKey = row.rowKey
          view.selectedKey = ""
        } else if (view.hoveredKey === row.rowKey) {
          view.hoveredKey = ""
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          view.toggleMenu(row.rowKey)
        } else if (view.busyElsewhere(row.rowKey)) {
          // Something is open elsewhere: this click just closes it.
          view.closeMenus()
          view.hoveredKey = row.rowKey
        } else {
          view.primaryAction(row.conn, row.rowKey)
        }
      }
    }

    Row {
      id: rowLine
      x: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width - Style.space(16)
      spacing: Style.space(10)

      // Protocol tile, with whether the server answers as a dot on its corner.
      Item {
        id: tile
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(30)
        height: width

        Rectangle {
          anchors.fill: parent
          radius: Style.cornerRadius
          color: Util.alpha(panel.protocolColors[row.conn.protocol] || panel.accent, 0.14)
          Text {
            anchors.centerIn: parent
            text: panel.protocolIcons[row.conn.protocol] || ""
            color: panel.protocolColors[row.conn.protocol] || panel.accent
            font.family: panel.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        Rectangle {
          visible: row.reach.state === "up" || row.reach.state === "down"
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.rightMargin: -Style.space(2)
          anchors.bottomMargin: -Style.space(2)
          width: Style.space(10)
          height: width
          radius: width / 2
          color: row.reach.state === "up" ? panel.okColor : panel.urgent
          border.width: Style.space(2)
          border.color: Color.background
        }
      }

      Column {
        width: parent.width - tile.width - rightSide.width - Style.space(20)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        Row {
          width: parent.width
          spacing: Style.space(5)
          Text {
            id: nameText
            width: Math.min(implicitWidth, parent.width - (star.visible ? star.width + parent.spacing : 0))
            text: row.conn.name
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: panel.foreground
            font.family: panel.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            id: star
            visible: row.conn.favorite === true
            anchors.verticalCenter: nameText.verticalCenter
            text: "★"
            color: panel.folderColor
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        Text {
          width: parent.width
          text: view.subtitle(row.conn, row.showFolder)
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: row.missing ? panel.warnColor : panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Item {
        id: rightSide
        anchors.verticalCenter: parent.verticalCenter
        width: row.showActions ? actions.implicitWidth : status.implicitWidth
        height: Math.max(actions.implicitHeight, status.implicitHeight)

        Column {
          id: status
          visible: !row.showActions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(2)
          Text {
            anchors.right: parent.right
            text: view.statusText(row.conn)
            color: view.statusColor(row.conn)
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            anchors.right: parent.right
            text: row.fromConfig ? "ssh config" : Model.relativeTime(row.conn.lastUsed, view.now)
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Row {
          id: actions
          visible: row.showActions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Pill {
            text: row.menuOpen || row.moving ? "✕" : "⋯"
            tooltip: row.menuOpen || row.moving ? "Close (Esc)" : "More actions (right-click, or .)"
            tint: row.menuOpen || row.moving ? panel.accent : panel.foreground
            fontFamily: panel.fontFamily
            onClicked: row.moving ? view.closeMenus() : view.toggleMenu(row.rowKey)
          }
          Pill {
            filled: true
            tint: row.missing ? panel.warnColor : panel.accent
            text: row.missing ? "Install " + Model.clientPackage(row.conn.protocol) : "Connect ↵"
            tooltip: row.missing ? "Opens a review of the install command first" : ""
            fontFamily: panel.fontFamily
            onClicked: view.primaryAction(row.conn, row.rowKey)
          }
        }
      }
    }
  }

  // Move to: every folder as a chip, the current one marked.
  Column {
    visible: row.moving
    width: parent.width
    leftPadding: Style.space(48)
    spacing: Style.space(6)
    onVisibleChanged: if (!visible) moveNewField.text = ""

    Text {
      width: parent.width - Style.space(48)
      text: "Move “" + row.conn.name + "” to"
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: panel.foreground
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    Flow {
      width: parent.width - Style.space(48)
      spacing: Style.space(6)

      Pill {
        text: "Top level"
        iconText: "󰋜"
        tint: row.conn.group === "" ? panel.accent : panel.foreground
        bold: row.conn.group === ""
        fontFamily: panel.fontFamily
        onClicked: view.moveTo(row.conn, "")
      }
      Repeater {
        model: store.allFolders
        delegate: Pill {
          required property string modelData
          readonly property bool here: row.conn.group === modelData
          text: Model.folderLabel(modelData)
          iconText: here ? "󰝰" : "󰉋"
          tint: here ? panel.accent : panel.foreground
          bold: here
          fontFamily: panel.fontFamily
          onClicked: view.moveTo(row.conn, modelData)
        }
      }
    }

    Row {
      spacing: Style.space(6)
      Field {
        id: moveNewField
        width: row.width - Style.space(48) - moveNewBtn.width - Style.space(6)
        placeholderText: view.here === "" || view.here === Model.SSH_CONFIG_FOLDER
          ? "Or a new folder…"
          : "Or a new folder in " + Model.folderName(view.here) + "…"
        foreground: panel.foreground
        accent: panel.accent
        onAccepted: view.moveToNewFolder(row.conn, text)
        Keys.onEscapePressed: { view.closeMenus(); panel.focusKeys() }
      }
      Pill {
        id: moveNewBtn
        anchors.verticalCenter: parent.verticalCenter
        text: "Create & move"
        tint: panel.accent
        enabled: moveNewField.text.trim() !== ""
        fontFamily: panel.fontFamily
        onClicked: view.moveToNewFolder(row.conn, moveNewField.text)
      }
    }
  }

  // Password prompt (RDP with no saved password)
  Column {
    visible: row.askingPassword
    width: parent.width
    leftPadding: Style.space(48)
    spacing: Style.space(6)
    onVisibleChanged: {
      if (!visible) { pwField.text = ""; return }
      pwUser.text = row.conn.user
      Qt.callLater(function() { (row.conn.user === "" ? pwUser : pwField).forceActiveFocus() })
    }

    Text {
      width: parent.width - Style.space(48)
      text: "Sign in to " + row.conn.host + (row.conn.rdp && row.conn.rdp.domain ? " (domain " + row.conn.rdp.domain + ")" : "")
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: panel.foreground
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }
    Field {
      id: pwUser
      width: parent.width - Style.space(48)
      placeholderText: "User"
      foreground: panel.foreground
      accent: panel.accent
      onAccepted: pwField.forceActiveFocus()
      Keys.onEscapePressed: { view.passwordKey = ""; panel.focusKeys() }
    }
    Field {
      id: pwField
      width: parent.width - Style.space(48)
      placeholderText: "Password"
      password: true
      foreground: panel.foreground
      accent: panel.accent
      onAccepted: view.connectWithPassword(row.conn, pwUser.text, text)
      Keys.onEscapePressed: { view.passwordKey = ""; panel.focusKeys() }
    }
    Toggle {
      width: parent.width - Style.space(48)
      label: "Remember in keyring"
      description: view.rememberPassword ? "Next time it connects without asking." : "Used once, then deleted."
      checked: view.rememberPassword
      foreground: panel.foreground
      accent: panel.accent
      fontFamily: panel.fontFamily
      onClicked: view.rememberPassword = !view.rememberPassword
    }
    Row {
      spacing: Style.space(6)
      Pill {
        text: "Cancel"
        tint: panel.foreground
        fontFamily: panel.fontFamily
        onClicked: { view.passwordKey = ""; panel.focusKeys() }
      }
      Pill {
        text: "Connect ↵"
        filled: true
        tint: panel.accent
        enabled: pwField.text !== ""
        fontFamily: panel.fontFamily
        onClicked: view.connectWithPassword(row.conn, pwUser.text, pwField.text)
      }
    }
  }

  // Delete confirmation
  Row {
    visible: row.confirmingDelete
    width: parent.width
    leftPadding: Style.space(48)
    spacing: Style.space(6)

    Text {
      width: parent.width - Style.space(48) - keepBtn.width - deleteBtn.width - Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: "Delete “" + row.conn.name + "”?" + (row.conn.hasSecret ? " Its password leaves the keyring too." : "")
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
      onClicked: view.pendingDeleteKey = ""
    }
    Pill {
      id: deleteBtn
      text: "Delete"
      filled: true
      tint: panel.urgent
      fontFamily: panel.fontFamily
      onClicked: {
        store.remove(row.conn.id)
        view.pendingDeleteKey = ""
      }
    }
  }
}
