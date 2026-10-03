import QtQuick
import qs.Commons
import qs.Ui

// The ⋯ menu of a row: a small card floating under the ⋯ button, over the
// rows below it (it takes no room in the layout), one action per line with
// its icon and keyboard shortcut, the destructive ones set apart at the
// bottom. `actions`: [{ id, icon, text, detail?, hint?, danger?, enabled?,
// visible? }]; picking one emits `triggered(id)`. `overflow` is how far the
// card sticks out below `bounds`, so the popup can grow to fit it.
Item {
  id: menu

  property var panel: null
  property var actions: []
  property Item bounds: null
  readonly property real overflow: visible && bounds
    ? Math.max(0, menu.mapToItem(bounds, 0, card.y + card.height).y - bounds.height + Style.space(4))
    : 0

  signal triggered(string id)

  readonly property var entries: {
    var shown = actions.filter(function(a) { return a.visible !== false })
    var normal = shown.filter(function(a) { return !a.danger })
    var danger = shown.filter(function(a) { return a.danger })
    return normal.concat(normal.length > 0 && danger.length > 0 ? [{ separator: true }] : [], danger)
  }

  height: 0
  z: 100

  // Soft shadow, so it reads as floating over the list.
  Rectangle {
    x: card.x + Style.space(1)
    y: card.y + Style.space(3)
    width: card.width
    height: card.height
    radius: card.radius
    color: Util.alpha("#000000", 0.35)
  }

  Rectangle {
    id: card
    y: Style.space(4)
    anchors.right: parent.right
    width: Math.min(parent.width, Style.space(250))
    height: list.implicitHeight + Style.space(8)
    radius: Style.cornerRadius
    color: Qt.tint(Color.background, Util.alpha(menu.panel.foreground, 0.05))
    border.width: Style.normalBorderWidth
    border.color: Util.alpha(menu.panel.foreground, 0.14)

    // Swallows clicks and hover between entries, so they don't reach the
    // rows underneath.
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.AllButtons
    }

    Column {
      id: list
      x: Style.space(4)
      y: Style.space(4)
      width: parent.width - Style.space(8)

      Repeater {
        model: menu.entries
        delegate: Item {
          id: entry
          required property var modelData
          readonly property bool separator: modelData.separator === true
          readonly property bool danger: modelData.danger === true
          readonly property color tint: danger ? menu.panel.urgent : menu.panel.foreground
          width: list.width
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
              x: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              horizontalAlignment: Text.AlignHCenter
              text: entry.modelData.icon || ""
              color: entry.danger ? menu.panel.urgent : (mouse.containsMouse ? menu.panel.accent : menu.panel.dim)
              font.family: menu.panel.fontFamily
              font.pixelSize: Style.font.body
            }

            Column {
              id: labels
              anchors.left: icon.right
              anchors.leftMargin: Style.space(8)
              anchors.right: keycap.visible ? keycap.left : parent.right
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
  }
}
