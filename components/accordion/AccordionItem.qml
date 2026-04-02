import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root

  property string title: ""
  property string description: ""
  property string metaText: ""
  property string icon: ""
  property bool expanded: false
  property bool disabled: false
  property bool showTopBorder: true
  property real horizontalPadding: Style.marginM
  property real verticalPadding: Style.marginM
  property real contentTopPadding: Math.max(6, Style.marginXS)

  default property alias contentData: contentColumn.data

  readonly property color borderColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.10 : 0.08)
  readonly property color triggerColor: triggerArea.containsMouse && !root.disabled ?
    Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.06 : 0.04) : "transparent"
  readonly property color triggerTextColor: root.disabled ? Qt.alpha(Color.mOnSurface, 0.45) : Color.mOnSurface

  implicitHeight: layout.implicitHeight

  Rectangle {
    id: frame

    anchors.fill: parent
    color: "transparent"
    radius: Style.radiusM
    border.width: 0
  }

  ColumnLayout {
    id: layout

    anchors.fill: parent
    spacing: 0

    Rectangle {
      Layout.fillWidth: true
      height: 1
      color: root.borderColor
      visible: root.showTopBorder
    }

    Rectangle {
      Layout.fillWidth: true
      implicitHeight: triggerRow.implicitHeight + root.verticalPadding * 2
      radius: Style.radiusM
      color: root.triggerColor

      Behavior on color {
        ColorAnimation {
          duration: 140
        }
      }

      RowLayout {
        id: triggerRow

        anchors.fill: parent
        anchors.leftMargin: root.horizontalPadding
        anchors.rightMargin: root.horizontalPadding
        anchors.topMargin: root.verticalPadding
        anchors.bottomMargin: root.verticalPadding
        spacing: Style.marginS

        NIcon {
          visible: root.icon !== ""
          icon: root.icon
          pointSize: Math.round(Style.fontSizeS * 1.1)
          color: root.triggerTextColor
          opacity: 0.88
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Math.max(2, Style.marginXS / 2)

          NText {
            Layout.fillWidth: true
            text: root.title
            elide: Text.ElideRight
            font.pointSize: Style.fontSizeS
            font.weight: Font.DemiBold
            color: root.triggerTextColor
          }

          NText {
            Layout.fillWidth: true
            text: root.description
            wrapMode: Text.WordWrap
            font.pointSize: Style.fontSizeS * 0.92
            color: Qt.alpha(root.triggerTextColor, 0.68)
            visible: text !== ""
          }
        }

        NText {
          text: root.metaText
          font.pointSize: Style.fontSizeS * 0.9
          color: Qt.alpha(root.triggerTextColor, 0.62)
          visible: text !== ""
        }

        Item {
          Layout.preferredWidth: 20 * Style.uiScaleRatio
          Layout.preferredHeight: 20 * Style.uiScaleRatio
          transformOrigin: Item.Center
          rotation: root.expanded ? 90 : 0

          Behavior on rotation {
            NumberAnimation {
              duration: 160
              easing.type: Easing.OutCubic
            }
          }

          NIcon {
            anchors.centerIn: parent
            icon: "chevron-right"
            pointSize: Math.round(Style.fontSizeS * 1.05)
            color: Qt.alpha(root.triggerTextColor, 0.78)
          }
        }
      }

      MouseArea {
        id: triggerArea

        anchors.fill: parent
        enabled: !root.disabled
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.expanded = !root.expanded
      }
    }

    Item {
      Layout.fillWidth: true
      implicitHeight: contentWrapper.implicitHeight

      Item {
        id: contentWrapper

        width: parent.width
        height: root.expanded ? contentColumn.implicitHeight + root.contentTopPadding : 0
        clip: true
        opacity: root.expanded ? 1 : 0
        implicitHeight: height

        Behavior on height {
          NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
          }
        }

        Behavior on opacity {
          NumberAnimation {
            duration: 120
          }
        }

        Column {
          id: contentColumn

          width: parent.width
          y: root.contentTopPadding
          spacing: Style.marginXS
        }
      }
    }
  }
}
