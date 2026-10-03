import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The bar icon and its popup: your remote connections (ConnectTab.qml).
// The add/edit form (ConnectionForm.qml) and Setup (SetupView.qml, the gear)
// take over the popup while open. They read colors and shared state from
// here through their `panel` property.
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
  property string formId: ""              // "" closed, "new", or a connection id
  property var formSeed: null             // prefill for "new" (e.g. from ~/.ssh/config)
  readonly property bool formOpen: formId !== ""
  // Setup (the gear): installs the clients the connections need.
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

  readonly property string tooltipText: {
    var lines = [store.connections.length === 0 ? "Remote Connections" : "Remote Connections · " + store.connections.length + " saved"]
    if (store.sessions.length > 0) lines.push(store.sessions.length + " open session(s)")
    return lines.join("\n")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    if (opened) {
      store.refresh()
      store.probeAll()
    } else {
      closeForm()
      setupOpen = false
      connectTab.reset()
    }
  }

  ConnectionStore {
    id: store
    watchSessions: root.opened
    changes: changes
  }

  // Reviews and applies installs/removals in its own centered window, so the
  // popup gets out of the way while it's up.
  ChangeSheet {
    id: changes
    okColor: root.okColor
    warnColor: root.warnColor
    fontFamily: root.fontFamily
    onStageChanged: if (stage === "review" && root.opened) root.close()
  }

  // Re-probe while the list is showing.
  Timer {
    interval: 30000
    repeat: true
    running: root.opened && !root.takeover
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
          text: "󰒍"
          color: root.barForeground
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
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: {
        if (root.formOpen) root.closeForm()
        else if (root.setupOpen) root.setupOpen = false
        else if (!connectTab.handleEscape()) root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onMoveRequested: function(dx, dy) {
        if (!root.takeover && dy !== 0) connectTab.moveCursor(dy)
      }
      onActivateRequested: if (!root.takeover) connectTab.activateCursor()
      onDeleteRequested: if (!root.takeover) connectTab.deleteCursor()
      onTextKey: function(t) {
        if (root.takeover) return
        if (t === "n" || t === "N") root.openForm("new", null)
        else connectTab.textKey(t)
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

          // --- Header: title and the Setup gear ---
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
              width: parent.width - gear.width - (root.setupOpen ? Style.space(52) : Style.space(8))
              anchors.verticalCenter: parent.verticalCenter
              text: root.setupOpen ? "Setup" : "Remote Connections"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
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
                  ? "Setup · " + store.neededMissing.length + " needed client(s) not installed"
                  : "Setup · install the SSH, RDP and VNC clients"
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

          ConnectTab {
            id: connectTab
            width: parent.width
            visible: !root.takeover
            panel: root
            store: store
            flickable: flick
          }

          SetupView {
            id: setupView
            width: parent.width
            visible: root.setupOpen
            panel: root
            store: store
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
