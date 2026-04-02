import QtQuick
import Quickshell
import qs.Widgets

NIconButtonHot {
  id: root

  property ShellScreen screen
  property var pluginApi: null
  readonly property var cfg: pluginApi?.pluginSettings ?? ({})

  icon: "noctalia"
  tooltipText: root.buildTooltip()
  onClicked: {
    if (pluginApi) {
      pluginApi.togglePanel(screen, this);
    }
  }

  function buildTooltip() {
    var proxyName = cfg._currentProxyName ?? (pluginApi?.tr("widget.runtime.unknown") || "Unknown");
    var mode = formatMode(cfg._routingMode ?? "rule");
    return formatLine(pluginApi?.tr("widget.runtime.proxy") || "Proxy", proxyName)
      + "\n" + formatLine(pluginApi?.tr("widget.runtime.mode") || "Mode", mode);
  }

  function formatMode(mode) {
    var normalized = String(mode ?? "rule").toLowerCase();
    if (normalized === "global") return pluginApi?.tr("panel.routing-modes.global") || "Global";
    if (normalized === "direct") return pluginApi?.tr("panel.routing-modes.direct") || "Direct";
    return pluginApi?.tr("panel.routing-modes.rule") || "Rule";
  }

  function formatLine(label, value) {
    return label + "    " + value;
  }
}
