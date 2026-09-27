.pragma library

// Schedule covers 7 AM through the 11 PM row, in half-hour slots.
var START_HOUR = 7
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
  return {
    slots: slots, priorities: priorities,
    brainDump: "", brainDump2: "",
    slotColors: {}, otherSlots: {}, extra: {}
  }
}

var KNOWN_FIELDS = ["date", "priorities", "brainDump", "brainDump2", "slots", "slotColors"]

// Returns null when the file has content that isn't a valid day, so callers
// can refuse to overwrite it instead of treating it as an empty day.
function parseDay(raw) {
  var day = emptyDay()
  if (!raw || !String(raw).trim()) return day
  var data = null
  try { data = JSON.parse(raw) } catch (e) { return null }
  if (!data || typeof data !== "object" || Array.isArray(data)) return null

  if (data.slots && typeof data.slots === "object") {
    for (var i = 0; i < SLOTS; i++) {
      var v = data.slots[slotKey(i)]
      if (typeof v === "string") day.slots[i] = v
    }
    // Entries outside the visible hours (e.g. saved when the day started
    // earlier) are kept as-is so saving never drops them.
    var shown = {}
    for (var k = 0; k < SLOTS; k++) shown[slotKey(k)] = true
    for (var key in data.slots) {
      if (!shown[key]) day.otherSlots[key] = data.slots[key]
    }
  }
  if (Array.isArray(data.priorities)) {
    for (var p = 0; p < PRIORITIES && p < data.priorities.length; p++) {
      var item = data.priorities[p] || {}
      day.priorities[p] = { text: String(item.text || ""), done: !!item.done }
      if (typeof item.color === "string" && item.color) day.priorities[p].color = item.color
    }
  }
  if (typeof data.brainDump === "string") day.brainDump = data.brainDump
  if (typeof data.brainDump2 === "string") day.brainDump2 = data.brainDump2
  if (data.slotColors && typeof data.slotColors === "object" && !Array.isArray(data.slotColors)) {
    for (var c in data.slotColors) {
      if (typeof data.slotColors[c] === "string") day.slotColors[c] = data.slotColors[c]
    }
  }
  // Fields written by a newer version are carried through untouched.
  for (var f in data) {
    if (KNOWN_FIELDS.indexOf(f) === -1) day.extra[f] = data[f]
  }
  return day
}

function serializeDay(dateKey, day) {
  var slots = {}
  var other = day.otherSlots || {}
  for (var key in other) slots[key] = other[key]
  for (var i = 0; i < SLOTS; i++) {
    if (day.slots[i]) slots[slotKey(i)] = day.slots[i]
  }
  var out = {}
  var extra = day.extra || {}
  for (var f in extra) out[f] = extra[f]
  out.date = dateKey
  out.priorities = day.priorities
  out.brainDump = day.brainDump
  if (day.brainDump2) out.brainDump2 = day.brainDump2
  out.slots = slots
  var colors = day.slotColors || {}
  if (Object.keys(colors).length) out.slotColors = colors
  return JSON.stringify(out, null, 2) + "\n"
}

// Brain dump notes are stored as rich text (so words can be colored). Older
// files hold plain text; turn that into equivalent HTML on load.
function isRichText(text) {
  return /^\s*<(!DOCTYPE|html|p[\s>]|body)/i.test(text || "")
}

function plainToHtml(text) {
  return String(text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/\n/g, "<br>")
}

// Keep only colors from Qt's generated HTML, so the stored note follows the
// planner's current font and size instead of freezing the ones in use today.
function cleanRichText(html) {
  return String(html || "")
    .replace(/font-family:[^;"]*;?/g, "")
    .replace(/font-size:[^;"]*;?/g, "")
    .replace(/font-weight:[^;"]*;?/g, "")
    .replace(/font-style:[^;"]*;?/g, "")
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

function slotMinutes(i) {
  return START_HOUR * 60 + i * 30
}

// "9:30 AM" style, matching the bar clock.
function slotTime(i) {
  var m = slotMinutes(i)
  var h = Math.floor(m / 60) % 24
  return (h % 12 === 0 ? 12 : h % 12) + ":" + pad(m % 60) + (h < 12 ? " AM" : " PM")
}

// The block (run) that starts exactly at the given minute of the day, if any.
function runStartingAt(slots, minuteOfDay) {
  var runs = computeRuns(slots).runs
  for (var r = 0; r < runs.length; r++) {
    if (slotMinutes(runs[r].start) === minuteOfDay) return runs[r]
  }
  return null
}

// Reminder modes, cycled from the planner and stored in settings.json.
// Each mode lists how many minutes before a block's start to notify.
var REMINDER_MODES = ["start", "before", "both", "off"]
var REMINDER_BEFORE = 5

function reminderMode(settings) {
  var mode = settings && settings.reminders
  return REMINDER_MODES.indexOf(mode) !== -1 ? mode : "start"
}

function reminderLeads(mode) {
  if (mode === "before") return [REMINDER_BEFORE]
  if (mode === "both") return [REMINDER_BEFORE, 0]
  if (mode === "off") return []
  return [0]
}

function reminderLabel(mode) {
  if (mode === "before") return REMINDER_BEFORE + " min before"
  if (mode === "both") return REMINDER_BEFORE + " min before + start"
  if (mode === "off") return "Reminders off"
  return "At start"
}

function nextReminderMode(mode) {
  return REMINDER_MODES[(REMINDER_MODES.indexOf(mode) + 1) % REMINDER_MODES.length]
}

function parseSettings(raw) {
  try {
    var data = JSON.parse(raw || "{}")
    return data && typeof data === "object" && !Array.isArray(data) ? data : {}
  } catch (e) {
    return {}
  }
}
