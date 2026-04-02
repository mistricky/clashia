import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Widgets

Item {
  id: root

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

  readonly property bool hasApi: apiBaseUrl !== ""
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
    spacing: Style.marginM

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NText {
        text: "Connections"
        font.pointSize: Style.fontSizeS
        font.weight: Font.DemiBold
        color: Color.mOnSurface
      }

      Item {
        Layout.fillWidth: true
      }

      Rectangle {
        Layout.preferredWidth: 30 * Style.uiScaleRatio
        Layout.preferredHeight: 30 * Style.uiScaleRatio
        radius: Style.radiusM
        color: refreshArea.containsMouse && !root.loading ? Qt.alpha(Color.mOnSurface, 0.08) : "transparent"
        border.color: Qt.alpha(Color.mOnSurface, 0.08)
        border.width: 1
        opacity: root.hasApi ? 1 : 0.45

        NIcon {
          anchors.centerIn: parent
          icon: "refresh-cw"
          pointSize: Math.round(Style.fontSizeS)
          color: Color.mOnSurface
          opacity: root.loading ? 1 : 0.8
        }

        MouseArea {
          id: refreshArea

          anchors.fill: parent
          enabled: root.hasApi && !root.loading
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.refresh()
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      Repeater {
        model: [
          { label: "Active", value: String(root.activeConnectionCount) },
          { label: "Upload", value: root.formatBytes(root.uploadTotal) },
          { label: "Download", value: root.formatBytes(root.downloadTotal) },
          { label: "Memory", value: root.memoryText || "0 B" }
        ]

        delegate: Rectangle {
          required property var modelData

          Layout.fillWidth: true
          implicitHeight: summaryColumn.implicitHeight + Style.marginM * 2
          radius: Style.radiusM
          color: root.itemColor
          border.color: root.itemBorderColor
          border.width: 1

          ColumnLayout {
            id: summaryColumn

            anchors.fill: parent
            anchors.leftMargin: Style.marginM
            anchors.rightMargin: Style.marginM
            anchors.topMargin: Style.marginM
            anchors.bottomMargin: Style.marginM
            spacing: Style.marginXS

            NText {
              text: modelData.label
              font.pointSize: Style.fontSizeS * 0.88
              color: Qt.alpha(Color.mOnSurface, 0.6)
            }

            NText {
              text: modelData.value
              font.pointSize: Style.fontSizeS
              font.weight: Font.DemiBold
              color: Color.mOnSurface
            }
          }
        }
      }
    }

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

    Flickable {
      id: connectionsFlickable

      clip: true
      boundsBehavior: Flickable.StopAtBounds
      contentWidth: width
      contentHeight: connectionsColumn.implicitHeight

      Column {
        id: connectionsColumn

        width: connectionsFlickable.width
        spacing: Style.marginXS

        Repeater {
          model: root.connectionItems

          delegate: Rectangle {
            required property var modelData

            width: connectionsColumn.width
            implicitHeight: connectionColumn.implicitHeight + Style.marginM * 2
            radius: Style.radiusM
            color: root.itemColor
            border.color: root.itemBorderColor
            border.width: 1

            ColumnLayout {
              id: connectionColumn

              anchors.fill: parent
              anchors.leftMargin: Style.marginM
              anchors.rightMargin: Style.marginM
              anchors.topMargin: Style.marginM
              anchors.bottomMargin: Style.marginM
              spacing: Style.marginXS

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NText {
                  Layout.fillWidth: true
                  text: modelData.hostText
                  elide: Text.ElideRight
                  font.pointSize: Style.fontSizeS
                  font.weight: Font.DemiBold
                  color: Color.mOnSurface
                }

                NText {
                  text: modelData.typeText
                  font.pointSize: Style.fontSizeS * 0.88
                  color: Qt.alpha(Color.mOnSurface, 0.55)
                }
              }

              RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS

                NText {
                  Layout.fillWidth: true
                  text: modelData.ruleText
                  elide: Text.ElideRight
                  font.pointSize: Style.fontSizeS * 0.92
                  color: Qt.alpha(Color.mOnSurface, 0.72)
                }

                NText {
                  text: modelData.transferText
                  font.pointSize: Style.fontSizeS * 0.9
                  color: Qt.alpha(Color.mOnSurface, 0.62)
                }
              }

              NText {
                Layout.fillWidth: true
                text: modelData.chainText
                wrapMode: Text.WordWrap
                font.pointSize: Style.fontSizeS * 0.9
                color: Qt.alpha(Color.mOnSurface, 0.6)
              }
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
      return {
        hostText: root.buildHostText(connection),
        typeText: String(connection?.metadata?.network ?? connection?.metadata?.type ?? "").toUpperCase(),
        ruleText: root.buildRuleText(connection),
        transferText: "↑ " + root.formatBytes(Number(connection?.upload ?? 0)) + "  ↓ " + root.formatBytes(Number(connection?.download ?? 0)),
        chainText: root.buildChainText(connection)
      };
    });
  }

  function buildHostText(connection) {
    var metadata = connection?.metadata ?? ({});
    var host = String(metadata?.host ?? "");
    var destination = String(metadata?.destinationIP ?? metadata?.remoteDestination ?? "");
    if (host && destination)
      return host + " (" + destination + ")";
    return host || destination || String(connection?.id ?? "");
  }

  function buildRuleText(connection) {
    var metadata = connection?.metadata ?? ({});
    var processName = String(metadata?.process ?? metadata?.processName ?? "");
    var rule = String(connection?.rule ?? metadata?.rule ?? "");
    if (processName && rule)
      return processName + " · " + rule;
    return processName || rule || "Unknown rule";
  }

  function buildChainText(connection) {
    var chains = connection?.chains ?? connection?.metadata?.chains ?? [];
    if (!Array.isArray(chains) || chains.length === 0)
      return "Direct";
    return chains.join(" -> ");
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
