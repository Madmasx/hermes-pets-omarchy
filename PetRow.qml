import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

CursorSurface {
  id: row

  required property var modelData
  property string fontFamily: Style.font.family
  property bool smoothScaling: true
  property bool selected: false
  property color foreground: Commons.Color.popups.text

  signal clicked()

  readonly property string petName: modelData && modelData.displayName ? modelData.displayName : ""
  readonly property string petKind: modelData && modelData.kind ? modelData.kind : ""
  readonly property url thumbSource: modelData && modelData.sheetUrl ? modelData.sheetUrl : ""

  hasCursor: mouse.containsMouse
  width: parent && parent.width ? parent.width : implicitWidth
  implicitHeight: content.implicitHeight + Style.spacing.md * 2

  Row {
    id: content
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.right: selectedBadge.left
    anchors.rightMargin: Style.spacing.rowGap
    spacing: Style.spacing.rowGap

    Image {
      id: thumb
      anchors.verticalCenter: parent.verticalCenter
      height: Style.space(36)
      width: height * 192 / 208
      source: row.thumbSource
      sourceClipRect: Qt.rect(0, 0, 192, 208)
      fillMode: Image.PreserveAspectFit
      smooth: row.smoothScaling
      asynchronous: true
    }

    Column {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, content.width - thumb.width - content.spacing)
      spacing: Style.spacing.labelGap

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: row.petName
        color: row.selected ? Commons.Color.accent : row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        font.bold: row.selected
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: row.petKind !== ""
        textFormat: Text.PlainText
        text: row.petKind
        color: Qt.darker(row.foreground, 1.5)
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  Text {
    id: selectedBadge
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.rowPaddingX
    visible: row.selected
    textFormat: Text.PlainText
    text: "✓"
    color: Commons.Color.accent
    font.family: row.fontFamily
    font.pixelSize: Style.font.body
    font.bold: true
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: row.clicked()
  }
}
