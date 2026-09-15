pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "madmasx.hermes-pets"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root

    readonly property string home: Quickshell.env("HOME")

    readonly property string petsDir: {
        var raw = String(root.setting("petsDir", "~/.hermes/pets"))
        return raw === "~" || raw.indexOf("~/") === 0 ? home + raw.slice(1) : raw
    }

    readonly property string petId: String(root.setting("petId", ""))
    readonly property bool smoothScaling: root.setting("smooth", true) === true
    readonly property bool animate: root.setting("animate", true) === true
    readonly property bool randomBehavior: root.setting("randomBehavior", true) === true
    readonly property bool pinned: root.setting("pinned", false) === true
    readonly property int pinnedX: root.setting("pinnedX", -1)
    readonly property int pinnedY: root.setting("pinnedY", -1)
    property bool activityEnabled: root.setting("activityEnabled", false) === true
    property bool movable: root.setting("movable", true) === true
    property real petScale: (root.setting("petScale", 0.75) || 1.0)

    readonly property real screenW: Quickshell.screen ? Quickshell.screen.width : 1920
    readonly property real screenH: Quickshell.screen ? Quickshell.screen.height : 1080

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

    property int dragDx: 0
    property int dragDy: 0

    readonly property var currentPet: {
        if (!petId) return null
        var pets = library.pets
        for (var i = 0; i < pets.length; i++) if (pets[i].name === petId) return pets[i]
        return pets.length > 0 ? pets[0] : null
    }

    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property color barForeground: bar ? bar.foreground : Style.textPrimary

    onOpenedChanged: { if (opened) library.rescan() }
    onPinnedChanged: if (pinned) root.controller.hide()
    onPetIdChanged: if (pinned && petId !== "" && !root.currentPet) root.saveSetting("pinned", false)

    function toggle() {
        if (pinned || !opened) open()
        else close()
    }

    function launchApp() {
        if (root.bar && typeof root.bar.run === "function")
            root.bar.run("bash \"" + home + "/.config/omarchy/plugins/madmasx.hermes-pets/open-hermes-hud.sh\"")
    }

    function dragPet(dx, dy) {
        if (!pinned || !movable) return
        dragDx += dx
        dragDy += dy
    }

    function dropPet() {
        if (!pinned) return
        var totalX = root.dragDx
        var totalY = root.dragDy
        root.dragDx = 0
        root.dragDy = 0
        var mx = root.pinnedX >= 0 ? root.pinnedX + totalX : Math.round(root.screenW / 2) - 96
        var my = root.pinnedY >= 0 ? root.pinnedY + totalY : Math.round(root.screenH / 2) - 104
        saveSetting("pinnedX", Math.round(root.clamp(mx, 0, Math.max(0, root.screenW - (192 * petScale + 20)))))
        saveSetting("pinnedY", Math.round(root.clamp(my, 0, Math.max(0, root.screenH - (208 * petScale + 20)))))
    }

    function saveSetting(key, value) {
        var reg = (typeof shell !== "undefined" && shell && shell.pluginRegistry) ? shell.pluginRegistry : null
        if (!reg) return
        var err = reg.setBarWidget(moduleName, key, value, {})
    }

    function toggleMovable() { movable = !movable; saveSetting("movable", movable) }
    function toggleActivity() { activityEnabled = !activityEnabled; saveSetting("activityEnabled", activityEnabled) }

    function setScale(val) {
        petScale = Math.max(0.25, Math.min(3.0, val))
        saveSetting("petScale", petScale)
    }

    function removePet() {
        if (!petId) return
        saveSetting("petId", "")
        library.rescan()
        if (!pinned) root.toggle()
    }

    function installPet() { Quickshell.openUrl("https://petdex.dev") }
    function installPetByName(name) { Quickshell.openUrl("https://petdex.dev/pet/" + encodeURIComponent(name)) }

    readonly property string activityFile: home + "/.hermes/pets/activity-state.json"

    readonly property string activityPose: {
        if (!activityEnabled || !activityFile) return "idle"
        try {
            var text = Qt.readFile(activityFile)
            if (!text) return "idle"
            var data = JSON.parse(text)
            if (data && typeof data.pose === "string") return data.pose
        } catch (e) { }
        return "idle"
    }

    Timer {
        id: activityTimer
        interval: 800
        repeat: true
        running: root.activityEnabled && root.currentPet !== null
        onTriggered: {
            var pose = root.activityPose
            if (sprite && pose && pose !== "idle" && sprite.pose !== pose)
                sprite.beginAction(pose, 1)
        }
    }

    PetLibrary { id: library; active: root.hostWidget !== null; petsDir: root.petsDir }

    // --- Panel popup ---
    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        padding: Style.space(14)
        contentWidth: panel.fittedContentWidth(400)
        contentHeight: content.implicitHeight

        Column {
            id: content
            anchors.fill: parent
            anchors.margins: Style.space(4)
            spacing: Style.space(7)

            PanelHero {
                width: parent.width
                title: "Hermes Pets"
                meta: root.currentPet ? root.currentPet.displayName : "No hay mascota"
                foreground: root.barForeground
                fontFamily: root.fontFamily
            }

            PanelSeparator { foreground: root.barForeground }

            // Mascotas disponibles
            PanelSectionHeader { text: "Mascotas disponibles (" + library.pets.length + ")"
                foreground: root.barForeground; fontFamily: root.fontFamily }

            // Lista de mascotas
            Repeater {
                id: petRepeater
                model: library.pets
                delegate: PetRow {
                    fontFamily: root.fontFamily
                    smoothScaling: root.smoothScaling
                    foreground: root.barForeground
                    selected: modelData && modelData.name === root.petId
                    onClicked: {
                        if (modelData) {
                            root.saveSetting("petId", modelData.name)
                            if (!root.pinned) root.toggle()
                        }
                    }
                }
            }

            Text {
                id: noPetsText
                width: parent.width
                text: "No hay mascotas instaladas\n\nInstala una con:\nhermes pets install <slug>"
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                opacity: 0.6
                wrapMode: Text.WordWrap
                visible: library.pets.length === 0
            }

            PanelSeparator { foreground: root.barForeground }

            // Acciones rápidas
            PanelSectionHeader { text: "Acciones"; foreground: root.barForeground; fontFamily: root.fontFamily }

            Row { spacing: Style.space(6)
                PanelActionButton {
                    iconText: root.pinned ? "\uf024" : "\uf0c7"
                    tooltipText: root.pinned ? "Desanclar del escritorio" : "Fijar al escritorio"
                    foreground: root.barForeground; fontFamily: root.fontFamily
                    onClicked: { root.saveSetting("pinned", !root.pinned) }
                }
                PanelActionButton {
                    id: removePetBtn
                    visible: root.petId !== ""
                    iconText: "\uf014"
                    tooltipText: "Quitar mascota actual"
                    foreground: root.barForeground; fontFamily: root.fontFamily
                    onClicked: root.removePet()
                }
                PanelActionButton {
                    iconText: "\uf067"
                    tooltipText: "Instalar nueva mascota"
                    foreground: root.barForeground; fontFamily: root.fontFamily
                    onClicked: root.installPet()
                }
            }

            PanelSeparator { foreground: root.barForeground }

            // Configuración
            PanelSectionHeader { text: "Configuración"; foreground: root.barForeground; fontFamily: root.fontFamily }

            Column { id: settingsColumn; width: parent.width; spacing: Style.space(4)

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlMove.width - Style.space(10); text: "Permitir mover el pet"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlMove; spacing: Style.space(4)
                        ToggleSwitch { checked: movable; onToggled: root.toggleMovable() }
                    }
                }

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlActivity.width - Style.space(10); text: "Reaccionar a actividad"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlActivity; spacing: Style.space(4)
                        ToggleSwitch { checked: activityEnabled; onToggled: root.toggleActivity() }
                    }
                }

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlScale.width - Style.space(10); text: "Tamaño: " + Math.round(petScale * 100) + "% (Alt+Scroll)"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlScale; spacing: Style.space(4)
                        Button { text: "-"; width: Style.space(32); foreground: root.barForeground; fontFamily: root.fontFamily; fontSize: 14; onClicked: root.setScale(petScale - 0.25) }
                        Button { text: "+"; width: Style.space(32); foreground: root.barForeground; fontFamily: root.fontFamily; fontSize: 14; onClicked: root.setScale(petScale + 0.25) }
                    }
                }

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlAnim.width - Style.space(10); text: "Animación"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlAnim; spacing: Style.space(4)
                        ToggleSwitch { checked: animate; onToggled: saveSetting("animate", checked) }
                    }
                }
            }

            PanelSeparator { foreground: root.barForeground }

            // Estado actual
            PanelSectionHeader { text: "Estado actual"; foreground: root.barForeground; fontFamily: root.fontFamily }

            Column { id: statusColumn; width: parent.width; spacing: Style.space(3)
                Text { width: parent.width; text: "Mascota: " + (root.currentPet ? root.currentPet.displayName : "Ninguna"); color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; opacity: 0.85 }
                Text { width: parent.width; text: "Estado: " + (root.activityEnabled ? root.activityPose : "idle (sin monitoreo)"); color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; opacity: 0.7 }
                Text { width: parent.width; text: root.pinned ? ("Fijado" + (root.movable ? " (movible)" : " (fijo)")) : "Panel de barra"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; opacity: 0.7 }
                Text { width: parent.width; text: "Click en la mascota: abre el Hub de Hermes"; color: "#6c63ff"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; opacity: 0.8 }
            }
        }
    }

    // --- Pinned sprite layer con overlay de funciones ---
    Item {
        id: stage
        parent: root.pinned ? pinnedWindow.contentItem : null
        visible: root.pinned
        implicitWidth: 192
        implicitHeight: 208

        FocusScope {
            focus: true
            x: 0
            y: 0
            width: 192
            height: 208

            PetSprite {
                id: sprite
                anchors.fill: parent
                scale: petScale
                sheetUrl: root.currentPet ? root.currentPet.sheetUrl : ""
                smoothScaling: root.smoothScaling
                running: root.pinned && root.animate && root.currentPet !== null
                randomBehavior: root.randomBehavior
                onDragged: function(dx, dy) { root.dragPet(dx, dy) }
                onDropped: root.dropPet()
                onHudClicked: root.launchApp()
            }

            // Escalado con Alt + Scroll
            WheelHandler {
                acceptedModifiers: Qt.AltModifier
                onWheel: function(wheel) {
                    if (wheel.angleDelta.y === 0) return
                    var dir = wheel.angleDelta.y > 0 ? -1 : 1
                    root.setScale(root.petScale + dir * 0.1)
                }
            }
        }
    }

    // --- Window para pinned mode ---
    PanelWindow {
        id: pinnedWindow
        visible: root.pinned
        implicitWidth: 192 * petScale + 20
        implicitHeight: 208 * petScale + 20
        WlrLayershell.namespace: "hermes-pets"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        anchors.top: true
        anchors.left: true
        margins {
            left: root.clamp(
                (root.pinnedX >= 0 ? root.pinnedX : Math.round(root.screenW / 2) - 96) + root.dragDx,
                0, Math.max(0, root.screenW - 192 * petScale - 20))
            top: root.clamp(
                (root.pinnedY >= 0 ? root.pinnedY : Math.round(root.screenH / 2) - 104) + root.dragDy,
                0, Math.max(0, root.screenH - 208 * petScale - 20))
        }
    }
}
