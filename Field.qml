import QtQuick
import qs.Commons
import qs.Ui

// The shell's TextField, keeping Return/Enter to itself and scrolling into
// view when it gets the focus (Tab through a long form on a short screen). A plain TextField
// emits `accepted` and then lets the key travel on to the popup's key
// handler, and by then whatever `accepted` did (saving the form, creating a
// folder) has usually taken the focus away from it, so the same Return also
// opened or connected the row under the keyboard cursor.
TextField {
  id: field

  onActiveFocusChanged: if (activeFocus) Qt.callLater(reveal)

  // Nudges the closest Flickable around it so the whole field shows.
  function reveal() {
    var flick = field.parent
    while (flick && flick.flickableDirection === undefined) flick = flick.parent
    if (!flick || !flick.contentItem) return
    var top = field.mapToItem(flick.contentItem, 0, 0).y - Style.space(8)
    var bottom = top + field.height + Style.space(16)
    var y = flick.contentY
    if (bottom > y + flick.height) y = bottom - flick.height
    if (top < y) y = top
    flick.contentY = Math.max(0, Math.min(y, flick.contentHeight - flick.height))
  }
  Keys.onReturnPressed: function(event) {
    event.accepted = true
    field.accepted()
  }
  Keys.onEnterPressed: function(event) {
    event.accepted = true
    field.accepted()
  }
}
