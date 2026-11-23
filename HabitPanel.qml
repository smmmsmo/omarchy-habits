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
  property string draftDefault: ""
  property string formError: ""
  property string returnTab: "task"
  property string appDraftStart: ""
  property bool appFixedDate: false
  property bool appModified: false
  property bool appSaved: false

  readonly property string todayKey: hostWidget ? hostWidget.todayKey : Model.todayKey()
  readonly property var trackerState: hostWidget ? hostWidget.trackerState : Model.emptyState()
  readonly property var habit: Model.findHabit(trackerState, selectedId)
    || Model.findHabit(trackerState, trackerState.selectedHabitId) || trackerState.habits[0] || null
  readonly property bool editing: creating || (tab === "settings" && habit !== null)
  readonly property bool appSettingsOpen: tab === "appSettings"
  readonly property string appDefaultStart: trackerState.preferences ? trackerState.preferences.defaultStartDate : ""
  readonly property var stats: opened && habit && tab === "analysis" ? Model.analyzeHabit(habit, trackerState, todayKey) : null
  readonly property int previewDays: editing && draftStart >= "1900-01-01"
    ? Model.defaultPreview(trackerState, editId, draftStart, todayKey, draftDefault) : 0
  readonly property var record: Model.recordFor(trackerState, habit, selectedDay, todayKey)
  readonly property var cells: Model.monthGrid(habit, trackerState, viewYear, viewMonth, todayKey)
  readonly property color foreground: Commons.Color.popups.text
  readonly property color accent: Commons.Color.accent
  readonly property color urgent: Commons.Color.urgent
  readonly property color surface: Commons.Color.popups.background
  readonly property color calendarSuccess: luminance(surface) < 0.32 ? "#75d796" : "#17683d"
  readonly property color calendarSetback: luminance(surface) < 0.32 ? "#f88c9a" : "#a32b40"
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
  function luminance(color) {
    function linear(c) { return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4) }
    return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
  }
  function readable(tone, background) {
    var ink = luminance(tone)
    var fill = luminance(background)
    return (Math.max(ink, fill) + 0.05) / (Math.min(ink, fill) + 0.05) >= 4.5 ? tone : foreground
  }
  function chooseHabit(id) {
    if (saving) return
    var wasCreating = creating
    creating = false
    selectedId = id
    saved = false
    detailsOpen = false
    deleteArmed = false
    if (wasCreating) tab = "task"
    if (tab === "settings" && habit) loadDraft(habit)
    inspectDay(todayKey)
    if (hostWidget && typeof hostWidget.rememberHabit === "function") hostWidget.rememberHabit(id)
    if (panel.loadedContent) panel.loadedContent.scrollArea.contentY = 0
  }
  function setTab(next, keepDay) {
    if (saving || (!creating && tab === next)) return
    if (next === "appSettings") returnTab = tab
    creating = false
    tab = next
    saved = false
    deleteArmed = false
    if (next === "task" && !keepDay) inspectDay(todayKey)
    if (next === "settings" && habit) loadDraft(habit)
    if (next === "appSettings") loadAppDraft()
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
    saved = false
    detailsOpen = false
    formError = ""
    if (hostWidget && !hostWidget.pendingSelection && !hostWidget.busy) selectedId = ""
    if (!saving) {
      creating = false
      tab = page
      inspectDay(todayKey)
      if (page === "appSettings") { returnTab = "task"; loadAppDraft() }
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
    loadDraft(item)
    if (panel.loadedContent) panel.loadedContent.scrollArea.contentY = 0
  }
  function loadDraft(item) {
    editId = item ? item.id : ""
    draftName = item ? item.name : ""
    draftKind = item ? item.kind : "good"
    draftQuestion = item ? item.question : t("defaultQuestion")
    draftMessage = item ? item.message : ""
    draftStart = item ? item.startDate : Model.newHabitStart(trackerState, todayKey)
    draftDefault = item ? item.defaultAnswer : ""
    saved = false
    deleteArmed = false
    formError = ""
  }
  function cancel() { setTab("task") }
  function setDraftDate(key) {
    draftStart = key
    saved = false
  }
  function loadAppDraft() {
    appFixedDate = appDefaultStart !== ""
    appDraftStart = Model.newHabitStart(trackerState, todayKey)
    appModified = false
    appSaved = false
  }
  function setAppDateMode(fixed) {
    if (saving || fixed === appFixedDate) return
    appFixedDate = fixed
    appModified = true
    appSaved = false
  }
  function saveAppSettings() {
    if (busy || saving) return
    saving = true
    appSaved = false
    hostWidget.savePreferences(appFixedDate ? appDraftStart : "")
  }
  function save() {
    if (busy) return
    var start = draftStart
    if (!draftName.trim()) { formError = t("nameError"); return }
    if (!draftQuestion.trim()) { formError = t("questionError"); return }
    if (!Model.validKey(start) || start < "1900-01-01" || start > todayKey) { formError = t("dateError"); return }
    saving = true
    saved = false
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
  function dayStatus() {
    if (!record.value) return t("pending")
    var status = t(habit && Model.successFor(habit.kind, record.value) ? "onTrack" : "setback")
    return record.source === "automatic" ? t("automaticResult").arg(status) : status
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
      if (action === "delete" && success) {
        root.setTab("task")
        root.selectedId = ""
      }
      if (action === "read" && success && root.tab === "settings" && !root.creating && root.habit && root.editId !== root.habit.id)
        root.loadDraft(root.habit)
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
    contentWidth: panel.fittedContentWidth(Math.max(560, Style.space(650)))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight || 340)

    content: Item {
      id: content
      property alias scrollArea: detailScroll
      readonly property bool multipleHabits: root.trackerState.habits.length > 1
      readonly property bool showSidebar: multipleHabits && !root.creating && !root.appSettingsOpen && width >= Math.max(500, Style.space(580))
      anchors.fill: parent
      implicitHeight: Math.max(245, bodyTop.y + Math.max(detailColumn.implicitHeight,
        showSidebar ? Math.min(habitList.implicitHeight, Style.space(220)) : 0))
      focus: true
      Keys.onEscapePressed: {
        if (root.appSettingsOpen) root.setTab(root.returnTab)
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
            : root.habit && !content.multipleHabits ? root.habit.name : root.t("title")
          font.pixelSize: root.headingSize
          font.weight: Font.DemiBold
          elide: Text.ElideRight
        }
        Row {
          id: headerActions
          anchors.right: parent.right
          spacing: Style.space(8)
          Action {
            text: root.t("newHabit")
            iconText: "+"
            visible: !root.creating && !root.appSettingsOpen
            enabled: !root.saving
            onClicked: root.beginEdit(null)
          }
          Action {
            objectName: "appSettingsButton"
            visible: !root.creating && !root.appSettingsOpen
            enabled: root.hostWidget && root.hostWidget.loaded && !root.saving
            text: "⚙"
            Accessible.name: root.t("appSettings")
            tooltipText: root.t("appSettings")
            onClicked: root.setTab("appSettings")
          }
          Action { text: "×"; objectName: "closeHabits"; Accessible.name: root.t("close"); onClicked: root.close() }
        }
      }
      PanelSeparator {
        id: headerRule
        width: parent.width
        y: header.height + Style.space(10)
        foreground: root.foreground
      }
      Item { id: bodyTop; y: headerRule.y + headerRule.height + Math.max(14, Style.space(18)) }

      // The habit list is separate from the detail canvas, never another
      // stack of statistic cards competing with the selected habit.
      Item {
        id: sidebar
        visible: content.showSidebar
        anchors.top: bodyTop.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: Math.max(114, Style.space(132))
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
            spacing: Style.space(5)
            Repeater {
              model: root.trackerState.habits
              Action {
                id: habitButton
                required property var modelData
                width: habitList.width
                height: Math.max(40, root.bodySize + Style.space(20))
                text: ""
                Accessible.name: root.t("habitStatus").arg(modelData.name).arg(root.t(root.todayStatus(modelData)))
                 selected: root.habit && root.habit.id === modelData.id
                bordered: false
                onClicked: root.chooseHabit(modelData.id)
                Column {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.margins: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0
                  Label {
                    width: Math.max(0, parent.width - Style.space(21))
                    text: habitButton.modelData.name
                     font.weight: habitButton.selected ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                  }
                }
                Label {
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
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
          spacing: Math.max(16, Style.space(19))
          Label {
            visible: text !== ""
            width: parent.width
            text: root.hostWidget ? root.hostWidget.storageError : ""
            color: root.urgent
            wrapMode: Text.Wrap
          }

          Column {
            visible: !root.habit && !root.editing && !root.appSettingsOpen && root.hostWidget && root.hostWidget.loaded
            width: parent.width
            spacing: Style.space(10)
            Label { width: parent.width; text: root.t("emptyTitle"); font.pixelSize: root.headingSize; font.weight: Font.DemiBold; wrapMode: Text.Wrap }
            Label { width: parent.width; text: root.t("emptyHint"); color: root.dim; wrapMode: Text.Wrap }
          }
          Label {
            visible: !root.habit && !root.editing && !root.appSettingsOpen && root.hostWidget && !root.hostWidget.loaded && text !== ""
            width: parent.width
            text: root.hostWidget && root.hostWidget.storageError ? "" : root.t("loading")
            color: root.dim
          }

          Column {
            visible: root.habit !== null && !root.creating && !root.appSettingsOpen
            width: parent.width
            spacing: Math.max(13, Style.space(16))
            QQC.ComboBox {
              id: habitPicker
              objectName: "habitPicker"
              visible: content.multipleHabits && !content.showSidebar
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
            Flow {
              width: parent.width
              spacing: Math.max(8, Style.space(10))
              Repeater {
                model: ["task", "analysis", "settings"]
                Action {
                  required property string modelData
                  objectName: modelData + "Tab"
                  text: ""
                  width: tabLabel.implicitWidth + 2 * Math.max(12, Style.space(14))
                  height: Math.max(tabLabel.implicitHeight + Style.space(14), Style.space(40))
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
                  }
                }
              }
            }
            CheckIn { id: checkIn; visible: root.tab === "task"; width: parent.width }

            Column {
              id: analysisCalendar
              visible: root.tab === "analysis"
              objectName: "habitAnalysis"
              width: parent.width
              spacing: Math.max(10, Style.space(12))
              function editDay() {
                root.setTab("task", true)
                Qt.callLater(function() { if (root.tab === "task") checkIn.focusAnswer() })
              }
              Item {
                width: parent.width
                height: Math.max(40, monthControls.implicitHeight)
                Label {
                  anchors.left: parent.left
                  anchors.right: monthControls.left
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.locale.toString(new Date(root.viewYear, root.viewMonth, 1, 12), "MMMM yyyy")
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
                    text: root.t("today")
                    visible: root.selectedDay !== root.todayKey
                    onClicked: { root.inspectDay(root.todayKey); calendar.forceActiveFocus() }
                  }
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
                    root.inspectDay(root.todayKey)
                    event.accepted = true
                  } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (root.record.source !== "before" && root.record.source !== "future") analysisCalendar.editDay()
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
                    readonly property color tone: success ? root.calendarSuccess : failure ? root.calendarSetback : root.foreground
                    objectName: "habitDay-" + modelData.date
                    width: (calendar.width - calendar.spacing * 6) / 7
                    height: Math.max(34, root.bodySize + Style.space(16), Style.space(40))
                    radius: Style.cornerRadius > 0 ? Math.min(Style.cornerRadius, Style.space(5)) : 0
                    opacity: !modelData.inMonth ? 0 : modelData.source === "before" || modelData.source === "future" ? 0.38 : 1
                    color: success || failure ? root.tint(tone, 0.20)
                      : hover.hovered && modelData.selectable ? root.tint(tone, 0.09) : root.tint(tone, 0.035)
                    border.width: modelData.date === root.selectedDay && modelData.selectable ? 2 : 0
                    border.color: calendar.activeFocus ? root.accent : root.foreground
                    Accessible.role: Accessible.Cell
                    Accessible.name: root.t("calendarDay").arg(root.displayDate(modelData.date))
                      .arg(root.t(success ? "onTrack" : failure ? "setback"
                        : modelData.source === "pending" ? "pending" : "outsideTracking"))
                    Accessible.selected: modelData.date === root.selectedDay
                    Accessible.ignored: !modelData.inMonth
                    Label {
                      anchors.centerIn: parent
                      text: root.n(cell.modelData.day)
                      color: cell.success || cell.failure
                        ? root.readable(cell.tone, root.blend(cell.tone, root.surface, 0.20))
                        : root.foreground
                      font.weight: cell.modelData.today ? Font.DemiBold : Font.Normal
                    }
                    Label {
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(6)
                      anchors.verticalCenter: parent.verticalCenter
                      text: cell.failure ? "×" : cell.success ? "✓" : ""
                      color: cell.tone
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
                    TapHandler { enabled: cell.modelData.inMonth && cell.modelData.selectable; onTapped: root.inspectDay(cell.modelData.date) }
                    HoverHandler { id: hover; cursorShape: cell.modelData.inMonth && cell.modelData.selectable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                  }
                }
              }
              Legend { label: root.t("automatic"); tone: root.dim }
              PanelSeparator { foreground: root.foreground }
              Flow {
                width: parent.width
                spacing: Style.space(12)
                Action {
                  id: editAnswer
                  objectName: "editAnswer"
                  text: root.t(root.record.value ? "editAnswer" : "checkIn")
                  Accessible.description: root.t("calendarDay").arg(root.displayDate(root.selectedDay)).arg(root.dayStatus())
                  enabled: root.record.source !== "before" && root.record.source !== "future"
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
              visible: root.tab === "analysis" && root.detailsOpen
              width: parent.width
              spacing: Math.max(16, Style.space(19))
              PanelSeparator { foreground: root.foreground }
              Row {
                id: progressHeading
                width: parent.width
                spacing: Style.space(14)
                Stat { width: (parent.width - parent.spacing * 2) / 3; caption: root.t("currentStreak"); value: root.t("streakValue").arg(root.n(root.stats ? root.stats.currentStreak : 0)) }
                Stat { width: (parent.width - parent.spacing * 2) / 3; caption: root.t("bestStreak"); value: root.t("streakValue").arg(root.n(root.stats ? root.stats.bestStreak : 0)) }
                Stat { width: (parent.width - parent.spacing * 2) / 3; caption: root.t("setbackDays"); value: root.n(root.stats ? root.stats.failureCount : 0); tone: root.stats && root.stats.failureCount ? root.urgent : root.foreground }
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
              label: root.t("appDefaultStart")
              Label {
                width: parent.width
                text: root.t("appDefaultStartHint")
                wrapMode: Text.Wrap
                color: root.dim
              }
              Flow {
                width: parent.width
                spacing: Style.space(8)
                Choice {
                  objectName: "appStartToday"
                  text: root.t("useToday")
                  active: !root.appFixedDate
                  enabled: !root.saving
                  onClicked: root.setAppDateMode(false)
                }
                Choice {
                  objectName: "appStartFixed"
                  text: root.t("useFixedDate")
                  active: root.appFixedDate
                  enabled: !root.saving
                  onClicked: root.setAppDateMode(true)
                }
              }
              StartDatePicker {
                objectName: "appStartDatePicker"
                fieldIdPrefix: "appStartDate"
                visible: root.appFixedDate
                enabled: !root.saving
                width: parent.width
                dateKey: root.appDraftStart || root.todayKey
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
                onPicked: function(dateKey) {
                  root.appDraftStart = dateKey
                  root.appModified = true
                  root.appSaved = false
                }
                onFieldFocused: function(field) { root.revealFocus(field) }
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
                Choice { text: root.t("buildHabit"); active: root.draftKind === "good"; onClicked: { root.draftKind = "good"; root.saved = false } }
                Choice { text: root.t("quitHabit"); active: root.draftKind === "bad"; onClicked: { root.draftKind = "bad"; root.saved = false } }
              }
              Label { width: parent.width; text: root.t(root.draftKind === "bad" ? "badHint" : "goodHint"); wrapMode: Text.Wrap; color: root.dim; font.pixelSize: root.secondarySize }
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
  component CheckIn: Column {
    objectName: "dailyCheckin"
    spacing: Math.max(12, Style.space(15))
    function focusAnswer() {
      var answer = answerButtons.itemAt(root.record.value === "no" ? 1 : 0)
      if (answer && answer.enabled) answer.forceActiveFocus()
    }
    PanelSeparator { foreground: root.foreground }
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
      width: parent.width
      text: root.habit ? root.habit.question : ""
      wrapMode: Text.Wrap
      font.pixelSize: root.displaySize
      font.weight: Font.DemiBold
      lineHeight: 1.12
    }
    Label {
      visible: text !== ""
      width: parent.width
      text: root.habit ? root.habit.message : ""
      color: root.dim
      wrapMode: Text.Wrap
    }
    Row {
      id: answers
      width: Math.min(parent.width, Math.max(290, Style.space(340)))
      spacing: Math.max(12, Style.space(14))
      Repeater {
        id: answerButtons
        model: ["yes", "no"]
        Choice {
          required property string modelData
          objectName: "answer-" + modelData
          width: (answers.width - answers.spacing) / 2
          height: Math.max(46, implicitHeight + Style.space(8), Style.space(51))
          fontSize: root.answerSize
          iconText: active ? "✓" : ""
          text: root.t(modelData)
          active: root.record.value === modelData
          foreground: !active ? root.foreground
            : root.readable(root.habit && Model.successFor(root.habit.kind, modelData) ? root.accent : root.urgent,
              root.blend(root.foreground, root.surface, 0.15))
          Accessible.description: root.t(root.habit && Model.successFor(root.habit.kind, modelData) ? "onTrack" : "setback")
          enabled: !root.busy && root.habit && root.selectedDay >= root.habit.startDate && root.selectedDay <= root.todayKey
          onClicked: root.hostWidget.setAnswer(root.habit.id, root.selectedDay, modelData)
        }
      }
    }
    Flow {
      visible: root.record.value !== ""
      width: parent.width
      spacing: Style.space(12)
      Label {
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
        enabled: !root.busy
        onClicked: root.hostWidget.setAnswer(root.habit.id, root.selectedDay, "")
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
