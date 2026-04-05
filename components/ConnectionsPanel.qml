import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var pluginApi: null
  property string apiBaseUrl: ""
  property string apiSecret: ""
  property bool loading: false
  property bool requestStarted: false
  property bool hasFetchedOnce: false
  property string errorText: ""
  property var connectionItems: []
  property real uploadTotal: 0
  property real downloadTotal: 0
  property int activeConnectionCount: 0
  property string memoryText: ""
  property var processIconCache: ({})
  property var pendingIconLookups: []
  property string currentLookupProcess: ""

  readonly property bool hasApi: apiBaseUrl !== ""
  readonly property var proxyTraceByName: pluginApi?.pluginSettings?._proxyTraceByName || ({})
  readonly property string requestUrl: hasApi ? apiBaseUrl + "/connections" : ""
  readonly property color panelColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.05 : 0.035)
  readonly property color borderColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.08 : 0.06)
  readonly property color itemColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.04 : 0.025)
  readonly property color itemBorderColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.08 : 0.05)

  Layout.fillWidth: true
  implicitHeight: 420 * Style.uiScaleRatio

  onApiBaseUrlChanged: {
    if (apiBaseUrl)
      Qt.callLater(root.refresh);
    else
      root.resetState();
  }

  onVisibleChanged: {
    if (visible)
      root.refresh();
  }

  Component.onCompleted: {
    if (visible && apiBaseUrl)
      Qt.callLater(root.refresh);
  }

  Timer {
    id: pollTimer

    interval: 2000
    repeat: true
    running: root.visible && root.hasApi
    onTriggered: root.refresh()
  }

  Rectangle {
    anchors.fill: parent
    color: root.panelColor
    radius: Style.radiusM
    border.color: root.borderColor
    border.width: 1
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginM
    spacing: 0

    Loader {
      Layout.fillWidth: true
      Layout.fillHeight: true
      active: true
      sourceComponent: {
        if (!root.hasApi) return noApiState;
        if (root.requestStarted && !root.hasFetchedOnce) return loadingState;
        if (root.loading && !root.hasFetchedOnce) return loadingState;
        if (root.errorText !== "") return errorState;
        if (root.connectionItems.length === 0) return emptyState;
        return listState;
      }
    }
  }

  Component {
    id: noApiState

    Item {
      implicitHeight: 180 * Style.uiScaleRatio

      NText {
        anchors.centerIn: parent
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "Mihomo API is unavailable. Check external-controller and secret."
        font.pointSize: Style.fontSizeS
        color: Qt.alpha(Color.mOnSurface, 0.72)
      }
    }
  }

  Component {
    id: loadingState

    Item {
      implicitHeight: 180 * Style.uiScaleRatio

      NText {
        anchors.centerIn: parent
        text: "Loading connections..."
        font.pointSize: Style.fontSizeS
        color: Qt.alpha(Color.mOnSurface, 0.72)
      }
    }
  }

  Component {
    id: errorState

    Item {
      implicitHeight: 180 * Style.uiScaleRatio

      ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width, 280 * Style.uiScaleRatio)
        spacing: Style.marginS

        NText {
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          text: root.errorText
          font.pointSize: Style.fontSizeS
          color: Qt.alpha(Color.mOnSurface, 0.72)
        }

        NButton {
          Layout.alignment: Qt.AlignHCenter
          text: "Retry"
          icon: "refresh-cw"
          onClicked: root.refresh()
        }
      }
    }
  }

  Component {
    id: emptyState

    Item {
      implicitHeight: 180 * Style.uiScaleRatio

      NText {
        anchors.centerIn: parent
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "No active Mihomo connections."
        font.pointSize: Style.fontSizeS
        color: Qt.alpha(Color.mOnSurface, 0.72)
      }
    }
  }

  Component {
    id: listState

    ListView {
      id: connectionsList

      clip: true
      boundsBehavior: Flickable.StopAtBounds
      spacing: Style.marginXS
      model: root.connectionItems
      reuseItems: true
      cacheBuffer: 256 * Style.uiScaleRatio

      delegate: Rectangle {
        required property var modelData

        readonly property var itemData: modelData

        width: connectionsList.width
        implicitHeight: 58 * Style.uiScaleRatio
        radius: Style.radiusM
        color: root.itemColor
        border.color: root.itemBorderColor
        border.width: 1

        ColumnLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.marginM
          anchors.rightMargin: Style.marginM
          spacing: 0

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            Item {
              Layout.alignment: Qt.AlignVCenter
              Layout.preferredWidth: 18 * Style.uiScaleRatio
              Layout.preferredHeight: 18 * Style.uiScaleRatio

              Image {
                anchors.fill: parent
                visible: itemData?.clientIconKind === "file"
                source: visible ? (itemData?.clientIcon ?? "") : ""
                sourceSize.width: Math.round(18 * Style.uiScaleRatio)
                sourceSize.height: Math.round(18 * Style.uiScaleRatio)
                fillMode: Image.PreserveAspectFit
                smooth: true
                antialiasing: true
              }

              NIcon {
                anchors.centerIn: parent
                visible: itemData?.clientIconKind !== "file"
                icon: itemData?.clientIcon ?? "world"
                pointSize: Math.round(Style.fontSizeS)
                color: Qt.alpha(Color.mOnSurface, 0.82)
              }
            }

            NText {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              text: itemData?.clientName ?? ""
              elide: Text.ElideRight
              font.pointSize: Style.fontSizeS
              font.weight: Font.DemiBold
              color: Color.mOnSurface
            }

            NText {
              Layout.alignment: Qt.AlignVCenter
              text: itemData?.statusText ?? "Active"
              font.pointSize: Style.fontSizeS * 0.92
              font.weight: Font.Medium
              color: root.statusColor(itemData?.statusText ?? "Active")
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.marginM

            NText {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              text: itemData?.policyText ?? "Direct"
              elide: Text.ElideRight
              font.pointSize: Style.fontSizeS * 0.78
              color: Qt.alpha(Color.mOnSurface, 0.72)
            }

            NText {
              Layout.alignment: Qt.AlignVCenter
              text: itemData?.timeText ?? ""
              font.pointSize: Style.fontSizeS * 0.78
              color: Qt.alpha(Color.mOnSurface, 0.6)
            }
          }
        }
      }
    }
  }

  Process {
    id: connectionsProcess

    property string outputBuffer: ""

    command: {
      if (!root.requestUrl) return ["echo"];
      var args = ["curl", "-s", root.requestUrl, "--max-time", "5"];
      if (root.apiSecret) args = args.concat(["-H", "Authorization: Bearer " + root.apiSecret]);
      return args;
    }

    stdout: SplitParser {
      onRead: data => {
        connectionsProcess.outputBuffer += data;
      }
    }

    onExited: function(code, status) {
      root.loading = false;
      root.hasFetchedOnce = true;

      if (code !== 0) {
        root.errorText = "Failed to fetch Mihomo connections.";
        connectionsProcess.outputBuffer = "";
        return;
      }

      try {
        var result = JSON.parse(connectionsProcess.outputBuffer || "{}");
        root.consumePayload(result);
      } catch (e) {
        root.errorText = "Failed to parse Mihomo connection data.";
      }

      connectionsProcess.outputBuffer = "";
    }
  }

  Process {
    id: iconLookupProcess

    property string outputBuffer: ""

    command: [
      "python3",
      Qt.resolvedUrl("../scripts/resolve_process_icon.py").toString().replace("file://", ""),
      root.currentLookupProcess
    ]

    stdout: SplitParser {
      onRead: data => {
        iconLookupProcess.outputBuffer += data;
      }
    }

    onExited: function(code, status) {
      var raw = root.currentLookupProcess;
      root.currentLookupProcess = "";

      if (code === 0) {
        try {
          var result = JSON.parse(iconLookupProcess.outputBuffer || "{}");
          root.storeResolvedProcessIcon(result);
        } catch (e) {
          Logger.w("Clashia", "Failed to parse process icon lookup: " + String(e));
        }
      }

      iconLookupProcess.outputBuffer = "";
      root.runNextIconLookup();
    }
  }

  function refresh() {
    if (!root.hasApi) {
      root.resetState();
      return;
    }

    root.requestStarted = true;
    root.loading = true;
    root.errorText = "";
    connectionsProcess.outputBuffer = "";
    connectionsProcess.running = false;
    connectionsProcess.running = true;
  }

  function resetState() {
    root.loading = false;
    root.requestStarted = false;
    root.hasFetchedOnce = false;
    root.errorText = "";
    root.connectionItems = [];
    root.uploadTotal = 0;
    root.downloadTotal = 0;
    root.activeConnectionCount = 0;
    root.memoryText = "";
  }

  function consumePayload(result) {
    var connections = Array.isArray(result?.connections) ? result.connections : [];
    var memory = Number(result?.memory ?? 0);

    root.uploadTotal = Number(result?.uploadTotal ?? 0);
    root.downloadTotal = Number(result?.downloadTotal ?? 0);
    root.activeConnectionCount = connections.length;
    root.memoryText = root.formatBytes(memory);
    root.connectionItems = connections.map(function(connection) {
      var metadata = connection?.metadata ?? ({});
      var processName = String((metadata?.process ?? metadata?.processName ?? "")).trim();
      var host = String(metadata?.host ?? "");
      var iconDescriptor = root.resolveClientIcon(connection);
      Logger.i(
        "Clashia",
        "Connection debug"
        + " process=" + (processName || "<empty>")
        + " host=" + (host || "<empty>")
        + " destination=" + String(metadata?.destinationIP ?? metadata?.remoteDestination ?? "")
        + " icon=" + String(iconDescriptor.icon ?? "")
        + " kind=" + String(iconDescriptor.kind ?? "")
        + " source=" + String(iconDescriptor.source ?? "")
        + " matchedBy=" + String(iconDescriptor.matchedBy ?? "")
        + " matchedKey=" + String(iconDescriptor.matchedKey ?? "")
        + " tried=" + String((iconDescriptor.triedKeys ?? []).join(","))
      );

      return {
        clientIcon: iconDescriptor.icon,
        clientIconKind: iconDescriptor.kind,
        clientName: root.buildClientName(connection),
        statusText: root.buildStatusText(connection),
        policyText: root.buildPolicyText(connection),
        timeText: root.buildTimeText(connection),
        processName: processName
      };
    });
  }

  function buildClientName(connection) {
    var metadata = connection?.metadata ?? ({});
    var host = String(metadata?.host ?? "");
    var destination = String(metadata?.destinationIP ?? metadata?.remoteDestination ?? "");
    return host || destination || String(connection?.id ?? "Unknown Client");
  }

  function resolveClientIcon(connection) {
    var metadata = connection?.metadata ?? ({});
    var processName = String(metadata?.process ?? metadata?.processName ?? "");
    var processMatch = root.lookupProcessIcon(processName);
    var matched = processMatch;

    if (matched.icon) {
      return {
        icon: matched.icon,
        kind: "file",
        source: matched.source,
        matchedBy: matched.matchedBy,
        matchedKey: matched.matchedKey,
        triedKeys: matched.triedKeys
      };
    }

    return {
      icon: "world",
      kind: "theme",
      source: "fallback",
      matchedBy: "",
      matchedKey: "",
      triedKeys: processMatch.triedKeys
    };
  }

  function buildStatusText(connection) {
    var status = String(connection?.status ?? connection?.state ?? connection?.metadata?.status ?? "").toLowerCase();

    if (status === "failed" || status === "failure")
      return "Failed";
    if (status === "rejected" || status === "reject")
      return "Rejected";
    if (status === "completed" || status === "closed" || status === "done")
      return "Completed";

    return "Active";
  }

  function buildPolicyText(connection) {
    var chains = connection?.chains ?? connection?.metadata?.chains ?? [];
    var candidate = "";

    if (Array.isArray(chains) && chains.length > 0)
      candidate = String(chains[chains.length - 1] ?? "");

    if (!candidate)
      candidate = String(connection?.rule ?? connection?.metadata?.rule ?? connection?.metadata?.specialProxy ?? "Direct");

    return root.resolveFinalProxyName(candidate);
  }

  function buildTimeText(connection) {
    return root.formatMeridiemTime(
      connection?.start ??
      connection?.startTime ??
      connection?.metadata?.start ??
      connection?.metadata?.startTime ??
      connection?.metadata?.createdAt ??
      connection?.metadata?.timestamp
    );
  }

  function lookupProcessIcon(value) {
    if (!value) {
      return {
        icon: "",
        source: "",
        matchedBy: "",
        matchedKey: "",
        triedKeys: []
      };
    }

    var normalized = root.normalizeAppKey(value);
    var triedKeys = [];
    if (!normalized) {
      return {
        icon: "",
        source: "",
        matchedBy: "",
        matchedKey: "",
        triedKeys: triedKeys
      };
    }

    triedKeys.push(normalized);
    if (root.processIconCache[normalized] !== undefined) {
      var cached = root.processIconCache[normalized];
      return {
        icon: String(cached?.icon ?? ""),
        source: String(cached?.source ?? String(value)),
        matchedBy: String(cached?.matchedBy ?? ""),
        matchedKey: String(cached?.matchedKey ?? ""),
        triedKeys: triedKeys
      };
    }

    var parts = String(value).split(/[\\/. _-]+/);
    for (var i = 0; i < parts.length; i++) {
      var partKey = root.normalizeAppKey(parts[i]);
      if (!partKey)
        continue;
      if (triedKeys.indexOf(partKey) === -1)
        triedKeys.push(partKey);
      if (root.processIconCache[partKey] !== undefined) {
        var partCached = root.processIconCache[partKey];
        return {
          icon: String(partCached?.icon ?? ""),
          source: String(partCached?.source ?? String(value)),
          matchedBy: String(partCached?.matchedBy ?? ""),
          matchedKey: String(partCached?.matchedKey ?? partKey),
          triedKeys: triedKeys
        };
      }
    }

    root.scheduleIconLookup(String(value), normalized);

    return {
      icon: "",
      source: String(value),
      matchedBy: "",
      matchedKey: "",
      triedKeys: triedKeys
    };
  }

  function normalizeAppKey(value) {
    var normalized = String(value ?? "").toLowerCase().trim();
    normalized = normalized.replace(/\.(desktop|bin|appimage|exe)$/g, "");
    normalized = normalized.replace(/[^a-z0-9]+/g, "");
    return normalized;
  }

  function resolveFinalProxyName(name) {
    var key = String(name ?? "").trim();
    if (!key)
      return "Direct";

    var trace = root.proxyTraceByName[key];
    var finalName = String(trace?.finalName ?? "");
    return finalName || key;
  }

  function rebindConnectionIcons() {
    if (!Array.isArray(root.connectionItems) || root.connectionItems.length === 0)
      return;

    root.connectionItems = root.connectionItems.map(function(item) {
      var match = root.lookupProcessIcon(item?.processName ?? "");
      if (!match.icon)
        return item;

      return {
        clientIcon: match.icon,
        clientIconKind: match.icon.indexOf("/") === 0 ? "file" : "theme",
        clientName: item?.clientName ?? "",
        statusText: item?.statusText ?? "Active",
        policyText: item?.policyText ?? "Direct",
        timeText: item?.timeText ?? "",
        processName: item?.processName ?? ""
      };
    });
  }

  function scheduleIconLookup(processName, normalized) {
    if (!processName || !normalized)
      return;
    if (root.processIconCache[normalized] !== undefined)
      return;
    if (root.currentLookupProcess === processName || root.currentLookupProcess === normalized)
      return;
    if (root.pendingIconLookups.indexOf(processName) !== -1)
      return;

    root.pendingIconLookups = root.pendingIconLookups.concat([processName]);
    root.runNextIconLookup();
  }

  function runNextIconLookup() {
    if (iconLookupProcess.running || root.pendingIconLookups.length === 0)
      return;

    root.currentLookupProcess = String(root.pendingIconLookups[0] ?? "");
    root.pendingIconLookups = root.pendingIconLookups.slice(1);
    iconLookupProcess.outputBuffer = "";
    iconLookupProcess.running = false;
    iconLookupProcess.running = true;
  }

  function storeResolvedProcessIcon(result) {
    var processName = String(result?.process ?? "");
    var normalized = root.normalizeAppKey(processName);
    if (!normalized)
      return;

    var nextCache = Object.assign({}, root.processIconCache);
    nextCache[normalized] = {
      icon: String(result?.icon ?? ""),
      source: processName,
      matchedBy: String(result?.matchedBy ?? ""),
      matchedKey: String(result?.matchedKey ?? "")
    };
    root.processIconCache = nextCache;

    Logger.i(
      "Clashia",
      "Process icon lookup"
      + " process=" + (processName || "<empty>")
      + " icon=" + String(result?.icon ?? "")
      + " matchedBy=" + String(result?.matchedBy ?? "")
      + " matchedKey=" + String(result?.matchedKey ?? "")
    );

    root.rebindConnectionIcons();
  }

  function statusColor(statusText) {
    if (statusText === "Failed")
      return "#d94f4f";
    if (statusText === "Rejected")
      return "#c97a22";
    if (statusText === "Completed")
      return Qt.alpha(Color.mOnSurface, 0.7);
    return "#36a269";
  }

  function formatMeridiemTime(value) {
    if (!value)
      return Qt.formatTime(new Date(), "hh:mm:ssAP");

    var parsed = new Date(value);
    if (isNaN(parsed.getTime())) {
      var numeric = Number(value);
      if (!isNaN(numeric) && numeric > 0) {
        parsed = new Date(numeric < 1000000000000 ? numeric * 1000 : numeric);
      }
    }

    if (isNaN(parsed.getTime()))
      return String(value);

    return Qt.formatTime(parsed, "hh:mm:ssAP");
  }

  function formatBytes(bytes) {
    if (bytes <= 0)
      return "0 B";

    var units = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    var value = bytes;

    while (value >= 1024 && i < units.length - 1) {
      value /= 1024;
      i++;
    }

    return value.toFixed(i === 0 ? 0 : 1) + " " + units[i];
  }
}
