import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Widgets

Item {
  id: root

  property string apiBaseUrl: ""
  property string apiSecret: ""
  property string logLevel: "info"
  property var logEntries: []
  property bool requestStarted: false
  property bool connected: false
  property bool stopping: false
  property string errorText: ""

  readonly property bool hasApi: apiBaseUrl !== ""
  readonly property int maxEntries: 200
  readonly property string requestUrl: hasApi ? apiBaseUrl + "/logs?level=" + encodeURIComponent(logLevel) + "&format=json" : ""
  readonly property color panelColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.05 : 0.035)
  readonly property color borderColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.08 : 0.06)
  readonly property color itemColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.04 : 0.025)
  readonly property color itemBorderColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.08 : 0.05)

  Layout.fillWidth: true
  implicitHeight: 360 * Style.uiScaleRatio

  onApiBaseUrlChanged: {
    if (apiBaseUrl)
      Qt.callLater(root.startStream);
    else
      root.resetState();
  }

  onVisibleChanged: {
    if (visible)
      root.startStream();
    else
      root.stopStream();
  }

  Component.onCompleted: {
    if (visible && apiBaseUrl)
      Qt.callLater(root.startStream);
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
        text: "Logs"
        font.pointSize: Style.fontSizeS
        font.weight: Font.DemiBold
        color: Color.mOnSurface
      }

      NText {
        text: root.connected ? "Streaming" : (root.requestStarted ? "Connecting" : "Idle")
        font.pointSize: Style.fontSizeS * 0.92
        color: Qt.alpha(Color.mOnSurface, 0.68)
      }

      Item {
        Layout.fillWidth: true
      }

      Rectangle {
        Layout.preferredWidth: 30 * Style.uiScaleRatio
        Layout.preferredHeight: 30 * Style.uiScaleRatio
        radius: Style.radiusM
        color: clearArea.containsMouse ? Qt.alpha(Color.mOnSurface, 0.08) : "transparent"
        border.color: Qt.alpha(Color.mOnSurface, 0.08)
        border.width: 1

        NIcon {
          anchors.centerIn: parent
          icon: "trash-2"
          pointSize: Math.round(Style.fontSizeS)
          color: Color.mOnSurface
          opacity: 0.8
        }

        MouseArea {
          id: clearArea

          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.logEntries = []
        }
      }

      Rectangle {
        Layout.preferredWidth: 30 * Style.uiScaleRatio
        Layout.preferredHeight: 30 * Style.uiScaleRatio
        radius: Style.radiusM
        color: refreshArea.containsMouse ? Qt.alpha(Color.mOnSurface, 0.08) : "transparent"
        border.color: Qt.alpha(Color.mOnSurface, 0.08)
        border.width: 1
        opacity: root.hasApi ? 1 : 0.45

        NIcon {
          anchors.centerIn: parent
          icon: "refresh-cw"
          pointSize: Math.round(Style.fontSizeS)
          color: Color.mOnSurface
          opacity: 0.8
        }

        MouseArea {
          id: refreshArea

          anchors.fill: parent
          enabled: root.hasApi
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.restartStream()
        }
      }
    }

    Loader {
      Layout.fillWidth: true
      Layout.fillHeight: true
      active: true
      sourceComponent: {
        if (!root.hasApi) return noApiState;
        if (root.errorText !== "") return errorState;
        if (root.logEntries.length === 0) return emptyState;
        return logListState;
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
          onClicked: root.restartStream()
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
        text: root.requestStarted ? "Waiting for Mihomo logs..." : "Start the Mihomo log stream to see entries."
        font.pointSize: Style.fontSizeS
        color: Qt.alpha(Color.mOnSurface, 0.72)
      }
    }
  }

  Component {
    id: logListState

    Flickable {
      id: logFlickable

      clip: true
      boundsBehavior: Flickable.StopAtBounds
      contentWidth: width
      contentHeight: logColumn.implicitHeight

      Column {
        id: logColumn

        width: logFlickable.width
        spacing: Style.marginXS

        Repeater {
          model: root.logEntries

          delegate: Rectangle {
            required property var modelData

            width: logColumn.width
            implicitHeight: logEntryColumn.implicitHeight + Style.marginM * 2
            radius: Style.radiusM
            color: root.itemColor
            border.color: root.itemBorderColor
            border.width: 1

            ColumnLayout {
              id: logEntryColumn

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
                  text: modelData.levelText ?? "INFO"
                  font.pointSize: Style.fontSizeS * 0.88
                  font.weight: Font.DemiBold
                  color: root.levelColor(modelData.levelText ?? "")
                }

                Item {
                  Layout.fillWidth: true
                }

                NText {
                  text: modelData.timeText ?? ""
                  font.pointSize: Style.fontSizeS * 0.88
                  color: Qt.alpha(Color.mOnSurface, 0.55)
                }
              }

              NText {
                Layout.fillWidth: true
                text: modelData.message ?? ""
                wrapMode: Text.WordWrap
                font.pointSize: Style.fontSizeS
                color: Color.mOnSurface
              }
            }
          }
        }
      }
    }
  }

  Process {
    id: logsProcess

    property string lineBuffer: ""

    command: {
      if (!root.requestUrl || !root.visible) return ["echo"];
      var args = ["curl", "-s", "-N", root.requestUrl, "--max-time", "0"];
      if (root.apiSecret) args = args.concat(["-H", "Authorization: Bearer " + root.apiSecret]);
      return args;
    }

    stdout: SplitParser {
      onRead: data => {
        root.connected = true;
        logsProcess.lineBuffer += data;
        root.consumeBufferedLines(false);
      }
    }

    onExited: function(code, status) {
      root.connected = false;
      root.consumeBufferedLines(true);

      if (root.stopping) {
        root.stopping = false;
        return;
      }

      if (!root.visible || !root.hasApi)
        return;

      if (code !== 0 && root.logEntries.length === 0)
        root.errorText = "Failed to stream Mihomo logs.";

      logRestartTimer.restart();
    }
  }

  Timer {
    id: logRestartTimer

    interval: 1500
    repeat: false
    onTriggered: root.startStream()
  }

  function startStream() {
    if (!root.visible || !root.hasApi)
      return;

    root.requestStarted = true;
    root.errorText = "";
    logRestartTimer.stop();
    logsProcess.running = false;
    logsProcess.lineBuffer = "";
    logsProcess.running = true;
  }

  function stopStream() {
    logRestartTimer.stop();
    root.connected = false;
    root.stopping = logsProcess.running;
    logsProcess.running = false;
  }

  function restartStream() {
    root.stopStream();
    root.startStream();
  }

  function resetState() {
    root.stopStream();
    root.requestStarted = false;
    root.errorText = "";
    root.logEntries = [];
  }

  function consumeBufferedLines(flushRemainder) {
    var parts = logsProcess.lineBuffer.split("\n");
    var completeCount = flushRemainder ? parts.length : parts.length - 1;

    for (var i = 0; i < completeCount; i++) {
      var line = parts[i].trim();
      if (!line)
        continue;
      root.appendLogEntry(root.parseLogLine(line));
    }

    logsProcess.lineBuffer = flushRemainder ? "" : (parts.length > 0 ? parts[parts.length - 1] : "");
  }

  function parseLogLine(line) {
    try {
      var parsed = JSON.parse(line);
      return {
        levelText: String(parsed?.type ?? parsed?.level ?? "info").toUpperCase(),
        message: String(parsed?.payload ?? parsed?.message ?? line),
        timeText: root.formatTimestamp(parsed?.time ?? parsed?.timestamp ?? "")
      };
    } catch (e) {
      return {
        levelText: "INFO",
        message: line,
        timeText: root.formatTimestamp("")
      };
    }
  }

  function appendLogEntry(entry) {
    var items = root.logEntries.slice();
    items.push(entry);

    if (items.length > root.maxEntries)
      items = items.slice(items.length - root.maxEntries);

    root.logEntries = items;
  }

  function formatTimestamp(value) {
    if (!value)
      return Qt.formatTime(new Date(), "HH:mm:ss");

    var parsed = new Date(value);
    if (isNaN(parsed.getTime()))
      return String(value);

    return Qt.formatTime(parsed, "HH:mm:ss");
  }

  function levelColor(level) {
    var normalized = String(level).toLowerCase();
    if (normalized.indexOf("error") >= 0) return "#FF6B6B";
    if (normalized.indexOf("warn") >= 0) return "#FFB74D";
    if (normalized.indexOf("debug") >= 0) return "#64B5F6";
    return "#81C784";
  }
}
