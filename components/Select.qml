import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

Item {
  id: root

  property var model: []
  property int currentIndex: 0
  property bool enabled: true
  property string placeholderText: "Select"
  property real menuMaxHeight: 220 * Style.uiScaleRatio
  property bool open: false

  readonly property var currentItem: {
    if (!model || currentIndex < 0 || currentIndex >= model.length) return null;
    return model[currentIndex];
  }
  readonly property string currentLabel: {
    var item = currentItem;
    if (!item) return placeholderText;
    if (typeof item === "string") return item;
    return item?.label ?? placeholderText;
  }
  readonly property string currentIcon: {
    var item = currentItem;
    if (!item || typeof item === "string") return "";
    return item?.icon ?? "";
  }
  readonly property real cornerRadius: Style.radiusL
  readonly property color frameColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.08 : 0.06)
  readonly property color frameBorderColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.09 : 0.07)
  readonly property color panelColor: Qt.alpha(Color.mSurface, Settings.data.colorSchemes.darkMode ? 0.96 : 0.98)
  readonly property color panelBorderColor: Qt.alpha(Color.mOnSurface, Settings.data.colorSchemes.darkMode ? 0.10 : 0.08)

  signal selected(int index, var item)

  implicitWidth: 180 * Style.uiScaleRatio
  implicitHeight: triggerContent.implicitHeight + Style.marginS * 2

  Rectangle {
    anchors.fill: parent
    color: root.frameColor
    radius: root.cornerRadius
    border.color: root.frameBorderColor
    border.width: 1
  }

  RowLayout {
    id: triggerContent

    anchors.fill: parent
    anchors.leftMargin: Style.marginM
    anchors.rightMargin: Style.marginM
    anchors.topMargin: Style.marginS
    anchors.bottomMargin: Style.marginS
    spacing: Style.marginS

    NIcon {
      visible: root.currentIcon !== ""
      icon: root.currentIcon
      pointSize: Math.round(Style.fontSizeS * 1.1)
      color: Color.mOnSurface
      opacity: root.enabled ? 1 : 0.45
    }

    NText {
      Layout.fillWidth: true
      text: root.currentLabel
      elide: Text.ElideRight
      font.pointSize: Style.fontSizeS
      color: Color.mOnSurface
      opacity: root.currentItem ? (root.enabled ? 1 : 0.45) : 0.6
    }

    NIcon {
      icon: root.open ? "chevron-up" : "chevron-down"
      pointSize: Math.round(Style.fontSizeS * 1.05)
      color: Color.mOnSurface
      opacity: root.enabled ? 0.78 : 0.45
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: root.enabled
    hoverEnabled: true
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: {
      if (menuPopup.opened)
        menuPopup.close();
      else
        menuPopup.open();
    }
  }

  Popup {
    id: menuPopup

    parent: root
    x: 0
    y: root.height + Style.marginXS
    width: root.width
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    padding: 0
    modal: false

    onOpened: root.open = true
    onClosed: root.open = false

    background: Rectangle {
      color: root.panelColor
      radius: root.cornerRadius
      border.color: root.panelBorderColor
      border.width: 1
    }

    contentItem: Flickable {
      id: menuFlick

      implicitHeight: Math.min(root.menuMaxHeight, menuColumn.implicitHeight)
      contentHeight: menuColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: menuColumn

        width: menuPopup.width
        spacing: 0

        Repeater {
          model: root.model

          delegate: Item {
            id: optionItem

            required property int index
            required property var modelData

            readonly property bool selected: root.currentIndex === index
            readonly property bool enabled: root.resolveEnabled(modelData)
            property bool hovered: false

            width: menuColumn.width
            implicitHeight: optionContent.implicitHeight + Style.marginS * 2

            Rectangle {
              anchors.fill: parent
              anchors.leftMargin: Style.marginXS
              anchors.rightMargin: Style.marginXS
              anchors.topMargin: Math.max(2, Style.marginXS / 2)
              anchors.bottomMargin: Math.max(2, Style.marginXS / 2)
              radius: 0
              color: "transparent"
            }

            RowLayout {
              id: optionContent

              anchors.fill: parent
              anchors.leftMargin: Style.marginM
              anchors.rightMargin: Style.marginM
              anchors.topMargin: Style.marginS
              anchors.bottomMargin: Style.marginS
              spacing: Style.marginS

              NIcon {
                visible: root.resolveIcon(optionItem.modelData) !== ""
                icon: root.resolveIcon(optionItem.modelData)
                pointSize: Math.round(Style.fontSizeS * 1.1)
                color: Color.mOnSurface
                opacity: optionLabel.opacity
              }

              NText {
                id: optionLabel

                Layout.fillWidth: true
                text: root.resolveLabel(optionItem.modelData)
                elide: Text.ElideRight
                font.pointSize: Style.fontSizeS
                color: Color.mOnSurface
                opacity: {
                  if (!optionItem.enabled) return 0.45;
                  if (optionItem.selected || optionItem.hovered) return 1;
                  return 0.72;
                }
              }

              NIcon {
                visible: optionItem.selected
                icon: "check"
                pointSize: Math.round(Style.fontSizeS)
                color: Color.mOnSurface
              }
            }

            MouseArea {
              anchors.fill: parent
              enabled: optionItem.enabled
              hoverEnabled: true
              cursorShape: optionItem.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              onEntered: optionItem.hovered = true
              onExited: optionItem.hovered = false
              onClicked: {
                root.currentIndex = optionItem.index;
                root.selected(optionItem.index, optionItem.modelData);
                menuPopup.close();
              }
            }
          }
        }
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
