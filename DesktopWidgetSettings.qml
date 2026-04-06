import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null
  property var widgetSettings: null

  spacing: Style.marginM

  Component.onCompleted: {
    Logger.d("Clashia", "Desktop Widget Settings UI loaded");
  }

  ColumnLayout {
    spacing: Style.marginM
    Layout.fillWidth: true

    NText {
      Layout.fillWidth: true
      wrapMode: Text.WordWrap
      text: pluginApi?.tr("settings.desktopWidget.empty") || "Desktop widget has no configurable settings."
      color: Color.mOnSurfaceVariant
    }
  }
}
