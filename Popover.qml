import QtQuick
import qs.Commons
import qs.Ui

// A card floating under its row, over the rows below it: it takes no room in
// the layout, so opening it never pushes the list around. Used by the ⋯
// menu (ActionMenu.qml), Move to, the RDP password prompt and the delete
// confirmations. Children go inside the card, stacked in a column.
// `overflow` is how far the card sticks out below `bounds`, so the popup can
// grow to fit it.
Item {
  id: pop

  property var panel: null
  property Item bounds: null
  property real cardWidth: Style.space(250)
  property real padding: Style.space(4)
  default property alias content: body.data

  readonly property real overflow: visible && bounds
    ? Math.max(0, pop.mapToItem(bounds, 0, card.y + card.height).y - bounds.height + Style.space(4))
    : 0

  height: 0
  z: 100

  // Scroll it into view once it has its size (bounds is the tab, which knows
  // how to scroll the list).
  onVisibleChanged: if (visible && bounds && bounds.reveal) Qt.callLater(function() { pop.bounds.reveal(card) })

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
    anchors.right: parent.right
    y: Style.space(4)
    width: Math.min(parent.width, pop.cardWidth)
    height: body.implicitHeight + pop.padding * 2
    radius: Style.cornerRadius
    color: Qt.tint(Color.background, Util.alpha(pop.panel.foreground, 0.05))
    border.width: Style.normalBorderWidth
    border.color: Util.alpha(pop.panel.foreground, 0.14)

    // Swallows clicks and hover on the card, so they don't reach the rows
    // underneath.
    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.AllButtons
    }

    Column {
      id: body
      x: pop.padding
      y: pop.padding
      width: parent.width - pop.padding * 2
    }
  }
}
