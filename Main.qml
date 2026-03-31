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

  // Clash config fields (parsed from yaml)
  property string externalController: ""
  property string apiSecret: ""

  readonly property string apiBaseUrl: {
    if (!externalController) return "";
    var addr = externalController;
    if (addr.indexOf("://") === -1) addr = "http://" + addr;
    return addr;
  }

  // Traffic monitoring (persistent across panel open/close)
  property real uploadSpeed: 0
  property real downloadSpeed: 0
  property var uploadHistory: []
  property var downloadHistory: []
  readonly property int trafficHistoryMax: 60
  property real trafficPeakSpeed: 1024

  onPluginApiChanged: {
    if (pluginApi) {
      Qt.callLater(function() {
        if (root.hasSubscription && root.resolvedConfigPath) {
          root.refreshSubscription();
        }
      });
    }
  }

  onApiBaseUrlChanged: {
    if (apiBaseUrl) {
      root.startTrafficStream();
    }
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

  // Stream /traffic for real-time speed data
  Process {
    id: trafficProcess

    command: {
      if (!root.apiBaseUrl) return ["echo"];
      var args = ["curl", "-s", "-N", root.apiBaseUrl + "/traffic"];
      if (root.apiSecret) args = args.concat(["-H", "Authorization: Bearer " + root.apiSecret]);
      return args;
    }

    stdout: SplitParser {
      onRead: data => {
        try {
          var parsed = JSON.parse(data);
          var up = parsed.up || 0;
          var down = parsed.down || 0;

          root.uploadSpeed = up;
          root.downloadSpeed = down;

          var upHist = root.uploadHistory.slice();
          var downHist = root.downloadHistory.slice();

          upHist.push(up);
          downHist.push(down);

          if (upHist.length > root.trafficHistoryMax)
            upHist.shift();

          if (downHist.length > root.trafficHistoryMax)
            downHist.shift();

          // Update peak for Y-axis scaling
          var peak = 1024;

          for (var i = 0; i < upHist.length; i++) {
            if (upHist[i] > peak) peak = upHist[i];
          }

          for (var j = 0; j < downHist.length; j++) {
            if (downHist[j] > peak) peak = downHist[j];
          }

          root.trafficPeakSpeed = peak * 1.2;
          root.uploadHistory = upHist;
          root.downloadHistory = downHist;

          // Share to pluginSettings for Panel to read (no saveSettings — transient)
          if (pluginApi) {
            pluginApi.pluginSettings._trafficUp = up;
            pluginApi.pluginSettings._trafficDown = down;
            pluginApi.pluginSettings._trafficUpHist = upHist;
            pluginApi.pluginSettings._trafficDownHist = downHist;
            pluginApi.pluginSettings._trafficPeak = root.trafficPeakSpeed;
          }
        } catch (e) {
          // Ignore malformed lines
        }
      }
    }

    onExited: (code, status) => {
      // Restart streaming after disconnect (backoff 2s)
      trafficRestartTimer.restart();
    }
  }

  Timer {
    id: trafficRestartTimer
    interval: 2000
    repeat: false
    onTriggered: root.startTrafficStream()
  }

  // Subscription updater: GET request
  // -D <file>: dump response headers to temp file
  // -o <file>: write response body (yaml config) to configPath
  Process {
    id: subscriptionProcess

    command: {
      if (!root.subscriptionUrl || !root.resolvedConfigPath) return ["echo"];
      return [
        "curl", "-s",
        "-D", root.headerTmpPath,
        "-o", root.resolvedConfigPath,
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

      Logger.i("Clashia", "Subscription config written to " + root.resolvedConfigPath);
      // Now read the header file to parse subscription info
      headerFileView.reload();
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
    pluginApi.saveSettings();

    Logger.i("Clashia", "Subscription info cached: " +
      formatBytes(upload + download) + " / " + formatBytes(total));
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

  function startTrafficStream() {
    if (!root.apiBaseUrl) return;

    trafficProcess.running = false;
    trafficProcess.running = true;
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
