import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Enumerates <petsDir>/*/ and keeps the valid Hermes petdex pets.
QtObject {
  id: root

  property string petsDir: ""
  property bool active: false
  property var pets: []
  property string scanDir: ""
  property bool rescanPending: false

  // One line per entry: "pet\t<dir>\t<json>" or "skip\t<dir>\t<reason>".
  readonly property string scanner: String(Qt.resolvedUrl("scan.py")).replace(/^file:\/\//, "")
  readonly property int scanTimeoutSec: 10

  function rescan() {
    if (!active) return
    if (scan.running) {
      rescanPending = true
      return
    }
    scanDir = petsDir
    scan.command = ["timeout", "-k", "2", String(scanTimeoutSec), "python3", scanner, scanDir]
    scan.running = true
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
      if (parts[0] !== "pet") throw new Error("hermes-pets: unexpected scan line: " + lines[i])
      var dir = parts[1]
      var meta = JSON.parse(parts[2])
      var name = dir.slice(dir.lastIndexOf("/") + 1)
      next.push({
        name: name,
        displayName: meta.displayName || meta.id,
        kind: meta.kind || "",
        sheetUrl: Util.fileUrl(dir + "/" + meta.spritesheetPath),
        thumbUrl: Util.fileUrl(root.petsDir + "/.thumbs/" + name + ".png")
      })
    }
    if (JSON.stringify(next) === JSON.stringify(pets)) return
    pets = next
    var names = next.map(function(pet) { return pet.name }).join(", ")
    console.log("hermes-pets: " + next.length + " pet(s) in " + petsDir + (names ? ": " + names : ""))
  }

  property Process scan: Process {
    stdout: StdioCollector { id: scanOut; waitForEnd: true }
    stderr: StdioCollector { id: scanErr; waitForEnd: true }
    onExited: function(code, status) {
      if (scanErr.text) console.warn("hermes-pets: scan stderr: " + scanErr.text.trim())
      if (code === 124) console.warn("hermes-pets: scan of " + root.scanDir + " timed out after " + root.scanTimeoutSec + " s")
      else if (code !== 0) console.warn("hermes-pets: scan of " + root.scanDir + " exited with " + code)
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
