pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "PinCoordinator.js" as PinGate
import "PetPhysics.js" as Physics

Panel {
    id: root
    moduleName: "madmasx.hermes-pets"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    readonly property var barIdentity: hostWidget || root

    readonly property string home: Quickshell.env("HOME")
    readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/+$/, "")
    readonly property string manager: root.pluginDir + "/petdex.py"

    readonly property string petsDir: {
        var raw = String(root.setting("petsDir", "") || "").trim()
        if (!raw) return root.pluginDir + "/pets"
        return raw === "~" || raw.indexOf("~/") === 0 ? root.home + raw.slice(1) : raw
    }

    readonly property string petId: String(root.setting("petId", ""))
    readonly property bool smoothScaling: root.setting("smooth", true) === true
    readonly property bool animate: root.setting("animate", true) === true
    readonly property bool randomBehavior: root.setting("randomBehavior", true) === true
    readonly property bool freeFlight: root.setting("freeFlight", false) === true
    readonly property bool pinned: root.setting("pinned", false) === true
    readonly property int pinnedX: Number(root.setting("pinnedX", -1))
    readonly property int pinnedY: Number(root.setting("pinnedY", -1))
    readonly property bool activityEnabled: root.setting("activityEnabled", false) === true
    readonly property bool movable: root.setting("movable", true) === true
    readonly property bool launchOnClick: root.setting("launchOnClick", false) === true
    readonly property string clickCommand: String(root.setting("clickCommand", "") || "").trim()
    readonly property bool gravityEnabled: root.setting("gravityEnabled", true) === true
    readonly property real petScale: {
        var v = Number(root.setting("petScale", 0.75))
        return isFinite(v) && v > 0 ? Math.max(0.25, Math.min(3.0, v)) : 0.75
    }

    // --- Single pinned pet across multi-monitor bars -------------------------
    readonly property string pinToken: PinGate.nextId()
    property bool pinEligible: false
    readonly property bool shownPinned: root.pinned && root.pinEligible && root.currentPet !== null

    function syncPinEligible() {
        if (root.pinned) root.pinEligible = PinGate.claim(root.pinToken)
        else if (PinGate.release(root.pinToken)) root.pinEligible = false
    }

    Component.onDestruction: PinGate.release(root.pinToken)

    Timer {
        interval: 250
        repeat: true
        running: root.pinned && !root.pinEligible
        onTriggered: root.syncPinEligible()
    }
    Timer {
        interval: 2000
        repeat: true
        running: root.pinned && root.pinEligible
        onTriggered: root.syncPinEligible()
    }

    onPinnedChanged: {
        if (root.pinned) {
            root.close()
            root.syncPinEligible()
            if (root.shownPinned && root.gravityEnabled) root.dropIfAirborne()
        } else if (PinGate.release(root.pinToken)) {
            root.pinEligible = false
        }
    }

    onShownPinnedChanged: {
        if (root.shownPinned && root.gravityEnabled) root.dropIfAirborne()
        else if (!root.shownPinned) root.stopBody()
    }

    // --- Geometry helpers ----------------------------------------------------
    readonly property real screenW: root.pinned && pinnedWindow && pinnedWindow.screen ? pinnedWindow.screen.width : (Quickshell.screen ? Quickshell.screen.width : 1920)
    readonly property real screenH: root.pinned && pinnedWindow && pinnedWindow.screen ? pinnedWindow.screen.height : (Quickshell.screen ? Quickshell.screen.height : 1080)

    function clamp(v, lo, hi) { return Physics.clamp(v, lo, hi) }
    function petWidthPx() { return Math.round(192 * root.petScale) }
    function petHeightPx() { return Math.round(208 * root.petScale) }
    function maxLeft() { return Math.max(0, root.screenW - root.petWidthPx()) }
    function floorY() { return Math.max(0, root.screenH - root.petHeightPx() + Physics.FEET_DROP_PX) }
    function baseLeft() { return root.pinnedX >= 0 ? root.pinnedX : Math.round(root.maxLeft() / 2) }
    function baseTop() { return root.pinnedY >= 0 ? root.pinnedY : Math.round(root.floorY() / 2) }

    readonly property real liveLeft: root.physActive
        ? root.physX
        : root.clamp(root.baseLeft() + root.dragDx + root.roamOffset, 0, root.maxLeft())
    readonly property real liveTop: root.physActive
        ? root.physY
        : root.clamp(root.baseTop() + root.dragDy + root.roamOffsetY, 0, root.floorY())

    readonly property var shadowInfo: Physics.shadowMetrics(root.liveTop, root.floorY(), root.petHeightPx())

    function resyncScreen() {
        var clampedX = Math.round(root.clamp(root.baseLeft(), 0, root.maxLeft()))
        var clampedY = Math.round(root.clamp(root.baseTop(), 0, root.floorY()))
        if (root.pinnedX >= 0 && clampedX !== root.pinnedX) root.saveSetting("pinnedX", clampedX)
        if (root.pinnedY >= 0 && clampedY !== root.pinnedY) root.saveSetting("pinnedY", clampedY)
        if (root.shownPinned && root.gravityEnabled && !root.grabbing) root.dropIfAirborne()
    }

    // --- Drag, throw momentum, gravity & bounce physics ----------------------
    property real dragDx: 0
    property real dragDy: 0
    property bool grabbing: false
    property real throwVx: 0
    property real throwVy: 0
    property double lastDragMs: 0

    property bool physActive: false
    property bool physBonked: false
    property real physX: 0
    property real physY: 0
    property real physVx: 0
    property real physVy: 0
    property double physLastMs: 0

    Timer {
        id: physLoop
        interval: 16
        repeat: true
        running: root.physActive && root.shownPinned && !root.grabbing
        onTriggered: root.physTick()
    }

    function stopBody() {
        root.physActive = false
        root.physVx = 0
        root.physVy = 0
    }

    function startBody(x, y, vx, vy, playJump) {
        if (!root.shownPinned) return
        root.physX = root.clamp(x, 0, root.maxLeft())
        root.physY = root.clamp(y, 0, root.floorY())
        root.physVx = vx
        root.physVy = vy
        root.physBonked = false
        root.physLastMs = Date.now()
        root.physActive = true
        if (playJump && sprite && root.animate) {
            sprite.beginAction("jumping", 9999)
            if (sprite.ticking) sprite.arm()
        }
    }

    function dropIfAirborne() {
        if (!root.shownPinned || root.grabbing || root.physActive || root.freeFlight) return
        var y = root.baseTop()
        if (y < root.floorY() - 2) {
            root.startBody(root.baseLeft(), y, 0, 0, true)
        }
    }

    function hopCelebrate() {
        if (!root.shownPinned || root.grabbing) return
        var x = root.liveLeft
        var y = root.liveTop
        var vx = (Math.random() - 0.5) * 260
        root.roamWalking = false
        root.roamOffset = 0
        root.startBody(x, y, vx, -820, true)
    }

    function physTick() {
        if (root.grabbing || !root.shownPinned) { root.stopBody(); return }
        var now = Date.now()
        var dt = Math.min(Physics.MAX_DT_S, Math.max(0.004, (now - root.physLastMs) / 1000))
        root.physLastMs = now

        var useGravity = root.gravityEnabled && !root.freeFlight
        var res = Physics.stepBody(
            { x: root.physX, y: root.physY, vx: root.physVx, vy: root.physVy },
            dt, root.maxLeft(), root.floorY(), useGravity
        )
        root.physX = res.x
        root.physY = res.y
        root.physVx = res.vx
        root.physVy = res.vy

        if (res.hardImpact) {
            root.physBonked = true
            if (sprite && root.animate && sprite.pose !== "failed") {
                sprite.beginAction("failed", 1)
                if (sprite.ticking) sprite.arm()
            }
        }

        if (res.landed) {
            var fx = Math.round(res.x)
            var fy = Math.round(res.y)
            var bonked = root.physBonked
            root.saveSetting("pinnedX", fx)
            root.saveSetting("pinnedY", fy)
            Qt.callLater(function() {
                root.stopBody()
                root.physBonked = false
                root.roamPauseUntil = Date.now() + Physics.dwellMs()
                if (sprite && !root.roamWalking) {
                    if (root.activityEnabled && root.activityPose !== "idle") root.applyActivityPose()
                    else if (bonked && root.animate) { sprite.beginAction("failed", 1); if (sprite.ticking) sprite.arm() }
                    else sprite.beginIdle()
                }
            })
        }
    }

    function dragPet(dx, dy) {
        if (!root.pinned || !root.movable) return
        var now = Date.now()
        if (!root.grabbing) {
            if (root.physActive) {
                root.saveSetting("pinnedX", Math.round(root.physX))
                root.saveSetting("pinnedY", Math.round(root.physY))
                root.stopBody()
            }
            if (root.roamWalking || root.roamOffset !== 0) {
                root.roamWalking = false
                root.roamCommit()
                if (sprite) sprite.beginIdle()
            }
            root.throwVx = 0
            root.throwVy = 0
            root.lastDragMs = now
        } else {
            var dt = (now - root.lastDragMs) / 1000
            if (dt > 0.002 && dt < 0.15) {
                root.throwVx = root.throwVx * 0.45 + (dx / dt) * 0.55
                root.throwVy = root.throwVy * 0.45 + (dy / dt) * 0.55
            }
            root.lastDragMs = now
        }
        root.grabbing = true
        root.dragDx += dx
        root.dragDy += dy
    }

    function dropPet() {
        if (!root.pinned) return
        var nx = Math.round(root.clamp(root.baseLeft() + root.dragDx, 0, root.maxLeft()))
        var ny = Math.round(root.clamp(root.baseTop() + root.dragDy, 0, root.floorY()))
        root.dragDx = 0
        root.dragDy = 0
        root.grabbing = false

        var stale = (Date.now() - root.lastDragMs) > 120
        var vel = stale ? { vx: 0, vy: 0 } : Physics.clampVelocity(root.throwVx, root.throwVy)
        root.throwVx = 0
        root.throwVy = 0

        root.saveSetting("pinnedX", nx)
        root.saveSetting("pinnedY", ny)

        var flung = Math.hypot(vel.vx, vel.vy) > 110
        var airborne = root.gravityEnabled && !root.freeFlight && ny < root.floorY() - 2
        if (flung || airborne) {
            root.startBody(nx, ny, vel.vx, vel.vy, root.gravityEnabled || root.freeFlight)
        }
    }

    // --- Calm ambient roaming (Hermes Game-AI + playful hops + free flight) --
    property real roamOffset: 0
    property real roamOffsetY: 0
    property bool roamWalking: false
    property bool roamFlying: false
    property bool roamMirror: false
    property real roamTargetLeft: 0
    property real roamTargetTop: 0
    property double roamPauseUntil: 0

    function roamAllowed() {
        return root.shownPinned && root.animate && root.randomBehavior && root.currentPet !== null
            && !root.grabbing && !root.physActive
            && (!root.activityEnabled || root.activityPose === "idle")
    }

    function roamPause() {
        root.roamWalking = false
        root.roamFlying = false
        root.roamMirror = false
        if (sprite && sprite.pose !== "idle") { sprite.beginIdle(); if (sprite.ticking) sprite.arm() }
        root.roamPauseUntil = Date.now() + Physics.dwellMs()
    }

    function roamCommit() {
        if (root.roamOffset === 0 && root.roamOffsetY === 0) return
        var nx = Math.round(root.clamp(root.baseLeft() + root.roamOffset, 0, root.maxLeft()))
        var ny = Math.round(root.clamp(root.baseTop() + root.roamOffsetY, 0, root.floorY()))
        root.roamOffset = 0
        root.roamOffsetY = 0
        root.saveSetting("pinnedX", nx)
        root.saveSetting("pinnedY", ny)
    }

    function roamPlan() {
        var maxL = root.maxLeft()
        var floor = root.floorY()
        if (maxL < 24) { root.roamPause(); return }
        var curX = root.clamp(root.baseLeft() + root.roamOffset, 0, maxL)
        var curY = root.clamp(root.baseTop() + root.roamOffsetY, 0, floor)

        if (root.freeFlight) {
            if (Physics.chooseMove(false) === "rest") {
                root.roamPause()
                return
            }
            var dst = Physics.pickFlightTarget(curX, curY, maxL, floor)
            var fdx = dst.x - curX
            var fdy = dst.y - curY
            if (Math.hypot(fdx, fdy) < 24) { root.roamPause(); return }
            var fdir = fdx >= 0 ? 1 : -1
            var steep = Math.abs(fdy) > Math.abs(fdx) * 0.65
            var fpres = steep
                ? { pose: "jumping", mirror: fdir > 0 }
                : Physics.walkPresentation(fdir, sprite ? sprite.hasLocomotion : false)
            root.roamWalking = true
            root.roamFlying = true
            root.roamMirror = fpres.mirror
            root.roamTargetLeft = dst.x
            root.roamTargetTop = dst.y
            if (sprite) {
                sprite.beginAction(fpres.pose, 9999)
                if (sprite.ticking) sprite.arm()
            }
            return
        }

        var move = Physics.chooseMove(root.gravityEnabled && curY >= floor - 4)

        if (move === "rest") {
            root.roamPause()
            return
        }

        if (move === "hop") {
            var hop = Physics.planHopVelocity(curX, maxL)
            root.roamCommit()
            root.startBody(curX, curY, hop.vx, hop.vy, true)
            return
        }

        var target = Physics.pickStrollTarget(curX, maxL)
        if (Math.abs(target - curX) < 16) { root.roamPause(); return }
        var dir = target > curX ? 1 : -1
        var pres = Physics.walkPresentation(dir, sprite ? sprite.hasLocomotion : false)
        root.roamWalking = true
        root.roamFlying = false
        root.roamMirror = pres.mirror
        root.roamTargetLeft = target
        root.roamTargetTop = curY
        if (sprite) {
            sprite.beginAction(pres.pose, 9999)
            if (sprite.ticking) sprite.arm()
        }
    }

    function roamStep() {
        if (!root.roamAllowed()) {
            if (root.roamWalking) { root.roamWalking = false; root.roamFlying = false; root.roamMirror = false; if (sprite) sprite.beginIdle() }
            if (root.roamOffset !== 0 || root.roamOffsetY !== 0) root.roamCommit()
            root.roamPauseUntil = 0
            if (root.activityEnabled && !root.physActive) root.applyActivityPose()
            return
        }
        if (root.roamWalking) {
            var dt = roamLoop.interval / 1000
            if (root.roamFlying) {
                var fspeed = Physics.flightSpeedPxS(root.petWidthPx(), sprite ? sprite.loopMs : 820)
                var cx = root.baseLeft() + root.roamOffset
                var cy = root.baseTop() + root.roamOffsetY
                var rx = root.roamTargetLeft - cx
                var ry = root.roamTargetTop - cy
                var dist = Math.hypot(rx, ry)
                var fstep = fspeed * dt
                if (dist <= Math.max(Physics.ARRIVE_EPS, fstep)) {
                    root.roamOffset += rx
                    root.roamOffsetY += ry
                    root.roamWalking = false
                    root.roamFlying = false
                    root.roamMirror = false
                    root.roamCommit()
                    root.roamPause()
                } else {
                    root.roamOffset += (rx / dist) * fstep
                    root.roamOffsetY += (ry / dist) * fstep
                }
                return
            }
            var speed = Physics.walkSpeedPxS(root.petWidthPx(), sprite ? sprite.loopMs : 820)
            var cur = root.baseLeft() + root.roamOffset
            var remaining = root.roamTargetLeft - cur
            var stepDist = speed * dt
            if (Math.abs(remaining) <= Math.max(Physics.ARRIVE_EPS, stepDist)) {
                root.roamOffset += remaining
                root.roamWalking = false
                root.roamMirror = false
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
        running: root.shownPinned && root.randomBehavior && root.animate
        onTriggered: root.roamStep()
    }

    // --- Active pet resolution -----------------------------------------------
    readonly property var currentPet: {
        var pets = library.pets
        if (!pets || pets.length === 0) return null
        if (root.petId) {
            for (var i = 0; i < pets.length; i++) {
                if (pets[i].name === root.petId) return pets[i]
            }
        }
        return pets[0]
    }

    readonly property string activePetName: root.currentPet ? root.currentPet.name : ""
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property color barForeground: (bar && bar.foreground !== undefined) ? bar.foreground : Commons.Color.popups.text

    onOpenedChanged: {
        if (opened) {
            root.panelNotice = ""
            library.rescan()
        }
    }

    function toggle() {
        if (root.opened) root.close()
        else root.open()
    }

    function launchApp() {
        if (!root.launchOnClick || !root.clickCommand) return
        if (root.bar && typeof root.bar.run === "function")
            root.bar.run(root.clickCommand)
    }

    function saveSetting(key, value) {
        var reg = (typeof shell !== "undefined" && shell && shell.pluginRegistry) ? shell.pluginRegistry : null
        if (!reg) return
        reg.setBarWidget(root.moduleName, key, value, {})
    }

    function toggleMovable() { root.saveSetting("movable", !root.movable) }
    function toggleLaunchOnClick() { root.saveSetting("launchOnClick", !root.launchOnClick) }
    function toggleRandomBehavior() { root.saveSetting("randomBehavior", !root.randomBehavior) }
    function toggleFreeFlight() {
        var next = !root.freeFlight
        root.saveSetting("freeFlight", next)
        if (!next && root.gravityEnabled && root.shownPinned) {
            root.roamFlying = false
            root.roamCommit()
            Qt.callLater(root.dropIfAirborne)
        }
    }
    function toggleSmooth() { root.saveSetting("smooth", !root.smoothScaling) }
    function toggleActivity() { root.saveSetting("activityEnabled", !root.activityEnabled) }
    function toggleAnimate() { root.saveSetting("animate", !root.animate) }

    function toggleGravity() {
        var next = !root.gravityEnabled
        root.saveSetting("gravityEnabled", next)
        if (!next) {
            root.stopBody()
            if (sprite && !root.roamWalking) sprite.beginIdle()
        } else if (root.shownPinned) {
            Qt.callLater(root.dropIfAirborne)
        }
    }

    function setScale(val) {
        var next = Math.round(Physics.clamp(val, 0.25, 3.0) * 100) / 100
        if (next === root.petScale) return
        // Anchor bottom-center so the pet's feet stay planted while scaling.
        if (root.pinnedX >= 0 && root.pinnedY >= 0) {
            var oldW = root.petWidthPx()
            var oldH = root.petHeightPx()
            var newW = Math.round(192 * next)
            var newH = Math.round(208 * next)
            var newMaxL = Math.max(0, root.screenW - newW)
            var newFloor = Math.max(0, root.screenH - newH + Physics.FEET_DROP_PX)
            var nx = Math.round(Physics.clamp(root.pinnedX + (oldW - newW) / 2, 0, newMaxL))
            var ny = Math.round(Physics.clamp(root.pinnedY + (oldH - newH), 0, newFloor))
            root.saveSetting("pinnedX", nx)
            root.saveSetting("pinnedY", ny)
        }
        root.saveSetting("petScale", next)
    }

    // --- Self-contained pet management via petdex.py -------------------------
    property string panelNotice: ""
    property bool catalogOpen: false
    property var catalogAll: []
    property string catalogStatus: "Pulsa + para cargar el catálogo"
    property string catalogInstalling: ""
    property bool removingPet: false

    QtObject { id: catalogOwner; function close() { root.catalogOpen = false } }

    function fetchCatalog(refresh) {
        if (catalogFetch.running) return
        root.catalogStatus = refresh ? "Actualizando catálogo…" : "Cargando catálogo…"
        catalogFetch.command = refresh
            ? ["python3", "-B", root.manager, "catalog", root.petsDir, "--refresh"]
            : ["python3", "-B", root.manager, "catalog", root.petsDir]
        catalogFetch.running = true
    }

    function openCatalog() {
        root.catalogOpen = true
        if (root.catalogAll.length === 0) root.fetchCatalog(false)
    }

    function installCatalogPet(slug) {
        if (!slug || root.catalogInstalling !== "") return
        root.catalogInstalling = slug
        root.catalogStatus = "Instalando " + slug + "…"
        installProc.command = ["python3", "-B", root.manager, "install", root.petsDir, slug]
        installProc.running = true
    }

    function removePet() {
        var target = root.activePetName
        if (!target || root.removingPet) return
        root.removingPet = true
        root.panelNotice = "Eliminando " + target + "…"
        removeProc.command = ["python3", "-B", root.manager, "remove", root.petsDir, target]
        removeProc.running = true
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

    // --- Activity file watcher (zero external `cat` polling) -----------------
    readonly property string activityFile: root.petsDir + "/activity-state.json"
    readonly property var transientActivityPoses: ["jump", "wave", "failed"]
    readonly property var sustainedActivityPoses: ["run", "review", "waiting"]
    property string activityPose: "idle"
    property string activityActivePose: "idle"

    WatchedFile {
        id: activityWatcher
        path: root.activityEnabled ? root.activityFile : ""
        onTextChanged: root.syncActivity()
    }

    function parseActivity(text) {
        if (!root.activityEnabled) return "idle"
        if (!text) return "idle"
        try {
            var data = JSON.parse(text)
            if (!data || typeof data.pose !== "string") return root.activityPose
            if (root.transientActivityPoses.indexOf(data.pose) >= 0) {
                var ts = Number(data.updated_at) || 0
                if (ts > 0 && (Date.now() / 1000 - ts) > 3) return "idle"
            }
            return data.pose
        } catch (e) { }
        return root.activityPose
    }

    function syncActivity() {
        root.activityPose = root.parseActivity(activityWatcher.text)
        root.applyActivityPose()
    }

    function resetActivityPose() {
        root.activityPose = "idle"
        root.activityActivePose = "idle"
        if (sprite && sprite.pose !== "idle") {
            sprite.beginIdle()
            if (sprite.ticking) sprite.arm()
        }
    }

    function applyActivityPose() {
        if (!sprite || root.roamWalking) return
        var pose = root.activityPose || "idle"
        if (pose === "idle") { root.resetActivityPose(); return }
        var sustained = root.sustainedActivityPoses.indexOf(pose) >= 0
        if (pose !== root.activityActivePose || (sustained && sprite.pose === "idle")) {
            root.activityActivePose = pose
            sprite.beginAction(pose, sustained ? 9999 : 1)
            if (sprite.ticking) sprite.arm()
        }
    }

    onActivityEnabledChanged: {
        if (root.activityEnabled) Qt.callLater(root.syncActivity)
        else root.resetActivityPose()
    }

    PetLibrary { id: library; active: root.hostWidget !== null; petsDir: root.petsDir }

    Process {
        id: catalogFetch
        stdout: StdioCollector { id: catalogOut; waitForEnd: true }
        stderr: StdioCollector { id: catalogErr; waitForEnd: true }
        onExited: function(code, status) {
            if (code !== 0) {
                var msg = catalogErr.text.trim() || ("código " + code)
                root.catalogStatus = "Error al cargar el catálogo: " + msg
                return
            }
            try {
                var data = JSON.parse(catalogOut.text)
                var arr = (data && data.pets) ? data.pets : []
                root.catalogAll = arr
                root.catalogStatus = arr.length + " mascotas disponibles"
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
                root.catalogStatus = "✓ Instalada: " + slug
                library.rescan()
            } else {
                var msg = installErr.text.trim() || ("código " + code)
                root.catalogStatus = "Error instalando " + slug + ": " + msg
                console.warn("hermes-pets: install failed (" + code + "): " + msg)
            }
        }
    }

    Process {
        id: removeProc
        stdout: StdioCollector { id: removeOut; waitForEnd: true }
        stderr: StdioCollector { id: removeErr; waitForEnd: true }
        onExited: function(code, status) {
            root.removingPet = false
            if (code === 0) {
                root.panelNotice = ""
                var remaining = library.pets.length - 1
                root.saveSetting("petId", "")
                if (remaining <= 0 && root.pinned) root.saveSetting("pinned", false)
                library.rescan()
            } else {
                var msg = removeErr.text.trim() || ("código " + code)
                root.panelNotice = "Error al eliminar: " + msg
                console.warn("hermes-pets: remove failed (" + code + "): " + msg)
            }
        }
    }

    // --- Main Panel popup ----------------------------------------------------
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

            PanelSectionHeader {
                text: "Mascotas instaladas (" + library.pets.length + ")"
                foreground: root.barForeground
                fontFamily: root.fontFamily
            }

            ListView {
                id: petList
                width: parent.width
                height: Math.min(Style.space(200), contentHeight)
                visible: library.pets.length > 0
                clip: true
                spacing: Style.space(2)
                boundsBehavior: Flickable.StopAtBounds
                model: library.pets
                delegate: PetRow {
                    fontFamily: root.fontFamily
                    smoothScaling: root.smoothScaling
                    foreground: root.barForeground
                    selected: modelData && modelData.name === root.activePetName
                    onClicked: {
                        if (modelData) {
                            root.saveSetting("petId", modelData.name)
                            if (!root.pinned) root.close()
                        }
                    }
                }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }

            Text {
                id: noPetsText
                width: parent.width
                textFormat: Text.PlainText
                text: "No hay mascotas instaladas.\nPulsa el botón  +  para abrir el catálogo petdex."
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                opacity: 0.65
                wrapMode: Text.WordWrap
                visible: library.pets.length === 0
            }

            PanelSeparator { foreground: root.barForeground }

            PanelSectionHeader { text: "Acciones"; foreground: root.barForeground; fontFamily: root.fontFamily }

            Row {
                spacing: Style.space(6)
                PanelActionButton {
                    visible: root.currentPet !== null
                    iconText: root.pinned ? "\uf024" : "\uf08d"
                    tooltipText: root.pinned ? "Quitar del escritorio" : "Fijar al escritorio"
                    foreground: root.barForeground; fontFamily: root.fontFamily
                    onClicked: root.saveSetting("pinned", !root.pinned)
                }
                PanelActionButton {
                    visible: root.shownPinned && root.animate
                    iconText: "\uf256"
                    tooltipText: "Saludar"
                    foreground: root.barForeground; fontFamily: root.fontFamily
                    onClicked: { if (sprite) sprite.wave() }
                }
                PanelActionButton {
                    id: removePetBtn
                    visible: root.activePetName !== "" && !root.removingPet
                    iconText: "\uf014"
                    tooltipText: "Eliminar mascota actual"
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

            Text {
                width: parent.width
                visible: root.panelNotice !== ""
                textFormat: Text.PlainText
                text: root.panelNotice
                color: Commons.Color.warning
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
            }

            PanelSeparator { foreground: root.barForeground }

            PanelSectionHeader { text: "Configuración"; foreground: root.barForeground; fontFamily: root.fontFamily }

            Column {
                id: settingsColumn
                width: parent.width
                spacing: Style.space(4)

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlAnim.width - Style.space(10); textFormat: Text.PlainText; text: "Animación"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlAnim; ToggleSwitch { checked: root.animate; onToggled: root.toggleAnimate() } }
                }

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlRoam.width - Style.space(10); textFormat: Text.PlainText; text: "Deambular por la pantalla"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlRoam; ToggleSwitch { checked: root.randomBehavior; onToggled: root.toggleRandomBehavior() } }
                }

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlFlight.width - Style.space(10); textFormat: Text.PlainText; text: "Vuelo libre (toda la pantalla)"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlFlight; ToggleSwitch { checked: root.freeFlight; onToggled: root.toggleFreeFlight() } }
                }

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlMove.width - Style.space(10); textFormat: Text.PlainText; text: "Permitir arrastrar"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlMove; ToggleSwitch { checked: root.movable; onToggled: root.toggleMovable() } }
                }

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlGravity.width - Style.space(10); textFormat: Text.PlainText; text: "Gravedad (cae al soltar)"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlGravity; ToggleSwitch { checked: root.gravityEnabled; onToggled: root.toggleGravity() } }
                }

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlSmooth.width - Style.space(10); textFormat: Text.PlainText; text: "Suavizado (apagar para pixel art)"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlSmooth; ToggleSwitch { checked: root.smoothScaling; onToggled: root.toggleSmooth() } }
                }

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlActivity.width - Style.space(10); textFormat: Text.PlainText; text: "Reaccionar a actividad"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlActivity; ToggleSwitch { checked: root.activityEnabled; onToggled: root.toggleActivity() } }
                }

                Row { width: parent.width; spacing: Style.space(10); visible: root.clickCommand !== ""
                    Text { width: parent.width - ctrlLaunch.width - Style.space(10); textFormat: Text.PlainText; text: "Ejecutar comando al hacer clic"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlLaunch; ToggleSwitch { checked: root.launchOnClick; onToggled: root.toggleLaunchOnClick() } }
                }

                Row { width: parent.width; spacing: Style.space(10)
                    Text { width: parent.width - ctrlScale.width - Style.space(10); textFormat: Text.PlainText; text: "Tamaño: " + Math.round(root.petScale * 100) + "%"; color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                    Row { id: ctrlScale; spacing: Style.space(4)
                        Button { text: "-"; width: Style.space(32); foreground: root.barForeground; fontFamily: root.fontFamily; fontSize: 14; onClicked: root.setScale(root.petScale - 0.25) }
                        Button { text: "+"; width: Style.space(32); foreground: root.barForeground; fontFamily: root.fontFamily; fontSize: 14; onClicked: root.setScale(root.petScale + 0.25) }
                    }
                }
            }

            PanelSeparator { foreground: root.barForeground }

            PanelSectionHeader { text: "Estado actual"; foreground: root.barForeground; fontFamily: root.fontFamily }

            Column {
                id: statusColumn
                width: parent.width
                spacing: Style.space(3)

                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: "Mascota: " + (root.currentPet ? root.currentPet.displayName : "Ninguna")
                    color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.body; opacity: 0.85
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: "Estado: " + (root.activityEnabled ? root.activityPose : "idle (sin monitoreo)")
                    color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; opacity: 0.7
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.pinned ? ("Fijada en escritorio" + (root.movable ? " (movible)" : " (fija)")) : "Solo en barra"
                    color: root.barForeground; font.family: root.fontFamily; font.pixelSize: Style.font.caption; opacity: 0.7
                }
                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: "Alt + rueda sobre la mascota para escalar"
                    color: Commons.Color.accent; font.family: root.fontFamily; font.pixelSize: Style.font.caption; opacity: 0.85
                }
            }
        }
    }

    // --- Built-in Petdex catalog popup ---------------------------------------
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

            Row {
                width: parent.width
                spacing: Style.space(6)

                TextField {
                    id: searchField
                    width: parent.width - refreshBtn.width - Style.space(6)
                    placeholderText: "Buscar por nombre o slug…"
                    foreground: root.barForeground
                    Keys.onEscapePressed: root.catalogOpen = false
                }

                PanelActionButton {
                    id: refreshBtn
                    iconText: "\uf021"
                    tooltipText: "Actualizar catálogo desde petdex.dev"
                    foreground: root.barForeground
                    fontFamily: root.fontFamily
                    onClicked: root.fetchCatalog(true)
                }
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
                textFormat: Text.PlainText
                text: root.catalogAll.length === 0 ? root.catalogStatus : "Sin resultados para «" + searchField.text + "»"
                color: root.barForeground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                opacity: 0.65
                wrapMode: Text.WordWrap
            }
        }
    }

    // --- Pinned desktop sprite stage -----------------------------------------
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
                scale: root.petScale
                transformOrigin: Item.TopLeft
                sheetUrl: root.currentPet ? root.currentPet.sheetUrl : ""
                smoothScaling: root.smoothScaling
                running: root.shownPinned && root.animate && root.currentPet !== null
                randomBehavior: root.randomBehavior
                mirrored: root.roamWalking
                    ? root.roamMirror
                    : (root.physActive
                        ? root.physVx > 20
                        : Physics.inwardMirror(root.liveLeft, root.petWidthPx(), root.screenW))
                shadowScale: root.shadowInfo.scale
                shadowOpacity: root.shadowInfo.opacity
                onDragged: function(dx, dy) { root.dragPet(dx * root.petScale, dy * root.petScale) }
                onDropped: root.dropPet()
                onClicked: root.launchApp()
                onDoubleClicked: root.hopCelebrate()
            }

            WheelHandler {
                acceptedModifiers: Qt.AltModifier
                onWheel: function(wheel) {
                    if (wheel.angleDelta.y === 0) return
                    var dir = wheel.angleDelta.y > 0 ? 1 : -1
                    root.setScale(root.petScale + dir * 0.1)
                }
            }
        }
    }

    // --- Pinned overlay window -----------------------------------------------
    PanelWindow {
        id: pinnedWindow
        visible: root.shownPinned
        implicitWidth: root.petWidthPx()
        implicitHeight: root.petHeightPx()
        WlrLayershell.namespace: "hermes-pets"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        onScreenChanged: { if (root.pinned) root.resyncScreen() }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        anchors.top: true
        anchors.left: true
        margins {
            left: root.liveLeft
            top: root.liveTop
        }
    }
}
