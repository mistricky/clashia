import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets
import "components"
import "lib/js-yaml.js" as JsYaml

// Panel Component
Item {
  id: root

  // Plugin API (injected by PluginPanelSlot)
  property var pluginApi: null

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  property int currentTab: 0

  readonly property string configPath: cfg.configPath ?? defaults.configPath ?? ""
  readonly property string resolvedConfigPath: configPath.replace(/[\n\r]/g, "").trim().replace(/^~/, Quickshell.env("HOME") || "")
  property string mixedPort: ""
  property string externalController: ""
  property string apiSecret: ""
  property var proxyGroupTestUrls: ({})
  property var proxyProviderTestUrls: ({})

  // Clashia feature toggles
  property bool systemProxyEnabled: !!(cfg.systemProxyEnabled ?? false)
  property bool tunEnabled: false
  property string globalRoutingMode: cfg.globalRoutingMode ?? defaults.globalRoutingMode ?? "rule"

  // Traffic monitoring (polled from shared pluginSettings, written by Main.qml)
  property real uploadSpeed: 0
  property real downloadSpeed: 0
  property var uploadHistory: []
  property var downloadHistory: []
  readonly property int trafficHistoryMax: 60
  property real trafficPeakSpeed: 1024

  // Scroll animation progress: 0 = data just arrived, 1 = fully scrolled to position
  property real trafficAnimProgress: 1

  // Desktop environment detection
  readonly property string xdgDesktop: Quickshell.env("XDG_CURRENT_DESKTOP") || ""
  readonly property bool isKDE: xdgDesktop === "KDE"
  readonly property string kdeSessionVersion: Quickshell.env("KDE_SESSION_VERSION") || "5"
  readonly property string proxyBypass: "localhost,127.0.0.1,::1"
  // Clashia API base URL
  readonly property string apiBaseUrl: {
    if (!externalController) return "";
    var addr = externalController;
    if (addr.indexOf("://") === -1) addr = "http://" + addr;
    return addr;
  }

  // Subscription info (cached in pluginSettings by Main.qml)
  readonly property string subscriptionUrl: cfg.subscriptionUrl ?? defaults.subscriptionUrl ?? ""
  readonly property bool hasSubscription: subscriptionUrl !== ""
  readonly property string subscriptionHost: {
    if (!hasSubscription) return "";
    try {
      var match = subscriptionUrl.match(/^https?:\/\/([^\/?#]+)/);
      return match ? match[1] : subscriptionUrl;
    } catch (e) {
      return subscriptionUrl;
    }
  }

  readonly property real subUpload: cfg.subUpload ?? defaults.subUpload ?? 0
  readonly property real subDownload: cfg.subDownload ?? defaults.subDownload ?? 0
  readonly property real subTotal: cfg.subTotal ?? defaults.subTotal ?? 0
  readonly property bool hasSubData: subTotal > 0

  readonly property real subUsed: subUpload + subDownload
  readonly property real subUsedRatio: subTotal > 0 ? Math.min(1, subUsed / subTotal) : 0
  // SmartPanel
  readonly property var geometryPlaceholder: panelContainer

  property real contentPreferredWidth: 360 * Style.uiScaleRatio
  property real contentPreferredHeight: 720 * Style.uiScaleRatio

  readonly property bool allowAttach: true
  // readonly property bool panelAnchorHorizontalCenter: true
  // readonly property bool panelAnchorVerticalCenter: true
  // readonly property bool panelAnchorTop: false
  // readonly property bool panelAnchorBottom: false
  // readonly property bool panelAnchorLeft: false
  // readonly property bool panelAnchorRight: false

  anchors.fill: parent

  Component.onCompleted: {
    if (pluginApi) {
      root.restoreCurrentTab();
      Logger.i("Clashia", "Panel initialized");
      root.syncTrafficData();
    }
  }

  // Poll traffic data from shared pluginSettings (written by Main.qml)
  Timer {
    id: trafficPollTimer
    interval: 1000
    repeat: true
    running: true
    onTriggered: root.syncTrafficData()
  }

  // Linear animation driving smooth scroll between data points
  NumberAnimation on trafficAnimProgress {
    id: trafficScrollAnim
    from: 0
    to: 1
    duration: 1000
    running: false
  }

  onPluginApiChanged: {
    if (pluginApi) {
      Qt.callLater(function() {
        root.restoreCurrentTab();
        // Re-apply system proxy on startup if it was enabled
        if (root.systemProxyEnabled) {
          setSystemProxyProcess.running = false;
          setSystemProxyProcess.running = true;
        }
      });
    }
  }
  FileView {
    id: configFileView
    path: root.resolvedConfigPath
    watchChanges: true
    onFileChanged: this.reload()

    onLoaded: {
      try {
        var parsed = JsYaml.jsyaml.load(this.text());

        if (parsed) {
          if (parsed["mixed-port"] !== undefined)
            root.mixedPort = String(parsed["mixed-port"]);

          if (parsed["external-controller"] !== undefined)
            root.externalController = String(parsed["external-controller"]);

          if (parsed["secret"] !== undefined)
            root.apiSecret = String(parsed["secret"]);

          // Read TUN initial state from config
          if (parsed["tun"] && parsed["tun"]["enable"] !== undefined)
            root.tunEnabled = !!parsed["tun"]["enable"];

          root.proxyGroupTestUrls = root.extractProxyGroupTestUrls(parsed);
          root.proxyProviderTestUrls = root.extractProxyProviderTestUrls(parsed);
        }

        // Fetch live state from Clashia API
        root.fetchClashiaConfig();
      } catch (e) {
        Logger.e("Clashia", "Failed to parse config: " + e);
      }
    }

    onLoadFailed: function (error) {
      Logger.e("Clashia", "Failed to read config: " + error);
    }
  }



  // Clashia API: fetch current config state
  Process {
    id: fetchConfigProcess
    property string outputBuffer: ""

    command: {
      if (!root.apiBaseUrl) return ["echo"];
      var args = ["curl", "-s", root.apiBaseUrl + "/configs", "--max-time", "5"];
      if (root.apiSecret) args = args.concat(["-H", "Authorization: Bearer " + root.apiSecret]);
      return args;
    }

    stdout: SplitParser {
      onRead: data => {
        fetchConfigProcess.outputBuffer += data;
      }
    }

    onExited: (code, status) => {
      if (code !== 0) {
        Logger.w("Clashia", "Failed to fetch Clashia config via API (" + root.apiBaseUrl + "), is Clash running?");
        return;
      }

      try {
        var result = JSON.parse(fetchConfigProcess.outputBuffer);
        if (result["tun"] && result["tun"]["enable"] !== undefined)
          root.tunEnabled = !!result["tun"]["enable"];
        if (result["mode"] !== undefined) {
          root.globalRoutingMode = String(result["mode"]);
          if (pluginApi) {
            pluginApi.pluginSettings.globalRoutingMode = root.globalRoutingMode;
            pluginApi.saveSettings();
          }
        }
        // system-proxy is not in clashia config, leave as-is
      } catch (e) {
        Logger.e("Clashia", "Failed to parse Clashia API response: " + e);
      }

      fetchConfigProcess.outputBuffer = "";
    }
  }

  // Clashia API: patch TUN setting
  Process {
    id: patchTunProcess

    command: {
      if (!root.apiBaseUrl) return ["echo"];
      var payload = JSON.stringify({ "tun": { "enable": root.tunEnabled } });
      var args = ["curl", "-s", "-X", "PATCH", root.apiBaseUrl + "/configs", "-d", payload,
                  "-H", "Content-Type: application/json", "--max-time", "5"];
      if (root.apiSecret) args = args.concat(["-H", "Authorization: Bearer " + root.apiSecret]);
      return args;
    }

    onExited: (code, status) => {
      if (code !== 0)
        Logger.e("Clashia", "Failed to patch TUN setting");
    }
  }

  Process {
    id: patchRoutingModeProcess

    command: {
      if (!root.apiBaseUrl) return ["echo"];
      var payload = JSON.stringify({ "mode": root.globalRoutingMode });
      var args = ["curl", "-s", "-X", "PATCH", root.apiBaseUrl + "/configs", "-d", payload,
                  "-H", "Content-Type: application/json", "--max-time", "5"];
      if (root.apiSecret) args = args.concat(["-H", "Authorization: Bearer " + root.apiSecret]);
      return args;
    }

    onExited: (code, status) => {
      if (code !== 0) {
        Logger.e("Clashia", "Failed to patch routing mode");
        root.fetchClashiaConfig();
      } else {
        Logger.i("Clashia", "Routing mode set to " + root.globalRoutingMode);
      }
    }
  }

  // System proxy: gsettings + KDE kwriteconfig
  Process {
    id: setSystemProxyProcess

    command: {
      var host = "127.0.0.1";
      var port = root.mixedPort || "7890";
      var enable = root.systemProxyEnabled;
      var isKDE = root.isKDE;
      var kdeVer = root.kdeSessionVersion;

      var script = "";

      if (enable) {
        // Set gsettings (GNOME + KDE both use this)
        var mode = "'manual'";
        script += "gsettings set org.gnome.system.proxy mode " + mode + "; ";
        script += "gsettings set org.gnome.system.proxy.http host '" + host + "'; ";
        script += "gsettings set org.gnome.system.proxy.http port " + port + "; ";
        script += "gsettings set org.gnome.system.proxy.https host '" + host + "'; ";
        script += "gsettings set org.gnome.system.proxy.https port " + port + "; ";
        script += "gsettings set org.gnome.system.proxy.socks host '" + host + "'; ";
        script += "gsettings set org.gnome.system.proxy.socks port " + port + "; ";

        // Build bypass list for gsettings: ['localhost', '127.0.0.1', '::1']
        var bypassParts = root.proxyBypass.split(",");
        var gsBypass = "[";

        for (var i = 0; i < bypassParts.length; i++) {
          if (i > 0) gsBypass += ", ";
          gsBypass += "'" + bypassParts[i].trim() + "'";
        }

        gsBypass += "]";
        script += "gsettings set org.gnome.system.proxy ignore-hosts \"" + gsBypass + "\"; ";

        // KDE: also write kioslaverc via kwriteconfig
        if (isKDE) {
          var kwrite = kdeVer === "6" ? "kwriteconfig6" : "kwriteconfig5";
          var kioConfig = Quickshell.env("HOME") + "/.config/kioslaverc";
          script += kwrite + " --file '" + kioConfig + "' --group 'Proxy Settings' --key ProxyType 1; ";
          script += kwrite + " --file '" + kioConfig + "' --group 'Proxy Settings' --key httpProxy 'http://" + host + " " + port + "'; ";
          script += kwrite + " --file '" + kioConfig + "' --group 'Proxy Settings' --key httpsProxy 'http://" + host + " " + port + "'; ";
          script += kwrite + " --file '" + kioConfig + "' --group 'Proxy Settings' --key socksProxy 'socks://" + host + " " + port + "'; ";
          script += kwrite + " --file '" + kioConfig + "' --group 'Proxy Settings' --key NoProxyFor '" + root.proxyBypass + "'; ";
        }
      } else {
        // Disable proxy
        script += "gsettings set org.gnome.system.proxy mode 'none'; ";

        if (isKDE) {
          var kwriteOff = kdeVer === "6" ? "kwriteconfig6" : "kwriteconfig5";
          var kioConfigOff = Quickshell.env("HOME") + "/.config/kioslaverc";
          script += kwriteOff + " --file '" + kioConfigOff + "' --group 'Proxy Settings' --key ProxyType 0; ";
        }
      }

      return ["bash", "-c", script];
    }

    onExited: (code, status) => {
      if (code !== 0)
        Logger.e("Clashia", "Failed to set system proxy (exit code " + code + ")");
      else
        Logger.i("Clashia", "System proxy " + (root.systemProxyEnabled ? "enabled" : "disabled"));
    }
  }
  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors {
        left: parent.left
        right: parent.right
        top: parent.top
        margins: Style.marginL
      }
      spacing: Style.marginL

      // Header: Logo + Info
      RowLayout {
        id: header
        Layout.fillWidth: true
        spacing: Style.marginM

        // Logo
        Image {
          Layout.preferredWidth: 48
          Layout.preferredHeight: 48
          source: pluginApi ? pluginApi.pluginDir + (Settings.data.colorSchemes.darkMode ? "/logo_dark.svg" : "/logo.svg") : ""
          fillMode: Image.PreserveAspectFit
          sourceSize.width: 48
          sourceSize.height: 48
          smooth: true
          antialiasing: true
        }

        // Info
        ColumnLayout {
          spacing: Style.marginS

          NText {
            text: "Clashia"
            font.pointSize: Style.fontSizeM * Style.uiScaleRatio
            font.weight: Font.Bold
            color: Color.mOnSurface
          }

          RowLayout {
            spacing: Style.marginS

            // Breathing status dot
            Rectangle {
              Layout.preferredWidth: 8
              Layout.preferredHeight: 8
              radius: 4
              color: "#4CAF50"

              SequentialAnimation on opacity {
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 0.3; duration: 1500; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.3; to: 1.0; duration: 1500; easing.type: Easing.InOutSine }
              }
            }

            NText {
              text: root.mixedPort !== "" ? "127.0.0.1:" + root.mixedPort : "failed to read mixed-port from " + root.configPath
              font.pointSize: Style.fontSizeS
              color: Qt.alpha(Color.mOnSurface, 0.5)
            }
          }
        }
      }

      SubscriptionSummary {
        hasSubscription: root.hasSubscription
        hasSubData: root.hasSubData
        emptyText: pluginApi?.tr("panel.subscription.empty") || "Please configure subscription URL in settings"
        noDataText: pluginApi?.tr("panel.subscription.noData") || "Subscription data not available"
        subscriptionName: root.subscriptionHost
        usageText: root.formatBytes(root.subUsed) + " / " + root.formatBytes(root.subTotal)
        progressValue: root.subUsedRatio
      }
 
 
      FeatureToggles {
        systemProxyEnabled: root.systemProxyEnabled
        tunEnabled: root.tunEnabled
        systemProxyLabel: pluginApi?.tr("panel.system-proxy") || "System Proxy"
        tunLabel: pluginApi?.tr("panel.tun") || "TUN"
        globalRoutingLabel: pluginApi?.tr("panel.global-routing") || "Global routing"
        globalRoutingMode: root.globalRoutingMode
        globalRoutingModel: [
          { key: "rule", label: pluginApi?.tr("panel.routing-modes.rule") || "Rule" },
          { key: "global", label: pluginApi?.tr("panel.routing-modes.global") || "Global" },
          { key: "direct", label: pluginApi?.tr("panel.routing-modes.direct") || "Direct" }
        ]
        onSystemProxyToggled: checked => {
          root.systemProxyEnabled = checked;
          pluginApi.pluginSettings.systemProxyEnabled = checked;
          pluginApi.saveSettings();
          setSystemProxyProcess.running = false;
          setSystemProxyProcess.running = true;
        }
        onTunToggled: checked => {
          root.tunEnabled = checked;
          patchTunProcess.running = false;
          patchTunProcess.running = true;
        }
        onGlobalRoutingSelected: key => {
          root.globalRoutingMode = key;
          pluginApi.pluginSettings.globalRoutingMode = key;
          pluginApi.saveSettings();
          patchRoutingModeProcess.running = false;
          patchRoutingModeProcess.running = true;
        }
      }

      TrafficMonitor {
        uploadSpeed: root.uploadSpeed
        downloadSpeed: root.downloadSpeed
        uploadHistory: root.uploadHistory
        downloadHistory: root.downloadHistory
        historyMax: root.trafficHistoryMax
        peakSpeed: root.trafficPeakSpeed
        animProgress: root.trafficAnimProgress
        peakLabelText: root.formatSpeed(root.trafficPeakSpeed / 1.2)
        uploadSpeedText: "↑ " + root.formatSpeed(root.uploadSpeed)
        downloadSpeedText: "↓ " + root.formatSpeed(root.downloadSpeed)
      }

      Tabs {
        Layout.fillWidth: true
        currentIndex: root.currentTab
        model: [
          { label: pluginApi?.tr("panel.tabs.nodes") || "Nodes" },
          { label: pluginApi?.tr("panel.tabs.logs") || "Logs" },
          { label: pluginApi?.tr("panel.tabs.connections") || "Connections" }
        ]
        onActivated: index => {
          var nextIndex = root.normalizeTabIndex(index);
          root.currentTab = nextIndex;
          if (pluginApi) {
            pluginApi.pluginSettings.currentTab = nextIndex;
            pluginApi.saveSettings();
          }
        }
      }

      LogsPanel {
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? implicitHeight : 0
        visible: root.currentTab === 1
        apiBaseUrl: root.apiBaseUrl
        apiSecret: root.apiSecret
      }

      ConnectionsPanel {
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? implicitHeight : 0
        visible: root.currentTab === 2
        apiBaseUrl: root.apiBaseUrl
        apiSecret: root.apiSecret
      }

      NodePanel {
        Layout.fillWidth: true
        Layout.preferredHeight: visible ? implicitHeight : 0
        visible: root.currentTab === 0
        pluginApi: root.pluginApi
        apiBaseUrl: root.apiBaseUrl
        apiSecret: root.apiSecret
        routingMode: root.globalRoutingMode
        proxyGroupTestUrls: root.proxyGroupTestUrls
        proxyProviderTestUrls: root.proxyProviderTestUrls
      }
    }
  }



  function fetchClashiaConfig() {
    if (!root.apiBaseUrl) return;

    fetchConfigProcess.outputBuffer = "";
    fetchConfigProcess.running = false;
    fetchConfigProcess.running = true;
  }

  function restoreCurrentTab() {
    var saved = pluginApi?.pluginSettings?.currentTab;
    var fallback = defaults.currentTab ?? 0;
    root.currentTab = root.normalizeTabIndex(saved ?? fallback);
  }

  function normalizeTabIndex(value) {
    var idx = Number(value);
    if (!isFinite(idx)) return 0;
    idx = Math.floor(idx);
    return Math.max(0, Math.min(2, idx));
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

  function formatSpeed(bytesPerSec) {
    if (bytesPerSec <= 0) return "0 B/s";

    var units = ["B/s", "KB/s", "MB/s", "GB/s"];
    var i = 0;
    var val = bytesPerSec;

    while (val >= 1024 && i < units.length - 1) {
      val /= 1024;
      i++;
    }

    return val.toFixed(i === 0 ? 0 : 1) + " " + units[i];
  }

  function syncTrafficData() {
    if (!pluginApi) return;

    var s = pluginApi.pluginSettings;
    root.uploadSpeed = s._trafficUp ?? 0;
    root.downloadSpeed = s._trafficDown ?? 0;
    root.uploadHistory = s._trafficUpHist ?? [];
    root.downloadHistory = s._trafficDownHist ?? [];
    root.trafficPeakSpeed = s._trafficPeak ?? 1024;

    // Restart scroll animation from 0 → 1 over 1s
    trafficScrollAnim.stop();
    root.trafficAnimProgress = 0;
    trafficScrollAnim.start();
  }

  function extractProxyGroupTestUrls(parsed) {
    var result = ({});
    var groups = parsed?.["proxy-groups"];
    if (!Array.isArray(groups))
      return result;

    for (var i = 0; i < groups.length; i++) {
      var group = groups[i];
      var name = String(group?.name ?? "").trim();
      var url = String(group?.url ?? "").trim();
      if (name && url)
        result[name] = url;
    }

    return result;
  }

  function extractProxyProviderTestUrls(parsed) {
    var result = ({});
    var providers = parsed?.["proxy-providers"];
    if (!providers || typeof providers !== "object")
      return result;

    var names = Object.keys(providers);
    for (var i = 0; i < names.length; i++) {
      var name = names[i];
      var provider = providers[name];
      var url = String(provider?.["health-check"]?.url ?? "").trim();
      if (name && url)
        result[name] = url;
    }

    return result;
  }
}
