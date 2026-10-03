import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// One folder in the Connect tab: click (or ↵/→) opens it. Shows what's
// inside — how many connections and subfolders, and which protocols — and,
// from ⋯ or a right-click, Rename and Delete (which keeps the connections:
// they move up one level). The ~/.ssh/config pseudo-folder is read-only.
Column {
  id: row

  property var view: null
  property var panel: null
  property var store: null
  property var folder: null
  property string rowKey: ""

  readonly property bool readOnly: folder.readOnly === true
  readonly property bool isSelected: view.selectedKey === rowKey || view.hoveredKey === rowKey
  readonly property bool menuOpen: view.menuKey === rowKey
  readonly property bool renaming: view.renameKey === rowKey
  readonly property bool confirmingDelete: view.pendingDeleteKey === rowKey
  readonly property bool lit: isSelected || menuOpen || renaming

  readonly property string summary: {
    if (readOnly) return folder.count + (folder.count === 1 ? " host" : " hosts") + " · read-only"
    var parts = []
    if (folder.folders > 0) parts.push(folder.folders + (folder.folders === 1 ? " folder" : " folders"))
    if (folder.count > 0) parts.push(folder.count + (folder.count === 1 ? " connection" : " connections"))
    return parts.length > 0 ? parts.join(" · ") : "Empty"
  }

  spacing: Style.space(4)

  Rectangle {
    width: parent.width
    height: rowLine.implicitHeight + Style.space(14)
    radius: Style.cornerRadius
    color: row.lit ? Util.alpha(panel.accent, 0.12) : "transparent"
    border.width: row.lit ? Style.normalBorderWidth : 0
    border.color: Util.alpha(panel.accent, 0.35)

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
      enabled: !row.renaming
      cursorShape: Qt.PointingHandCursor
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) {
          if (!row.readOnly) view.toggleMenu(row.rowKey)
        } else if (view.busyElsewhere(row.rowKey)) {
          view.closeMenus()
          view.hoveredKey = row.rowKey
        } else {
          view.openFolder(row.folder.path)
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
        color: Util.alpha(row.readOnly ? panel.foreground : panel.folderColor, row.readOnly ? 0.08 : 0.16)
        Text {
          anchors.centerIn: parent
          text: row.readOnly ? "󰣀" : (row.folder.count === 0 && row.folder.folders === 0 ? "󰉖" : "󰉋")
          color: row.readOnly ? panel.dim : panel.folderColor
          font.family: panel.fontFamily
          font.pixelSize: Style.font.body
        }
      }

      Column {
        visible: !row.renaming
        width: parent.width - tile.width - rightSide.width - Style.space(20)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        Text {
          width: parent.width
          text: row.folder.name
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: panel.foreground
          font.family: panel.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
        Text {
          width: parent.width
          text: row.summary
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: panel.dim
          font.family: panel.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Field {
        id: renameField
        visible: row.renaming
        width: parent.width - tile.width - rightSide.width - Style.space(20)
        anchors.verticalCenter: parent.verticalCenter
        placeholderText: "Folder name"
        foreground: panel.foreground
        accent: panel.accent
        onVisibleChanged: {
          if (!visible) return
          text = row.folder.name
          Qt.callLater(function() { renameField.forceActiveFocus(); renameField.selectAll() })
        }
        onAccepted: view.renameFolder(row.folder.path, text)
        Keys.onEscapePressed: { view.closeMenus(); panel.focusKeys() }
      }

      Item {
        id: rightSide
        anchors.verticalCenter: parent.verticalCenter
        width: rightRow.implicitWidth
        height: rightRow.implicitHeight

        Row {
          id: rightRow
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(6)

          // What's inside, at a glance.
          Repeater {
            model: row.lit ? [] : row.folder.protocols
            delegate: Text {
              required property string modelData
              anchors.verticalCenter: parent.verticalCenter
              text: panel.protocolIcons[modelData] || ""
              color: Util.alpha(panel.protocolColors[modelData] || panel.dim, 0.7)
              font.family: panel.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          Pill {
            visible: row.renaming
            anchors.verticalCenter: parent.verticalCenter
            text: "Cancel"
            tint: panel.foreground
            fontFamily: panel.fontFamily
            onClicked: { view.closeMenus(); panel.focusKeys() }
          }
          Pill {
            visible: row.renaming
            anchors.verticalCenter: parent.verticalCenter
            text: "Rename"
            filled: true
            tint: panel.accent
            enabled: renameField.text.trim() !== ""
            fontFamily: panel.fontFamily
            onClicked: view.renameFolder(row.folder.path, renameField.text)
          }

          Pill {
            visible: row.lit && !row.renaming && !row.readOnly
            anchors.verticalCenter: parent.verticalCenter
            text: row.menuOpen ? "✕" : "⋯"
            tooltip: row.menuOpen ? "Close (Esc)" : "Rename or delete (right-click, or .)"
            tint: row.menuOpen ? panel.accent : panel.foreground
            fontFamily: panel.fontFamily
            onClicked: view.toggleMenu(row.rowKey)
          }
          Pill {
            visible: row.lit && !row.renaming
            anchors.verticalCenter: parent.verticalCenter
            text: "Open ›"
            tint: panel.accent
            fontFamily: panel.fontFamily
            onClicked: view.openFolder(row.folder.path)
          }
          Text {
            visible: !row.lit
            anchors.verticalCenter: parent.verticalCenter
            text: "›"
            color: panel.dim
            font.family: panel.fontFamily
            font.pixelSize: Style.font.title
          }
        }
      }
    }
  }

  // ⋯ actions
  Flow {
    visible: row.menuOpen
    width: parent.width
    leftPadding: Style.space(48)
    spacing: Style.space(6)

    Pill {
      text: "Rename"
      iconText: "󰏫"
      tint: panel.foreground
      fontFamily: panel.fontFamily
      onClicked: view.startRename(row.rowKey)
    }
    Pill {
      text: "New connection here"
      iconText: "󰐕"
      tint: panel.foreground
      enabled: store.writable
      fontFamily: panel.fontFamily
      onClicked: panel.openForm("new", { group: row.folder.path })
    }
    Pill {
      text: "Delete folder"
      iconText: "󰆴"
      tint: panel.urgent
      fontFamily: panel.fontFamily
      onClicked: {
        view.closeMenus()
        view.pendingDeleteKey = row.rowKey
      }
    }
  }

  Text {
    visible: row.renaming && view.folderError !== ""
    width: parent.width
    leftPadding: Style.space(48)
    text: view.folderError
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: panel.urgent
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
  }

  // Delete confirmation: only the folder goes, never a connection.
  Row {
    visible: row.confirmingDelete
    width: parent.width
    leftPadding: Style.space(48)
    spacing: Style.space(6)

    Text {
      width: parent.width - Style.space(48) - keepBtn.width - deleteBtn.width - Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: "Delete the folder “" + row.folder.name + "”?"
        + (row.folder.count + row.folder.folders > 0
          ? " What's in it moves to " + (Model.parentFolder(row.folder.path) === "" ? "the top level" : "“" + Model.folderName(Model.parentFolder(row.folder.path)) + "”") + "; no connection is deleted."
          : "")
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
        store.deleteFolder(row.folder.path)
        view.pendingDeleteKey = ""
      }
    }
  }
}
