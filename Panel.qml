import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI
import qs.Widgets
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

  // Clashia feature toggles
  property bool systemProxyEnabled: !!(cfg.systemProxyEnabled ?? false)
  property bool tunEnabled: false

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
  readonly property int subExpire: cfg.subExpire ?? defaults.subExpire ?? 0
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

  onTrafficAnimProgressChanged: {
    trafficChart.requestPaint();
  }

  onPluginApiChanged: {
    if (pluginApi) {
      Qt.callLater(function() {
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

      // Tab bar
      RowLayout {
        Layout.fillWidth: true
        spacing: 0

        Repeater {
          model: [
            { label: pluginApi?.tr("panel.tabs.nodes") || "Nodes", index: 0 },
            { label: pluginApi?.tr("panel.tabs.logs") || "Logs", index: 1 },
            { label: pluginApi?.tr("panel.tabs.connections") || "Connections", index: 2 }
          ]

          delegate: Item {
            Layout.fillWidth: true
            implicitHeight: tabLabel.implicitHeight + Style.marginM * 2

            required property var modelData

            Rectangle {
              anchors.fill: parent
              color: root.currentTab === modelData.index ? Qt.alpha(Color.mPrimary, 0.1) : "transparent"
              radius: Style.radiusM

              NText {
                id: tabLabel
                anchors.centerIn: parent
                text: modelData.label
                font.pointSize: Style.fontSizeS
                font.weight: root.currentTab === modelData.index ? Font.Bold : Font.Normal
                color: root.currentTab === modelData.index ? Color.mPrimary : Color.mOnSurfaceVariant
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.currentTab = modelData.index
            }

            // Active indicator
            Rectangle {
              anchors.bottom: parent.bottom
              anchors.horizontalCenter: parent.horizontalCenter
              width: parent.width * 0.6
              height: 2
              radius: 1
              color: Color.mPrimary
              visible: root.currentTab === modelData.index
            }
          }
        }
      }

      // Subscription info card
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: subCardColumn.implicitHeight + Style.marginM * 2
        color: Color.mSurfaceVariant
        radius: Style.radiusM

        ColumnLayout {
          id: subCardColumn
          anchors {
            fill: parent
            margins: Style.marginM
          }
          spacing: Style.marginS

          // No subscription URL configured
          NText {
            visible: !root.hasSubscription
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: pluginApi?.tr("panel.subscription.empty") || "Please configure subscription URL in settings"
            font.pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
          }

          // Has subscription but no cached data yet
          NText {
            visible: root.hasSubscription && !root.hasSubData
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: pluginApi?.tr("panel.subscription.noData") || "Subscription data not available"
            font.pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
          }

          // Subscription data row
          RowLayout {
            visible: root.hasSubscription && root.hasSubData
            Layout.fillWidth: true
            spacing: Style.marginS

            NIcon {
              icon: "send"
              pointSize: Style.fontSizeM
              color: Color.mOnSurface
            }

            NText {
              text: root.subscriptionHost
              font.pointSize: Style.fontSizeS
              font.weight: Font.Medium
              color: Color.mOnSurface
              Layout.fillWidth: true
              elide: Text.ElideRight
            }

            NText {
              text: root.formatBytes(root.subUsed) + " / " + root.formatBytes(root.subTotal)
              font.pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
          }

          // Progress bar
          Rectangle {
            visible: root.hasSubscription && root.hasSubData
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            radius: 3
            color: Color.mSurface

            Rectangle {
              width: parent.width * root.subUsedRatio
              height: parent.height
              radius: parent.radius
              color: Color.mPrimary

              Behavior on width {
                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
              }
            }
          }

          // Expire date
          NText {
            visible: root.hasSubscription && root.hasSubData && root.subExpire > 0
            text: (pluginApi?.tr("panel.subscription.expire") || "Expires: ") + root.formatExpireDate(root.subExpire)
            font.pointSize: Style.fontSizeS
            color: Color.mOnSurfaceVariant
          }
        }
      }


      // Feature toggles
      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.marginXS

        NToggle {
          label: pluginApi?.tr("panel.system-proxy") || "System Proxy"
          icon: "world"
          checked: root.systemProxyEnabled
          defaultValue: false
          baseSize: Math.round(Style.baseWidgetSize * 0.6 * Style.uiScaleRatio)
          Component.onCompleted: {
            children[0].labelSize = Style.fontSizeS;
            children[0].children[0].children[0].pointSize = Style.fontSizeS;
            // Debug: dump NToggle child tree
            function dumpTree(item, prefix) {
              Logger.i("Clashia", prefix + item + " color=" + (item.color || "n/a") + " children=" + item.children.length);
              for (var i = 0; i < item.children.length; i++) {
                dumpTree(item.children[i], prefix + "  [" + i + "] ");
              }
            }
            dumpTree(this, "NToggle ");
          }
          onToggled: checked => {
            root.systemProxyEnabled = checked;
            pluginApi.pluginSettings.systemProxyEnabled = checked;
            pluginApi.saveSettings();
            setSystemProxyProcess.running = false;
            setSystemProxyProcess.running = true;
          }
        }

        NToggle {
          label: pluginApi?.tr("panel.tun") || "TUN"
          icon: "shield"
          checked: root.tunEnabled
          defaultValue: false
          baseSize: Math.round(Style.baseWidgetSize * 0.6 * Style.uiScaleRatio)
          Component.onCompleted: {
            children[0].labelSize = Style.fontSizeS;
            children[0].children[0].children[0].pointSize = Style.fontSizeS;
            var sw = children[1];
            if (sw && sw.children[0]) {
              sw.children[0].color = Qt.binding(function() {
                return root.tunEnabled ? Color.mPrimary : Color.mSurfaceVariant;
              });
            }
            if (sw && sw.children[1]) {
              var thumb = sw.children[1];
              thumb.color = Color.mSurfaceVariant;
              thumb.onColorChanged.connect(function() {
                if (thumb.color !== Color.mSurfaceVariant) {
                  thumb.color = Color.mSurfaceVariant;
                }
              });
            }
          }
          onToggled: checked => {
            root.tunEnabled = checked;
            patchTunProcess.running = false;
            patchTunProcess.running = true;
          }
        }
      }

      // Traffic monitor chart
      Item {
        Layout.fillWidth: true
        Layout.preferredHeight: 80

        ColumnLayout {
          anchors {
            fill: parent
          }
          spacing: Style.marginS

          // Chart header
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            NText {
              text: pluginApi?.tr("panel.traffic.title") || "Traffic"
              font.pointSize: Style.fontSizeS
              font.weight: Font.Medium
              color: Color.mOnSurface
            }

            Item { Layout.fillWidth: true }

            // Upload speed indicator
            Rectangle {
              Layout.preferredWidth: 8
              Layout.preferredHeight: 8
              radius: 4
              color: "#4CAF50"
            }

            NText {
              text: "↑ " + root.formatSpeed(root.uploadSpeed)
              font.pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }

            // Download speed indicator
            Rectangle {
              Layout.preferredWidth: 8
              Layout.preferredHeight: 8
              radius: 4
              color: Color.mPrimary
            }

            NText {
              text: "↓ " + root.formatSpeed(root.downloadSpeed)
              font.pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }
          }

          // Canvas line chart
          Canvas {
            id: trafficChart
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 100
            onPaint: {
              var ctx = getContext("2d");
              var w = width;
              var h = height;
              var progress = root.trafficAnimProgress;

              ctx.clearRect(0, 0, w, h);

              var upHist = root.uploadHistory;
              var downHist = root.downloadHistory;
              var maxPoints = root.trafficHistoryMax;
              var peak = root.trafficPeakSpeed;

              if (peak <= 0) peak = 1024;

              // Draw grid lines
              ctx.strokeStyle = Qt.rgba(Color.mOnSurfaceVariant.r, Color.mOnSurfaceVariant.g, Color.mOnSurfaceVariant.b, 0.15);
              ctx.lineWidth = 1;

              for (var gi = 1; gi <= 3; gi++) {
                var gy = h - (h * gi / 4);

                ctx.beginPath();
                ctx.moveTo(0, gy);
                ctx.lineTo(w, gy);
                ctx.stroke();
              }

              // Helper: draw a line series with smooth scroll
              // progress (0→1) shifts points left by one step width,
              // creating a smooth sliding effect between data updates.
              function drawLine(data, color) {
                if (data.length < 2) return;

                var step = w / (maxPoints - 1);
                // Smooth scroll: shift all points left by progress * step
                var scrollOffset = progress * step;
                var baseOffset = (maxPoints - data.length) * step - scrollOffset;

                ctx.strokeStyle = color;
                ctx.lineWidth = 1;
                ctx.lineJoin = "round";
                ctx.lineCap = "round";

                // Clip to chart bounds
                ctx.save();
                ctx.beginPath();
                ctx.rect(0, 0, w, h);
                ctx.clip();

                ctx.beginPath();

                var firstX = 0;
                var lastX = 0;

                for (var i = 0; i < data.length; i++) {
                  var x = baseOffset + i * step;
                  var y = h - (data[i] / peak) * h;

                  if (y < 0) y = 0;

                  if (i === 0) {
                    firstX = x;
                    ctx.moveTo(x, y);
                  } else {
                    ctx.lineTo(x, y);
                    lastX = x;
                  }
                }

                ctx.stroke();

                // Fill area under curve
                ctx.lineTo(lastX, h);
                ctx.lineTo(firstX, h);
                ctx.closePath();

                var parsed = Qt.color(color);
                var gradient = ctx.createLinearGradient(0, 0, 0, h);
                gradient.addColorStop(0, Qt.rgba(parsed.r, parsed.g, parsed.b, 0.2));
                gradient.addColorStop(1, Qt.rgba(parsed.r, parsed.g, parsed.b, 0.02));
                ctx.fillStyle = gradient;
                ctx.fill();

                ctx.restore();
              }

              // Draw download first (behind), then upload
              drawLine(downHist, Color.mPrimary.toString());
              drawLine(upHist, "#4CAF50");

              // Fade edges: erase opacity at left and right with destination-out
              var fadeW = w * 0.08;

              ctx.save();
              ctx.globalCompositeOperation = "destination-out";

              // Left fade
              var leftGrad = ctx.createLinearGradient(0, 0, fadeW, 0);
              leftGrad.addColorStop(0, "rgba(0,0,0,1)");
              leftGrad.addColorStop(1, "rgba(0,0,0,0)");
              ctx.fillStyle = leftGrad;
              ctx.fillRect(0, 0, fadeW, h);

              // Right fade
              var rightGrad = ctx.createLinearGradient(w - fadeW, 0, w, 0);
              rightGrad.addColorStop(0, "rgba(0,0,0,0)");
              rightGrad.addColorStop(1, "rgba(0,0,0,1)");
              ctx.fillStyle = rightGrad;
              ctx.fillRect(w - fadeW, 0, fadeW, h);

              ctx.restore();
            }
          }

          // Y-axis peak label
          NText {
            text: root.formatSpeed(root.trafficPeakSpeed / 1.2)
            font.pointSize: Style.fontSizeS * 0.85
            color: Qt.alpha(Color.mOnSurfaceVariant, 0.6)
          }
        }
      }
    }
  }



  function fetchClashiaConfig() {
    if (!root.apiBaseUrl) return;

    fetchConfigProcess.outputBuffer = "";
    fetchConfigProcess.running = false;
    fetchConfigProcess.running = true;
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

  function formatExpireDate(timestamp) {
    if (timestamp <= 0) return "";

    var d = new Date(timestamp * 1000);
    var year = d.getFullYear();
    var month = String(d.getMonth() + 1).padStart(2, "0");
    var day = String(d.getDate()).padStart(2, "0");
    return year + "-" + month + "-" + day;
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
}
