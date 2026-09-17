import QtQuick
import qs.Commons
import qs.Ui

CursorSurface {
  id: row

  required property var modelData
  property string fontFamily: Style.font.family
  property bool smoothScaling: true
  property bool installed: false
  property bool busy: false
  property color foreground: Style.textPrimary

  signal clicked()

  readonly property string petName: modelData && modelData.displayName ? modelData.displayName : ""
  readonly property string petKind: modelData && modelData.kind ? modelData.kind : ""
  readonly property url thumbSource: modelData && modelData.sheetUrl ? modelData.sheetUrl : ""

  hasCursor: mouse.containsMouse
  width: parent && parent.width ? parent.width : implicitWidth
  implicitHeight: content.implicitHeight + Style.spacing.md * 2
  opacity: row.busy ? 0.55 : 1.0

  Row {
    id: content
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.right: statusText.left
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
        text: row.petName
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        visible: row.petKind !== ""
        text: row.petKind
        color: Qt.darker(row.foreground, 1.5)
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  Text {
    id: statusText
    anchors.verticalCenter: parent.verticalCenter
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.rowPaddingX
    text: row.busy ? "Instalando…" : (row.installed ? "✓ Instalada" : "Instalar")
    color: row.installed ? "#6c63ff" : row.foreground
    opacity: row.installed ? 1.0 : 0.6
    font.family: row.fontFamily
    font.pixelSize: Style.font.caption
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    enabled: !row.installed && !row.busy
    onClicked: row.clicked()
  }
}
