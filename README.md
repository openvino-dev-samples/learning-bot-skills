# Learning Bot Skills

A set of OpenVINO skills for a local **Learning Bot** on Intel AIPC (Windows). The bot turns a
natural-language request into a concrete result — a configured environment, recommended learning
material, or a runnable, optimized, served demo — by orchestrating the three skills below. Everything
runs locally and is offline / China-network capable (`-China`).

## Skills

| Skill | What it does |
|---|---|
| [`openvino-environment-management`](openvino-environment-management/) | Configure the Intel AIPC dev environment on Windows (Python, Git, ModelScope, OpenVINO, PyTorch; optional CMake / Visual Studio). |
| [`openvino-content-fetch`](openvino-content-fetch/) | Fetch, parse, and index notebooks / samples / models / articles from GitHub, ModelScope AI PC Zone, and CSDN; returns a structured `[SKILL_RESULT]`. Also locates and downloads models / pre-converted OpenVINO IR from ModelScope and the Intel OpenVINO Model Hub. |
| [`openvino-pipeline-optimization`](openvino-pipeline-optimization/) | Scaffold a multi-model OpenVINO pipeline from notebook(s): discover stages → optimize (device + precision) → benchmark → serve (client + server). |

## Learning Bot

- **[`learning-bot-system-prompt.md`](learning-bot-system-prompt.md)** — the system prompt for the
  orchestration agent (role, skill routing, honesty & limits, response style).
- **[`learning-bot-test-cases.md`](learning-bot-test-cases.md)** — prompt test cases for evaluating the
  bot's intent classification, skill selection/ordering, and boundary handling.

## Requirements

- Intel AIPC (Windows) — Intel Ultra series or Intel Arc recommended for NPU/GPU acceleration.
- Each skill's `SKILL.md` documents its parameters, usage, and (where applicable) the `[SKILL_RESULT]`
  contract.

## Usage

Each skill is invoked via its own entry script / instructions in `SKILL.md`. Add `-China` (or
`--china`) to use domestic mirrors (pip / ModelScope / HF-mirror / GitCode) when GitHub/HF aren't
directly reachable.
