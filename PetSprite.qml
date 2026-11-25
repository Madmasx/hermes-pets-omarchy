import QtQuick
import "Sprite.js" as Sprite

Item {
  id: root

  property url sheetUrl
  property bool smoothScaling: true
  property bool running: false
  property bool randomBehavior: true
  property bool mirrored: false
  property real shadowScale: 1.0
  property real shadowOpacity: 0.42
  property string pose: "idle"
  property int frame: 0
  property int waitMs: 0
  property int loopsLeft: 0
  property string lastAction: ""
  property bool hovering: false
  property var look: ({ row: 0, frame: 0 })
  property bool neutralBeat: false
  property real pressX: 0
  property real pressY: 0
  property real lastX: 0
  property real lastY: 0
  property bool dragMoved: false
  property double lastClickMs: 0

  readonly property bool ready: sheet.status === Image.Ready
  readonly property int rows: ready ? Math.floor(sheet.sourceSize.height / 208) : 0
  readonly property bool lookEnabled: rows >= Sprite.LOOK_ROWS
  readonly property bool looking: running && lookEnabled && hovering && pose === "idle"
  readonly property bool ticking: running && !looking

  function poseDef(name) {
    return Sprite.POSES[name] || Sprite.ACTIVITY_POSES[name] || Sprite.LOCOMOTION[name] || Sprite.POSES.idle
  }

  function safeRow(rowIdx) {
    return (rows > 0 && rowIdx >= 0 && rowIdx < rows) ? rowIdx : 0
  }

  readonly property var durations: poseDef(pose).durations
  readonly property int loopMs: {
    var d = durations
    var total = 0
    for (var i = 0; i < d.length; i++) total += d[i]
    return total > 0 ? total : 820
  }
  readonly property bool hasLocomotion: rows >= 3
  readonly property var cell: looking ? look
    : (neutralBeat ? { row: 0, frame: Sprite.NEUTRAL_FRAME } : { row: safeRow(poseDef(pose).row), frame: frame })
  property url loggedSheet

  signal dragged(real dx, real dy)
  signal dropped()
  signal clicked()
  signal doubleClicked()

  implicitWidth: 192
  implicitHeight: 208
  clip: true

  function restart() {
    beginIdle()
    if (ticking) arm()
  }

  function arm() {
    var d = durations
    clock.interval = (d && frame >= 0 && frame < d.length) ? d[frame] : 160
    clock.restart()
  }

  function beginIdle() {
    frame = 0
    neutralBeat = false
    pose = "idle"
    waitMs = Sprite.drawWaitMs(Math.random())
  }

  function beginAction(name, loops) {
    frame = 0
    neutralBeat = false
    lastAction = name
    loopsLeft = Math.max(1, loops || 1)
    pose = name
  }

  function wave() {
    if (!running) return
    beginAction("waving", 1)
    if (ticking) arm()
    burstHearts(3)
  }

  function burstHearts(count) {
    if (!running) return
    var n = Math.min(heartRepeater.count, Math.max(1, count || 3))
    for (var i = 0; i < n; i++) {
      var h = heartRepeater.itemAt(i)
      if (h) h.launch(i * 75)
    }
  }

  function leave() {
    if (looking) {
      frame = 0
      neutralBeat = true
    }
    hovering = false
  }

  function press(x, y) {
    pressX = x
    pressY = y
    lastX = x
    lastY = y
    dragMoved = false
  }

  function drag(x, y) {
    var dx = x - pressX
    var dy = y - pressY
    if (!dragMoved && Math.hypot(dx, dy) < 2) return
    if (!dragMoved) {
      dragged(pressX - width / 2 + dx, pressY - height / 2 + dy)
      lastX = x
      lastY = y
      dragMoved = true
      return
    }
    dragged(x - lastX, y - lastY)
    lastX = x
    lastY = y
  }

  function release() {
    if (dragMoved) {
      dropped()
      return
    }
    var now = Date.now()
    if (now - lastClickMs <= 280) {
      lastClickMs = 0
      burstHearts(5)
      doubleClicked()
      return
    }
    lastClickMs = now
    wave()
    clicked()
  }

  function step() {
    if (neutralBeat) {
      neutralBeat = false
      arm()
      return
    }
    var elapsed = clock.interval
    frame = (frame + 1) % durations.length
    if (pose !== "idle") {
      if (frame === 0 && --loopsLeft <= 0) beginIdle()
    } else {
      waitMs -= elapsed
      if (randomBehavior && waitMs <= 0) beginAction(Sprite.pickAction(lastAction, Math.random()), Sprite.ACTION_LOOPS)
    }
    if (ticking) arm()
  }

  onRunningChanged: {
    if (running) beginIdle()
    else {
      clock.stop()
      pose = "idle"
      frame = 0
      neutralBeat = false
    }
  }

  onTickingChanged: {
    if (ticking) arm()
    else clock.stop()
  }

  onRandomBehaviorChanged: if (running) restart()

  Timer {
    id: clock
    repeat: false
    onTriggered: root.step()
  }

  // Soft contact shadow under feet; shrinks and fades with altitude.
  Rectangle {
    id: contactShadow
    z: 0
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 2
    width: Math.round(106 * root.shadowScale)
    height: Math.max(4, Math.round(22 * root.shadowScale))
    radius: height / 2
    color: "#000000"
    opacity: root.ready ? root.shadowOpacity : 0
    visible: root.ready && root.shadowOpacity > 0.02
  }

  // Mirrored sprite viewport so art can face inward or match travel direction.
  Item {
    id: spriteViewport
    z: 1
    anchors.fill: parent
    clip: true
    transform: Scale {
      origin.x: spriteViewport.width / 2
      xScale: root.mirrored ? -1 : 1
    }

    Image {
      id: sheet
      source: root.sheetUrl
      x: -root.cell.frame * 192
      y: -root.cell.row * 208
      smooth: root.smoothScaling
      asynchronous: true
      onStatusChanged: {
        if (status === Image.Error) console.warn("hermes-pets: failed to load " + source)
        if (status !== Image.Ready || source === root.loggedSheet) return
        root.loggedSheet = source
        if (sourceSize.width !== 1536 || sourceSize.height % 208 !== 0)
          console.warn("hermes-pets: unexpected atlas size " + sourceSize.width + "x" + sourceSize.height + " for " + source)
      }
    }
  }

  // Floating heart particles on click / double-click (zero timers when idle).
  Item {
    id: heartLayer
    z: 3
    anchors.fill: parent
    enabled: false

    Repeater {
      id: heartRepeater
      model: 5

      Text {
        id: heart
        property real startX: 96
        property real driftX: 0
        property real startY: 56
        property int delayMs: 0

        textFormat: Text.PlainText
        text: "♥"
        color: index % 2 === 0 ? "#ff5c8a" : "#ff85a8"
        font.pixelSize: 18 + (index % 3) * 4
        opacity: 0
        x: startX
        y: startY

        function launch(delay) {
          anim.stop()
          delayMs = delay
          startX = 62 + Math.random() * 68
          driftX = (Math.random() - 0.5) * 48
          startY = 48 + Math.random() * 28
          x = startX
          y = startY
          scale = 0.7
          opacity = 0
          anim.start()
        }

        SequentialAnimation {
          id: anim
          PauseAnimation { duration: heart.delayMs }
          ParallelAnimation {
            NumberAnimation { target: heart; property: "y"; from: heart.startY; to: heart.startY - 52; duration: 760; easing.type: Easing.OutCubic }
            NumberAnimation { target: heart; property: "x"; from: heart.startX; to: heart.startX + heart.driftX; duration: 760; easing.type: Easing.OutSine }
            NumberAnimation { target: heart; property: "scale"; from: 0.7; to: 1.15; duration: 300; easing.type: Easing.OutCubic }
            SequentialAnimation {
              NumberAnimation { target: heart; property: "opacity"; from: 0; to: 0.95; duration: 140; easing.type: Easing.OutCubic }
              NumberAnimation { target: heart; property: "opacity"; from: 0.95; to: 0; duration: 620; easing.type: Easing.InQuad }
            }
          }
        }
      }
    }
  }

  MouseArea {
    id: mouse
    z: 2
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    onEntered: {
      var lx = (mouseX - width / 2) * (root.mirrored ? -1 : 1)
      root.look = Sprite.lookCell(lx, mouseY - height / 2)
      root.hovering = true
    }
    onPositionChanged: function(event) {
      var lx = (event.x - width / 2) * (root.mirrored ? -1 : 1)
      root.look = Sprite.lookCell(lx, event.y - height / 2)
      if (pressed) root.drag(event.x, event.y)
    }
    onExited: root.leave()
    onPressed: function(event) { root.press(event.x, event.y) }
    onReleased: root.release()
  }
}
