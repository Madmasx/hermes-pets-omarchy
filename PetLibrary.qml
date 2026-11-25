import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Enumerates <petsDir>/*/ using the bundled petdex.py helper and keeps valid pets.
QtObject {
  id: root

  property string petsDir: ""
  property bool active: false
  property var pets: []
  property string scanDir: ""
  property bool rescanPending: false

  // One line per entry: "pet\t<dir>\t<json>" or "skip\t<dir>\t<reason>".
  readonly property string manager: String(Qt.resolvedUrl("petdex.py")).replace(/^file:\/\//, "")
  readonly property int scanTimeoutMs: 10000

  function rescan() {
    if (!active || !petsDir) return
    if (scan.running) {
      rescanPending = true
      return
    }
    scanDir = petsDir
    scan.command = ["python3", "-B", manager, "scan", scanDir]
    scan.running = true
    scanWatchdog.restart()
  }

  function apply(output) {
    var next = []
    var lines = output.split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i]) continue
      var parts = lines[i].split("\t")
      if (parts[0] === "skip") {
        console.warn("hermes-pets: skipped " + parts[1] + ": " + parts[2])
        continue
      }
      if (parts[0] !== "pet" || parts.length < 3) {
        console.warn("hermes-pets: unexpected scan line: " + lines[i])
        continue
      }
      var dir = parts[1]
      var meta = null
      try {
        meta = JSON.parse(parts[2])
      } catch (err) {
        console.warn("hermes-pets: invalid scan json for " + dir + ": " + err)
        continue
      }
      var name = dir.slice(dir.lastIndexOf("/") + 1)
      next.push({
        name: name,
        displayName: meta.displayName || meta.id || name,
        kind: meta.kind || "",
        sheetUrl: Util.fileUrl(dir + "/" + meta.spritesheetPath)
      })
    }
    if (JSON.stringify(next) === JSON.stringify(pets)) return
    pets = next
    var names = next.map(function(pet) { return pet.name }).join(", ")
    console.log("hermes-pets: " + next.length + " pet(s) in " + petsDir + (names ? ": " + names : ""))
  }

  property Timer scanWatchdog: Timer {
    interval: root.scanTimeoutMs
    repeat: false
    onTriggered: {
      if (scan.running) {
        console.warn("hermes-pets: scan of " + root.scanDir + " timed out after " + (root.scanTimeoutMs / 1000) + " s")
        scan.running = false
      }
    }
  }

  property Process scan: Process {
    stdout: StdioCollector { id: scanOut; waitForEnd: true }
    stderr: StdioCollector { id: scanErr; waitForEnd: true }
    onExited: function(code, status) {
      scanWatchdog.stop()
      if (scanErr.text) console.warn("hermes-pets: scan stderr: " + scanErr.text.trim())
      if (code !== 0) console.warn("hermes-pets: scan of " + root.scanDir + " exited with " + code)
      else if (root.scanDir === root.petsDir) root.apply(scanOut.text)
      if (root.rescanPending) {
        root.rescanPending = false
        root.rescan()
      }
    }
  }

  onActiveChanged: rescan()
  onPetsDirChanged: rescan()
}
