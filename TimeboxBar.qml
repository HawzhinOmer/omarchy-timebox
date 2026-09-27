import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "TimeboxModel.js" as Model

// Bar label for the timebox planner: the block you're in now and how long is
// left of it, or the next block when nothing is scheduled right now.
// Left click opens the planner.
BarWidget {
  id: root
  moduleName: "hawzhin.timebox"

  readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/omarchy-timebox"
  readonly property int maxLength: Number(setting("maxLength", 28)) || 28
  readonly property bool showNext: String(setting("showNext", true)) !== "false"
  readonly property string icon: "󰃰"

  property date now: clock.date
  readonly property string dateKey: Qt.formatDate(now, "yyyy-MM-dd")
  property var slots: Model.emptyDay().slots
  readonly property var info: Model.computeRuns(slots)

  readonly property int nowMinutes: now.getHours() * 60 + now.getMinutes()
  readonly property int nowSlot: {
    var i = (now.getHours() - Model.START_HOUR) * 2 + (now.getMinutes() >= 30 ? 1 : 0)
    return i >= 0 && i < Model.SLOTS ? i : -1
  }
  readonly property var current: nowSlot >= 0 && info.runOf[nowSlot] >= 0 ? info.runs[info.runOf[nowSlot]] : null
  readonly property var next: {
    for (var r = 0; r < info.runs.length; r++) {
      if (slotMinutes(info.runs[r].start) > nowMinutes) return info.runs[r]
    }
    return null
  }

  readonly property string labelText: {
    if (current) return clip(current.text) + " · " + duration(slotMinutes(current.start + current.len) - nowMinutes)
    if (next && showNext) return "Next " + slotTime(next.start) + " " + clip(next.text)
    return ""
  }

  readonly property string tooltip: {
    var lines = []
    if (current) lines.push("Now: " + current.text + "  (" + slotTime(current.start) + "–" + slotTime(current.start + current.len) + ")")
    if (next) lines.push("Next: " + next.text + "  (" + slotTime(next.start) + ")")
    if (!lines.length) lines.push("Nothing else planned today")
    lines.push("Click to open the planner")
    return lines.join("\n")
  }

  function slotMinutes(i) {
    return Model.START_HOUR * 60 + i * 30
  }

  function slotTime(i) {
    var m = slotMinutes(i)
    return Qt.formatTime(new Date(2000, 0, 1, Math.floor(m / 60), m % 60), "h:mm AP")
  }

  function duration(minutes) {
    if (minutes < 60) return minutes + "m"
    var h = Math.floor(minutes / 60), m = minutes % 60
    return m ? h + "h " + m + "m" : h + "h"
  }

  function clip(text) {
    return text.length > maxLength ? text.slice(0, maxLength - 1) + "…" : text
  }

  function refresh() {
    root.now = new Date()
    dayFile.reload()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    // Re-read each minute too: the planner saves by replacing the file,
    // and today's file may not exist yet when the bar starts.
    onDateChanged: dayFile.reload()
  }

  FileView {
    id: dayFile
    path: root.dataDir + "/" + root.dateKey + ".json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var day = Model.parseDay(text())
      root.slots = day ? day.slots : Model.emptyDay().slots
    }
    onLoadFailed: root.slots = Model.emptyDay().slots
    onFileChanged: reload()
  }

  IpcHandler {
    target: "hawzhin.timebox.bar"
    function refresh(): void { root.broadcast("refresh") }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical || !root.labelText ? root.icon : root.icon + "  " + root.labelText
    dimmed: !root.current
    tooltipText: root.tooltip
    horizontalMargin: 8.75
    onPressed: function(b) {
      if (root.bar) root.bar.run("omarchy-shell shell toggle hawzhin.timebox")
    }
  }
}
