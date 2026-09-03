import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.srsergi0.omarchy-opencode-usage"

  readonly property string workspaceId: String(setting("workspaceId", ""))
  readonly property string authKey: String(setting("authKey", ""))
  readonly property int refreshIntervalSec: Math.max(15, parseInt(setting("refreshIntervalSec", 15), 10) || 15)
  readonly property int hybridFallbackSec: Math.max(60, parseInt(setting("hybridFallbackSec", 300), 10) || 300)
  readonly property string _serverId: String(setting("serverId", ""))
  property bool _discovering: false

  property var rolling: ({ usage: 0, limit: 0, pct: 0, resetSec: 0 })
  property var weekly: ({ usage: 0, limit: 0, pct: 0, resetSec: 0 })
  property var monthly: ({ usage: 0, limit: 0, pct: 0, resetSec: 0 })
  property var detailsRolling: ({ usage: 0, limit: 0, pct: 0, rows: [] })
  property var detailsWeekly: ({ usage: 0, limit: 0, pct: 0, rows: [] })
  property var detailsMonthly: ({ usage: 0, limit: 0, pct: 0, rows: [] })
  property string error: ""
  property bool loading: false
  property bool detailsLoading: false
  property bool _detailsDiscovering: false
  readonly property string _detailsServerId: String(setting("detailsServerId", ""))

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

  readonly property bool isDark: {
    var bg = Color.background;
    var lum = 0.2126*bg.r + 0.7152*bg.g + 0.0722*bg.b;
    return lum < 0.5;
  }
  readonly property string iconSource: Qt.resolvedUrl("assets/" + (isDark ? "opencode-logo-dark.svg" : "opencode-logo-light.svg"))
  readonly property bool isConnected: !error && workspaceId && authKey
  readonly property string displayLabel: {
    if(!workspaceId || !authKey) return "";
    if(error) return "";
    if(loading && rolling.pct===0 && weekly.pct===0) return "…";
    return rolling.pct.toFixed(1)+"%";
  }
  readonly property string tooltipText2: {
    var conn = isConnected ? "connected" : "disconnected";
    if(error) return "State: "+conn+" — Error: "+error+"\nConfigure Workspace ID and Auth cookie in plugin settings panel.";
    if(!isConnected) return "State: disconnected — Configure in panel gear → Credentials";
    var r = "State: "+conn+"\n";
    r += "Rolling(5h): "+rolling.pct+"% reset in "+fmtReset(rolling.resetSec)+"\n";
    r += "Weekly: "+weekly.pct+"% reset in "+fmtReset(weekly.resetSec)+"\n";
    r += "Monthly: "+monthly.pct+"% reset in "+fmtReset(monthly.resetSec);
    return r;
  }

  // Panel integration like hass — click shows Panel.qml with usage + gear to Settings overlay
  function injectPanel(){
    var t=panelLoader.item;
    if(!t) return;
    if("bar" in t) t.bar=root.bar;
    if("settings" in t) t.settings=root.settings;
    if("anchorItem" in t) t.anchorItem=button;
    if("hostWidget" in t) t.hostWidget=root;
  }
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened===true : false
  function open(){ if(panelLoader.item) panelLoader.item.open(); }
  function close(){ if(panelLoader.item) panelLoader.item.close(); }
  function togglePanel(){ console.log("BarWidget togglePanel clicked", panelLoader.item, panelLoader.item ? panelLoader.item.opened : "no item"); if(panelLoader.item) panelLoader.item.toggle(); else console.log("no panel item"); }
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing===true : false
  function closeForPopoutSwitch(){ if(panelLoader.item) panelLoader.item.closeForPopoutSwitch(); }
  function setConnectionStatus(connected){
    var status = connected ? "connected" : "disconnected";
    if(String(setting("connectionStatus",""))===status) return;
    var entry={ id: root.moduleName };
    for(var k in root.settings) if(k!=="id") entry[k]=root.settings[k];
    entry["connectionStatus"]=status;
    root.settings=entry;
    if(root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline==="function")
      root.bar.shell.updateEntryInline(root.moduleName, entry);
  }

  // Híbrido incremental: fast _server 15s + HTML repara vars, backoff evita loop infinito
  property int _tick: 0
  property int _fastFails: 0
  property int _htmlFails: 0
  property int _fastInterval: refreshIntervalSec
  function refresh() { refreshFast(); }
  function discoverServerId() {
    if(_discovering) return;
    if(!workspaceId || !authKey){ error="Missing Workspace ID or Auth in settings"; setConnectionStatus(false); return; }
    _discovering = true;
    loading = true;
    function esc(s){ return String(s).replace(/'/g,"'\\''"); }
    var pluginDir = Quickshell.env("HOME")+"/.config/omarchy/plugins/io.github.srsergi0.omarchy-opencode-usage";
    var devDir = Quickshell.env("HOME")+"/Work/project/omarchy-plugins/opencode-usage-unofficial";
    var script = pluginDir+"/discover_server_id.py";
    var devScript = devDir+"/discover_server_id.py";
    var cmd = "PY=\""+script+"\"; if [[ ! -f \"$PY\" ]]; then PY=\""+devScript+"\"; fi; "
      + "WRK='"+esc(workspaceId)+"'; AUTH='"+esc(authKey)+"'; "
      + "python3 \"$PY\" \"$WRK\" \"$AUTH\"";
    discoverProc.command = ["bash","-c",cmd];
    discoverProc.running = true;
  }
  function refreshFast() {
    if(loading) return;
    if(!workspaceId || !authKey){ error="Missing Workspace ID or Auth in settings"; setConnectionStatus(false); loading=false; return; }
    if(!_serverId){ discoverServerId(); return; }
    loading=true;
    function esc(s){ return String(s).replace(/'/g,"'\\''"); }
    var pluginDir = Quickshell.env("HOME")+"/.config/omarchy/plugins/io.github.srsergi0.omarchy-opencode-usage";
    var parsePy = pluginDir+"/parse.py";
    var devParse = Quickshell.env("HOME")+"/Work/project/omarchy-plugins/opencode-usage-unofficial/parse.py";
    var cmd = "set -uo pipefail; WRK='"+esc(workspaceId)+"'; SID='"+esc(_serverId)+"'; AUTH='"+esc(authKey)+"'; "
      + "if [[ -z \"$AUTH\" && -n \"${AUTH_TOKEN:-}\" ]]; then AUTH=\"$AUTH_TOKEN\"; fi; "
      + "if [[ -z \"$WRK\" ]]; then echo '{\"error\":\"Missing workspaceId in settings\"}'; exit 0; fi; "
      + "if [[ -z \"$AUTH\" ]]; then echo '{\"error\":\"Missing authKey in settings\"}'; exit 0; fi; "
      + "PARSE=\""+parsePy+"\"; if [[ ! -f \"$PARSE\" ]]; then PARSE=\""+devParse+"\"; fi; "
      + "curl --silent --url \"https://opencode.ai/_server?id=$SID&args=%7B%22t%22%3A%7B%22t%22%3A9%2C%22i%22%3A0%2C%22l%22%3A1%2C%22a%22%3A%5B%7B%22t%22%3A1%2C%22s%22%3A%22$WRK%22%7D%5D%2C%22o%22%3A0%7D%2C%22f%22%3A31%2C%22m%22%3A%5B%5D%7D\" "
      + "-H 'accept: */*' -b \"auth=$AUTH\" -H \"referer: https://opencode.ai/workspace/$WRK/usage\" -H \"x-server-id: $SID\" -H \"x-server-instance: server-fn:9\" "
      + "| python3 \"$PARSE\"; ec=$?; if [[ $ec -ne 0 ]]; then echo '{\"error\":\"_server failed\"}'; fi";
    fastProc.command = ["bash","-c",cmd];
    fastProc.running=true;
  }
  function refreshHtml() {
    if(loading) return;
    if(!workspaceId || !authKey){ error="Missing Workspace ID or Auth in settings"; setConnectionStatus(false); loading=false; return; }
    loading=true;
    function esc(s){ return String(s).replace(/'/g,"'\\''"); }
    var pluginDir = Quickshell.env("HOME")+"/.config/omarchy/plugins/io.github.srsergi0.omarchy-opencode-usage";
    var parsePy = pluginDir+"/parse_html.py";
    var devParse = Quickshell.env("HOME")+"/Work/project/omarchy-plugins/opencode-usage-unofficial/parse_html.py";
    var cmd = "set -uo pipefail; WRK='"+esc(workspaceId)+"'; AUTH='"+esc(authKey)+"'; "
      + "if [[ -z \"$AUTH\" && -n \"${AUTH_TOKEN:-}\" ]]; then AUTH=\"$AUTH_TOKEN\"; fi; "
      + "if [[ -z \"$WRK\" ]]; then echo '{\"error\":\"Missing workspaceId in settings\"}'; exit 0; fi; "
      + "if [[ -z \"$AUTH\" ]]; then echo '{\"error\":\"Missing authKey in settings\"}'; exit 0; fi; "
      + "PARSE=\""+parsePy+"\"; if [[ ! -f \"$PARSE\" ]]; then PARSE=\""+devParse+"\"; fi; "
      + "curl --silent \"https://opencode.ai/workspace/$WRK/usage\" -b \"auth=$AUTH\" -H 'accept: text/html' "
      + "| python3 \"$PARSE\"";
    htmlProc.command = ["bash","-c",cmd];
    htmlProc.running=true;
  }

  function discoverDetailsServerId(){
    if(_detailsDiscovering) return;
    if(!workspaceId || !authKey){ error="Missing Workspace ID or Auth in settings"; return; }
    _detailsDiscovering=true;
    detailsLoading=true;
    function esc(s){ return String(s).replace(/'/g,"'\\''"); }
    var pluginDir = Quickshell.env("HOME")+"/.config/omarchy/plugins/io.github.srsergi0.omarchy-opencode-usage";
    var devDir = Quickshell.env("HOME")+"/Work/project/omarchy-plugins/opencode-usage-unofficial";
    var script = pluginDir+"/discover_details_server_id.py";
    var devScript = devDir+"/discover_details_server_id.py";
    var cmd = "PY=\""+script+"\"; if [[ ! -f \"$PY\" ]]; then PY=\""+devScript+"\"; fi; "
      + "WRK='"+esc(workspaceId)+"'; AUTH='"+esc(authKey)+"'; "
      + "python3 \"$PY\" \"$WRK\" \"$AUTH\"";
    detailsDiscoverProc.command = ["bash","-c",cmd];
    detailsDiscoverProc.running=true;
  }
  function fetchDetails(){
    if(detailsLoading) return;
    if(!workspaceId || !authKey){ error="Missing Workspace ID or Auth in settings"; return; }
    if(!_detailsServerId){ discoverDetailsServerId(); return; }
    detailsLoading=true;
    function esc(s){ return String(s).replace(/'/g,"'\\''"); }
    var pluginDir = Quickshell.env("HOME")+"/.config/omarchy/plugins/io.github.srsergi0.omarchy-opencode-usage";
    var devDir = Quickshell.env("HOME")+"/Work/project/omarchy-plugins/opencode-usage-unofficial";
    var parsePy = pluginDir+"/parse_details.py";
    var devParse = devDir+"/parse_details.py";
    var cmd = "set -uo pipefail; WRK='"+esc(workspaceId)+"'; SID='"+esc(_detailsServerId)+"'; AUTH='"+esc(authKey)+"'; "
      + "if [[ -z \"$AUTH\" && -n \"${AUTH_TOKEN:-}\" ]]; then AUTH=\"$AUTH_TOKEN\"; fi; "
      + "PARSE=\""+parsePy+"\"; if [[ ! -f \"$PARSE\" ]]; then PARSE=\""+devParse+"\"; fi; "
      + "fetch_one(){ local period=\"$1\"; local json=\"{\\\"t\\\":{\\\"t\\\":9,\\\"i\\\":0,\\\"l\\\":2,\\\"a\\\":[{\\\"t\\\":1,\\\"s\\\":\\\"$WRK\\\"},{\\\"t\\\":1,\\\"s\\\":\\\"$period\\\"}],\\\"o\\\":0},\\\"f\\\":31,\\\"m\\\":[]}\"; local args=$(python3 -c \"import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))\" \"$json\"); curl --silent \"https://opencode.ai/_server?id=$SID&args=$args\" -H 'accept: */*' -b \"auth=$AUTH\" -H \"referer: https://opencode.ai/workspace/$WRK/go\" -H \"x-server-id: $SID\" -H \"x-server-instance: server-fn:1\" | python3 \"$PARSE\" \"$period\"; }; "
      + "R=$(fetch_one rolling); W=$(fetch_one weekly); M=$(fetch_one monthly); "
      + "echo \"{\\\"rolling\\\":$R,\\\"weekly\\\":$W,\\\"monthly\\\":$M}\"";
    detailProc.command = ["bash","-c",cmd];
    detailProc.running=true;
  }
  function handleDetailsDiscover(text){
    _detailsDiscovering=false;
    var t=String(text||"").trim();
    try{
      var j=JSON.parse(t);
      if(j.serverId){
        var entry={ id: root.moduleName };
        for(var k in root.settings) if(k!=="id") entry[k]=root.settings[k];
        entry["detailsServerId"]=j.serverId;
        root.settings=entry;
        if(root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline==="function")
          root.bar.shell.updateEntryInline(root.moduleName, entry);
        fetchDetails();
      } else {
        detailsLoading=false;
        console.log("details discover failed", j.error);
      }
    }catch(e){
      detailsLoading=false;
      console.log("details discover JSON error", e, t.slice(0,300));
    }
  }
  function handleDetails(text){
    detailsLoading=false;
    var t=String(text||"").trim();
    if(!t) return;
    try{
      var j=JSON.parse(t);
      if(j.rolling) detailsRolling=j.rolling;
      if(j.weekly) detailsWeekly=j.weekly;
      if(j.monthly) detailsMonthly=j.monthly;
    }catch(e){
      console.log("handleDetails JSON error", e, t.slice(0,300));
    }
  }
  function handleDiscover(text){
    _discovering=false; loading=false;
    var t=String(text||"").trim();
    try{
      var j=JSON.parse(t);
      if(j.serverId){
        var entry={ id: root.moduleName };
        for(var k in root.settings) if(k!=="id") entry[k]=root.settings[k];
        entry["serverId"]=j.serverId;
        root.settings=entry;
        if(root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline==="function")
          root.bar.shell.updateEntryInline(root.moduleName, entry);
        // retry fast with new serverId
        refreshFast();
      } else {
        error=j.error || "discover failed";
        setConnectionStatus(false);
        refreshHtml();
      }
    }catch(e){
      error="discover JSON "+e;
      refreshHtml();
    }
  }
  function handleOutput(text, isHtml){
    loading=false;
    var t=String(text||"").trim();
    if(!t){
      setConnectionStatus(false);
      if(!isHtml){ _fastFails++; var backoff=Math.min(3600, refreshIntervalSec*Math.pow(2,_fastFails)); fastTimer.interval=backoff*1000; if(_fastFails<=3) refreshHtml(); else error="fast empty, backoff "+fmtReset(backoff); }
      else { _htmlFails++; var backoffH=Math.min(3600, hybridFallbackSec*Math.pow(2,_htmlFails)); htmlTimer.interval=backoffH*1000; error="empty HTML, backoff "+fmtReset(backoffH); }
      return;
    }
    try{
      var j=JSON.parse(t);
      if(j.error){
        if(!isHtml){
          _fastFails++; var backoff=Math.min(3600, refreshIntervalSec*Math.pow(2,_fastFails)); fastTimer.interval=backoff*1000;
          if(_fastFails===2) discoverServerId();
          if(_fastFails<=3){ htmlProc.running=false; refreshHtml(); } else error=j.error+" (fast backoff "+fmtReset(backoff)+", HTML repara vars)";
          return;
        } else {
          _htmlFails++; var backoffH=Math.min(3600, hybridFallbackSec*Math.pow(2,_htmlFails)); htmlTimer.interval=backoffH*1000;
          error=j.error+" (html backoff "+fmtReset(backoffH)+")";
          return;
        }
      }
      if(j.rolling){
        rolling=j.rolling; weekly=j.weekly; monthly=j.monthly; error="";
        setConnectionStatus(true);
        // éxito resetea backoff y repara vars
        if(isHtml){ _htmlFails=0; htmlTimer.interval=hybridFallbackSec*1000; }
        else { _fastFails=0; fastTimer.interval=refreshIntervalSec*1000; _htmlFails=0; htmlTimer.interval=hybridFallbackSec*1000; }
      } else { setConnectionStatus(false); error="parse empty "+t.slice(0,200); }
    }catch(e){
      if(!isHtml){
        _fastFails++; var backoff=Math.min(3600, refreshIntervalSec*Math.pow(2,_fastFails)); fastTimer.interval=backoff*1000;
        if(_fastFails<=3) refreshHtml(); else error="JSON fast "+e+" (backoff "+fmtReset(backoff)+")";
      } else {
        _htmlFails++; var backoffH=Math.min(3600, hybridFallbackSec*Math.pow(2,_htmlFails)); htmlTimer.interval=backoffH*1000;
        error="JSON HTML "+e+" (backoff "+fmtReset(backoffH)+")";
      }
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  IpcHandler{ target:"io.github.srsergi0.omarchy-opencode-usage"; function refresh(): void { root.broadcast("refresh") } function refreshFast(): void { root.broadcast("refreshFast") } function refreshHtml(): void { root.broadcast("refreshHtml") } function fetchDetails(): void { root.broadcast("fetchDetails") } function open(): void { root.open() } function close(): void { root.close() } function toggle(): void { root.togglePanel() } }
  Process{
    id: fastProc
    running:false
    stdout: StdioCollector{ waitForEnd:true; onStreamFinished: root.handleOutput(text, false) }
    onExited: if(root.loading && !htmlProc.running) root.loading=false
  }
  Process{
    id: htmlProc
    running:false
    stdout: StdioCollector{ waitForEnd:true; onStreamFinished: root.handleOutput(text, true) }
    onExited: if(root.loading) root.loading=false
  }
  Process{
    id: discoverProc
    running:false
    stdout: StdioCollector{ waitForEnd:true; onStreamFinished: root.handleDiscover(text) }
    onExited: if(root._discovering) root._discovering=false
  }
  Process{
    id: detailProc
    running:false
    stdout: StdioCollector{ waitForEnd:true; onStreamFinished: root.handleDetails(text) }
    onExited: if(root.detailsLoading) root.detailsLoading=false
  }
  Process{
    id: detailsDiscoverProc
    running:false
    stdout: StdioCollector{ waitForEnd:true; onStreamFinished: root.handleDetailsDiscover(text) }
    onExited: if(root._detailsDiscovering) root._detailsDiscovering=false
  }
  Timer{ id: fastTimer; interval: root.refreshIntervalSec*1000; running:true; repeat:true; triggeredOnStart:true; onTriggered: root.refreshFast() }
  Timer{ id: htmlTimer; interval: root.hybridFallbackSec*1000; running:true; repeat:true; triggeredOnStart:false; onTriggered: root.refreshHtml() }
  WidgetButton{
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    keepSpace: true
    hasVisualContent: true
    tooltipText: root.tooltipText2
    // Fix overlap: width based on contentRow, not on empty label
    fixedWidth: contentRow.implicitWidth + scaledHorizontalMargin*2 + 4
    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.space(6)
      Image {
        visible: !root.isConnected
        source: root.iconSource
        width: 18
        height: 20
        fillMode: Image.PreserveAspectFit
        opacity: 0.45
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        visible: root.displayLabel !== "" && root.displayLabel !== "…"
        text: root.displayLabel
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        visible: root.displayLabel === "…"
        text: "…"
        color: root.bar ? root.bar.foreground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        anchors.verticalCenter: parent.verticalCenter
      }
    }
    onPressed: function(b){
      console.log("BarWidget WidgetButton pressed", b, root.isConnected ? "connected" : "disconnected");
      if(b===Qt.RightButton){ if(root.bar) root.bar.run("xdg-open 'https://opencode.ai/workspace/"+root.workspaceId+"/usage'"); }
      else if(b===Qt.MiddleButton) root.refresh();
      else { console.log("BarWidget button left click -> togglePanel"); root.togglePanel(); }
    }
  }
  Component.onCompleted: refresh()
}
