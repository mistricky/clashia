import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var model: []
  property int currentIndex: 0
  property int visualIndex: currentIndex
  property bool fillWidth: false
  property real framePadding: Math.max(4, Style.marginXS)
  property real buttonSpacing: Math.max(4, Style.marginXS)
  property real buttonHorizontalPadding: Style.marginM
  property real buttonVerticalPadding: Math.max(6, Style.marginS)

  readonly property real cornerRadius: Style.radiusL
  readonly property color frameColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.08 : 0.06)
  readonly property color frameBorderColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.09 : 0.07)
  readonly property color activeColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.13 : 0.09)
  readonly property color activeBorderColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.12 : 0.08)

  signal activated(int index, var item)

  implicitWidth: buttonRow.implicitWidth + root.framePadding * 2
  implicitHeight: buttonRow.implicitHeight + root.framePadding * 2

  Component.onCompleted: visualIndex = currentIndex
  onCurrentIndexChanged: visualIndex = currentIndex

  Rectangle {
    anchors.fill: parent
    color: root.frameColor
    radius: root.cornerRadius
    border.color: root.frameBorderColor
    border.width: 1
  }

  RowLayout {
    id: buttonRow

    anchors.fill: parent
    anchors.margins: root.framePadding
    spacing: root.buttonSpacing

    Repeater {
      model: root.model

      delegate: Item {
        id: buttonItem

        required property int index
        required property var modelData

        readonly property bool selected: root.visualIndex === index
        readonly property bool enabled: root.resolveEnabled(modelData)
        property bool hovered: false
        readonly property color labelColor: Color.mOnSurface

        Layout.fillWidth: root.fillWidth
        Layout.preferredWidth: root.fillWidth ? 1 : implicitWidth
        implicitWidth: buttonContent.implicitWidth + root.buttonHorizontalPadding * 2
        implicitHeight: buttonContent.implicitHeight + root.buttonVerticalPadding * 2

        Rectangle {
          anchors.fill: parent
          radius: Math.max(Style.radiusM, root.cornerRadius - root.framePadding)
          color: buttonItem.selected ? root.activeColor : "transparent"
          border.color: buttonItem.selected ? root.activeBorderColor : "transparent"
          border.width: buttonItem.selected ? 1 : 0

          Behavior on color {
            ColorAnimation {
              duration: 160
              easing.type: Easing.OutCubic
            }
          }
        }

        RowLayout {
          id: buttonContent

          anchors.centerIn: parent
          spacing: Style.marginXS

          NIcon {
            visible: root.resolveIcon(buttonItem.modelData) !== ""
            icon: root.resolveIcon(buttonItem.modelData)
            pointSize: Math.round(Style.fontSizeS * 1.15)
            color: buttonItem.labelColor
            opacity: buttonLabel.opacity
          }

          NText {
            id: buttonLabel

            text: root.resolveLabel(buttonItem.modelData)
            font.pointSize: Style.fontSizeS
            font.weight: buttonItem.selected ? Font.DemiBold : Font.Medium
            color: buttonItem.labelColor
            opacity: {
              if (!buttonItem.enabled) return 0.45;
              if (buttonItem.hovered) return 1;
              return buttonItem.selected ? 1 : 0.68;
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          enabled: buttonItem.enabled
          hoverEnabled: true
          cursorShape: buttonItem.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onEntered: buttonItem.hovered = true
          onExited: buttonItem.hovered = false
          onClicked: {
            if (root.visualIndex === buttonItem.index) return;
            root.visualIndex = buttonItem.index;
            root.activated(buttonItem.index, buttonItem.modelData);
          }
        }

        opacity: buttonItem.enabled ? 1 : 0.65
      }
    }
  }

  function resolveLabel(item) {
    if (typeof item === "string") return item;
    return item?.label ?? "";
  }

  function resolveIcon(item) {
    if (typeof item === "string") return "";
    return item?.icon ?? "";
  }

  function resolveEnabled(item) {
    if (typeof item === "string") return true;
    return item?.enabled ?? true;
  }
}
