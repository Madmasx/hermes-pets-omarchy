# Hermes Pets — Omarchy plugin

Un acompañante animado tipo mascota en la barra de Omarchy que reproduce
hojas de sprite del petdex de Hermes (`~/.hermes/pets/`), mira tu cursor,
saluda cuando le clickeas, y se puede fijar al escritorio (pinned). Es un
clone de [Omarchy Pets](https://plugins.omarchy.org/plugin.html?id=raiden-meixelysia.omarchy-pets)
adaptado para leer los pets de Hermes en lugar de los de Codex.

## Qué hace

- Lee mascotas del petdex de Hermes desde `~/.hermes/pets/<slug>/`.
- Reproduce las animaciones del atlas (idle, waving, jumping, waiting, running).
- El sprite mira el cursor (solo hojas v2 con filas de look).
- Click = wave; arrastrar el pet fijado = moverlo; click en barra = toggle.
- Pinned mode: el pet queda flotando sobre el escritorio con la panel cerrada.
- Activity hook (opcional): cuando está activado, el pet cambia de pose según
  el estado del agente Hermes (idle / thinking / running / error / done).
  Requiere que se teja el hook; ver abajo.

## Requisitos

- Omarchy 4 con su barra Quickshell (`omarchy-shell`) sobre Hyprland.
- Python 3 (ya lo trae toda instalación de Omarchy).
- Al menos una mascota instalada en Hermes:
  `hermes pets install <slug>` — los pets se instalan en
  `~/.hermes/pets/<slug>/`. La carpeta debe contener `pet.json` y el
  spritesheet (WebP o PNG, atlas 1536×N*208, 192×208 por frame).
  Ver el formato de petdex: https://petdex.dev

## Instalar

```sh
omarchy plugin add /home/madmasx/Disco/proyectos/hermes-pets-omarchy --enable
```

O desde el repo una vez publicado:

```sh
omarchy plugin add https://github.com/tu-usuario/hermes-pets-omarchy.git --enable
```

El botón de la barra mostrará el primer frame del pet activo; sin pets
muestra una pata.

## Usar

- Click en el icono de la barra: abre el panel (el pet animado, los tres
  primeros pets instalados, y los ajustes). Escape o click fuera cierra.
- Click en un pet de la lista para cambiarlo. La elección sobrevive a
  reinicios del shell.
- Hover sobre el pet y mira el cursor (solo hojas v2); click = wave.
- Botón pin (arriba a la derecha del pet): fija el pet al escritorio con el
  panel cerrado. No toma foco de teclado y solo el pet es clickeable. Arrastra
  el pet fijado para moverlo; la posición se recuerda.
- Click en el icono de barra cuando está pinned = unpinn.

## Ajustes

Todos viven en la entrada del widget dentro de `~/.config/omarchy/shell.json`
y se pueden setear desde CLI:

```sh
omarchy bar set madmasx.hermes-pets smooth false --json
```

| Clave | Tipo | Default | Significado |
|---|---|---|---|
| `petId` | string | `""` | Nombre del directorio del pet activo; vacío = el primero |
| `petsDir` | string | `~/.hermes/pets` | Dónde leer los pets de Hermes |
| `smooth` | bool | `true` | Escalado bilinear; apagar para pixel art |
| `pinned` | bool | `false` | Dejar el pet en el escritorio |
| `pinnedX` | int | `-1` | Borde izquierdo del pet pinned en píxeles de pantalla; `-1` = bajo su icono de barra. El arrastre lo setea |
| `pinnedY` | int | `-1` | Borde superior; misma regla |
| `randomBehavior` | bool | `true` | Roaming: pausa 8-20 s y camina por el borde inferior hacia una X aleatoria (filas `running-right`/`running-left`). Off = se queda quieto |
| `animate` | bool | `true` | Apagado muestra un frame quieto y no corre el timer |
| `activityEnabled` | bool | `false` | Cuando está on, el pet cambia de pose leyendo `~/.hermes/pets/activity-state.json` (ver abajo) |

## Roaming (randomBehavior)

Inspirado en `apps/desktop/src/components/pet/use-pet-roam.ts` de Hermes: el
pet deambula en vez de quedarse clavado. Un loop decide un destino aleatorio
en la pantalla, camina hacia él con la fila direccional correspondiente
(`running-right`/`running-left`, o `running` en espejo si el atlas no las
trae) y vuelve a pausar 8-20 s. La velocidad se deriva de la duración del loop
de la animación (una longitud de cuerpo por loop) para que los pasos se lean
como pasos y no como un deslizamiento. Al terminar cada tramo se persiste la X
en `pinnedX`.

Se detiene mientras arrastrás el pet, mientras cae por gravedad, y mientras el
agente Hermes está activo (`run`/`review`/`waiting`), como en Hermes, que solo
deambula con el agente en reposo.

## Espejo de actividad de Hermes (activityEnabled)

Cuando `activityEnabled` es `true`, el pet refleja en vivo lo que hace el
agente Hermes. El estado del pet de Hermes (`agent.pet.state.derive_pet_state`)
se calcula en proceso y **no se persiste**, así que lo escribe a disco un
plugin de Hermes y lo lee este plugin de Omarchy.

### 1. Plugin de Hermes (productor)

El plugin de Hermes se suscribe a los hooks del ciclo de vida
(`pre/post_llm_call`, `pre/post_api_request`, `api_request_error`,
`pre/post_tool_call`, `pre/post_approval_response`, `pre_verify`,
`agent_loop_stopped`, `subagent_stop`, `on_session_start/end/finalize`),
deriva la pose canónica con `derive_pet_state` y escribe de forma atómica:

```json
{ "pose": "run", "state": "run", "surface": "cli",
  "session_id": "20260916_194912_3c1ef4", "updated_at": 1789609759.39 }
```

Su fuente versionada vive en [`hermes-plugin/`](hermes-plugin/) de este repo.
Instalarlo y habilitarlo (una sola vez):

```sh
mkdir -p ~/.hermes/plugins/pet-activity
cp hermes-plugin/__init__.py hermes-plugin/plugin.yaml ~/.hermes/plugins/pet-activity/
hermes plugins enable pet-activity
hermes plugins doctor pet-activity   # verifica los hooks registrados
```

### 2. Lector en Omarchy (consumidor)

Este runtime de Quickshell **no expone `Qt.readFile`**, y `FileView.text()`
devuelve contenido desfasado respecto de `onFileChanged`; por eso el panel lee
el archivo con un `Process` (`cat`) cada 700 ms mientras `activityEnabled` esté
on, y aplica `sprite.beginAction(pose)` cuando la pose cambia.

Vocabulario canónico (enum `PetState` de Hermes):
`idle`, `run`, `review`, `wave`, `jump`, `failed`, `waiting`.

- `run`, `review`, `waiting` se **sostienen** mientras Hermes siga en ese estado.
- `wave`, `jump`, `failed` son beats de un solo pase; el panel también ignora
  beats transitorios con `updated_at` de más de 3 s (p. ej. si un proceso
  `hermes -z` terminó antes del TTL y dejó el archivo en `jump`).

El panel mantiene compatibilidad con los nombres de sprite del atlas
(`idle`, `waving`, `jumping`, `waiting`, `running`) además de los canónicos.

## Qué toca

- Lee `~/.hermes/pets/` (o el overriding `petsDir`) cada vez que abre el
  panel. Nunca crea, renombra ni borra nada ahí.
- Escribe solo sus propios ajustes (las claves de arriba) en el layout de la
  barra, en `~/.config/omarchy/shell.json`, a través del plugin registry del
  shell, que es el mismo camino que `omarchy bar set`.
- No accede a la red, no instala nada, no corre como root.

## Desarrollar

```sh
# Validar estructura
omarchy plugin validate /home/madmasx/Disco/proyectos/hermes-pets-omarchy

# Lint QML (si qmllint está disponible)
/usr/lib/qt6/bin/qmllint -I "$(omarchy shell path)/shell" *.qml

# Reiniciar el shell para recargar
omarchy restart shell

# Ver logs
journalctl --user | grep hermes-pets
```

Guardar un archivo bajo `~/.config/omarchy/plugins/` recarga el plugin
automáticamente; no hace falta recargar manualmente salvo para `manifest.json`.

## Quitar

```sh
omarchy plugin remove madmasx.hermes-pets
```

Esto borra la carpeta del plugin (con backup). La línea de ajustes en
`~/.config/omarchy/shell.json` queda; borrarla a mano si querés limpio.
`~/.hermes/pets/` no se toca.

## Diferencias con Omarchy Pets

- Origen de los pets: `~/.hermes/pets/` en lugar de `~/.codex/pets/`.
- Nombre del namespace / layer: `hermes-pets` en lugar de `omarchy-pets`.
- Pose `thinking` / `error` / `done` añadidos para encajar con estados del
  agente Hermes (Redis mapeados a filas del atlas en `Sprite.js`).
- El hook de actividad está esbozado pero no conectado todavía (ver arriba).

## Créditos

Formato de sprite heredado de [Petdex](https://github.com/crafter-station/petdex)
(MIT) y [Codex Pets](https://codex-pets.net). Mascotas: assets de terceros,
no parte de este repo. Estructura y engine de animación tomados de
[Omarchy Pets](https://github.com/ZacharyZhang-NY/omarchy-pets) como guía.

## Licencia

MIT — ver LICENSE.
