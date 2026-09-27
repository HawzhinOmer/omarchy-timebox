import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui
import "TimeboxModel.js" as Model

Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string dataDir: Quickshell.env("HOME") + "/.local/share/omarchy-timebox"

  // Day state
  property date day: new Date()
  readonly property string dateKey: Qt.formatDate(root.day, "yyyy-MM-dd")
  property date now: new Date()
  readonly property bool isToday: root.dateKey === Qt.formatDate(root.now, "yyyy-MM-dd")
  property var slots: Model.emptyDay().slots
  property var priorities: Model.emptyDay().priorities
  property string brainDump: ""
  property string brainDump2: ""
  property var slotColors: ({})
  property var otherSlots: ({})
  property var extraFields: ({})
  // Which field the text-color button applies to: "grid", "p0".."p2",
  // "dump1" or "dump2" (whatever was focused last).
  property string colorTarget: "grid"
  property bool inkOpen: false
  property bool loading: false
  property int revision: 0
  property bool fileExists: false
  // Plugin preferences (reminder mode), shared with the reminder service.
  property var settings: ({})
  readonly property string reminderMode: Model.reminderMode(settings)
  // Set when today's file exists but can't be read or parsed. Editing is
  // blocked so a save can never overwrite data we failed to load.
  property string loadError: ""
  readonly property bool locked: loadError !== ""
  readonly property var runInfo: Model.computeRuns(root.slots)

  // Schedule selection (slot indexes) and inline editor
  property int anchorSlot: 0
  property int cursorSlot: 0
  readonly property int selStart: Math.min(anchorSlot, cursorSlot)
  readonly property int selEnd: Math.max(anchorSlot, cursorSlot)
  property bool editing: false

  // Theme
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  // Accent color: the theme's by default, or one picked from the palette.
  // All colors come from the current Omarchy theme (colors.toml) by name.
  property var themeColors: ({})
  readonly property color accent: {
    var a = root.settings.accent
    return a && a.charAt(0) !== "#" ? root.tone(a) : root.tone("accent")
  }
  readonly property var palette: Model.paletteTones(root.themeColors)
  property bool paletteOpen: false
  property color line: Util.alpha(foreground, 0.28)
  property color muted: Util.alpha(foreground, 0.55)
  property color selectionFill: Util.alpha(accent, 0.18)
  property string fontFamily: Style.font.menuFamily
  // Everything you write (priorities, notes, blocks, the date) uses a bundled
  // handwriting font, like pen on the paper planner; printed labels stay as is.
  readonly property string handFamily: handFont.status === FontLoader.Ready ? handFont.name : fontFamily
  readonly property real handScale: handFont.status === FontLoader.Ready ? 1.4 : 1
  readonly property int cornerRadius: Style.cornerRadius
  readonly property int boxWidth: Math.max(2, Style.space(3))

  function open(payloadJson) {
    root.now = new Date()
    root.setDay(new Date())
    if (!saveTimer.running) dayFile.reload()
    root.opened = true
    var slot = root.currentSlot()
    root.cursorSlot = slot
    root.anchorSlot = slot
    Qt.callLater(function() { gridKeys.forceActiveFocus() })
  }

  function close() {
    root.flush()
    root.editing = false
    root.opened = false
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "hawzhin.timebox")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // ---- persistence ----

  function setDay(d) {
    var next = new Date(d.getFullYear(), d.getMonth(), d.getDate())
    if (Qt.formatDate(next, "yyyy-MM-dd") === root.dateKey) return
    root.flush()
    root.editing = false
    root.day = next
  }

  function shiftDay(delta) {
    root.setDay(new Date(root.day.getFullYear(), root.day.getMonth(), root.day.getDate() + delta))
  }

  function applyData(raw) {
    var d = Model.parseDay(raw)
    if (!d) {
      root.loadError = root.dateKey + ".json isn't a valid planner file"
      d = Model.emptyDay()
    }
    root.loading = true
    root.slots = d.slots
    root.priorities = d.priorities
    root.brainDump = Model.tonesToColors(Model.isRichText(d.brainDump) ? d.brainDump : Model.plainToHtml(d.brainDump), root.tone)
    root.brainDump2 = Model.tonesToColors(Model.isRichText(d.brainDump2) ? d.brainDump2 : Model.plainToHtml(d.brainDump2), root.tone)
    root.slotColors = d.slotColors
    root.otherSlots = d.otherSlots
    root.extraFields = d.extra
    root.revision++
    root.loading = false
  }

  function scheduleSave() {
    if (!root.loading && !root.locked) saveTimer.restart()
  }

  function flush() {
    if (!saveTimer.running) return
    saveTimer.stop()
    root.save()
  }

  function save() {
    if (root.locked) return
    var d = {
      slots: root.slots, priorities: root.priorities,
      brainDump: dumpEdit.length ? Model.colorsToTones(Model.cleanRichText(root.brainDump), root.tonePairs()) : "",
      brainDump2: dumpEdit2.length ? Model.colorsToTones(Model.cleanRichText(root.brainDump2), root.tonePairs()) : "",
      slotColors: root.slotColors, otherSlots: root.otherSlots, extra: root.extraFields
    }
    var empty = !d.brainDump && !d.brainDump2 && root.slots.every(function(s) { return !s })
      && root.priorities.every(function(p) { return !p.text })
    if (empty && !root.fileExists) return
    dayFile.setText(Model.serializeDay(root.dateKey, d))
    root.fileExists = true
  }

  function setPriority(i, patch) {
    if (root.locked) return
    var next = root.priorities.slice()
    next[i] = Object.assign({}, next[i], patch)
    root.priorities = next
    root.scheduleSave()
  }

  function fillSelection(text) {
    if (root.locked) return
    var next = root.slots.slice()
    for (var i = root.selStart; i <= root.selEnd; i++) next[i] = text
    root.slots = next
    root.scheduleSave()
  }

  function tone(name) {
    var t = root.themeColors
    if (!name) return root.foreground
    if (name.charAt(0) === "#") return name
    if (name === "accent") return t.accent || Color.accent
    if (name === "foreground") return t.foreground || Color.foreground
    if (name === "red") return t.red || Color.urgent
    return t[name] || t.accent || Color.accent
  }

  function tonePairs() {
    var names = ["foreground", "red", "accent"].concat(Model.THEME_TONES)
    var out = []
    for (var i = 0; i < names.length; i++) out.push({ name: names[i], color: String(root.tone(names[i])) })
    return out
  }

  function setSetting(key, value) {
    var next = Object.assign({}, root.settings)
    if (value === "" || value === undefined) delete next[key]
    else next[key] = value
    root.settings = next
    settingsFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  function cycleReminders() {
    root.setSetting("reminders", Model.nextReminderMode(root.reminderMode))
  }

  // ---- schedule interaction ----

  function currentSlot() {
    var h = root.now.getHours()
    var i = (h - Model.START_HOUR) * 2 + (root.now.getMinutes() >= 30 ? 1 : 0)
    return Math.max(0, Math.min(Model.SLOTS - 1, i))
  }

  function moveCursor(delta, extend) {
    var next = Math.max(0, Math.min(Model.SLOTS - 1, root.cursorSlot + delta))
    root.cursorSlot = next
    if (!extend) root.anchorSlot = next
  }

  function startEdit(initial) {
    if (root.locked) return
    editor.text = initial
    root.editing = true
    editor.forceActiveFocus()
    editor.cursorPosition = editor.text.length
  }

  function commitEdit() {
    if (!root.editing) return
    root.editing = false
    root.fillSelection(editor.text.trim())
    gridKeys.forceActiveFocus()
  }

  // ---- copy / cut / paste for schedule slots (like a spreadsheet) ----
  // Colors travel with a copy made here; text from elsewhere pastes plain.
  property var copied: null

  function copySlots() {
    var texts = [], colors = []
    for (var i = root.selStart; i <= root.selEnd; i++) {
      texts.push(root.slots[i])
      colors.push(root.slotColors[Model.slotKey(i)] || "")
    }
    Quickshell.clipboardText = texts.join("\n")
    root.copied = { text: texts.join("\n"), colors: colors }
  }

  function cutSlots() {
    root.copySlots()
    root.fillSelection("")
    var next = Object.assign({}, root.slotColors)
    for (var i = root.selStart; i <= root.selEnd; i++) delete next[Model.slotKey(i)]
    root.slotColors = next
  }

  function pasteSlots() {
    if (root.locked) return
    var text = String(Quickshell.clipboardText || "").replace(/\r/g, "")
    if (!text) return
    var lines = text.replace(/\n$/, "").split("\n")
    var colors = root.copied && root.copied.text === text ? root.copied.colors : null
    var nextSlots = root.slots.slice()
    var nextColors = Object.assign({}, root.slotColors)
    function put(i, j) {
      nextSlots[i] = lines[j].trim()
      var key = Model.slotKey(i)
      if (colors && colors[j]) nextColors[key] = colors[j]
      else if (colors) delete nextColors[key]
    }
    if (lines.length === 1) {
      for (var i = root.selStart; i <= root.selEnd; i++) put(i, 0)
    } else {
      var end = Math.min(Model.SLOTS - 1, root.selStart + lines.length - 1)
      for (var k = root.selStart; k <= end; k++) put(k, k - root.selStart)
      root.anchorSlot = root.selStart
      root.cursorSlot = end
    }
    root.slots = nextSlots
    root.slotColors = nextColors
    root.scheduleSave()
  }

  function commitAndMoveDown() {
    var single = root.selStart === root.selEnd
    root.commitEdit()
    if (single) root.moveCursor(2, false)
  }

  function cancelEdit() {
    root.editing = false
    gridKeys.forceActiveFocus()
  }

  function inRun(a, b) {
    if (b < 0 || b >= Model.SLOTS) return false
    var r = root.runInfo.runOf[a]
    return r >= 0 && root.runInfo.runOf[b] === r
  }

  Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.dataDir])

  FileView {
    id: settingsFile
    path: root.dataDir + "/settings.json"
    atomicWrites: true
    blockWrites: true
    watchChanges: true
    printErrors: false
    onLoaded: root.settings = Model.parseSettings(text())
    onLoadFailed: root.settings = ({})
    onFileChanged: reload()
  }

  FileView {
    id: themeFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var next = Model.parseThemeColors(text())
      // Save pending edits with the old theme's colors so they map back to
      // names, then reload so notes pick up the new theme.
      if (saveTimer.running) { saveTimer.stop(); root.save() }
      root.themeColors = next
      if (root.opened && !root.locked) dayFile.reload()
    }
    onFileChanged: reload()
  }

  FontLoader {
    id: handFont
    source: Qt.resolvedUrl("fonts/Caveat.ttf")
  }

  FileView {
    id: dayFile
    path: root.dataDir + "/" + root.dateKey + ".json"
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onLoaded: { root.fileExists = true; root.loadError = ""; root.applyData(text()) }
    onLoadFailed: function(error) {
      root.fileExists = error !== FileViewError.FileNotFound
      root.loadError = root.fileExists ? "Couldn't read " + root.dateKey + ".json" : ""
      root.applyData("")
    }
  }

  Timer {
    id: saveTimer
    interval: 600
    onTriggered: root.save()
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.now = new Date()
  }

  // A normal toplevel window, so Hyprland treats it like any app: SUPER + Q
  // closes it and it can be moved, resized, or tiled.
  FloatingWindow {
    id: panel
    visible: root.opened
    title: "Timebox Planner"
    color: root.background
    implicitWidth: 1280
    implicitHeight: 800
    minimumSize: Qt.size(900, 620)

    // Closed by the compositor (SUPER + Q, the window's close button):
    // save and tell the host so SUPER + D opens it again next time.
    onVisibleChanged: {
      if (visible || !root.opened) return
      root.close()
      if (root.shell && typeof root.shell.hide === "function")
        root.shell.hide((root.manifest && root.manifest.id) || "hawzhin.timebox")
    }

    Shortcut {
      sequences: ["Escape"]
      onActivated: {
        if (root.paletteOpen || root.inkOpen) { root.paletteOpen = false; root.inkOpen = false }
        else if (root.editing) root.cancelEdit()
        else root.dismiss()
      }
    }

    Item {
      id: card
      anchors.fill: parent
      readonly property int inset: Style.space(28)

      MouseArea { anchors.fill: parent; onClicked: gridKeys.forceActiveFocus() }

      Item {
        id: content
        anchors.fill: parent
        anchors.margins: card.inset

        readonly property int gutter: Style.space(36)
        readonly property int leftWidth: Math.round((width - gutter) * 0.42)
        readonly property int footerHeight: Style.font.bodySmall + Style.space(12)
        readonly property int labelGap: Style.space(10)
        readonly property int sectionGap: Style.space(26)

        // ================= Header =================
        Item {
          id: topBar
          z: 10
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Style.space(60)

          Row {
            id: header
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(16)

            Rectangle {
              width: Style.space(60)
              height: width
              color: root.foreground

              Column {
                anchors.centerIn: parent
                spacing: 0
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: Qt.formatDate(root.day, "d")
                  color: root.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge
                  font.bold: true
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: Qt.formatDate(root.day, "MMM").toUpperCase()
                  color: root.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: Style.space(2)
                }
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Daily Timebox Planner"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              font.bold: true
            }
          }

          // ---- Date line ----
          Item {
            id: dateLine
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: rightCol.width
            height: Style.space(44)

            Text {
              id: dateLabel
              anchors.left: parent.left
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(6)
              text: "Date:"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              id: dateText
              anchors.left: dateLabel.right
              anchors.leftMargin: Style.space(14)
              anchors.right: navRow.left
              anchors.rightMargin: Style.space(10)
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(4)
              horizontalAlignment: Text.AlignHCenter
              text: Qt.formatDate(root.day, "dddd, MMMM d, yyyy")
              color: root.foreground
              font.family: root.handFamily
              font.pixelSize: Style.font.display * (1 + (root.handScale - 1) / 2)
              fontSizeMode: Text.HorizontalFit
              minimumPixelSize: Style.font.heading
              elide: Text.ElideRight
            }

            Rectangle {
              anchors.left: dateText.left
              anchors.right: dateText.right
              anchors.bottom: parent.bottom
              height: 1
              color: root.foreground
            }

            Row {
              id: navRow
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.bottomMargin: Style.space(4)
              spacing: Style.space(4)

              Rectangle {
                id: inkButton
                width: Style.space(28)
                height: Style.space(28)
                radius: root.cornerRadius
                color: inkMouse.containsMouse || root.inkOpen ? Util.alpha(root.foreground, 0.1) : "transparent"
                border.color: root.line
                border.width: 1
                Text {
                  anchors.centerIn: parent
                  anchors.verticalCenterOffset: -Style.space(2)
                  text: "A"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(5)
                  width: Style.space(14); height: Math.max(2, Style.space(3))
                  color: root.tone("red")
                }
                MouseArea {
                  id: inkMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.paletteOpen = false; root.inkOpen = !root.inkOpen }
                }

              }

              Rectangle {
                id: colorButton
                width: Style.space(28)
                height: Style.space(28)
                radius: root.cornerRadius
                color: colorMouse.containsMouse || root.paletteOpen ? Util.alpha(root.foreground, 0.1) : "transparent"
                border.color: root.line
                border.width: 1
                Rectangle {
                  anchors.centerIn: parent
                  width: Style.space(14); height: width; radius: width / 2
                  color: root.accent
                }
                MouseArea {
                  id: colorMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.inkOpen = false; root.paletteOpen = !root.paletteOpen }
                }

              }

              Rectangle {
                width: bellText.implicitWidth + Style.space(16)
                height: Style.space(28)
                radius: root.cornerRadius
                color: bellMouse.containsMouse ? Util.alpha(root.foreground, 0.1) : "transparent"
                border.color: root.line
                border.width: 1
                Text {
                  id: bellText
                  anchors.centerIn: parent
                  text: (root.reminderMode === "off" ? "󰂛  " : "󰂚  ") + Model.reminderLabel(root.reminderMode)
                  color: root.reminderMode === "off" ? root.muted : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                MouseArea {
                  id: bellMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: { root.cycleReminders(); gridKeys.forceActiveFocus() }
                }
              }

              Repeater {
                model: [
                  { label: "‹", delta: -1 },
                  { label: "Today", delta: 0 },
                  { label: "›", delta: 1 }
                ]
                Rectangle {
                  required property var modelData
                  visible: modelData.delta !== 0 || !root.isToday
                  width: navText.implicitWidth + Style.space(16)
                  height: Style.space(28)
                  radius: root.cornerRadius
                  color: navMouse.containsMouse ? Util.alpha(root.foreground, 0.1) : "transparent"
                  border.color: root.line
                  border.width: 1
                  Text {
                    id: navText
                    anchors.centerIn: parent
                    text: parent.modelData.label
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                  }
                  MouseArea {
                    id: navMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (parent.modelData.delta === 0) root.setDay(new Date())
                      else root.shiftDay(parent.modelData.delta)
                      gridKeys.forceActiveFocus()
                    }
                  }
                }
              }
            }
          }

        }

        // ================= Left column =================
        Item {
          id: leftCol
          anchors.left: parent.left
          anchors.top: topBar.bottom
          anchors.topMargin: content.sectionGap
          anchors.bottom: footer.top
          width: content.leftWidth

          // ---- Top priorities ----
          Text {
            id: prioritiesLabel
            anchors.top: parent.top
            text: "Top Priorities"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Rectangle {
            id: prioritiesBox
            anchors.top: prioritiesLabel.bottom
            anchors.topMargin: content.labelGap
            width: parent.width
            height: Style.space(52) * Model.PRIORITIES
            color: "transparent"
            border.color: root.line
            border.width: 1

            Column {
              anchors.fill: parent
              Repeater {
                id: priorityRepeater
                model: Model.PRIORITIES

                Item {
                  id: prow
                  required property int index
                  readonly property var item: root.priorities[index] || ({ text: "", done: false })
                  property alias input: pinput
                  width: prioritiesBox.width
                  height: prioritiesBox.height / Model.PRIORITIES

                  Rectangle {
                    visible: prow.index > 0
                    width: parent.width; height: 1
                    color: root.line
                  }

                  Rectangle {
                    id: check
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(16)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(16); height: width
                    radius: width / 2
                    color: prow.item.done ? root.accent : "transparent"
                    border.color: prow.item.done ? root.accent : root.muted
                    border.width: Math.max(1, Style.space(2))
                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -Style.space(6)
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.setPriority(prow.index, { done: !prow.item.done })
                    }
                  }

                  TextInput {
                    id: pinput
                    anchors.left: check.right
                    anchors.leftMargin: Style.space(14)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(14)
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.tone(prow.item.color)
                    opacity: prow.item.done ? 0.5 : 1
                    font.family: root.handFamily
                    font.pixelSize: Style.font.heading * root.handScale
                    font.strikeout: prow.item.done
                    selectionColor: root.selectionFill
                    selectByMouse: true
                    readOnly: root.locked
                    clip: true
                    onTextChanged: if (!root.loading) root.setPriority(prow.index, { text: text })
                    onActiveFocusChanged: if (activeFocus) root.colorTarget = "p" + prow.index
                    Keys.onEscapePressed: root.dismiss()
                    Keys.onReturnPressed: root.focusPriority(prow.index + 1)
                    Keys.onTabPressed: root.focusPriority(prow.index + 1)

                    Text {
                      anchors.fill: parent
                      visible: !pinput.text && !pinput.activeFocus
                      text: "Priority " + (prow.index + 1)
                      color: root.muted
                      opacity: 0.6
                      font: pinput.font
                    }

                    Connections {
                      target: root
                      function onRevisionChanged() { pinput.text = prow.item.text }
                    }
                  }
                }
              }
            }
          }

          // ---- Brain dump ----
          Text {
            id: dumpLabel
            anchors.top: prioritiesBox.bottom
            anchors.topMargin: content.sectionGap
            text: "Brain Dump"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }

          Rectangle {
            id: dumpBox
            anchors.top: dumpLabel.bottom
            anchors.topMargin: content.labelGap
            anchors.bottom: parent.bottom
            width: parent.width
            color: Util.alpha(root.foreground, 0.03)
            border.color: root.line
            border.width: 1
            clip: true

            Canvas {
              id: dots
              anchors.fill: parent
              readonly property color dotColor: Util.alpha(root.foreground, 0.22)
              readonly property int step: Style.space(22)
              onDotColorChanged: requestPaint()
              onWidthChanged: requestPaint()
              onHeightChanged: requestPaint()
              onPaint: {
                var ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.fillStyle = dotColor
                for (var y = step / 2; y < height; y += step)
                  for (var x = step / 2; x < width; x += step)
                    ctx.fillRect(Math.round(x), Math.round(y), 2, 2)
              }
            }

            Flickable {
              id: dumpFlick
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(16)
              anchors.left: parent.left
              width: (dumpBox.width - Style.space(16) * 4 - 1) / 2
              contentWidth: width
              contentHeight: dumpEdit.contentHeight
              boundsBehavior: Flickable.StopAtBounds
              clip: true

              function ensureVisible(r) {
                if (contentY >= r.y) contentY = r.y
                else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
              }

              TextEdit {
                id: dumpEdit
                objectName: "dumpEdit"
                width: dumpFlick.width
                height: Math.max(dumpFlick.height, contentHeight)
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.Wrap
                color: root.foreground
                font.family: root.handFamily
                font.pixelSize: Style.font.title * (1 + (root.handScale - 1) * 0.7)
                selectionColor: root.selectionFill
                selectByMouse: true
                persistentSelection: true
                readOnly: root.locked
                onActiveFocusChanged: if (activeFocus) root.colorTarget = "dump1"
                onCursorRectangleChanged: dumpFlick.ensureVisible(cursorRectangle)
                onTextChanged: if (!root.loading && !root.locked) { root.brainDump = text; root.scheduleSave() }
                Keys.onEscapePressed: root.dismiss()
                Keys.onTabPressed: root.focusDump(2)

                Text {
                  visible: dumpEdit.length === 0 && !dumpEdit.activeFocus
                  text: "Everything on your mind…"
                  color: root.muted
                  opacity: 0.6
                  font: dumpEdit.font
                }

                Connections {
                  target: root
                  function onRevisionChanged() { dumpEdit.text = root.brainDump }
                }
              }
            }

            Rectangle {
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(10)
              width: 1
              color: root.line
            }

            Flickable {
              id: dumpFlick2
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(16)
              anchors.right: parent.right
              width: (dumpBox.width - Style.space(16) * 4 - 1) / 2
              contentWidth: width
              contentHeight: dumpEdit2.contentHeight
              boundsBehavior: Flickable.StopAtBounds
              clip: true

              function ensureVisible(r) {
                if (contentY >= r.y) contentY = r.y
                else if (contentY + height <= r.y + r.height) contentY = r.y + r.height - height
              }

              TextEdit {
                id: dumpEdit2
                objectName: "dumpEdit2"
                width: dumpFlick2.width
                height: Math.max(dumpFlick2.height, contentHeight)
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.Wrap
                color: root.foreground
                font.family: root.handFamily
                font.pixelSize: Style.font.title * (1 + (root.handScale - 1) * 0.7)
                selectionColor: root.selectionFill
                selectByMouse: true
                persistentSelection: true
                readOnly: root.locked
                onActiveFocusChanged: if (activeFocus) root.colorTarget = "dump2"
                onCursorRectangleChanged: dumpFlick2.ensureVisible(cursorRectangle)
                onTextChanged: if (!root.loading && !root.locked) { root.brainDump2 = text; root.scheduleSave() }
                Keys.onEscapePressed: root.dismiss()
                Keys.onTabPressed: root.focusDump(1)

                Text {
                  visible: dumpEdit2.length === 0 && !dumpEdit2.activeFocus
                  text: "…and more"
                  color: root.muted
                  opacity: 0.6
                  font: dumpEdit2.font
                }

                Connections {
                  target: root
                  function onRevisionChanged() { dumpEdit2.text = root.brainDump2 }
                }
              }
            }

          }
        }

        // ================= Right column =================
        Item {
          id: rightCol
          anchors.left: leftCol.right
          anchors.leftMargin: content.gutter
          anchors.right: parent.right
          anchors.top: topBar.bottom
          anchors.topMargin: content.sectionGap
          anchors.bottom: footer.top

          // ---- :00 / :30 header ----
          Item {
            id: colHeader
            anchors.top: parent.top
            width: parent.width
            height: Style.font.title + Style.space(12)

            Repeater {
              model: ["00:", "30:"]
              Text {
                required property int index
                required property var modelData
                x: grid.labelWidth + index * grid.cellWidth
                width: grid.cellWidth
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
            }
          }

          // ---- Schedule grid ----
          Item {
            id: grid
            anchors.top: colHeader.bottom
            anchors.bottom: parent.bottom
            width: parent.width

            readonly property real labelWidth: Style.space(50)
            readonly property real cellWidth: (width - labelWidth) / 2
            readonly property real rowHeight: height / Model.ROWS

            function slotAt(mx, my) {
              var row = Math.max(0, Math.min(Model.ROWS - 1, Math.floor(my / rowHeight)))
              var col = mx < labelWidth + cellWidth ? 0 : 1
              return row * 2 + col
            }

            function slotX(i) { return labelWidth + (i % 2) * cellWidth }
            function slotY(i) { return Math.floor(i / 2) * rowHeight }

            Item {
              id: gridKeys
              anchors.fill: parent
              focus: true
              onActiveFocusChanged: if (activeFocus) root.colorTarget = "grid"

              Keys.onPressed: function(event) {
                var shift = (event.modifiers & Qt.ShiftModifier) !== 0
                var k = event.key
                var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                if (ctrl && k === Qt.Key_C) root.copySlots()
                else if (ctrl && k === Qt.Key_X) root.cutSlots()
                else if (ctrl && k === Qt.Key_V) root.pasteSlots()
                else if (k === Qt.Key_Escape) root.dismiss()
                else if (k === Qt.Key_Up) root.moveCursor(-2, shift)
                else if (k === Qt.Key_Down) root.moveCursor(2, shift)
                else if (k === Qt.Key_Left) root.moveCursor(-1, shift)
                else if (k === Qt.Key_Right) root.moveCursor(1, shift)
                else if (k === Qt.Key_PageUp) root.shiftDay(-1)
                else if (k === Qt.Key_PageDown) root.shiftDay(1)
                else if (k === Qt.Key_Home) root.setDay(new Date())
                else if (k === Qt.Key_Tab) root.moveCursor(1, false)
                else if (k === Qt.Key_Backtab) root.moveCursor(-1, false)
                else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_F2)
                  root.startEdit(root.slots[root.selStart] || "")
                else if (k === Qt.Key_Delete || k === Qt.Key_Backspace) root.fillSelection("")
                else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
                         && event.text.charCodeAt(0) !== 127 && !(event.modifiers & Qt.ControlModifier))
                  root.startEdit(event.text)
                else return
                event.accepted = true
              }
            }

            // Hour label column
            Rectangle {
              width: grid.labelWidth
              height: parent.height
              color: Util.alpha(root.foreground, 0.05)
            }

            Repeater {
              model: Model.ROWS
              Text {
                required property int index
                readonly property bool current: root.isToday
                  && root.now.getHours() === Model.START_HOUR + index
                y: index * grid.rowHeight
                width: grid.labelWidth
                height: grid.rowHeight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: Model.hourLabel(index)
                color: current ? root.accent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }
            }

            // Cells: selection fill + timebox borders
            Repeater {
              model: Model.SLOTS
              Item {
                id: cell
                required property int index
                readonly property int col: index % 2
                readonly property bool boxed: root.runInfo.runOf[index] >= 0
                  && root.runInfo.runs[root.runInfo.runOf[index]].len >= 2
                readonly property bool selected: index >= root.selStart && index <= root.selEnd
                x: grid.slotX(index)
                y: grid.slotY(index)
                width: grid.cellWidth
                height: grid.rowHeight

                Rectangle {
                  anchors.fill: parent
                  color: cell.selected && gridKeys.activeFocus ? root.selectionFill
                    : (cell.selected ? Util.alpha(root.accent, 0.08) : "transparent")
                }

                // Box edges only where the neighbouring slot is not part of the same timebox
                Rectangle {
                  visible: cell.boxed && !root.inRun(cell.index, cell.index - 2)
                  width: parent.width; height: root.boxWidth
                  y: -root.boxWidth / 2
                  color: root.accent
                  z: 2
                }
                Rectangle {
                  visible: cell.boxed && !root.inRun(cell.index, cell.index + 2)
                  width: parent.width; height: root.boxWidth
                  y: parent.height - root.boxWidth / 2
                  color: root.accent
                  z: 2
                }
                Rectangle {
                  visible: cell.boxed && !(cell.col === 1 && root.inRun(cell.index, cell.index - 1))
                  width: root.boxWidth; height: parent.height + root.boxWidth
                  x: -root.boxWidth / 2; y: -root.boxWidth / 2
                  color: root.accent
                  z: 2
                }
                Rectangle {
                  visible: cell.boxed && !(cell.col === 0 && root.inRun(cell.index, cell.index + 1))
                  width: root.boxWidth; height: parent.height + root.boxWidth
                  x: parent.width - root.boxWidth / 2; y: -root.boxWidth / 2
                  color: root.accent
                  z: 2
                }
              }
            }

            // Grid lines
            Repeater {
              model: Model.ROWS + 1
              Rectangle {
                required property int index
                y: Math.min(grid.height - 1, index * grid.rowHeight)
                width: grid.width; height: 1
                color: root.line
              }
            }
            Repeater {
              model: [0, grid.labelWidth, grid.labelWidth + grid.cellWidth, grid.width - 1]
              Rectangle {
                required property var modelData
                x: modelData
                width: 1; height: grid.height
                color: root.line
              }
            }

            // Timebox labels, drawn once per run
            Repeater {
              model: root.runInfo.runs
              Text {
                required property var modelData
                readonly property int start: modelData.start
                readonly property int col: start % 2
                readonly property bool spansRow: col === 0 && modelData.len >= 2
                visible: !(root.editing && start >= root.selStart && start <= root.selEnd)
                x: grid.slotX(start) + Style.space(12)
                y: grid.slotY(start)
                width: (spansRow ? grid.cellWidth * 2 : grid.cellWidth) - Style.space(24)
                height: grid.rowHeight
                verticalAlignment: Text.AlignVCenter
                text: modelData.text
                color: root.tone(root.slotColors[Model.slotKey(start)])
                font.family: root.handFamily
                font.pixelSize: Math.min(Style.font.heading * root.handScale, grid.rowHeight * 0.72)
                elide: Text.ElideRight
                z: 3
              }
            }

            // Cursor outline
            Rectangle {
              visible: gridKeys.activeFocus && !root.editing
              x: grid.slotX(root.cursorSlot)
              y: grid.slotY(root.cursorSlot)
              width: grid.cellWidth
              height: grid.rowHeight
              color: "transparent"
              border.color: root.accent
              border.width: 1
              z: 5
            }

            MouseArea {
              anchors.fill: parent
              anchors.leftMargin: grid.labelWidth
              z: 6
              onPressed: function(mouse) {
                if (root.editing) root.commitEdit()
                var s = grid.slotAt(mouse.x + grid.labelWidth, mouse.y)
                root.cursorSlot = s
                if (!(mouse.modifiers & Qt.ShiftModifier)) root.anchorSlot = s
                gridKeys.forceActiveFocus()
              }
              onPositionChanged: function(mouse) {
                if (pressed) root.cursorSlot = grid.slotAt(mouse.x + grid.labelWidth, mouse.y)
              }
              onDoubleClicked: root.startEdit(root.slots[root.selStart] || "")
            }

            // Inline editor over the selection
            Rectangle {
              id: editorBox
              visible: root.editing
              readonly property bool multiRow: Math.floor(root.selStart / 2) !== Math.floor(root.selEnd / 2)
              x: multiRow ? grid.labelWidth : grid.slotX(root.selStart)
              y: grid.slotY(root.selStart)
              width: multiRow ? grid.cellWidth * 2 : grid.slotX(root.selEnd) + grid.cellWidth - x
              height: grid.rowHeight
              color: root.background
              border.color: root.accent
              border.width: root.boxWidth
              z: 7

              TextInput {
                id: editor
                anchors.fill: parent
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                verticalAlignment: TextInput.AlignVCenter
                color: root.foreground
                font.family: root.handFamily
                font.pixelSize: Math.min(Style.font.heading * root.handScale, grid.rowHeight * 0.72)
                selectionColor: root.selectionFill
                selectByMouse: true
                clip: true
                Keys.onReturnPressed: root.commitAndMoveDown()
                Keys.onTabPressed: { root.commitEdit(); root.moveCursor(1, false) }
                Keys.onBacktabPressed: { root.commitEdit(); root.moveCursor(-1, false) }
                Keys.onEnterPressed: root.commitAndMoveDown()
                Keys.onEscapePressed: root.cancelEdit()
                onActiveFocusChanged: if (!activeFocus && root.editing) root.commitEdit()
              }
            }
          }
        }

        // ================= Popups =================
        Rectangle {
          visible: root.inkOpen
          z: 20
          // Lives at the content level (not inside the header row) so
          // clicks on it are always delivered.
          x: root.inkOpen ? inkButton.mapToItem(content, inkButton.width, 0).x - width : 0
          y: root.inkOpen ? inkButton.mapToItem(content, 0, inkButton.height).y + Style.space(6) : 0
          width: inkChoices.implicitWidth + Style.space(16)
          height: inkChoices.implicitHeight + Style.space(16)
          radius: root.cornerRadius
          color: root.background
          border.color: root.line
          border.width: 1

          Row {
            id: inkChoices
            anchors.centerIn: parent
            spacing: Style.space(6)
            Repeater {
              model: [
                { label: "Default", ink: "" },
                { label: "Red", ink: "red" },
                { label: "Accent", ink: root.settings.accent && root.settings.accent.charAt(0) !== "#" ? root.settings.accent : "accent" }
              ]
              Rectangle {
                required property var modelData
                width: inkLabel.implicitWidth + Style.space(34)
                height: Style.space(26)
                radius: root.cornerRadius
                color: chipMouse.containsMouse ? Util.alpha(root.foreground, 0.1) : "transparent"
                Rectangle {
                  id: inkDot
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(8)
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(12); height: width; radius: width / 2
                  color: root.tone(parent.modelData.ink)
                }
                Text {
                  id: inkLabel
                  anchors.left: inkDot.right
                  anchors.leftMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: parent.modelData.label
                  color: root.tone(parent.modelData.ink)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
                MouseArea {
                  id: chipMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.applyInk(parent.modelData.ink)
                }
              }
            }
          }
        }

        Rectangle {
          visible: root.paletteOpen
          z: 20
          // Lives at the content level (not inside the header row) so
          // clicks on it are always delivered.
          x: root.paletteOpen ? colorButton.mapToItem(content, colorButton.width, 0).x - width : 0
          y: root.paletteOpen ? colorButton.mapToItem(content, 0, colorButton.height).y + Style.space(6) : 0
          width: swatches.implicitWidth + Style.space(16)
          height: swatches.implicitHeight + Style.space(16)
          radius: root.cornerRadius
          color: root.background
          border.color: root.line
          border.width: 1

          Row {
            id: swatches
            anchors.centerIn: parent
            spacing: Style.space(8)
            Repeater {
              model: root.palette
              Rectangle {
                required property var modelData
                readonly property color swatch: root.tone(modelData)
                readonly property bool current: (root.settings.accent && root.settings.accent.charAt(0) !== "#" ? root.settings.accent : "accent") === modelData
                width: Style.space(24); height: width; radius: width / 2
                color: swatch
                border.color: root.foreground
                border.width: current ? Math.max(2, Style.space(2)) : 0
                Text {
                  anchors.centerIn: parent
                  visible: parent.modelData === "accent"
                  text: "T"
                  color: root.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.setSetting("accent", parent.modelData === "accent" ? "" : parent.modelData)
                    root.paletteOpen = false
                    gridKeys.forceActiveFocus()
                  }
                }
              }
            }
          }
        }

        Text {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          text: "Created by HawzhinOmer"
          color: root.muted
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // ================= Footer =================
        Text {
          id: footer
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          height: content.footerHeight
          verticalAlignment: Text.AlignBottom
          text: root.locked
            ? "⚠  " + root.loadError + ". Read-only so it isn't overwritten; fix the file, then reopen."
            : "Type to fill  •  Tab next  •  Enter save + down  •  Ctrl C/X/V  •  A text color  •  Del clear  •  PgUp/PgDn day  •  Esc close"
          color: root.locked ? root.urgentColor : root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: Style.space(1)
        }
      }
    }
  }

  property color urgentColor: Color.urgent

  function focusDump(n) {
    if (n === 2) dumpEdit2.forceActiveFocus()
    else dumpEdit.forceActiveFocus()
  }

  // Text color ("" = default ink) for whatever was focused last.
  function applyInk(color) {
    root.inkOpen = false
    if (root.locked) return
    var t = root.colorTarget
    if (t === "grid") {
      // Color whole blocks: a block's text uses its first slot's color, so
      // selecting any part of a block recolors all of it.
      var from = root.selStart, to = root.selEnd
      var runOf = root.runInfo.runOf, runs = root.runInfo.runs
      if (runOf[from] >= 0) from = runs[runOf[from]].start
      if (runOf[to] >= 0) to = runs[runOf[to]].start + runs[runOf[to]].len - 1
      var next = Object.assign({}, root.slotColors)
      for (var i = from; i <= to; i++) {
        if (color) next[Model.slotKey(i)] = color
        else delete next[Model.slotKey(i)]
      }
      root.slotColors = next
      root.scheduleSave()
      gridKeys.forceActiveFocus()
    } else if (t.charAt(0) === "p") {
      root.setPriority(Number(t.slice(1)), { color: color || undefined })
    } else {
      root.colorSelection(t === "dump2" ? dumpEdit2 : dumpEdit, String(root.tone(color || "foreground")))
    }
  }

  function colorSelection(edit, color) {
    var a = edit.selectionStart, b = edit.selectionEnd
    if (a === b) return
    var plain = edit.getText(a, b).replace(/\u2029/g, "\n")
    edit.remove(a, b)
    edit.insert(a, '<span style="color:' + color + ';">' + Model.plainToHtml(plain) + '</span>')
    // Leave the cursor after the colored words instead of re-selecting
    // them; the selection highlight would hide the new color.
    edit.deselect()
    edit.cursorPosition = a + plain.length
    edit.forceActiveFocus()
  }

  function focusPriority(i) {
    if (i >= Model.PRIORITIES) { dumpEdit.forceActiveFocus(); return }
    var row = priorityRepeater.itemAt(i)
    if (row) row.input.forceActiveFocus()
  }
}
