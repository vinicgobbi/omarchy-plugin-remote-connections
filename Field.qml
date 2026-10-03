import QtQuick
import qs.Ui

// The shell's TextField, keeping Return/Enter to itself. A plain TextField
// emits `accepted` and then lets the key travel on to the popup's key
// handler, and by then whatever `accepted` did (saving the form, creating a
// folder) has usually taken the focus away from it, so the same Return also
// opened or connected the row under the keyboard cursor.
TextField {
  id: field
  Keys.onReturnPressed: function(event) {
    event.accepted = true
    field.accepted()
  }
  Keys.onEnterPressed: function(event) {
    event.accepted = true
    field.accepted()
  }
}
