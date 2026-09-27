.pragma library

// Schedule covers 5 AM through the 11 PM row, in half-hour slots, like the paper planner.
var START_HOUR = 5
var END_HOUR = 23
var ROWS = END_HOUR - START_HOUR + 1
var SLOTS = ROWS * 2
var PRIORITIES = 3

function pad(n) {
  return n < 10 ? "0" + n : "" + n
}

function slotKey(i) {
  return pad(START_HOUR + Math.floor(i / 2)) + ":" + (i % 2 === 0 ? "00" : "30")
}

function hourLabel(row) {
  var h = (START_HOUR + row) % 12
  return "" + (h === 0 ? 12 : h)
}

function emptyDay() {
  var slots = []
  for (var i = 0; i < SLOTS; i++) slots.push("")
  var priorities = []
  for (var p = 0; p < PRIORITIES; p++) priorities.push({ text: "", done: false })
  return { slots: slots, priorities: priorities, brainDump: "" }
}

function parseDay(raw) {
  var day = emptyDay()
  var data = null
  try { data = JSON.parse(raw || "{}") } catch (e) { data = null }
  if (!data || typeof data !== "object") return day

  if (data.slots && typeof data.slots === "object") {
    for (var i = 0; i < SLOTS; i++) {
      var v = data.slots[slotKey(i)]
      if (typeof v === "string") day.slots[i] = v
    }
  }
  if (Array.isArray(data.priorities)) {
    for (var p = 0; p < PRIORITIES && p < data.priorities.length; p++) {
      var item = data.priorities[p] || {}
      day.priorities[p] = { text: String(item.text || ""), done: !!item.done }
    }
  }
  if (typeof data.brainDump === "string") day.brainDump = data.brainDump
  return day
}

function serializeDay(dateKey, day) {
  var slots = {}
  for (var i = 0; i < SLOTS; i++) {
    if (day.slots[i]) slots[slotKey(i)] = day.slots[i]
  }
  return JSON.stringify({
    date: dateKey,
    priorities: day.priorities,
    brainDump: day.brainDump,
    slots: slots
  }, null, 2) + "\n"
}

// Consecutive slots holding the same text form one run; runs of two or more
// slots are drawn as a boxed timebox.
function computeRuns(slots) {
  var runOf = []
  var runs = []
  for (var i = 0; i < slots.length; i++) {
    var text = slots[i]
    if (!text) { runOf.push(-1); continue }
    if (i > 0 && runOf[i - 1] >= 0 && slots[i - 1] === text) {
      runs[runOf[i - 1]].len++
      runOf.push(runOf[i - 1])
    } else {
      runs.push({ start: i, len: 1, text: text })
      runOf.push(runs.length - 1)
    }
  }
  return { runOf: runOf, runs: runs }
}
