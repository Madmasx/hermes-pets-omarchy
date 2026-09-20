# Checklist de publicación (Madmasx)

> Datos del creador para el marketplace de Omarchy.

- Creador: **Madmasx**
- Cuenta GitHub: **https://github.com/madmasx**
- Repo del plugin: **https://github.com/madmasx/hermes-pets-omarchy**
- Autor en `manifest.json`: `Madmasx` (ya correcto)
- Licencia: `MIT`

## Pasos antes de subir

1. El repo en GitHub debe ser **público** y contener en la **raíz**:
   - `manifest.json` (id `madmasx.hermes-pets`, kinds `bar-widget`, entryPoints `BarWidget.qml`)
   - `README.md`
   - `LICENSE`
   - `preview.png` (opcional, se optimiza automáticamente)
2. Validar localmente:
   ```sh
   cd ~/.config/omarchy/plugins
   omarchy plugin validate madmasx.hermes-pets
   qmllint -I "$OMARCHY_PATH/shell" \
     madmasx.hermes-pets/BarWidget.qml madmasx.hermes-pets/Panel.qml madmasx.hermes-pets/PetSprite.qml
   ```
   - Sin symlinks en la carpeta del plugin.
   - ID de terceros NO puede empezar por `omarchy.*`.
3. Push a GitHub y crear el issue de submit con el template `submit-plugin.yml`:
   https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=submit-plugin.yml
   (link del repo, categoría y etiquetas).

Guías completas guardadas en:
- `docs/omarchy-development.md`
- `docs/omarchy-publishing.md`