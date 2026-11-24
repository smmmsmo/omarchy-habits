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
  property string tab: "today"
  property bool saved: false
  property bool detailsOpen: false
  property bool saving: false
  property bool deleteArmed: false
  property string editId: ""
  property string draftName: ""
  property string draftKind: "good"
  property string draftQuestion: ""
  property string draftMessage: ""
  property string draftStart: Model.todayKey()
  property string draftEnd: ""
  property string draftDefault: ""
  property string draftTarget: ""
  property string draftUnit: ""
  property string calendarMode: "month"
  readonly property bool yearMode: calendarMode === "year"
  readonly property bool weekMode: calendarMode === "week"
  property int overviewYear: new Date().getFullYear()
  property string archiveViewId: ""
  property string formError: ""
  property string returnTab: "today"
  property int appDraftWeekStart: 1
  property bool appModified: false
  property bool appSaved: false

  readonly property string todayKey: hostWidget ? hostWidget.todayKey : Model.todayKey()
  readonly property var trackerState: hostWidget ? hostWidget.trackerState : Model.emptyState()
  readonly property var activeHabits: Model.activeHabits(trackerState)
  readonly property var archivedHabits: trackerState.habits.filter(Model.isArchived)
  readonly property bool viewingArchive: tab === "analysis" && archiveViewId !== ""
  readonly property bool overview: tab === "archive" || viewingArchive
  readonly property bool canUndoHere: !!hostWidget && hostWidget.canUndo && !!habit
    && selectedDay === todayKey && hostWidget.undoEntry.id === habit.id
  readonly property var habit: viewingArchive ? Model.findHabit(trackerState, archiveViewId)
    : activeHabit(selectedId) || activeHabit(trackerState.selectedHabitId) || activeHabits[0] || null
  readonly property bool editing: creating || (tab === "settings" && habit !== null)
  readonly property bool appSettingsOpen: tab === "appSettings"
  readonly property string throughDate: Model.throughDate(habit, todayKey)
  readonly property string maximumEndDate: Math.max(Number(todayKey.slice(0, 4)) + 100,
    habit && habit.endDate ? Number(habit.endDate.slice(0, 4)) : 0) + "-12-31"
  readonly property var deadline: Model.dateMetrics(habit, todayKey)
  readonly property int weekStart: Model.weekStartDay(trackerState.preferences && trackerState.preferences.weekStart)
  readonly property var stats: opened && habit && !creating && (tab === "today" || tab === "analysis")
    ? Model.analyzeHabit(habit, trackerState, todayKey) : null
  readonly property int previewDays: editing && draftKind !== "count" && draftStart >= "1900-01-01"
    ? Model.defaultPreview(trackerState, editId, draftStart, todayKey, draftDefault, draftEnd) : 0
  readonly property var record: Model.recordFor(trackerState, habit, selectedDay, todayKey)
  readonly property var cells: weekMode ? Model.weekGrid(habit, trackerState, selectedDay, todayKey)
    : Model.monthGrid(habit, trackerState, viewYear, viewMonth, todayKey)
  readonly property var weekSummary: weekMode ? Model.summarizeWeek(cells) : null
  readonly property var yearMonths: opened && tab === "analysis" && yearMode
    ? Model.yearMonths(habit, trackerState, overviewYear, todayKey) : []
  readonly property bool countHabit: !!habit && habit.kind === "count"
  readonly property bool canCheckIn: !busy && !!habit && !viewingArchive && !Model.isArchived(habit)
    && selectedDay <= todayKey && Model.isDue(habit, selectedDay)
  readonly property color foreground: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property color surface: Commons.Color.popups.background
  readonly property color calendarSuccess: Model.paletteColor("success", surface)
  readonly property color calendarSetback: Model.paletteColor("failure", surface)
  readonly property color calendarProgress: Model.paletteColor("progress", surface)
  readonly property color bestStreakTone: Model.paletteColor("best", surface)
  readonly property color dim: readable(blend(foreground, surface, 0.8), surface)
  readonly property bool busy: !hostWidget || hostWidget.busy || !hostWidget.loaded
  // Keep the bar's monospace glyphs separate from the popup's prose and controls.
  readonly property string fontFamily: Qt.fontFamilies().indexOf("Adwaita Sans") >= 0 ? "Adwaita Sans" : "sans-serif"
  readonly property real typeScale: Math.max(1, Style.fontScale)
  readonly property int secondarySize: typeSize(12)
  readonly property int bodySize: typeSize(12)
  readonly property int answerSize: typeSize(13)
  readonly property int headingSize: typeSize(16)
  readonly property int displaySize: typeSize(18)
  readonly property int questionSize: typeSize(22)
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
  function pct(rate, count) { return count ? n(Math.round(rate * 100)) + "%" : "—" }
  function typeSize(size) { return Math.round(size * typeScale) }
  function tint(color, opacity) { return Qt.rgba(color.r, color.g, color.b, opacity) }
  function blend(fg, bg, amount) {
    return Qt.rgba(fg.r * amount + bg.r * (1 - amount), fg.g * amount + bg.g * (1 - amount),
      fg.b * amount + bg.b * (1 - amount), 1)
  }
  // Keep text legible when a theme's accent is suitable for marks but not text.
  function readable(tone, background) {
    return Model.contrast(tone, background) >= 4.5 ? tone : foreground
  }
  function statusTone(status) {
    return status === "success" ? calendarSuccess : status === "failure" ? calendarSetback
      : status === "progress" ? calendarProgress : dim
  }
  function statusMark(status) {
    return status === "success" ? "✓" : status === "failure" ? "×" : status === "progress" ? "◐"
      : status === "paused" ? "–" : "·"
  }
  function statusKey(status) {
    return status === "success" ? "onTrack" : status === "failure" ? "setback"
      : status === "progress" ? "inProgress" : status === "paused" ? "paused"
      : status === "pending" ? "pending" : status === "after" ? "ended" : "outsideTracking"
  }
  function statusFor(item, day) {
    return Model.outcome(item, Model.recordFor(trackerState, item, day, todayKey), day, todayKey)
  }
  function deadlineText() {
    if (!deadline) return ""
    if (deadline.ended) return t("endedOn").arg(displayDate(habit.endDate))
    if (deadline.dueToday) return t("endsToday")
    return strings.tn("daysLeft", deadline.left).arg(n(deadline.left))
      + " · " + t("endsOn").arg(displayDate(habit.endDate))
  }
  function countText(item, value) {
    var shown = value === "" ? "—" : n(value)
    return item.unit ? t("countWithUnit").arg(shown).arg(n(item.target)).arg(item.unit)
      : t("countProgress").arg(shown).arg(n(item.target))
  }
  function activeHabit(id) {
    var item = Model.findHabit(trackerState, id)
    return Model.isArchived(item) ? null : item
  }
  function chooseHabit(id) {
    if (saving) return
    var wasCreating = creating
    creating = false
    selectedId = id
    archiveViewId = ""
    saved = false
    detailsOpen = false
    deleteArmed = false
    if (wasCreating) tab = "today"
    if (tab === "settings" && habit) loadDraft(habit)
    inspectDay(tab === "analysis" ? throughDate : todayKey)
    if (hostWidget && typeof hostWidget.rememberHabit === "function") hostWidget.rememberHabit(id)
    if (panel.loadedContent) panel.loadedContent.scrollArea.contentY = 0
  }
  function setTab(next, keepDay) {
    if (saving) return
    if (!creating && tab === next) {
      if (next === "today" && !keepDay) inspectDay(todayKey)
      return
    }
    if (next === "appSettings" && tab !== "archive") returnTab = tab
    if (next !== "analysis") archiveViewId = ""
    creating = false
    tab = next
    saved = false
    deleteArmed = false
    if (next === "today" && !keepDay) inspectDay(todayKey)
    if (next === "analysis" && habit) inspectDay(throughDate)
    if (next === "settings") {
      if (habit) loadDraft(habit)
      else beginEdit(null)
    }
    if (next === "appSettings") loadAppDraft()
    if (panel.loadedContent) panel.loadedContent.scrollArea.contentY = 0
  }
  function showToday(id) {
    chooseHabit(id)
    setTab("today")
  }
  function showArchived(id) {
    if (saving || !Model.isArchived(Model.findHabit(trackerState, id))) return
    archiveViewId = id
    setTab("analysis")
    calendarMode = "month"
    inspectDay(throughDate)
  }
  function inspectDay(day) {
    selectedDay = day
    var date = Model.dateFromKey(day)
    viewYear = date.getFullYear()
    viewMonth = date.getMonth()
    overviewYear = viewYear
  }
  function canMoveYear(delta) {
    return habit && overviewYear + delta >= Number(habit.startDate.slice(0, 4))
      && overviewYear + delta <= Number(throughDate.slice(0, 4))
  }
  function openYearMonth(first) {
    inspectDay(first < habit.startDate ? habit.startDate : first)
    calendarMode = "month"
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
    return delta < 0 ? next >= habit.startDate.slice(0, 7) : next <= throughDate.slice(0, 7)
  }
  function canMoveWeek(delta) {
    if (!habit) return false
    var first = Model.addDays(Model.startOfWeek(selectedDay, weekStart), delta * 7)
    return first <= throughDate && Model.addDays(first, 6) >= habit.startDate
  }
  function moveWeek(delta) {
    if (!canMoveWeek(delta)) return
    var next = Model.addDays(selectedDay, 7 * delta)
    inspectDay(next < habit.startDate ? habit.startDate : next > throughDate ? throughDate : next)
  }
  function openPage(page) {
    deleteArmed = false
    saved = false
    detailsOpen = false
    formError = ""
    if (hostWidget && !hostWidget.pendingSelection && !hostWidget.busy) selectedId = ""
    if (!saving) {
      creating = false
      archiveViewId = ""
      tab = page
      inspectDay(page === "analysis" ? throughDate : todayKey)
      if (page === "appSettings") { returnTab = "today"; loadAppDraft() }
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
    tab = item ? "settings" : "today"
    loadDraft(item)
    if (panel.loadedContent) panel.loadedContent.scrollArea.contentY = 0
  }
  function loadDraft(item) {
    editId = item ? item.id : ""
    draftName = item ? item.name : ""
    draftKind = item ? item.kind : "good"
    draftQuestion = item ? item.question : t("defaultQuestion")
    draftMessage = item ? item.message : ""
    draftStart = item ? item.startDate : todayKey
    draftEnd = item ? item.endDate || "" : ""
    draftDefault = item ? item.defaultAnswer : ""
    draftTarget = item && item.kind === "count" ? String(item.target) : ""
    draftUnit = item && item.kind === "count" ? item.unit : ""
    saved = false
    deleteArmed = false
    formError = ""
  }
  function cancel() { setTab("today") }
  function setDraftDate(key) {
    draftStart = key
    if (draftEnd && draftEnd < key) draftEnd = key
    saved = false
  }
  function loadAppDraft() {
    appDraftWeekStart = weekStart
    appModified = false
    appSaved = false
  }
  function setAppWeekStart(day) {
    if (saving || day === appDraftWeekStart) return
    appDraftWeekStart = day
    appModified = day !== weekStart
    appSaved = false
  }
  function saveAppSettings() {
    if (busy || saving) return
    saving = true
    appSaved = false
    hostWidget.savePreferences(appDraftWeekStart)
  }
  function save() {
    if (busy) return
    var start = draftStart
    if (!draftName.trim()) { formError = t("nameError"); return }
    if (!draftQuestion.trim()) { formError = t("questionError"); return }
    if (!Model.validKey(start) || start < "1900-01-01" || start > todayKey) { formError = t("dateError"); return }
    if (draftEnd && (!Model.validKey(draftEnd) || draftEnd < start || draftEnd > maximumEndDate)) {
      formError = t("endDateError")
      return
    }
    var target = Number(draftTarget)
    if (draftKind === "count" && (!Model.validCount(target) || target === 0)) {
      formError = t("targetError")
      return
    }
    saving = true
    saved = false
    formError = ""
    hostWidget.saveHabit({
      id: editId, name: draftName, kind: draftKind, question: draftQuestion,
      message: draftMessage, startDate: start, endDate: draftEnd, defaultAnswer: draftKind === "count" ? "" : draftDefault,
      target: target, unit: draftUnit
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
    return statusFor(item, todayKey)
  }
  function dayStatus() {
    var status = t(statusKey(Model.outcome(habit, record, selectedDay, todayKey)))
    return record.source === "automatic" ? t("automaticResult").arg(status) : status
  }
  function moveDay(offset) {
    if (!habit) return
    var day = Model.addDays(selectedDay, offset)
    if (day >= habit.startDate && day <= throughDate) inspectDay(day)
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
  onTodayKeyChanged: {
    inspectDay(tab === "analysis" ? Model.throughDate(habit, todayKey) : todayKey)
  }
  Timer { id: deleteTimer; interval: 5000; onTriggered: root.deleteArmed = false }
  Connections {
    target: root.hostWidget
    ignoreUnknownSignals: true
    function onOperationFinished(action, success, habitId) {
      if (action === "setPreferences") {
        root.saving = false
        if (success) {
          root.loadAppDraft()
          root.appSaved = true
        }
      }
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
      if ((action === "delete" || action === "archive") && success) {
        root.setTab("today")
        root.selectedId = ""
      }
      if (action === "read" && success && root.tab === "settings" && !root.creating && root.habit && root.editId !== root.habit.id)
        root.loadDraft(root.habit)
      if (action === "read" && success && root.tab === "analysis" && root.selectedDay > root.throughDate)
        root.inspectDay(root.throughDate)
      if (action === "read" && success && root.appSettingsOpen && !root.appModified && !root.appSaved)
        root.loadAppDraft()
    }
  }

  KeyboardPanel {
    id: panel
    objectName: "habitsPopup"
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    padding: Math.min(24, Math.max(16, Math.round(contentWidth * 0.034)))
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Math.max(560, Math.min(670, Style.space(594))))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight || 340)

    content: Item {
      id: content
      property alias scrollArea: detailScroll
      readonly property bool multipleHabits: root.activeHabits.length > 1
      readonly property bool showSidebar: root.activeHabits.length > 0 && !root.overview && !root.creating
        && !root.appSettingsOpen && width >= Math.max(425, Math.min(500, Style.space(425)))
      anchors.fill: parent
      implicitHeight: Math.max(245, bodyTop.y + Math.max(detailColumn.implicitHeight,
        showSidebar ? Math.min(habitList.implicitHeight, Style.space(220)) : 0))
      focus: true
      Keys.onEscapePressed: {
        if (root.appSettingsOpen) root.setTab(root.returnTab)
        else if (root.viewingArchive) root.setTab("archive")
        else if (root.tab === "archive") root.setTab("appSettings")
        else if (root.editing) root.cancel()
        else root.close()
      }

      Item {
        id: header
        width: parent.width
        height: Math.max(headerActions.implicitHeight, Style.space(40))
        Label {
          objectName: "popupTitle"
          anchors.left: parent.left
          anchors.right: headerActions.left
          anchors.rightMargin: Style.space(12)
          anchors.verticalCenter: parent.verticalCenter
          text: root.appSettingsOpen ? root.t("appSettings")
            : root.creating ? root.t("newHabit")
            : root.tab === "archive" ? root.t("archive")
            : root.habit && (root.viewingArchive || (!content.showSidebar && !content.multipleHabits))
              ? root.habit.name : root.t("title")
          font.pixelSize: root.displaySize
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }
        Row {
          id: headerActions
          anchors.right: parent.right
          spacing: Style.space(5)
          Action {
            text: root.t("newHabit")
            iconText: "+"
            bordered: false
            background: root.tint(root.foreground, 0.06)
            visible: !root.creating && !root.appSettingsOpen && !root.overview
            enabled: !root.saving
            onClicked: root.beginEdit(null)
          }
          Action {
            objectName: "appSettingsButton"
            visible: !root.creating && !root.appSettingsOpen && !root.overview
            enabled: root.hostWidget && root.hostWidget.loaded && !root.saving
            text: "⚙"
            bordered: false
            horizontalPadding: Style.space(10)
            Accessible.name: root.t("appSettings")
            tooltipText: root.t("appSettings")
            onClicked: root.setTab("appSettings")
          }
          Action {
            text: "×"
            objectName: "closeHabits"
            Accessible.name: root.t("close")
            bordered: false
            horizontalPadding: Style.space(10)
            onClicked: root.close()
          }
        }
      }
      PanelSeparator {
        id: headerRule
        width: parent.width
        y: header.height + Style.space(10)
        foreground: root.foreground
      }
      Item { id: bodyTop; y: headerRule.y + headerRule.height + Math.max(12, Style.space(14)) }

      // The habit list is separate from the detail canvas, never another
      // stack of statistic cards competing with the selected habit.
      Item {
        id: sidebar
        objectName: "habitSidebar"
        visible: content.showSidebar
        anchors.top: bodyTop.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: Math.max(112, Math.min(158, Style.space(130)))
        Flickable {
          objectName: "habitsScroll"
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: parent.width
          contentWidth: width
          contentHeight: habitList.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          Column {
            id: habitList
            width: parent.width
            spacing: Style.space(3)
            Repeater {
              model: root.activeHabits
              Action {
                id: habitButton
                required property var modelData
                width: habitList.width
                objectName: "focus-habit-" + modelData.id
                height: Math.max(36, root.bodySize + Style.space(17))
                text: ""
                Accessible.name: root.t("habitStatus").arg(modelData.name).arg(root.t(root.statusKey(root.todayStatus(modelData))))
                selected: !!root.habit && root.habit.id === modelData.id
                bordered: false
                onClicked: root.showToday(modelData.id)
                Label {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.right: sidebarStatus.left
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: habitButton.modelData.name
                  font.weight: habitButton.selected ? Font.DemiBold : Font.Normal
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  lineHeight: 1.04
                  elide: Text.ElideRight
                }
                Label {
                  id: sidebarStatus
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(9)
                  anchors.verticalCenter: parent.verticalCenter
                  readonly property string status: root.todayStatus(habitButton.modelData)
                  text: status === "after" ? "–" : root.statusMark(status)
                  color: root.readable(root.statusTone(status), root.surface)
                  font.bold: true
                }
              }
            }
          }
        }
      }
      Rectangle {
        visible: content.showSidebar
        anchors.left: sidebar.right
        anchors.leftMargin: Style.space(12)
        anchors.top: sidebar.top
        anchors.bottom: parent.bottom
        width: 1
        color: root.tint(root.foreground, 0.10)
      }

      Flickable {
        id: detailScroll
        objectName: "habitsScroll"
        anchors.top: bodyTop.top
        anchors.left: content.showSidebar ? sidebar.right : parent.left
        anchors.leftMargin: content.showSidebar ? Style.space(28) : 0
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
          spacing: Math.max(14, Style.space(16))
          Label {
            visible: text !== ""
            width: parent.width
            text: root.hostWidget ? root.hostWidget.storageError : ""
            color: root.urgent
            wrapMode: Text.Wrap
          }

          Flow {
            visible: !root.creating && !root.appSettingsOpen && root.tab !== "archive" && !root.viewingArchive
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: ["today", "analysis", "settings"]
              Action {
                required property string modelData
                objectName: modelData + "Tab"
                text: ""
                width: tabLabel.implicitWidth + 2 * Style.space(12)
                height: Math.max(34, tabLabel.implicitHeight + Style.space(12))
                enabled: root.activeHabits.length > 0
                Accessible.role: Accessible.PageTab
                Accessible.name: root.t(modelData)
                Accessible.selected: selected
                bordered: false
                selected: root.tab === modelData
                onClicked: root.setTab(modelData)
                Label {
                  id: tabLabel
                  anchors.centerIn: parent
                  text: root.t(modelData)
                  font.weight: parent.selected ? Font.DemiBold : Font.Normal
                  color: parent.selected ? root.foreground : root.dim
                }
              }
            }
          }

          Column {
            objectName: "archiveOverview"
            visible: root.tab === "archive" && !root.creating
            width: parent.width
            spacing: Style.space(10)
            Action {
              objectName: "archiveBack"
              text: root.t("backAppSettings")
              bordered: false
              onClicked: root.setTab("appSettings")
            }
            Label {
              width: parent.width
              text: root.t(root.archivedHabits.length ? "archiveHint" : "emptyArchive")
              color: root.dim
              wrapMode: Text.Wrap
            }
            Repeater {
              model: root.tab === "archive" ? root.archivedHabits : []
              Column {
                id: archivedRow
                required property var modelData
                width: parent.width
                spacing: Style.space(6)
                PanelSeparator { foreground: root.foreground }
                Label {
                  width: parent.width
                  text: archivedRow.modelData.name
                  font.weight: Font.DemiBold
                  wrapMode: Text.Wrap
                }
                Flow {
                  width: parent.width
                  spacing: Style.space(8)
                  Action {
                    text: root.t("viewHistory")
                    onClicked: root.showArchived(archivedRow.modelData.id)
                  }
                  Action {
                    objectName: "restore-" + archivedRow.modelData.id
                    text: root.t("restoreHabit")
                    enabled: !root.busy
                    onClicked: root.hostWidget.restoreHabit(archivedRow.modelData.id)
                  }
                }
              }
            }
          }

          Column {
            visible: !root.habit && !root.editing && !root.appSettingsOpen && root.tab !== "archive"
              && root.hostWidget && root.hostWidget.loaded
            width: parent.width
            spacing: Style.space(10)
            Label { width: parent.width; text: root.t(root.archivedHabits.length ? "noActiveHabits" : "emptyTitle"); font.pixelSize: root.headingSize; font.weight: Font.DemiBold; wrapMode: Text.Wrap }
            Label { width: parent.width; text: root.t(root.archivedHabits.length ? "noActiveHint" : "emptyHint"); color: root.dim; wrapMode: Text.Wrap }
          }
          Label {
            visible: !root.habit && !root.editing && !root.appSettingsOpen && root.tab !== "archive"
              && root.hostWidget && !root.hostWidget.loaded && text !== ""
            width: parent.width
            text: root.hostWidget && root.hostWidget.storageError ? "" : root.t("loading")
            color: root.dim
          }

          Column {
            visible: root.habit !== null && !root.creating && !root.appSettingsOpen
              && (root.tab === "today" || root.tab === "analysis" || root.tab === "settings")
            width: parent.width
            spacing: Math.max(13, Style.space(16))
            QQC.ComboBox {
              id: habitPicker
              objectName: "habitPicker"
              visible: content.multipleHabits && !content.showSidebar && !root.viewingArchive
              width: parent.width
                model: root.activeHabits
              textRole: "name"
              currentIndex: root.habit ? model.indexOf(root.habit) : -1
              onActivated: function(index) { root.showToday(model[index].id) }
              Accessible.name: root.t("chooseHabit")
              contentItem: Label {
                leftPadding: Style.space(12)
                rightPadding: Style.space(28)
                text: root.habit ? root.habit.name : ""
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
              }
              background: Card { implicitHeight: Math.max(40, Style.space(44)) }
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
            CheckIn { id: checkIn; visible: root.tab === "today"; width: parent.width }

            Flow {
              visible: root.tab === "analysis"
              width: parent.width
              spacing: Style.space(8)
              Action { visible: root.viewingArchive; text: root.t("backArchive"); onClicked: root.setTab("archive") }
              Choice {
                objectName: "weekView"
                text: root.t("week")
                active: root.weekMode
                onClicked: root.calendarMode = "week"
              }
              Choice { text: root.t("month"); active: root.calendarMode === "month"; onClicked: root.calendarMode = "month" }
              Choice {
                objectName: "yearView"
                text: root.t("year")
                active: root.yearMode
                onClicked: root.calendarMode = "year"
              }
            }
            DeadlineCard { visible: root.tab === "analysis" && !!root.deadline; width: parent.width }
            YearOverview { visible: root.tab === "analysis" && root.yearMode; width: parent.width }
            Column {
              id: analysisCalendar
              visible: root.tab === "analysis" && !root.yearMode
              objectName: "habitAnalysis"
              width: parent.width
              spacing: Math.max(10, Style.space(12))
              function editDay() {
                if (!root.canCheckIn) return
                 root.setTab("today", true)
                 Qt.callLater(function() { if (root.tab === "today") checkIn.focusAnswer() })
              }
              Item {
                width: parent.width
                height: Math.max(40, monthControls.implicitHeight)
                Label {
                  anchors.left: parent.left
                  anchors.right: monthControls.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.weekMode && root.cells.length
                    ? root.displayDate(root.cells[0].date) + " – " + root.displayDate(root.cells[6].date)
                    : root.locale.toString(new Date(root.viewYear, root.viewMonth, 1, 12), "MMMM yyyy")
                  font.pixelSize: root.headingSize
                  font.weight: Font.DemiBold
                  elide: Text.ElideRight
                }
                Row {
                  id: monthControls
                  anchors.right: parent.right
                  spacing: Style.space(6)
                  Action {
                    objectName: "calendarToday"
                    text: root.t(root.throughDate === root.todayKey ? "today" : "lastDay")
                    visible: root.selectedDay !== root.throughDate
                    onClicked: { root.inspectDay(root.throughDate); calendar.forceActiveFocus() }
                  }
                  Action {
                    text: Commons.I18n.rightToLeft ? "›" : "‹"
                    Accessible.name: root.t(root.weekMode ? "previousWeek" : "previousMonth")
                    enabled: root.weekMode ? root.canMoveWeek(-1) : root.canMoveMonth(-1)
                    onClicked: root.weekMode ? root.moveWeek(-1) : root.moveMonth(-1)
                  }
                  Action {
                    text: Commons.I18n.rightToLeft ? "‹" : "›"
                    Accessible.name: root.t(root.weekMode ? "nextWeek" : "nextMonth")
                    enabled: root.weekMode ? root.canMoveWeek(1) : root.canMoveMonth(1)
                    onClicked: root.weekMode ? root.moveWeek(1) : root.moveMonth(1)
                  }
                }
              }
              Row {
                id: weekdayRow
                width: parent.width
                spacing: Style.space(6)
                Repeater {
                  model: Model.orderedWeekdays(root.weekStart)
                  Label {
                    required property int modelData
                    objectName: "calendarWeekday-" + modelData
                    width: (weekdayRow.width - weekdayRow.spacing * 6) / 7
                    text: root.locale.dayName(modelData, Locale.ShortFormat)
                    color: root.dim
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: root.secondarySize
                    elide: Text.ElideRight
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
                     root.inspectDay(root.throughDate)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                     analysisCalendar.editDay()
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
                    readonly property bool hasOutcome: success || failure || modelData.state === "progress"
                    readonly property color tone: root.statusTone(modelData.state)
                    objectName: "habitDay-" + modelData.date
                    width: (calendar.width - calendar.spacing * 6) / 7
                    height: Math.max(34, root.bodySize + Style.space(16), Style.space(40))
                    radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(5)) : 0
                    opacity: !modelData.inMonth ? 0
                      : modelData.source === "before" || modelData.source === "future" || modelData.source === "after" ? 0.38 : 1
                    color: hasOutcome ? root.tint(tone, 0.21)
                      : hover.hovered && modelData.selectable ? root.tint(tone, 0.09) : root.tint(tone, 0.035)
                    border.width: modelData.date === root.selectedDay && modelData.selectable ? 2 : 0
                    border.color: calendar.activeFocus ? root.accent : root.foreground
                    Accessible.role: Accessible.Cell
                    Accessible.name: root.t("calendarDay").arg(root.displayDate(modelData.date))
                      .arg(root.t(root.statusKey(modelData.state)))
                    Accessible.selected: modelData.date === root.selectedDay
                    Accessible.ignored: !modelData.inMonth
                    Label {
                      anchors.centerIn: parent
                      text: root.n(cell.modelData.day)
                       color: cell.hasOutcome
                         ? root.readable(cell.tone, root.blend(cell.tone, root.surface, 0.21))
                        : root.foreground
                      font.weight: cell.modelData.today ? Font.DemiBold : Font.Normal
                    }
                    Label {
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(6)
                      anchors.verticalCenter: parent.verticalCenter
                       text: cell.hasOutcome || cell.modelData.state === "paused" ? root.statusMark(cell.modelData.state) : ""
                       color: root.readable(cell.tone, root.blend(cell.tone, root.surface, cell.hasOutcome ? 0.21 : 0.035))
                      font.pixelSize: root.secondarySize
                    }
                    Rectangle {
                      visible: cell.modelData.automatic
                      anchors.right: parent.right
                      anchors.top: parent.top
                      anchors.margins: Style.space(5)
                      width: Math.max(4, Style.space(5))
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
                     readonly property bool inspectable: modelData.inMonth
                       && modelData.source !== "before" && modelData.source !== "future" && modelData.source !== "after"
                     TapHandler { enabled: cell.inspectable; onTapped: root.inspectDay(cell.modelData.date) }
                     HoverHandler { id: hover; cursorShape: cell.inspectable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                  }
                }
              }
               Legend { label: root.t("automatic"); tone: root.dim }
               Flow {
                 objectName: "weekSummary"
                 visible: root.weekMode && !!root.weekSummary
                 width: parent.width
                 spacing: Style.space(10)
                 Repeater {
                   model: ["success", "failure", "pending"]
                  Legend {
                    required property string modelData
                    tone: root.statusTone(modelData)
                    label: root.weekSummary ? strings.tn("weekCount." + modelData, root.weekSummary[modelData])
                      .arg(root.n(root.weekSummary[modelData])) : ""
                   }
                 }
               }
               Label {
                 visible: root.weekMode || root.viewingArchive || root.countHabit || root.record.source === "paused"
                 width: parent.width
                 wrapMode: Text.Wrap
                 text: root.t("calendarDay").arg(root.displayDate(root.selectedDay)).arg(root.dayStatus())
                   + (root.countHabit && root.record.value !== "" ? " · " + root.countText(root.habit, root.record.value) : "")
                 color: root.dim
               }
              PanelSeparator { foreground: root.foreground }
              Flow {
                width: parent.width
                spacing: Style.space(12)
                Action {
                  id: editAnswer
                  objectName: "editAnswer"
                  text: root.t(root.record.value !== "" ? "editAnswer" : "checkIn")
                  Accessible.description: root.t("calendarDay").arg(root.displayDate(root.selectedDay)).arg(root.dayStatus())
                  visible: !root.viewingArchive
                  enabled: root.canCheckIn
                  onClicked: analysisCalendar.editDay()
                }
                Action {
                  objectName: "progressDetails"
                  text: root.t(root.detailsOpen ? "hideProgress" : "showProgress")
                  bordered: false
                  active: root.detailsOpen
                  onClicked: {
                    root.detailsOpen = !root.detailsOpen
                    if (root.detailsOpen) Qt.callLater(function() { root.revealFocus(progressHeading) })
                  }
                }
              }
            }

            Column {
              objectName: "progressReport"
               visible: root.tab === "analysis" && !root.yearMode && root.detailsOpen
              width: parent.width
              spacing: Math.max(16, Style.space(19))
              PanelSeparator { foreground: root.foreground }
               Stat {
                 id: progressHeading
                 width: parent.width
                 caption: root.t("setbackDays")
                 value: root.n(root.stats ? root.stats.failureCount : 0)
                 tone: root.stats && root.stats.failureCount ? root.calendarSetback : root.foreground
              }
              Label { text: root.t("successRate"); font.weight: Font.DemiBold }
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
              Label { text: root.t("recovery"); font.weight: Font.DemiBold; font.pixelSize: root.headingSize }
              Column {
                width: parent.width
                spacing: Style.space(10)
                Label {
                  width: parent.width
                  text: root.recoveryText()
                  color: root.stats && root.stats.pendingRecovery ? root.readable(root.urgent, root.surface) : root.foreground
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
            }
          }

          Column {
            objectName: "appSettingsForm"
            visible: root.appSettingsOpen
            width: parent.width
            spacing: Math.max(16, Style.space(19))

            FieldGroup {
              width: parent.width
              label: root.t("weekStartsOn")
              Label {
                width: parent.width
                text: root.t("weekStartHint")
                wrapMode: Text.Wrap
                color: root.dim
              }
              Flow {
                width: parent.width
                spacing: Style.space(8)
                Repeater {
                  model: [1, 2, 3, 4, 5, 6, 7]
                  Choice {
                    required property int modelData
                    objectName: "weekStart-" + modelData
                    text: root.locale.dayName(modelData, Locale.LongFormat)
                    iconText: active ? "✓" : ""
                    active: root.appDraftWeekStart === modelData
                    enabled: !root.saving
                    onClicked: root.setAppWeekStart(modelData)
                  }
                }
              }
            }
            Flow {
              width: parent.width
              spacing: Style.space(10)
              Action {
                objectName: "saveAppSettings"
                text: root.t(root.saving ? "saving" : "saveSettings")
                active: true
                enabled: !root.busy && !root.saving && root.appModified
                onClicked: root.saveAppSettings()
              }
              Action {
                objectName: "backFromAppSettings"
                text: root.t("back")
                enabled: !root.saving
                onClicked: root.setTab(root.returnTab)
              }
              Label {
                 visible: root.appSaved
                height: Style.space(36)
                verticalAlignment: Text.AlignVCenter
                text: root.t("saved")
                 color: root.accent
               }
             }
             PanelSeparator { foreground: root.foreground }
             Action {
               objectName: "archiveTab"
               text: root.t("archive")
               onClicked: root.setTab("archive")
             }
             PanelSeparator { foreground: root.foreground }
             FieldGroup {
               width: parent.width
               label: root.t("export")
               Label { width: parent.width; text: root.t("exportHint"); color: root.dim; wrapMode: Text.Wrap }
               Flow {
                 width: parent.width
                 spacing: Style.space(8)
                 Action {
                   objectName: "exportCsv"
                   text: root.t("exportCsv")
                   enabled: !root.busy
                   onClicked: root.hostWidget.exportProgress("csv")
                 }
                 Action {
                   objectName: "exportJson"
                   text: root.t("exportJson")
                   enabled: !root.busy
                   onClicked: root.hostWidget.exportProgress("json")
                 }
               }
               Label {
                 objectName: "exportPath"
                 visible: !!root.hostWidget && root.hostWidget.exportPath !== ""
                 width: parent.width
                 text: visible ? root.t("exportSaved").arg(root.hostWidget.exportPath) : ""
                 wrapMode: Text.WrapAnywhere
                 color: root.readable(root.calendarSuccess, root.surface)
               }
             }
          }

          // Editing is a separate, uncluttered surface. No data-management
          // controls are mixed into the everyday check-in.
          Column {
            visible: root.editing
            width: parent.width
            spacing: Math.max(17, Style.space(20))
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
              Flow {
                width: parent.width
                spacing: Style.space(8)
                 Choice { visible: root.creating || root.draftKind !== "count"; text: root.t("buildHabit"); active: root.draftKind === "good"; onClicked: { root.draftKind = "good"; root.saved = false } }
                 Choice { visible: root.creating || root.draftKind !== "count"; text: root.t("quitHabit"); active: root.draftKind === "bad"; onClicked: { root.draftKind = "bad"; root.saved = false } }
                 Choice { objectName: "countKind"; visible: root.creating || root.draftKind === "count"; text: root.t("countHabit"); active: root.draftKind === "count"; onClicked: { root.draftKind = "count"; root.saved = false } }
               }
               Label { width: parent.width; text: root.t(root.draftKind === "count" ? "countHint" : root.draftKind === "bad" ? "badHint" : "goodHint"); wrapMode: Text.Wrap; color: root.dim; font.pixelSize: root.secondarySize }
             }
             FieldGroup {
               visible: root.draftKind === "count"
               width: parent.width
               label: root.t("dailyTarget")
               DraftField {
                 objectName: "dailyTarget"
                 Accessible.name: root.t("dailyTarget")
                 text: root.draftTarget
                 onTextEdited: root.draftTarget = text
                 inputMethodHints: Qt.ImhDigitsOnly
                 validator: RegularExpressionValidator { regularExpression: /[0-9]{0,7}/ }
               }
               DraftField {
                 objectName: "targetUnit"
                 Accessible.name: root.t("targetUnit")
                 text: root.draftUnit
                 onTextEdited: root.draftUnit = text
                 maximumLength: 32
                 placeholderText: root.t("targetUnit")
               }
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
              StartDatePicker {
                objectName: "startDatePicker"
                width: parent.width
                dateKey: root.draftStart
                maximumDate: root.todayKey
                locale: root.locale
                translations: strings
                foreground: root.foreground
                accent: root.accent
                surface: root.surface
                muted: root.dim
                fontFamily: root.fontFamily
                bodySize: root.bodySize
                secondarySize: root.secondarySize
                onPicked: function(dateKey) { root.setDraftDate(dateKey) }
                onFieldFocused: function(field) { root.revealFocus(field) }
              }
            }
             FieldGroup {
               width: parent.width
               label: root.t("endDate")
               Label {
                 width: parent.width
                 text: root.t("endDateHint")
                 color: root.dim
                 wrapMode: Text.Wrap
               }
               Flow {
                 width: parent.width
                 spacing: Style.space(8)
                 Choice {
                   text: root.t("noEndDate")
                   active: root.draftEnd === ""
                   onClicked: { root.draftEnd = ""; root.saved = false }
                 }
                 Choice {
                   objectName: "setEndDate"
                   text: root.t("setEndDate")
                   active: root.draftEnd !== ""
                   onClicked: {
                     if (!root.draftEnd) root.draftEnd = root.todayKey
                     root.saved = false
                   }
                 }
               }
               StartDatePicker {
                 objectName: "endDatePicker"
                 visible: root.draftEnd !== ""
                 width: parent.width
                 dateKey: root.draftEnd || root.todayKey
                 minimumDate: root.draftStart
                 maximumDate: root.maximumEndDate
                 fieldPrefix: "endDate"
                 showToday: false
                 locale: root.locale
                 translations: strings
                 foreground: root.foreground
                 accent: root.accent
                 surface: root.surface
                 muted: root.dim
                 fontFamily: root.fontFamily
                 bodySize: root.bodySize
                 secondarySize: root.secondarySize
                 onPicked: function(dateKey) { root.draftEnd = dateKey; root.saved = false }
                 onFieldFocused: function(field) { root.revealFocus(field) }
               }
             }
             FieldGroup {
               visible: root.draftKind !== "count"
               width: parent.width
               label: root.t("defaultAnswer")
              Flow {
                width: parent.width
                spacing: Style.space(8)
                Choice { text: root.t("yes"); active: root.draftDefault === "yes"; onClicked: { root.draftDefault = "yes"; root.saved = false } }
                Choice { text: root.t("no"); active: root.draftDefault === "no"; onClicked: { root.draftDefault = "no"; root.saved = false } }
                Choice { text: root.t("noDefault"); active: root.draftDefault === ""; onClicked: { root.draftDefault = ""; root.saved = false } }
              }
              Label { width: parent.width; text: root.t("defaultHint"); wrapMode: Text.Wrap; color: root.dim; font.pixelSize: root.secondarySize }
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
               Action { objectName: "saveHabit"; text: root.t(root.saving ? "saving" : "saveHabit"); active: true; enabled: !root.busy; onClicked: root.save() }
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
               objectName: "archiveHabit"
               text: root.t("archiveHabit")
               enabled: !root.busy
               onClicked: root.hostWidget.archiveHabit(root.editId)
             }
             Label {
               visible: root.editId !== ""
               width: parent.width
               text: root.t("archiveHabitHint")
               color: root.dim
               wrapMode: Text.Wrap
             }
            Action {
              visible: root.editId !== ""
              text: root.t(root.deleteArmed ? "confirmDelete" : "deleteHabit")
              foreground: root.urgent
              enabled: !root.busy
              bordered: false
              onClicked: root.remove()
            }
          }
        }
      }
    }
  }

  component Label: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.bodySize
    lineHeight: 1.24
  }
  component DraftField: TextField {
    width: parent.width
    foreground: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.bodySize
    verticalPadding: Math.max(9, Style.space(11))
    onActiveFocusChanged: if (activeFocus) root.revealFocus(this)
    onTextEdited: root.saved = false
  }
  component Action: Button {
    foreground: root.foreground
    accent: root.accent
    fontFamily: root.fontFamily
    fontSize: root.bodySize
    bordered: true
    focusable: true
    horizontalPadding: Math.max(14, Style.space(16))
    verticalPadding: Math.max(9, Style.space(10))
    opacity: enabled ? 1 : 0.4
    onActiveFocusChanged: if (activeFocus && activeFocusOnTab) root.revealFocus(this)
  }
  // Use the theme's active fill without replacing readable text with the selection tint.
  component Choice: Action {
    Accessible.selected: active
  }
  component Card: BorderSurface {
    color: root.tint(root.foreground, 0.025)
    borderSpec: Border.flat(root.tint(root.foreground, 0.12), 1)
    radius: Style.cornerRadius
  }
  component NumberEntry: Row {
    id: editor
    property var value: ""
    property bool available: false
    property string habitName: ""
    signal submitted(int value)
    function submit() {
      if (saveCount.enabled) submitted(Number(countInput.text))
    }
    function focusValue() { if (available) countInput.forceActiveFocus() }
    spacing: Style.space(8)
    DraftField {
      id: countInput
      objectName: "countValue"
      width: Math.min(Style.space(118), Math.max(52, editor.width - saveCount.implicitWidth - editor.spacing))
      enabled: editor.available
      placeholderText: root.t("countValue")
      Accessible.name: editor.habitName + " · " + root.t("countValue")
      text: typeof editor.value === "number" ? String(editor.value) : ""
      inputMethodHints: Qt.ImhDigitsOnly
      validator: RegularExpressionValidator { regularExpression: /[0-9]{0,7}/ }
      onAccepted: editor.submit()
    }
    Action {
      id: saveCount
      objectName: "saveCount"
      text: root.t("saveCount")
      enabled: editor.available && countInput.text !== "" && Model.validCount(Number(countInput.text))
        && editor.value !== Number(countInput.text)
      onClicked: editor.submit()
    }
  }
  component YearOverview: Column {
    spacing: Style.space(12)
    Row {
      spacing: Style.space(8)
      Action { text: "‹"; Accessible.name: root.t("previousYear"); enabled: root.canMoveYear(-1); onClicked: root.overviewYear-- }
      Label {
        height: Math.max(implicitHeight, nextYear.implicitHeight)
        verticalAlignment: Text.AlignVCenter
        text: root.locale.toString(new Date(root.overviewYear, 0, 1, 12), "yyyy")
        font.pixelSize: root.headingSize
        font.weight: Font.DemiBold
      }
      Action { id: nextYear; text: "›"; Accessible.name: root.t("nextYear"); enabled: root.canMoveYear(1); onClicked: root.overviewYear++ }
    }
    Flow {
      width: parent.width
      spacing: Style.space(9)
      Repeater {
        model: root.countHabit ? ["success", "failure", "progress", "paused"] : ["success", "failure", "paused"]
        Legend {
          required property string modelData
          tone: root.statusTone(modelData)
          label: root.statusMark(modelData) + " " + root.t(root.statusKey(modelData))
        }
      }
    }
    Grid {
      id: months
      width: parent.width
      columns: width >= Math.max(445, Style.space(400)) ? 4
        : width >= Math.max(325, Style.space(310)) ? 3 : 2
      spacing: Style.space(8)
      Repeater {
        model: root.yearMonths
        Action {
          id: monthButton
          required property var modelData
          readonly property string monthName: root.locale.monthName(modelData.month, Locale.ShortFormat)
          objectName: "yearMonth-" + modelData.month
          width: (months.width - (months.columns - 1) * months.spacing) / months.columns
          height: monthContent.implicitHeight + Style.space(14)
          enabled: modelData.available
          text: ""
          Accessible.name: root.t("yearMonthSummary").arg(monthName).arg(root.n(modelData.success)).arg(root.n(modelData.recorded))
          onClicked: root.openYearMonth(modelData.first)
          Column {
            id: monthContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(7)
            spacing: Style.space(5)
            Label {
              width: parent.width
              text: monthButton.monthName
              elide: Text.ElideRight
              font.weight: Font.DemiBold
            }
            Grid {
              id: miniCalendar
              width: parent.width
              columns: 7
              spacing: 2
              Repeater {
                model: monthButton.modelData.cells
                Rectangle {
                  id: tinyDay
                  required property var modelData
                  readonly property bool hasMark: ["success", "failure", "progress", "paused"].includes(modelData.state)
                  readonly property color tone: root.statusTone(modelData.state)
                  width: Math.max(2, (miniCalendar.width - 6 * miniCalendar.spacing) / 7)
                  height: Math.min(12, width)
                  radius: Math.min(2, Style.cornerRadius)
                  color: !modelData.inMonth ? "transparent" : root.tint(tone, hasMark ? 0.35
                    : modelData.state === "pending" ? 0.18 : 0.06)
                  border.width: modelData.inMonth && modelData.today ? 1 : 0
                  border.color: root.accent
                  Label {
                    anchors.centerIn: parent
                    visible: tinyDay.modelData.inMonth && tinyDay.hasMark && parent.width >= 8
                    text: root.statusMark(tinyDay.modelData.state)
                    color: root.readable(tinyDay.tone, root.blend(tinyDay.tone, root.surface, 0.35))
                    font.pixelSize: Math.min(10, Math.floor(parent.width))
                  }
                }
              }
            }
          }
        }
      }
    }
  }
  component DeadlineCard: Column {
    id: timeline
    objectName: "habitTimeline"
    spacing: Style.space(6)
    Label {
      width: parent.width
      text: root.deadlineText()
      color: root.deadline && root.deadline.dueToday ? root.readable(root.calendarProgress, root.surface) : root.foreground
      font.weight: Font.DemiBold
      wrapMode: Text.Wrap
    }
    Rectangle {
      width: parent.width
      height: Math.max(4, Style.space(5))
      radius: height / 2
      color: root.tint(root.foreground, 0.14)
      Rectangle {
        width: root.deadline ? parent.width * root.deadline.elapsed / root.deadline.total : 0
        height: parent.height
        radius: parent.radius
        color: root.readable(root.accent, root.surface)
      }
    }
    Label {
      width: parent.width
      text: root.deadline ? root.t("elapsedDays").arg(root.n(root.deadline.elapsed)).arg(root.n(root.deadline.total)) : ""
      color: root.dim
      wrapMode: Text.Wrap
      font.pixelSize: root.secondarySize
    }
  }
  component CheckIn: Column {
    objectName: "dailyCheckin"
    spacing: Math.max(12, Style.space(15))
    function focusAnswer() {
      if (root.countHabit) { countEditor.focusValue(); return }
      var answer = answerButtons.itemAt(root.record.value === "no" ? 1 : 0)
      if (answer && answer.enabled) answer.forceActiveFocus()
    }
    PanelSeparator { foreground: root.foreground }
    DeadlineCard { objectName: "taskTimeline"; visible: !!root.deadline; width: parent.width }
    Action {
      visible: root.record.source === "after"
      text: root.t("viewHistory")
      onClicked: root.setTab("analysis")
    }
    Flow {
      objectName: "pastDateContext"
      visible: root.selectedDay !== root.todayKey
      width: parent.width
      spacing: Style.space(12)
      Label {
        height: Math.max(implicitHeight, backToday.visible ? backToday.implicitHeight : 0)
        verticalAlignment: Text.AlignVCenter
        text: root.displayDate(root.selectedDay)
        color: root.dim
        font.pixelSize: root.secondarySize
      }
      Action {
        id: backToday
        objectName: "backToToday"
        text: root.t("backToday")
        bordered: false
        onClicked: root.inspectDay(root.todayKey)
      }
    }
    Label {
      objectName: "dailyQuestion"
      visible: root.record.source !== "after"
      width: parent.width
      text: root.habit ? root.habit.question : ""
      wrapMode: Text.Wrap
      font.pixelSize: root.questionSize
      font.weight: Font.DemiBold
      lineHeight: 1.12
    }
    Label {
      visible: text !== "" && root.record.source !== "after"
      width: parent.width
      text: root.habit ? root.habit.message : ""
      color: root.dim
      wrapMode: Text.Wrap
    }
    Row {
      id: answers
      visible: !root.countHabit && root.record.source !== "after"
      width: parent.width
      spacing: Style.space(8)
      Repeater {
        id: answerButtons
        model: ["yes", "no"]
        Choice {
          required property string modelData
          readonly property string answerOutcome: root.habit && Model.successFor(root.habit.kind, modelData) ? "success" : "failure"
          objectName: "answer-" + modelData
          width: (answers.width - answers.spacing) / 2
          height: Math.max(46, implicitHeight + Style.space(8), Style.space(51))
          fontSize: root.answerSize
          iconText: active ? root.statusMark(answerOutcome) : ""
          text: root.t(modelData)
          active: root.record.value === modelData
          foreground: !active ? root.foreground
            : root.readable(root.statusTone(answerOutcome), root.blend(root.foreground, root.surface, 0.15))
          Accessible.description: root.t(root.statusKey(answerOutcome))
          enabled: root.canCheckIn
          onClicked: root.hostWidget.setAnswer(root.habit.id, root.selectedDay, modelData)
        }
      }
    }
    Label {
      visible: root.countHabit && root.record.source !== "after"
      width: parent.width
      text: root.countHabit ? root.countText(root.habit, root.record.value) : ""
      color: root.readable(root.statusTone(Model.outcome(root.habit, root.record, root.selectedDay, root.todayKey)), root.surface)
      font.weight: Font.DemiBold
      wrapMode: Text.Wrap
    }
    NumberEntry {
      id: countEditor
      visible: root.countHabit && root.record.source !== "after"
      width: parent.width
      value: root.record.value
      available: root.canCheckIn
      habitName: root.habit ? root.habit.name : ""
      onSubmitted: function(value) { root.hostWidget.setAnswer(root.habit.id, root.selectedDay, value) }
    }
    Flow {
      visible: root.record.value !== "" || root.record.source === "paused" || root.canUndoHere
      width: parent.width
      spacing: Style.space(12)
      Label {
        visible: root.record.value !== "" || root.record.source === "paused"
        text: root.dayStatus()
        width: Math.min(parent.width, implicitWidth)
        height: Math.max(implicitHeight, clearAnswer.implicitHeight)
        verticalAlignment: Text.AlignVCenter
        color: root.dim
        wrapMode: Text.Wrap
      }
      Action {
        id: clearAnswer
        visible: root.record.source === "manual"
        text: root.t(root.selectedDay < root.todayKey && root.habit && root.habit.defaultAnswer ? "useDefault" : "clear")
        bordered: false
         enabled: root.canCheckIn
        onClicked: root.hostWidget.setAnswer(root.habit.id, root.selectedDay, "")
      }
      Action {
        objectName: "undoCheckIn"
        visible: root.canUndoHere
        enabled: !root.busy
        text: root.t("undo")
        onClicked: root.hostWidget.undoAnswer()
      }
    }
    StreakPair { visible: !!root.stats; width: parent.width }
  }
  component StreakPair: Row {
    objectName: "habitStreaks"
    spacing: Style.space(8)
    StreakCard {
      objectName: "currentStreak"
      width: (parent.width - parent.spacing) / 2
      caption: root.t(root.deadline && root.deadline.ended ? "finalStreak" : "currentStreak")
      days: root.stats ? root.stats.currentStreak : 0
      tone: days > 0 ? root.calendarSuccess : root.dim
    }
    StreakCard {
      objectName: "bestStreak"
      width: (parent.width - parent.spacing) / 2
      caption: root.t("bestStreak")
      days: root.stats ? root.stats.bestStreak : 0
      tone: days > 0 ? root.bestStreakTone : root.dim
    }
  }
  component StreakCard: Rectangle {
    id: streakCard
    property string caption: ""
    property int days: 0
    property color tone: root.foreground
    readonly property real inset: Style.space(11)
    height: streakColumn.implicitHeight + 2 * inset
    radius: Style.cornerRadius
    color: root.blend(tone, root.surface, days > 0 ? 0.10 : 0.04)
    border.width: 1
    border.color: root.blend(tone, root.surface, days > 0 ? 0.32 : 0.18)
    Column {
      id: streakColumn
      x: streakCard.inset
      y: streakCard.inset
      width: Math.max(0, parent.width - 2 * x)
      spacing: Style.space(4)
      Label {
        width: parent.width
        text: streakCard.caption
        color: root.readable(root.foreground, streakCard.color)
        wrapMode: Text.Wrap
      }
      Label {
        width: parent.width
        text: strings.tn("days", streakCard.days).arg(root.n(streakCard.days))
        color: root.readable(streakCard.tone, streakCard.color)
        font.pixelSize: root.displaySize
        font.weight: Font.DemiBold
        wrapMode: Text.Wrap
      }
    }
  }
  component Stat: Column {
    property string caption: ""
    property string value: ""
    property color tone: root.foreground
    spacing: Style.space(8)
    Label { text: parent.value; color: root.readable(parent.tone, root.surface); font.pixelSize: root.displaySize; font.weight: Font.DemiBold }
    Label { width: parent.width; text: parent.caption; color: root.dim; font.pixelSize: root.secondarySize; wrapMode: Text.Wrap }
  }
  component Rate: Column {
    id: rate
    property string caption: ""
    property int correct: 0
    property int total: 0
    spacing: Style.space(7)
    Label { width: parent.width; text: rate.caption; color: root.dim; wrapMode: Text.Wrap }
    Label { text: root.pct(rate.total ? rate.correct / rate.total : 0, rate.total); font.pixelSize: root.displaySize; font.weight: Font.DemiBold }
    Label { width: parent.width; text: root.t("rateCount").arg(root.n(rate.correct)).arg(root.n(rate.total)); color: root.dim; wrapMode: Text.Wrap; font.pixelSize: root.secondarySize }
  }
  component Legend: Row {
    property string label: ""
    property color tone: root.accent
    spacing: Style.space(7)
    Rectangle { width: Math.max(6, Style.space(7)); height: width; radius: width / 2; color: parent.tone; anchors.verticalCenter: parent.verticalCenter }
    Label { text: parent.label; color: root.dim; font.pixelSize: root.secondarySize }
  }
  component FieldGroup: Column {
    property string label: ""
    spacing: Style.space(9)
    Label { text: parent.label; font.weight: Font.DemiBold }
  }
}
