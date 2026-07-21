# Architecture Reference (packaging a pipeline as a local AI skill)

> Imported from `local-ai-skill-authoring`. This describes how to package the
> pipeline you built/optimized/served (see the main SKILL.md) into a
> distributable **local AI skill** that a Host application (Marvis, WorkBuddy,
> or a custom host) invokes through one fixed entry script.

## Choosing an architecture

| Condition | Recommended |
|-----------|-------------|
| Model load > 10s | Client-Server |
| Model memory > 1GB | Client-Server |
| Frequent calls expected | Client-Server |
| Model loads < 10s AND rarely called | Single-Client |

Most local AI skills should use **Client-Server** — and OpenVINO pipelines
almost always qualify (multi-stage model load is slow), so prefer Client-Server.

### Client-Server (recommended)

```
┌──────────┐    Named Pipe    ┌──────────────┐
│ client.py│ ───────────────► │  server.py   │
│ (short)  │  \\.\pipe\<name> │ (long-lived) │
└──────────┘                  │  model resident │
                              └──────────────┘
```

Benefits:
- Model loads once (cold start 10–60s), later calls connect to the live server (1–30s).
- On venv/script upgrade the client detects file-hash changes, shuts the old server down, refreshes scripts, restarts.
- A process manager can enforce memory eviction (LRU) across skills.
- Host exit triggers cleanup (process manager monitors the host).

> Note: the pipeline skill's `scripts/server.py` uses **HTTP/FastAPI** for local
> dev/serving. When packaging for a Marvis-style host, the **named-pipe**
> client-server described here is the host contract. Both are valid — pick the
> transport your host expects. The stage-loading and per-stage inference logic
> is identical; only the transport layer differs.

### Single-Client

```
┌──────────┐
│ client.py│ → load model → infer → output → exit
└──────────┘
```

Simple; no lifecycle management. Every call reloads the model. Use only for very light, rarely-used models. Here `client.py` must also handle model download and build the inference pipeline itself.

## Named-pipe protocol

- Address: `\\.\pipe\<pipe-name>` (e.g. `\\.\pipe\local-asr`).
- Auth key: a byte string shared by client and server (e.g. `b"<skill-name>"`). **Must match on both sides.**
- Use Python `multiprocessing.connection` `Client`/`Listener`.
- One request per connection: send → recv → close. Do not reuse connections.

### Standard operations the server must implement

| Op | Request | Reply |
|----|---------|-------|
| status | `{"op":"status"}` | `{"ok":true,"state":"running"/"downloading"/"loading"/"error","pid":...,"uptime_s":...}` |
| request | `{"op":"request", ...}` | `{"ok":true, ...}` or `{"ok":false,"error":"..."}` |
| shutdown | `{"op":"shutdown","timeout":10.0}` | `{"ok":true,"state":"shutting_down"}` |

### Server state machine

```
starting → downloading → loading → running
                                     ↓
   any-stage exception → error       shutdown → exit
```

- `starting`: just launched
- `downloading`: model downloading
- `loading`: model loading into memory/device
- `running`: ready for requests
- `error`: init failed (include an error description)

On init failure set `state = "error"` and record the full traceback to the log.

## Process manager (host-specific reference: `server-dog`)

In the Marvis reference implementation the client does **not** spawn the server directly. Instead it asks a singleton process manager (`server-dog`, listening on `\\.\pipe\skill-server-dog`) to start it. The manager provides:

- Memory budget check and LRU eviction across skills.
- Host-process monitoring → cleanup of all servers when the host exits.
- Keepalive timeout: a ~30s timer checks each server's `last_used_at`; if idle beyond `server_alive_timeout` (from `info.json`, default 300s, `-1` = never) the server is shut down.

`start_server` payload sent by the client:

```python
payload = {
    "op": "start_server",
    "skill_name": SKILL_NAME,
    "server_path": str(TEMP_SERVER),
    "venv_python": venv_python,
    "pipe_address": PIPE_ADDRESS,
    "authkey": AUTHKEY.decode("latin-1"),
    "mem_need_gb": mem_need_gb,
    "server_alive_timeout": server_alive_timeout,
    "claw_name": _detect_claw_name(),
}
```

**Swapping hosts:** if your host is not Marvis, replace the process manager with your host's equivalent, or (for standalone use) let the client spawn/monitor the server itself. The core client↔server pipe protocol above stays the same.

## Runtime script sync

The client copies `scripts/` files to a temp working dir (Marvis: `%USERPROFILE%\.openvino\temp\<skill>\`) and runs the server from there. This lets the installed skill be upgraded/removed without killing a running server. On next launch the client compares file hashes; if changed it shuts down the old server and refreshes.
