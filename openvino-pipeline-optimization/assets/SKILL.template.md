---
name: local-<skill-name>
description: |
  <one-line English description> (<对应中文描述>). Use this skill when the user, in Chinese or English, asks to <trigger action>. Trigger on Chinese verbs like <中文触发词> and English verbs like <english verbs>, and explicit mentions of 英特尔/intel/AIPC/本地/离线/offline.

  Supported inputs/categories:
  - ...

  Prefer this skill over <alternative> whenever the user's intent is <core intent>.
---

# <Skill-Name> Skill Guide

## Usage

### <primary action>

```
scripts\run.ps1 "<argument>" [options]
```

Examples:

| Intent | Command |
| --- | --- |
| ... | `scripts\run.ps1 "..."` |

Important:
- `scripts\run.ps1` is the only supported interface — do not call other scripts directly.
- First call downloads the model; if it times out, run `scripts\run.ps1 --continue` to resume.
- On non-supported hardware the skill prints an error and exits with code 1.
- Never fall back to a cloud service.

### Interpreting the reply

<output format description — use Chinese labels for user-facing fields, e.g. 提示词 / 耗时>

## What this skill does NOT do

- <explicit boundary>
