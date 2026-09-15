#!/usr/bin/env bash
# Abre el HUB (HUD mode) de Hermes Desktop: ventana flotante con el chat real.
# Uso desde el plugin: bash open-hermes-hud.sh
set -u

hud_open() {
  hyprctl clients -j 2>/dev/null | jq -e 'any(.[]; .class == "Hermes" and ((.title // "") | contains("HUD")))' >/dev/null 2>&1
}

# Ya está abierto el HUB: no tocar nada (evita un toggle que lo cierre).
if hud_open; then exit 0; fi

# Arranca (o trae al frente) la app Desktop. Si ya corre, el single-instance
# enfoca su ventana principal y el CLI sale rápido.
hermes desktop --skip-build >/dev/null 2>&1 &

# Espera a que la ventana principal de Hermes tenga el foco y que el renderer
# esté listo (los keybinds se registran al montar la UI). Sondeamos + reintentamos
# el atajo varias veces: el primer arranque puede tardar bastante en conectar el backend.
for attempt in 1 2 3 4 5; do
  # Espera a que Hermes tome el foco (hasta ~15s por intento).
  got=no
  c=""
  for i in $(seq 1 30); do
    c=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class? // empty' 2>/dev/null)
    if [ "$c" = "Hermes" ]; then got=yes; break; fi
    sleep 0.5
  done

  if [ "$got" = "yes" ] && ! hud_open; then
    # Renderer listo + pequeño margen antes de pulsar Ctrl+Shift+H.
    sleep 4
    if ! hud_open; then
      wtype -M ctrl -M shift -k h -m shift -m ctrl
      for i in $(seq 1 8); do
        if hud_open; then exit 0; fi
        sleep 0.5
      done
    fi
  fi

  # Último intento: salimos limpio, el siguiente click volverá a intentar.
  [ "$attempt" -eq 5 ] && break
  sleep 3
done

exit 0