import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property bool hasSubscription: false
  property bool hasSubData: false
  property string emptyText: ""
  property string noDataText: ""
  property string subscriptionName: ""
  property string usageText: ""
  property real progressValue: 0

  Layout.fillWidth: true
  spacing: Math.max(3, Style.marginXS)

  NText {
    visible: !root.hasSubscription
    Layout.fillWidth: true
    horizontalAlignment: Text.AlignHCenter
    text: root.emptyText
    font.pointSize: Style.fontSizeS
    color: Color.mOnSurfaceVariant
  }

  NText {
    visible: root.hasSubscription && !root.hasSubData
    Layout.fillWidth: true
    horizontalAlignment: Text.AlignHCenter
    text: root.noDataText
    font.pointSize: Style.fontSizeS
    color: Color.mOnSurfaceVariant
  }

  RowLayout {
    visible: root.hasSubscription && root.hasSubData
    Layout.fillWidth: true
    spacing: Style.marginS

    NIcon {
      Layout.preferredWidth: 18
      Layout.preferredHeight: 18
      Layout.alignment: Qt.AlignVCenter
      icon: "plane"
      color: Color.mOnSurface
    }

    NText {
      text: root.subscriptionName
      font.pointSize: Style.fontSizeS
      color: Color.mOnSurface
      Layout.fillWidth: true
      elide: Text.ElideRight
    }

    NText {
      text: root.usageText
      font.pointSize: Style.fontSizeS
      color: Qt.alpha(Color.mOnSurface, 0.88)
    }
  }

  Rectangle {
    visible: root.hasSubscription && root.hasSubData
    Layout.fillWidth: true
    Layout.preferredHeight: 3
    Layout.topMargin: Style.marginXS
    Layout.leftMargin: Style.marginS
    Layout.rightMargin: Style.marginS
    radius: 1.5
    color: Qt.alpha(Color.mOnSurface, 0.06)

    Rectangle {
      width: parent.width * Math.max(0, Math.min(1, root.progressValue))
      height: parent.height
      radius: parent.radius
      color: Color.mPrimary

      Behavior on width {
        NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
      }
    }
  }
}
