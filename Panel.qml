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
  property var recentDays: hostWidget ? hostWidget.recentDays : []
  property string lastError: hostWidget ? String(hostWidget.lastError || "") : ""
  property date lastUpdated: hostWidget ? hostWidget.lastUpdated : new Date(0)
  property bool refreshing: hostWidget ? !!hostWidget.refreshing : false
  property double nowMs: hostWidget ? hostWidget.nowMs : Date.now()

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

          Item {
            width: parent.width
            implicitHeight: Math.max(usageHeader.implicitHeight, usageValue.implicitHeight)

            PanelSectionHeader {
              id: usageHeader
              text: "RECENT USAGE"
              foreground: root.foreground
              fontFamily: root.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: usageValue
              visible: recentDays.length > 0
              text: Model.tokenCount(Model.recentTotal(recentDays)) + " TOKENS"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(4)
            visible: recentDays.length > 0

            Repeater {
              model: recentDays

              delegate: Column {
                required property var modelData
                width: (body.width - Style.space(24)) / 7

                Text {
                  width: parent.width
                  text: Model.tokenCount(modelData.tokens)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignHCenter
                }

                Item {
                  width: parent.width
                  height: Style.space(28)

                  Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Style.space(10)
                    height: parent.height * Model.dayTokens(modelData) / Math.max(1, Model.recentPeak(recentDays))
                    color: root.foreground
                  }
                }

                Text {
                  width: parent.width
                  text: Model.dayLabel(modelData.date)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  horizontalAlignment: Text.AlignHCenter
                }
              }
            }
          }
          Text {
            visible: recentDays.length === 0
            width: parent.width
            text: "No recent token history (requires local opencode.db)"
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
        readonly property var w: Model.normalizeWindow(card.account ? card.account[modelData.key] : null, modelData.key, root.nowMs)

        RowLayout {
          width: parent.width

          Text {
            Layout.preferredWidth: Style.space(58)
            text: modelData.label
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Item { Layout.fillWidth: true }

          Text {
            Layout.fillWidth: true
            text: windowRow.w
              ? Model.percent(windowRow.w.percent) + " · $" + (windowRow.w.limitDollars || modelData.dollars)
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
            color: modelData.key === "weekly" && Model.behindPace(windowRow.w, root.nowMs) ? root.urgent : root.foreground

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
