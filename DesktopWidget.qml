import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Widgets

DraggableDesktopWidget {
  id: root
  property var pluginApi: null

  readonly property var cfg: pluginApi?.pluginSettings ?? ({})
  readonly property var defaults: pluginApi?.manifest?.metadata?.defaultSettings ?? ({})
  readonly property string currentProxyName: cfg._currentProxyName ?? (pluginApi?.tr("widget.runtime.unknown") || "Unknown")
  readonly property string routingMode: cfg._routingMode ?? "rule"

  implicitWidth: 240
  implicitHeight: 96

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.marginL
    spacing: Style.marginS

    NText {
      text: root.currentProxyName
      font.pointSize: Style.fontSizeM
      Layout.alignment: Qt.AlignHCenter
      elide: Text.ElideRight
      Layout.fillWidth: true
      horizontalAlignment: Text.AlignHCenter
    }

    NText {
      text: (pluginApi?.tr("widget.runtime.mode") || "Mode") + ": " + root.formatMode(root.routingMode)
      font.pointSize: Style.fontSizeS
      color: Color.mOnSurfaceVariant
      Layout.alignment: Qt.AlignHCenter
    }
  }

  function formatMode(mode) {
    var normalized = String(mode ?? "rule").toLowerCase();
    if (normalized === "global") return pluginApi?.tr("panel.routing-modes.global") || "Global";
    if (normalized === "direct") return pluginApi?.tr("panel.routing-modes.direct") || "Direct";
    return pluginApi?.tr("panel.routing-modes.rule") || "Rule";
  }

}
