.pragma library

// Self-contained physics & ambient-AI behavior engine for Hermes Pets.
// Inspired by Hermes Desktop's platformer wander (exponential dwell, loaf-first
// rhythm, foot-synced stride, inward facing) and enhanced with throw momentum,
// wall/floor bounces, and playful arc hops — with zero external dependencies.

var STRIDE_PER_LOOP = 0.8
var GRAVITY_PX_S2 = 5200
var MAX_DT_S = 0.05
var ARRIVE_EPS = 1.5
var FEET_DROP_PX = 4

// Ambient-AI rhythm: calm, believable critter (loaf > move).
var PAUSE_MIN_MS = 1500
var PAUSE_MEAN_MS = 4200
var PAUSE_MAX_MS = 13000
var REST_CHANCE = 0.58
var HOP_CHANCE = 0.18
var STROLL_MIN_FRACTION = 0.35
var STROLL_MIN_PX = 110
var STROLL_TOWARD_ROOM = 0.85

// Throw / bounce tuning.
var MAX_THROW_SPEED = 2200
var WALL_RESTITUTION = 0.55
var FLOOR_RESTITUTION = 0.34
var FLOOR_STOP_VY = 160
var GROUND_FRICTION = 0.84
var AIR_DRAG_ZERO_G = 0.92
var ZERO_G_STOP_SPEED = 35
var HOP_VY = -920
var HOP_VX_MIN = 140
var HOP_VX_MAX = 320

function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v))
}

// Memoryless exponential dwell: mostly short rests with occasional long loafs.
function dwellMs(rng) {
  var r = typeof rng === "function" ? rng() : Math.random()
  var u = Math.max(1e-6, 1 - r)
  return clamp(-Math.log(u) * PAUSE_MEAN_MS, PAUSE_MIN_MS, PAUSE_MAX_MS)
}

// Decide next ambient beat: "rest", "stroll", or "hop".
function chooseMove(allowHop, rng) {
  var r = typeof rng === "function" ? rng : Math.random
  if (r() < REST_CHANCE) return "rest"
  if (allowHop && r() < HOP_CHANCE) return "hop"
  return "stroll"
}

// Pick a meaningful stroll target X, biased toward the roomier side.
function pickStrollTarget(fromX, maxLeft, rng) {
  if (maxLeft <= 4) return 0
  var r = typeof rng === "function" ? rng : Math.random
  var roomLeft = Math.max(0, fromX)
  var roomRight = Math.max(0, maxLeft - fromX)
  var goRight = (r() < STROLL_TOWARD_ROOM) === (roomRight >= roomLeft)
  var room = goRight ? roomRight : roomLeft
  var minDist = Math.min(room, Math.max(maxLeft * STROLL_MIN_FRACTION, STROLL_MIN_PX))
  var dist = minDist + r() * Math.max(0, room - minDist)
  return clamp(goRight ? fromX + dist : fromX - dist, 0, maxLeft)
}

// Foot-synced walk speed in px/s derived from sprite width and loop duration.
function walkSpeedPxS(petW, loopMs) {
  var sec = Math.max(0.15, (loopMs || 820) / 1000)
  return Math.max(24, (petW * STRIDE_PER_LOOP) / sec)
}

// Art faces left by default; mirror when resting on the left half of the screen
// so the pet looks inward toward the desktop center.
function inwardMirror(leftX, petW, screenW) {
  return (leftX + petW * 0.5) < (screenW * 0.5)
}

// Compute directional walk row & horizontal mirror flag.
function walkPresentation(dir, hasLocomotion) {
  if (dir === 0) return { pose: "idle", mirror: false }
  if (hasLocomotion) {
    return { pose: dir > 0 ? "running-right" : "running-left", mirror: false }
  }
  return { pose: "running", mirror: dir > 0 }
}

// Compute a playful arc hop velocity toward the roomier side.
function planHopVelocity(fromX, maxLeft, rng) {
  var r = typeof rng === "function" ? rng : Math.random
  var roomLeft = Math.max(0, fromX)
  var roomRight = Math.max(0, maxLeft - fromX)
  var dir = (r() < 0.8) === (roomRight >= roomLeft) ? 1 : -1
  var vx = dir * (HOP_VX_MIN + r() * (HOP_VX_MAX - HOP_VX_MIN))
  return { vx: vx, vy: HOP_VY }
}

// Clamp throw velocity vector to MAX_THROW_SPEED.
function clampVelocity(vx, vy) {
  var speed = Math.hypot(vx, vy)
  if (!isFinite(speed) || speed <= MAX_THROW_SPEED) {
    return { vx: isFinite(vx) ? vx : 0, vy: isFinite(vy) ? vy : 0 }
  }
  var scale = MAX_THROW_SPEED / speed
  return { vx: vx * scale, vy: vy * scale }
}

// Advance free-body physics (gravity, throw momentum, wall & floor bounces).
// Returns { x, y, vx, vy, landed, hardImpact }.
function stepBody(state, dt, maxLeft, floorY, gravityEnabled) {
  var stepDt = Math.min(MAX_DT_S, Math.max(0.001, dt))
  var x = state.x
  var y = state.y
  var vx = state.vx
  var vy = state.vy
  var hardImpact = false

  if (gravityEnabled) {
    vy += GRAVITY_PX_S2 * stepDt
  } else {
    var drag = Math.pow(AIR_DRAG_ZERO_G, stepDt * 60)
    vx *= drag
    vy *= drag
  }

  x += vx * stepDt
  y += vy * stepDt

  // Left / right screen edge bounce.
  if (x < 0) {
    if (Math.abs(vx) > 650) hardImpact = true
    x = 0
    vx = Math.abs(vx) * WALL_RESTITUTION
  } else if (x > maxLeft) {
    if (Math.abs(vx) > 650) hardImpact = true
    x = maxLeft
    vx = -Math.abs(vx) * WALL_RESTITUTION
  }

  // Ceiling bounce.
  if (y < 0) {
    if (Math.abs(vy) > 650) hardImpact = true
    y = 0
    vy = Math.abs(vy) * 0.4
  }

  var landed = false
  if (gravityEnabled) {
    if (y >= floorY) {
      if (vy > 1100) hardImpact = true
      y = floorY
      if (Math.abs(vy) >= FLOOR_STOP_VY) {
        vy = -Math.abs(vy) * FLOOR_RESTITUTION
        vx *= GROUND_FRICTION
      } else {
        vy = 0
        vx *= Math.pow(GROUND_FRICTION, 2)
        if (Math.abs(vx) < 25) {
          vx = 0
          landed = true
        }
      }
    }
  } else {
    if (y > floorY) {
      if (Math.abs(vy) > 650) hardImpact = true
      y = floorY
      vy = -Math.abs(vy) * WALL_RESTITUTION
    }
    if (Math.hypot(vx, vy) < ZERO_G_STOP_SPEED) {
      vx = 0
      vy = 0
      landed = true
    }
  }

  return { x: x, y: y, vx: vx, vy: vy, landed: landed, hardImpact: hardImpact }
}

// Contact shadow scale & opacity based on altitude above the floor.
function shadowMetrics(y, floorY, petH) {
  var altitude = Math.max(0, floorY - y)
  var norm = clamp(altitude / Math.max(120, petH * 2.2), 0, 1)
  return {
    scale: 1 - norm * 0.55,
    opacity: (1 - norm * 0.85) * 0.42
  }
}
