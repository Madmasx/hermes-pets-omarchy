.pragma library

// Global coordinator for the single pinned pet window across multi-monitor bars.
// Uses a short lease (heartbeat) so a hot-reloaded or destroyed instance can
// never permanently wedge ownership.

var LEASE_MS = 5000
var _owner = ""
var _expiresAt = 0
var _counter = 0

function nextId() { return "pin-" + (++_counter) }

function claim(id) {
  var now = Date.now()
  if (_owner === "" || _owner === id || now > _expiresAt) {
    _owner = id
    _expiresAt = now + LEASE_MS
    return true
  }
  return false
}

function release(id) {
  if (_owner === id) {
    _owner = ""
    _expiresAt = 0
    return true
  }
  return false
}

function stats() { return "owner=" + _owner + " counter=" + _counter + " ttl=" + Math.max(0, _expiresAt - Date.now()) }
