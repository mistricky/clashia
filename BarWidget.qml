import QtQuick
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

NIconButton {
  id: root

  property var pluginApi: null

  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  readonly property string iconColorKey: cfg.iconColor ?? defaults.iconColor

  icon: ""
  tooltipText: root.buildTooltip()
  tooltipDirection: BarService.getTooltipDirection(screen?.name)
  baseSize: Style.getCapsuleHeightForScreen(screen?.name)
  applyUiScale: false
  customRadius: Style.radiusL
  colorBg: Style.capsuleColor
  colorFg: Color.resolveColorKey(iconColorKey)

  border.color: Style.capsuleBorderColor
  border.width: Style.capsuleBorderWidth

  // Custom SVG logo icon
  Image {
    readonly property real iconSize: Style.toOdd(root.buttonSize * 0.68)
    width: iconSize
    height: iconSize
    anchors.centerIn: parent
    source: pluginApi ? pluginApi.pluginDir + (Settings.data.colorSchemes.darkMode ? "/logo_dark.svg" : "/logo.svg") : ""
    fillMode: Image.PreserveAspectFit
    sourceSize.width: iconSize
    sourceSize.height: iconSize
    smooth: true
    antialiasing: true
  }

  onClicked: {
    if (pluginApi) {
      pluginApi.openPanel(root.screen, this);
    }
  }

  NPopupContextMenu {
    id: contextMenu

    model: [
      {
        "label": pluginApi?.tr("menu.settings"),
        "action": "settings",
        "icon": "settings"
      },
    ]

    onTriggered: function (action) {
      contextMenu.close();
      PanelService.closeContextMenu(screen);
      if (action === "settings") {
        BarService.openPluginSettings(root.screen, pluginApi.manifest);
      }
    }
  }

  onRightClicked: {
    PanelService.showContextMenu(contextMenu, root, screen);
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
