# Publish your plugin — Omarchy / Marketplace

> Fuente: https://plugins.omarchy.org/publish.html
> Descargado: 2026-09-20. Guardado como referencia para publicar los plugins en la comunidad.

Updated 20 Aug 2026 — 3 min read — Stable

List your plugin in three steps. Keep the code in a public GitHub repository and add a valid `manifest.json`.

Still building? Start with the [custom plugin development guide →](https://plugins.omarchy.org/develop.html).

**The marketplace validates listings, not plugin security.**

Plugins run unsandboxed. You remain responsible for your code, assets, documentation, and license.

---

## 01 — Prepare the repository

Prepare these files before you submit:

- ✓ **Public GitHub repository**
- ✓ **Valid `manifest.json` in the repository root**
- ✓ **README and license**
- ✓ **Safe install and removal**
- + **Optional preview, optimized automatically**

---

## 02 — Add a manifest

Create and validate the manifest before you submit.

Run `omarchy plugin clone`, then `omarchy plugin validate`. See the [official Omarchy Quattro plugin reference ↗](https://github.com/omacom/omarchy/blob/quattro/shell/plugins/README.md).

```json
{
  "schemaVersion": 1,
  "id": "yourname.plugin",
  "name": "Plugin name",
  "version": "1.0.0",
  "author": "Your name",
  "description": "What the plugin does.",
  "kinds": ["overlay"],
  "entryPoints": {
    "overlay": "Plugin.qml"
  }
}
```

### Manifest field reference

| Field | Purpose | Required |
|---|---|---|
| `schemaVersion` | Omarchy manifest contract version | **Yes** |
| `id` | Unique namespaced plugin identifier | **Yes** |
| `name` | Human-readable name | **Yes** |
| `version` | Current version, up to 64 characters for marketplace display | **Yes** |
| `author` | Plugin author shown in the marketplace | **Yes** |
| `description` | Short marketplace summary | **Yes** |
| `kinds` | Plugin capabilities exposed to Omarchy | **Yes** |
| `entryPoints` | QML entry file for each plugin kind | **Yes** |

---

## 03 — Submit your plugin

Open the issue form with your repository link, category, and tags. Automated validation checks the current commit before a maintainer approves the listing.

[Submit your plugin ↗](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml)

---

*Metadata: Status Stable · Runtime Quattro · Owner HANCORE (HANCORE-linux) · Visibility Public · Updated 20 Aug 2026*