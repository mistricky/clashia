import QtQuick
import QtQuick.Layouts
import qs.Commons

Column {
  id: root

  default property alias contentData: container.data
  property real itemSpacing: Math.max(6, Style.marginXS)

  width: parent ? parent.width : implicitWidth
  spacing: root.itemSpacing

  Column {
    id: container

    width: parent.width
    spacing: root.itemSpacing
  }
}
