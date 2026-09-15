#!/usr/bin/env bash
# Coloca y abre/repone el HUB (HUD mode) de Hermes Desktop AL COSTADO del pet.
# Uso: bash open-hermes-hud.sh petGX petGY petW petH screenW screenH [mode]
#   mode=open  → abre el Hub junto al pet (o lo reposiciona si ya está abierto). [por defecto]
#   mode=move  → solo reposiciona si el Hub ya está abierto; no abre si estaba cerrado.
set -u

PET_GX="${1:-960}"; PET_GY="${2:-540}"; PET_W="${3:-192}"; PET_H="${4:-208}"
SCR_W="${5:-1920}"; SCR_H="${6:-1080}"; MODE="${7:-open}"
HUD_W=620; HUD_H=320
HUD_STATE="${HOME}/.config/Hermes/hud-state.json"

# --- Posición objetivo: a la derecha del pet (centrado vertical); si no cabe, a la izquierda.
tx=$((PET_GX + PET_W + 20))
ty=$((PET_GY + (PET_H - HUD_H) / 2))
max_x=$((SCR_W - HUD_W))
max_y=$((SCR_H - HUD_H))
if [ "$tx" -gt "$max_x" ]; then
  tx=$((PET_GX - HUD_W - 20))
fi
if [ "$tx" -lt 0 ]; then tx=0; fi
if [ "$ty" -lt 0 ]; then ty=0; fi
if [ "$ty" -gt "$max_y" ]; then ty=$max_y; fi

hud_addr() {
  hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class == "Hermes" and ((.title // "") | contains("HUD"))) | .address' | head -1
}
main_addr() {
  hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class == "Hermes" and .title == "Hermes") | .address' | head -1
}
focus_win() {
  local a="$1"
  [ -z "$a" ] && return 1
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$a\" })" >/dev/null 2>&1
}

# Un HUD ya abierto → se cierra: la app restaura su ventana principal y
# re-leerá hud-state.json en la próxima apertura (así aterriza junto al pet).
h=$(hud_addr)
if [ -n "$h" ]; then
  focus_win "$h"
  sleep 0.3
  hyprctl dispatch 'hl.dsp.window.close()' >/dev/null 2>&1
  sleep 1.5
else
  # Modo "move" (tras arrastrar el pet): no abrir si el Hub estaba cerrado.
  [ "$MODE" = "move" ] && exit 0
fi

# Posición en disco antes de abrir: la app la valida y la usa (hudBounds).
mkdir -p "$(dirname "$HUD_STATE")"
printf '{\n  "x": %s,\n  "y": %s,\n  "width": %s,\n  "height": %s\n}\n' "$tx" "$ty" "$HUD_W" "$HUD_H" > "$HUD_STATE"

# Arranca (o trae al frente) la app Desktop si no está corriendo.
hermes desktop --skip-build >/dev/null 2>&1 &

# Espera a que exista la ventana principal.
addr=""
for i in $(seq 1 60); do
  addr=$(main_addr)
  [ -n "$addr" ] && break
  sleep 0.5
done

if [ -z "$addr" ]; then
  exit 1
fi

# Foco explícito sobre la principal (determinista) + margen para el renderer.
focus_win "$addr"

for attempt in 1 2 3 4 5; do
  focus_win "$addr"
  sleep 4
  if [ -n "$(hud_addr)" ]; then exit 0; fi
  wtype -M ctrl -M shift -k h -m shift -m ctrl
  for i in $(seq 1 8); do
    if [ -n "$(hud_addr)" ]; then exit 0; fi
    sleep 0.5
  done
done

exit 0