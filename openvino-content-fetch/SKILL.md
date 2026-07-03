---
name: openvino-content-fetch
description: |
  Fetches, parses, and indexes notebooks, sample codes, models, and articles from OpenVINO GitHub
  repository, ModelScope Intel AI PC Zone, and CSDN Intel Developer Zone. This content is used
  for student learning recommendation and training local learning-bot models.
  Call this skill when the student or learning-bot asks for notebooks, tutorials, sample codes,
  ModelScope updates, CSDN developer articles, or learning path recommendations.
  Triggers: fetch notebooks, get tutorials, find OpenVINO samples, get articles, ModelScope updates,
  CSDN posts, content fetch, recommend notebooks.
---

# OpenVINO Content Fetch — learning bot pipeline step

This skill provides the content retrieval step for the OpenVINO student learning bot. It crawls, scrapes, or reads local/remote OpenVINO resources and formats them as a clean, structured index inside a standard [SKILL_RESULT] block.

## Parameters

| Parameter | Description |
|---|---|
| -Source | github (notebooks), modelscope (AI PC zone), csdn (Intel dev zone), or ll (default) |
| -China | Switch to use local mirrors/endpoints |

`powershell
# Fetch GitHub notebooks only
run.ps1 -Source github

# Fetch everything using China mirrors
run.ps1 -Source all -China
`

## [SKILL_RESULT] (fetch contract)
`
[SKILL_RESULT]
status=ok|error
source=github|modelscope|csdn|all
count=<number of items fetched>
data=[JSON-formatted list of items]
[/SKILL_RESULT]
`
