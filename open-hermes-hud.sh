#!/usr/bin/env bash
# Coloca y ABRE/CIERRA (toggle real) el HUD de Hermes Desktop junto a la mascota.
# Uso: bash open-hermes-hud.sh petGX petGY petW petH screenW screenH [mode]
#   mode=open (default): toggle real on/off:
#       click 1 → abre el HUD junto al pet; la ventana principal de Hermes se
#                 oculta al scratchpad para que SOLO el HUD quede visible.
#       click 2 → cierra el HUD y la ventana principal (nada de Hermes visible).
#       click 3 → vuelve a abrir todo.   [alterna con cada click]
#   mode=move (tras arrastrar el pet): solo reposiciona el HUD si YA estaba
#       abierto; no abre si estaba cerrado y no toca la ventana principal.
set -u

PET_GX="${1:-960}"; PET_GY="${2:-540}"; PET_W="${3:-192}"; PET_H="${4:-208}"
SCR_W="${5:-1920}"; SCR_H="${6:-1080}"; MODE="${7:-open}"
HUD_W=620; HUD_H=320
HUD_STATE="${HOME}/.config/Hermes/hud-state.json"

hud_addr() {
  hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class == "Hermes" and ((.title // "") | contains("HUD"))) | .address' | head -1
}
main_addr() {
  hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class == "Hermes" and .title == "Hermes") | .address' | head -1
}
focus_win() {
  [ -n "$1" ] && hyprctl dispatch "hl.dsp.focus({ window = \"address:$1\" })" >/dev/null 2>&1
}
close_win() {
  [ -n "$1" ] && hyprctl dispatch 'hl.dsp.window.close()' >/dev/null 2>&1
}
# Envía la ventana principal de Hermes al scratchpad: solo el HUD queda visible.
hide_main() {
  local m h
  m=$(main_addr)
  [ -z "$m" ] && return 0
  h=$(hud_addr)
  focus_win "$m"
  sleep 0.2
  hyprctl dispatch 'hl.dsp.window.move({ workspace = "special:n:scratchpad", follow = false })' >/dev/null 2>&1
  # Devuelve el foco al HUD cuando el move no lo conserva.
  [ -n "$h" ] && focus_win "$h"
}

# --- Toggle OFF (HUD ya abierto) -------------------------------------------
# Cierra el HUD y —si vienes de un click (no de arrastrar)— también la ventana
# principal que la app restaura al salir del HUD: nada queda visible.
h=$(hud_addr)
if [ -n "$h" ]; then
  focus_win "$h"; sleep 0.3
  close_win "$h"
  if [ "$MODE" = "move" ]; then
    # Solo reposicionar (tras arrastrar): deja que la app suelte el HUD y reabre.
    sleep 1.0
  else
    sleep 0.5
    m=$(main_addr)
    if [ -n "$m" ]; then
      focus_win "$m"; sleep 0.3
      close_win "$m"
    fi
    exit 0
  fi
else
  # No abrir en modo "move" si el HUD estaba cerrado (tras arrastrar el pet).
  [ "$MODE" = "move" ] && exit 0
fi

# --- Colocación objetivo: al lado del pet (derecha; si no cabe, izquierda) --
tx=$((PET_GX + PET_W + 20))
ty=$((PET_GY + (PET_H - HUD_H) / 2))
max_x=$((SCR_W - HUD_W)); max_y=$((SCR_H - HUD_H))
[ "$tx" -gt "$max_x" ] && tx=$((PET_GX - HUD_W - 20))
[ "$tx" -lt 0 ] && tx=0
[ "$ty" -lt 0 ] && ty=0
[ "$ty" -gt "$max_y" ] && ty=$max_y

mkdir -p "$(dirname "$HUD_STATE")"
printf '{ "x": %s, "y": %s, "width": %s, "height": %s }\n' "$tx" "$ty" "$HUD_W" "$HUD_H" > "$HUD_STATE"

# --- Arranca la app Desktop si no está corriendo.
hermes desktop --skip-build >/dev/null 2>&1 &

addr=""
for i in $(seq 1 60); do
  addr=$(main_addr)
  [ -n "$addr" ] && break
  sleep 0.5
done
[ -z "$addr" ] && exit 1

focus_win "$addr"
sleep 1

for attempt in 1 2 3 4 5; do
  focus_win "$addr"
  sleep 4
  [ -n "$(hud_addr)" ] && { hide_main; exit 0; }
  wtype -M ctrl -M shift -k h -m shift -m ctrl >/dev/null 2>&1
  for i in $(seq 1 8); do
    [ -n "$(hud_addr)" ] && { hide_main; exit 0; }
    sleep 0.5
  done
done

exit 0