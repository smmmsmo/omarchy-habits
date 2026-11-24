import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Flow {
  id: picker
  required property string dateKey
  required property string maximumDate
  property string minimumDate: "1900-01-01"
  property string fieldPrefix: "startDate"
  property bool showToday: true
  required property var locale
  required property var translations
  property color foreground: Commons.Color.popups.text
  property color accent: Commons.Color.accent
  property color surface: Commons.Color.popups.background
  property color muted: foreground
  property string fontFamily: Style.font.family
  property int bodySize: Style.font.body
  property int secondarySize: Style.font.bodySmall

  readonly property var maximum: Model.dateParts(maximumDate)
  readonly property var minimum: Model.dateParts(minimumDate)
  readonly property var current: Model.dateParts(dateKey) || maximum
  readonly property var limits: Model.dateLimits(current.year, current.month, maximum)
  readonly property int firstMonth: current.year === minimum.year ? minimum.month : 1
  readonly property int firstDay: current.year === minimum.year && current.month === minimum.month ? minimum.day : 1
  signal picked(string dateKey)
  signal fieldFocused(Item field)

  function makeOptions(from, to, step, label) {
    var result = []
    for (var v = from; step > 0 ? v <= to : v >= to; v += step)
      result.push({ key: v, label: label(v) })
    return result
  }
  function numberLabel(value) { return picker.locale.toString(value, "f", 0) }
  function selectPart(part, value) {
    var next = Model.changeDatePart(dateKey, maximumDate, part, value)
    if (next < minimumDate) next = minimumDate
    if (next !== dateKey) picked(next)
  }

  spacing: Style.space(8)

  Row {
    id: fields
    readonly property real fieldSpace: Math.max(0, width - 2 * spacing)
    spacing: picker.spacing
    width: Math.min(picker.width, Math.max(255, Style.space(306)))

    DateField {
      objectName: picker.fieldPrefix + "Day"
      title: picker.translations.t("day")
      width: fields.fieldSpace * 0.23
      model: picker.makeOptions(picker.firstDay, picker.limits.day, 1, picker.numberLabel)
      currentIndex: picker.current.day - picker.firstDay
      onActivated: function(index) { popup.close(); picker.selectPart("day", model[index].key) }
    }
    DateField {
      objectName: picker.fieldPrefix + "Month"
      title: picker.translations.t("month")
      width: fields.fieldSpace * 0.48
      model: picker.makeOptions(picker.firstMonth, picker.limits.month, 1,
        function(month) { return picker.locale.standaloneMonthName(month - 1, Locale.LongFormat) })
      currentIndex: picker.current.month - picker.firstMonth
      onActivated: function(index) { popup.close(); picker.selectPart("month", model[index].key) }
    }
    DateField {
      objectName: picker.fieldPrefix + "Year"
      title: picker.translations.t("year")
      width: fields.fieldSpace * 0.29
      model: picker.makeOptions(picker.maximum.year, picker.minimum.year, -1,
        function(year) { return picker.locale.toString(new Date(year, 0, 1, 12), "yyyy") })
      currentIndex: picker.maximum.year - picker.current.year
      onActivated: function(index) { popup.close(); picker.selectPart("year", model[index].key) }
    }
  }

  Item {
    visible: picker.showToday
    width: todayButton.implicitWidth
    height: fields.height
    Button {
      id: todayButton
      objectName: "startDateToday"
      anchors.bottom: parent.bottom
      text: picker.translations.t("today")
      enabled: picker.dateKey !== picker.maximumDate
      height: Math.max(32, picker.bodySize + Style.space(16))
      fontFamily: picker.fontFamily
      fontSize: picker.bodySize
      foreground: picker.foreground
      accent: picker.accent
      focusable: true
      bordered: true
      opacity: enabled ? 1 : 0.5
      onClicked: picker.picked(picker.maximumDate)
    }
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: picker.foreground
    font.family: picker.fontFamily
    font.pixelSize: picker.bodySize
  }

  component DateField: QQC.ComboBox {
    id: field
    required property string title
    textRole: "label"
    implicitHeight: labelHeight + controlHeight
    readonly property real labelHeight: fieldLabel.implicitHeight + Style.space(5)
    readonly property real controlHeight: Math.max(32, picker.bodySize + Style.space(16))
    topPadding: labelHeight
    hoverEnabled: true
    font.family: picker.fontFamily
    font.pixelSize: picker.bodySize
    Accessible.name: title

    Caption {
      id: fieldLabel
      width: field.width
      text: field.title
      color: picker.muted
      font.pixelSize: picker.secondarySize
      elide: Text.ElideRight
    }
    contentItem: Caption {
      text: field.currentText
      leftPadding: Style.space(9)
      rightPadding: Style.space(19)
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }
    indicator: Caption {
      x: field.mirrored ? Style.space(6) : field.width - width - Style.space(7)
      y: field.labelHeight + (field.controlHeight - height) / 2
      text: "⌄"
      color: picker.muted
    }
    background: BorderSurface {
      y: field.labelHeight
      width: field.width
      height: field.controlHeight
      color: Style.normalFillFor(picker.foreground, picker.accent)
      borderSpec: Border.controlSpec(field.activeFocus ? "focus" : field.hovered ? "hover-cursor" : "normal", picker.foreground, picker.accent)
      radius: Style.cornerRadius
    }
    delegate: QQC.ItemDelegate {
      id: option
      required property var modelData
      required property int index
      objectName: field.objectName + "-option-" + modelData.key
      width: ListView.view ? ListView.view.width : field.width
      height: Math.max(30, picker.bodySize + Style.space(12))
      highlighted: field.highlightedIndex === index
      contentItem: Caption {
        text: option.modelData.label
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }
      background: Rectangle { color: option.highlighted ? Style.selectedFillFor(picker.foreground, picker.accent) : "transparent" }
    }
    popup: QQC.Popup {
      id: menu
      y: field.height + Style.space(3)
      width: Math.max(field.width, Style.space(96))
      height: Math.min(Style.space(250), options.contentHeight + 2 * padding)
      padding: Style.space(3)
      margins: Style.space(6)
      contentItem: ListView {
        id: options
        clip: true
        model: menu.visible ? field.delegateModel : null
        currentIndex: field.highlightedIndex
        highlightMoveDuration: 0
        boundsBehavior: Flickable.StopAtBounds
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }
      }
      background: BorderSurface {
        color: picker.surface
        borderSpec: Border.controlSpec("normal", picker.foreground, picker.accent)
        radius: Style.cornerRadius
      }
    }
    onActiveFocusChanged: if (activeFocus) picker.fieldFocused(this)
  }
}
