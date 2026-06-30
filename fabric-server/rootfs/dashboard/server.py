#!/usr/bin/env python3
"""Web dashboard for the Minecraft Server add-on.

- GET  /                  → dashboard HTML
- GET  /static/*          → static assets
- GET  /events/status     → SSE stream of server status (one-directional push)
- WS   /ws/terminal       → bidirectional server console (read log + write stdin)
"""
import asyncio
import json
import os
import re
import time
from pathlib import Path

from aiohttp import web, WSMsgType

LOG_FILE    = os.environ.get("MC_LOG_FILE",    "/tmp/mc.log")
STDIN_PIPE  = os.environ.get("MC_STDIN_PIPE",  "/tmp/mc_stdin")
STATUS_FILE = os.environ.get("MC_STATUS_FILE", "/tmp/mc_status.json")
STATIC_DIR  = Path(__file__).parent / "static"
PORT        = int(os.environ.get("INGRESS_PORT", "8099"))

# ---------------------------------------------------------------------------
# Runtime state mutated by the log-tailer background task
# ---------------------------------------------------------------------------
_player_set: set[str] = set()
_server_ready: bool = False

# Active WebSocket terminal clients
_ws_clients: set[web.WebSocketResponse] = set()

# Active SSE status subscribers — each entry is an asyncio.Queue
_sse_clients: set[asyncio.Queue] = set()

_start_time: float = time.time()


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _build_status() -> dict:
    base: dict = {"server_type": "unknown", "mc_version": "unknown",
                  "max_players": 20, "status": "starting"}
    try:
        with open(STATUS_FILE) as f:
            base.update(json.load(f))
    except Exception:
        pass
    return {
        **base,
        "ready":          _server_ready,
        "players":        sorted(_player_set),
        "player_count":   len(_player_set),
        "uptime_seconds": int(time.time() - _start_time),
    }


def _parse_log_line(line: str) -> bool:
    """Update runtime state; return True if player count changed."""
    global _server_ready
    changed = False
    if not _server_ready and "Done (" in line and "For help" in line:
        _server_ready = True
        changed = True
    m = re.search(r":\s+(\S+)\s+joined the game", line)
    if m:
        _player_set.add(m.group(1))
        changed = True
    m = re.search(r":\s+(\S+)\s+left the game", line)
    if m:
        _player_set.discard(m.group(1))
        changed = True
    return changed


async def _push_status() -> None:
    """Push a status snapshot to every active SSE client."""
    payload = json.dumps(_build_status())
    dead: set[asyncio.Queue] = set()
    for q in _sse_clients:
        try:
            q.put_nowait(payload)
        except asyncio.QueueFull:
            dead.add(q)
    _sse_clients.difference_update(dead)


async def _broadcast_terminal(line: str) -> None:
    """Send a log line to every active WebSocket terminal client."""
    dead: set[web.WebSocketResponse] = set()
    for ws in _ws_clients:
        try:
            await ws.send_str(line)
        except Exception:
            dead.add(ws)
    _ws_clients.difference_update(dead)


# ---------------------------------------------------------------------------
# Background task: tail the log file, broadcast to WS, notify SSE on change
# ---------------------------------------------------------------------------

async def _tail_log_task() -> None:
    log_path = Path(LOG_FILE)
    while True:
        if not log_path.exists():
            await asyncio.sleep(1)
            continue

        try:
            stat_before = log_path.stat()
            with log_path.open("r", errors="replace") as f:
                f.seek(0, 2)
                while True:
                    line = f.readline()
                    if line:
                        line = line.rstrip("\n")
                        changed = _parse_log_line(line)
                        await _broadcast_terminal(line + "\n")
                        if changed:
                            await _push_status()
                    else:
                        await asyncio.sleep(0.05)
                    try:
                        if not log_path.exists() or \
                                log_path.stat().st_ino != stat_before.st_ino:
                            break
                    except OSError:
                        break
        except OSError:
            await asyncio.sleep(1)


# ---------------------------------------------------------------------------
# Background task: heartbeat SSE every 10 s so clients detect stale links
# ---------------------------------------------------------------------------

async def _sse_heartbeat_task() -> None:
    while True:
        await asyncio.sleep(10)
        await _push_status()


# ---------------------------------------------------------------------------
# HTTP handlers
# ---------------------------------------------------------------------------

async def handle_index(request: web.Request) -> web.FileResponse:
    return web.FileResponse(STATIC_DIR / "index.html")


async def handle_sse_status(request: web.Request) -> web.StreamResponse:
    """SSE endpoint — server pushes status; client never sends data back."""
    resp = web.StreamResponse(headers={
        "Content-Type":  "text/event-stream",
        "Cache-Control": "no-cache",
        "Connection":    "keep-alive",
        "X-Accel-Buffering": "no",   # disable nginx buffering if proxied
    })
    await resp.prepare(request)

    q: asyncio.Queue = asyncio.Queue(maxsize=16)
    _sse_clients.add(q)

    # Send current state immediately so the page doesn't wait 10 s
    try:
        snapshot = json.dumps(_build_status())
        await resp.write(f"data: {snapshot}\n\n".encode())
    except Exception:
        _sse_clients.discard(q)
        return resp

    try:
        while True:
            try:
                payload = await asyncio.wait_for(q.get(), timeout=30)
                await resp.write(f"data: {payload}\n\n".encode())
            except asyncio.TimeoutError:
                # Send a keep-alive comment so the connection doesn't time out
                await resp.write(b": keepalive\n\n")
    except (ConnectionResetError, Exception):
        pass
    finally:
        _sse_clients.discard(q)

    return resp


# ---------------------------------------------------------------------------
# WebSocket terminal (bidirectional: log stream → client, commands ← client)
# ---------------------------------------------------------------------------

async def handle_ws_terminal(request: web.Request) -> web.WebSocketResponse:
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    _ws_clients.add(ws)

    # Replay recent history so a fresh tab has context
    log_path = Path(LOG_FILE)
    if log_path.exists():
        try:
            with log_path.open("r", errors="replace") as f:
                lines = f.readlines()
            for line in lines[-300:]:
                await ws.send_str(line if line.endswith("\n") else line + "\n")
        except OSError:
            pass

    try:
        async for msg in ws:
            if msg.type == WSMsgType.TEXT:
                cmd = msg.data.strip()
                if cmd:
                    await _send_command(cmd, ws)
            elif msg.type in (WSMsgType.ERROR, WSMsgType.CLOSE):
                break
    finally:
        _ws_clients.discard(ws)

    return ws


async def _send_command(cmd: str, ws: web.WebSocketResponse) -> None:
    pipe_path = Path(STDIN_PIPE)
    if not pipe_path.exists():
        await ws.send_str("[dashboard] Server stdin not available\n")
        return
    loop = asyncio.get_event_loop()
    try:
        await loop.run_in_executor(None, _write_pipe, cmd)
    except Exception as exc:
        await ws.send_str(f"[dashboard] Failed to send command: {exc}\n")


def _write_pipe(cmd: str) -> None:
    with open(STDIN_PIPE, "w") as f:
        f.write(cmd + "\n")
        f.flush()


# ---------------------------------------------------------------------------
# App factory + entrypoint
# ---------------------------------------------------------------------------

def create_app() -> web.Application:
    app = web.Application()
    app.router.add_get("/",                 handle_index)
    app.router.add_get("/events/status",    handle_sse_status)
    app.router.add_get("/ws/terminal",      handle_ws_terminal)
    app.router.add_static("/static",        STATIC_DIR, show_index=False)
    return app


async def _main() -> None:
    app = create_app()
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", PORT)
    await site.start()

    asyncio.create_task(_tail_log_task())
    asyncio.create_task(_sse_heartbeat_task())

    print(f"Dashboard listening on 0.0.0.0:{PORT}", flush=True)
    await asyncio.Event().wait()


if __name__ == "__main__":
    asyncio.run(_main())
