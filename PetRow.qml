import QtQuick
import qs.Commons
import qs.Ui

CursorSurface {
  id: row

  required property var modelData
  property string fontFamily: Style.font.family
  property bool smoothScaling: true
  property bool selected: false
  property color foreground: Style.textPrimary

  signal clicked()

  readonly property string petName: modelData && modelData.displayName ? modelData.displayName : ""
  readonly property string petKind: modelData && modelData.kind ? modelData.kind : ""
  readonly property url thumbSource: modelData ? (modelData.thumbUrl || modelData.sheetUrl || "") : ""

  hasCursor: mouse.containsMouse
  width: parent && parent.width ? parent.width : implicitWidth
  implicitHeight: content.implicitHeight + Style.spacing.md * 2

  Row {
    id: content
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.rowPaddingX
    spacing: Style.spacing.rowGap

    Image {
      anchors.verticalCenter: parent.verticalCenter
      height: Style.space(36)
      width: height * 192 / 208
      source: row.thumbSource
      fillMode: Image.PreserveAspectFit
      smooth: row.smoothScaling
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.spacing.labelGap

      Text {
        text: row.petName
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        visible: row.petKind !== ""
        text: row.petKind
        color: Qt.darker(row.foreground, 1.5)
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.clicked()
  }
}