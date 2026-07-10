# Learning Bot Skills

A set of OpenVINO skills for a local **Learning Bot** on Intel AIPC (Windows). The bot turns a
natural-language request into a concrete result — a configured environment, recommended learning
material, or a runnable, optimized, served demo — by orchestrating the three skills below. Everything
runs locally and is offline / China-network capable (`-China`).

## Skills

| Skill | What it does |
|---|---|
| [`learning-bot`](learning-bot/) | **Entry / launcher.** Starts the Learning Bot: recommends a set of preset questions (each mapped to a local aipc-skill — ASR / TTS / realtime-translator / OCR (NPU·GPU) / MinerU / txt2img / img2img / txt2video / SR / YOLO26 / screenshot-QA / computer-use / VRAM). Downloads & invokes the matching skill on a preset hit; routes out-of-scope requests to the three dev skills below. |
| [`openvino-environment-management`](openvino-environment-management/) | Configure the Intel AIPC dev environment on Windows (Python, Git, ModelScope, OpenVINO, PyTorch; optional CMake / Visual Studio). |
| [`openvino-content-fetch`](openvino-content-fetch/) | Fetch, parse, and index notebooks / samples / models / articles from GitHub, ModelScope AI PC Zone, and CSDN; returns a structured `[SKILL_RESULT]`. Also locates and downloads models / pre-converted OpenVINO IR from ModelScope and the Intel OpenVINO Model Hub. |
| [`openvino-pipeline-optimization`](openvino-pipeline-optimization/) | Scaffold a multi-model OpenVINO pipeline from notebook(s): discover stages → optimize (device + precision) → benchmark → serve (client + server). |

The `learning-bot` skill is the **entry point**: it presents preset questions and routes each request
to a preset local skill or, when out of scope, to one of the three dev skills. The preset skills are
downloaded from the [`makejiang/aipc-skills`](https://github.com/makejiang/aipc-skills/releases/tag/1.0.6)
`1.0.6` release.

## Learning Bot

- **[`learning-bot-system-prompt.md`](learning-bot-system-prompt.md)** — the system prompt for the
  orchestration agent (role, skill routing, honesty & limits, response style).
- **[`learning-bot-test-cases.md`](learning-bot-test-cases.md)** — prompt test cases for evaluating the
  bot's intent classification, skill selection/ordering, and boundary handling.
- **[`learning-bot-preset-test-cases.md`](learning-bot-preset-test-cases.md)** — prompt test cases for
  the `learning-bot` launcher: preset vs. non-preset routing, discovery, boundaries, and honesty.

## Requirements

- Intel AIPC (Windows) — Intel Ultra series or Intel Arc recommended for NPU/GPU acceleration.
- Each skill's `SKILL.md` documents its parameters, usage, and (where applicable) the `[SKILL_RESULT]`
  contract.

## Usage

Each skill is invoked via its own entry script / instructions in `SKILL.md`. Add `-China` (or
`--china`) to use domestic mirrors (pip / ModelScope / HF-mirror / GitCode) when GitHub/HF aren't
directly reachable.
