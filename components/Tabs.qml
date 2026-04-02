import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var model: []
  property int currentIndex: 0
  property int visualIndex: currentIndex
  property bool fillWidth: true
  property real framePadding: Math.max(4, Style.marginXS)
  property real tabSpacing: Math.max(4, Style.marginXS)
  property real tabHorizontalPadding: Style.marginM
  property real tabVerticalPadding: Math.max(6, Style.marginS)

  readonly property real cornerRadius: Style.radiusL
  readonly property color frameColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.08 : 0.06)
  readonly property color frameBorderColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.09 : 0.07)
  readonly property color activeColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.13 : 0.09)
  readonly property color activeBorderColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.12 : 0.08)
  property real indicatorX: framePadding
  property real indicatorWidth: 0

  signal activated(int index, var item)

  Layout.topMargin: Style.marginM
  implicitWidth: tabRow.implicitWidth + root.framePadding * 2
  implicitHeight: tabRow.implicitHeight + root.framePadding * 2

  Component.onCompleted: Qt.callLater(updateIndicator)
  onCurrentIndexChanged: visualIndex = currentIndex
  onVisualIndexChanged: Qt.callLater(updateIndicator)
  onWidthChanged: Qt.callLater(updateIndicator)
  onHeightChanged: Qt.callLater(updateIndicator)
  onModelChanged: Qt.callLater(updateIndicator)

  Rectangle {
    id: frame

    anchors.fill: parent
    color: root.frameColor
    radius: root.cornerRadius
    border.color: root.frameBorderColor
    border.width: 1
  }

  Rectangle {
    id: activeIndicator

    x: root.indicatorX
    y: root.framePadding
    width: root.indicatorWidth
    height: Math.max(0, root.height - root.framePadding * 2)
    radius: Math.max(Style.radiusM, root.cornerRadius - root.framePadding)
    color: root.activeColor
    border.color: root.activeBorderColor
    border.width: root.indicatorWidth > 0 ? 1 : 0

    Behavior on x {
      NumberAnimation {
        duration: 170
        easing.type: Easing.OutCubic
      }
    }

    Behavior on width {
      NumberAnimation {
        duration: 230
        easing.type: Easing.OutQuart
      }
    }
  }

  RowLayout {
    id: tabRow

    anchors.fill: parent
    anchors.margins: root.framePadding
    spacing: root.tabSpacing

    Repeater {
      model: root.model

      delegate: Item {
        id: tabButton

        required property int index
        required property var modelData

        readonly property bool selected: root.visualIndex === index
        readonly property bool enabled: root.resolveEnabled(modelData)
        property bool hovered: false
        readonly property color labelColor: Color.mOnSurface

        Layout.fillWidth: root.fillWidth
        Layout.preferredWidth: 1
        implicitWidth: tabContent.implicitWidth + root.tabHorizontalPadding * 2
        implicitHeight: tabContent.implicitHeight + root.tabVerticalPadding * 2

        Rectangle {
          anchors.fill: parent
          color: "transparent"
          radius: Math.max(Style.radiusM, root.cornerRadius - root.framePadding)
          border.color: "transparent"
          border.width: 0
        }

        RowLayout {
          id: tabContent

          anchors.centerIn: parent
          spacing: Style.marginXS

          NIcon {
            visible: root.resolveIcon(tabButton.modelData) !== ""
            icon: root.resolveIcon(tabButton.modelData)
            pointSize: Math.round(Style.fontSizeS * 1.15)
            color: tabButton.labelColor
            opacity: tabLabel.opacity
          }

          NText {
            id: tabLabel

            text: root.resolveLabel(tabButton.modelData)
            font.pointSize: Style.fontSizeS
            font.weight: tabButton.selected ? Font.DemiBold : Font.Medium
            color: tabButton.labelColor
            opacity: {
              if (!tabButton.enabled) return 0.45;
              if (tabButton.hovered) return 1;
              return tabButton.selected ? 1 : 0.68;
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          enabled: tabButton.enabled
          hoverEnabled: true
          cursorShape: tabButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onEntered: tabButton.hovered = true
          onExited: tabButton.hovered = false
          onClicked: {
            if (root.visualIndex === tabButton.index) return;
            root.visualIndex = tabButton.index;
            root.activated(tabButton.index, tabButton.modelData);
          }
        }

        Behavior on opacity {
          NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
          }
        }

        opacity: tabButton.enabled ? 1 : 0.65
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

  function updateIndicator() {
    var target = tabRow.children[root.visualIndex];
    if (!target) return;

    root.indicatorX = root.framePadding + target.x;
    root.indicatorWidth = target.width;
  }
}
