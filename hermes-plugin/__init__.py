"""pet-activity — mirror the Hermes pet's live animation state to disk.

The Hermes pet state (``agent.pet.state.derive_pet_state``) is computed in-process
from transient signals (turn busy, model reasoning, tool running, awaiting the
user, errors, completion beats) and never persisted. This plugin subscribes to
the lifecycle hooks that carry those signals and writes the resulting canonical
pose to ``$HERMES_HOME/pets/activity-state.json`` so an out-of-process client
(the Omarchy desktop pet) can react to it in near real time.

Output format::

    {"pose": "run", "state": "run", "surface": "cli",
     "session_id": "...", "updated_at": 1756000000.0}

Pose vocabulary matches ``agent.pet.constants.PetState``:
``idle`` / ``run`` / ``review`` / ``wave`` / ``jump`` / ``failed`` / ``waiting``.
"""

from __future__ import annotations

import json
import logging
import os
import threading
import time
from pathlib import Path
from typing import Any, Optional

logger = logging.getLogger(__name__)

_STATE_FILENAME = "activity-state.json"
_SESSION_TTL_S = 1800.0
_BEAT_TTL_S = 1.8
_SUSTAINED = ("run", "review", "waiting")

_lock = threading.Lock()
_sessions: dict = {}
_beat: Optional[str] = None
_beat_until: float = 0.0
_beat_timer: Optional[threading.Timer] = None
_last_surface = ""


def _state_path() -> Path:
    home = os.environ.get("HERMES_HOME") or str(Path.home() / ".hermes")
    return Path(home) / "pets" / _STATE_FILENAME


def _session(sid: str) -> dict:
    entry = _sessions.get(sid)
    if entry is None:
        entry = {"busy": False, "reasoning": 0, "tools": 0, "awaiting": False, "ts": time.time()}
        _sessions[sid] = entry
    entry["ts"] = time.time()
    return entry


def _prune(now: float) -> None:
    for sid in [s for s, e in _sessions.items() if now - e.get("ts", 0.0) > _SESSION_TTL_S]:
        _sessions.pop(sid, None)


def _resolve_pose() -> str:
    now = time.time()
    _prune(now)
    if _beat and now < _beat_until:
        return _beat

    busy = any(e["busy"] for e in _sessions.values())
    reasoning = any(e["reasoning"] > 0 for e in _sessions.values())
    tool_running = any(e["tools"] > 0 for e in _sessions.values())
    awaiting = any(e["awaiting"] for e in _sessions.values())

    try:
        from agent.pet.state import derive_pet_state

        return derive_pet_state(
            busy=busy,
            reasoning=reasoning,
            tool_running=tool_running,
            awaiting_input=awaiting,
        ).value
    except Exception:
        if awaiting:
            return "waiting"
        if tool_running or busy:
            return "run"
        if reasoning:
            return "review"
        return "idle"


def _write(pose: str, sid: str) -> None:
    payload = {
        "pose": pose,
        "state": pose,
        "surface": _last_surface,
        "session_id": sid,
        "updated_at": time.time(),
    }
    path = _state_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(path.name + f".tmp.{os.getpid()}")
        tmp.write_text(json.dumps(payload), encoding="utf-8")
        os.replace(tmp, path)
    except Exception as exc:  # never let a write failure touch the agent loop
        logger.debug("pet-activity write failed: %s", exc)


def _publish(sid: str) -> None:
    with _lock:
        _write(_resolve_pose(), sid)


def _flash(beat: str, sid: str, secs: float = _BEAT_TTL_S) -> None:
    """Show a transient reaction (wave/jump/failed), then fall back to the sustained state."""
    global _beat, _beat_until, _beat_timer
    with _lock:
        _beat = beat
        _beat_until = time.time() + secs
        if _beat_timer is not None:
            _beat_timer.cancel()
        _beat_timer = threading.Timer(secs, _clear_beat, args=(sid,))
        _beat_timer.daemon = True
        _beat_timer.start()
        _write(beat, sid)


def _clear_beat(sid: str) -> None:
    global _beat
    with _lock:
        _beat = None
        _write(_resolve_pose(), sid)


def _flag(sid: str, **changes: Any) -> None:
    with _lock:
        entry = _session(sid or "default")
        entry.update(changes)
    _publish(sid or "default")


def _bump(sid: str, key: str, delta: int) -> None:
    with _lock:
        entry = _session(sid or "default")
        entry[key] = max(0, int(entry.get(key, 0)) + delta)
    _publish(sid or "default")


def _drop(sid: str) -> None:
    with _lock:
        _sessions.pop(sid or "default", None)
    _publish(sid or "default")


# --- hook callbacks ---------------------------------------------------------

def _on_pre_llm_call(session_id: str = "", platform: str = "", model: str = "", **_: Any) -> None:
    global _last_surface
    _last_surface = platform or "cli"
    _flag(session_id, busy=True)


def _on_post_llm_call(session_id: str = "", platform: str = "", **_: Any) -> None:
    global _last_surface
    _last_surface = platform or _last_surface
    with _lock:
        _session(session_id or "default")["busy"] = False
    _flash("wave", session_id)


def _on_pre_api_request(session_id: str = "", platform: str = "", **_: Any) -> None:
    global _last_surface
    _last_surface = platform or _last_surface
    _bump(session_id, "reasoning", 1)


def _on_post_api_request(session_id: str = "", **_: Any) -> None:
    _bump(session_id, "reasoning", -1)


def _on_api_request_error(session_id: str = "", platform: str = "", **_: Any) -> None:
    global _last_surface
    _last_surface = platform or _last_surface
    _bump(session_id, "reasoning", -1)
    _flash("failed", session_id, secs=2.2)


def _on_pre_tool_call(session_id: str = "", **_: Any) -> None:
    _bump(session_id, "tools", 1)


def _on_post_tool_call(session_id: str = "", **_: Any) -> None:
    _bump(session_id, "tools", -1)


def _on_pre_approval_request(session_id: str = "", session_key: str = "", **_: Any) -> None:
    _flag(session_id or session_key, awaiting=True)


def _on_post_approval_response(choice: str = "", session_id: str = "", session_key: str = "", **_: Any) -> None:
    sid = session_id or session_key
    with _lock:
        _session(sid or "default")["awaiting"] = False
    if choice == "deny":
        _flash("failed", sid)
    else:
        _publish(sid or "default")


def _on_pre_verify(session_id: str = "", platform: str = "", **_: Any) -> None:
    global _last_surface
    _last_surface = platform or _last_surface
    _flash("jump", session_id)


def _on_subagent_stop(parent_session_id: str = "", child_status: str = "", **_: Any) -> None:
    if child_status == "completed":
        _flash("jump", parent_session_id)


def _on_agent_loop_stopped(session_key: str = "", **_: Any) -> None:
    _drop(session_key or "default")


def _on_session_start(session_id: str = "", **_: Any) -> None:
    _flag(session_id, busy=False, reasoning=0, tools=0, awaiting=False)


def _on_session_end(session_id: str = "", completed: bool = False, failed: bool = False, **_: Any) -> None:
    with _lock:
        _sessions.pop(session_id or "default", None)
    if failed:
        _flash("failed", session_id, secs=2.2)
    elif completed:
        _flash("jump", session_id)
    else:
        _publish(session_id or "default")


def _on_session_finalize(session_id: str = "", **_: Any) -> None:
    # End of session: drop any pending transient beat synchronously so the file
    # settles on the sustained pose even if the process exits right away.
    global _beat, _beat_until
    with _lock:
        _sessions.pop(session_id or "default", None)
        if _beat_timer is not None:
            _beat_timer.cancel()
        _beat = None
        _beat_until = 0.0
        _write(_resolve_pose(), session_id or "default")


def register(ctx) -> None:
    ctx.register_hook("pre_llm_call", _on_pre_llm_call)
    ctx.register_hook("post_llm_call", _on_post_llm_call)
    ctx.register_hook("pre_api_request", _on_pre_api_request)
    ctx.register_hook("post_api_request", _on_post_api_request)
    ctx.register_hook("api_request_error", _on_api_request_error)
    ctx.register_hook("pre_tool_call", _on_pre_tool_call)
    ctx.register_hook("post_tool_call", _on_post_tool_call)
    ctx.register_hook("pre_approval_request", _on_pre_approval_request)
    ctx.register_hook("post_approval_response", _on_post_approval_response)
    ctx.register_hook("pre_verify", _on_pre_verify)
    ctx.register_hook("subagent_stop", _on_subagent_stop)
    ctx.register_hook("agent_loop_stopped", _on_agent_loop_stopped)
    ctx.register_hook("on_session_start", _on_session_start)
    ctx.register_hook("on_session_end", _on_session_end)
    ctx.register_hook("on_session_finalize", _on_session_finalize)
    logger.debug("pet-activity registered")
