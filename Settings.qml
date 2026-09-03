import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Overlay for credentials, summoned via bar.shell.summon("io.github.srsergi0.omarchy-opencode-usage", '{"tab":"connection"}')
// Similar to hass Settings.qml but minimal: only workspaceId + authKey
Item {
  id: root
  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  property string tab: "connection"

  property string workspaceDraft: ""
  property string authDraft: ""

  function open(payloadJson) {
    console.log("Settings open called", payloadJson)
    root.opened = true
    try {
      var p = payloadJson ? JSON.parse(payloadJson) : {}
      if (p.tab) root.tab = p.tab
      if (p.workspaceId) root.workspaceDraft = p.workspaceId
      if (p.authKey) root.authDraft = p.authKey
    } catch(e) { console.log("Settings open parse error", e) }
    if(!root.workspaceDraft || !root.authDraft) resetDrafts()
    try {
      var pp = payloadJson ? JSON.parse(payloadJson) : {}
      if (pp.workspaceId) root.workspaceDraft = pp.workspaceId
      if (pp.authKey) root.authDraft = pp.authKey
    } catch(e) {}
    console.log("Settings opened", root.opened, "ws", root.workspaceDraft, "auth len", root.authDraft.length)
    Qt.callLater(function(){ if(wsField) wsField.forceActiveFocus() })
  }
  function close() { root.opened = false }
  function dismiss() {
    root.opened = false
    if(root.shell && typeof root.shell.hide==="function") root.shell.hide((root.manifest && root.manifest.id) || "io.github.srsergi0.omarchy-opencode-usage")
  }
  function resetDrafts() {
    var cfg = null
    if(root.shell && typeof root.shell.configFor==="function") {
      try { cfg = root.shell.configFor("io.github.srsergi0.omarchy-opencode-usage") } catch(e) {}
    }
    if(!cfg && root.shell && root.shell.serviceFor) {
      try {
        var w = root.shell.serviceFor("io.github.srsergi0.omarchy-opencode-usage")
        if(w && w.settings) cfg = w.settings
      } catch(e) {}
    }
    if(cfg){
      root.workspaceDraft = cfg.workspaceId || ""
      root.authDraft = cfg.authKey || ""
    }
  }

  function save() {
    var entry = { id: "io.github.srsergi0.omarchy-opencode-usage" }
    // Preserve other keys like refreshIntervalSec
    var existing = null
    if(root.shell && typeof root.shell.configFor==="function") {
      try { existing = root.shell.configFor("io.github.srsergi0.omarchy-opencode-usage") } catch(e) {}
    }
    if(existing) for(var k in existing) if(k!=="id") entry[k]=existing[k]
    entry["workspaceId"] = wsField.text.trim()
    entry["authKey"] = authField.text.trim()
    entry["connectionStatus"] = "disconnected"
    if(root.shell && typeof root.shell.updateEntryInline==="function") {
      root.shell.updateEntryInline("io.github.srsergi0.omarchy-opencode-usage", entry)
    } else if(root.shell && typeof root.shell.setPluginConfig==="function") {
      root.shell.setPluginConfig("io.github.srsergi0.omarchy-opencode-usage", entry)
    }
    // Also try bar shell
    if(root.shell && root.shell.serviceFor) {
      var w = root.shell.serviceFor("io.github.srsergi0.omarchy-opencode-usage")
      if(w) w.settings = entry
    }
    root.close()
    // Force rescan to apply
    if(root.shell && typeof root.shell.rescanPlugins==="function") root.shell.rescanPlugins()
  }

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "opencode-usage-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      anchors.centerIn: parent
      width: Math.min(Style.space(620), window.width - Style.gapsOut*2)
      height: Math.min(Style.space(420), window.height - Style.gapsOut*2)
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent }

      Item {
        id: header
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: Math.max(title.implicitHeight, closeBtn.implicitHeight)
        Text {
          id: title
          text: "Opencode Usage — Settings"
          color: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.title
          font.weight: Font.Medium
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
        }
        PanelActionButton {
          id: closeBtn
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          iconText: ""
          tooltipText: "Close"
          foreground: Color.menu.text
          fontFamily: Style.font.menuFamily
          onClicked: root.dismiss()
        }
      }

      PanelSeparator { id: rule; anchors { top: header.bottom; left: parent.left; right: parent.right } anchors.topMargin: Style.space(12) }

      Column {
        anchors { top: rule.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
        anchors.topMargin: Style.space(14)
        spacing: Style.spacing.xl

        Column {
          width: parent.width
          spacing: Style.spacing.sm
          Text { text: "Workspace ID"; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
          TextField {
            id: wsField
            width: parent.width
            text: root.workspaceDraft
            placeholderText: "wrk_..."
            onTextChanged: root.workspaceDraft = text
          }
          Text { text: "From https://opencode.ai/workspace/<id>/usage"; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.caption; wrapMode: Text.Wrap; width: parent.width }
        }

        Column {
          width: parent.width
          spacing: Style.spacing.sm
          Text { text: "Auth cookie"; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
          TextField {
            id: authField
            width: parent.width
            text: root.authDraft
            placeholderText: "Fe26.2**..."
            password: true
            onTextChanged: root.authDraft = text
          }
          Text { text: "DevTools → Application → Cookies → auth. Expires ~1 year. Stored in shell.json, no hardcoded defaults. Details SID auto-discovered, no manual input needed."; color: Color.muted; font.family: Style.font.menuFamily; font.pixelSize: Style.font.caption; wrapMode: Text.Wrap; width: parent.width }
        }

        Row {
          spacing: Style.spacing.xl
          anchors.right: parent.right
          Button {
            text: "Cancel"
            bordered: true
            foreground: Color.menu.text
            fontFamily: Style.font.menuFamily
            onClicked: root.dismiss()
          }
          Button {
            text: "Save"
            bordered: true
            foreground: Color.menu.text
            fontFamily: Style.font.menuFamily
            onClicked: root.save()
          }
        }

        Text {
          width: parent.width
          text: "Status shows in bar tooltip and settings Status field (connected/disconnected). No defaults are stored in code."
          color: Color.muted
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }
    }
  }
}
