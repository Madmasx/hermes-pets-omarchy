import QtQuick
import "Sprite.js" as Sprite

Item {
  id: root

  property url sheetUrl
  property bool smoothScaling: true
  property bool running: false
  property bool randomBehavior: true
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
      // First drag movement: center the pet under the cursor.
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
    if (dragMoved) dropped()
    else {
      wave()
      clicked()
    }
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

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: {
      root.look = Sprite.lookCell(mouseX - width / 2, mouseY - height / 2)
      root.hovering = true
    }
    onPositionChanged: function(event) {
      root.look = Sprite.lookCell(event.x - width / 2, event.y - height / 2)
      if (pressed) root.drag(event.x, event.y)
    }
    onExited: root.leave()
    onPressed: function(event) { root.press(event.x, event.y) }
    onReleased: root.release()
  }
}
