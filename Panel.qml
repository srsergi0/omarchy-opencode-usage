import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.srsergi0.omarchy-opencode-usage"
  ipcTarget: "io.github.srsergi0.omarchy-opencode-usage"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Mirror from hostWidget (collector auto-reads auth.json, no credentials needed)
  property var account: hostWidget ? hostWidget.account : null
  property var recentDays: hostWidget ? hostWidget.recentDays : [] // kept for collector compat, not shown
  property var heatmap: hostWidget ? hostWidget.heatmap : []
  property var projects: hostWidget ? hostWidget.projects : []
  property string lastError: hostWidget ? String(hostWidget.lastError || "") : ""
  property date lastUpdated: hostWidget ? hostWidget.lastUpdated : new Date(0)
  property bool refreshing: hostWidget ? !!hostWidget.refreshing : false
  property double nowMs: hostWidget ? hostWidget.nowMs : Date.now()

  readonly property var heatmapDates: Model.lastNDates(7)
  readonly property int heatmapMaxTokens: Model.heatmapMax(heatmap)
  readonly property var heatmapPeak: Model.heatmapPeak(heatmap)
  readonly property string heatmapToday: heatmapDates.length > 0 ? heatmapDates[heatmapDates.length - 1] : ""
  readonly property int heatmapTodayTotal: Model.heatmapDayTotal(heatmap, heatmapToday)

  readonly property real projectMaxCost: Model.projectMaxCost(projects)
  readonly property int projectTotalTokens: {
    var s=0; for(var i=0;i<projects.length;i++) s+=Number(projects[i].tokens||0); return s
  }
  readonly property real projectTotalCost: {
    var s=0; for(var i=0;i<projects.length;i++) s+=Number(projects[i].cost||0); return s
  }

  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.35)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool alarming: Model.behindPace(
    Model.normalizeWindow(account ? account.weekly : null, "weekly", nowMs), nowMs)

  readonly property bool isDark: {
    var bg = Color.background
    var lum = 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b
    return lum < 0.5
  }
  readonly property string iconSource: Qt.resolvedUrl("assets/" + (isDark ? "opencode-logo-dark.svg" : "opencode-logo-light.svg"))

  function refresh() {
    if (hostWidget && hostWidget.refresh) hostWidget.refresh()
    nowMs = Date.now()
  }

  function promptNewSession() {
    if (hostWidget && typeof hostWidget.promptNewSession === "function") hostWidget.promptNewSession()
    else if (hostWidget && typeof hostWidget.newSessionAt === "function") hostWidget.newSessionAt(Quickshell.env("HOME") || "/home/srsergio")
  }

  onOpenedChanged: if (opened) {
    nowMs = Date.now()
    if (hostWidget && (!hostWidget.lastUpdated || (Date.now() - hostWidget.lastUpdated.getTime()) > hostWidget.refreshIntervalSec * 1000)) refresh()
  }

  Timer {
    interval: 30000
    repeat: true
    running: true
    onTriggered: root.nowMs = hostWidget ? hostWidget.nowMs : Date.now()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: catcher
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(body.implicitHeight, Style.space(650))

    PanelKeyCatcher {
      id: catcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTextKey: function(text) { if (text === "r" || text === "R") root.refresh() }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scroll
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: body.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scroll.contentItem
          property: "interactive"
          value: body.implicitHeight > scroll.height
        }

        Column {
          id: body
          width: scroll.availableWidth
          spacing: Style.space(10)

          Text {
            width: parent.width
            text: "Updated " + (lastUpdated ? Qt.formatTime(lastUpdated, "HH:mm:ss") : "never") + " · " + (refreshing ? "Refreshing…" : "R to refresh")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          PanelHero {
            width: parent.width
            title: "OpenCode Go"
            meta: account ? account.label : "Go"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Image {
                width: Style.font.display
                height: width
                source: root.iconSource
                sourceSize: Qt.size(48, 48)
                layer.enabled: true
                layer.effect: MultiEffect {
                  colorization: 1
                  colorizationColor: root.foreground
                }
              }
            }
          }

          Text {
            visible: lastError !== ""
            width: parent.width
            text: lastError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
          Text {
            visible: lastError === "" && account && account.status !== "ok"
            width: parent.width
            text: account ? account.status : ""
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
          Text {
            visible: !account && refreshing
            width: parent.width
            text: "Loading usage…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            visible: !account && !refreshing && lastError === ""
            width: parent.width
            text: "No API key — run `opencode auth login` (reads ~/.local/share/opencode/auth.json)"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          PanelSectionHeader {
            text: "LIMIT WINDOWS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          AccountCard {
            width: body.width
            account: root.account
          }

          PanelSeparator { width: parent.width; foreground: root.foreground }

          RowLayout {
            width: parent.width
            PanelSectionHeader {
              Layout.fillWidth: true
              text: "PROJECTS — 7D COST (local)"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            PanelActionButton {
              iconText: ""
              tooltipText: "New session — Windows-like file explorer"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.promptNewSession()
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Text {
              width: parent.width
              text: projects.length > 0
                    ? Model.costText(projectTotalCost) + " · " + Model.tokenCount(projectTotalTokens) + " tok · " + projects.length + " projects · " + (function(){var c=0;for(var i=0;i<projects.length;i++)c+=Number(projects[i].sessions||0);return c})() + " sessions"
                    : "No project data (requires opencode.db sessions >7d)"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Repeater {
              model: root.projects
              delegate: Column {
                required property var modelData
                width: body.width
                spacing: Style.space(3)

                RowLayout {
                  width: parent.width
                  spacing: Style.space(6)
                  Text {
                    Layout.fillWidth: true
                    text: Model.shortWorktree(modelData.worktree) + " · " + modelData.sessions + " sess"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  Text {
                    text: Model.costText(modelData.cost) + " · " + Model.tokenCount(modelData.tokens)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    elide: Text.ElideRight
                  }
                  PanelActionButton {
                    iconText: ""
                    tooltipText: "Open " + modelData.worktree
                    foreground: root.dim
                    fontFamily: root.fontFamily
                    onClicked: if (hostWidget && typeof hostWidget.newSessionAt === "function") hostWidget.newSessionAt(modelData.worktree)
                  }
                }

                Text {
                  width: parent.width
                  text: modelData.worktree
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }
            }

            Text {
              visible: projects.length > 0
              width: parent.width
              text: "Local · sqlite session 7d · sorted by cost"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.italic: true
              horizontalAlignment: Text.AlignHCenter
            }
          }

          PanelSeparator { width: parent.width; foreground: root.foreground; visible: heatmap.length > 0 }

          PanelSectionHeader {
            visible: heatmap.length > 0
            text: "HOURLY HEATMAP — 7D × 24H (local)"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            visible: heatmap.length > 0
            width: parent.width
            spacing: Style.space(4)

            Text {
              width: parent.width
              text: heatmapPeak ? "Peak " + heatmapPeak.date + " " + Model.heatmapHourLabel(heatmapPeak.hour) + "h · " + Model.tokenCount(heatmapPeak.tokens) + " · " + heatmapPeak.count + " msgs" : "No hourly data"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              width: parent.width
              text: "Today " + heatmapToday + " · " + Model.tokenCount(heatmapTodayTotal) + " tokens" + (heatmapMaxTokens > 0 ? " · max " + Model.tokenCount(heatmapMaxTokens) + "/h" : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.italic: true
              elide: Text.ElideRight
            }

            // Hour header
            Row {
              width: parent.width
              spacing: 1
              Item { width: Style.space(32); height: Style.space(10) }
              Repeater {
                model: 24
                delegate: Text {
                  required property int index
                  width: (body.width - Style.space(32) - 23) / 24
                  text: index % 3 === 0 ? Model.heatmapHourLabel(index) : ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: 8
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                }
              }
            }

            // 7 rows × 24 cols
            Column {
              width: parent.width
              spacing: 1
              Repeater {
                model: root.heatmapDates
                delegate: Row {
                  required property var modelData
                  readonly property string d: String(modelData)
                  width: parent.width
                  spacing: 1
                  Text {
                    width: Style.space(32)
                    text: Model.dayLabel(d) + " " + d.slice(5)
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: 8
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                  }
                  Repeater {
                    model: 24
                    delegate: Rectangle {
                      required property int index
                      readonly property int hour: index
                      readonly property int tokens: Model.heatmapTokens(root.heatmap, d, hour)
                      readonly property real intensity: root.heatmapMaxTokens > 0 ? tokens / root.heatmapMaxTokens : 0
                      width: (body.width - Style.space(32) - 23) / 24
                      height: Style.space(12)
                      radius: 2
                      color: tokens > 0 ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15 + 0.85 * intensity) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                      border.width: d === root.heatmapToday && hour === new Date().getHours() ? 1 : 0
                      border.color: root.foreground
                    }
                  }
                }
              }
            }

            // Legend + burn rate sparkline for today
            Row {
              width: parent.width
              spacing: Style.space(6)
              anchors.horizontalCenter: parent.horizontalCenter
              Text { text: "less"; color: root.dim; font.family: root.fontFamily; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
              Row {
                spacing: 1
                anchors.verticalCenter: parent.verticalCenter
                Repeater {
                  model: [0.06, 0.3, 0.55, 0.8, 1.0]
                  delegate: Rectangle {
                    required property var modelData
                    width: Style.space(10)
                    height: Style.space(8)
                    radius: 2
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15 + 0.85 * modelData)
                  }
                }
              }
              Text { text: "more"; color: root.dim; font.family: root.fontFamily; font.pixelSize: 8; anchors.verticalCenter: parent.verticalCenter }
            }

            // Burn rate mini bars for today
            Row {
              width: parent.width
              spacing: 1
              Item { width: Style.space(32); height: Style.space(14) }
              Repeater {
                model: 24
                delegate: Item {
                  required property int index
                  readonly property int tokens: Model.heatmapTokens(root.heatmap, root.heatmapToday, index)
                  width: (body.width - Style.space(32) - 23) / 24
                  height: Style.space(14)
                  Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width * 0.8
                    height: parent.height * (root.heatmapMaxTokens > 0 ? tokens / root.heatmapMaxTokens : 0)
                    color: root.foreground
                    opacity: 0.9
                    radius: 1
                  }
                }
              }
            }
            Text {
              width: parent.width
              text: heatmap.length > 0 ? "Local · sqlite opencode.db · 7d · counts per hour (localtime)" : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.italic: true
              horizontalAlignment: Text.AlignHCenter
            }
          }

          Text {
            visible: heatmap.length === 0
            width: parent.width
            text: "No hourly data (requires opencode.db)"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.italic: true
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component AccountCard: Column {
    id: card
    required property var account
    readonly property var windows: [
      { key: "rolling", label: "5h", dollars: 12 },
      { key: "weekly", label: "Weekly", dollars: 30 },
      { key: "monthly", label: "Monthly", dollars: 60 }
    ]
    spacing: Style.space(6)

    RowLayout {
      width: parent.width

      Text {
        Layout.fillWidth: true
        text: card.account ? card.account.label : "Go"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
      }
    }

    Repeater {
      model: card.windows

      delegate: Column {
        id: windowRow
        required property var modelData
        width: card.width
        spacing: Style.space(2)
        readonly property var w: modelData ? Model.normalizeWindow(card.account ? card.account[modelData.key] : null, modelData.key, root.nowMs) : null

        RowLayout {
          width: parent.width

          Text {
            Layout.preferredWidth: Style.space(58)
            text: modelData ? modelData.label : ""
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Item { Layout.fillWidth: true }

          Text {
            Layout.fillWidth: true
            text: windowRow.w
              ? Model.percent(windowRow.w.percent) + " · $" + (windowRow.w.limitDollars || (modelData ? modelData.dollars : 0))
              : (card.account && card.account.status && card.account.status !== "ok" ? card.account.status : "—")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
          }
        }

        Rectangle {
          width: parent.width
          height: Style.space(5)
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.22)

          Rectangle {
            width: parent.width * (windowRow.w ? windowRow.w.percent : 0)
            height: parent.height
            radius: parent.radius
            color: modelData && modelData.key === "weekly" && Model.behindPace(windowRow.w, root.nowMs) ? root.urgent : root.foreground

            Behavior on width { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 60 } }
          }
        }

        Text {
          visible: !!windowRow.w
          width: parent.width
          text: windowRow.w ? "resets " + Model.countdown(windowRow.w.resetMs, root.nowMs) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }

    RowLayout {
      id: paceRow
      width: card.width
      visible: !!paceRow.weekly && paceRow.weekly.resetMs > 0
      readonly property var weekly: Model.normalizeWindow(card.account ? card.account.weekly : null, "weekly", root.nowMs)

      Text {
        Layout.fillWidth: true
        text: paceRow.weekly ? Model.paceText(paceRow.weekly, root.nowMs) : ""
        color: Model.behindPace(paceRow.weekly, root.nowMs) ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        visible: !!paceRow.weekly
        text: paceRow.weekly ? "Expected " + Model.percent(1 - Model.expectedRemaining(paceRow.weekly, root.nowMs)) + " used" : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    PanelSeparator { width: parent.width; foreground: root.foreground }
  }
}
