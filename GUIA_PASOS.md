# Hermes Pets — Omarchy plugin (guía completa)

Plugin de Omarchy que flota una mascota del petdex de Hermes en el escritorio,
reacciona al cursor, saluda al clickear, se puede fijar (pinned), muestra un
HUD mode al clickear el personaje, y — cuando el hook de actividad está conectado —
reacciona a lo que hace el agente Hermes (idle / run / review / wave / jump / failed / waiting).

Repo fuente: /home/madmasx/Disco/Proyectos/hermes-pets-omarchy/
Plugin activo: ~/.config/omarchy/plugins/madmasx.hermes-pets/

---

## Lo que está hecho hoy

- Widget de barra: icono en la barra de Omarchy con icono personalizado (image.png)
  cuando no hay mascota, y sprite del petdex cuando hay una seleccionada.
- Panel desplegable: lista de mascotas de `~/.hermes/pets/`, selección, toggles.
- Scan de mascotas: `scan.py` lee `pet.json` + spritesheet, valida atlas 1536xN*208.
- Mascotas detectadas automáticamente: las que estén instaladas en Hermes.
- Hook de actividad: `activity-writer.py` pollea `gateway_state.json` y escribe
  `activity-state.json` con el pose canónico de Hermes ("idle" / "run").
- Panel.qml Timer lee `activity-state.json` cada 800ms y mueve al sprite.
- HUD mode: al clickear el pet, aparece un overlay flotante con el estado actual
  del agente Hermes (icono + nombre de mascota + estado). Se auto-esconde en 3s.
- Nombres de pose alineados: watcher → Sprite.js usan los mismos nombres canónicos
  de Hermes (idle, run, review, wave, jump, failed, waiting).

---

## Pasos para instalar / recuperar

### 1. Instalar una mascota en Hermes (si no tienes ninguna)

```sh
hermes pets list                 # ver disponibles
hermes pets install boba --select   # instala boba y la activa
hermes pets doctor               # verifica que esté ready
```

Esto deja la mascota en `~/.hermes/pets/<slug>/` con `pet.json` + `spritesheet.webp`.

### 2. Habilitar el plugin en Omarchy

El plugin vive en `~/.config/omarchy/plugins/madmasx.hermes-pets/`. Si está ahí,
Omarchy lo detecta automáticamente. Para asegurar que está habilitado:

```sh
omarchy plugin enable madmasx.hermes-pets
omarchy plugin list | grep hermes
```

Debería aparecer como `enabled`.

### 3. Reiniciar el shell si se tocó el manifest o se añadió el plugin

```sh
omarchy restart shell
```

Salvo `manifest.json`, los cambios a archivos QML se recargan solos (cada vez que
se guarda el archivo). Pero `omarchy restart shell` asegura un arranque limpio.

### 4. Verificar que el plugin cargó bien

```sh
journalctl --user -u omarchy-shell -n 30 --no-pager | grep -i hermes-pets
```

Deberías ver:

- `hermes-pets: X pet(s) in /home/madmasx/.hermes/pets: ...`
- `hermes-pets: loaded .../spritesheet.webp rows=N`
- `hermes-pets: animation started`

Si ves `PetRow is not a type` o `PetLibrary is not a type`, faltan esos archivos
en `~/.config/omarchy/plugins/madmasx.hermes-pets/`. Copialos de la fuente.

### 5. Encender el hook de actividad

El hook es un proceso separado que pollea `gateway_state.json` y escribe
`~/.hermes/pets/activity-state.json`. Para arrancarlo:

```sh
# matar viejo si existe
pkill -f activity-writer.py

# lanzar nuevo (se queda en bg)
cd ~/.config/omarchy/plugins/madmasx.hermes-pets
nohup python3 activity-writer.py > ~/.hermes/logs/hermes-pets-activity.log 2>&1 &
disown
```

Verificar que está corriendo:

```sh
pgrep -af activity-writer.py
cat ~/.hermes/logs/hermes-pets-activity.log
```

El log debería decir algo como:

```
hermes-pets-activity: polling /home/madmasx/.hermes/gateway_state.json -> /home/madmasx/.hermes/pets/activity-state.json
```

### 6. Verificar que el hook escribe el pose

```sh
cat ~/.hermes/pets/activity-state.json
```

Debería aparecer `{"pose": "idle"}` cuando Hermes está quieto y
`{"pose": "run"}` cuando Hermes está procesando un turno.

### 7. Encender el toggle en el panel

Abre el panel de Hermes Pets (click en el icono de barra), y enciende
"React to Hermes activity". El pet empezará a reaccionar.

---

## HUD mode

Al clickear el personaje (sin arrastrar), aparece un overlay flotante HUD con:
- Icono del estado del agente (emoji Unicode según estado)
- Nombre de la mascota
- Label del estado (idle / run / review / wave / jump / failed / waiting)

El HUD se auto-esconde después de 3 segundos.

El HUD mode está activado por defecto (toggle "Show HUD on click" en el panel).
Para desactivarlo, deselecciona el toggle o pon `hudModeEnabled: false` en
`~/.config/omarchy/shell.json` para el widget `madmasx.hermes-pets`.

---

## Icono personalizado (image.png)

Cuando NO hay mascota seleccionada (`petId: ""`), el widget de barra muestra
`image.png` del proyecto como icono fallback.

El icono está en:
- `/home/madmasx/Disco/proyectos/hermes-pets-omarchy/image.png` (repo fuente)
- `/home/madmasx/.config/omarchy/plugins/madmasx.hermes-pets/image.png` (plugin activo)

Para cambiarlo, reemplaza `image.png` en ambos lugares (o solo en el activo).
Cuando hay una mascota seleccionada, se muestra el sprite del petdex en lugar de
image.png.

---

## Estados del agente y poses del sprite

| Hermes activity | Pose escrita | Fila atlas Codex (9 filas) |
|---|---|---|
| Sin turno en vuelo (`active_agents == 0`) | `idle` | 0 |
| Turno en vuelo (`active_agents > 0`) | `run` | 7 (en spritesheet actual) |
| Error de herramienta | `failed` | 5 (pendiente de wirear) |
| Modelo pensando/leyendo | `review` | 8 (pendiente de wirear) |
| Turno terminado limpio | `wave` | 3 (pendiente de wirear) |
| Plan terminado (todos los todos completados) | `jump` | 4 (pendiente) |
| Bloqueado esperando a usuario | `waiting` | 6 (pendiente) |

El watcher solo distingue `idle` / `run` porque `gateway_state.json` solo expone
`active_agents` y `gateway_state`. Para los otros estados habría que suscribirse a
los eventos del gateway (tool.start/complete, message.delta/complete) vía WebSocket
o leer canal interno de Hermes.

El Panel.qml Sprite.js ya tiene ACTIVITY_POSES mapeado con los nombres canónicos
de Hermes (idle, run, review, wave, jump, failed, waiting). El watcher escribe
esos mismos nombres. No hay traducción intermedia.

---

## Qué toca el plugin

- Lee `~/.hermes/pets/` (o el overriding `petsDir`) cada vez que abre el panel.
  Nunca crea, renombra ni borra nada ahí.
- Escribe sus propios ajustes (las keys del manifest) en el layout de la barra,
  en `~/.config/omarchy/shell.json`, a través del plugin registry del shell.
- El watcher lee `gateway_state.json` (read-only) y escribe
  `~/.hermes/pets/activity-state.json` (suyo, se sobreescribe cada poll).
- No accede a la red, no instala nada, no corre como root.

---

## Qué falta para estar completo

1. Wirear más estados: suscribirse a eventos del gateway (WebSocket) o leer el
   canal interno de Hermes para traducir tool.start/complete, message.delta/complete,
   error, clarify/approval a failed/review/wave/jump/waiting.
2. Hacer que el watcher se lance automáticamente con Omarchy (servicio user systemd
   o integrarlo como plugin service de Omarchy) para que no haya que lanzarlo a mano.
3. LICENSE (MIT, igual que Omarchy Pets de referencia).
4. Publicarlo en un repo git para que otros lo instalen con `omarchy plugin add <url>`.

---

## Logs de diagnóstico

```sh
# Plugin QML
journalctl --user -u omarchy-shell -n 50 --no-pager | grep -i hermes-pets

# Watcher de actividad
tail -f ~/.hermes/logs/hermes-pets-activity.log

# Estado del pet en Hermes
hermes pets doctor
hermes pets list --installed

# Estado del gateway de Hermes
cat ~/.hermes/gateway_state.json | python3 -m json.tool
```

---

## Quitar

```sh
# matar watcher si corre
pkill -f activity-writer.py

# remover plugin
omarchy plugin remove madmasx.hermes-pets

# borrar ajustes residuales en shell.json si querés limpio
# (la línea del widget en ~/.config/omarchy/shell.json)
```

`~/.hermes/pets/` no se toca bajo ningún lado.

---

## Archivos del proyecto

```
/home/madmasx/Disco/proyectos/hermes-pets-omarchy/
├── manifest.json          # id: madmasx.hermes-pets, bar-widget
├── BarWidget.qml          # icono en barra con image.png como fallback
├── Panel.qml              # panel desplegable + HUD mode + Timer actividad
├── HudOverlay.qml         # overlay HUD flotante (nuevo)
├── PetLibrary.qml         # scanner de mascotas (portado de Omarchy Pets)
├── PetRow.qml             # fila de lista de mascotas (portado)
├── PetSprite.qml          # motor del sprite (idéntico al de Omarchy Pets)
├── Sprite.js              # .pragma library con POSES + ACTIVITY_POSES alineados
├── scan.py                # valida pet.json + atlas (portado)
├── activity-writer.py     # watcher que pollea gateway_state.json (alineado)
├── README.md              # documentación del plugin
├── GUIA_PASOS.md          # guía de pasos (esta que no se pierde)
└── image.png              # icono fallback para la barra cuando no hay mascota
```

---

## Notas de desarrollo

- Los nombres de pose están alineados: watcher escribe "idle"/"run" y Sprite.js
  espera "idle"/"run"/"review"/"wave"/"jump"/"failed"/"waiting". Los nombres
  canónicos de Hermes (PetState enum) se usan en ambos lados sin traducción.
- El HUD mode usa emoji Unicode para representar el estado del agente. Se puede
  personalizar editando HudOverlay.qml (propiedad `poseIcon`).
- El icono fallback (image.png) es una pata de animal en estilo line art minimalista.
  Se puede reemplazar por cualquier imagen PNG transparente.
- El watcher debe lanzarse a mano (ver paso 5). No se auto-inicia con Omarchy todavía.
