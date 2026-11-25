# Hermes Pets

![Hermes Pets](assets/preview.png)

Un acompañante animado tipo mascota para la barra de Omarchy, **100 % autocontenido dentro de la carpeta del plugin** (sin depender de `hermes`, `curl` ni binarios externos). Reproduce hojas de sprite de [petdex.dev](https://petdex.dev), mira el cursor, saluda al hacer clic, deambula por la pantalla y puede fijarse sobre el escritorio.

## Características

- **Autocontenido**: todo vive dentro de la carpeta del plugin (las mascotas se guardan en `pets/` por defecto y se gestionan con `petdex.py` usando solo la librería estándar de Python 3).
- **Catálogo integrado**: busca, instala y elimina mascotas directamente desde `https://petdex.dev/api/manifest` con caché local y validación estricta del atlas (1536×N·208, PNG/WebP).
- **Animaciones completas**: `idle`, `waving`, `jumping`, `waiting`, `running`, filas direccionales (`running-right`/`running-left`) y seguimiento del cursor (hojas v2).
- **Modo fijado (`pinned`)**: flota sobre el escritorio con una sola instancia aunque tengas múltiples monitores (`PinGate.js`), se puede arrastrar, recuerda posición y tiene física de gravedad opcional.
- **Roaming**: pausa 8-20 s y camina a un punto aleatorio del borde inferior.
- **Escalado rápido**: `Alt + rueda` sobre la mascota fijada (subir agranda, bajar achica) o botones `-`/`+` en el panel.
- **Espejo de actividad (opcional)**: observa `pets/activity-state.json` en tiempo real con `WatchedFile` (sin polling con `cat`).

## Requisitos

- Omarchy con su barra Quickshell (`omarchy-shell`) sobre Hyprland.
- Python 3 (solo biblioteca estándar).

## Instalar

```sh
git clone https://github.com/madmasx/hermes-pets-omarchy.git
omarchy plugin add ./hermes-pets-omarchy --enable
```

## Uso

- **Clic en el icono de la barra**: abre o cierra el panel (lista de mascotas instaladas, acciones rápidas y ajustes).
- **Botón `+`**: abre el catálogo integrado de petdex.dev para buscar e instalar mascotas directamente en `pets/`.
- **Botón pin**: fija o quita la mascota del escritorio.
- **Botón mano**: hace saludar a la mascota fijada.
- **Botón papelera**: elimina la mascota activa del disco.
- **Mascota fijada**: clic = saluda (y opcionalmente ejecuta `clickCommand` si `launchOnClick` está activo); arrastrar = mover; `Alt + rueda` = escalar.

## Configuración

Los ajustes se cambian desde el panel o por CLI:

```sh
omarchy bar set madmasx.hermes-pets smooth false --json
```

| Clave | Tipo | Default | Significado |
|---|---|---|---|
| `petId` | string | `""` | Carpeta de la mascota activa; vacío = primera instalada |
| `petsDir` | string | `""` | Vacío = `<plugin>/pets/`; acepta ruta personalizada (ej. `~/.hermes/pets`) |
| `smooth` | bool | `true` | Escalado bilineal; apagar para pixel art |
| `pinned` | bool | `false` | Dejar la mascota en el escritorio |
| `pinnedX`/`pinnedY` | int | `-1` | Posición en píxeles; `-1` = centrada. Arrastrar los actualiza |
| `movable` | bool | `true` | Permitir arrastrar la mascota fijada |
| `gravityEnabled` | bool | `true` | Si sueltas la mascota en el aire, cae al borde inferior |
| `randomBehavior` | bool | `true` | Roaming: pausa y camina por el borde inferior |
| `animate` | bool | `true` | Apagado: muestra un frame quieto y detiene el timer |
| `petScale` | number | `0.75` | Factor de escala (`0.25` a `3.0`) |
| `activityEnabled` | bool | `false` | Reacciona a `activity-state.json` dentro de `petsDir` |
| `launchOnClick` | bool | `false` | Ejecuta `clickCommand` al hacer clic en la mascota fijada |
| `clickCommand` | string | `""` | Comando opcional al hacer clic (ej. `hermes desktop --skip-build`) |

## Espejo de actividad (opcional)

Si quieres que la mascota reaccione a un agente externo (como Hermes), activa `activityEnabled` y escribe JSON en `<petsDir>/activity-state.json`:

```json
{"pose": "run", "updated_at": 1756000000.0}
```

Poses soportadas: `idle`, `run`, `review`, `waiting` (sostenidas) y `wave`, `jump`, `failed` (transitorias de un solo pase). El plugin opcional para Hermes vive en [`hermes-plugin/`](hermes-plugin/).

## Desarrollar

```sh
omarchy plugin validate .
omarchy agent look plugin .
```

## Licencia

MIT — ver `LICENSE`.
