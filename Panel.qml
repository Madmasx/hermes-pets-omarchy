pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "PinGate.js" as PinGate

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
    property bool animate: root.setting("animate", true) === true
    readonly property bool randomBehavior: root.setting("randomBehavior", true) === true
    readonly property bool pinned: root.setting("pinned", false) === true
    readonly property int pinnedX: root.setting("pinnedX", -1)
    readonly property int pinnedY: root.setting("pinnedY", -1)
    property bool activityEnabled: root.setting("activityEnabled", false) === true
    property bool movable: root.setting("movable", true) === true
    property bool launchOnClick: root.setting("launchOnClick", true) === true
    property bool gravityEnabled: root.setting("gravityEnabled", true) === true
    property real petScale: (root.setting("petScale", 0.75) || 1.0)

// --- Pet único por escritorio -----------------------------------------
    // El bar quickshell crea una instancia del widget por monitor (Bar.qml:
    // "a widget that appears once in the layout is still live once per screen"),
    // asi que con varias pantallas hay varias mascotas vivas y cada una pineaba
    // su ventana -> pet duplicado. Todas las instancias comparten el MISMO
    // engine QML, asi que PinGate (singleton .pragma library) decide que una
    // sola instancia tenga la ventana pinned (owner); las demas conservan su
    // icono en su bar y el ajuste compartido, pero sin ventana, ni roaming, ni
    // gravedad. Si el owner suelta, la siguiente releva.
    readonly property string pinToken: PinGate.nextId()
    property bool pinEligible: false
    readonly property bool shownPinned: root.pinned && root.pinEligible

    function syncPinEligible() {
        if (root.pinned) root.pinEligible = PinGate.claim(root.pinToken)
        else if (PinGate.release(root.pinToken)) root.pinEligible = false
    }
    // El onCompleted de este root no llega a ejecutarse en el arranque limpio
    // (lo detectamos con los logs de diagnostico), asi que el reclamo/impulso
    // sale de este Timer que SI dispara; ademas fuerza el relevo si el owner cae.
    Timer {
        interval: 250
        repeat: true
        running: root.pinned && !root.pinEligible
        onTriggered: root.syncPinEligible()
    }
    Timer {
        interval: 4000
        repeat: true
        running: root.pinned
        onTriggered: root.syncPinEligible()
    }
    onPinnedChanged: {
        if (pinned) root.controller.hide()
        if (root.pinned) {
            if (root.gravityEnabled) gravLoop.start()
            if (root.shownPinned && root.gravityEnabled && sprite) root.resyncScreen()
        } else if (PinGate.release(root.pinToken)) root.pinEligible = false
    }
    onShownPinnedChanged: {
        if (root.shownPinned && root.gravityEnabled && !gravLoop.running) gravLoop.start()
        else if (!root.shownPinned) gravLoop.stop()
    }

    readonly property real screenW: root.pinned && pinnedWindow && pinnedWindow.screen ? pinnedWindow.screen.width : (Quickshell.screen ? Quickshell.screen.width : 1920)
    readonly property real screenH: root.pinned && pinnedWindow && pinnedWindow.screen ? pinnedWindow.screen.height : (Quickshell.screen ? Quickshell.screen.height : 1080)

    function resyncScreen() {
        // Detecta cambio de monitor/resolución de la pantalla donde vive el pet:
        // si la gravedad está activa, relanza la caída para caer lo mismo hasta el nuevo fondo;
        // el pet_NUNCA_ queda descolgado: gravTick recalcula floorY con la screenH nueva cada tick.
        if (root.shownPinned && root.gravityEnabled) {
            if (gravLoop.running) { gravLoop.stop(); gravLoop.start() }
            else if (!root.grabbing) gravLoop.start()
        }
        root.saveSetting("pinnedY", root.pinnedY >= 0 ? root.pinnedY : Math.round(root.screenH / 2) - 104)
    }

    function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

    // --- Arrastre y gravedad ------------------------------------------------
    property int dragDx: 0
    property int dragDy: 0
    property bool grabbing: false

    // La mascota cae (gravDropOffset alimenta el margen top de la ventana),
    // y al aterrizar se desliza en horizontal (gravWalkOffset) hacia la X real
    // donde se soltó. gravVel acumula la velocidad de caída; gravFall y
    // gravLandX son estados de la física.
    property real gravDropOffset: 0
    property real gravFall: 0
    property real gravVel: 0
    property real gravWalkOffset: 0
    property int gravLandX: -1

    Timer {
        id: gravLoop
        interval: 16
        repeat: true
        onTriggered: root.gravTick()
    }

    NumberAnimation {
        id: gravAnim
        target: root
        property: "gravDropOffset"
        duration: 320
        easing.type: Easing.InQuad
        onRunningChanged: if (!running) {
            // aterrizó: compromiso con la X real desde donde soltaste (gravLandX, nunca el centro)
            var floorY = Math.round(Math.max(0, root.screenH - Math.round(208 * petScale + 6)))
            var lanX = root.gravLandX >= 0 ? root.gravLandX : (root.pinnedX >= 0 ? root.pinnedX : Math.round(root.screenW / 2) - 96)
            root.saveSetting("pinnedX", lanX)
            root.saveSetting("pinnedY", floorY)
            var walk = Math.round(lanX - (root.pinnedX >= 0 ? root.pinnedX : Math.round(root.screenW / 2) - 96))
            if (walk !== 0) {
                if (sprite) sprite.pose = "running"
                walkAnim.to = walk
                walkAnim.restart()
            } else if (sprite) sprite.pose = "idle"
        }
    }

    NumberAnimation {
        id: walkAnim
        target: root
        property: "gravWalkOffset"
        from: 0.0
        duration: 700
        easing.type: Easing.InOutSine
        onRunningChanged: if (!running) {
            if (root.gravityEnabled) root.pinnedX = Math.round(root.clamp((root.pinnedX >= 0 ? root.pinnedX : Math.round(root.screenW / 2) - 96) + root.gravWalkOffset, 0, Math.max(0, root.screenW - 192 * petScale)))
            root.saveSetting("pinnedX", root.pinnedX)
            root.gravWalkOffset = 0
            if (sprite) sprite.pose = "idle"
        }
    }

    // --- Roaming estilo Hermes: pausa y camina por el borde inferior ---
    // Pausa 8-20s, elige una X aleatoria y camina hacia ella con las filas
    // direccionales (running-right/left). Solo cuando el agente esta en reposo.
    property real roamOffset: 0
    property bool roamWalking: false
    property real roamTargetLeft: 0
    property real roamPauseUntil: 0

    function roamBaseLeft() {
        return root.pinnedX >= 0 ? root.pinnedX : Math.round(root.screenW / 2) - 96
    }
    function roamMaxLeft() { return Math.max(0, root.screenW - 192 * petScale) }
    function roamAllowed() {
        return root.shownPinned && root.animate && root.randomBehavior && root.currentPet !== null
            && !root.grabbing && !gravLoop.running && !gravAnim.running && !walkAnim.running
            && (!root.activityEnabled || root.activityPose === "idle")
    }
    function roamPause() {
        root.roamWalking = false
        if (sprite) { sprite.beginIdle(); if (sprite.ticking) sprite.arm() }
        root.roamPauseUntil = Date.now() + 8000 + Math.random() * 12000
    }
    function roamCommit() {
        var nx = Math.round(root.clamp(root.roamBaseLeft() + root.roamOffset, 0, root.roamMaxLeft()))
        root.roamOffset = 0
        root.saveSetting("pinnedX", nx)
    }
    function roamPlan() {
        var maxLeft = root.roamMaxLeft()
        var cur = root.clamp(root.roamBaseLeft() + root.roamOffset, 0, maxLeft)
        var target = Math.round(Math.random() * maxLeft)
        if (Math.abs(target - cur) < 12) { root.roamPause(); return }
        var delta = target - cur
        root.roamWalking = true
        root.roamTargetLeft = target
        if (sprite) {
            var pose = "running"
            if (sprite.hasLocomotion) pose = delta > 0 ? "running-right" : "running-left"
            sprite.beginAction(pose, 9999)
            if (sprite.ticking) sprite.arm()
        }
    }
    function roamStep() {
        if (!roamAllowed()) {
            if (root.roamWalking) { root.roamWalking = false; if (sprite) sprite.beginIdle() }
            if (root.roamOffset !== 0) root.roamCommit()
            root.roamPauseUntil = 0
            if (root.activityEnabled) root.applyActivityPose()
            return
        }
        if (root.roamWalking) {
            var petW = 192 * petScale
            var loopMs = sprite ? sprite.loopMs : 820
            var speed = Math.max(20, (petW * 0.8) / Math.max(0.1, loopMs / 1000))
            var cur = root.roamBaseLeft() + root.roamOffset
            var remaining = root.roamTargetLeft - cur
            var stepDist = speed * (roamLoop.interval / 1000)
            if (Math.abs(remaining) <= Math.max(1.5, stepDist)) {
                root.roamOffset += remaining
                root.roamWalking = false
                root.roamCommit()
                root.roamPause()
            } else {
                root.roamOffset += (remaining > 0 ? 1 : -1) * stepDist
            }
            return
        }
        if (root.roamPauseUntil === 0) { root.roamPause(); return }
        if (Date.now() >= root.roamPauseUntil) root.roamPlan()
    }

    Timer {
        id: roamLoop
        interval: root.roamWalking ? 16 : 250
        repeat: true
        running: root.shownPinned
        onTriggered: root.roamStep()
    }

    readonly property var currentPet: {
        if (!petId) return null
        var pets = library.pets
        for (var i = 0; i < pets.length; i++) if (pets[i].name === petId) return pets[i]
        return pets.length > 0 ? pets[0] : null
    }

    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property color barForeground: bar ? bar.foreground : Style.textPrimary

    onOpenedChanged: { if (opened) library.rescan() }
    onPetIdChanged: if (pinned && petId !== "" && library.pets.length > 0 && !root.currentPet) root.saveSetting("pinned", false)

    function toggle() {
        if (pinned || !opened) open()
        else close()
    }

    function launchApp() {
        if (!root.launchOnClick) return
        if (root.bar && typeof root.bar.run === "function")
            root.bar.run("hermes desktop --skip-build")
    }

    function dragPet(dx, dy) {
        if (!pinned || !movable) return
        root.grabbing = true
        if (gravLoop.running) gravLoop.stop()
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
        var nx = Math.round(root.clamp(mx, 0, Math.max(0, root.screenW - (192 * petScale))))
        var ny = Math.round(root.clamp(my, 0, Math.max(0, Math.round(Math.max(0, root.screenH - Math.round(208 * petScale + 6))))))
        root.grabbing = false
        root.saveSetting("pinnedX", nx)
        root.saveSetting("pinnedY", ny)
        if (root.gravityEnabled) {
            // GRAVEDAD ON: si quedó en el aire, REANUDAR la física continua desde aquí
            var floorY = Math.max(0, Math.round(Math.max(0, root.screenH - Math.round(208 * petScale + 6))))
            if (ny < floorY) {
                root.gravLandX = nx
                root.gravVel = 0
                root.gravDropOffset = 0
                gravLoop.restart()
                return
            }
        }
    }

    function saveSetting(key, value) {
        var reg = (typeof shell !== "undefined" && shell && shell.pluginRegistry) ? shell.pluginRegistry : null
        if (!reg) return
        var err = reg.setBarWidget(moduleName, key, value, {})
    }

    function toggleMovable() { movable = !movable; saveSetting("movable", movable) }
    function toggleLaunchOnClick() { launchOnClick = !launchOnClick; saveSetting("launchOnClick", launchOnClick) }
    function gravTick() {
        if (root.grabbing) return
        if (!root.gravityEnabled || !root.shownPinned) { gravLoop.stop(); return }
        var floorY = Math.max(0, Math.round(Math.max(0, root.screenH - Math.round(208 * petScale + 6))))
        var base = root.pinnedY >= 0 ? root.pinnedY + root.dragDy : Math.round(root.screenH / 2) - 104
        var cy = base + root.gravDropOffset
        if (cy >= floorY) {
            var fx = root.gravLandX >= 0 ? root.gravLandX : (root.pinnedX >= 0 ? root.pinnedX : Math.round(root.screenW / 2) - 96)
            root.saveSetting("pinnedX", fx)
            root.saveSetting("pinnedY", floorY)
            root.gravDropOffset = 0
            if (sprite) sprite.pose = "idle"
            gravLoop.stop()
            return
        }
        root.gravVel = Math.min(root.gravVel + 6, 18)
        root.gravDropOffset += root.gravVel
        if (base + root.gravDropOffset > floorY) root.gravDropOffset = floorY - base
    }

    function toggleGravity() { gravityEnabled = !gravityEnabled; saveSetting("gravityEnabled", gravityEnabled)
        if (!gravityEnabled) {
            if (walkAnim.running) walkAnim.stop()
            if (gravAnim.running) gravAnim.stop()
            if (gravLoop.running) gravLoop.stop()
            root.gravVel = 0
            root.gravWalkOffset = 0; root.gravDropOffset = 0
            if (sprite) sprite.pose = "idle"
        } else {
            // Gravedad ACTIVADA: física CONTINUA e INMEDIATA — cae sola sin tocar el pet
            if (root.shownPinned) {
                if (walkAnim.running) walkAnim.stop()
                root.gravVel = 0
                root.gravDropOffset = 0; root.gravWalkOffset = 0
                gravLoop.restart()
            }
        }
    }
    function toggleActivity() { activityEnabled = !activityEnabled; saveSetting("activityEnabled", activityEnabled) }
    function toggleAnimate() { animate = !animate; saveSetting("animate", animate) }

    function setScale(val) {
        petScale = Math.max(0.25, Math.min(3.0, val))
        saveSetting("petScale", petScale)
    }

    // Borra la mascota actual del disco (hermes pets remove), sin pasar por Hermes.
    function removePet() {
        if (!petId) return
        removeProc.command = [root.hermesBin, "pets", "remove", petId]
        removeProc.running = true
    }

    function openCatalog() {
        root.catalogOpen = true
        if (root.catalogAll.length === 0 && !catalogFetch.running) {
            root.catalogStatus = "Cargando catálogo…"
            catalogFetch.running = true
        }
    }

    function installCatalogPet(slug) {
        if (!slug || root.catalogInstalling !== "") return
        root.catalogInstalling = slug
        installProc.command = [root.hermesBin, "pets", "install", slug]
        installProc.running = true
    }

    function filterCatalog(query, all) {
        if (!all || all.length === 0) return []
        var q = String(query || "").trim().toLowerCase()
        var out = []
        var cap = q === "" ? 60 : 200
        for (var i = 0; i < all.length && out.length < cap; i++) {
            var e = all[i]
            if (q === "" || e.slug.toLowerCase().indexOf(q) >= 0 || (e.displayName || "").toLowerCase().indexOf(q) >= 0)
                out.push(e)
        }
        return out
    }

    function isInstalled(slug) {
        var p = library.pets
        for (var i = 0; i < p.length; i++) if (p[i].name === slug) return true
        return false
    }

    readonly property string activityFile: home + "/.hermes/pets/activity-state.json"

    // Este runtime de Quickshell no expone Qt.readFile y FileView.text() devuelve
    // contenido desfasado; leemos el archivo con cat (proceso + polling barato).
    property string activityRaw: ""

    // Beats de un solo pase: si el archivo quedó con uno viejo (p.ej. un proceso
    // -z que terminó antes del TTL), el lector lo ignora en vez de re-reproducirlo.
    readonly property var transientActivityPoses: ["jump", "wave", "failed"]

    function parseActivity() {
        if (!activityEnabled) return "idle"
        var text = root.activityRaw
        if (!text) return root.activityPose
        try {
            var data = JSON.parse(text)
            if (!data || typeof data.pose !== "string") return root.activityPose
            if (root.transientActivityPoses.indexOf(data.pose) >= 0) {
                var ts = Number(data.updated_at) || 0
                if (ts > 0 && (Date.now() / 1000 - ts) > 3) return "idle"
            }
            return data.pose
        } catch (e) { }
        // Lectura parcial ilegible: conserva la última pose conocida.
        return root.activityPose
    }
    property string activityPose: "idle"

    Process {
        id: activityReader
        command: ["cat", root.activityFile]
        stdout: StdioCollector {
            onStreamFinished: {
                root.activityRaw = text
                root.activityPose = root.parseActivity()
                root.applyActivityPose()
            }
        }
    }

    // run/review/waiting se mantienen mientras Hermes siga en ese estado;
    // wave/jump/failed son reacciones de un solo pase.
    property string activityActivePose: "idle"
    readonly property var sustainedActivityPoses: ["run", "review", "waiting"]

    function resetActivityPose() {
        root.activityActivePose = "idle"
        if (sprite && sprite.pose !== "idle") {
            sprite.beginIdle()
            if (sprite.ticking) sprite.arm()
        }
    }

    function applyActivityPose() {
        if (!sprite) return
        if (root.roamWalking) return
        var pose = root.activityPose || "idle"
        if (pose === "idle") { root.resetActivityPose(); return }
        var sustained = root.sustainedActivityPoses.indexOf(pose) >= 0
        if (pose !== root.activityActivePose || (sustained && sprite.pose === "idle")) {
            root.activityActivePose = pose
            sprite.beginAction(pose, sustained ? 9999 : 1)
            if (sprite.ticking) sprite.arm()
        }
    }

    Timer {
        id: activityTimer
        interval: 700
        repeat: true
        running: root.activityEnabled && root.currentPet !== null
        onTriggered: {
            if (!sprite) return
            if (!activityReader.running) activityReader.running = true
            root.applyActivityPose()
        }
    }

    onActivityEnabledChanged: {
        if (activityEnabled) activityReader.running = true
        else root.resetActivityPose()
    }

    PetLibrary { id: library; active: root.hostWidget !== null; petsDir: root.petsDir }

    readonly property string hermesBin: home + "/.local/bin/hermes"
    property bool catalogOpen: false
    property var catalogAll: []
    property string catalogStatus: "Pulsa + para cargar el catálogo"
    property string catalogInstalling: ""

    QtObject { id: catalogOwner; function close() { root.catalogOpen = false } }

    Process {
        id: catalogFetch
        command: ["curl", "-sSL", "--max-time", "30", "-H", "User-Agent: hermes-agent-petdex", "https://petdex.dev/api/manifest"]
        stdout: StdioCollector { id: catalogOut; waitForEnd: true }
        stderr: StdioCollector { id: catalogErr; waitForEnd: true }
        onExited: function(code, status) {
            if (code !== 0) { root.catalogStatus = "No se pudo cargar el catálogo (curl " + code + ")"; return }
            try {
                var data = JSON.parse(catalogOut.text)
                var arr = (data && data.pets) ? data.pets : []
                var out = []
                for (var i = 0; i < arr.length; i++) {
                    var e = arr[i]
                    if (!e || !e.slug || !e.spritesheetUrl) continue
                    out.push({ slug: e.slug, displayName: e.displayName || e.slug, kind: e.kind || "", sheetUrl: e.spritesheetUrl })
                }
                root.catalogAll = out
                root.catalogStatus = out.length + " mascotas disponibles"
            } catch (err) {
                root.catalogStatus = "Error al leer el catálogo: " + err
            }
        }
    }

    Process {
        id: installProc
        stdout: StdioCollector { id: installOut; waitForEnd: true }
        stderr: StdioCollector { id: installErr; waitForEnd: true }
        onExited: function(code, status) {
            var slug = root.catalogInstalling
            root.catalogInstalling = ""
            if (code === 0) {
                if (slug) root.saveSetting("petId", slug)
                library.rescan()
            } else {
                console.warn("hermes-pets: install failed (" + code + "): " + installErr.text.trim())
            }
        }
    }

    Process {
        id: removeProc
        stdout: StdioCollector { id: removeOut; waitForEnd: true }
        stderr: StdioCollector { id: removeErr; waitForEnd: true }
        onExited: function(code, status) {
            if (code === 0) {
                root.saveSetting("petId", "")
                library.rescan()
            } else {
                console.warn("hermes-pets: remove failed (" + code + "): " + removeErr.text.trim())
            }
        }
    }

    // --- Panel popup ---
    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        padding: Style.space(14)
        contentWidth: panel.fittedContentWidth(400)
        contentHeight: panel.fittedContentHeight(content.implicitHeight + Style.space(8))

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
                text: "No hay mascotas instaladas\n\nPulsa el botón  +  para abrir el catálogo petdex."
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
                    tooltipText: root.pinned ? "Quitar del escritorio" : "Fijar al escritorio"
                    foreground: root.barForeground; fontFamily: root.fontFamily
                    onClicked: { root.saveSetting("pinned", !root.pinned) }
                }
                PanelActionButton {
                    id: removePetBtn
                    visible: root.petId !== ""
                    iconText: "\uf014"
                    tooltipText: "Eliminar mascota actual (borra del disco)"
                    foreground: root.barForeground; fontFamily: root.fontFamily
                    onClicked: root.removePet()
                }
                PanelActionButton {
                    iconText: "\uf067"
                    tooltipText: "Instalar mascota (catálogo petdex)"
                    foreground: root.barForeground; fontFamily: root.fontFamily
                    onClicked: root.openCatalog()
                }
            }

            PanelSeparator { foreground: root.barForeground }

            // Configuración
            PanelSectionHeader { text: "Configuración"; foreground: root.barForeground; fontFamily: root.fontFamily }

            Column { id: settingsColumn; width: parent.width; spacing: Style.space(4)

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlLaunch.width - Style.space(10); text: "Clic: abrir Hermes Desktop"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlLaunch; spacing: Style.space(4)
                        ToggleSwitch { checked: launchOnClick; onToggled: root.toggleLaunchOnClick() }
                    }
                }

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlMove.width - Style.space(10); text: "Permitir mover la mascota"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlMove; spacing: Style.space(4)
                        ToggleSwitch { checked: movable; onToggled: root.toggleMovable() }
                    }
                }

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlGravity.width - Style.space(10); text: "Gravedad (al soltar cae al suelo)"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlGravity; spacing: Style.space(4)
                        ToggleSwitch { checked: gravityEnabled; onToggled: root.toggleGravity() }
                    }
                }

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlActivity.width - Style.space(10); text: "Reaccionar a actividad"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlActivity; spacing: Style.space(4)
                        ToggleSwitch { checked: activityEnabled; onToggled: root.toggleActivity() }
                    }
                }

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlScale.width - Style.space(10); text: "Tamaño: " + Math.round(petScale * 100) + "%"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlScale; spacing: Style.space(4)
                        Button { text: "-"; width: Style.space(32); foreground: root.barForeground; fontFamily: root.fontFamily; fontSize: 14; onClicked: root.setScale(petScale - 0.25) }
                        Button { text: "+"; width: Style.space(32); foreground: root.barForeground; fontFamily: root.fontFamily; fontSize: 14; onClicked: root.setScale(petScale + 0.25) }
                    }
                }

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlAnim.width - Style.space(10); text: "Animación"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlAnim; spacing: Style.space(4)
                        ToggleSwitch { checked: animate; onToggled: root.toggleAnimate() }
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
                Text { width: parent.width; text: root.launchOnClick ? "Clic en la mascota: abre Hermes Desktop" : "Clic en la mascota: desactivado"; color: "#6c63ff"; font.family: root.fontFamily; font.pixelSize: Style.font.caption; opacity: 0.8 }
            }
        }
    }

    // --- Popup independiente: catálogo petdex ---
    KeyboardPanel {
        id: catalog
        anchorItem: root.anchorItem
        bar: root.bar
        owner: catalogOwner
        open: root.catalogOpen
        padding: Style.space(14)
        contentWidth: catalog.fittedContentWidth(460)
        contentHeight: catalog.fittedContentHeight(catalogCol.implicitHeight + Style.space(8))
        focusTarget: searchField
        onOpenChanged: if (!open && searchField) searchField.text = ""

        Column {
            id: catalogCol
            anchors.fill: parent
            anchors.margins: Style.space(4)
            spacing: Style.space(6)

            PanelHero {
                width: parent.width
                title: "Catálogo petdex"
                meta: root.catalogStatus
                foreground: root.barForeground
                fontFamily: root.fontFamily
            }

            PanelSeparator { foreground: root.barForeground }

            TextField {
                id: searchField
                width: parent.width
                placeholderText: "Buscar por nombre o slug…"
                foreground: root.barForeground
                Keys.onEscapePressed: root.catalogOpen = false
            }

            ListView {
                id: catalogList
                width: parent.width
                height: Style.space(340)
                clip: true
                spacing: Style.space(2)
                boundsBehavior: Flickable.StopAtBounds
                model: root.filterCatalog(searchField.text, root.catalogAll)
                delegate: CatalogRow {
                    fontFamily: root.fontFamily
                    smoothScaling: root.smoothScaling
                    foreground: root.barForeground
                    installed: root.isInstalled(modelData.slug)
                    busy: root.catalogInstalling === modelData.slug
                    onClicked: root.installCatalogPet(modelData.slug)
                }

                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }

            Text {
                width: parent.width
                visible: catalogList.count === 0
                text: root.catalogAll.length === 0 ? root.catalogStatus : "Sin resultados para «" + searchField.text + "»"
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                opacity: 0.6
                wrapMode: Text.WordWrap
            }
        }
    }

    // --- Pinned sprite layer con overlay de funciones ---
    Item {
        id: stage
        parent: root.shownPinned ? pinnedWindow.contentItem : null
        visible: root.shownPinned
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
                transformOrigin: Item.TopLeft
                sheetUrl: root.currentPet ? root.currentPet.sheetUrl : ""
                smoothScaling: root.smoothScaling
                running: root.shownPinned && root.animate && root.currentPet !== null
                randomBehavior: root.randomBehavior
                onDragged: function(dx, dy) { root.dragPet(dx, dy) }
                onDropped: root.dropPet()
                onClicked: root.launchApp()
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
        visible: root.shownPinned
        implicitWidth: 192 * petScale
        implicitHeight: 208 * petScale
        WlrLayershell.namespace: "hermes-pets"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        onScreenChanged: { if (root.pinned) root.resyncScreen() }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        anchors.top: true
        anchors.left: true
        margins {
            left: root.clamp(
                (root.pinnedX >= 0 ? root.pinnedX : Math.round(root.screenW / 2) - 96) + root.dragDx + root.gravWalkOffset + root.roamOffset,
                0, Math.max(0, root.screenW - 192 * petScale))
            top: root.clamp(
                (root.pinnedY >= 0 ? root.pinnedY : Math.round(root.screenH / 2) - 104) + root.dragDy + root.gravDropOffset,
                0, Math.max(0, Math.round(Math.max(0, root.screenH - Math.round(208 * petScale + 6)))))
        }
    }
}
