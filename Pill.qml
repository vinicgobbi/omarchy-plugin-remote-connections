import QtQuick
import qs.Commons
import qs.Ui

// Small text button used across the popup: outlined by default, `filled`
// for the one primary action in a spot.
Rectangle {
  id: pill

  property string text: ""
  property string iconText: ""
  property string tooltip: ""
  property color tint: Color.accent
  property string fontFamily: Style.font.family
  property bool filled: false
  property bool bold: filled

  signal clicked()

  implicitWidth: row.implicitWidth + Style.space(20)
  implicitHeight: Style.font.caption + Style.space(14)
  radius: Style.cornerRadius
  opacity: enabled ? 1 : 0.4
  color: filled
    ? (mouse.containsMouse ? Qt.lighter(tint, 1.12) : tint)
    : (mouse.containsMouse ? Util.alpha(tint, 0.12) : "transparent")
  border.width: filled ? 0 : Style.normalBorderWidth
  border.color: Util.alpha(tint, 0.55)

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Text {
      visible: pill.iconText !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: pill.iconText
      color: pill.filled ? Color.background : pill.tint
      font.family: pill.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      visible: pill.text !== ""
      anchors.verticalCenter: parent.verticalCenter
      text: pill.text
      textFormat: Text.PlainText
      color: pill.filled ? Color.background : pill.tint
      font.family: pill.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: pill.bold
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: pill.enabled
    cursorShape: Qt.PointingHandCursor
    onClicked: pill.clicked()
  }

  PanelToolTip {
    visible: pill.tooltip !== "" && mouse.containsMouse
    text: pill.tooltip
    fontFamily: pill.fontFamily
  }
}
