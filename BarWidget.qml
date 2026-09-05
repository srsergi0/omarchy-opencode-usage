import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.srsergi0.omarchy-opencode-usage"

  readonly property int refreshIntervalSec: {
    var v = parseInt(String(setting("refreshIntervalSec", 300)), 10)
    if (!isFinite(v)) v = 300
    return Math.max(60, Math.min(v, 3600))
  }

  // Data from collector — auto-reads ~/.local/share/opencode/auth.json (opencode-go key)
  property var account: null
  property var recentDays: []
  property var heatmap: []
  property var projects: []
  property bool refreshing: false
  property string lastError: ""
  property date lastUpdated: new Date(0)
  property double nowMs: Date.now()
  readonly property string collectorScript: decodeURIComponent(String(Qt.resolvedUrl("collector.sh")).replace(/^file:\/\//, ""))

  readonly property bool isDark: {
    var bg = Color.background
    var lum = 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b
    return lum < 0.5
  }
  readonly property string iconSource: Qt.resolvedUrl("assets/" + (isDark ? "opencode-logo-dark.svg" : "opencode-logo-light.svg"))

  readonly property var weeklyWindow: Model.normalizeWindow(account ? account.weekly : null, "weekly", nowMs)
  readonly property bool alarming: Model.behindPace(weeklyWindow, nowMs)

  readonly property string displayLabel: {
    if (!account || !weeklyWindow) return "—"
    if (lastError && lastError !== "" && (!account || account.status !== "ok")) return "—"
    return Model.percent(weeklyWindow.percent)
  }

  readonly property string tooltipText2: {
    if (lastError && lastError !== "" && (!account || account.status !== "ok")) return "OpenCode Go — " + lastError + "\nKey from ~/.local/share/opencode/auth.json (opencode-go)"
    if (!account) return "OpenCode Go — loading…"
    var rw = Model.normalizeWindow(account.rolling, "rolling", nowMs)
    var ww = Model.normalizeWindow(account.weekly, "weekly", nowMs)
    var mw = Model.normalizeWindow(account.monthly, "monthly", nowMs)
    var r = "OpenCode Go · " + (account.status === "ok" ? "connected" : account.status) + "\n"
    r += "Rolling 5h: " + Model.percent(rw ? rw.percent : 0) + " resets " + Model.countdown(rw ? rw.resetMs : 0, nowMs) + "\n"
    r += "Weekly: " + Model.percent(ww ? ww.percent : 0) + " resets " + Model.countdown(ww ? ww.resetMs : 0, nowMs) + "\n"
    r += "Monthly: " + Model.percent(mw ? mw.percent : 0) + " resets " + Model.countdown(mw ? mw.resetMs : 0, nowMs)
    return r
  }

  // Panel integration
  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("settings" in t) t.settings = root.settings
    if ("anchorItem" in t) t.anchorItem = button
    if ("hostWidget" in t) t.hostWidget = root
  }
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  function refresh() {
    if (refreshing || collector.running) return
    refreshing = true
    lastError = ""
    collector.command = ["bash", root.collectorScript]
    collector.running = true
  }

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  IpcHandler {
    target: "io.github.srsergi0.omarchy-opencode-usage"
    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  Process {
    id: collector
    command: []
    stdout: StdioCollector { id: collectorOutput; waitForEnd: true; onStreamFinished: root.output = text }
    stderr: StdioCollector { id: collectorStderr; waitForEnd: true }
    property string output: ""
    onExited: function(exitCode) {
      root.refreshing = false
      if (exitCode !== 0) {
        var detail = String(collectorStderr.text || "").replace(/\s+/g, " ").trim()
        root.lastError = detail ? detail.slice(0, 180) : ("Collector failed (exit " + exitCode + ")")
        return
      }
      var parsed = Model.parseCollector(collectorOutput.text || collector.output)
      if (!parsed.ok) { root.lastError = parsed.error; return }
      root.account = parsed.data.account
      root.recentDays = parsed.data.recentDays
      root.heatmap = parsed.data.heatmap
      root.projects = parsed.data.projects
      root.lastError = parsed.data.error
      root.lastUpdated = new Date()
      nowMs = Date.now()
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.nowMs = Date.now()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    keepSpace: true
    hasVisualContent: true
    tooltipText: root.tooltipText2
    fixedWidth: contentRow.implicitWidth + scaledHorizontalMargin * 2 + 4
    active: root.alarming
    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      Image {
        source: root.iconSource
        width: 18
        height: 18
        fillMode: Image.PreserveAspectFit
        anchors.verticalCenter: parent.verticalCenter
        opacity: root.account && root.account.status === "ok" ? 1.0 : 0.45
      }
      Text {
        text: root.displayLabel
        color: root.alarming ? (root.bar ? root.bar.urgent : Color.urgent) : (root.bar ? root.bar.foreground : Color.foreground)
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        anchors.verticalCenter: parent.verticalCenter
        visible: root.displayLabel !== ""
      }
    }
    onPressed: function(b) {
      if (b === Qt.RightButton || b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }

  Component.onCompleted: refresh()
}
