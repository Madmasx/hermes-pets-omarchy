# Develop a Custom Plugin — Omarchy / Marketplace

> Fuente: https://plugins.omarchy.org/develop.html
> Descargado: 2026-09-20. Guardado como referencia para publicar los plugins en la comunidad.

Updated 13 Aug 2026 — 12 min read — Stable

Build in your user-owned plugin directory, edit a working Omarchy example, and validate the finished folder with the same manifest rules enforced by the Quattro shell.

**Plugins share the long-running Omarchy shell process.**

They run unsandboxed with your user permissions. Review every dependency and command, avoid unnecessary privileges, and never start a second Quickshell process for a plugin.

---

## 01 — Clone a Built-in Plugin

This tutorial builds a `bar-widget` with a details panel, so the built-in clock is the closest working starting point.

1. **Match the runtime contract** — Choose a built-in with the same plugin kind and interaction pattern as the plugin you want to build.
2. **Work in a user-owned copy** — Edit the clone under your config directory, never the packaged Omarchy source.
3. **Expect an immediate switch** — The clone command discovers and enables the copy, then replaces the built-in clock in your active bar.

```sh
omarchy plugin clone omarchy.clock --edit
```

On success, the command prints the new plugin ID, creates its folder, and opens that folder in your configured editor:

```
~/.config/omarchy/plugins/yourname.clock/
├── manifest.json
├── BarWidget.qml
├── Panel.qml
└── Model.js
```

**Keep the clone ID while developing.**

Use the exact ID printed by the command, such as `yourname.clock`, in every development example below. Saved changes reload automatically. Force discovery only when needed:

```sh
omarchy-shell shell rescanPlugins
```

Choose the permanent namespaced ID before publishing.

Browse the [built-in plugin examples ↗](https://github.com/omacom/omarchy/tree/quattro/shell/plugins) before designing a new component from scratch.

---

## 02 — Define the Plugin Contract

The clone keeps the clock's `bar-widget` contract. Use this reference when another plugin needs a different shell entry point.

### Plugin kind reference

| Plugin kind | `entryPoints` key | File loaded | Use it for |
|---|---|---|---|
| `bar-widget` | `barWidget` | `BarWidget.qml` | Item in the active bar |
| `panel` | `panel` | `Panel.qml` | Floating surface |
| `overlay` | `overlay` | `Overlay.qml` | Fullscreen surface |
| `menu` | `menu` | `Menu.qml` | Summoned menu |
| `service` | `service` | `Service.qml` | Headless singleton |
| `bar` | `bar` | `Bar.qml` | Full bar replacement |

For this tutorial, keep `bar-widget`, open `manifest.json`, and replace its contents with this complete development manifest:

```json
{
  "schemaVersion": 1,
  "id": "yourname.clock",
  "name": "Custom Clock",
  "version": "1.0.0",
  "author": "Your name",
  "license": "MIT",
  "description": "A small clock with a details panel for the Omarchy bar.",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "BarWidget.qml" },
  "barWidget": {
    "displayName": "Custom Clock",
    "category": "Time",
    "allowMultiple": false,
    "defaultSection": "center"
  },
  "omarchy": { "clonedFrom": "omarchy.clock" }
}
```

**The details panel is part of this bar widget.**

Keep `kinds: ["bar-widget"]` and `entryPoints.barWidget: "BarWidget.qml"`. The entry point loads `Panel.qml` internally, so this example does not declare a separate `panel` kind. Keep the clone-generated `omarchy.clonedFrom` value while developing so disabling or removing the clone restores the built-in clock.

---

## 03 — Implement the Bar and Panel

`BarWidget.qml` is the manifest entry point. It displays the clock, loads `Panel.qml`, and forwards the panel lifecycle that Quattro uses for clicks and shell commands.

```qml
import QtQuick
import Quickshell
import qs.Ui

BarWidget {
  id: root
  moduleName: "yourname.clock"

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Qt.formatTime(clock.date, "HH:mm")
    tooltipText: "Open Custom Clock"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}
```

Now replace `Panel.qml`. Quattro's `Panel` base provides the open state and controller; `KeyboardPanel` anchors the surface to the bar button, and Escape closes it through `PanelKeyCatcher`.

```qml
import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "yourname.clock"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(240))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: parent.width
          text: Qt.formatDateTime(clock.date, "dddd, d MMMM yyyy")
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          text: Qt.formatTime(clock.date, "HH:mm")
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.displayLarge
        }
      }
    }
  }
}
```

**Both files belong to one `bar-widget` plugin.**

The manifest loads `BarWidget.qml`; its `Loader` loads `Panel.qml`. Keep the same `moduleName` in both files, and do not add a second manifest kind for this nested panel.

This structure follows Omarchy's built-in clock plugin and the Marketplace's [Agent Usage plugin](plugin.html?id=robzolkos.agent-usage). The [official Omarchy shell reference ↗](https://github.com/omacom/omarchy/blob/quattro/shell/README.md) remains the source of truth for the runtime contract.

---

## 04 — Validate the Folder

Check both parts of the plugin without running it. Omarchy validates the manifest and repository layout; `qmllint` checks the bar and panel against the installed shell imports.

```sh
PLUGIN_ID="yourname.clock"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
omarchy plugin validate "$PLUGIN_DIR"
qmllint -I "$OMARCHY_PATH/shell" \
  "$PLUGIN_DIR/BarWidget.qml" "$PLUGIN_DIR/Panel.qml"
```

Both commands should exit without an error. A broken manifest mapping gives an actionable message, for example:

```
entry point file not found: 'BarWidget.qml'
```

- ✓ **Manifest parses as JSON** — `schemaVersion`, `id`, `name`, `version`, `kinds`, and `entryPoints` must be present and valid.
- ✓ **Kind and entry point agree** — A `bar-widget` needs `entryPoints.barWidget`; a standalone `panel` kind needs `entryPoints.panel`.
- ✓ **Every referenced file exists** — Manifest entry points must be safe relative paths, and every QML file passed to `qmllint` must exist.
- ✓ **No forbidden ID or symlink** — Third-party IDs cannot use `omarchy.*`, and plugin folders cannot contain symlinks.

---

## 05 — Run & Inspect the Plugin

The clone command already discovers, enables, and places the new bar widget. After validation succeeds, confirm that Quattro still lists it as enabled:

```sh
PLUGIN_ID="yourname.clock"
omarchy plugin list --json \
  | jq --arg id "$PLUGIN_ID" '.[] | select(.id == $id)'
```

For the `bar-widget` example, the result should include your ID, kind, and enabled state:

```json
{
  "id": "yourname.clock",
  "kinds": ["bar-widget"],
  "enabled": true
}
```

Test the panel through the same `bar-widget` ID. Quattro routes these commands to the `open()` and `close()` methods exposed by `BarWidget.qml`:

```sh
PLUGIN_ID="yourname.clock"
omarchy-shell shell summon "$PLUGIN_ID" '{}'
```

The command should open the clock details panel. Close it with Escape, then confirm the shell close route separately:

```sh
PLUGIN_ID="yourname.clock"
omarchy-shell shell hide "$PLUGIN_ID"
```

Before sharing, test click, Escape, shell open and close, disable, re-enable, shell restart, and removal. If a component does not load, continue to Troubleshooting below.

---

## 06 — Finished Example

After testing the plugin, replace the temporary clone ID with a permanent namespaced ID and remove the clone-only `omarchy.clonedFrom` field. Move these files into a public repository, then select a file to inspect or copy it.

### `custom-clock/manifest.json`

```json
{
  "schemaVersion": 1,
  "id": "io.github.yourname.custom-clock",
  "name": "Custom Clock",
  "version": "1.0.0",
  "author": "Your name",
  "license": "MIT",
  "description": "A small clock with a details panel for the Omarchy bar.",
  "kinds": [
    "bar-widget"
  ],
  "entryPoints": {
    "barWidget": "BarWidget.qml"
  },
  "barWidget": {
    "displayName": "Custom Clock",
    "category": "Time",
    "allowMultiple": false,
    "defaultSection": "center"
  }
}
```

### `custom-clock/README.md`

```markdown
# Custom Clock

A small clock with a details panel for the Omarchy Quattro bar.

## Install

```sh
omarchy plugin add https://github.com/yourname/custom-clock.git --enable
```

## Usage

Click the clock to open or close the details panel. Press Escape to close it.

## Configure

```sh
omarchy bar move io.github.yourname.custom-clock --section center
```

## Remove

```sh
omarchy plugin remove io.github.yourname.custom-clock
```
```

### `custom-clock/LICENSE`

```
MIT License

Copyright (c) David Heinemeier Hansson
Copyright (c) 2026 Your name

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

An optional `preview.png` can sit beside these files; it is binary, so it is not included in the copy-ready tree.

**Use this as a structural reference.**

Do not copy the ID, repository URL, author, or description unchanged. Document every external dependency, setup step, privilege boundary, service, installer, or remote build used by your plugin.

---

## Troubleshooting

- **Plugin Folder Not Found** — Use the exact ID printed by `omarchy plugin clone` and confirm the folder under `~/.config/omarchy/plugins/`.
- **Entry Point File Not Found** — Make the value in `entryPoints` match the filename and capitalization on disk.
- **The Plugin Validates but Is Not Listed** — Run `omarchy-shell shell rescanPlugins`, then inspect `omarchy plugin list --json`.
- **The Plugin Is Listed but Does Not Appear** — Enable it, confirm the declared kind, and inspect `qs log -p "$OMARCHY_PATH/shell" --tail 100` for QML errors.
- **A Panel Opens Once but Not Again** — Forward `opened`, `open()`, and `close()` from the bar entry point to the loaded panel.

---

*Metadata: Status Stable · Runtime Quattro · Owner HANCORE · Updated 13 Aug 2026*