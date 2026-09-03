import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.srsergi0.omarchy-opencode-usage"
  ipcTarget: "io.github.srsergi0.omarchy-opencode-usage"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  property string workspaceId: hostWidget ? String(hostWidget.workspaceId || "") : ""
  property string authKey: hostWidget ? String(hostWidget.authKey || "") : ""
  property var rolling: hostWidget ? hostWidget.rolling : ({ usage: 0, limit: 0, pct: 0, resetSec: 0 })
  property var weekly: hostWidget ? hostWidget.weekly : ({ usage: 0, limit: 0, pct: 0, resetSec: 0 })
  property var monthly: hostWidget ? hostWidget.monthly : ({ usage: 0, limit: 0, pct: 0, resetSec: 0 })
  property var detailsRolling: hostWidget ? hostWidget.detailsRolling : ({ usage: 0, limit: 0, pct: 0, rows: [] })
  property var detailsWeekly: hostWidget ? hostWidget.detailsWeekly : ({ usage: 0, limit: 0, pct: 0, rows: [] })
  property var detailsMonthly: hostWidget ? hostWidget.detailsMonthly : ({ usage: 0, limit: 0, pct: 0, rows: [] })
  property string error: hostWidget ? String(hostWidget.error || "") : ""

  readonly property bool isConnected: !error && workspaceId && authKey
  property bool showCreds: false
  property bool showDetails: false
  readonly property bool isDark: {
    var bg = Color.background;
    var lum = 0.2126*bg.r + 0.7152*bg.g + 0.0722*bg.b;
    return lum < 0.5;
  }
  readonly property string iconSource: Qt.resolvedUrl("assets/" + (isDark ? "opencode-logo-dark.svg" : "opencode-logo-light.svg"))

  function fmtTokens(n) {
    var v=Number(n); if(!isFinite(v)) return "0";
    if(v>=1e9) return (v/1e9).toFixed(2)+"B";
    if(v>=1e6) return (v/1e6).toFixed(1)+"M";
    if(v>=1e3) return (v/1e3).toFixed(1)+"k";
    return String(Math.round(v));
  }
  function fmtReset(sec) {
    var s=Math.max(0,parseInt(sec,10)||0);
    if(s<60) return "<1m";
    var h=Math.floor(s/3600), m=Math.floor((s%3600)/60);
    if(h>=24){ var d=Math.floor(h/24); h=h%24; if(m>0) return d+"d "+h+"h "+m+"m"; return d+"d "+h+"h"; }
    if(h>0) return m>0 ? h+"h "+m+"m" : h+"h";
    return m+"m";
  }

  function open() { root.controller.show(); }
  function close() { root.controller.hide(); }
  function toggle() { if(root.opened) root.close(); else root.open(); }
  function refresh() { if(hostWidget && hostWidget.refresh) hostWidget.refresh(); }
  function openSettings() {
    console.log("Panel gear clicked, trying to summon settings", root.workspaceId)
    if(root.bar && root.bar.shell && typeof root.bar.shell.summon==="function"){
      var payload = JSON.stringify({ tab: "connection", workspaceId: root.workspaceId, authKey: root.authKey });
      console.log("Panel summon payload", payload)
      close();
      var res = root.bar.shell.summon("io.github.srsergi0.omarchy-opencode-usage", payload);
      console.log("Panel summon result", res)
    } else {
      console.log("Panel: cannot summon settings, shell unavailable", root.bar, root.bar ? root.bar.shell : null);
    }
  }
  function persistSettings(newWorkspace, newAuth) {
    var entry={ id: root.moduleName };
    if(hostWidget && hostWidget.settings){
      for(var k in hostWidget.settings) if(k!=="id") entry[k]=hostWidget.settings[k];
    }
    entry["workspaceId"]=newWorkspace;
    entry["authKey"]=newAuth;
    entry["connectionStatus"]="disconnected";
    if(hostWidget) hostWidget.settings=entry;
    root.settings=entry;
    if(root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline==="function")
      root.bar.shell.updateEntryInline(root.moduleName, entry);
    Qt.callLater(function(){ if(hostWidget) hostWidget.refresh(); });
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(col.implicitHeight, Style.space(560))

    Column {
      id: col
      width: parent.width
      spacing: Style.space(14)
      anchors.margins: Style.space(14)

      // Header with vector icon + gear
      Row {
        width: parent.width
        spacing: Style.space(8)
        Image {
          source: root.iconSource
          width: 28
          height: 28
          fillMode: Image.PreserveAspectFit
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          text: "Opencode Usage"
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          width: parent.width - gearBtn.width - 28 - Style.space(16)
          elide: Text.ElideRight
          anchors.verticalCenter: parent.verticalCenter
        }
        PanelActionButton {
          id: gearBtn
          iconText: ""
          tooltipText: "Settings"
          foreground: root.bar ? root.bar.foreground : Color.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onClicked: root.showCreds = !root.showCreds
        }
      }

      // Status dot
      Rectangle {
        width: parent.width
        height: 1
        color: root.bar ? Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12) : "#333"
      }

      // Usage cards (like hass panel) — toggled by gear in same panel
      Column {
        width: parent.width
        spacing: Style.space(8)
        visible: !root.showCreds
        height: visible ? implicitHeight : 0
        opacity: visible ? 1 : 0

        Text {
          visible: !!error
          text: error
          color: "#ef4444"
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
          wrapMode: Text.Wrap
        }

        Repeater {
          model: [
            { label: "Rolling (5h)", data: rolling, details: detailsRolling },
            { label: "Weekly (7d)", data: weekly, details: detailsWeekly },
            { label: "Monthly (30d)", data: monthly, details: detailsMonthly }
          ]
          delegate: Column {
            required property var modelData
            width: col.width
            spacing: Style.space(4)
            Row {
              width: parent.width
              spacing: Style.space(6)
              Text {
                text: modelData.label
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.3)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.letterSpacing: 1
                font.bold: true
                width: parent.width - pctText.width - resetText.width - Style.space(12)
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: pctText
                text: modelData.data.pct.toFixed(1) + "%"
                color: root.bar ? root.bar.foreground : Color.foreground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                width: 52
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                id: resetText
                text: fmtReset(modelData.data.resetSec)
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
              }
            }
            Text {
              visible: root.showDetails
              text: fmtTokens(modelData.data.usage) + " / " + fmtTokens(modelData.data.limit)
              color: root.bar ? root.bar.foreground : Color.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
              width: parent.width
              elide: Text.ElideRight
            }
            Rectangle {
              width: parent.width
              height: 6
              radius: 3
              color: Qt.rgba(root.bar ? root.bar.foreground.r : 0.5, root.bar ? root.bar.foreground.g : 0.5, root.bar ? root.bar.foreground.b : 0.5, 0.12)
              Rectangle {
                width: parent.width * Math.min(1, modelData.data.pct/100)
                height: parent.height
                radius: parent.radius
                color: Color.accent
              }
            }
            // Más detalles — modelos usados en este periodo (solo cuando showDetails)
            Column {
              visible: root.showDetails
              width: parent.width
              spacing: Style.space(2)
              Text {
                visible: modelData.details && modelData.details.rows && modelData.details.rows.length>0
                text: "Models"
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.letterSpacing: 0.5
                font.bold: false
              }
              Repeater {
                model: modelData.details && modelData.details.rows ? modelData.details.rows : []
                delegate: Row {
                  required property var modelData
                  width: parent.width
                  spacing: Style.space(6)
                  Text {
                    text: modelData.name || modelData.model
                    color: root.bar ? root.bar.foreground : Color.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    width: parent.width * 0.55
                    elide: Text.ElideRight
                  }
                  Text {
                    text: fmtTokens(modelData.quotaCost || modelData.cost)
                    color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.2)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    width: parent.width * 0.22
                    horizontalAlignment: Text.AlignRight
                  }
                  Text {
                    text: (modelData.contributionPercent!=null? modelData.contributionPercent.toFixed(1)+"%":"")
                    color: root.bar ? root.bar.foreground : Color.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    width: parent.width * 0.15
                    horizontalAlignment: Text.AlignRight
                  }
                }
              }
              Text {
                visible: root.showDetails && (!modelData.details || !modelData.details.rows || modelData.details.rows.length===0)
                text: "No model breakdown available"
                color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.6)
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.caption
                font.italic: true
              }
            }
          }
        }

        Row {
          spacing: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
          PanelActionButton {
            iconText: ""
            tooltipText: "Refresh now"
            foreground: root.bar ? root.bar.foreground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: root.refresh()
          }
          PanelActionButton {
            iconText: root.showDetails ? "" : ""
            tooltipText: root.showDetails ? "Hide details" : "More details"
            foreground: root.bar ? root.bar.foreground : Color.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: {
              root.showDetails = !root.showDetails;
              if(root.showDetails && hostWidget && hostWidget.fetchDetails) hostWidget.fetchDetails();
            }
          }
        }
        Text {
          visible: root.showDetails
          text: "Model breakdown for 5h / 7d / 30d"
          color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.5)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          font.italic: true
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }

      // Credentials form — same panel, replaces usage when gear clicked
      Column {
        id: creds
        width: parent.width
        spacing: Style.space(8)
        visible: root.showCreds
        height: visible ? implicitHeight : 0
        opacity: visible ? 1 : 0
          Text {
            text: "Credentials"
            color: root.bar ? root.bar.foreground : Color.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }
          Text {
            text: "Workspace ID and Auth cookie from DevTools → Application → Cookies. Stored in shell.json."
            color: Qt.darker(root.bar ? root.bar.foreground : Color.foreground, 1.4)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
            width: parent.width
          }
          TextField {
            id: wsField
            width: parent.width
            placeholderText: "wrk_..."
            text: root.workspaceId
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            onAccepted: saveBtn.clicked()
          }
          TextField {
            id: authField
            width: parent.width
            placeholderText: "Fe26.2**..."
            text: root.authKey
            echoMode: TextInput.Password
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            onAccepted: saveBtn.clicked()
          }
          Row {
            spacing: Style.space(8)
            anchors.right: parent.right
            Button {
              id: saveBtn
              text: "Save"
              bordered: true
              foreground: Color.menu.text
              fontFamily: Style.font.menuFamily
              onClicked: {
                root.persistSettings(wsField.text.trim(), authField.text.trim());
                root.showCreds=false;
              }
            }
            Button {
              text: "Cancel"
              bordered: true
              foreground: Color.menu.text
              fontFamily: Style.font.menuFamily
              onClicked: { wsField.text=root.workspaceId; authField.text=root.authKey; root.showCreds=false; }
            }
          }
        }
      }
    }
  }
