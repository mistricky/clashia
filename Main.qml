import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import "lib/js-yaml.js" as JsYaml
Item {
  id: root

  property var pluginApi: null

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  readonly property string subscriptionUrl: cfg.subscriptionUrl ?? defaults.subscriptionUrl ?? ""
  readonly property bool hasSubscription: subscriptionUrl !== ""
  readonly property string configPath: cfg.configPath ?? defaults.configPath ?? ""
  readonly property string resolvedConfigPath: configPath.replace(/[\n\r]/g, "").trim().replace(/^~/, Quickshell.env("HOME") || "")

  readonly property string headerTmpPath: "/tmp/clashia-sub-headers.txt"
  readonly property string configTmpPath: "/tmp/clashia-sub-config.yaml"

  // Clash config fields (parsed from yaml)
  property string externalController: ""
  property string apiSecret: ""

  readonly property string apiBaseUrl: {
    if (!externalController) return "";
    var addr = externalController;
    if (addr.indexOf("://") === -1) addr = "http://" + addr;
    return addr;
  }

  property string currentProxyName: ""
  property string currentProxyChain: ""
  property string globalRoutingMode: "rule"
  property real trafficUp: 0
  property real trafficDown: 0
  property var trafficUpHistory: []
  property var trafficDownHistory: []
  property real trafficPeak: 1024
  readonly property int trafficHistoryMax: 60

  onPluginApiChanged: {
    if (pluginApi) {
      Qt.callLater(function() {
        if (root.hasSubscription && root.resolvedConfigPath) {
          root.refreshSubscription();
        }

        root.publishRuntimeState();
      });
    }
  }

  onApiBaseUrlChanged: {
    if (apiBaseUrl) {
      root.refreshRuntimeState();
    } else {
      root.currentProxyName = "";
      root.currentProxyChain = "";
      root.globalRoutingMode = "rule";
      root.resetTrafficState();
      root.publishRuntimeState();
    }
  }

  Timer {
    id: runtimePollTimer
    interval: 1000
    repeat: true
    running: !!root.apiBaseUrl
    triggeredOnStart: true
    onTriggered: root.refreshRuntimeState()
  }

  // Parse Clash config yaml for API connection info
  FileView {
    id: configFileView
    path: root.resolvedConfigPath
    watchChanges: true
    onFileChanged: this.reload()

    onLoaded: {
      try {
        var parsed = JsYaml.jsyaml.load(this.text());

        if (parsed) {
          if (parsed["external-controller"] !== undefined)
            root.externalController = String(parsed["external-controller"]);

          if (parsed["secret"] !== undefined)
            root.apiSecret = String(parsed["secret"]);
        }
      } catch (e) {
        Logger.e("Clashia", "Main: Failed to parse config: " + e);
      }
    }

    onLoadFailed: function (error) {
      Logger.e("Clashia", "Main: Failed to read config: " + error);
    }
  }

  Process {
    id: configStateProcess
    property string outputBuffer: ""

    command: {
      if (!root.apiBaseUrl) return ["echo"];
      var args = ["curl", "-s", root.apiBaseUrl + "/configs", "--max-time", "5"];
      if (root.apiSecret) args = args.concat(["-H", "Authorization: Bearer " + root.apiSecret]);
      return args;
    }

    stdout: SplitParser {
      onRead: data => {
        configStateProcess.outputBuffer += data;
      }
    }

    onExited: (code, status) => {
      if (code !== 0) {
        configStateProcess.outputBuffer = "";
        return;
      }

      try {
        var result = JSON.parse(configStateProcess.outputBuffer);
        if (result["mode"] !== undefined)
          root.globalRoutingMode = String(result["mode"]);
        root.publishRuntimeState();
      } catch (e) {
        Logger.w("Clashia", "Main: Failed to parse config state: " + e);
      }

      configStateProcess.outputBuffer = "";
    }
  }

  Process {
    id: proxiesStateProcess
    property string outputBuffer: ""

    command: {
      if (!root.apiBaseUrl) return ["echo"];
      var args = ["curl", "-s", root.apiBaseUrl + "/proxies", "--max-time", "5"];
      if (root.apiSecret) args = args.concat(["-H", "Authorization: Bearer " + root.apiSecret]);
      return args;
    }

    stdout: SplitParser {
      onRead: data => {
        proxiesStateProcess.outputBuffer += data;
      }
    }

    onExited: (code, status) => {
      if (code !== 0) {
        proxiesStateProcess.outputBuffer = "";
        return;
      }

      try {
        var result = JSON.parse(proxiesStateProcess.outputBuffer);
        var proxyState = root.resolveCurrentProxyState(result?.proxies ?? ({}));
        root.currentProxyName = proxyState.name;
        root.currentProxyChain = proxyState.chain;
        root.publishRuntimeState();
      } catch (e) {
        Logger.w("Clashia", "Main: Failed to parse proxies state: " + e);
      }

      proxiesStateProcess.outputBuffer = "";
    }
  }

  Process {
    id: trafficStateProcess
    property string outputBuffer: ""

    command: {
      if (!root.apiBaseUrl) return ["echo"];
      var args = ["curl", "-s", root.apiBaseUrl + "/traffic", "--max-time", "5"];
      if (root.apiSecret) args = args.concat(["-H", "Authorization: Bearer " + root.apiSecret]);
      return args;
    }

    stdout: SplitParser {
      onRead: data => {
        trafficStateProcess.outputBuffer += data;
      }
    }

    onExited: (code, status) => {
      if (code !== 0) {
        trafficStateProcess.outputBuffer = "";
        return;
      }

      try {
        var result = JSON.parse(trafficStateProcess.outputBuffer || "{}");
        root.updateTrafficState(result);
      } catch (e) {
        Logger.w("Clashia", "Main: Failed to parse traffic state: " + e);
      }

      trafficStateProcess.outputBuffer = "";
    }
  }

  // Subscription updater: GET request
  // -D <file>: dump response headers to temp file
  // -o <file>: write response body (yaml config) to configPath
  Process {
    id: subscriptionProcess

    command: {
      if (!root.subscriptionUrl || !root.resolvedConfigPath) return ["echo"];
      return [
        "curl", "-s", "-f",
        "-D", root.headerTmpPath,
        "-o", root.configTmpPath,
        root.subscriptionUrl,
        "-A", "clash.meta",
        "--max-time", "30"
      ];
    }

    onExited: (code, status) => {
      if (code !== 0) {
        Logger.w("Clashia", "Subscription update failed (curl exit " + code + "), keeping previous values");
        return;
      }

      stagedConfigFileView.reload();
      headerFileView.reload();
    }
  }

  FileView {
    id: stagedConfigFileView
    path: root.configTmpPath

    onLoaded: {
      try {
        var parsed = JsYaml.jsyaml.load(this.text());
        if (!root.isValidClashConfig(parsed)) {
          Logger.w("Clashia", "Downloaded subscription payload is not a valid Clash config, keeping previous values");
          return;
        }

        applySubscriptionProcess.running = false;
        applySubscriptionProcess.running = true;
      } catch (e) {
        Logger.w("Clashia", "Downloaded subscription payload is not valid YAML, keeping previous values: " + e);
      }
    }

    onLoadFailed: function(error) {
      Logger.w("Clashia", "Failed to read staged subscription config: " + error);
    }
  }

  Process {
    id: applySubscriptionProcess

    command: {
      if (!root.resolvedConfigPath) return ["echo"];
      return ["cp", root.configTmpPath, root.resolvedConfigPath];
    }

    onExited: (code, status) => {
      if (code !== 0) {
        Logger.w("Clashia", "Failed to apply staged subscription config (cp exit " + code + "), keeping previous values");
        return;
      }

      Logger.i("Clashia", "Subscription config written to " + root.resolvedConfigPath);
    }
  }

  // Read dumped headers after curl finishes
  FileView {
    id: headerFileView
    path: root.headerTmpPath

    onLoaded: {
      var text = this.text();
      var lines = text.split("\n");
      var userinfo = "";

      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();

        if (line.toLowerCase().indexOf("subscription-userinfo:") === 0) {
          userinfo = line.substring(line.indexOf(":") + 1).trim();
          break;
        }
      }

      if (userinfo === "") {
        Logger.w("Clashia", "No Subscription-Userinfo header in response, keeping previous values");
        return;
      }

      root.parseAndSaveSubscriptionInfo(userinfo);
    }

    onLoadFailed: function (error) {
      Logger.w("Clashia", "Failed to read subscription headers: " + error);
    }
  }

  function refreshSubscription() {
    Logger.i("Clashia", "Refreshing subscription from " + root.subscriptionUrl);
    subscriptionProcess.running = false;
    subscriptionProcess.running = true;
  }

  function isValidClashConfig(parsed) {
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
      return false;

    var expectedKeys = [
      "proxies",
      "proxy-groups",
      "rules",
      "mixed-port",
      "port",
      "socks-port",
      "redir-port",
      "tproxy-port",
      "external-controller",
      "secret",
      "mode",
      "dns",
      "tun"
    ];

    for (var i = 0; i < expectedKeys.length; i++) {
      if (parsed[expectedKeys[i]] !== undefined)
        return true;
    }

    return false;
  }

  function parseAndSaveSubscriptionInfo(userinfo) {
    var parts = userinfo.split(";");
    var upload = 0;
    var download = 0;
    var total = 0;
    var expire = 0;

    for (var i = 0; i < parts.length; i++) {
      var kv = parts[i].trim().split("=");

      if (kv.length !== 2) continue;

      var key = kv[0].trim().toLowerCase();
      var val = parseInt(kv[1].trim(), 10);

      if (isNaN(val)) continue;

      if (key === "upload") upload = val;
      else if (key === "download") download = val;
      else if (key === "total") total = val;
      else if (key === "expire") expire = val;
    }

    pluginApi.pluginSettings.subUpload = upload;
    pluginApi.pluginSettings.subDownload = download;
    pluginApi.pluginSettings.subTotal = total;
    pluginApi.pluginSettings.subExpire = expire;
    pluginApi.pluginSettings.subUpdatedAt = Math.floor(Date.now() / 1000);
    pluginApi.saveSettings();

    Logger.i("Clashia", "Subscription info cached: " +
      formatBytes(upload + download) + " / " + formatBytes(total));
  }

  function refreshRuntimeState() {
    if (!root.apiBaseUrl) return;

    configStateProcess.running = false;
    configStateProcess.outputBuffer = "";
    configStateProcess.running = true;

    proxiesStateProcess.running = false;
    proxiesStateProcess.outputBuffer = "";
    proxiesStateProcess.running = true;

    trafficStateProcess.running = false;
    trafficStateProcess.outputBuffer = "";
    trafficStateProcess.running = true;
  }

  function updateTrafficState(result) {
    var up = Number(result?.up ?? result?.upload ?? 0);
    var down = Number(result?.down ?? result?.download ?? 0);

    if (!isFinite(up) || up < 0) up = 0;
    if (!isFinite(down) || down < 0) down = 0;

    root.trafficUp = up;
    root.trafficDown = down;
    root.trafficUpHistory = root.pushTrafficSample(root.trafficUpHistory, up);
    root.trafficDownHistory = root.pushTrafficSample(root.trafficDownHistory, down);

    var observedPeak = Math.max(up, down, 1024);
    if (observedPeak > root.trafficPeak)
      root.trafficPeak = observedPeak * 1.2;
    else
      root.trafficPeak = Math.max(1024, root.trafficPeak * 0.92, observedPeak * 1.2);

    root.publishRuntimeState();
  }

  function pushTrafficSample(history, value) {
    var next = Array.isArray(history) ? history.slice(0) : [];
    next.push(value);
    if (next.length > root.trafficHistoryMax)
      next = next.slice(next.length - root.trafficHistoryMax);
    return next;
  }

  function resetTrafficState() {
    root.trafficUp = 0;
    root.trafficDown = 0;
    root.trafficUpHistory = [];
    root.trafficDownHistory = [];
    root.trafficPeak = 1024;
  }

  function resolveCurrentProxyState(proxies) {
    var groupName = "GLOBAL";
    var globalGroup = proxies["GLOBAL"];

    if (!globalGroup || !globalGroup.now) {
      var names = Object.keys(proxies);

      for (var i = 0; i < names.length; i++) {
        var name = names[i];
        var entry = proxies[name];
        if (!entry || !entry.all || !Array.isArray(entry.all) || entry.all.length === 0) continue;
        if (!root.isSelectableGroup(entry.type)) continue;
        groupName = name;
        globalGroup = entry;
        break;
      }
    }

    var current = globalGroup?.now ?? "";
    var trace = root.resolveProxyTrace(current, proxies);

    return {
      name: trace.finalName || current || "",
      chain: trace.chainText || groupName
    };
  }

  function resolveProxyTrace(name, proxies) {
    var result = {
      finalName: "",
      chainText: ""
    };
    if (!name) return result;

    var seen = ({});
    var chain = [];
    var current = name;

    while (current && !seen[current]) {
      seen[current] = true;
      chain.push(current);

      var entry = proxies[current];
      if (!entry) break;

      var next = entry.now;
      if (!next || next === current) break;
      current = next;
    }

    result.finalName = chain.length > 0 ? chain[chain.length - 1] : name;
    result.chainText = chain.join(" -> ");
    return result;
  }

  function isSelectableGroup(type) {
    var normalized = String(type ?? "").toLowerCase();
    return normalized === "selector" ||
      normalized === "select" ||
      normalized === "urltest" ||
      normalized === "fallback" ||
      normalized === "loadbalance" ||
      normalized === "load-balance" ||
      normalized === "relay";
  }

  function formatBytes(bytes) {
    if (bytes <= 0) return "0 B";

    var units = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    var val = bytes;

    while (val >= 1024 && i < units.length - 1) {
      val /= 1024;
      i++;
    }

    return val.toFixed(i === 0 ? 0 : 1) + " " + units[i];
  }

  function publishRuntimeState() {
    if (!pluginApi) return;
    pluginApi.pluginSettings._currentProxyName = root.currentProxyName;
    pluginApi.pluginSettings._currentProxyChain = root.currentProxyChain;
    pluginApi.pluginSettings._routingMode = root.globalRoutingMode;
    pluginApi.pluginSettings._trafficUp = root.trafficUp;
    pluginApi.pluginSettings._trafficDown = root.trafficDown;
    pluginApi.pluginSettings._trafficUpHist = root.trafficUpHistory;
    pluginApi.pluginSettings._trafficDownHist = root.trafficDownHistory;
    pluginApi.pluginSettings._trafficPeak = root.trafficPeak;
  }

  IpcHandler {
    target: "plugin:clashia"

    function setMessage(message: string) {
      if (pluginApi && message) {
        pluginApi.pluginSettings.message = message;
        pluginApi.saveSettings();
        ToastService.showNotice("Message updated to: " + message);
      }
    }

    function toggle() {
      if (pluginApi) {
        pluginApi.withCurrentScreen(screen => {
          pluginApi.openPanel(screen);
        });
      }
    }
  }
}
