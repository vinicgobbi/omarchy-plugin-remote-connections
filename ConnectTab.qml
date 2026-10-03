import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// "Connect" tab: your connections organized in folders, browsed like a file
// manager. The top level has Favorites and Recent, then the folders
// (~/.ssh/config hosts are a read-only one) and the connections that aren't
// in any; opening a folder shows a breadcrumb back up. Searching looks in
// every folder at once. The row under the mouse, or the one picked with
// ↑/↓, shows its actions. With nothing saved yet, it shows the first-run
// cards instead.
Column {
  id: tab

  property var panel: null
  property var store: null
  property var flickable: null

  // The folder being shown: "" is the top level, Model.SSH_CONFIG_FOLDER
  // the ~/.ssh/config hosts.
  property string folder: ""
  property string query: ""
  property string protoFilter: ""        // "" | ssh | rdp | vnc
  // Rows are addressed by key ("<section>|<connection id>" or
  // "folder|<path>"), since a connection can be listed twice (Favorites and
  // its folder). Keyboard cursor (↑/↓); the mouse doesn't set it: hovering
  // highlights a row only while the pointer is on it (hoveredKey).
  property string selectedKey: ""
  property string hoveredKey: ""
  property string menuKey: ""            // row whose ⋯ actions are open
  property string moveKey: ""            // connection row picking a folder
  property string renameKey: ""          // folder row being renamed
  property string pendingDeleteKey: ""
  // RDP connection asking for its password inline before connecting.
  property string passwordKey: ""
  property bool rememberPassword: true
  property bool addingFolder: false
  property string folderError: ""
  property string copiedId: ""
  property real now: Date.now()

  // The folder actually shown: `folder`, or the closest parent that still
  // exists (it may have been renamed or deleted, here or in the file).
  readonly property string here: {
    if (folder === Model.SSH_CONFIG_FOLDER) return Model.unsavedSshHosts(store.connections, store.sshHosts).length > 0 ? folder : ""
    var p = folder
    while (p !== "" && store.allFolders.indexOf(p) < 0) p = Model.parentFolder(p)
    return p
  }
  readonly property bool searching: query.trim() !== "" || protoFilter !== ""
  readonly property bool atTop: here === "" || searching
  readonly property var crumbs: here === Model.SSH_CONFIG_FOLDER
    ? [{ name: "All", path: "" }, { name: "~/.ssh/config", path: here }]
    : Model.breadcrumbs(here)
  readonly property var sections: Model.browse(store.connections, store.folders, store.sshHosts, here, query, protoFilter)
  readonly property var flatRows: {
    var out = []
    for (var i = 0; i < sections.length; i++) {
      var s = sections[i]
      for (var j = 0; j < s.rows.length; j++)
        out.push({ key: rowKey(s, s.rows[j]), kind: s.kind, item: s.rows[j] })
    }
    return out
  }
  readonly property var counts: Model.protocolCounts(store.connections, store.sshHosts)
  readonly property int protocolsInUse: (counts.ssh > 0 ? 1 : 0) + (counts.rdp > 0 ? 1 : 0) + (counts.vnc > 0 ? 1 : 0)
  readonly property bool firstRun: store.loaded && store.connections.length === 0 && store.sshHosts.length === 0 && store.folders.length === 0

  spacing: Style.space(10)

  function rowKey(section, item) {
    return section.kind === "folder" ? "folder|" + item.path : section.id + "|" + item.id
  }

  function reset() {
    folder = ""
    query = ""
    protoFilter = ""
    closeMenus()
    addingFolder = false
    searchField.text = ""
  }

  // Closes every inline thing a row can open (tab switch, form, a click
  // elsewhere).
  function closeMenus() {
    menuKey = ""
    moveKey = ""
    renameKey = ""
    pendingDeleteKey = ""
    passwordKey = ""
    folderError = ""
    selectedKey = ""
    hoveredKey = ""
  }

  // True while another row has something open: hovering this one then
  // doesn't steal the highlight, and clicking it just closes that.
  function busyElsewhere(key) {
    var open = [menuKey, moveKey, renameKey, passwordKey, pendingDeleteKey]
    for (var i = 0; i < open.length; i++)
      if (open[i] !== "" && open[i] !== key) return true
    return false
  }

  function toggleMenu(key) {
    var wasOpen = menuKey === key
    closeMenus()
    menuKey = wasOpen ? "" : key
    selectedKey = key
  }

  function startMove(key) {
    closeMenus()
    moveKey = key
    selectedKey = key
  }

  function startRename(key) {
    closeMenus()
    renameKey = key
    selectedKey = key
  }

  // --- Folders ---

  function openFolder(path) {
    closeMenus()
    addingFolder = false
    if (searching) {
      searchField.text = ""
      protoFilter = ""
    }
    folder = path
    if (flickable) flickable.contentY = 0
  }

  // One level up; false when already at the top.
  function goUp() {
    if (searching || here === "") return false
    var from = here
    openFolder(here === Model.SSH_CONFIG_FOLDER ? "" : Model.parentFolder(here))
    // Land on the folder we came from, so ↵ goes straight back in.
    selectedKey = "folder|" + from
    return true
  }

  function renameFolder(path, name) {
    var to = store.renameFolder(path, name)
    if (to === "") { folderError = store.lastError; store.lastError = ""; return }
    closeMenus()
    if (Model.isInside(folder, path)) folder = to + folder.slice(path.length)
    selectedKey = "folder|" + to
    panel.focusKeys()
  }

  function createFolder(name) {
    var path = store.createFolder(here === Model.SSH_CONFIG_FOLDER ? "" : here, name)
    if (path === "") { folderError = store.lastError; store.lastError = ""; return }
    addingFolder = false
    folderError = ""
    newFolderField.text = ""
    selectedKey = "folder|" + path
    panel.focusKeys()
  }

  function moveTo(c, path) {
    store.moveToFolder(c.id, path)
    closeMenus()
    panel.focusKeys()
  }

  function moveToNewFolder(c, name) {
    var path = store.createFolder(here === Model.SSH_CONFIG_FOLDER ? "" : here, name)
    if (path === "") return
    moveTo(c, path)
  }

  // New connection in the folder being shown (or from what was searched).
  function newConnection() {
    var seed = {}
    if (here !== "" && here !== Model.SSH_CONFIG_FOLDER) seed.group = here
    if (query.trim() !== "") {
      seed.name = query.trim()
      if (query.trim().indexOf(" ") < 0) seed.host = query.trim()
    }
    panel.openForm("new", seed)
  }

  function startNewFolder() {
    closeMenus()
    folderError = ""
    addingFolder = true
    Qt.callLater(function() { newFolderField.forceActiveFocus() })
  }

  // Esc peels one layer at a time, then climbs the folders; returns false
  // when there's nothing left so the popup itself closes.
  function handleEscape() {
    if (passwordKey !== "" || pendingDeleteKey !== "" || moveKey !== "" || renameKey !== "" || menuKey !== "") {
      var key = passwordKey || pendingDeleteKey || moveKey || renameKey || menuKey
      closeMenus()
      selectedKey = key
      return true
    }
    if (addingFolder) { addingFolder = false; folderError = ""; return true }
    if (searching) { searchField.text = ""; protoFilter = ""; return true }
    return goUp()
  }

  // The row keyboard shortcuts act on: the open menu's, the keyboard
  // cursor's, or the one under the mouse.
  readonly property string activeKey: menuKey !== "" ? menuKey : (selectedKey !== "" ? selectedKey : hoveredKey)

  function indexOfActive() {
    for (var i = 0; i < flatRows.length; i++) if (flatRows[i].key === activeKey) return i
    return -1
  }

  function active() {
    var i = indexOfActive()
    return i >= 0 ? flatRows[i] : null
  }

  function moveCursor(dy) {
    if (flatRows.length === 0) return
    var i = indexOfActive()
    i = i < 0 ? (dy > 0 ? 0 : flatRows.length - 1) : Math.max(0, Math.min(flatRows.length - 1, i + dy))
    var key = flatRows[i].key
    closeMenus()
    selectedKey = key
  }

  // → / l: into the folder under the cursor.
  function enterCursor() {
    var r = active()
    if (r && r.kind === "folder") openFolder(r.item.path)
  }

  function activateCursor() {
    var r = active() || flatRows[0]
    if (!r) return
    if (r.kind === "folder") openFolder(r.item.path)
    else primaryAction(r.item, r.key)
  }

  function deleteCursor() {
    var r = active()
    if (!r || (r.kind === "folder" ? r.item.readOnly : Model.isSshConfigEntry(r.item))) return
    closeMenus()
    pendingDeleteKey = r.key
    selectedKey = r.key
  }

  function textKey(t) {
    if (t === "/") { searchField.forceActiveFocus(); return }
    if (t === "\b") { goUp(); return }
    if (t === "N") { startNewFolder(); return }
    if (t === "n") { newConnection(); return }
    var r = active()
    if (!r) return
    if (r.kind === "folder") {
      if (r.item.readOnly) return
      if (t === "e" || t === "r") startRename(r.key)
      else if (t === ".") toggleMenu(r.key)
      return
    }
    var c = r.item
    var saved = !Model.isSshConfigEntry(c)
    if (t === "e" && saved) panel.openForm(c.id, null)
    else if (t === "m" && saved) startMove(r.key)
    else if (t === "f" && saved) store.toggleFavorite(c.id)
    else if (t === "c") copyAddress(c, r.key)
    else if (t === ".") toggleMenu(r.key)
  }

  // --- Connections ---

  function clientMissing(c) {
    return store.clientsChecked && !store.hasClient(c.protocol)
  }

  function primaryAction(c, key) {
    if (clientMissing(c)) {
      store.installClient(c.protocol)
      panel.close()
    } else if (store.needsPassword(c)) {
      closeMenus()
      rememberPassword = true
      passwordKey = key
      selectedKey = key
    } else if (store.connect(c.id)) {
      panel.close()
    }
  }

  function connectWithPassword(c, user, password) {
    if (password === "") return
    var id = c.id
    passwordKey = ""
    store.connectWithPassword(id, user, password, rememberPassword, function(ok) {
      if (ok) panel.close()
    })
  }

  function copyAddress(c, key) {
    store.copyText(Model.isSshConfigEntry(c) ? c.host : Model.address(c))
    copiedId = key
    copiedTimer.restart()
  }

  function statusText(c) {
    var r = store.reachOf(c.id)
    if (r.state === "up") return r.ms + " ms"
    if (r.state === "down") return "offline"
    if (r.state === "checking") return "…"
    return c.jumpHost ? "via " + c.jumpHost : ""
  }

  function statusColor(c) {
    var r = store.reachOf(c.id)
    return r.state === "up" ? panel.okColor : (r.state === "down" ? panel.urgent : panel.dim)
  }

  function subtitle(c, showFolder) {
    if (clientMissing(c)) return "Needs " + Model.clientPackage(c.protocol) + " · " + Model.address(c)
    if (Model.isSshConfigEntry(c)) return c.display
    var parts = [Model.protocolLabel(c.protocol), Model.address(c)]
    if (showFolder && c.group !== "") parts.push("󰉋 " + Model.folderLabel(c.group))
    return parts.join(" · ") + (c.hasSecret ? " · 󰌾" : "")
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
      text: "All your SSH, RDP and VNC connections in one place, one click (or one shortcut) away."
      wrapMode: Text.Wrap
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }

    Repeater {
      model: [
        { icon: "󰒓", title: "Install what you need", text: "The RDP and VNC clients: see what's installed and add it in one go. Also under the gear, top right.", action: "setup" },
        { icon: "󰐕", title: "Add a connection", text: "SSH, RDP (Windows) or VNC. Passwords stay in your keyring.", action: "new" }
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
          onClicked: card.modelData.action === "new" ? tab.newConnection() : panel.openSetup()
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
  Row {
    visible: !tab.firstRun
    width: parent.width
    spacing: Style.space(6)

    Field {
      id: searchField
      width: parent.width - (chips.visible ? chips.width + Style.space(6) : 0)
      placeholderText: tab.here === "" ? "Search connections" : "Search all folders"
      foreground: panel.foreground
      accent: panel.accent
      onTextChanged: {
        tab.query = text
        tab.closeMenus()
      }
      onAccepted: tab.activateCursor()
      Keys.onEscapePressed: {
        if (text !== "") text = ""
        else panel.focusKeys()
      }
      Keys.onDownPressed: tab.moveCursor(1)
      Keys.onUpPressed: tab.moveCursor(-1)
    }

    // Protocol filter, only when there's more than one to tell apart.
    Row {
      id: chips
      visible: tab.protocolsInUse > 1
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)
      Repeater {
        model: ["ssh", "rdp", "vnc"]
        delegate: Pill {
          required property string modelData
          readonly property bool on: tab.protoFilter === modelData
          visible: (tab.counts[modelData] || 0) > 0
          iconText: panel.protocolIcons[modelData]
          tooltip: (on ? "Show everything" : "Only " + Model.protocolLabel(modelData)) + " · " + tab.counts[modelData]
          tint: on ? panel.protocolColors[modelData] : panel.dim
          filled: on
          fontFamily: panel.fontFamily
          onClicked: {
            tab.closeMenus()
            tab.protoFilter = on ? "" : modelData
          }
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

  // ===== Where we are: All › Work › Servers =====
  Row {
    visible: !tab.firstRun && !tab.atTop
    width: parent.width
    spacing: Style.space(8)

    Pill {
      id: upBtn
      anchors.verticalCenter: parent.verticalCenter
      text: "←"
      tooltip: "Up one folder (← or Backspace)"
      tint: panel.foreground
      fontFamily: panel.fontFamily
      onClicked: tab.goUp()
    }

    Flow {
      width: parent.width - upBtn.width - Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      Repeater {
        model: tab.crumbs
        delegate: Row {
          id: crumb
          required property var modelData
          required property int index
          readonly property bool last: index === tab.crumbs.length - 1
          spacing: Style.space(4)

          Text {
            visible: crumb.index > 0
            anchors.verticalCenter: parent.verticalCenter
            text: "›"
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: crumb.index === 0 ? "󰋜" : crumb.modelData.name
            textFormat: Text.PlainText
            color: crumb.last ? panel.foreground : (crumbMouse.containsMouse ? panel.accent : panel.dim)
            font.family: panel.fontFamily
            font.pixelSize: crumb.last ? Style.font.title : Style.font.body
            font.bold: crumb.last
            font.underline: !crumb.last && crumbMouse.containsMouse
            MouseArea {
              id: crumbMouse
              anchors.fill: parent
              enabled: !crumb.last
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: tab.openFolder(crumb.modelData.path)
            }
          }
        }
      }
    }
  }

  // ===== Empty =====
  Text {
    visible: !tab.firstRun && tab.searching && tab.sections.length === 0
    width: parent.width
    text: tab.query.trim() !== "" ? "Nothing matches “" + tab.query + "” in any folder. New connection (below) starts from it." : "No connections of this type."
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }

  Column {
    visible: !tab.firstRun && !tab.searching && tab.sections.length === 0
    width: parent.width
    topPadding: Style.space(12)
    bottomPadding: Style.space(12)
    spacing: Style.space(6)
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "󰉖"
      color: Util.alpha(panel.folderColor, 0.6)
      font.family: panel.fontFamily
      font.pixelSize: Style.font.title * 2
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: tab.here === "" ? "No connections yet." : "This folder is empty."
      color: panel.foreground
      font.family: panel.fontFamily
      font.pixelSize: Style.font.body
    }
    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      text: "Add a connection here, or bring one in from its ⋯ › Move to."
      wrapMode: Text.Wrap
      color: panel.dim
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }
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
        visible: section.modelData.title !== ""
        text: section.modelData.title
        foreground: panel.foreground
        fontFamily: panel.fontFamily
      }

      Repeater {
        model: section.modelData.kind === "folder" ? section.modelData.rows : []
        delegate: FolderRow {
          required property var modelData
          width: section.width
          view: tab
          panel: tab.panel
          store: tab.store
          folder: modelData
          rowKey: tab.rowKey(section.modelData, modelData)
        }
      }

      Repeater {
        model: section.modelData.kind === "connection" ? section.modelData.rows : []
        delegate: ConnectionRow {
          required property var modelData
          width: section.width
          view: tab
          panel: tab.panel
          store: tab.store
          conn: modelData
          rowKey: tab.rowKey(section.modelData, modelData)
          showFolder: section.modelData.id !== "here"
        }
      }
    }
  }

  // ===== New folder (inline) =====
  Column {
    visible: tab.addingFolder
    width: parent.width
    spacing: Style.space(6)

    Row {
      width: parent.width
      spacing: Style.space(6)
      Field {
        id: newFolderField
        width: parent.width - createFolderBtn.width - cancelFolderBtn.width - Style.space(12)
        placeholderText: tab.here === "" || tab.here === Model.SSH_CONFIG_FOLDER
          ? "New folder name"
          : "New folder in " + Model.folderName(tab.here)
        foreground: panel.foreground
        accent: panel.accent
        onTextChanged: tab.folderError = ""
        onAccepted: tab.createFolder(text)
        Keys.onEscapePressed: {
          text = ""
          tab.addingFolder = false
          panel.focusKeys()
        }
      }
      Pill {
        id: cancelFolderBtn
        anchors.verticalCenter: parent.verticalCenter
        text: "Cancel"
        tint: panel.foreground
        fontFamily: panel.fontFamily
        onClicked: {
          newFolderField.text = ""
          tab.addingFolder = false
          panel.focusKeys()
        }
      }
      Pill {
        id: createFolderBtn
        anchors.verticalCenter: parent.verticalCenter
        text: "Create"
        filled: true
        tint: panel.accent
        enabled: newFolderField.text.trim() !== ""
        fontFamily: panel.fontFamily
        onClicked: tab.createFolder(newFolderField.text)
      }
    }
    Text {
      visible: tab.folderError !== "" && tab.renameKey === ""
      width: parent.width
      text: tab.folderError
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      color: panel.urgent
      font.family: panel.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // ===== Footer =====
  Rectangle {
    visible: !tab.firstRun
    width: parent.width
    height: Style.normalBorderWidth
    color: Util.alpha(panel.foreground, 0.08)
  }

  Row {
    visible: !tab.firstRun
    width: parent.width
    spacing: Style.space(6)

    Pill {
      width: (parent.width - Style.space(6)) * 0.6
      iconText: "󰐕"
      text: "New connection"
      tooltip: tab.here !== "" && tab.here !== Model.SSH_CONFIG_FOLDER ? "In " + Model.folderLabel(tab.here) + " (n)" : "n"
      tint: panel.accent
      enabled: store.writable
      fontFamily: panel.fontFamily
      onClicked: tab.newConnection()
    }
    Pill {
      width: (parent.width - Style.space(6)) * 0.4
      iconText: "󰉗"
      text: "New folder"
      tooltip: (tab.here !== "" && tab.here !== Model.SSH_CONFIG_FOLDER ? "Inside " + Model.folderLabel(tab.here) : "At the top level") + " (Shift+N)"
      tint: panel.foreground
      enabled: store.writable && tab.here !== Model.SSH_CONFIG_FOLDER
      fontFamily: panel.fontFamily
      onClicked: tab.startNewFolder()
    }
  }

  Text {
    visible: !tab.firstRun
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    text: "↑↓ move · ↵ open · ← back · / search · m move · n new"
    wrapMode: Text.Wrap
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }
}
