import QtQuick
import Quickshell
import qs.Commons as Commons
import "Plugin" as Habits

ShellRoot {
  id: demo
  property int stage: 0
  property int tickCount: 0
  property int captures: 0
  property var popup
  property var panel

  function require(ok, message) {
    if (!ok) throw new Error(message)
  }
  function find(item, name) {
    if (!item) return null
    if (item.objectName === name) return item
    for (const child of item.children || []) {
      const match = find(child, name)
      if (match) return match
    }
    return null
  }
  function control(name) { return find(panel.loadedContent, name) }
  function click(name) {
    const item = control(name)
    require(item && item.visible && item.enabled, "Control unavailable: " + name)
    item.clicked()
  }
  function capture(item, name) {
    require(item && item.visible, "Capture unavailable: " + name)
    captures++
    require(item.grabToImage(function(result) {
      const ok = result && result.saveToFile(Quickshell.env("HABITS_DEMO_DIR") + "/" + name + ".png")
      if (!ok) {
        console.error("Capture failed: " + name)
        Qt.quit()
      } else captures--
    }), "Cannot capture " + name)
  }
  function theme(light) {
    Commons.Color.background = light ? "#f5f6fb" : "#1e2030"
    Commons.Color.foreground = light ? "#24283c" : "#c8d3f5"
    Commons.Color.accent = light ? "#3d59a1" : "#82aaff"
    Commons.Color.urgent = light ? "#982438" : "#ff98a4"
    Commons.Color.shellValues = ({
      "popups.background": light ? "#f5f6fb" : "#1e2030",
      "popups.text": light ? "#24283c" : "#c8d3f5",
      "controls.selected-color": "accent",
      "controls.selected-fill-alpha": "0.16",
      "controls.normal-fill-alpha": "0.04"
    })
  }

  QtObject {
    id: fakeBar
    property bool vertical: false
    property string position: "top"
    property int barSize: 29
    property string fontFamily: "monospace"
    property color foreground: Commons.Color.foreground
    property color barForeground: foreground
    property color background: "#181a27"
    property color urgent: Commons.Color.urgent
    property bool transparent: false
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    function requestPopout(owner) { activePopout = owner }
    function releasePopout(owner) { if (activePopout === owner) activePopout = null }
    function showTooltip() {}
    function hideTooltip() {}
  }

  PanelWindow {
    anchors { top: true; left: true; right: true }
    implicitHeight: fakeBar.barSize
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    Habits.BarWidget {
      id: widget
      anchors.centerIn: parent
      width: implicitWidth
      height: implicitHeight
      bar: fakeBar
    }
  }

  Timer {
    running: true
    repeat: true
    interval: 350
    onTriggered: {
      try {
        if (++demo.tickCount > 50) throw new Error("Timed out waiting for widget or capture")
        if (demo.captures || !widget.loaded || widget.busy) return
        switch (demo.stage++) {
        case 0:
          demo.theme(false)
          demo.popup = widget.children.find(child => child.beginEdit !== undefined)
          demo.panel = demo.popup.data.find(child => child.objectName === "habitsPopup")
          widget.open()
          break
        case 1:
          demo.require(demo.popup.tab === "today" && demo.control("dailyQuestion").visible, "Today opens the selected check-in")
          demo.require(demo.control("todayTab").selected && demo.control("habitSidebar").visible, "Split layout is visible")
          demo.require(widget.todaySummary.total === 3 && widget.todaySummary.success === 1, "Demo totals are correct")
          demo.require(!demo.control("todayOverview") && !demo.control("archiveTab").visible, "No aggregate view or Archive in Today")
          demo.capture(demo.panel.loadedContent, "today")
          demo.capture(demo.find(widget, "habitsBarButton"), "bar")
          break
        case 2:
          demo.click("focus-habit-hscroll")
          demo.require(demo.control("dailyQuestion").text === "Did you scroll after bedtime?", "Clicking selects the habit's Today")
          demo.click("answer-no")
          break
        case 3:
          demo.require(widget.todaySummary.success === 2, "The real helper saved via stdin")
          demo.click("undoCheckIn")
          break
        case 4:
          demo.require(widget.todaySummary.success === 1, "Undo restored the previous value")
          demo.click("focus-habit-hwalk")
          demo.click("analysisTab")
          demo.click("weekView")
          demo.popup.moveWeek(-1)
          break
        case 5:
          demo.require(demo.popup.weekMode && demo.popup.cells.length === 7 && demo.control("weekSummary").visible, "Week shows seven days")
          demo.capture(demo.panel.loadedContent, "week")
          break
        case 6:
          demo.theme(true)
          demo.click("yearView")
          break
        case 7:
          demo.require(demo.popup.yearMode && demo.popup.yearMonths.length === 12, "Year shows twelve months")
          demo.capture(demo.panel.loadedContent, "year")
          break
        case 8:
          demo.click("appSettingsButton")
          demo.click("archiveTab")
          demo.require(demo.control("archiveOverview").visible, "Archive is under App settings")
          console.info("HABITS_DEMO_PASS")
          Qt.quit()
          break
        }
      } catch (error) {
        console.error(error)
        Qt.quit()
      }
    }
  }
}
