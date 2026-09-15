pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "madmasx.hermes-pets"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property var pet: panelLoader.item ? panelLoader.item.currentPet : null
  readonly property bool smoothScaling: setting("smooth", true) === true

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
  }

  implicitWidth: vertical ? barSize : Style.bar.iconSlot
  implicitHeight: vertical ? barSize : barSize

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Icono cuando NO hay mascota seleccionada: image.png del proyecto
  Component {
    id: fallbackIcon

    Image {
      source: Qt.resolvedUrl("image.png")
      fillMode: Image.PreserveAspectFit
      asynchronous: true
    }
  }

  // Icono cuando hay mascota: suhoja de sprite del petdex
  Component {
    id: petIcon

    Image {
      source: root.pet ? root.pet.sheetUrl : ""
      sourceClipRect: Qt.rect(0, 0, 192, 208)
      fillMode: Image.PreserveAspectFit
      smooth: root.smoothScaling
      asynchronous: true
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    opticalSize: root.barSize - Style.space(6)
    text: root.pet ? "" : "\uf1b0"
    iconComponent: root.pet ? petIcon : fallbackIcon
    tooltipText: root.pet ? root.pet.displayName : "Hermes Pets"
    onPressed: root.toggle()
  }
}
