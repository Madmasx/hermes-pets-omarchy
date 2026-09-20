.pragma library

// Coordinador global de la ventana pinned del pet. El bar quickshell crea una
// instancia del widget por monitor (Bar.qml: "a widget that appears once in the
// layout is still live once per screen"), asi que con varias pantallas hay
// varias mascotas vivas. Todas las instancias viven en el MISMO engine QML, y
// un modulo .pragma library es un singleton por engine, asi que aqui se
// decide cual instancia obtiene la ventana pinned (owner).
//
// Mientras el owner pida mantenerla (claim), las demas esperan; si el owner
// suelta (release) o pierde claim, la siguiente que reintente releva.

var _owner = ""
var _counter = 0

function _next() { return "pin-" + (++_counter) }

function nextId() { return _next() }
function claim(id) {
  if (_owner === "" || _owner === id) {
    _owner = id
    return true
  }
  return false
}

function release(id) {
  if (_owner === id) {
    _owner = ""
    return true
  }
  return false
}

function stats() { return "owner=" + _owner + " counter=" + _counter }