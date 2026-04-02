import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property bool systemProxyEnabled: false
  property bool tunEnabled: false
  property string systemProxyLabel: "System Proxy"
  property string tunLabel: "TUN"
  property string globalRoutingLabel: "Global routing"
  property string globalRoutingMode: "rule"
  property var globalRoutingModel: [
    { key: "rule", label: "Rule" },
    { key: "global", label: "Global" },
    { key: "direct", label: "Direct" }
  ]

  signal systemProxyToggled(bool checked)
  signal tunToggled(bool checked)
  signal globalRoutingSelected(string key)

  Layout.fillWidth: true
  spacing: Style.marginXS

  function setToggleLabelSize(toggle) {
    var labelContainer = toggle.children[0];
    if (labelContainer) {
      labelContainer.labelSize = Style.fontSizeS;

      var rowItem = labelContainer.children[0];
      var iconItem = rowItem?.children[0];
      var textItem = rowItem?.children[1];
      if (iconItem) {
        iconItem.pointSize = Style.fontSizeS;
        iconItem.color = Qt.binding(function() {
          return textItem?.color ?? Color.mOnSurface;
        });
      }
    }
  }

  function globalRoutingIndex() {
    for (var i = 0; i < root.globalRoutingModel.length; i++) {
      if (root.globalRoutingModel[i]?.key === root.globalRoutingMode) {
        return i;
      }
    }

    return 0;
  }

  NToggle {
    label: root.systemProxyLabel
    icon: "world"
    checked: root.systemProxyEnabled
    defaultValue: false
    baseSize: Math.round(Style.baseWidgetSize * 0.6 * Style.uiScaleRatio)
    Component.onCompleted: root.setToggleLabelSize(this)
    onToggled: checked => root.systemProxyToggled(checked)
  }

  NToggle {
    label: root.tunLabel
    icon: "shield"
    checked: root.tunEnabled
    defaultValue: false
    baseSize: Math.round(Style.baseWidgetSize * 0.6 * Style.uiScaleRatio)
    Component.onCompleted: root.setToggleLabelSize(this)
    onToggled: checked => root.tunToggled(checked)
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NIcon {
      icon: "settings"
      pointSize: Style.fontSizeS
      color: Color.mOnSurface
    }

    NText {
      text: root.globalRoutingLabel
      font.pointSize: Style.fontSizeS
      font.weight: Font.DemiBold
      color: Color.mOnSurface
      Layout.fillWidth: true
    }

    Select {
      Layout.preferredWidth: 84
      model: root.globalRoutingModel
      currentIndex: root.globalRoutingIndex()
      onSelected: (_, item) => root.globalRoutingSelected(item?.key ?? "rule")
    }
  }
}
