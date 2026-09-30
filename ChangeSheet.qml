import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// The review sheet for every change that needs administrator rights (and
// the few that run as you). A centered window of its own, so it survives the
// popup closing and sits where Omarchy's password dialog appears:
//
//   review  → what changes, how to undo it, and the exact commands (always
//             visible; each step can be left out). "Run in terminal
//             instead" and "Copy commands" for people who'd rather do it
//             themselves.
//   apply   → one `pkexec /usr/bin/bash -c <script>` running exactly the
//             reviewed commands (Omarchy's polkit dialog asks the password
//             once), with a marker around each step for live progress.
//   done / failed → result, output, and Undo / Retry / Try in terminal.
//
// Plans come from bin/rc-steps. Steps that need a terminal (ssh-keygen,
// ssh-copy-id) never come here: request() hands those to bin/rc-terminal.
Item {
  id: sheet

  property color okColor: Color.accent
  property color warnColor: Color.urgent
  property string fontFamily: Style.font.family

  property string stage: ""            // "" | loading | review | auth | running | done | failed
  property string title: ""
  property var args: []
  property var steps: []               // [{ mode, desc, cmd, included, state, out }]
  property var afters: []
  property var undos: []
  property var reverseArgs: []
  property string error: ""
  property bool copied: false
  property var _callback: null
  property int _current: -1
  property bool _authorized: false

  readonly property bool active: stage !== ""
  readonly property bool busy: stage === "auth" || stage === "running" || stage === "loading"
  readonly property var included: steps.filter(function(s) { return s.included })
  readonly property bool needsAdmin: included.some(function(s) { return s.mode === "root" })
  readonly property color fg: Color.popups.text
  readonly property color dim: Qt.darker(fg, 1.55)
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent

  function bundledPath(name) {
    return decodeURIComponent(String(Qt.resolvedUrl(name)).replace(/^file:\/\//, ""))
  }

  // Start a change. callback(ok, code, message): code 0 done, 1 failed,
  // 2 canceled, 3 terminal closed early, 4 done with steps skipped (the
  // same codes as bin/rc-terminal).
  function request(title, args, callback) {
    if (busy) { if (callback) callback(false, 1, "Another change is still running."); return }
    sheet.title = title
    sheet.args = args
    sheet._callback = callback || null
    sheet.error = ""
    sheet.steps = []
    sheet.afters = []
    sheet.undos = []
    sheet.reverseArgs = []
    sheet.copied = false
    sheet.stage = "loading"
    planProcess.command = [bundledPath("bin/rc-steps")].concat(args)
    planProcess.running = true
  }

  function finish(ok, code, message) {
    var cb = _callback
    _callback = null
    if (cb) cb(ok, code, message || "")
  }

  function close() {
    if (stage === "review" || stage === "loading") finish(false, 2, "")
    if (!busy) stage = ""
    else hidden = true
  }

  // While a change runs, the sheet can be put away; it comes back (and a
  // notification says so) when it's done.
  property bool hidden: false

  function toggleStep(i) {
    var next = steps.slice()
    next[i] = Object.assign({}, next[i], { included: !next[i].included })
    steps = next
  }

  function commandsText() {
    return included.map(function(s) { return (s.mode === "root" ? "sudo bash -c " + JSON.stringify(s.cmd) : s.cmd) }).join("\n")
  }

  function copyCommands() {
    Quickshell.execDetached(["wl-copy", "--", commandsText()])
    copied = true
    copiedTimer.restart()
  }

  function runInTerminal() {
    var cb = _callback
    _callback = null
    stage = ""
    terminalProcess.callback = cb
    terminalProcess.command = [bundledPath("bin/rc-terminal"), title].concat(args)
    terminalProcess.running = true
  }

  // Exactly the reviewed commands, each in a subshell between markers.
  function buildScript() {
    var lines = []
    for (var i = 0; i < steps.length; i++) {
      if (!steps[i].included) continue
      lines.push("printf '::rc-step " + i + " start\\n'")
      lines.push("( " + steps[i].cmd + "\n) 2>&1")
      lines.push("rc=$?; printf '::rc-step " + i + " end %s\\n' \"$rc\"; [ \"$rc\" -eq 0 ] || exit \"$rc\"")
    }
    return lines.join("\n")
  }

  function apply() {
    if (included.length === 0) return
    var mixed = included.some(function(s) { return s.mode !== "root" }) && needsAdmin
    if (mixed) { runInTerminal(); return }
    var next = steps.map(function(s) { return Object.assign({}, s, { state: s.included ? "pending" : "skipped", out: "" }) })
    steps = next
    _current = -1
    _authorized = !needsAdmin
    stage = needsAdmin ? "auth" : "running"
    hidden = false
    var script = buildScript()
    applyProcess.command = needsAdmin ? ["pkexec", "/usr/bin/bash", "-c", script] : ["bash", "-c", script]
    applyProcess.running = true
  }

  function undo() {
    if (reverseArgs.length === 0) return
    request("Undo: " + title, reverseArgs, null)
  }

  function setStep(i, fields) {
    if (i < 0 || i >= steps.length) return
    var next = steps.slice()
    next[i] = Object.assign({}, next[i], fields)
    steps = next
  }

  function onOutputLine(line) {
    var m = line.match(/^::rc-step (\d+) (start|end)(?: (\d+))?$/)
    if (m) {
      var i = parseInt(m[1], 10)
      if (!_authorized) { _authorized = true; stage = "running" }
      if (m[2] === "start") { _current = i; setStep(i, { state: "running" }) }
      else setStep(i, { state: m[3] === "0" ? "ok" : "fail" })
      return
    }
    if (_current >= 0) {
      var s = steps[_current]
      var out = s.out ? s.out + "\n" + line : line
      // Keep the tail; a package install can print a lot.
      var parts = out.split("\n")
      if (parts.length > 40) out = parts.slice(parts.length - 40).join("\n")
      setStep(_current, { out: out })
    }
  }

  function notify(summary, body) {
    Quickshell.execDetached(["notify-send", "-a", "Remote Connections", summary, body])
  }

  Timer {
    id: copiedTimer
    interval: 1500
    onTriggered: sheet.copied = false
  }

  Process {
    id: planProcess
    running: false
    command: []
    stdout: StdioCollector { id: planOut; waitForEnd: true }
    stderr: StdioCollector { id: planErr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        sheet.error = String(planErr.text || "").trim() || "Couldn't plan this change."
        sheet.stage = "failed"
        sheet.finish(false, 1, sheet.error)
        return
      }
      var steps = [], afters = [], undos = [], reverse = []
      var lines = String(planOut.text || "").split("\n")
      var interactive = false
      for (var i = 0; i < lines.length; i++) {
        var f = lines[i].split("\t")
        if (f[0] === "#after") afters.push(f.slice(1).join("\t"))
        else if (f[0] === "#undo") undos.push(f.slice(1).join("\t"))
        else if (f[0] === "#reverse") reverse = f.slice(1).join("\t").split(" ").filter(function(a) { return a !== "" })
        else if (f.length >= 3 && ["root", "user", "interactive"].indexOf(f[0]) >= 0) {
          if (f[0] === "interactive") interactive = true
          steps.push({ mode: f[0], desc: f[1], cmd: f.slice(2).join("\t"), included: true, state: "", out: "" })
        }
      }
      if (steps.length === 0) {
        sheet.stage = ""
        sheet.finish(true, 0, "")
        return
      }
      if (interactive) { sheet.runInTerminal(); return }
      sheet.steps = steps
      sheet.afters = afters
      sheet.undos = undos
      sheet.reverseArgs = reverse
      sheet.hidden = false
      sheet.stage = "review"
    }
  }

  Process {
    id: applyProcess
    running: false
    command: []
    stdout: SplitParser { onRead: function(line) { sheet.onOutputLine(line) } }
    stderr: StdioCollector { id: applyErr; waitForEnd: true }
    onExited: function(exitCode) {
      var hiddenBefore = sheet.hidden
      sheet.hidden = false
      // pkexec: 126 = dialog dismissed, 127 = not authorized.
      if (!sheet._authorized && (exitCode === 126 || exitCode === 127)) {
        sheet.error = "Authorization was canceled; nothing changed."
        sheet.stage = "review"
        return
      }
      if (exitCode === 0) {
        sheet.stage = "done"
        if (hiddenBefore) sheet.notify(sheet.title + ": done", sheet.afters.join(" · "))
        sheet.finish(true, 0, "")
      } else {
        if (sheet._current >= 0 && sheet.steps[sheet._current].state === "running")
          sheet.setStep(sheet._current, { state: "fail" })
        var errText = String(applyErr.text || "").trim()
        sheet.error = errText !== "" ? errText : "A step failed (exit code " + exitCode + ")."
        sheet.stage = "failed"
        sheet.notify(sheet.title + ": couldn't finish", sheet.error)
        sheet.finish(false, 1, sheet.error)
      }
    }
  }

  Process {
    id: terminalProcess
    running: false
    property var callback: null
    command: []
    stderr: StdioCollector { id: terminalErr; waitForEnd: true }
    onExited: function(exitCode) {
      var cb = callback
      callback = null
      if (cb) cb(exitCode === 0, exitCode, String(terminalErr.text || "").trim())
    }
  }

  PanelWindow {
    id: win
    visible: sheet.active && !sheet.hidden && sheet.stage !== "loading"
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-remote-connections-changes"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive while reviewing (Esc/Enter); on demand while it runs so the
    // password dialog and the rest of the desktop stay usable.
    WlrLayershell.keyboardFocus: sheet.stage === "review" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    exclusionMode: ExclusionMode.Ignore
    onVisibleChanged: if (visible) Qt.callLater(function() { keyCatcher.forceActiveFocus() })

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: sheet.close()
    }

    BorderSurface {
      id: card
      width: Math.min(Style.space(640), win.width - Style.gapsOut * 2)
      height: Math.min(body.implicitHeight + card.contentTopInset + card.contentBottomInset, win.height - Style.gapsOut * 2)
      anchors.centerIn: parent
      radius: Style.cornerRadius
      color: Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border",
        sheet.stage === "failed" ? sheet.urgent : (sheet.stage === "done" ? sheet.okColor : sheet.accent),
        Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            sheet.close()
            event.accepted = true
          }
        }
      }

      Flickable {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        contentWidth: width
        contentHeight: body.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: body
          width: parent.width
          spacing: Style.space(12)

          // --- Header ---
          Row {
            width: parent.width
            spacing: Style.space(12)
            Rectangle {
              width: Style.space(36)
              height: width
              radius: Style.cornerRadius
              color: Util.alpha(sheet.stage === "failed" ? sheet.urgent : (sheet.stage === "done" ? sheet.okColor : sheet.accent), 0.14)
              Text {
                anchors.centerIn: parent
                text: sheet.stage === "done" ? "󰄬" : (sheet.stage === "failed" ? "󰀦" : "󰒃")
                color: sheet.stage === "failed" ? sheet.urgent : (sheet.stage === "done" ? sheet.okColor : sheet.accent)
                font.family: sheet.fontFamily
                font.pixelSize: Style.font.title
              }
            }
            Column {
              width: parent.width - Style.space(48)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                width: parent.width
                text: sheet.stage === "done" ? sheet.title + " · done"
                  : sheet.stage === "failed" ? "Couldn't finish: " + sheet.title
                  : sheet.title
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                color: sheet.fg
                font.family: sheet.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                width: parent.width
                text: sheet.stage === "review" ? (sheet.needsAdmin ? "Needs administrator rights · review before applying" : "Runs as you · review before applying")
                  : sheet.stage === "auth" ? "Waiting for your password in the Omarchy dialog…"
                  : sheet.stage === "running" ? "Applying… you can close this; you'll get a notification when it's done."
                  : sheet.stage === "done" ? "All steps applied."
                  : ""
                visible: text !== ""
                wrapMode: Text.Wrap
                color: sheet.dim
                font.family: sheet.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // --- What changes / how to undo ---
          Row {
            visible: sheet.stage === "review" && (sheet.afters.length > 0 || sheet.undos.length > 0)
            width: parent.width
            spacing: Style.space(10)
            Repeater {
              model: [
                { title: "WHAT CHANGES", lines: sheet.afters },
                { title: "TO UNDO", lines: sheet.undos }
              ]
              delegate: Rectangle {
                id: box
                required property var modelData
                visible: modelData.lines.length > 0
                width: (body.width - Style.space(10)) / 2
                height: boxCol.implicitHeight + Style.space(20)
                radius: Style.cornerRadius
                color: Util.alpha(sheet.fg, 0.05)
                Column {
                  id: boxCol
                  x: Style.space(10)
                  y: Style.space(10)
                  width: parent.width - Style.space(20)
                  spacing: Style.space(4)
                  Text {
                    text: box.modelData.title
                    color: sheet.dim
                    font.family: sheet.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    font.letterSpacing: 1
                  }
                  Repeater {
                    model: box.modelData.lines
                    delegate: Text {
                      required property string modelData
                      width: boxCol.width
                      text: "• " + modelData
                      textFormat: Text.PlainText
                      wrapMode: Text.Wrap
                      color: /allowed|off:|every network|internet if/i.test(modelData) && box.modelData.title === "WHAT CHANGES" ? sheet.warnColor : sheet.fg
                      font.family: sheet.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }

          // --- Steps ---
          Text {
            text: sheet.stage === "review"
              ? "COMMANDS · RUN EXACTLY AS SHOWN (" + sheet.included.length + " OF " + sheet.steps.length + ")"
              : "STEPS"
            visible: sheet.steps.length > 0
            color: sheet.dim
            font.family: sheet.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1
          }

          Repeater {
            model: sheet.steps
            delegate: Rectangle {
              id: stepBox
              required property var modelData
              required property int index
              readonly property var s: modelData
              width: body.width
              height: stepCol.implicitHeight + Style.space(16)
              radius: Style.cornerRadius
              opacity: s.included ? 1 : 0.45
              color: "transparent"
              border.width: Style.normalBorderWidth
              border.color: s.state === "fail" ? Util.alpha(sheet.urgent, 0.6)
                : s.state === "running" ? Util.alpha(sheet.accent, 0.6)
                : Util.alpha(sheet.fg, 0.12)

              Row {
                x: Style.space(10)
                y: Style.space(8)
                width: parent.width - Style.space(20)
                spacing: Style.space(10)

                // checkbox in review, state mark afterwards
                Item {
                  width: Style.space(18)
                  height: Style.space(18)
                  Rectangle {
                    visible: sheet.stage === "review"
                    anchors.fill: parent
                    radius: Style.space(4)
                    color: stepBox.s.included ? sheet.accent : "transparent"
                    border.width: Style.normalBorderWidth
                    border.color: stepBox.s.included ? sheet.accent : sheet.dim
                    Text {
                      anchors.centerIn: parent
                      visible: stepBox.s.included
                      text: "✓"
                      color: Color.popups.background
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: sheet.toggleStep(stepBox.index)
                    }
                  }
                  BusyIndicator {
                    visible: sheet.stage !== "review" && stepBox.s.state === "running"
                    running: visible
                    anchors.fill: parent
                  }
                  Text {
                    visible: sheet.stage !== "review" && stepBox.s.state !== "running"
                    anchors.centerIn: parent
                    text: stepBox.s.state === "ok" ? "✓" : stepBox.s.state === "fail" ? "✕" : stepBox.s.state === "skipped" ? "–" : "○"
                    color: stepBox.s.state === "ok" ? sheet.okColor : stepBox.s.state === "fail" ? sheet.urgent : sheet.dim
                    font.family: sheet.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }

                Column {
                  id: stepCol
                  width: parent.width - Style.space(28)
                  spacing: Style.space(6)
                  Row {
                    width: parent.width
                    spacing: Style.space(8)
                    Text {
                      width: parent.width - badge.width - Style.space(8)
                      text: stepBox.s.desc
                      textFormat: Text.PlainText
                      wrapMode: Text.Wrap
                      color: sheet.fg
                      font.family: sheet.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                    Text {
                      id: badge
                      text: sheet.stage === "review"
                        ? (!stepBox.s.included ? "skipped" : stepBox.s.mode === "root" ? "as admin" : "as you")
                        : ({ ok: "done", fail: "failed", running: "running…", skipped: "skipped", pending: "" })[stepBox.s.state] || ""
                      color: stepBox.s.state === "fail" ? sheet.urgent : stepBox.s.state === "ok" ? sheet.okColor : sheet.dim
                      font.family: sheet.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                  Rectangle {
                    width: parent.width
                    height: cmdText.implicitHeight + Style.space(12)
                    radius: Style.cornerRadius
                    color: Util.alpha(sheet.fg, 0.05)
                    Text {
                      id: cmdText
                      x: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - Style.space(16)
                      text: (stepBox.s.mode === "root" ? "# " : "$ ") + stepBox.s.cmd
                      textFormat: Text.PlainText
                      wrapMode: Text.WrapAnywhere
                      color: sheet.accent
                      font.family: sheet.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                  Rectangle {
                    visible: stepBox.s.out !== "" && stepBox.s.out !== undefined
                    width: parent.width
                    height: outText.implicitHeight + Style.space(10)
                    radius: Style.cornerRadius
                    color: Util.alpha(sheet.fg, 0.03)
                    Text {
                      id: outText
                      x: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      width: parent.width - Style.space(16)
                      text: stepBox.s.out || ""
                      textFormat: Text.PlainText
                      wrapMode: Text.WrapAnywhere
                      color: stepBox.s.state === "fail" ? sheet.urgent : sheet.dim
                      font.family: sheet.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }

          Text {
            visible: sheet.error !== ""
            width: parent.width
            text: sheet.error
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            color: sheet.urgent
            font.family: sheet.fontFamily
            font.pixelSize: Style.font.caption
          }

          // --- Warning (review) ---
          Rectangle {
            visible: sheet.stage === "review"
            width: parent.width
            height: warnText.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: "transparent"
            border.width: Style.normalBorderWidth
            border.color: sheet.warnColor
            Text {
              id: warnText
              x: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - Style.space(20)
              text: sheet.needsAdmin
                ? "⚠  These commands change your system and run as administrator. Only apply them if you understand what they do. Omarchy will ask for your password once."
                : "⚠  These commands change files in your home folder. Only apply them if you understand what they do."
              wrapMode: Text.Wrap
              color: sheet.warnColor
              font.family: sheet.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // --- Actions ---
          Row {
            width: parent.width
            spacing: Style.space(8)
            layoutDirection: Qt.RightToLeft

            // review
            Pill {
              visible: sheet.stage === "review"
              text: sheet.needsAdmin ? "Authorize & apply" : "Apply"
              filled: true
              tint: sheet.accent
              enabled: sheet.included.length > 0
              fontFamily: sheet.fontFamily
              onClicked: sheet.apply()
            }
            Pill {
              visible: sheet.stage === "review"
              text: "Cancel"
              tint: sheet.fg
              fontFamily: sheet.fontFamily
              onClicked: sheet.close()
            }
            // running
            Pill {
              visible: sheet.stage === "auth" || sheet.stage === "running"
              text: "Hide"
              tooltip: "Keep it running in the background; a notification says when it's done"
              tint: sheet.fg
              fontFamily: sheet.fontFamily
              onClicked: sheet.hidden = true
            }
            // done
            Pill {
              visible: sheet.stage === "done"
              text: "Done"
              filled: true
              tint: sheet.okColor
              fontFamily: sheet.fontFamily
              onClicked: sheet.stage = ""
            }
            // failed
            Pill {
              visible: sheet.stage === "failed" && sheet.steps.length > 0
              text: "Retry"
              filled: true
              tint: sheet.accent
              fontFamily: sheet.fontFamily
              onClicked: sheet.apply()
            }
            Pill {
              visible: sheet.stage === "failed" && sheet.reverseArgs.length > 0 && sheet.steps.some(function(s) { return s.state === "ok" })
              text: "Undo what ran"
              tint: sheet.fg
              fontFamily: sheet.fontFamily
              onClicked: sheet.undo()
            }
            Pill {
              visible: sheet.stage === "failed"
              text: "Close"
              tint: sheet.fg
              fontFamily: sheet.fontFamily
              onClicked: sheet.stage = ""
            }

            Item { width: Style.space(1); height: 1 }

            // left side (in RTL order: rightmost first)
            Pill {
              visible: sheet.stage === "failed" && sheet.steps.length > 0
              text: "Try in terminal"
              tint: sheet.dim
              fontFamily: sheet.fontFamily
              onClicked: sheet.runInTerminal()
            }
            Pill {
              visible: sheet.stage === "review"
              text: sheet.copied ? "Copied" : "Copy commands"
              tint: sheet.dim
              fontFamily: sheet.fontFamily
              onClicked: sheet.copyCommands()
            }
            Pill {
              visible: sheet.stage === "review"
              text: "Run in terminal instead"
              tint: sheet.dim
              fontFamily: sheet.fontFamily
              onClicked: sheet.runInTerminal()
            }
          }
        }
      }
    }
  }
}
