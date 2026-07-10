---
name: openvino-pipeline-optimization
description: |
  一套面向开发者的脚手架 + 参考标准，用于在 Intel AIPC 上构建多模型 OpenVINO 流水线 demo，
  以 openvino_notebooks 仓库（github.com/openvinotoolkit/openvino_notebooks）为依据。
  给定一个或多个 notebook slug（例如 whisper-asr-genai、llm-rag-langchain、vlm-chatbot、
  openvoice2-and-melotts）或一个自由描述的目标（例如 "local ASR -> LLM -> TTS"），它会从 notebook
  本身**发现**流水线各阶段，给出每个阶段的优化建议（设备 NPU/GPU/CPU + 精度 INT4/INT8，经 NNCF），
  做端到端 + 逐阶段基准测试，并提供 client+server 模板把 demo 部署为本地服务。它提供的是**方向 +
  一套约定**，而**不是**开箱即用的自动构建器。随附的脚本是**参考实现**，不是强制路径：模型转换和
  推理必须遵循所选 notebook 自己的代码，而不是某个通用脚本。未接入的流水线族返回 501，绝不伪造输出。
  当开发者想要构建/搭建 demo、把多个模型组合/串联成一条流水线、把阶段放到设备上、调精度、做基准
  测试，或把流水线部署为服务（client+server）时使用本技能。触发词：build a demo / scaffold a
  pipeline / multi-model pipeline / chain models / ASR->LLM->TTS / RAG / vision chatbot /
  device placement / benchmark the pipeline / deploy as a service / serve a pipeline /
  client server / reference standard。
  需要 Intel AIPC 硬件。
---

# OpenVINO Pipeline Optimization —— 开发者脚手架 & 参考标准

本技能为开发者提供在 Intel AIPC 上构建多模型 OpenVINO 流水线 demo 的**方向和一套约定** ——
而不是一条现成的流水线。它展示*如何*从 `openvino_notebooks` 发现各阶段、*如何*把各阶段放到
设备/精度上、*如何*做基准测试，以及*如何*用 **client + server** 把它们封装起来。真正的流水线
由用户选定的 notebook 组合搭建而成；开发者补齐各阶段特定的逻辑。本技能提供结构、建议默认值和
诚实的报告 —— 绝不提供预制的流水线。

主线（一条建议路径，按 notebook 需要裁剪/替换）：

**选 notebook → 发现并组合各阶段 → 优化（设备 + 精度）→ 基准测试 → 部署（client+server）**

### 哪些是固定的 vs. 哪些由你构建

| 固定（本技能标准化的约定） | 由你构建（来自所选 notebook） |
| --- | --- |
| 目录布局、`[SKILL_RESULT]` 契约、生命周期参数 | 阶段图以及各阶段如何连接 |
| client+server *模式*（endpoints、health、501 诚实） | 每个阶段的模型加载 / 转换 / 推理代码 |
| 建议的设备/精度启发式（可覆盖） | 权威的转换 + 推理 —— 从 notebook 复制/改编而来 |

> **脚本是参考，不是法律。** `scripts/` 下的所有内容（`resolve_pipeline.py`、`optimize.py`、
> `bench.py`、`server.py`、`client.py`）都是这些约定的**参考实现**。把它们当作起点，可自由改编。
> 当某个脚本的通用行为（例如一刀切的 `optimum-cli export openvino`）与 notebook 冲突时，
> **以 notebook 为准** —— 它的模型加载、转换和推理才是权威来源。

> **通用为设计原则。** 不硬编码任何 model ID —— 各阶段从所选 notebook 中发现。没有模型族开关。
> 未接入 runner 的流水线族返回 HTTP 501；本技能绝不伪造输出。

---

## !! 关键：环境 / 镜像 / 持久化 !!

| 需求 | 详情 |
| --- | --- |
| Intel AIPC (LNL/ARL/PTL/WCL)、git | 运行前先验证 |
| Python 3.x | **不做硬性锁定** —— 使用所选 notebook 支持的版本（由它的 `requirements.txt` 决定）。venv 用当前 `python` 解析到的版本创建 |
| `--china` | pip=tuna、HF=hf-mirror、notebooks=gitcode；不做网络探测 |
| 持久化目录（sandbox 之外） | `%USERPROFILE%\.openvino\`：`venv-pipeopt\`、`openvino_notebooks\`、`ir\<slug>\`、`log\` |

首次运行时依赖装入持久化 venv：参考脚本所需的**最小核心**
（`openvino, nncf, optimum-intel, fastapi, uvicorn, pydantic, nbformat, numpy` —— 仅当某阶段用到时
再加 `openvino-genai`/`openvino-tokenizers`），**加上每个所选 notebook 自己的 `requirements.txt`**
（`notebooks/<slug>/requirements.txt`），这样模型相关依赖始终与所选 notebook 匹配。没有技能级的静态
requirements 文件，也没有强制的版本锁定 —— 依赖从你构建的 notebook 中解析而来。如果某个 notebook
锁定了自己的 OpenVINO/Python 版本，以 notebook 为准。

---

## 构建 & 优化（参考流程）

下面的命令驱动的是**参考**脚本。它们是方便的起点；真正的转换/推理请优先采用所选 notebook 里的
步骤，并据此改编脚本。

```powershell
# 单个 notebook
run.ps1 --china --slug whisper-asr-genai
# 把多个 notebook 组合成一条流水线
run.ps1 --china --slug whisper-asr-genai,llm-rag-langchain,openvoice2-and-melotts
# 按目标（与仓库的 notebooks/README.md 索引匹配）
run.ps1 --china --goal "local ASR to LLM to TTS"
# 仅解析 + 规划（不下载）
run.ps1 --dry-run --slug vlm-chatbot
```

流程：**resolve**（`resolve_pipeline.py` —— 从 `notebooks/<slug>/` 发现各阶段）→
**optimize**（`optimize.py` —— 一个调用 `optimum-cli export openvino` + NNCF + 设备的参考导出器
→ `pipeline-plan.json`）→ **benchmark**（`bench.py` —— 逐阶段 + 端到端、瓶颈、`[SKILL_RESULT]`）。

> 参考的 `optimize.py` 用的是单一通用的 `optimum-cli export openvino`。它对很多标准模型有效，但
> **并不权威**：如果 notebook 以特定方式转换模型（自定义 export 参数、`ov.convert_model`、手写
> NNCF 配置、stateful/GenAI 导出、多个子模型），请把导出调用替换为 notebook 自己的转换方式。推理
> 同理 —— notebook 的运行时代码才是参考，而不是 `server.py` 的通用执行器。

**建议的**每角色设备/精度启发式（仅为默认值，始终可通过 `--device` / `--precision` 覆盖，并被
notebook 的实际做法取代）：LLM→GPU/INT4、encoder→GPU/INT8、retriever→CPU/INT8、pre/post→CPU/FP16。

### `[SKILL_RESULT]`（构建/基准测试契约）
```
[SKILL_RESULT]
status=ok|error|timeout
pipeline=<slug or a+b+c>
stages=asr:GPU/INT8/312ms; llm:GPU/INT4/540ms; tts:CPU/FP16/120ms
e2e_latency_ms=972
throughput=...
bottleneck=llm
ir_dir=%USERPROFILE%\.openvino\ir\<slug>
[/SKILL_RESULT]
```

---

## 部署流水线（client + server）

把构建并优化好的流水线部署为本地 HTTP 服务，然后用 CLI client 与之交互。

```powershell
run.ps1 --serve --slug whisper-asr-genai [--port 18790]   # 构建+优化（复用 IR）后部署
```

`--serve` 会 resolve → optimize（复用已有 IR）→ 在后台启动 `server.py` → 轮询 `/api/health` →
输出带 `service_url` 的 `[SKILL_RESULT]` 并打印 client 用法。

**架构**
```
 CLI / HTTP client  ──HTTP :18790──▶  server.py (FastAPI)  ──▶  OpenVINO pipeline stages (from pipeline-plan.json)
   client.py / curl                     /api/run · /api/health · /v1/chat/completions · /api/shutdown
```

**Endpoints**（服务运行在 `127.0.0.1:18790`）

| Endpoint | Method | 用途 |
| --- | --- | --- |
| `/api/health` | GET | 状态 + 各阶段加载情况 |
| `/api/run` | POST | 通用执行器：`{input, params}` → `{output, per_stage_ms, e2e_ms}` |
| `/v1/chat/completions` | POST | 兼容 OpenAI（chat/LLM & RAG 族） |
| `/api/shutdown` | POST | 优雅退出 |

**Client**
```powershell
python scripts\client.py --health
python scripts\client.py --run --input "your input"
python scripts\client.py --chat "hello"          # chat/RAG 流水线
curl http://127.0.0.1:18790/api/health
```

**诚实原则：** 未接入 runner 的流水线族返回 **HTTP 501**（"runner for family 'X' not implemented
yet"）—— 开发者用 **notebook 自己的推理代码**在 `server.py::PIPELINE_RUNNERS` 中接入该族的 runner。
绝不伪造。`server.py --stub` 返回预设输出，用于在没有硬件的情况下接线/测试 client。通用的 `/api/run`
执行器只是一层便捷外壳，不能替代 notebook 的流水线逻辑。

---

## 生命周期 & 参数

| 参数 | 含义 |
| --- | --- |
| `--slug a[,b,c]` | 一个或多个 notebook slug（逗号 = 按顺序组合） |
| `--goal "…"` | 自由描述的目标 → 通过仓库索引匹配到 slug |
| `--device / --precision` | 覆盖每角色默认值 |
| `--serve [--port N]` | 构建+优化，然后部署（默认端口 18790） |
| `--china` | 锁定国内镜像 |
| `--dry-run` | 仅解析 + 规划 |
| `--status` | venv / notebooks / 上次 plan / **服务**状态（以 `[SKILL_RESULT]` 输出） |
| `--stop` | POST `/api/shutdown`，然后杀掉 pidfile + 残留进程 |
| `--debug` | 详细诊断（venv、repo、设备、最近日志） |

退出码 `0` 成功 / `1` 出错。幂等：重跑会复用已克隆的仓库 + 已有 IR（标 `from IR`）。

## 排错（简要）
- **repo-required / goal-unresolved** → 让 `--serve`/构建先克隆仓库；细化 `--goal` 或传 `--slug`。
- **no static model ids found** → 该 notebook 动态获取模型；显式提供该阶段的模型，或先跑一次 notebook。
- **/api/run 501** → 在 `server.py::PIPELINE_RUNNERS` 中接入该族的 runner（设计如此）。
- **service not healthy** → `run.ps1 --debug`；检查端口、venv 依赖、`%USERPROFILE%\.openvino\log\` 下的最近日志。

## 做什么 / 不做什么
- **做：** 为基于仓库的流水线提供方向 + 约定；从 notebook 发现各阶段；建议每阶段设备/精度；基准测试；提供 `[SKILL_RESULT]` + client/server *模式*；多 notebook 组合；离线/`--china`。
- **不做：** 交付现成的流水线；强制把随附脚本作为执行路径；臆造模型架构；硬编码 model ID 或 Python/OpenVINO 版本；覆盖 notebook 的转换/推理；云端/非 Intel；为未接入的族伪造输出。

## 测试
运行离线冒烟测试（无需模型、无需克隆、无需 Intel 硬件）来验证编排 ——
resolve → optimize `--dry-run` → bench `--dry-run` → client `--help` → `--status`：
```powershell
powershell -ExecutionPolicy Bypass -File test_pipeline.ps1
```
退出码 `0` = 所有检查通过。它会在临时目录里构建一个极小的合成 notebooks 仓库，并断言发现的各阶段、
plan 文件和 `[SKILL_RESULT]` 块。
