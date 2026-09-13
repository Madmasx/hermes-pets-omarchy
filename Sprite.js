.pragma library

// Row and frame durations (ms) per pose.
// Hermes canonical activity names (PetState enum values) mapped to Codex atlas rows.
// Codex atlas: 8 columns x 9 rows of 192x208 cells (1536x1872).
//   row 0 idle        row 1 running-right  row 2 running-left
//   row 3 waving      row 4 jumping        row 5 failed
//   row 6 waiting     row 7 running        row 8 review
var POSES = {
  idle:    { row: 0, durations: [280, 110, 110, 140, 140, 320] },
  waving:  { row: 3, durations: [140, 140, 140, 280] },
  jumping: { row: 4, durations: [140, 140, 140, 140, 280] },
  waiting: { row: 6, durations: [150, 150, 150, 150, 150, 260] },
  running: { row: 7, durations: [120, 120, 120, 120, 120, 220] }
}

// Hermes agent activity poses — canonical Hermes state names → row + durations.
// These are the values written by activity-writer.py into activity-state.json.
// The watcher translates Hermes runtime signals (active_agents, tool events) to
// these pose labels.
var ACTIVITY_POSES = {
  idle:    { row: 0, durations: [280, 110, 110, 140, 140, 320] },   // nothing happening
  run:     { row: 7, durations: [120, 120, 120, 120, 120, 220] },   // turn/tool in flight
  review:  { row: 8, durations: [150, 150, 150, 150, 150, 260] },   // model thinking/reading
  wave:    { row: 3, durations: [140, 140, 140, 280] },              // turn finished cleanly
  jump:    { row: 4, durations: [140, 140, 140, 140, 280] },         // plan finished (celebrate)
  failed:  { row: 5, durations: [150, 150, 150, 150, 150, 260] },   // tool/turn failed
  waiting: { row: 6, durations: [150, 150, 150, 150, 150, 260] }    // blocked on user (clarify/approval)
}

// Random behaviour pool, played ACTION_LOOPS times.
var ACTIONS = ["waving", "jumping", "waiting", "running"]
var ACTION_LOOPS = 2

function pickAction(previous, random) {
  var pool = ACTIONS.filter(function(name) { return name !== previous })
  return pool[Math.floor(random * pool.length)]
}

function drawWaitMs(random) {
  return 8000 + Math.floor(random * 12001)
}

// Rows 9-10: 16-way look wheel, index 0 = up, clockwise.
var LOOK_ROWS = 11
var NEUTRAL_FRAME = 6

function lookCell(dx, dy) {
  var index = Math.round(((Math.atan2(dx, -dy) * 180 / Math.PI + 360) % 360) / 22.5) % 16
  return { row: 9 + Math.floor(index / 8), frame: index % 8 }
}
