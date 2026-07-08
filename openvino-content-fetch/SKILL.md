---
name: openvino-content-fetch
description: |
  Fetches, parses, and indexes notebooks, sample codes, models, and articles from OpenVINO GitHub
  repository, ModelScope Intel AI PC Zone, and CSDN Intel Developer Zone — AND locates/downloads
  models and pre-converted OpenVINO IR from ModelScope (Model Repo + Intel AI PC Zone) and the Intel
  OpenVINO Model Hub for local inference on Intel AIPC.
  Call this skill when the student or learning-bot asks for notebooks, tutorials, sample codes,
  ModelScope updates, CSDN developer articles, learning path recommendations, OR to find / resolve /
  download a model or pre-converted IR for local OpenVINO inference.
  Triggers: fetch notebooks, get tutorials, find OpenVINO samples, get articles, ModelScope updates,
  CSDN posts, content fetch, recommend notebooks, download model, get IR, resolve model, find
  OpenVINO-optimized model.
---

# OpenVINO Content Fetch — learning bot pipeline step

This skill owns both **content** and **model files** for the learning bot:

1. **Content** — notebooks, tutorials, sample code, and articles from the OpenVINO GitHub repo,
   ModelScope AI PC Zone, and CSDN Intel Developer Zone. It crawls/reads these resources and returns
   a clean, structured index inside a standard `[SKILL_RESULT]` block. The GitHub notebook list is
   fetched **live from the `latest` branch** (GitHub API), so recommendations always reflect the
   current notebooks; a seeded list is used only as an offline/failure fallback.
2. **Model files / IR** — it locates and downloads models and **pre-converted OpenVINO IR** from
   ModelScope (Model Repo + Intel AI PC Zone) and the Intel OpenVINO Model Hub. It resolves a model
   id, prefers an existing OpenVINO IR when available, reports size/license before large downloads,
   and fetches the files to a local directory for local OpenVINO inference on Intel AIPC.

## Parameters

| Parameter | Description |
|---|---|
| -Source | github (notebooks), modelscope (AI PC zone), csdn (Intel dev zone), or all (default) |
| -Download | A model id to download (e.g. `Qwen2.5-7B-Instruct-INT4-OV`); triggers download mode |
| -OutDir | Local directory to download the model / IR into (defaults to `~/.openvino/models`) |
| -China | Switch to use local mirrors/endpoints |

```powershell
# Fetch GitHub notebooks only
run.ps1 -Source github

# Fetch everything using China mirrors
run.ps1 -Source all -China

# Download a pre-converted OpenVINO IR model from ModelScope
run.ps1 -Download "Qwen2.5-7B-Instruct-INT4-OV" -OutDir "D:\models\qwen2.5-7b"
```

## Content fetch — [SKILL_RESULT] (fetch contract)

```
[SKILL_RESULT]
status=ok|error
source=github|modelscope|csdn|all
count=<number of items fetched>
data=[JSON-formatted list of items]
[/SKILL_RESULT]
```

## Model download

### Where to find models

1. **ModelScope — OpenVINO organization (prefer pre-converted IR)**
   - **URL:** https://www.modelscope.cn/organization/OpenVINO
   - OpenVINO-optimized models, many already exported to IR. Prefer these — no conversion needed.
2. **ModelScope — Intel AI PC Zone model list**
   - **URL:** https://modelscope.cn/brand/view/AI_PC?branch=2&tree=1
   - Models curated for Intel AI PC; check for an IR / OpenVINO variant before downloading the source.
3. **Intel OpenVINO Model Hub**
   - **URL:** https://www.intel.com/content/www/us/en/developer/tools/openvino-toolkit/model-hub.html
   - Fallback source of models optimized for Intel hardware (different page structure than ModelScope).

### Download procedure

1. **Resolve** the model id (from the user, or by searching the sources above via `-Source modelscope`).
   Prefer a variant that already ships OpenVINO IR (`openvino_model.xml/.bin`); if only the source
   model exists, flag that conversion (via `openvino-pipeline-optimization`) will be needed.
2. **Report before downloading:** model id, size, license, and whether IR is available — confirm
   before pulling multi-GB assets.
3. **Download** to a local directory using the ModelScope SDK:
   ```python
   from modelscope import snapshot_download
   local_dir = snapshot_download("OpenVINO/<model-id>")   # e.g. an OpenVINO-optimized repo
   ```
   ModelScope is domestic (fast in China by default). Set `local_dir=` to a persisted path so retries
   don't re-download.
4. **Report result:** local path + which files (IR vs source), so the pipeline / env skills can use it.

### Model download — [SKILL_RESULT] (download contract)

```
[SKILL_RESULT]
status=ok|error
action=download
model_id=<resolved model id>
local_dir=<absolute local path>
has_ir=true|false
[/SKILL_RESULT]
```

## API Reference (ModelScope)

Programmatic model lookup / download on ModelScope:

**Base URL:** https://modelscope.cn/openapi/v1  ·  **Auth:** Bearer Token

- `GET /models` — list / search models (filter by task, keyword)
- `GET /models/{owner}/{repo_name}` — model details (files, size, license)

**OpenAPI docs:** https://modelscope.cn/docs/openapi

## Testing
Run the offline smoke test (uses stdlib-only paths + seeded fallbacks; no venv, bs4, or network
required) to validate the fetch and download contracts:
```powershell
powershell -ExecutionPolicy Bypass -File test_content_fetch.ps1
```
Exit code `0` = all checks passed. It asserts a well-formed `[SKILL_RESULT]` (status/count) for each
source and the `action=download` contract.
