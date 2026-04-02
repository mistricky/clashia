import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Widgets
import "accordion" as AccordionComponents

Item {
  id: root

  property var pluginApi: null
  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})
  property var proxyGroupTestUrls: ({})
  property var proxyProviderTestUrls: ({})
  property string apiBaseUrl: ""
  property string apiSecret: ""
  property string routingMode: "rule"
  property var proxyGroups: []
  property var expandedGroupStates: ({})
  property var proxiesByName: ({})
  property var delayByKey: ({})
  property var testingByKey: ({})
  property var manualTestingByKey: ({})
  property var headerTestingByKey: ({})
  property var activeDelayTestProcesses: ({})
  property bool loading: false
  property bool requestStarted: false
  property bool hasFetchedOnce: false
  property bool switching: false
  property string errorText: ""
  property string infoText: ""
  property string sortMode: normalizeSortMode(cfg.sortMode ?? defaults.sortMode ?? "name")
  property bool delayCacheRestored: false

  readonly property string requestUrl: apiBaseUrl ? apiBaseUrl + "/proxies" : ""
  readonly property bool hasApi: apiBaseUrl !== ""
  readonly property bool hasGroups: proxyGroups.length > 0
  readonly property int totalNodeCount: countNodes(proxyGroups)
  readonly property string normalizedRoutingMode: String(routingMode ?? "rule").toLowerCase()
  readonly property bool isRuleMode: normalizedRoutingMode === "rule"
  readonly property bool isGlobalMode: normalizedRoutingMode === "global"
  readonly property bool isDirectMode: normalizedRoutingMode === "direct"
  readonly property string panelTitle: isGlobalMode ? "Proxies" : "Proxy groups"
  readonly property string delayTestUrl: cfg.delayTestUrl ?? defaults.delayTestUrl ?? "https://www.gstatic.com/generate_204"
  readonly property bool delayTesting: Object.keys(headerTestingByKey).length > 0
  readonly property var effectiveGlobalGroup: findGroup("GLOBAL")
  readonly property string effectiveGlobalCurrent: effectiveGlobalGroup?.current ?? ""
  readonly property var globalNodes: buildGlobalNodes(proxyGroups)
  readonly property var sortedProxyGroups: sortProxyGroups(proxyGroups)
  readonly property var sortedGlobalNodes: sortGlobalNodes(globalNodes)
  readonly property real contentOpacity: isDirectMode ? 0.58 : 1
  readonly property color sectionColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.04 : 0.025)
  readonly property color sectionBorderColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.08 : 0.06)
  readonly property color sectionActiveColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.12 : 0.08)
  readonly property color sectionActiveBorderColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.10 : 0.08)
  readonly property color delayFastColor: "#22c55e"
  readonly property color delayMediumColor: "#f59e0b"
  readonly property color delaySlowColor: "#ef4444"
  readonly property color delayIdleColor: Qt.alpha(Color.mOnSurface, 0.16)
  readonly property real nodeNameWidth: 128 * Style.uiScaleRatio
  readonly property real middleInfoWidth: 72 * Style.uiScaleRatio
  readonly property real groupChildIndent: Math.max(16, Style.marginL)
  readonly property string delayCacheScopeKey: apiBaseUrl || "__default__"
  readonly property int delayCacheMaxEntries: 512

  Layout.fillWidth: true
  implicitHeight: 320 * Style.uiScaleRatio

  onPluginApiChanged: {
    if (pluginApi && root.hasGroups)
      Qt.callLater(root.restoreDelayCache);
  }

  onApiBaseUrlChanged: {
    if (apiBaseUrl)
      Qt.callLater(root.refresh);
    else
      root.resetState();
  }

  Component.onCompleted: {
    if (apiBaseUrl)
      Qt.callLater(root.refresh);
  }

  onVisibleChanged: {
    if (visible && apiBaseUrl && !root.loading && !root.hasFetchedOnce)
      Qt.callLater(root.refresh);
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.05 : 0.035)
    radius: Style.radiusM
    border.color: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.08 : 0.06)
    border.width: 1
  }

  Timer {
    id: delayCacheSaveTimer

    interval: 400
    repeat: false
    onTriggered: root.persistDelayCache()
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: 0
    spacing: Style.marginM

    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.marginL
      Layout.rightMargin: Style.marginS
      Layout.topMargin: Style.marginM
      spacing: Style.marginS

      NText {
        text: root.panelTitle
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
        color: headerSortArea.containsMouse ? Qt.alpha(Color.mOnSurface, 0.09) : "transparent"
        opacity: root.hasGroups ? 1 : 0.45

        NIcon {
          anchors.centerIn: parent
          icon: root.sortMode === "delay" ? "activity" : "list"
          pointSize: Math.round(Style.fontSizeS * 1.05)
          color: Color.mOnSurface
          opacity: 0.78
        }

        MouseArea {
          id: headerSortArea

          anchors.fill: parent
          enabled: root.hasGroups
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.toggleSortMode()
        }
      }

      Rectangle {
        Layout.preferredWidth: 30 * Style.uiScaleRatio
        Layout.preferredHeight: 30 * Style.uiScaleRatio
        radius: Style.radiusM
        color: headerTestArea.containsMouse && !root.loading ? Qt.alpha(Color.mOnSurface, 0.09) : "transparent"
        opacity: root.hasApi ? 1 : 0.45

        NIcon {
          anchors.centerIn: parent
          icon: root.delayTesting ? "loader-2" : "gauge"
          pointSize: Math.round(Style.fontSizeS * 1.08)
          color: Color.mOnSurface
          opacity: root.delayTesting ? 1 : 0.78

          NumberAnimation on rotation {
            running: root.delayTesting
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 900
          }
        }

        MouseArea {
          id: headerTestArea

          anchors.fill: parent
          enabled: root.hasApi && !root.loading
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.queueAllDelayTests(true, true)
        }
      }
    }

    Loader {
      Layout.fillWidth: true
      Layout.fillHeight: true
      opacity: root.contentOpacity
      active: true
      sourceComponent: {
        if (!root.hasApi) return noApiState;
        if (root.requestStarted && !root.hasFetchedOnce) return loadingState;
        if (root.loading) return loadingState;
        if (root.errorText !== "") return errorState;
        if (!root.hasGroups) return emptyState;
        return root.isGlobalMode ? globalListState : ruleListState;
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
        text: "Loading proxies..."
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
        width: Math.min(parent.width, 260 * Style.uiScaleRatio)
        spacing: Style.marginS

        NText {
          Layout.fillWidth: true
          horizontalAlignment: Text.AlignHCenter
          text: root.errorText
          wrapMode: Text.WordWrap
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
        text: "No selectable Mihomo proxy groups found."
        font.pointSize: Style.fontSizeS
        color: Qt.alpha(Color.mOnSurface, 0.72)
      }
    }
  }

  Component {
    id: ruleListState

    Flickable {
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      contentHeight: groupsColumn.implicitHeight

      AccordionComponents.Accordion {
        id: groupsColumn

        width: parent.width
        itemSpacing: 0

        Repeater {
          model: root.sortedProxyGroups

          delegate: Item {
            id: groupItem

            required property var modelData

            readonly property string groupName: modelData.name ?? ""
            readonly property var groupState: root.findGroup(groupName) ?? modelData
            property bool expandedState: root.isGroupExpanded(groupName)
            readonly property string currentNodeName: groupState?.current ?? ""
            readonly property string delayText: root.formatGroupDelay(groupName, currentNodeName)

            width: groupsColumn.width
            implicitHeight: groupContent.implicitHeight

            onGroupStateChanged: {
              var nextExpanded = root.isGroupExpanded(groupName);
              if (expandedState !== nextExpanded)
                expandedState = nextExpanded;
            }

            Column {
              id: groupContent

              width: parent.width
              spacing: 0

              Rectangle {
                id: groupHeaderBackground

                width: parent.width
                implicitHeight: groupHeader.implicitHeight + Style.marginS * 2
                radius: 0
                color: groupHeaderArea.containsMouse || groupTestArea.containsMouse
                  ? Qt.alpha(Color.mOnSurface, 0.045)
                  : "transparent"
                border.color: "transparent"
                border.width: 0

                Behavior on color {
                  ColorAnimation {
                    duration: 140
                  }
                }

                RowLayout {
                  id: groupHeader

                  anchors.fill: parent
                  anchors.leftMargin: Style.marginL
                  anchors.rightMargin: Style.marginS
                  anchors.topMargin: 1
                  anchors.bottomMargin: 1
                  spacing: Style.marginS

                  NText {
                    Layout.fillWidth: true
                    text: groupItem.groupName
                    elide: Text.ElideRight
                    font.pointSize: Style.fontSizeS * 0.92
                    font.weight: Font.DemiBold
                    color: Color.mOnSurface
                  }

                  NText {
                    Layout.preferredWidth: root.middleInfoWidth
                    text: groupItem.currentNodeName
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignLeft
                    font.pointSize: Style.fontSizeS * 0.88
                    color: Qt.alpha(Color.mOnSurface, 0.72)
                  }

                  NText {
                    text: groupItem.delayText
                    font.pointSize: Style.fontSizeS * 0.82
                    color: root.delayColorForValue(root.delayValueForGroup(groupItem.modelData.name ?? "", groupItem.currentNodeName))
                    opacity: groupItem.delayText === "--" ? 0.65 : 1
                  }

                  Rectangle {
                    Layout.preferredWidth: 26 * Style.uiScaleRatio
                    Layout.preferredHeight: 26 * Style.uiScaleRatio
                    radius: Style.radiusM
                    color: groupTestArea.containsMouse ? Qt.alpha(Color.mOnSurface, 0.08) : "transparent"
                    z: 2

                    NIcon {
                      anchors.centerIn: parent
                      icon: root.isManualTestingDelay("group", groupItem.modelData.name ?? "") ? "loader-2" : "gauge"
                      pointSize: Math.round(Style.fontSizeS)
                      color: Color.mOnSurface
                      opacity: root.isManualTestingDelay("group", groupItem.modelData.name ?? "") ? 1 : 0.76

                      NumberAnimation on rotation {
                        running: root.isManualTestingDelay("group", groupItem.modelData.name ?? "")
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                      }
                    }

                    MouseArea {
                      id: groupTestArea

                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        mouse.accepted = true;
                        root.queueDelayTest("group", groupItem.groupName);
                      }
                    }
                  }

                  Item {
                    Layout.preferredWidth: 20 * Style.uiScaleRatio
                    Layout.preferredHeight: 20 * Style.uiScaleRatio
                    transformOrigin: Item.Center
                    rotation: groupItem.expandedState ? 90 : 0

                    Behavior on rotation {
                      NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                      }
                    }

                    NIcon {
                      anchors.centerIn: parent
                      icon: "chevron-right"
                      pointSize: Math.round(Style.fontSizeS * 1.02)
                      color: Qt.alpha(Color.mOnSurface, 0.72)
                    }
                  }
                }

                MouseArea {
                  id: groupHeaderArea

                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  z: 1
                  onClicked: {
                    var nextExpanded = !groupItem.expandedState;
                    groupItem.expandedState = nextExpanded;
                    root.updateGroupExpandedState(groupItem.groupName, nextExpanded);
                  }
                }
              }

              Item {
                height: groupContentWrapper.height
                width: parent.width
                implicitHeight: height

                Item {
                  id: groupContentWrapper

                  width: parent.width
                  height: groupItem.expandedState ? groupNodesColumn.implicitHeight : 0
                  clip: true
                  opacity: groupItem.expandedState ? 1 : 0
                  y: groupItem.expandedState ? 0 : -Math.max(6, Style.marginXS)
                  implicitHeight: height

                  Behavior on height {
                    NumberAnimation {
                      duration: 260
                      easing.type: Easing.OutCubic
                    }
                  }

                  Behavior on opacity {
                    NumberAnimation {
                      duration: 180
                    }
                  }

                  Behavior on y {
                    NumberAnimation {
                      duration: 260
                      easing.type: Easing.OutCubic
                    }
                  }

                  Column {
                    id: groupNodesColumn

                    width: parent.width
                    spacing: 0

                    Repeater {
                      model: root.sortNodes(groupItem.groupState?.nodes ?? [])

                      delegate: Rectangle {
                        id: groupNodeBackground

                        required property var modelData

                        readonly property bool isCurrent: modelData.current ?? false
                        readonly property bool selectable: modelData.selectable ?? true

                        width: parent.width
                        implicitHeight: nodeRow.implicitHeight + Style.marginS * 2
                        radius: 0
                        color: groupNodeArea.containsMouse ? Qt.alpha(Color.mOnSurface, 0.04) : "transparent"
                        border.color: "transparent"
                        border.width: 0

                        Behavior on color {
                          ColorAnimation {
                            duration: 140
                          }
                        }

                        RowLayout {
                          id: nodeRow

                          anchors.fill: parent
                          anchors.leftMargin: root.groupChildIndent + Style.marginL
                          anchors.rightMargin: Style.marginS
                          anchors.topMargin: 1
                          anchors.bottomMargin: 1
                          spacing: Style.marginS
                          z: 1

                          NText {
                            Layout.preferredWidth: root.nodeNameWidth
                            text: modelData.name ?? ""
                            elide: Text.ElideRight
                            font.pointSize: Style.fontSizeS * 0.9
                            font.weight: isCurrent ? Font.DemiBold : Font.Medium
                            color: Color.mOnSurface
                          }

                          NIcon {
                            Layout.preferredWidth: Math.round(Style.fontSizeS * 1.2)
                            icon: "check"
                            pointSize: Math.round(Style.fontSizeS)
                            color: Color.mOnSurface
                            opacity: isCurrent ? 1 : 0
                          }
                        }

                        MouseArea {
                          id: groupNodeArea

                          anchors.fill: parent
                          enabled: selectable && !isCurrent && !root.switching
                          hoverEnabled: true
                          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                          z: 0
                          onClicked: root.selectNode(modelData.name ?? "", modelData.groupName ?? "")
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  Component {
    id: globalListState

    Flickable {
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      contentHeight: globalNodesColumn.implicitHeight

      Column {
        id: globalNodesColumn

        width: parent.width
        spacing: 0

        Repeater {
          model: root.sortedGlobalNodes

          delegate: Rectangle {
            id: globalNodeBackground

            required property var modelData

            readonly property bool isCurrent: modelData.current ?? false
            readonly property bool selectable: modelData.selectable ?? true
            readonly property string itemKind: modelData.kind ?? "node"

            width: globalNodesColumn.width
            implicitHeight: nodeRow.implicitHeight + Style.marginS * 2
            radius: 0
            color: globalNodeArea.containsMouse ? Qt.alpha(Color.mOnSurface, 0.04) : "transparent"
            border.color: "transparent"
            border.width: 0

            Behavior on color {
              ColorAnimation {
                duration: 140
              }
            }

            RowLayout {
              id: nodeRow

              anchors.fill: parent
              anchors.leftMargin: Style.marginL
              anchors.rightMargin: Style.marginS
              anchors.topMargin: 1
              anchors.bottomMargin: 1
              spacing: Style.marginS
              z: 1

              NText {
                Layout.preferredWidth: root.nodeNameWidth
                text: modelData.name ?? ""
                elide: Text.ElideRight
                font.pointSize: Style.fontSizeS * 0.9
                font.weight: isCurrent ? Font.DemiBold : Font.Medium
                color: Color.mOnSurface
              }

              NText {
                Layout.preferredWidth: root.middleInfoWidth
                text: modelData.groupLabel ?? ""
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignLeft
                font.pointSize: Style.fontSizeS * 0.84
                color: Qt.alpha(Color.mOnSurface, 0.68)
              }

              NText {
                text: itemKind === "group"
                  ? root.formatDelay("group", modelData.name ?? "")
                  : root.formatDelay("node", modelData.name ?? "")
                font.pointSize: Style.fontSizeS * 0.82
                color: root.delayColorForValue(
                  itemKind === "group"
                    ? root.delayValueForKey("group", modelData.name ?? "")
                    : root.delayValueForKey("node", modelData.name ?? "")
                )
                opacity: (
                  itemKind === "group"
                    ? root.formatDelay("group", modelData.name ?? "")
                    : root.formatDelay("node", modelData.name ?? "")
                ) === "--" ? 0.65 : 1
              }

              Rectangle {
                Layout.preferredWidth: 26 * Style.uiScaleRatio
                Layout.preferredHeight: 26 * Style.uiScaleRatio
                radius: Style.radiusM
                color: globalTestArea.containsMouse ? Qt.alpha(Color.mOnSurface, 0.08) : "transparent"

                NIcon {
                  anchors.centerIn: parent
                  icon: root.isManualTestingDelay(itemKind, modelData.name ?? "") ? "loader-2" : "gauge"
                  pointSize: Math.round(Style.fontSizeS)
                  color: Color.mOnSurface
                  opacity: root.isManualTestingDelay(itemKind, modelData.name ?? "") ? 1 : 0.76

                  NumberAnimation on rotation {
                    running: root.isManualTestingDelay(itemKind, modelData.name ?? "")
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 900
                  }
                }

                MouseArea {
                  id: globalTestArea

                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    mouse.accepted = true;
                    root.queueDelayTest(itemKind, modelData.name ?? "");
                  }
                }
              }

              NIcon {
                Layout.preferredWidth: Math.round(Style.fontSizeS * 1.2)
                icon: "check"
                pointSize: Math.round(Style.fontSizeS)
                color: Color.mOnSurface
                opacity: isCurrent ? 1 : 0
              }
            }

            MouseArea {
              id: globalNodeArea

              anchors.fill: parent
              enabled: selectable && !isCurrent && !root.switching
              hoverEnabled: true
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              z: 0
              onClicked: root.selectNode(modelData.name ?? "", modelData.switchGroupName ?? "")
            }
          }
        }
      }
    }
  }

  Process {
    id: fetchNodesProcess

    property string outputBuffer: ""

    command: {
      if (!root.requestUrl) return ["echo"];
      var args = ["curl", "-s", root.requestUrl, "--max-time", "5"];
      if (root.apiSecret) args = args.concat(["-H", "Authorization: Bearer " + root.apiSecret]);
      return args;
    }

    stdout: SplitParser {
      onRead: data => {
        fetchNodesProcess.outputBuffer += data;
      }
    }

    onExited: function(code, status) {
      root.loading = false;
      root.hasFetchedOnce = true;

      if (code !== 0) {
        root.errorText = "Failed to fetch Mihomo nodes.";
        fetchNodesProcess.outputBuffer = "";
        return;
      }

      try {
        var result = JSON.parse(fetchNodesProcess.outputBuffer);
        root.consumeProxyPayload(result);
      } catch (e) {
        root.errorText = "Failed to parse Mihomo node data.";
      }

      fetchNodesProcess.outputBuffer = "";
    }
  }

  Process {
    id: switchNodeProcess

    property string targetNodeName: ""
    property string targetGroupName: ""

    command: {
      if (!root.requestUrl || !switchNodeProcess.targetNodeName || !switchNodeProcess.targetGroupName) return ["echo"];
      var payload = JSON.stringify({ "name": switchNodeProcess.targetNodeName });
      var groupPath = encodeURIComponent(switchNodeProcess.targetGroupName);
      var args = [
        "curl",
        "-s",
        "-X", "PUT",
        root.apiBaseUrl + "/proxies/" + groupPath,
        "-d", payload,
        "-H", "Content-Type: application/json",
        "--max-time", "5"
      ];
      if (root.apiSecret) args = args.concat(["-H", "Authorization: Bearer " + root.apiSecret]);
      return args;
    }

    onExited: function(code, status) {
      root.switching = false;

      if (code !== 0) {
        root.errorText = "Failed to switch Mihomo node.";
        return;
      }

      root.errorText = "";
      root.applySelectedNode(switchNodeProcess.targetGroupName, switchNodeProcess.targetNodeName);
    }
  }

  Component {
    id: delayTestProcessComponent

    Process {
      id: delayTestProcess

      property string outputBuffer: ""
      property string targetKind: ""
      property string targetName: ""
      property string targetKey: ""
      property bool manual: false
      property string triggerSource: ""

      command: {
        return root.buildDelayTestCommand(targetKind, targetName);
      }

      stdout: SplitParser {
        onRead: data => {
          delayTestProcess.outputBuffer += data;
        }
      }

      onExited: function(code, status) {
        root.finishDelayTest(delayTestProcess, code);
      }
    }
  }

  function refresh() {
    if (!root.apiBaseUrl) {
      root.resetState();
      return;
    }

    root.requestStarted = true;
    root.loading = true;
    root.errorText = "";
    root.infoText = "";
    fetchNodesProcess.outputBuffer = "";
    fetchNodesProcess.running = false;
    fetchNodesProcess.running = true;
  }

  function resetState() {
    root.loading = false;
    root.requestStarted = false;
    root.hasFetchedOnce = false;
    root.switching = false;
    root.errorText = "";
    root.infoText = "";
    root.proxyGroups = [];
    root.expandedGroupStates = ({});
    root.proxiesByName = ({});
    root.delayByKey = ({});
    root.testingByKey = ({});
    root.manualTestingByKey = ({});
    root.headerTestingByKey = ({});
    root.activeDelayTestProcesses = ({});
    root.delayCacheRestored = false;
  }

  function buildDelayTestCommand(kind, name) {
    if (!root.apiBaseUrl || !name) return ["echo"];

    var namePath = encodeURIComponent(name);
    var endpoint = kind === "group"
      ? "/group/" + namePath + "/delay"
      : "/proxies/" + namePath + "/delay";
    var url = root.apiBaseUrl + endpoint + "?timeout=5000&url=" + encodeURIComponent(root.resolveDelayTestUrl(kind, name));
    var args = ["curl", "-s", url, "--max-time", "8"];
    if (root.apiSecret) args = args.concat(["-H", "Authorization: Bearer " + root.apiSecret]);
    return args;
  }

  function resolveDelayTestUrl(kind, name) {
    var groupUrl = "";
    if (kind === "group") {
      groupUrl = String(root.proxyGroupTestUrls?.[name] ?? "").trim();
      if (groupUrl)
        return groupUrl;
    }

    var providerUrl = root.resolveProviderDelayTestUrl(name);
    if (providerUrl)
      return providerUrl;

    if (kind === "node") {
      var nodeGroupUrl = root.resolveGroupDelayTestUrlForNode(name);
      if (nodeGroupUrl)
        return nodeGroupUrl;
    }

    return root.delayTestUrl;
  }

  function resolveProviderDelayTestUrl(name) {
    var providerName = String(root.proxiesByName?.[name]?.provider ?? "").trim();
    if (!providerName)
      return "";

    return String(root.proxyProviderTestUrls?.[providerName] ?? "").trim();
  }

  function resolveGroupDelayTestUrlForNode(name) {
    if (!name)
      return "";

    for (var i = 0; i < root.proxyGroups.length; i++) {
      var group = root.proxyGroups[i];
      var nodes = group?.nodes ?? [];
      for (var j = 0; j < nodes.length; j++) {
        if ((nodes[j]?.name ?? "") !== name)
          continue;

        var groupName = String(group?.name ?? "").trim();
        var groupUrl = String(root.proxyGroupTestUrls?.[groupName] ?? "").trim();
        if (groupUrl)
          return groupUrl;
      }
    }

    return "";
  }

  function consumeProxyPayload(result) {
    var proxies = result?.proxies ?? ({});
    root.proxiesByName = proxies;
    var names = Object.keys(proxies);
    var groups = [];
    var expandedByName = Object.assign({}, root.expandedGroupStates);

    for (var i = 0; i < names.length; i++) {
      var name = names[i];
      var entry = proxies[name];
      if (!entry || !entry.all || !Array.isArray(entry.all) || entry.all.length === 0) continue;
      if (!root.isSelectableGroup(entry.type)) continue;

      groups.push({
        name: name,
        label: name,
        icon: entry.type === "Selector" || entry.type === "select" ? "list-filter" : "network",
        type: entry.type ?? "",
        current: entry.now ?? "",
        all: entry.all,
        nodes: root.buildGroupNodes(name, entry, proxies)
      });
    }

    groups.sort(function(a, b) {
      if (a.name === "GLOBAL") return -1;
      if (b.name === "GLOBAL") return 1;
      return a.name.localeCompare(b.name);
    });

    root.proxyGroups = groups;
    root.expandedGroupStates = expandedByName;
    root.restoreDelayCache();
    Qt.callLater(function() {
    root.queueAllDelayTests(false, false);
    });
  }

  function restoreDelayCache() {
    if (!pluginApi || !root.hasGroups || root.delayCacheRestored) return;

    var cacheRoot = pluginApi.pluginSettings?._delayCacheByApi;
    var cached = cacheRoot?.[root.delayCacheScopeKey]?.delayByKey;
    if (!cached || typeof cached !== "object") {
      root.delayCacheRestored = true;
      return;
    }

    var nextDelays = Object.assign({}, root.delayByKey);
    var allowedKeys = root.collectAllowedDelayKeys();
    var keys = Object.keys(cached);

    for (var i = 0; i < keys.length; i++) {
      var key = keys[i];
      if (!allowedKeys[key]) continue;

      var delay = Number(cached[key]);
      if (!isNaN(delay) && delay >= 0)
        nextDelays[key] = delay;
    }

    root.delayByKey = nextDelays;
    root.delayCacheRestored = true;
  }

  function collectAllowedDelayKeys() {
    var allowed = ({});

    for (var i = 0; i < root.proxyGroups.length; i++) {
      var group = root.proxyGroups[i];
      var groupName = group?.name ?? "";
      if (groupName)
        allowed[root.makeDelayKey("group", groupName)] = true;

      var nodes = group?.nodes ?? [];
      for (var j = 0; j < nodes.length; j++) {
        var nodeName = nodes[j]?.name ?? "";
        if (nodeName)
          allowed[root.makeDelayKey("node", nodeName)] = true;
      }
    }

    return allowed;
  }

  function scheduleDelayCacheSave() {
    if (!pluginApi) return;
    delayCacheSaveTimer.restart();
  }

  function persistDelayCache() {
    if (!pluginApi) return;

    var settings = pluginApi.pluginSettings;
    if (!settings) return;

    var allowedKeys = root.collectAllowedDelayKeys();
    var keys = Object.keys(root.delayByKey);
    var cachedDelays = ({});
    var count = 0;

    for (var i = 0; i < keys.length; i++) {
      var key = keys[i];
      if (!allowedKeys[key]) continue;

      var delay = Number(root.delayByKey[key]);
      if (isNaN(delay) || delay < 0) continue;

      cachedDelays[key] = delay;
      count += 1;
      if (count >= root.delayCacheMaxEntries)
        break;
    }

    var cacheByApi = Object.assign({}, settings._delayCacheByApi ?? ({}));
    cacheByApi[root.delayCacheScopeKey] = {
      updatedAt: Math.floor(Date.now() / 1000),
      delayByKey: cachedDelays
    };
    settings._delayCacheByApi = cacheByApi;
    pluginApi.saveSettings();
  }

  function buildGroupNodes(groupName, group, proxies) {
    var items = Array.isArray(group?.all) ? group.all : [];
    return items.map(function(name) {
      var node = proxies[name] ?? ({});
      return {
        name: name,
        groupName: groupName,
        current: name === group?.now,
        selectable: true,
        metaText: root.buildNodeMeta(node)
      };
    });
  }

  function sortProxyGroups(groups) {
    var items = Array.isArray(groups) ? groups.slice() : [];
    items.sort(function(a, b) {
      if ((a?.name ?? "") === "GLOBAL") return -1;
      if ((b?.name ?? "") === "GLOBAL") return 1;

      if (root.sortMode === "delay") {
        var compareByDelay = compareDelayValues(
          root.delayValueForGroup(a?.name ?? "", a?.current ?? ""),
          root.delayValueForGroup(b?.name ?? "", b?.current ?? "")
        );
        if (compareByDelay !== 0) return compareByDelay;
      }

      return compareNames(a?.name ?? "", b?.name ?? "");
    });
    return items;
  }

  function buildGlobalNodes(groups) {
    var nodesResult = [];
    var groupsResult = [];
    var selectedName = root.effectiveGlobalCurrent;
    var seenGroups = ({});
    var seenNodes = ({});

    for (var i = 0; i < groups.length; i++) {
      var group = groups[i];
      var groupName = group?.name ?? "";
      var nodes = group?.nodes ?? [];
      for (var j = 0; j < nodes.length; j++) {
        var node = nodes[j];
        var name = node?.name ?? "";
        if (!name || seenNodes[name]) continue;
        seenNodes[name] = true;

        nodesResult.push({
          kind: "node",
          name: name,
          groupLabel: "Node",
          switchGroupName: "GLOBAL",
          selectable: node.selectable ?? true,
          current: name === selectedName
        });
      }

      if (groupName && groupName !== "GLOBAL" && !seenGroups[groupName] && !seenNodes[groupName]) {
        seenGroups[groupName] = true;
        groupsResult.push({
          kind: "group",
          name: groupName,
          groupLabel: String(group?.type ?? "Group"),
          switchGroupName: "GLOBAL",
          selectable: true,
          current: groupName === selectedName
        });
      }
    }

    return nodesResult.concat(groupsResult);
  }

  function sortGlobalNodes(nodes) {
    var items = Array.isArray(nodes) ? nodes.slice() : [];
    items.sort(function(a, b) {
      if (root.sortMode === "delay") {
        var compareByDelay = compareDelayValues(
          root.delayValueForKey("node", a?.name ?? ""),
          root.delayValueForKey("node", b?.name ?? "")
        );
        if (compareByDelay !== 0) return compareByDelay;
      }

      var compareByName = compareNames(a?.name ?? "", b?.name ?? "");
      if (compareByName !== 0) return compareByName;
      return compareNames(a?.groupLabel ?? "", b?.groupLabel ?? "");
    });
    return items;
  }

  function sortNodes(nodes) {
    var items = Array.isArray(nodes) ? nodes.slice() : [];
    items.sort(function(a, b) {
      if (root.sortMode === "delay") {
        var compareByDelay = compareDelayValues(
          root.delayValueForKey("node", a?.name ?? ""),
          root.delayValueForKey("node", b?.name ?? "")
        );
        if (compareByDelay !== 0) return compareByDelay;
      }

      return compareNames(a?.name ?? "", b?.name ?? "");
    });
    return items;
  }

  function buildNodeMeta(node) {
    var parts = [];
    if (node?.type) parts.push(String(node.type));

    var history = node?.history;
    if (Array.isArray(history) && history.length > 0) {
      var last = history[history.length - 1];
      var delay = last?.delay;
      if (delay !== undefined && delay !== null && Number(delay) > 0)
        parts.push(String(delay) + " ms");
    } else if (node?.delay !== undefined && Number(node.delay) > 0) {
      parts.push(String(node.delay) + " ms");
    }

    return parts.join(" · ");
  }

  function normalizeSortMode(value) {
    return value === "delay" ? "delay" : "name";
  }

  function toggleSortMode() {
    root.sortMode = root.sortMode === "delay" ? "name" : "delay";
    if (!pluginApi) return;

    pluginApi.pluginSettings.sortMode = root.sortMode;
    pluginApi.saveSettings();
  }

  function compareNames(left, right) {
    return String(left ?? "").localeCompare(String(right ?? ""));
  }

  function compareDelayValues(left, right) {
    var leftDelay = Number(left ?? -1);
    var rightDelay = Number(right ?? -1);
    var leftKnown = leftDelay > 0;
    var rightKnown = rightDelay > 0;

    if (leftKnown && rightKnown) {
      if (leftDelay !== rightDelay) return leftDelay - rightDelay;
      return 0;
    }

    if (leftKnown) return -1;
    if (rightKnown) return 1;
    return 0;
  }

  function selectNode(name, groupName) {
    if (!name || !groupName) return;

    root.switching = true;
    root.errorText = "";
    switchNodeProcess.targetNodeName = name;
    switchNodeProcess.targetGroupName = groupName;
    switchNodeProcess.running = false;
    switchNodeProcess.running = true;
  }

  function applySelectedNode(groupName, nodeName) {
    if (!groupName || !nodeName) return;

    var nextProxies = Object.assign({}, root.proxiesByName);
    var proxyEntry = nextProxies[groupName];
    if (proxyEntry)
      nextProxies[groupName] = Object.assign({}, proxyEntry, { now: nodeName });
    root.proxiesByName = nextProxies;

    var nextGroups = root.proxyGroups.slice();
    for (var i = 0; i < nextGroups.length; i++) {
      var group = nextGroups[i];
      if (group?.name !== groupName) continue;

      var nextNodes = [];
      var nodes = group?.nodes ?? [];
      for (var j = 0; j < nodes.length; j++) {
        var node = nodes[j];
        nextNodes.push(Object.assign({}, node, {
          current: (node?.name ?? "") === nodeName
        }));
      }

      nextGroups[i] = Object.assign({}, group, {
        current: nodeName,
        nodes: nextNodes
      });
      break;
    }

    root.proxyGroups = nextGroups;
  }

  function updateGroupExpandedState(name, expanded) {
    if (!name) return;
    if ((root.expandedGroupStates?.[name] ?? false) === expanded) return;

    root.expandedGroupStates = Object.assign({}, root.expandedGroupStates, {
      [name]: expanded
    });
  }

  function isGroupExpanded(name) {
    return root.expandedGroupStates?.[name] ?? false;
  }

  function findGroupIndex(name) {
    for (var i = 0; i < root.proxyGroups.length; i++) {
      if (root.proxyGroups[i]?.name === name) return i;
    }
    return -1;
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

  function findGroup(name) {
    var index = findGroupIndex(name);
    return index >= 0 ? root.proxyGroups[index] : null;
  }

  function resolveProxyTrace(name) {
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

      var entry = root.proxiesByName?.[current];
      if (!entry) break;

      var next = entry.now;
      if (!next || next === current) break;
      current = next;
    }

    result.finalName = chain.length > 0 ? chain[chain.length - 1] : name;
    result.chainText = chain.join(" -> ");
    return result;
  }

  function countNodes(groups) {
    var total = 0;
    for (var i = 0; i < groups.length; i++) {
      var items = groups[i]?.nodes;
      if (Array.isArray(items))
        total += items.length;
    }
    return total;
  }

  function makeDelayKey(kind, name) {
    return String(kind) + ":" + String(name ?? "");
  }

  function formatDelay(kind, name) {
    var key = makeDelayKey(kind, name);
    var delay = delayValueForKey(kind, name);
    if (delay > 0) return String(delay) + " ms";
    if (root.testingByKey?.[key]) return "Testing...";
    return "--";
  }

  function formatGroupDelay(groupName, currentNodeName) {
    var nodeDelay = delayValueForKey("node", currentNodeName);
    if (nodeDelay > 0) return String(nodeDelay) + " ms";
    return root.formatDelay("group", groupName);
  }

  function delayValueForKey(kind, name) {
    var key = makeDelayKey(kind, name);
    return Number(root.delayByKey?.[key] ?? -1);
  }

  function delayValueForGroup(groupName, currentNodeName) {
    var nodeDelay = delayValueForKey("node", currentNodeName);
    if (nodeDelay > 0) return nodeDelay;
    return delayValueForKey("group", groupName);
  }

  function delayColorForValue(delay) {
    if (delay <= 0) return root.delayIdleColor;
    if (delay < 700) return root.delayFastColor;
    if (delay < 1200) return root.delayMediumColor;
    return root.delaySlowColor;
  }

  function isTestingDelay(kind, name) {
    return !!root.testingByKey?.[makeDelayKey(kind, name)];
  }

  function isManualTestingDelay(kind, name) {
    return !!root.manualTestingByKey?.[makeDelayKey(kind, name)];
  }

  function queueDelayTest(kind, name) {
    if (!root.hasApi || !name) return;

    var key = makeDelayKey(kind, name);
    if (root.testingByKey?.[key]) return;

    root.startDelayTest(kind, name, key, true, "item");
  }

  function queueAllDelayTests(clearPrevious, manual) {
    if (!root.hasApi) return;

    var seen = ({});
    if (clearPrevious)
      root.delayByKey = ({});

    if (root.isGlobalMode) {
      for (var i = 0; i < root.globalNodes.length; i++) {
        var globalNode = root.globalNodes[i];
        var globalNodeKey = makeDelayKey("node", globalNode?.name);
        if (!globalNodeKey || seen[globalNodeKey]) continue;
        seen[globalNodeKey] = true;
        if (!root.testingByKey?.[globalNodeKey])
          root.startDelayTest("node", globalNode?.name ?? "", globalNodeKey, manual, manual ? "header" : "silent");
      }
      return;
    }

    for (var groupIndex = 0; groupIndex < root.proxyGroups.length; groupIndex++) {
      var group = root.proxyGroups[groupIndex];
      var groupName = group?.name ?? "";
      var groupKey = makeDelayKey("group", groupName);
      if (!groupName || seen[groupKey]) continue;

      seen[groupKey] = true;
      if (!root.testingByKey?.[groupKey])
        root.startDelayTest("group", groupName, groupKey, manual, manual ? "header" : "silent");

      if (!root.isGroupExpanded(groupName)) continue;

      var nodes = group?.nodes ?? [];
      for (var nodeIndex = 0; nodeIndex < nodes.length; nodeIndex++) {
        var node = nodes[nodeIndex];
        var nodeName = node?.name ?? "";
        var nodeKey = makeDelayKey("node", nodeName);
        if (!nodeName || seen[nodeKey]) continue;

        seen[nodeKey] = true;
        if (!root.testingByKey?.[nodeKey])
          root.startDelayTest("node", nodeName, nodeKey, manual, manual ? "header" : "silent");
      }
    }
  }

  function startDelayTest(kind, name, key, manual, triggerSource) {
    if (!name || !key || root.testingByKey?.[key]) return;

    var process = delayTestProcessComponent.createObject(root, {
      targetKind: kind ?? "",
      targetName: name ?? "",
      targetKey: key,
      manual: !!manual,
      triggerSource: triggerSource ?? "",
      outputBuffer: ""
    });
    if (!process)
      return;

    var nextTesting = Object.assign({}, root.testingByKey);
    nextTesting[key] = true;
    root.testingByKey = nextTesting;

    if (manual) {
      var nextManualTesting = Object.assign({}, root.manualTestingByKey);
      nextManualTesting[key] = true;
      root.manualTestingByKey = nextManualTesting;

      if (triggerSource === "header") {
        var nextHeaderTesting = Object.assign({}, root.headerTestingByKey);
        nextHeaderTesting[key] = true;
        root.headerTestingByKey = nextHeaderTesting;
      }
    }

    var nextProcesses = Object.assign({}, root.activeDelayTestProcesses);
    nextProcesses[key] = process;
    root.activeDelayTestProcesses = nextProcesses;

    process.running = true;
  }

  function finishDelayTest(process, code) {
    if (!process) return;

    var key = process.targetKey;
    var nextTesting = Object.assign({}, root.testingByKey);
    delete nextTesting[key];
    root.testingByKey = nextTesting;

    var nextManualTesting = Object.assign({}, root.manualTestingByKey);
    delete nextManualTesting[key];
    root.manualTestingByKey = nextManualTesting;

    var nextHeaderTesting = Object.assign({}, root.headerTestingByKey);
    delete nextHeaderTesting[key];
    root.headerTestingByKey = nextHeaderTesting;

    var nextProcesses = Object.assign({}, root.activeDelayTestProcesses);
    delete nextProcesses[key];
    root.activeDelayTestProcesses = nextProcesses;

    if (code === 0) {
      try {
        var result = JSON.parse(process.outputBuffer || "{}");
        root.applyDelayResult(process.targetKind, process.targetName, key, result);
      } catch (e) {
      }
    }

    root.scheduleDelayCacheSave();
    process.outputBuffer = "";
    process.destroy();
  }

  function applyDelayResult(kind, name, key, result) {
    var nextDelays = Object.assign({}, root.delayByKey);

    if (kind === "group") {
      var entries = ({});
      var allowedNames = ({});
      allowedNames[name] = true;

      var group = root.proxiesByName?.[name];
      var items = Array.isArray(group?.all) ? group.all : [];
      for (var i = 0; i < items.length; i++) {
        var itemName = items[i];
        if (itemName)
          allowedNames[itemName] = true;
      }

      root.collectNamedDelayValues(result, allowedNames, entries);

      var entryNames = Object.keys(entries);
      for (var index = 0; index < entryNames.length; index++) {
        var entryName = entryNames[index];
        var delay = entries[entryName];
        nextDelays[root.makeDelayKey("group", entryName)] = delay;
        nextDelays[root.makeDelayKey("node", entryName)] = delay;
      }

      var currentName = group?.now ?? "";
      if (entries[name] === undefined && currentName && entries[currentName] !== undefined)
        nextDelays[key] = entries[currentName];
      else if (entries[name] === undefined && nextDelays[key] === undefined)
        nextDelays[key] = 0;
    } else {
      var delay = root.extractDelayValue(result);
      nextDelays[key] = delay > 0 ? delay : 0;
    }

    root.delayByKey = nextDelays;
  }

  function collectNamedDelayValues(value, allowedNames, output) {
    if (value === null || value === undefined) return;

    if (Array.isArray(value)) {
      for (var i = 0; i < value.length; i++)
        root.collectNamedDelayValues(value[i], allowedNames, output);
      return;
    }

    if (typeof value !== "object") return;

    var keys = Object.keys(value);
    for (var index = 0; index < keys.length; index++) {
      var key = keys[index];
      var child = value[key];

      if (allowedNames?.[key]) {
        var delay = root.extractDelayValue(child);
        if (delay >= 0)
          output[key] = delay;
      }

      root.collectNamedDelayValues(child, allowedNames, output);
    }
  }

  function extractDelayValue(value) {
    if (typeof value === "number" && isFinite(value))
      return value > 0 ? value : 0;

    if (!value || typeof value !== "object")
      return -1;

    var directDelay = Number(value.delay);
    if (!isNaN(directDelay))
      return directDelay > 0 ? directDelay : 0;

    var history = value.history;
    if (Array.isArray(history) && history.length > 0) {
      var last = history[history.length - 1];
      var historyDelay = Number(last?.delay);
      if (!isNaN(historyDelay))
        return historyDelay > 0 ? historyDelay : 0;
    }

    return -1;
  }
}
