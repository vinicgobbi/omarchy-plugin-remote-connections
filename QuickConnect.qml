import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Keyboard-first quick connect: type to filter saved connections and
// ~/.ssh/config hosts, Enter connects. Summoned with
// `omarchy-shell shell toggle vinicgobbi.remote-connections`.
// Structure follows the built-in emoji picker (omarchy.emojis).
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  // RDP connection waiting for its password (see store.needsPassword).
  property var passwordConn: null
  property bool rememberPassword: true
  property int selectedIndex: 0

  readonly property var protocolIcons: ({ ssh: "󰆍", rdp: "󰍹", vnc: "󰢹" })
  readonly property var results: Model.quickList(store.connections, store.sshHosts, filterText)

  // Same [menu] surface tokens as the emoji picker/Omarchy menu, so themes
  // that style those style this too.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color urgent: Color.urgent
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int contentSpacing: Style.spacing.md
  property int rowHeight: Math.max(Style.space(46), Style.font.body + Style.font.caption + Style.space(18))
  property int cardWidth: Math.min(Style.space(520), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(460), panel.height - Style.gapsOut * 2)

  function cancelPassword() {
    root.passwordConn = null
    pwField.text = ""
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function submitPassword() {
    var c = root.passwordConn
    if (!c || pwField.text === "") return
    var pw = pwField.text
    pwField.text = ""
    root.passwordConn = null
    root.dismiss()
    store.connectWithPassword(c.id, c.user, pw, root.rememberPassword, null)
  }

  function open(payloadJson) {
    root.passwordConn = null
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    store.refresh()
    store.probeAll()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "vinicgobbi.remote-connections")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    resultList.positionViewAtBeginning()
  }

  function select(delta) {
    var n = root.results.length
    if (n === 0) return
    root.selectedIndex = Math.max(0, Math.min(n - 1, root.selectedIndex + delta))
    resultList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function clientMissing(c) {
    return store.clientsChecked && !store.hasClient(c.protocol)
  }

  // Missing client → offer the install (a terminal asking for sudo) instead
  // of failing; the notification from rc-connect would say the same thing.
  function activate(index) {
    var c = root.results[index]
    if (!c) return
    if (!clientMissing(c) && store.needsPassword(c)) {
      root.rememberPassword = true
      root.passwordConn = c
      Qt.callLater(function() { pwField.forceActiveFocus() })
      return
    }
    root.dismiss()
    if (clientMissing(c)) store.installClient(c.protocol)
    else store.connect(c.id)
  }

  ConnectionStore {
    id: store
    changes: changes
  }

  // Installing a missing client from here goes through the same review.
  ChangeSheet {
    id: changes
    fontFamily: root.fontFamily
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-remote-connections"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && event.modifiers & Qt.ControlModifier)) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab || (event.key === Qt.Key_J && event.modifiers & Qt.ControlModifier)) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Backtab) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            root.select(-Math.max(1, Math.floor(resultList.height / root.rowHeight)))
            event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            root.select(Math.max(1, Math.floor(resultList.height / root.rowHeight)))
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate(root.selectedIndex)
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.passwordConn ? "Password for " + root.passwordConn.name : (root.filterText || "Connect to…")
            color: root.foreground
            opacity: root.filterText || root.passwordConn ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }
        }

        // Password for an RDP connection with none saved.
        Column {
          id: pwBox
          visible: root.passwordConn !== null
          width: parent.width
          spacing: Style.space(8)
          Text {
            width: parent.width
            text: root.passwordConn ? Model.subtitle(root.passwordConn) : ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          TextField {
            id: pwField
            width: parent.width
            password: true
            placeholderText: "Password"
            foreground: root.foreground
            accent: Color.accent
            onAccepted: root.submitPassword()
            Keys.onEscapePressed: root.cancelPassword()
          }
          Toggle {
            width: parent.width
            label: "Remember in keyring"
            description: root.rememberPassword ? "Next time it connects without asking." : "Used once, then deleted."
            checked: root.rememberPassword
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            onClicked: root.rememberPassword = !root.rememberPassword
          }
        }

        Item {
          visible: root.passwordConn === null
          width: parent.width
          height: parent.height - root.headerHeight - hint.height - root.contentSpacing * 2

          ListView {
            id: resultList
            anchors.fill: parent
            model: root.results
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: row
              required property var modelData
              required property int index
              readonly property bool selected: index === root.selectedIndex
              readonly property bool missing: root.clientMissing(modelData)

              width: resultList.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: selected ? root.selectedBackground : "transparent"

              Row {
                anchors.fill: parent
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(12)

                Text {
                  id: icon
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.protocolIcons[row.modelData.protocol] || ""
                  color: row.selected ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }

                Column {
                  width: parent.width - icon.width - badge.width - Style.space(24)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: row.modelData.name
                    color: row.selected ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: row.missing
                      ? "Needs the '" + Model.clientPackage(row.modelData.protocol) + "' package — Enter installs it"
                      : Model.subtitle(row.modelData)
                    color: row.missing ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }

                Text {
                  id: badge
                  anchors.verticalCenter: parent.verticalCenter
                  readonly property var reach: store.reachOf(row.modelData.id)
                  text: (row.modelData.favorite ? "󰓎  " : "")
                    + (reach.state === "up" ? "● up" : reach.state === "down" ? "● down" : reach.state === "checking" ? "● …" : "")
                  color: reach.state === "down" ? root.urgent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) root.selectedIndex = row.index
                onClicked: root.activate(row.index)
              }
            }
          }

          Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: Style.space(8)
            visible: root.results.length === 0

            Text {
              text: "󰒍"
              color: root.selectedText
              opacity: 0.8
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.filterText !== ""
                ? "No matches for “" + root.filterText + "”"
                : "No connections yet — add one from the bar icon"
              color: root.foreground
              opacity: 0.7
              wrapMode: Text.Wrap
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              horizontalAlignment: Text.AlignHCenter
              width: parent.width
            }
          }
        }

        Text {
          id: hint
          width: parent.width
          text: root.passwordConn ? "Enter connect · Esc back" : "Enter connect · ↑↓ select · Esc close"
          color: root.dim
          horizontalAlignment: Text.AlignHCenter
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
