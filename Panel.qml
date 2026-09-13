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
    readonly property bool hudModeEnabled: root.setting("hudModeEnabled", true) === true
    readonly property bool activityEnabled: root.setting("activityEnabled", false) === true
    property bool movable: root.setting("movable", true) === true
    property real petScale: (root.setting("petScale", 0.75) || 1.0)

    property int dragDx: 0
    property int dragDy: 0
    property bool hudShown: false
    property bool functionBarShown: false

    readonly property var currentPet: {
        if (!petId) return null
        var pets = library.pets
        for (var i = 0; i < pets.length; i++) if (pets[i].name === petId) return pets[i]
        return pets.length > 0 ? pets[0] : null
    }

    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property color barForeground: bar ? bar.foreground : Style.textPrimary

    readonly property string hudPetName: root.currentPet ? root.currentPet.displayName : "Hermes"
    readonly property string hudPoseLabel: root.activityPose

    onOpenedChanged: { if (opened) library.rescan() }
    onPinnedChanged: if (pinned) root.controller.hide()

    function toggle() {
        if (pinned || !opened) open()
        else close()
    }

    function openHud() {
        if (!hudModeEnabled || !pinned || hudShown) return
        hudShown = true
        hudTimer.restart()
    }

    function closeHud() { hudShown = false; hudTimer.stop() }

    function toggleFunctionBar() {
        if (!pinned) return
        functionBarShown = !functionBarShown
        if (functionBarShown) {
            hudShown = false
            hudTimer.stop()
        }
    }

    function dragPet(dx, dy) {
        if (!pinned || !movable) return
        dragDx += dx
        dragDy += dy
    }

    function dropPet() {
        if (!pinned) return
        saveSetting("pinnedX", dragDx)
        saveSetting("pinnedY", dragDy)
        dragDx = 0
        dragDy = 0
    }

    function saveSetting(key, value) {
        var reg = bar && bar.shell ? bar.shell.pluginRegistry : null
        if (!reg) return
        var err = reg.setBarWidget(moduleName, key, value, {})
    }

    function toggleMovable() { movable = !movable; saveSetting("movable", movable) }
    function toggleHudMode() { hudModeEnabled = !hudModeEnabled; saveSetting("hudModeEnabled", hudModeEnabled) }
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

    Timer { id: hudTimer; interval: 3000; repeat: false; onTriggered: root.closeHud() }

    PetLibrary { id: library; active: root.hostWidget !== null; petsDir: root.petsDir }

    // --- Bar button ---
    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.pet ? "" : "\uf1b0"
        iconComponent: root.pet ? petIcon : fallbackIcon
        tooltipText: root.pet ? root.pet.displayName : "Hermes Pets"
        onPressed: root.toggle()
    }

    Component { id: fallbackIcon; Image { source: Qt.resolvedUrl("image.png"); fillMode: Image.PreserveAspectFit; asynchronous: true } }

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

    // --- Panel popup ---
    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
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
                    property var pet: modelData
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

                Row { spacing: Style.space(10)
                    Text { text: "Mostrar HUD al clickear"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; width: parent.width * 0.58; elide: Text.ElideRight }
                    ToggleSwitch { checked: hudModeEnabled; onToggled: root.toggleHudMode() }
                }

                Row { spacing: Style.space(10)
                    Text { text: "Permitir mover el pet"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; width: parent.width * 0.58; elide: Text.ElideRight }
                    ToggleSwitch { checked: movable; onToggled: root.toggleMovable() }
                }

                Row { spacing: Style.space(10)
                    Text { text: "Reaccionar a actividad"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; width: parent.width * 0.58; elide: Text.ElideRight }
                    ToggleSwitch { checked: activityEnabled; onToggled: root.toggleActivity() }
                }

                Row { spacing: Style.space(10)
                    Text { text: "Tamaño: " + Math.round(petScale * 100) + "% (Alt+Scroll)"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; width: parent.width * 0.58; elide: Text.ElideRight }
                    Row { spacing: Style.space(4)
                        Button { text: "-"; width: Style.space(32); foreground: root.barForeground; fontFamily: root.fontFamily; fontSize: 14; onClicked: root.setScale(petScale - 0.25) }
                        Button { text: "+"; width: Style.space(32); foreground: root.barForeground; fontFamily: root.fontFamily; fontSize: 14; onClicked: root.setScale(petScale + 0.25) }
                    }
                }

                Row { spacing: Style.space(10)
                    Text { text: "Animación"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; width: parent.width * 0.58; elide: Text.ElideRight }
                    ToggleSwitch { checked: animate; onToggled: saveSetting("animate", checked) }
                }
            }

            PanelSeparator { foreground: root.barForeground }

            // Estado actual
            PanelSectionHeader { text: "Estado actual"; foreground: root.barForeground; fontFamily: root.fontFamily }

            Column { id: statusColumn; width: parent.width; spacing: Style.space(3)
                Text { width: parent.width; text: "Mascota: " + (root.currentPet ? root.currentPet.displayName : "Ninguna"); color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; opacity: 0.85 }
                Text { width: parent.width; text: "Estado: " + (root.activityEnabled ? root.activityPose : "idle (sin monitoreo)"); color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; opacity: 0.7 }
                Text { width: parent.width; text: root.pinned ? ("Fijado" + (root.movable ? " (movible)" : " (fijo)")) : "Panel de barra"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; opacity: 0.7 }
                Text { id: hudStatusText; width: parent.width; text: "HUD: Activado"; color: "#6c63ff"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; opacity: 0.9; visible: root.hudModeEnabled }
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
            // Centrar en pantalla usando Quickshell.screen
            property real petX: root.pinnedX >= 0 ? root.pinnedX + root.dragDx : (Quickshell.screen ? Quickshell.screen.width : 1920) / 2 - 96
            property real petY: root.pinnedY >= 0 ? root.pinnedY + root.dragDy : (Quickshell.screen ? Quickshell.screen.height : 1080) / 2 - 104
            x: petX
            y: petY
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
                onHudClicked: {
                    if (root.hudModeEnabled) {
                        root.openHud()
                        root.functionBarShown = false
                    } else {
                        root.toggleFunctionBar()
                    }
                }
            }

            // --- Overlay HUD (modo HUD) ---
            Item {
                id: hudOverlay
                visible: root.hudShown && root.pinned
                anchors.centerIn: parent
                z: 50
                width: 160
                height: 64

                property string poseIcon: {
                    switch (root.hudPoseLabel) {
                        case "run": return String.fromCharCode(0x26A1)
                        case "review": return String.fromCharCode(0x2713)
                        case "wave": return String.fromCharCode(0x270C)
                        case "jump": return String.fromCharCode(0x2694)
                        case "failed": return String.fromCharCode(0x2717)
                        case "waiting": return String.fromCharCode(0x23F3)
                        default: return String.fromCharCode(0x263E)
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: "transparent"
                    border.color: "#6c63ff"
                    border.width: 1
                    Column {
                        anchors.centerIn: parent
                        spacing: 3
                        Text { text: hudOverlay.poseIcon; font.pixelSize: 20; color: "#6c63ff" }
                        Text { text: root.hudPetName; font.pixelSize: 10; font.bold: true; color: "#ffffff" }
                        Text { text: root.hudPoseLabel; font.pixelSize: 9; color: "#b8b8d0" }
                    }
                }
                MouseArea { anchors.fill: parent; onClicked: root.closeHud() }
            }

            // --- Overlay de funciones rápidas (panel flotante estilo snap-preview) ---
            Item {
                id: functionBar
                visible: root.functionBarShown && root.pinned
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: -6
                anchors.rightMargin: -6
                z: 200
                width: 240
                height: 52

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: "#1a1a2e"
                    border.color: "#6c63ff"
                    border.width: 1

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        // Botón Mover / Desmover
                        Rectangle {
                            id: btnMove
                            width: 40; height: 40; radius: 8
                            color: root.movable ? "#51cf66" : "#ff6b6b"
                            border.color: "#ffffff"
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "\uf024"; font.pixelSize: 15; color: "#ffffff" }
                            ToolTip.foreground: root.barForeground
                            ToolTip.text: root.movable ? "Desanclar del escritorio" : "Fijar al escritorio"
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.toggleMovable()
                                    console.log("[hermes-pets] movable: " + root.movable)
                                }
                                onEntered: btnMove.border.color = "#ffcc00"
                                onExited: btnMove.border.color = "#ffffff"
                            }
                        }

                        // Botón HUD
                        Rectangle {
                            id: btnHud
                            width: 40; height: 40; radius: 8
                            color: root.hudModeEnabled ? "#6c63ff" : "#ff6b6b"
                            border.color: "#ffffff"
                            border.width: 1
                            Text { anchors.centerIn: parent; text: root.hudModeEnabled ? "\uf128" : "\uf129"; font.pixelSize: 15; color: "#ffffff" }
                            ToolTip.foreground: root.barForeground
                            ToolTip.text: root.hudModeEnabled ? "Desactivar HUD" : "Activar HUD"
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.toggleHudMode()
                                    console.log("[hermes-pets] hudModeEnabled: " + root.hudModeEnabled)
                                }
                                onEntered: btnHud.border.color = "#ffcc00"
                                onExited: btnHud.border.color = "#ffffff"
                            }
                        }

                        // Botón Animación
                        Rectangle {
                            id: btnAnim
                            width: 40; height: 40; radius: 8
                            color: root.animate ? "#51cf66" : "#ff6b6b"
                            border.color: "#ffffff"
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "\uf04b"; font.pixelSize: 15; color: "#ffffff" }
                            ToolTip.foreground: root.barForeground
                            ToolTip.text: root.animate ? "Desactivar animación" : "Activar animación"
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.animate = !root.animate
                                    root.saveSetting("animate", root.animate)
                                    console.log("[hermes-pets] animate: " + root.animate)
                                }
                                onEntered: btnAnim.border.color = "#ffcc00"
                                onExited: btnAnim.border.color = "#ffffff"
                            }
                        }

                        // Botón Escala -
                        Rectangle {
                            width: 32; height: 32; radius: 6
                            color: "#2d2d44"
                            border.color: "#aab"
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "\u2212"; font.pixelSize: 16; color: "#ffffff" }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setScale(root.petScale - 0.25)
                                onEntered: parent.color = "#6c63ff"
                                onExited: parent.color = "#2d2d44"
                            }
                        }

                        // Botón Escala +
                        Rectangle {
                            width: 32; height: 32; radius: 6
                            color: "#2d2d44"
                            border.color: "#aab"
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 14; color: "#ffffff" }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setScale(root.petScale + 0.25)
                                onEntered: parent.color = "#6c63ff"
                                onExited: parent.color = "#2d2d44"
                            }
                        }
                    }
                }
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
    }
}
