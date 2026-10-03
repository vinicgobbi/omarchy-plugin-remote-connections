import QtQuick
import qs.Commons
import qs.Ui

// A floating menu (see Popover.qml): one action per line with its icon and
// keyboard shortcut, the destructive ones set apart at the bottom. Used for
// the rows' ⋯ menu and, as a folder tree, for Move to. `actions`:
// [{ id, icon, text, detail?, hint?, danger?, enabled?, visible?, indent?,
// checked? }]; picking one emits `triggered(id)`. Anything declared inside
// goes below the list (Move to's new-folder field).
Popover {
  id: menu

  property var actions: []
  property string title: ""

  signal triggered(string id)

  readonly property var entries: {
    var shown = actions.filter(function(a) { return a.visible !== false })
    var normal = shown.filter(function(a) { return !a.danger })
    var danger = shown.filter(function(a) { return a.danger })
    return normal.concat(normal.length > 0 && danger.length > 0 ? [{ separator: true }] : [], danger)
  }

  Text {
    visible: menu.title !== ""
    width: parent.width
    leftPadding: Style.space(8)
    rightPadding: Style.space(8)
    topPadding: Style.space(4)
    bottomPadding: Style.space(4)
    text: menu.title
    textFormat: Text.PlainText
    elide: Text.ElideRight
    color: menu.panel.dim
    font.family: menu.panel.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }

  Repeater {
    model: menu.entries
    delegate: Item {
      id: entry
      required property var modelData
      readonly property bool separator: modelData.separator === true
      readonly property bool danger: modelData.danger === true
      readonly property bool checked: modelData.checked === true
      readonly property color tint: danger ? menu.panel.urgent : (checked ? menu.panel.accent : menu.panel.foreground)
      width: parent.width
      height: separator ? Style.space(9) : line.height

      Rectangle {
        visible: entry.separator
        anchors.verticalCenter: parent.verticalCenter
        x: Style.space(8)
        width: parent.width - Style.space(16)
        height: Style.normalBorderWidth
        color: Util.alpha(menu.panel.foreground, 0.1)
      }

      Rectangle {
        id: line
        visible: !entry.separator
        enabled: entry.modelData.enabled !== false
        width: parent.width
        height: labels.implicitHeight + Style.space(12)
        radius: Style.cornerRadius
        opacity: enabled ? 1 : 0.4
        color: mouse.containsMouse && enabled ? Util.alpha(entry.tint, 0.1) : "transparent"

        Text {
          id: icon
          x: Style.space(8) + Style.space(14) * (entry.modelData.indent || 0)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(18)
          horizontalAlignment: Text.AlignHCenter
          text: entry.modelData.icon || ""
          color: entry.danger ? menu.panel.urgent
            : entry.modelData.iconColor ? entry.modelData.iconColor
            : (mouse.containsMouse || entry.checked ? menu.panel.accent : menu.panel.dim)
          font.family: menu.panel.fontFamily
          font.pixelSize: Style.font.body
        }

        Column {
          id: labels
          anchors.left: icon.right
          anchors.leftMargin: Style.space(8)
          anchors.right: keycap.visible ? keycap.left : (check.visible ? check.left : parent.right)
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(1)
          Text {
            width: parent.width
            text: entry.modelData.text || ""
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: entry.tint
            font.family: menu.panel.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: entry.checked
          }
          Text {
            visible: (entry.modelData.detail || "") !== ""
            width: parent.width
            text: entry.modelData.detail || ""
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: menu.panel.dim
            font.family: menu.panel.fontFamily
            font.pixelSize: Style.font.caption - 1
          }
        }

        // The key that does the same from the keyboard.
        Rectangle {
          id: keycap
          visible: (entry.modelData.hint || "") !== ""
          anchors.right: parent.right
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(height, hintText.implicitWidth + Style.space(8))
          height: hintText.implicitHeight + Style.space(2)
          radius: Style.space(3)
          color: "transparent"
          border.width: Style.normalBorderWidth
          border.color: Util.alpha(menu.panel.foreground, 0.18)
          Text {
            id: hintText
            anchors.centerIn: parent
            text: entry.modelData.hint || ""
            color: menu.panel.dim
            font.family: menu.panel.fontFamily
            font.pixelSize: Style.font.caption - 1
          }
        }

        Text {
          id: check
          visible: entry.checked && !keycap.visible
          anchors.right: parent.right
          anchors.rightMargin: Style.space(10)
          anchors.verticalCenter: parent.verticalCenter
          text: "󰄬"
          color: menu.panel.accent
          font.family: menu.panel.fontFamily
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: menu.triggered(entry.modelData.id)
        }
      }
    }
  }
}
