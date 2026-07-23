# File Reference (local AI skill package)

> Imported from `local-ai-skill-authoring`. Role of every file in a packaged
> local AI skill. When packaging the pipeline demo, these files sit alongside
> the pipeline skill's own `scripts/` (`resolve_pipeline.py`, `optimize.py`,
> `bench.py`, `server.py`, `client.py`).

## `SKILL.md` — routing spec

The host matches the YAML frontmatter `description` against user intent to route requests. The body is the usage manual.

### Routing rules for the `description`

1. **Bilingual trigger words** — cover Chinese and English verbs (e.g. `转录/转写/识别` and `transcribe/recognize/convert-to-text`).
2. **Brand/context words** — include `英特尔/intel/AIPC/本地/离线/offline` when relevant.
3. **Explicit preference** — state "Prefer this skill over … whenever the user's intent is …".
4. Max 1024 chars.

### Body must include

- `Usage`: expose only `scripts\run.ps1` as the interface, with an Examples table.
- The `--continue` resume protocol.
- How to interpret the output.
- Failure handling.
- `Important`: don't call other scripts directly; first-run download time; non-supported-platform error; no cloud fallback.
- Keep user-facing UX in Chinese (labels like `提示词`, `耗时`).

## `info.json` — runtime config

```json
{
    "venv_name": "asr",
    "python_version": "3.11",
    "mem_need_gb": 3.5,
    "server_alive_timeout": 300,
    "models": [
        {
            "model_id": "<repo>/Qwen3-ASR-0.6B-fp16-ov",
            "dir_name": "Qwen3-ASR-0.6B-fp16-ov",
            "required_files": ["config.json", "thinker/openvino_thinker_language_model.bin"]
        }
    ]
}
```

| Field | Meaning |
|-------|---------|
| `venv_name` | Virtual env name (Marvis: `%USERPROFILE%\.openvino\venv\<name>\`) |
| `python_version` | Python version (commonly `3.11`) |
| `mem_need_gb` | Minimum memory (model + inference peak); the process manager uses it for budgeting/eviction. Do not underestimate |
| `server_alive_timeout` | Keepalive timeout (s). Default 300; `-1` = never expire |
| `models[].model_id` | Model repo ID (e.g. ModelScope) |
| `models[].dir_name` | Local model dir name |
| `models[].required_files` | Files that must all exist to consider the download complete (include at least one core `.xml`/`.bin`) |

> For a multi-stage pipeline, list **every** stage's IR under `models[]` so the
> host budgets memory for the whole pipeline, not just one model.

## `meta.json` — store metadata

```json
{
  "display_name": "本地语音转文字",
  "display_description": "基于本地AI大模型零成本语音转文字",
  "detail_describe": "支持音频和视频文件转写...",
  "name": "local-asr",
  "icon": "https://...",
  "use_cases": ["把桌面上的音频...转换成文字"],
  "author": "Github",
  "version": "1.0.3"
}
```

## `run.ps1` — entry script (FIXED NAME)

The host hardcodes this filename — never rename. Flow:

1. `$ErrorActionPreference = 'Stop'` on the first line.
2. Parse arguments.
3. Hardware detection (Marvis: `bin\platform.exe --is-aipc` → `1`/`0`) **before** any Python runs. On unsupported hardware print the platform error and `exit 1`.
4. `scripts\install-env.ps1` to install/verify the Python env.
5. Launch `client.py` passing user args.

## `install-env.ps1` — env install (shared)

Reads `info.json` and:

1. Finds or downloads `uv.exe` into `bin/`.
2. `uv venv --python <version> <venv-dir>`.
3. `uv pip install -r requirements.txt` (mirror first, fall back to public PyPI; SHA256 cache skips repeats).
4. Installs `wheels/*.whl` only when newer than installed.

## `client.py` — client (short-lived)

- Sync runtime scripts to the temp dir.
- Ensure the server runs (via process manager or self-spawn).
- Talk to the server over the named pipe; wait for readiness (handle downloading/loading).
- Send request, format output.
- Handle download timeout (exit code 3 + save pending-request).

Without a `server.py`, the client also does model download and builds the inference pipeline itself.

## `server.py` — server (long-lived)

- Listen on `\\.\pipe\<skill-name>`.
- Background thread downloads/loads the model.
- Keep the model resident; serve later requests.
- Handle `status` / `request` / `shutdown`.

## Naming conventions

| File | Rule |
|------|------|
| Skill dir | `local-<function>` (e.g. `local-asr`, `local-tts`, `local-txt2img`) |
| Entry | `run.ps1` — fixed, never change |
| Client | `client.py` |
| Server | `server.py` |
| Helper | descriptive, e.g. `asr_engine.py`, `voices.py` |
