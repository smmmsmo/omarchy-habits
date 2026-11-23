import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "mo.habits"

  property var trackerState: Model.emptyState(Model.todayKey())
  property bool loaded: false
  property string storageError: ""
  property date today: new Date()
  readonly property string todayKey: Model.keyForDate(today)
  readonly property var todaySummary: Model.summaryForDay(trackerState, todayKey)
  readonly property bool busy: storage.running
  readonly property string dataPath: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/omarchy/habits.json"
  readonly property string storeScript: decodeURIComponent(Qt.resolvedUrl("store.py").toString().replace(/^(file|qs):\/\//, ""))
  property string resultText: ""
  property string operationAction: ""
  property string pendingSelection: ""
  signal operationFinished(string action, bool success, string habitId)

  function operate(operation) {
    if (storage.running) return
    storageError = ""
    resultText = ""
    operationAction = operation.action
    storage.command = ["python3", storeScript, dataPath, JSON.stringify(operation)]
    storage.running = true
  }

  function reload() { operate({ action: "read" }) }
  function rememberHabit(id) {
    pendingSelection = id
    Qt.callLater(flushSelection)
  }
  function flushSelection() {
    if (!pendingSelection || storage.running) return
    var id = pendingSelection
    pendingSelection = ""
    if (trackerState.selectedHabitId !== id) operate({ action: "select", id: id })
  }
  function saveHabit(fields) {
    var operation = JSON.parse(JSON.stringify(fields))
    operation.action = fields.id ? "edit" : "add"
    operate(operation)
  }
  function deleteHabit(id) { operate({ action: "delete", id: id }) }
  function setAnswer(id, date, value) {
    operate({ action: "answer", id: id, date: date, value: value })
  }

  Process {
    id: storage
    stdout: StdioCollector {
      onStreamFinished: root.resultText = text
    }
    onExited: function(code) {
      try {
        var reply = JSON.parse(root.resultText)
        if (code !== 0 || !reply.ok) throw new Error(reply.error || "Could not save habit data.")
        root.trackerState = Model.parseState(JSON.stringify(reply.data), root.todayKey)
        root.loaded = true
        root.storageError = ""
        root.operationFinished(root.operationAction, true, reply.habitId || "")
      } catch (error) {
        root.storageError = String(error.message || error)
        root.operationFinished(root.operationAction, false, "")
      }
      Qt.callLater(root.flushSelection)
    }
  }

  FileView {
    path: root.dataPath
    watchChanges: true
    printErrors: false
    onFileChanged: syncTimer.restart()
  }
  Timer {
    id: syncTimer
    interval: 120
    onTriggered: {
      if (root.busy) restart()
      else root.reload()
    }
  }
  SystemClock {
    precision: SystemClock.Minutes
    onDateChanged: {
      var changedDay = Model.keyForDate(date) !== root.todayKey
      root.today = date
      if (changedDay) syncTimer.restart()
    }
  }
  Component.onCompleted: reload()

  readonly property bool opened: popup.opened
  readonly property bool popoutSwitchClosing: popup.popoutSwitchClosing
  function open() { popup.openPage("calendar") }
  function close() { popup.close() }
  function togglePanel() { opened ? close() : open() }
  function closeForPopoutSwitch() { popup.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  HabitPanel {
    id: popup
    bar: root.bar
    settings: root.settings
    anchorItem: button
    hostWidget: root
  }

  ShellIpc {
    target: "mo.habits"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function openToday(): void { popup.openPage("calendar") }
    function openAnalysis(): void { popup.openPage("analysis") }
    function openSettings(): void { popup.openPage("settings") }
    function refresh(): void { root.reload() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰄬"
    labelText: !root.vertical && root.todaySummary.total > 0
      ? root.todaySummary.success + "/" + root.todaySummary.total : ""
    slotSize: labelText !== "" ? Style.bar.iconSlot * 2 : Style.bar.iconSlot
    tooltipText: "Habit tracker"
    active: root.todaySummary.perfect
    activeColor: Commons.Color.accent
    onPressed: function(b) {
      if (b === Qt.RightButton) popup.openPage("settings")
      else if (b === Qt.MiddleButton) popup.openPage("calendar")
      else root.togglePanel()
    }
  }
}
