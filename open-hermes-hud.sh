#!/usr/bin/env bash
# Coloca y ABRE/CIERRA (toggle real) el HUD de Hermes Desktop junto a la mascota.
# Uso: bash open-hermes-hud.sh petGX petGY petW petH screenW screenH [mode]
#   mode=open (default): toggle real on/off:
#       click 1 → entra en HUD mode: la app abre SOLO el HUD (la principal la
#                 oculta ella misma y flota/pega el HUD como overlay).
#       click 2 → sale de HUD mode con el atajo de la app y cierra la principal:
#                 nada de Hermes queda visible y NO se tocan otras ventanas.
#   mode=move (tras arrastrar el pet): solo reposiciona el HUD si YA estaba
#       abierto; si estaba cerrado no abre y no toca la ventana principal.
set -u

# Guard anticlicks dobles: una sola operación a la vez. PIDfile autocurable —
# si el dueño desapareció o caducó (>60s) se descarta solo (los flock se volvían
# eternos porque el daemon de `hermes desktop` heredaba el fd y lo dejaba vivo).
LOCK="${TMPDIR:-/tmp}/hermes-hud.lock"
mkdir -p "$(dirname "$LOCK")"
if [ -f "$LOCK" ]; then
  lock_pid=$(cat "$LOCK" 2>/dev/null || "")
  lock_age=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
  if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null && [ "$lock_age" -lt 60 ]; then
    exit 0   # otra operación de toggle está en curso
  fi
  rm -f "$LOCK"
fi
echo $$ > "$LOCK"
trap 'rm -f "$LOCK"' EXIT

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
  [ -n "$1" ] && hyprctl dispatch "hl.dsp.window.close({ window = \"address:$1\" })" >/dev/null 2>&1
}
# El propio atajo de la app (view.toggleHud = mod+shift+h): entra/sale de HUD.
send_toggle() {
  wtype -M ctrl -M shift -k h -m shift -m ctrl >/dev/null 2>&1
}
# wait_hud want[1=presente|0=ausente]: sondea hasta 10s en pasos de 0.5s.
wait_hud() {
  local want="$1" attempts="${2:-20}" i
  for i in $(seq 1 "$attempts"); do
    if [ "$want" = "1" ] && [ -n "$(hud_addr)" ]; then return 0; fi
    if [ "$want" = "0" ] && [ -z "$(hud_addr)" ]; then return 0; fi
    sleep 0.5
  done
  return 1
}

# --- Toggle OFF (HUD ya abierto) -------------------------------------------
# Margen de mapeo: si el HUD está arriba (aunque esté recién mapeándose) es un
# toggle OFF. Sin este margen un segundo click que cae mientras se abre toma el
# camino OPEN, no encuentra la principal (la app la oculta) y no hace nada.
h=""
for i in 1 2 3 4 5; do
  h=$(hud_addr)
  [ -n "$h" ] && break
  sleep 0.4
done

if [ -n "$h" ]; then
  if [ "$MODE" = "move" ]; then
    # Solo reposicionar (tras arrastrar): cierra el HUD y reabre en el nuevo
    # costado; deja que la app suelte el HUD antes de reabrir.
    focus_win "$h"; sleep 0.3
    send_toggle
    wait_hud 0
    sleep 1.0
  else
    focus_win "$h"; sleep 0.3
    send_toggle
    wait_hud 0
    # La app restaura la principal justo al salir de HUD: espero que aparezca
    # y la cierro por dirección para que no quede nada visible.
    m=""
    for i in 1 2 3 4 5 6; do
      m=$(main_addr)
      [ -n "$m" ] && break
      sleep 0.5
    done
    [ -n "$m" ] && close_win "$m"
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
  [ -n "$(hud_addr)" ] && exit 0   # ya en HUD (la app tiene la principal oculta)
  sleep 0.5
done
[ -z "$addr" ] && exit 1

# --- Entra en HUD mode: enfocar la principal y enviar el atajo de la app.
# Un solo atajo por intento con ventana amplia (10s): si el HUD no aparece, el
# atajo se perdió (app aún arrancando) y se reintenta SOLO si sigue ausente —
# reenviar a ciegas apagaría un HUD que acaba de abrirse.
for attempt in 1 2 3; do
  focus_win "$addr"
  sleep 4
  [ -n "$(hud_addr)" ] && exit 0     # ya en HUD (la app oculta la principal)
  send_toggle
  if wait_hud 1 20; then exit 0; fi
done

exit 0