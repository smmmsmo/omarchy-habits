import QtQuick
import QtQuick.Controls as QQC
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "mo.habits"
  manageIpc: false
  property var anchorItem: null
  property var hostWidget: null
  property string selectedId: ""
  property string selectedDay: todayKey
  property int viewYear: new Date().getFullYear()
  property int viewMonth: new Date().getMonth()
  property bool creating: false
  property string tab: "task"
  property bool datePickerOpen: false
  property bool saved: false
  property bool saving: false
  property bool deleteArmed: false
  property string editId: ""
  property string draftName: ""
  property string draftKind: "good"
  property string draftQuestion: ""
  property string draftMessage: ""
  property string draftStart: ""
  property string draftDefault: ""
  property string formError: ""

  readonly property string todayKey: hostWidget ? hostWidget.todayKey : Model.todayKey()
  readonly property var trackerState: hostWidget ? hostWidget.trackerState : Model.emptyState()
  readonly property var habit: Model.findHabit(trackerState, selectedId)
    || Model.findHabit(trackerState, trackerState.selectedHabitId) || trackerState.habits[0] || null
  readonly property bool editing: creating || (tab === "settings" && habit !== null)
  readonly property var stats: opened && habit ? Model.analyzeHabit(habit, trackerState, todayKey) : null
  readonly property string draftDateKey: editing ? parseDate(draftStart) : ""
  readonly property int previewDays: draftDateKey >= "1900-01-01"
    ? Model.defaultPreview(trackerState, editId, draftDateKey, todayKey, draftDefault) : 0
  readonly property var record: Model.recordFor(trackerState, habit, selectedDay, todayKey)
  readonly property var cells: Model.monthGrid(habit, trackerState, viewYear, viewMonth, todayKey)
  readonly property color foreground: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property color dim: blend(foreground, Commons.Color.popups.background, 0.80)
  readonly property bool busy: !hostWidget || hostWidget.busy || !hostWidget.loaded
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var locale: Qt.locale(Commons.I18n.formatLocale)

  Commons.Translations {
    id: strings
    directory: decodeURIComponent(Qt.resolvedUrl("i18n").toString().replace(/^(file|qs):\/\//, ""))
  }
  function t(key) { return strings.t(key) }
  function n(value, decimals) { return Commons.I18n.formatNumber(value, decimals || 0) }
  function displayDate(key) {
    var date = Model.dateFromKey(key)
    return date ? locale.toString(date, "dd MMM yyyy") : ""
  }
  function parseDate(text) {
    if (!text.trim()) return ""
    var key = Model.parseDisplayDate(text)
    if (key) return key
    try {
      var date = Date.fromLocaleDateString(locale, text.trim(), "dd MMM yyyy")
      var parsed = Model.keyForDate(date)
      return parsed && displayDate(parsed).toLowerCase() === text.trim().toLowerCase() ? parsed : ""
    } catch (error) {
      return ""
    }
  }
  function pct(rate, count) { return count ? n(Math.round(rate * 100)) + "%" : "—" }
  function tint(color, opacity) { return Qt.rgba(color.r, color.g, color.b, opacity) }
  function blend(fg, bg, amount) {
    return Qt.rgba(fg.r * amount + bg.r * (1 - amount), fg.g * amount + bg.g * (1 - amount),
      fg.b * amount + bg.b * (1 - amount), 1)
  }
  function chooseHabit(id) {
    if (saving) return
    var wasCreating = creating
    creating = false
    selectedId = id
    datePickerOpen = false
    saved = false
    deleteArmed = false
    if (wasCreating) tab = "task"
    if (tab === "settings" && habit) loadDraft(habit)
    inspectDay(todayKey)
    if (hostWidget && typeof hostWidget.rememberHabit === "function") hostWidget.rememberHabit(id)
    if (panel.loadedContent) panel.loadedContent.scrollArea.contentY = 0
  }
  function setTab(next) {
    if (saving || (!creating && tab === next)) return
    creating = false
    tab = next
    datePickerOpen = false
    saved = false
    deleteArmed = false
    if (next === "settings" && habit) loadDraft(habit)
    if (panel.loadedContent) panel.loadedContent.scrollArea.contentY = 0
  }
  function inspectDay(day) {
    selectedDay = day
    var date = Model.dateFromKey(day)
    viewYear = date.getFullYear()
    viewMonth = date.getMonth()
  }
  function moveMonth(delta) {
    if (!canMoveMonth(delta)) return
    var date = new Date(viewYear, viewMonth + delta, 1, 12)
    var first = Model.keyForDate(date)
    inspectDay(first < habit.startDate ? habit.startDate : first)
  }
  function canMoveMonth(delta) {
    if (!habit) return false
    var next = Model.keyForDate(new Date(viewYear, viewMonth + delta, 1, 12)).slice(0, 7)
    return delta < 0 ? next >= habit.startDate.slice(0, 7) : next <= todayKey.slice(0, 7)
  }
  function openPage(page) {
    deleteArmed = false
    datePickerOpen = false
    saved = false
    formError = ""
    if (hostWidget && !hostWidget.pendingSelection && !hostWidget.busy) selectedId = ""
    if (!saving) {
      creating = false
      tab = page
      inspectDay(todayKey)
      if (page === "settings" && habit) loadDraft(habit)
      else if (page === "settings" && hostWidget && hostWidget.loaded) beginEdit(null)
      if (panel.loadedContent) panel.loadedContent.scrollArea.contentY = 0
    }
    controller.show()
    if (hostWidget) hostWidget.reload()
  }
  function beginEdit(item) {
    if (saving) return
    creating = !item
    tab = item ? "settings" : "task"
    datePickerOpen = false
    loadDraft(item)
    if (panel.loadedContent) panel.loadedContent.scrollArea.contentY = 0
  }
  function loadDraft(item) {
    editId = item ? item.id : ""
    draftName = item ? item.name : ""
    draftKind = item ? item.kind : "good"
    draftQuestion = item ? item.question : t("defaultQuestion")
    draftMessage = item ? item.message : ""
    draftStart = displayDate(item ? item.startDate : todayKey)
    draftDefault = item ? item.defaultAnswer : ""
    saved = false
    deleteArmed = false
    formError = ""
  }
  function cancel() { setTab("task") }
  function setDraftDate(key) {
    draftStart = displayDate(key)
    saved = false
    datePickerOpen = false
  }
  function save() {
    if (busy) return
    var start = parseDate(draftStart)
    if (!draftName.trim()) { formError = t("nameError"); return }
    if (!draftQuestion.trim()) { formError = t("questionError"); return }
    if (!start || start < "1900-01-01" || start > todayKey) { formError = t("dateError"); return }
    saving = true
    saved = false
    datePickerOpen = false
    formError = ""
    hostWidget.saveHabit({
      id: editId, name: draftName, kind: draftKind, question: draftQuestion,
      message: draftMessage, startDate: start, defaultAnswer: draftDefault
    })
  }
  function remove() {
    if (!deleteArmed) { deleteArmed = true; deleteTimer.restart(); return }
    hostWidget.deleteHabit(editId)
  }
  function recoveryText() {
    if (!stats || !stats.answered) return t("noEntries")
    if (stats.pendingRecovery) return t("recoveryPending").arg(displayDate(stats.recoverySince))
    if (!stats.failureCount) return t("noSetbacks")
    return strings.tn("recoveries", stats.recoveries).arg(n(stats.recoveries))
  }
  function todayStatus(item) {
    var entry = Model.recordFor(trackerState, item, todayKey, todayKey)
    return !entry.value ? "pending" : Model.successFor(item.kind, entry.value) ? "onTrack" : "setback"
  }
  function moveDay(offset) {
    if (!habit) return
    var day = Model.addDays(selectedDay, offset)
    if (day >= habit.startDate && day <= todayKey) inspectDay(day)
  }
  function revealFocus(item) {
    for (var ancestor = item.parent; ancestor; ancestor = ancestor.parent) {
      if (ancestor.objectName !== "habitsScroll") continue
      var point = item.mapToItem(ancestor.contentItem, 0, 0)
      var inset = Style.space(8)
      var next = ancestor.contentY
      if (point.y < next + inset) next = point.y - inset
      else if (point.y + item.height > next + ancestor.height - inset)
        next = point.y + Math.min(item.height, ancestor.height) - ancestor.height + inset
      ancestor.contentY = Math.max(0, Math.min(ancestor.contentHeight - ancestor.height, next))
      break
    }
  }
  onTodayKeyChanged: inspectDay(todayKey)
  Timer { id: deleteTimer; interval: 5000; onTriggered: root.deleteArmed = false }
  Connections {
    target: root.hostWidget
    ignoreUnknownSignals: true
    function onOperationFinished(action, success, habitId) {
      if ((action === "add" || action === "edit") && root.saving) {
        root.saving = false
        if (success && action === "add") root.chooseHabit(habitId)
        if (success && action === "edit") {
          root.selectedId = habitId
          root.loadDraft(root.habit)
          root.saved = true
          if (root.selectedDay < root.habit.startDate) root.inspectDay(root.todayKey)
        }
      }
      if (action === "delete" && success) {
        root.setTab("task")
        root.selectedId = ""
      }
      if (action === "read" && success && root.tab === "settings" && !root.creating && root.habit && root.editId !== root.habit.id)
        root.loadDraft(root.habit)
    }
  }

  KeyboardPanel {
    id: panel
    objectName: "habitsPopup"
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    padding: Style.space(26)
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(900))
    contentHeight: panel.fittedContentHeight(Style.space(885))

    content: Item {
      id: content
      property alias scrollArea: detailScroll
      readonly property bool wide: width > Style.space(640)
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: {
        if (root.datePickerOpen) root.datePickerOpen = false
        else if (root.editing) root.cancel()
        else root.close()
      }

      Item {
        id: header
        width: parent.width
        height: Style.space(36)
        Label {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.t("title")
          font.pixelSize: Math.max(16, Style.font.heading)
          font.bold: true
        }
        Row {
          anchors.right: parent.right
          spacing: Style.space(8)
          Action {
            text: root.t("newHabit")
            iconText: "+"
            onClicked: root.beginEdit(null)
          }
          Action { text: "×"; objectName: "closeHabits"; Accessible.name: root.t("close"); onClicked: root.close() }
        }
      }
      PanelSeparator {
        id: headerRule
        width: parent.width
        y: header.height + Style.space(18)
        foreground: root.foreground
      }

      // The habit list is separate from the detail canvas, never another
      // stack of statistic cards competing with the selected habit.
      Item {
        id: sidebar
        visible: content.wide
        anchors.top: headerRule.bottom
        anchors.topMargin: Style.space(22)
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: Style.space(164)
        Label {
          id: sidebarTitle
          text: root.t("yourHabits")
          color: root.dim
          font.pixelSize: Math.max(11, Style.font.caption)
          font.letterSpacing: 1
        }
        Flickable {
          objectName: "habitsScroll"
          anchors.top: sidebarTitle.bottom
          anchors.topMargin: Style.space(16)
          anchors.bottom: parent.bottom
          width: parent.width
          contentWidth: width
          contentHeight: habitList.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          Column {
            id: habitList
            width: parent.width
            spacing: Style.space(8)
            Repeater {
              model: root.trackerState.habits
              Action {
                id: habitButton
                required property var modelData
                width: habitList.width
                height: Style.space(62)
                text: ""
                Accessible.name: root.t("habitStatus").arg(modelData.name).arg(root.t(root.todayStatus(modelData)))
                 selected: root.habit && root.habit.id === modelData.id && !root.creating
                bordered: false
                onClicked: root.chooseHabit(modelData.id)
                Column {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.margins: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(7)
                  Label {
                    width: Math.max(0, parent.width - Style.space(21))
                    text: habitButton.modelData.name
                    font.bold: habitButton.selected
                    elide: Text.ElideRight
                  }
                  Label {
                    text: root.t(habitButton.modelData.kind === "bad" ? "quitHabit" : "buildHabit")
                    color: root.dim
                    font.pixelSize: Math.max(11, Style.font.caption)
                  }
                }
                Label {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(8)
                  anchors.top: parent.top
                  anchors.topMargin: Style.space(10)
                  readonly property string status: root.todayStatus(habitButton.modelData)
                  text: status === "onTrack" ? "✓" : status === "setback" ? "×" : "·"
                  color: status === "onTrack" ? root.accent : status === "setback" ? root.urgent : root.dim
                  font.bold: true
                }
              }
            }
          }
        }
      }
      Rectangle {
        visible: content.wide
        anchors.left: sidebar.right
        anchors.leftMargin: Style.space(18)
        anchors.top: sidebar.top
        anchors.bottom: parent.bottom
        width: 1
        color: root.tint(root.foreground, 0.10)
      }

      Flickable {
        id: detailScroll
        objectName: "habitsScroll"
        anchors.top: headerRule.bottom
        anchors.topMargin: Style.space(22)
        anchors.left: content.wide ? sidebar.right : parent.left
        anchors.leftMargin: content.wide ? Style.space(42) : 0
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: detailColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        interactive: contentHeight > height
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }

        Column {
          id: detailColumn
          width: detailScroll.width
          spacing: Style.space(22)
          Label {
            visible: text !== ""
            width: parent.width
            text: root.hostWidget ? root.hostWidget.storageError : ""
            color: root.urgent
            wrapMode: Text.Wrap
          }

          Column {
            visible: !root.habit && !root.editing && root.hostWidget && root.hostWidget.loaded
            width: parent.width
            spacing: Style.space(20)
            Item { width: 1; height: Style.space(70) }
            Label { text: root.t("emptyTitle"); font.pixelSize: Math.max(22, Style.font.display); font.bold: true }
            Label { width: parent.width; text: root.t("emptyHint"); color: root.dim; wrapMode: Text.Wrap }
            Action { text: root.t("createFirst"); onClicked: root.beginEdit(null) }
          }
          Label {
            visible: !root.habit && !root.editing && root.hostWidget && !root.hostWidget.loaded && text !== ""
            width: parent.width
            text: root.hostWidget && root.hostWidget.storageError ? "" : root.t("loading")
            color: root.dim
          }

          Column {
            visible: root.habit !== null && !root.creating
            width: parent.width
            spacing: Style.space(14)
            QQC.ComboBox {
              id: habitPicker
              objectName: "habitPicker"
              visible: !content.wide && root.trackerState.habits.length > 1
              width: parent.width
              model: root.trackerState.habits
              textRole: "name"
              currentIndex: root.habit ? model.indexOf(root.habit) : -1
              onActivated: function(index) { root.chooseHabit(model[index].id) }
              Accessible.name: root.t("chooseHabit")
              contentItem: Label {
                leftPadding: Style.space(12)
                rightPadding: Style.space(28)
                text: root.habit ? root.habit.name : ""
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
              }
              background: Card { implicitHeight: Style.space(36) }
              indicator: Label {
                x: habitPicker.width - width - Style.space(12)
                y: (habitPicker.height - height) / 2
                text: "⌄"
                color: root.dim
              }
              onActiveFocusChanged: if (activeFocus) root.revealFocus(this)
              delegate: QQC.ItemDelegate {
                required property var modelData
                required property int index
                width: habitPicker.width
                highlighted: habitPicker.highlightedIndex === index
                contentItem: Label {
                  text: modelData.name
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle { color: parent.highlighted ? root.tint(root.accent, 0.18) : Commons.Color.background }
              }
            }
            Item {
              width: parent.width
              height: habitHeading.implicitHeight
              Column {
                id: habitHeading
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Style.space(9)
                Label {
                  width: parent.width
                  text: root.habit ? root.habit.name : ""
                  wrapMode: Text.Wrap
                  font.pixelSize: Math.max(22, Style.font.display)
                  font.bold: true
                }
                Label {
                  width: parent.width
                  text: root.habit ? root.t("since").arg(root.displayDate(root.habit.startDate)) : ""
                  color: root.dim
                  font.pixelSize: Math.max(11, Style.font.bodySmall)
                }
              }
            }
            Flow {
              width: parent.width
              spacing: Style.space(8)
              Repeater {
                model: ["task", "analysis", "settings"]
                Action {
                  required property string modelData
                  objectName: modelData + "Tab"
                  text: root.t(modelData)
                  selected: root.tab === modelData
                  onClicked: root.setTab(modelData)
                }
              }
            }
            Row {
              visible: root.tab !== "settings"
              width: parent.width
              spacing: Style.space(14)
              Stat { width: (parent.width - parent.spacing * 3) / 4; caption: root.t("currentStreak"); value: root.t("streakValue").arg(root.n(root.stats ? root.stats.currentStreak : 0)) }
              Stat { width: (parent.width - parent.spacing * 3) / 4; caption: root.t("bestStreak"); value: root.t("streakValue").arg(root.n(root.stats ? root.stats.bestStreak : 0)) }
              Stat { width: (parent.width - parent.spacing * 3) / 4; caption: root.t("onTrackDays"); value: root.stats ? root.n(root.stats.successCount) : "0" }
              Stat { width: (parent.width - parent.spacing * 3) / 4; caption: root.t("setbackDays"); value: root.stats ? root.n(root.stats.failureCount) : "0"; tone: root.stats && root.stats.failureCount ? root.urgent : root.foreground }
            }
            CheckIn { id: checkIn; visible: root.tab === "task"; width: parent.width }

            Column {
              visible: root.tab === "task"
              width: parent.width
              spacing: Style.space(12)
              Item {
                width: parent.width
                height: Style.space(34)
                Label {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.locale.toString(new Date(root.viewYear, root.viewMonth, 1, 12), "MMMM yyyy")
                  font.pixelSize: Math.max(14, Style.font.title)
                  font.bold: true
                }
                Row {
                  anchors.right: parent.right
                  spacing: Style.space(6)
                  Action { text: root.t("today"); onClicked: root.inspectDay(root.todayKey) }
                  Action { text: Commons.I18n.rightToLeft ? "›" : "‹"; Accessible.name: root.t("previousMonth"); enabled: root.canMoveMonth(-1); onClicked: root.moveMonth(-1) }
                  Action { text: Commons.I18n.rightToLeft ? "‹" : "›"; Accessible.name: root.t("nextMonth"); enabled: root.canMoveMonth(1); onClicked: root.moveMonth(1) }
                }
              }
              Row {
                id: weekdayRow
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: [1, 2, 3, 4, 5, 6, 7]
                  Label {
                    required property int modelData
                    width: (weekdayRow.width - weekdayRow.spacing * 6) / 7
                    text: root.locale.dayName(modelData, Locale.ShortFormat)
                    color: root.dim
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Math.max(11, Style.font.caption)
                  }
                }
              }
              Grid {
                id: calendar
                objectName: "habitCalendar"
                width: parent.width
                columns: 7
                spacing: Style.space(6)
                activeFocusOnTab: true
                onActiveFocusChanged: if (activeFocus) root.revealFocus(this)
                Accessible.role: Accessible.Table
                Accessible.name: root.t("calendar")
                Keys.onLeftPressed: root.moveDay(Commons.I18n.rightToLeft ? 1 : -1)
                Keys.onRightPressed: root.moveDay(Commons.I18n.rightToLeft ? -1 : 1)
                Keys.onUpPressed: root.moveDay(-7)
                Keys.onDownPressed: root.moveDay(7)
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Home) {
                    root.inspectDay(root.todayKey)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    checkIn.focusAnswer()
                    event.accepted = true
                  }
                }
                Repeater {
                  model: root.cells
                  Rectangle {
                    id: cell
                    required property var modelData
                    readonly property bool success: modelData.state === "success"
                    readonly property bool failure: modelData.state === "failure"
                    readonly property color tone: success ? root.accent : failure ? root.urgent : root.foreground
                    width: (calendar.width - calendar.spacing * 6) / 7
                    height: Style.space(34)
                    radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(5)) : 0
                    opacity: modelData.inMonth && modelData.source !== "before" && modelData.source !== "future" ? 1 : 0.28
                    color: success || failure ? root.tint(tone, 0.16)
                      : hover.hovered && modelData.selectable ? root.tint(tone, 0.09) : root.tint(tone, 0.035)
                    border.width: modelData.date === root.selectedDay ? 1 : 0
                    border.color: calendar.activeFocus ? root.accent : root.foreground
                    Accessible.role: Accessible.Cell
                    Accessible.name: root.t("calendarDay").arg(root.displayDate(modelData.date))
                      .arg(root.t(success ? "onTrack" : failure ? "setback"
                        : modelData.source === "pending" ? "pending" : "outsideTracking"))
                    Accessible.selected: modelData.date === root.selectedDay
                    Label {
                      anchors.centerIn: parent
                      text: root.n(cell.modelData.day)
                      color: cell.success || cell.failure ? cell.tone : root.foreground
                      font.bold: cell.modelData.today
                    }
                    Label {
                      anchors.right: parent.right
                      anchors.bottom: parent.bottom
                      anchors.margins: Style.space(3)
                      text: cell.failure ? "×" : cell.success ? "✓" : ""
                      color: cell.tone
                      font.pixelSize: Math.max(9, Style.font.caption - 1)
                    }
                    Rectangle {
                      visible: cell.modelData.automatic
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.margins: Style.space(5)
                      width: Style.space(3)
                      height: width
                      radius: width / 2
                      color: cell.tone
                    }
                    Rectangle {
                      visible: cell.modelData.today
                      anchors.bottom: parent.bottom
                      anchors.horizontalCenter: parent.horizontalCenter
                      anchors.bottomMargin: Style.space(3)
                      width: Style.space(12)
                      height: 1
                      color: root.foreground
                    }
                    TapHandler { enabled: cell.modelData.selectable; onTapped: { root.inspectDay(cell.modelData.date); root.revealFocus(checkIn) } }
                    HoverHandler { id: hover; cursorShape: cell.modelData.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                  }
                }
              }
              Row {
                spacing: Style.space(18)
                Legend { label: root.t("onTrack"); tone: root.accent }
                Legend { label: root.t("setback"); tone: root.urgent }
                Legend { label: root.t("automatic"); tone: root.dim; dot: true }
              }
            }

            Column {
              visible: root.tab === "analysis"
              objectName: "habitAnalysis"
              width: parent.width
              spacing: Style.space(16)
              PanelSeparator { foreground: root.foreground }
              Label { text: root.t("successRate"); font.bold: true; font.pixelSize: Math.max(15, Style.font.title) }
              Row {
                width: parent.width
                spacing: Style.space(12)
                Rate { width: (parent.width - parent.spacing * 2) / 3; caption: root.t("last7"); correct: root.stats ? root.stats.weekSuccess : 0; total: root.stats ? root.stats.weekAnswered : 0 }
                Rate { width: (parent.width - parent.spacing * 2) / 3; caption: root.t("last30"); correct: root.stats ? root.stats.monthSuccess : 0; total: root.stats ? root.stats.monthAnswered : 0 }
                Rate { width: (parent.width - parent.spacing * 2) / 3; caption: root.t("allTime"); correct: root.stats ? root.stats.successCount : 0; total: root.stats ? root.stats.answered : 0 }
              }
              Label {
                width: parent.width
                text: root.stats ? root.t("answerCounts").arg(root.n(root.stats.manualCount)).arg(root.n(root.stats.automaticCount)) : ""
                color: root.dim
                wrapMode: Text.Wrap
              }
              PanelSeparator { foreground: root.foreground }
              Label { text: root.t("recovery"); font.bold: true; font.pixelSize: Math.max(15, Style.font.title) }
              Column {
                width: parent.width
                spacing: Style.space(10)
                Label {
                  width: parent.width
                  text: root.recoveryText()
                  color: root.stats && root.stats.pendingRecovery ? root.urgent : root.foreground
                  wrapMode: Text.Wrap
                }
                Label {
                  visible: text !== ""
                  width: parent.width
                  text: root.stats && root.stats.latestRecovery
                    ? root.t("latestRecovery").arg(root.displayDate(root.stats.latestRecovery.from))
                        .arg(root.displayDate(root.stats.latestRecovery.to))
                        .arg(strings.tn("days", root.stats.latestRecovery.days).arg(root.n(root.stats.latestRecovery.days))) : ""
                  color: root.dim
                  wrapMode: Text.Wrap
                }
                Label {
                  visible: root.stats && root.stats.latestRecovery && root.stats.latestRecovery.automatic
                  width: parent.width
                  text: root.t("autoRecovery")
                  color: root.dim
                  wrapMode: Text.Wrap
                }
                Label {
                  width: parent.width
                  text: root.stats && root.stats.recoveries ? root.t("averageRecovery").arg(root.n(root.stats.averageRecoveryDays, 1)) : ""
                  visible: text !== ""
                  color: root.dim
                  wrapMode: Text.Wrap
                }
              }
              PanelSeparator { foreground: root.foreground }
              Label { width: parent.width; text: root.t("analysisHelp"); color: root.dim; wrapMode: Text.Wrap; font.pixelSize: Math.max(11, Style.font.caption) }
            }
          }

          // Editing is a separate, uncluttered surface. No data-management
          // controls are mixed into the everyday check-in.
          Column {
            visible: root.editing
            width: parent.width
            spacing: Style.space(18)
            Label { visible: root.creating; text: root.t("newHabit"); font.pixelSize: Math.max(22, Style.font.display); font.bold: true }
            FieldGroup {
              width: parent.width
              label: root.t("habitName")
              DraftField {
                objectName: "habitName"
                Accessible.name: root.t("habitName")
                text: root.draftName
                onTextEdited: root.draftName = text
                maximumLength: 96
              }
            }
            FieldGroup {
              width: parent.width
              label: root.t("habitType")
              Row {
                spacing: Style.space(8)
                Action { text: root.t("buildHabit"); selected: root.draftKind === "good"; onClicked: { root.draftKind = "good"; root.saved = false } }
                Action { text: root.t("quitHabit"); selected: root.draftKind === "bad"; onClicked: { root.draftKind = "bad"; root.saved = false } }
              }
              Label { width: parent.width; text: root.t(root.draftKind === "bad" ? "badHint" : "goodHint"); wrapMode: Text.Wrap; color: root.dim; font.pixelSize: Math.max(11, Style.font.caption) }
            }
            FieldGroup {
              width: parent.width
              label: root.t("question")
              DraftField {
                objectName: "habitQuestion"
                Accessible.name: root.t("question")
                text: root.draftQuestion
                onTextEdited: root.draftQuestion = text
                maximumLength: 256
              }
            }
            FieldGroup {
              width: parent.width
              label: root.t("message")
              DraftField {
                objectName: "habitMessage"
                Accessible.name: root.t("message")
                text: root.draftMessage
                onTextEdited: root.draftMessage = text
                maximumLength: 512
                placeholderText: root.t("optional")
              }
            }
            FieldGroup {
              width: parent.width
              label: root.t("startingDate")
              Flow {
                width: parent.width
                spacing: Style.space(8)
                DraftField {
                  objectName: "habitStartDate"
                  Accessible.name: root.t("startingDate")
                  width: Math.min(parent.width, Style.space(190))
                  text: root.draftStart
                  onTextEdited: root.draftStart = text
                  placeholderText: root.displayDate(root.todayKey)
                }
                Action {
                  id: chooseDateButton
                  objectName: "chooseStartDate"
                  text: root.t(root.datePickerOpen ? "hideDatePicker" : "chooseDate")
                  selected: root.datePickerOpen
                  onClicked: root.datePickerOpen = !root.datePickerOpen
                }
              }
              Loader {
                width: Math.min(parent.width, Style.space(336))
                active: root.datePickerOpen && root.editing
                onLoaded: Qt.callLater(function() {
                  if (item) { root.revealFocus(item); item.focusDays() }
                })
                sourceComponent: StartDatePicker {
                  objectName: "startDatePicker"
                  initialDate: root.draftDateKey
                  maximumDate: root.todayKey
                  locale: root.locale
                  translations: strings
                  foreground: root.foreground
                  accent: root.accent
                  muted: root.dim
                  fontFamily: root.fontFamily
                  onPicked: function(dateKey) {
                    root.setDraftDate(dateKey)
                    chooseDateButton.forceActiveFocus()
                  }
                  onDismissed: {
                    root.datePickerOpen = false
                    chooseDateButton.forceActiveFocus()
                  }
                }
              }
            }
            FieldGroup {
              width: parent.width
              label: root.t("defaultAnswer")
              Row {
                spacing: Style.space(8)
                Action { text: root.t("yes"); selected: root.draftDefault === "yes"; onClicked: { root.draftDefault = "yes"; root.saved = false } }
                Action { text: root.t("no"); selected: root.draftDefault === "no"; onClicked: { root.draftDefault = "no"; root.saved = false } }
                Action { text: root.t("noDefault"); selected: root.draftDefault === ""; onClicked: { root.draftDefault = ""; root.saved = false } }
              }
              Label { width: parent.width; text: root.t("defaultHint"); wrapMode: Text.Wrap; color: root.dim; font.pixelSize: Math.max(11, Style.font.caption) }
              Label {
                objectName: "defaultPreview"
                visible: root.previewDays > 0
                width: parent.width
                wrapMode: Text.Wrap
                color: root.accent
                text: root.previewDays > 0 ? strings.tn("defaultPreview", root.previewDays)
                  .arg(root.n(root.previewDays)).arg(root.t(root.draftDefault)) : ""
              }
            }
            Label { visible: text !== ""; width: parent.width; text: root.formError; color: root.urgent; wrapMode: Text.Wrap }
            Row {
              spacing: Style.space(10)
              Action { objectName: "saveHabit"; text: root.t(root.saving ? "saving" : "saveHabit"); selected: true; enabled: !root.busy; onClicked: root.save() }
              Action { text: root.t("cancel"); enabled: !root.busy; onClicked: root.cancel() }
              Label {
                visible: root.saved
                anchors.verticalCenter: parent.verticalCenter
                text: root.t("saved")
                color: root.accent
              }
            }
            PanelSeparator { visible: root.editId !== ""; foreground: root.foreground }
            Action {
              visible: root.editId !== ""
              text: root.t(root.deleteArmed ? "confirmDelete" : "deleteHabit")
              foreground: root.urgent
              enabled: !root.busy
              bordered: false
              onClicked: root.remove()
            }
            Label { width: parent.width; text: root.t("privacy"); color: root.dim; wrapMode: Text.Wrap; font.pixelSize: Math.max(11, Style.font.caption) }
          }
        }
      }
    }
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Math.max(13, Style.font.body)
    lineHeight: 1.2
  }
  component DraftField: TextField {
    width: parent.width
    foreground: root.foreground
    font.pixelSize: Math.max(13, Style.font.body)
    onActiveFocusChanged: if (activeFocus) root.revealFocus(this)
    onTextEdited: root.saved = false
  }
  component Action: Button {
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    fontSize: Math.max(12, Style.font.bodySmall)
    bordered: true
    focusable: true
    horizontalPadding: Style.space(12)
    verticalPadding: Style.space(8)
    opacity: enabled ? 1 : 0.4
    onActiveFocusChanged: if (activeFocus && activeFocusOnTab) root.revealFocus(this)
  }
  component Card: BorderSurface {
    color: root.tint(root.foreground, 0.025)
    borderSpec: Border.flat(root.tint(root.foreground, 0.12), 1)
    radius: Style.cornerRadius
  }
  component CheckIn: Card {
    implicitHeight: checkinColumn.implicitHeight + Style.space(30)
    function focusAnswer() {
      var answer = answerButtons.itemAt(root.record.value === "no" ? 1 : 0)
      if (answer && answer.enabled) answer.forceActiveFocus()
    }
    Column {
      id: checkinColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: Style.space(16)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(9)
      Item {
        width: parent.width
        height: Math.max(dateLabel.implicitHeight, sourceLabel.implicitHeight)
        Label { id: dateLabel; anchors.left: parent.left; text: root.displayDate(root.selectedDay); color: root.dim; font.pixelSize: Math.max(11, Style.font.bodySmall) }
        Label {
          id: sourceLabel
          anchors.right: parent.right
          text: root.t(root.record.source === "automatic" ? "automaticAnswer" : root.record.value ? "manualAnswer" : "awaitingAnswer")
          color: root.record.source === "automatic" ? root.accent : root.dim
          font.pixelSize: Math.max(11, Style.font.caption)
        }
      }
      Label { width: parent.width; text: root.habit ? root.habit.question : ""; wrapMode: Text.Wrap; font.pixelSize: Math.max(15, Style.font.heading); font.bold: true }
      Label {
        visible: text !== ""
        width: parent.width
        text: root.habit ? root.habit.message : ""
        color: root.dim
        wrapMode: Text.Wrap
      }
      Flow {
        width: parent.width
        spacing: Style.space(8)
        Repeater {
          id: answerButtons
          model: ["yes", "no"]
          Action {
            required property string modelData
            objectName: "answer-" + modelData
            width: Style.space(85)
            text: root.t(modelData)
            selected: root.record.value === modelData
            foreground: !selected ? root.foreground
              : root.habit && Model.successFor(root.habit.kind, modelData) ? root.accent : root.urgent
            Accessible.description: root.t(root.habit && Model.successFor(root.habit.kind, modelData) ? "onTrack" : "setback")
            enabled: !root.busy && root.habit && root.selectedDay >= root.habit.startDate && root.selectedDay <= root.todayKey
            onClicked: root.hostWidget.setAnswer(root.habit.id, root.selectedDay, modelData)
          }
        }
        Action {
          visible: root.record.source === "manual"
          text: root.t(root.selectedDay < root.todayKey && root.habit && root.habit.defaultAnswer ? "useDefault" : "clear")
          bordered: false
          enabled: !root.busy
          onClicked: root.hostWidget.setAnswer(root.habit.id, root.selectedDay, "")
        }
      }
      Label {
        width: parent.width
        text: root.habit ? root.t(root.habit.kind === "bad" ? "badHint" : "goodHint") : ""
        color: root.dim
        wrapMode: Text.Wrap
        font.pixelSize: Math.max(11, Style.font.caption)
      }
    }
  }
  component Stat: Column {
    property string caption: ""
    property string value: ""
    property color tone: root.foreground
    spacing: Style.space(8)
    Label { text: parent.value; color: parent.tone; font.pixelSize: Math.max(23, Style.font.display); font.bold: true }
    Label { width: parent.width; text: parent.caption; color: root.dim; font.pixelSize: Math.max(11, Style.font.caption); wrapMode: Text.Wrap }
  }
  component Rate: Column {
    id: rate
    property string caption: ""
    property int correct: 0
    property int total: 0
    spacing: Style.space(7)
    Label { width: parent.width; text: rate.caption; color: root.dim; wrapMode: Text.Wrap }
    Label { text: root.pct(rate.total ? rate.correct / rate.total : 0, rate.total); font.pixelSize: Math.max(22, Style.font.display); font.bold: true }
    Label { width: parent.width; text: root.t("rateCount").arg(root.n(rate.correct)).arg(root.n(rate.total)); color: root.dim; wrapMode: Text.Wrap; font.pixelSize: Math.max(11, Style.font.caption) }
  }
  component Legend: Row {
    property string label: ""
    property color tone: root.accent
    property bool dot: false
    spacing: Style.space(7)
    Rectangle { width: Style.space(6); height: width; radius: parent.dot ? width / 2 : Style.space(1); color: parent.tone; anchors.verticalCenter: parent.verticalCenter }
    Label { text: parent.label; color: root.dim; font.pixelSize: Math.max(11, Style.font.caption) }
  }
  component FieldGroup: Column {
    property string label: ""
    spacing: Style.space(9)
    Label { text: parent.label; font.pixelSize: Math.max(12, Style.font.bodySmall); font.bold: true }
  }
}
