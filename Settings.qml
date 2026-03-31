import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  property var cfg: pluginApi?.pluginSettings || ({})
  property var defaults: pluginApi?.manifest?.metadata?.defaultSettings || ({})

  property string valueMessage: cfg.message ?? defaults.message
  property string valueIconColor: cfg.iconColor ?? defaults.iconColor
  property string valueConfigPath: cfg.configPath ?? defaults.configPath
  property string valueSubscriptionUrl: cfg.subscriptionUrl ?? defaults.subscriptionUrl

  spacing: Style.marginL

  Component.onCompleted: {
    Logger.d("Clashia", "Settings UI loaded");
  }

  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    NComboBox {
      label: pluginApi?.tr("settings.iconColor.label")
      description: pluginApi?.tr("settings.iconColor.desc")
      model: Color.colorKeyModel
      currentKey: root.valueIconColor
      onSelected: key => root.valueIconColor = key
    }

    NTextInput {
      Layout.fillWidth: true
      label: pluginApi?.tr("settings.message.label")
      description: pluginApi?.tr("settings.message.desc")
      placeholderText: pluginApi?.tr("settings.message.placeholder")
      text: root.valueMessage
      onTextChanged: root.valueMessage = text
    }

    NTextInput {
      Layout.fillWidth: true
      label: pluginApi?.tr("settings.subscriptionUrl.label")
      description: pluginApi?.tr("settings.subscriptionUrl.desc")
      placeholderText: pluginApi?.tr("settings.subscriptionUrl.placeholder")
      text: root.valueSubscriptionUrl
      onTextChanged: root.valueSubscriptionUrl = text
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NText {
        text: pluginApi?.tr("settings.configPath.label") || "Config Path"
        font.pointSize: Style.fontSizeM * Style.uiScaleRatio
        font.weight: Font.Medium
        color: Color.mOnSurface
      }

      NText {
        text: pluginApi?.tr("settings.configPath.desc") || ""
        font.pointSize: Style.fontSizeS
        color: Color.mOnSurfaceVariant
        visible: text !== ""
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        NTextInput {
          id: configPathInput
          Layout.fillWidth: true
          placeholderText: pluginApi?.tr("settings.configPath.placeholder") || "~/.config/mihomo/config.yaml"
          text: root.valueConfigPath
          onTextChanged: root.valueConfigPath = text
        }

        NButton {
          text: pluginApi?.tr("settings.configPath.browse") || "Browse"
          icon: "folder-open"

          onClicked: {
            filePickerProcess.running = true;
          }
        }
      }
    }
  }

  Process {
    id: filePickerProcess
    command: [
      "zenity",
      "--file-selection",
      "--title=" + (pluginApi?.tr("settings.configPath.dialogTitle") || "Select Clashia Config File"),
      "--file-filter=YAML files (*.yaml *.yml) | *.yaml *.yml",
      "--file-filter=All files (*) | *"
    ]
    stdout: SplitParser {
      onRead: data => {
        const path = data.trim();

        if (path !== "") {
          root.valueConfigPath = path;
          configPathInput.text = path;
        }
      }
    }
  }

  function saveSettings() {
    if (!pluginApi) {
      Logger.e("Clashia", "Cannot save settings: pluginApi is null");
      return;
    }

    pluginApi.pluginSettings.message = root.valueMessage;
    pluginApi.pluginSettings.iconColor = root.valueIconColor;
    pluginApi.pluginSettings.configPath = root.valueConfigPath.trim();
    pluginApi.pluginSettings.subscriptionUrl = root.valueSubscriptionUrl.trim();
    pluginApi.saveSettings();

    Logger.d("Clashia", "Settings saved successfully");
  }
}
