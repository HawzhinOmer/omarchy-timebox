import QtQuick
import Quickshell
import Quickshell.Io
import "TimeboxModel.js" as Model

// Background service: sends a desktop notification when a timebox starts.
// Runs once per shell (not per bar), so reminders keep working without the
// bar widget and never arrive twice on multi-monitor setups.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  property var shell: null
  property var manifest: null

  property string dataDir: Quickshell.env("HOME") + "/.local/share/omarchy-timebox"
  property date now: clock.date
  readonly property string dateKey: Qt.formatDate(now, "yyyy-MM-dd")
  property var slots: Model.emptyDay().slots
  // "<date>@<slot>" of the last block announced, so a reload in the same
  // minute can't send it twice.
  property string lastSent: ""

  function minuteOfDay() {
    return root.now.getHours() * 60 + root.now.getMinutes()
  }

  function check() {
    var run = Model.runStartingAt(root.slots, root.minuteOfDay())
    if (!run) return
    var key = root.dateKey + "@" + run.start
    if (key === root.lastSent) return
    root.lastSent = key
    root.notify(run)
  }

  function notify(run) {
    Quickshell.execDetached([
      root.omarchyPath + "/bin/omarchy-notification-send",
      "--app-name", "Timebox Planner",
      "-g", "󰃰",
      "-u", "normal",
      "-t", "10000",
      run.text,
      Model.slotTime(run.start) + " – " + Model.slotTime(run.start + run.len),
      "--exec", "omarchy-shell", "shell", "summon", "hawzhin.timebox", "{}"
    ])
  }

  function nextReminder() {
    var runs = Model.computeRuns(root.slots).runs
    var minute = root.minuteOfDay()
    for (var r = 0; r < runs.length; r++) {
      if (Model.slotMinutes(runs[r].start) > minute)
        return Model.slotTime(runs[r].start) + " " + runs[r].text
    }
    return "none left today"
  }

  onSlotsChanged: check()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      root.now = date
      dayFile.reload()
      root.check()
    }
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
    target: "hawzhin.timebox.reminders"
    function next(): string { return root.nextReminder() }
  }
}
