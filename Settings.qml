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

  property string valueConfigPath: cfg.configPath ?? defaults.configPath

  spacing: Style.marginL

  Component.onCompleted: {
    Logger.d("Clashia", "Settings UI loaded");
  }

  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

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

    pluginApi.pluginSettings.configPath = root.valueConfigPath.trim();
    pluginApi.saveSettings();

    Logger.d("Clashia", "Settings saved successfully");
  }
}
