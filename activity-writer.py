#!/usr/bin/env python3
"""Hermes Pets activity watcher — Omarchy plugin companion (v2).

Pollea el gateway de Hermes y escribe poses canónicas de Hermes en
~/.hermes/pets/activity-state.json. El plugin Omarchy (Panel.qml) lee ese
archivo cada 800ms y mueve al sprite con beginAction(pose).

Pose vocabulary (Hermes PetState enum, agent/pet/constants.py):

  IDLE, WAVE, RUN, FAILED, REVIEW, JUMP, WAITING

Estos nombres concordann directamente con lo que Sprite.js espera en su
ACTIVITY_POSES (idle, run, review, wave, jump, failed, waiting). No hay
traducción intermedia: lo que el watcher escribe es lo que el sprite reproduce.

Mapeo de señales Hermes → pose:

  gateway_state != "running"  -> idle
  active_agents == 0           -> idle
  active_agents > 0            -> run    (turn/tool en vuelo)

Los otros estados (review/wave/jump/failed/waiting) se agregan cuando el watcher
suscribe a eventos del gateway vía WebSocket (tool.start/complete, message.delta,
error signals). Por ahora el watcher solo maneja idle/run.

El archivo activity-state.json también puede ser sobreescrito por un listener
externo (ej. la app de Hermes o un script custom). Cuando el archivo contiene un
pose que no es idle/run, el watcher lo respeta y lo re-emite (para que un futuro
listener de WebSocket pueda inyectar review/wave/jump/failed/waiting sin pelear
con el poll).

Si el gateway no es alcanzable, el último pose se mantiene — no se hace snap a
idle en cada glitch.

Run como processo en background junto a Omarchy. Matar con SIGTERM/SIGINT.
No limpiamos activity-state.json al salir para que un crash no deje al pet atasco.
"""
from __future__ import annotations

import json
import os
import signal
import sys
import time
from pathlib import Path
from typing import Any

POLL_INTERVAL_S = 1.0
POSE_FILE = Path.home() / ".hermes" / "pets" / "activity-state.json"
RUNTIME_STATUS_FILE = Path.home() / ".hermes" / "gateway_state.json"

# Pose canónicos de Hermes — idénticos a Hermes PetState enum values y a los
# que Sprite.js ACTIVITY_POSES espera.
POSE_IDLE = "idle"
POSE_RUN = "run"


def read_runtime_status() -> dict[str, Any] | None:
    """Best-effort read de gateway_state.json."""
    if not RUNTIME_STATUS_FILE.exists():
        return None
    try:
        raw = RUNTIME_STATUS_FILE.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeDecodeError):
        return None
    if not raw:
        return None
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return None
    return payload if isinstance(payload, dict) else None


def derive_pose(status: dict[str, Any] | None) -> str:
    """Traduce el runtime status del gateway a un pose canónico de Hermes.

    Solo maneja idle/run porque gateway_state.json solo expone
    gateway_state + active_agents. Los demás estados llegan vía events.
    """
    if status is None:
        return POSE_IDLE

    gateway_state = status.get("gateway_state")
    if gateway_state != "running":
        return POSE_IDLE

    active_agents = status.get("active_agents", 0)
    try:
        active = int(active_agents) > 0
    except (TypeError, ValueError):
        active = False

    if active:
        return POSE_RUN
    return POSE_IDLE


def read_explicit_pose() -> str | None:
    """Si activity-state.json ya tiene un pose explícito, lo retorna.

    Permite que un futuro listener (WebSocket de herramientas) inyecte
    review/wave/jump/failed/waiting sin pelear con el poll.
    """
    if not POSE_FILE.exists():
        return None
    try:
        raw = POSE_FILE.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeDecodeError):
        return None
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return None
    if not isinstance(data, dict):
        return None
    pose = data.get("pose")
    if isinstance(pose, str) and pose:
        return pose
    return None


def write_pose(pose: str) -> None:
    """Escribe el pose actual atómicamente."""
    POSE_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = POSE_FILE.with_suffix(".tmp")
    try:
        tmp.write_text(json.dumps({"pose": pose}, ensure_ascii=False) + "\n")
        tmp.replace(POSE_FILE)
    except OSError as exc:
        print(f"hermes-pets-activity: cannot write {POSE_FILE}: {exc}", file=sys.stderr)


def main() -> None:
    running = True

    def stop(*_args: Any) -> None:
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    last_pose: str | None = None

    print(
        f"hermes-pets-activity: polling {RUNTIME_STATUS_FILE} -> {POSE_FILE}",
        file=sys.stderr,
    )

    while running:
        status = read_runtime_status()
        candidate = derive_pose(status)

        # Pose explícito del archivo gana sobre el poll — future WebSocket listener.
        override = read_explicit_pose()
        if override and override != POSE_RUN and override != POSE_IDLE:
            candidate = override

        if candidate != last_pose:
            write_pose(candidate)
            last_pose = candidate

        deadline = time.monotonic() + POLL_INTERVAL_S
        while running and time.monotonic() < deadline:
            time.sleep(0.1)

    print("hermes-pets-activity: stopped", file=sys.stderr)


if __name__ == "__main__":
    main()
