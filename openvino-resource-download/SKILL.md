---
name: "openvino-resource-download"
description: "Locate and download models and pre-converted OpenVINO IR from ModelScope (Model Repo + Intel AI PC Zone) and the Intel OpenVINO Model Hub. Invoke when the user needs to find, resolve, or download a model / IR for local OpenVINO inference on Intel AIPC."
---

# Resource Download (ModelScope)

This skill owns **model files**: it locates and downloads models and **pre-converted OpenVINO IR**
from ModelScope (Model Repo + Intel AI PC Zone) and the Intel OpenVINO Model Hub, for local OpenVINO
inference on Intel AIPC. It resolves a model id, prefers an existing OpenVINO IR when available,
reports size/license before large downloads, and fetches the files to a local directory.

> **Division of labour:** this skill downloads *model files / IR*. To fetch *content* — notebooks,
> tutorials, samples, articles, ModelScope/CSDN updates — use the `openvino-content-fetch` skill.

## Invocation Triggers

Call this skill when the user asks to:
- Find / download a model for OpenVINO (e.g. "download Qwen2.5-7B OpenVINO", "get a whisper model")
- Resolve a **pre-converted OpenVINO IR** for a model
- Locate OpenVINO-optimized models on ModelScope or the Intel OpenVINO Model Hub

## Where to find models

### 1. ModelScope — OpenVINO organization (prefer pre-converted IR)
- **URL:** https://www.modelscope.cn/organization/OpenVINO
- OpenVINO-optimized models, many already exported to IR. Prefer these — no conversion needed.

### 2. ModelScope — Intel AI PC Zone model list
- **URL:** https://modelscope.cn/brand/view/AI_PC?branch=2&tree=1
- Models curated for Intel AI PC; check for an IR / OpenVINO variant before downloading the source.

### 3. Intel OpenVINO Model Hub
- **URL:** https://www.intel.com/content/www/us/en/developer/tools/openvino-toolkit/model-hub.html
- Fallback source of models optimized for Intel hardware (different page structure than ModelScope).

## Download procedure

1. **Resolve** the model id (from the user, or by searching the sources above). Prefer a variant that
   already ships OpenVINO IR (`openvino_model.xml/.bin`); if only the source model exists, flag that
   conversion (via `openvino-pipeline-optimization`) will be needed.
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

## API Reference

Programmatic model lookup / download on ModelScope:

**Base URL:** https://modelscope.cn/openapi/v1  ·  **Auth:** Bearer Token

- `GET /models` — list / search models (filter by task, keyword)
- `GET /models/{owner}/{repo_name}` — model details (files, size, license)

**OpenAPI docs:** https://modelscope.cn/docs/openapi

For SPA pages that don't expose a clean API, browser tools may be used to read the model page, but the
**goal of this skill is to resolve and download model/IR files** — not to browse news/articles.
