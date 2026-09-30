import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The bar icon and its popup. Two tabs, one per job: "Connect" (reach other
// machines) and "This machine" (let others reach this one); the add/edit
// form takes over the popup while open. The tabs live in ConnectTab.qml,
// MachineTab.qml and ConnectionForm.qml; they read colors and shared state
// from here through their `panel` property.
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

  // Status colors from the current Omarchy theme's colors.toml (the shell's
  // palette has no green/yellow), with neutral fallbacks for other themes.
  property var themeColors: ({})
  readonly property color okColor: themeColors.green || Qt.lighter(accent, 1.1)
  readonly property color warnColor: themeColors.yellow || Qt.lighter(urgent, 1.4)
  readonly property var protocolColors: ({
    ssh: accent,
    rdp: themeColors.blue || accent,
    vnc: themeColors.magenta || accent
  })
  readonly property var protocolIcons: ({ ssh: "󰆍", rdp: "󰍹", vnc: "󰢹" })

  // --- Navigation ---
  property string tab: "connect"          // connect | machine
  property string formId: ""              // "" closed, "new", or a connection id
  property var formSeed: null             // prefill for "new" (e.g. from ~/.ssh/config)
  readonly property bool formOpen: formId !== ""
  // Setup (the gear): everything the plugin installs, one place.
  property bool setupOpen: false
  // Form and Setup each take over the popup.
  readonly property bool takeover: formOpen || setupOpen

  function openSetup() {
    closeForm()
    connectTab.closeMenus()
    setupView.reset()
    setupOpen = true
  }

  function openForm(id, seed) {
    setupOpen = false
    connectTab.closeMenus()
    formSeed = seed || null
    formId = id || "new"
  }

  function closeForm() {
    formId = ""
    formSeed = null
  }

  // Give the keyboard back to the popup's key handler (after a text field).
  function focusKeys() {
    keys.forceActiveFocus()
  }

  function showTab(name) {
    closeForm()
    setupOpen = false
    connectTab.closeMenus()
    tab = name
  }

  // --- Bar icon state ---
  readonly property bool hostReachable: host.sshActive || host.vncActive
  readonly property string barIcon: host.screenBeingViewed ? "󰈈" : "󰒍"
  readonly property color barIconColor: host.screenBeingViewed ? urgent : barForeground
  readonly property string tooltipText: {
    var lines = []
    if (host.screenBeingViewed) lines.push("Your screen is being viewed from " + host.vncClients.join(", "))
    lines.push(store.connections.length === 0 ? "Remote Connections" : "Remote Connections · " + store.connections.length + " saved")
    if (host.sshActive) lines.push("SSH server is on")
    if (host.vncActive && !host.screenBeingViewed) lines.push("Screen sharing is on")
    return lines.join("\n")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      store.refresh()
      store.probeAll()
      host.refresh()
    } else {
      closeForm()
      setupOpen = false
      connectTab.reset()
      machineTab.reset()
    }
  }

  ConnectionStore {
    id: store
    watchSessions: root.opened
    changes: changes
  }

  HostService {
    id: host
    store: store
    changes: changes
    panelOpen: root.opened
  }

  // Reviews and applies privileged changes in its own centered window, so
  // the popup gets out of the way while it's up.
  ChangeSheet {
    id: changes
    okColor: root.okColor
    warnColor: root.warnColor
    fontFamily: root.fontFamily
    onStageChanged: if (stage === "review" && root.opened) root.close()
  }

  // Re-probe while the Connect tab is showing.
  Timer {
    interval: 30000
    repeat: true
    running: root.opened && root.tab === "connect" && !root.takeover
    onTriggered: store.probeAll()
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var out = {}
      var lines = String(text() || "").split("\n")
      for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(/^\s*(green|yellow|blue|magenta)\s*=\s*"(#[0-9a-fA-F]{6})"/)
        if (m) out[m[1]] = m[2]
      }
      root.themeColors = out
    }
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
        // This machine accepts remote access (SSH server or screen sharing).
        Rectangle {
          visible: root.hostReachable && !host.screenBeingViewed
          width: Style.space(6)
          height: width
          radius: width / 2
          color: root.okColor
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: Style.space(4)
          anchors.topMargin: Style.space(4)
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
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: {
        if (root.formOpen) root.closeForm()
        else if (root.setupOpen) root.setupOpen = false
        else if (!(root.tab === "connect" && connectTab.handleEscape())) root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (root.takeover) return
        if (dx !== 0) root.showTab(dx > 0 ? "machine" : "connect")
        else if (root.tab === "connect") connectTab.moveCursor(dy)
      }
      onActivateRequested: if (!root.takeover && root.tab === "connect") connectTab.activateCursor()
      onDeleteRequested: if (!root.takeover && root.tab === "connect") connectTab.deleteCursor()
      onTextKey: function(t) {
        if (root.takeover) return
        if (t === "1") root.showTab("connect")
        else if (t === "2") root.showTab("machine")
        else if (t === "n" || t === "N") root.openForm("new", null)
        else if (root.tab === "connect") connectTab.textKey(t)
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: content
          width: parent.width
          spacing: Style.space(12)

          // --- Header: title, what this machine exposes, the Setup gear ---
          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: !root.formOpen

            Pill {
              visible: root.setupOpen
              anchors.verticalCenter: parent.verticalCenter
              text: "←"
              tooltip: "Back (Esc)"
              tint: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.setupOpen = false
            }

            Text {
              width: parent.width - statusPill.width - gear.width - (root.setupOpen ? Style.space(52) : Style.space(16))
              anchors.verticalCenter: parent.verticalCenter
              text: root.setupOpen ? "Setup" : "Remote Connections"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Rectangle {
              id: statusPill
              visible: root.hostReachable
              anchors.verticalCenter: parent.verticalCenter
              width: visible ? pillText.implicitWidth + Style.space(16) : 0
              height: pillText.implicitHeight + Style.space(6)
              radius: height / 2
              color: Util.alpha(host.screenBeingViewed ? root.urgent : root.okColor, 0.14)

              Text {
                id: pillText
                anchors.centerIn: parent
                text: "● " + (host.screenBeingViewed ? "Being viewed"
                  : [host.sshActive ? "SSH" : "", host.vncActive ? "Sharing" : ""].filter(function(s) { return s !== "" }).join(" + ") + " on")
                color: host.screenBeingViewed ? root.urgent : root.okColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.showTab("machine")
              }
            }

            // Setup, with how many needed things are missing.
            Item {
              id: gear
              visible: !root.setupOpen
              anchors.verticalCenter: parent.verticalCenter
              width: visible ? gearPill.width : 0
              height: gearPill.height
              Pill {
                id: gearPill
                iconText: "󰒓"
                tooltip: store.neededMissing.length > 0
                  ? "Setup · " + store.neededMissing.length + " needed thing(s) not installed"
                  : "Setup · what the plugin installs"
                tint: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.openSetup()
              }
              Rectangle {
                visible: store.neededMissing.length > 0
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: -Style.space(4)
                anchors.topMargin: -Style.space(4)
                width: Math.max(height, badgeText.implicitWidth + Style.space(8))
                height: badgeText.implicitHeight + Style.space(2)
                radius: height / 2
                color: root.warnColor
                Text {
                  id: badgeText
                  anchors.centerIn: parent
                  text: store.neededMissing.length
                  color: Color.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }
          }

          // --- Tabs ---
          Rectangle {
            visible: !root.takeover
            width: parent.width
            height: tabRow.height + Style.space(6)
            radius: Style.cornerRadius
            color: Util.alpha(root.foreground, 0.06)

            Row {
              id: tabRow
              x: Style.space(3)
              y: Style.space(3)
              width: parent.width - Style.space(6)
              spacing: Style.space(4)

              Repeater {
                model: [
                  { id: "connect", label: "Connect" },
                  { id: "machine", label: "This machine" }
                ]
                delegate: Rectangle {
                  id: tabItem
                  required property var modelData
                  readonly property bool current: root.tab === modelData.id
                  width: (tabRow.width - Style.space(4)) / 2
                  height: Style.font.caption + Style.space(16)
                  radius: Style.cornerRadius
                  color: current ? Util.alpha(root.accent, 0.16) : (tabMouse.containsMouse ? Util.alpha(root.foreground, 0.05) : "transparent")

                  Row {
                    anchors.centerIn: parent
                    spacing: Style.space(6)
                    Text {
                      text: tabItem.modelData.label
                      color: tabItem.current ? root.accent : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: tabItem.current
                    }
                    Rectangle {
                      visible: tabItem.modelData.id === "machine" && root.hostReachable
                      anchors.verticalCenter: parent.verticalCenter
                      width: Style.space(6)
                      height: width
                      radius: width / 2
                      color: host.screenBeingViewed ? root.urgent : root.okColor
                    }
                  }

                  MouseArea {
                    id: tabMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showTab(tabItem.modelData.id)
                  }
                }
              }
            }
          }

          ConnectTab {
            id: connectTab
            width: parent.width
            visible: root.tab === "connect" && !root.takeover
            panel: root
            store: store
            flickable: flick
          }

          MachineTab {
            id: machineTab
            width: parent.width
            visible: root.tab === "machine" && !root.takeover
            panel: root
            store: store
            host: host
          }

          SetupView {
            id: setupView
            width: parent.width
            visible: root.setupOpen
            panel: root
            store: store
            host: host
          }

          ConnectionForm {
            id: form
            width: parent.width
            visible: root.formOpen
            panel: root
            store: store
          }
        }
      }
    }
  }
}
