import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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
  readonly property string dataDir: Quickshell.env("HOME") + "/.local/share/omarchy-timebox"

  // Day state
  property date day: new Date()
  readonly property string dateKey: Qt.formatDate(root.day, "yyyy-MM-dd")
  property date now: new Date()
  readonly property bool isToday: root.dateKey === Qt.formatDate(root.now, "yyyy-MM-dd")
  property var slots: Model.emptyDay().slots
  property var priorities: Model.emptyDay().priorities
  property string brainDump: ""
  property bool loading: false
  property int revision: 0
  property bool fileExists: false
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
  property color accent: Color.accent
  property color scrim: Color.menu.scrim
  property var borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  property color line: Util.alpha(foreground, 0.28)
  property color muted: Util.alpha(foreground, 0.55)
  property color selectionFill: Util.alpha(accent, 0.18)
  property string fontFamily: Style.font.menuFamily
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
    root.loading = true
    root.slots = d.slots
    root.priorities = d.priorities
    root.brainDump = d.brainDump
    root.revision++
    root.loading = false
  }

  function scheduleSave() {
    if (!root.loading) saveTimer.restart()
  }

  function flush() {
    if (!saveTimer.running) return
    saveTimer.stop()
    root.save()
  }

  function save() {
    var d = { slots: root.slots, priorities: root.priorities, brainDump: root.brainDump }
    var empty = !root.brainDump && root.slots.every(function(s) { return !s })
      && root.priorities.every(function(p) { return !p.text })
    if (empty && !root.fileExists) return
    dayFile.setText(Model.serializeDay(root.dateKey, d))
    root.fileExists = true
  }

  function setPriority(i, patch) {
    var next = root.priorities.slice()
    next[i] = Object.assign({}, next[i], patch)
    root.priorities = next
    root.scheduleSave()
  }

  function fillSelection(text) {
    var next = root.slots.slice()
    for (var i = root.selStart; i <= root.selEnd; i++) next[i] = text
    root.slots = next
    root.scheduleSave()
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
    id: dayFile
    path: root.dataDir + "/" + root.dateKey + ".json"
    atomicWrites: true
    blockWrites: true
    printErrors: false
    onLoaded: { root.fileExists = true; root.applyData(text()) }
    onLoadFailed: { root.fileExists = false; root.applyData("") }
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

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-timebox"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }

    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      width: Math.min(Style.space(1180), panel.width - Style.gapsOut * 2)
      height: Math.min(Style.space(880), panel.height - Style.gapsOut * 2)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.space(28)

      MouseArea { anchors.fill: parent; onClicked: gridKeys.forceActiveFocus() }

      Item {
        id: content
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        readonly property int gutter: Style.space(36)
        readonly property int leftWidth: Math.round((width - gutter) * 0.42)
        readonly property int footerHeight: Style.font.bodySmall + Style.space(12)
        readonly property int labelGap: Style.space(10)
        readonly property int sectionGap: Style.space(26)

        // ================= Left column =================
        Item {
          id: leftCol
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: footer.top
          width: content.leftWidth

          Row {
            id: header
            spacing: Style.space(18)

            Rectangle {
              width: Style.space(112)
              height: width
              color: root.foreground

              Column {
                anchors.centerIn: parent
                spacing: Style.space(2)
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: Qt.formatDate(root.day, "d")
                  color: root.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.displayLarge * 1.6
                  font.bold: true
                }
                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  text: Qt.formatDate(root.day, "MMM").toUpperCase()
                  color: root.background
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  font.letterSpacing: Style.space(2)
                }
              }
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Daily\nTimebox\nPlanner"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
              lineHeight: 0.95
            }
          }

          // ---- Top priorities ----
          Text {
            id: prioritiesLabel
            anchors.top: header.bottom
            anchors.topMargin: content.sectionGap
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
                    color: root.foreground
                    opacity: prow.item.done ? 0.5 : 1
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.strikeout: prow.item.done
                    selectionColor: root.selectionFill
                    selectByMouse: true
                    clip: true
                    onTextChanged: if (!root.loading) root.setPriority(prow.index, { text: text })
                    Keys.onEscapePressed: gridKeys.forceActiveFocus()
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
              anchors.fill: parent
              anchors.margins: Style.space(16)
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
                width: dumpFlick.width
                height: Math.max(dumpFlick.height, contentHeight)
                wrapMode: TextEdit.Wrap
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                selectionColor: root.selectionFill
                selectByMouse: true
                onCursorRectangleChanged: dumpFlick.ensureVisible(cursorRectangle)
                onTextChanged: if (!root.loading) { root.brainDump = text; root.scheduleSave() }
                Keys.onEscapePressed: gridKeys.forceActiveFocus()

                Text {
                  visible: !dumpEdit.text && !dumpEdit.activeFocus
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
          }
        }

        // ================= Right column =================
        Item {
          id: rightCol
          anchors.left: leftCol.right
          anchors.leftMargin: content.gutter
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: footer.top

          // ---- Date line ----
          Item {
            id: dateLine
            width: parent.width
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
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
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

          // ---- :00 / :30 header ----
          Item {
            id: colHeader
            anchors.top: dateLine.bottom
            anchors.topMargin: Style.space(16)
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

              Keys.onPressed: function(event) {
                var shift = (event.modifiers & Qt.ShiftModifier) !== 0
                var k = event.key
                if (k === Qt.Key_Escape) {
                  if (root.selStart !== root.selEnd) root.anchorSlot = root.cursorSlot
                  else root.dismiss()
                } else if (k === Qt.Key_Up) root.moveCursor(-2, shift)
                else if (k === Qt.Key_Down) root.moveCursor(2, shift)
                else if (k === Qt.Key_Left) root.moveCursor(-1, shift)
                else if (k === Qt.Key_Right) root.moveCursor(1, shift)
                else if (k === Qt.Key_PageUp) root.shiftDay(-1)
                else if (k === Qt.Key_PageDown) root.shiftDay(1)
                else if (k === Qt.Key_Home) root.setDay(new Date())
                else if (k === Qt.Key_Tab) root.focusPriority(0)
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
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Math.min(Style.font.heading, grid.rowHeight * 0.5)
                elide: Text.ElideRight
                z: 3
              }
            }

            // Current-time marker
            Item {
              visible: root.isToday && root.now.getHours() >= Model.START_HOUR
              readonly property real hours: root.now.getHours() - Model.START_HOUR + root.now.getMinutes() / 60
              x: grid.labelWidth
              y: Math.min(grid.height, hours * grid.rowHeight) - 1
              width: grid.width - grid.labelWidth
              z: 4
              Rectangle { width: parent.width; height: 2; color: root.urgentColor }
              Rectangle {
                width: Style.space(8); height: width; radius: width / 2
                x: -width / 2; y: 1 - height / 2
                color: root.urgentColor
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
                font.family: root.fontFamily
                font.pixelSize: Math.min(Style.font.heading, grid.rowHeight * 0.5)
                selectionColor: root.selectionFill
                selectByMouse: true
                clip: true
                Keys.onReturnPressed: root.commitEdit()
                Keys.onEnterPressed: root.commitEdit()
                Keys.onEscapePressed: root.cancelEdit()
                onActiveFocusChanged: if (!activeFocus && root.editing) root.commitEdit()
              }
            }
          }
        }

        // ================= Footer =================
        Text {
          id: footer
          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          height: content.footerHeight
          verticalAlignment: Text.AlignBottom
          text: "Drag to select slots  •  type or Enter to fill  •  Del to clear  •  PgUp/PgDn change day  •  Home today  •  Esc close"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.letterSpacing: Style.space(1)
        }
      }
    }
  }

  property color urgentColor: Color.urgent

  function focusPriority(i) {
    if (i >= Model.PRIORITIES) { dumpEdit.forceActiveFocus(); return }
    var row = priorityRepeater.itemAt(i)
    if (row) row.input.forceActiveFocus()
  }
}
