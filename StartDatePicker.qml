import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Shown only on request; typing a date remains the quickest route to an old date.
BorderSurface {
  id: picker
  required property string initialDate
  required property string maximumDate
  required property var locale
  required property var translations
  property color foreground: Color.popups.text
  property color accent: Color.accent
  property color muted: foreground
  property string fontFamily: Style.font.family
  property int bodySize: Style.font.body
  property int secondarySize: Style.font.bodySmall
  readonly property string minimumDate: "1900-01-01"
  property date viewedMonth: Model.dateFromKey(maximumDate)
  property string cursorDate: maximumDate
  readonly property string monthKey: Model.keyForDate(viewedMonth).slice(0, 7)
  signal picked(string dateKey)
  signal dismissed()

  function inRange(key) { return key >= minimumDate && key <= maximumDate }
  function selectDay(key) {
    if (!inRange(key)) return
    cursorDate = key
    viewedMonth = Model.dateFromKey(key)
  }
  function shiftMonth(amount) {
    var next = new Date(viewedMonth.getFullYear(), viewedMonth.getMonth() + amount, 1, 12)
    var key = Model.keyForDate(next)
    if (inRange(key)) selectDay(key)
  }
  function commit(key) { if (inRange(key)) picked(key) }
  function focusDays() { dates.forceActiveFocus() }
  Component.onCompleted: selectDay(inRange(initialDate) ? initialDate : maximumDate)

  implicitHeight: layout.implicitHeight + 2 * Style.space(12)
  radius: Style.cornerRadius
  color: Style.normalFillFor(foreground, accent)
  borderSpec: Border.controlSpec("normal", foreground, accent)

  Column {
    id: layout
    width: Math.max(0, parent.width - 2 * Style.space(12))
    anchors.centerIn: parent
    spacing: Style.space(8)
    Item {
      width: parent.width
      height: Math.max(monthTitle.implicitHeight, monthNav.implicitHeight)
      Caption {
        id: monthTitle
        anchors.left: parent.left
        anchors.right: monthNav.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: picker.locale.toString(picker.viewedMonth, "MMMM yyyy")
         font.weight: Font.DemiBold
        elide: Text.ElideRight
      }
      Row {
        id: monthNav
        anchors.right: parent.right
        spacing: Style.space(4)
        DateButton {
          text: I18n.rightToLeft ? "›" : "‹"
          Accessible.name: picker.translations.t("previousMonth")
          enabled: picker.monthKey > picker.minimumDate.slice(0, 7)
          onClicked: picker.shiftMonth(-1)
        }
        DateButton {
          text: I18n.rightToLeft ? "‹" : "›"
          Accessible.name: picker.translations.t("nextMonth")
          enabled: picker.monthKey < picker.maximumDate.slice(0, 7)
          onClicked: picker.shiftMonth(1)
        }
      }
    }

    Row {
      width: parent.width
      spacing: dates.spacing
      Repeater {
        model: [1, 2, 3, 4, 5, 6, 7]
        Caption {
          required property int modelData
          width: dates.cellWidth
          text: picker.locale.dayName(modelData, Locale.ShortFormat)
          horizontalAlignment: Text.AlignHCenter
          color: picker.muted
          font.pixelSize: picker.secondarySize
          elide: Text.ElideRight
        }
      }
    }

    Grid {
      id: dates
      readonly property real cellWidth: Math.max(0, (width - spacing * 6) / 7)
      width: parent.width
      columns: 7
      spacing: Style.space(3)
      activeFocusOnTab: true
      Accessible.role: Accessible.Table
      Accessible.name: picker.translations.t("chooseDate")
      Keys.onPressed: function(event) {
        var step = 0
        switch (event.key) {
        case Qt.Key_Left: step = I18n.rightToLeft ? 1 : -1; break
        case Qt.Key_Right: step = I18n.rightToLeft ? -1 : 1; break
        case Qt.Key_Up: step = -7; break
        case Qt.Key_Down: step = 7; break
        case Qt.Key_PageUp: picker.shiftMonth(-1); break
        case Qt.Key_PageDown: picker.shiftMonth(1); break
        case Qt.Key_Home: picker.selectDay(picker.maximumDate); break
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space: picker.commit(picker.cursorDate); break
        default: return
        }
        if (step) picker.selectDay(Model.addDays(picker.cursorDate, step))
        event.accepted = true
      }
      Repeater {
        model: Model.calendarDates(picker.viewedMonth.getFullYear(), picker.viewedMonth.getMonth())
        DateButton {
          required property var modelData
          objectName: "startDate-" + modelData.key
          width: dates.cellWidth
          height: Math.max(34, picker.bodySize + Style.space(14))
          horizontalPadding: 0
          focusable: false // One keyboard stop for the grid instead of 42.
          opacity: !modelData.inMonth ? 0 : enabled ? 1 : 0.35
          enabled: modelData.inMonth && picker.inRange(modelData.key)
          text: I18n.formatNumber(modelData.day)
          active: modelData.key === picker.cursorDate
          hasCursor: active && dates.activeFocus
          Accessible.role: Accessible.Cell
          Accessible.name: picker.locale.toString(Model.dateFromKey(modelData.key), "dd MMM yyyy")
          Accessible.selected: active
          Accessible.ignored: !modelData.inMonth
          onClicked: if (enabled) picker.commit(modelData.key)
        }
      }
    }
    DateButton {
      objectName: "datePickerToday"
      text: picker.translations.t("today")
      bordered: true
      onClicked: picker.commit(picker.maximumDate)
    }
  }

  Keys.onEscapePressed: picker.dismissed()

  component Caption: Text {
    textFormat: Text.PlainText
    color: picker.foreground
    font.family: picker.fontFamily
    font.pixelSize: picker.bodySize
  }
  component DateButton: Button {
    foreground: picker.foreground
    accent: picker.accent
    fontFamily: picker.fontFamily
    focusable: true
    fontSize: picker.bodySize
    horizontalPadding: Style.space(9)
    verticalPadding: Style.space(5)
    opacity: enabled ? 1 : 0.4
  }
}
