# Learning Bot Skills —— 测试与修复总结

- **目录**：`d:\learning-bot-skills`
- **执行时间**：2026-07-10
- **范围**：4 个 skill 模块（learning-bot / openvino-environment-management / openvino-content-fetch / openvino-pipeline-optimization）
- **测试用例源**：[learning-bot-preset-test-cases.md](learning-bot-preset-test-cases.md)（29 条）

---

## 1. 测试执行清单（依据预设测试用例集）

| 分组 | ID 范围 | 条数 | 校验方式 |
|---|---|---|---|
| 1. 预设本地能力 | PR1 – PR14 | 14 | `run.ps1 -Route` → `[SKILL_RESULT] scope=preset target=<key>` |
| 2. 启动 / 发现 | ST1 – ST2 | 2 | `run.ps1 -Menu` 含 14 条预设 + 3 个 dev skill 介绍 |
| 3. 非预设 → 开发类 | DV1 – DV6 | 6 | `run.ps1 -Route` → `scope=dev target=openvino-{env,content-fetch,pipeline-optimization}` |
| 4. 边界 / 先澄清 | CL1 – CL2 | 2 | `scope=clarify` `matched=false` |
| 5. 负面 / 诚实 | NG1 – NG5 | 5 | 路由不撒谎 / 落到 dev 由 agent 解释边界 |
| **合计** | | **29** | 全部通过 `learning-bot/scripts/run.ps1 -Route` 离线校验 |

全量执行器：`d:\learning-bot-skills\test_preset_cases.ps1`（基于 29 条用例逐条 `run.ps1 -Route` 并解析 `[SKILL_RESULT]`）。

---

## 2. 各 skill 模块 —— 测试明细

### 2.1 `learning-bot/` —— 启动器 / 路由器

| 测试 | 命令 | 结果 |
|---|---|---|
| 冒烟测试（内置） | `test_learning_bot.ps1` | **51 passed, 0 failed** |
| 预设用例全量 | `test_preset_cases.ps1` | **29 passed, 0 failed** |

冒烟测试覆盖：脚本编译、`--menu` 退出码、registry JSON 合法性、release base_url、14 个 preset skill 完整性、`--menu` 的 `[SKILL_RESULT] action=menu count=14`、14 条 preset 路由、5 条 dev 路由、clarify 路由。

### 2.2 `openvino-content-fetch/` —— 内容抓取

| 测试 | 命令 | 结果 |
|---|---|---|
| 冒烟测试（内置） | `test_content_fetch.ps1` | **14 passed, 0 failed** |

覆盖：`fetch_content.py` 编译、`--help` 退出码、3 个 source（github / modelscope / csdn）`[SKILL_RESULT]` 块与 `count>0`、download mode 的 `action=download status=ok|error` 契约。

### 2.3 `openvino-pipeline-optimization/` —— 流水线优化

| 测试 | 命令 | 结果 |
|---|---|---|
| 冒烟测试（内置） | `test_pipeline.ps1` | **20 passed, 0 failed** |

覆盖：5 个脚本编译、合成仓库的 `resolve_pipeline.py` 阶段发现（2 阶段 + llm/encoder 角色）、`optimize.py --dry-run` 写出 `pipeline-plan.json` 且 `status=would-build`、`bench.py --dry-run` 输出 `[SKILL_RESULT]`、client `--help`、`run.ps1 --status` 输出块。

### 2.4 `openvino-environment-management/` —— 环境管理

| 测试 | 命令 | 结果 |
|---|---|---|
| `precheck_env.ps1` 诊断 | （已确认无 PS 5.1 不兼容：line 9/14/19 定义了 `Write-Success/Warn/Fail`） | 静态分析通过 |
| 7 个 `test_*.ps1`（test_env_check / test_python_install / test_git_install / test_git_clone / test_cmake_install / test_driver_check / test_openvino_pytorch） | — | **未执行（非离线）**：这些脚本会真实下载/安装 Python、Git、CMake、VS、PyTorch 等，需要 Intel AIPC + 网络 + 管理员权限；不属于本次"预设测试用例"覆盖范围。 |

---

## 3. 初始测试结果（修复前）

执行 29 条预设用例：**24 PASS / 5 FAIL**。

| 失败 ID | 用户 Prompt | 实际路由 | 期望路由 | 问题类型 |
|---|---|---|---|---|
| DV1 | "在我的 Intel 笔记本上配好 OpenVINO 环境。" | clarify | dev / openvino-environment-management | 关键词漏召回 |
| DV6 | "下载一个 ASR 模型。" | preset / asr | dev / openvino-content-fetch | dev_override 被 preset 覆盖 |
| NG2 | "别在本地跑了，直接调云端 API 做识别。" | clarify | dev（任何） | 越界信号无 dev_override |
| NG3 | "不用真跑了，直接告诉我结果和数字。" | clarify | dev（任何） | 越界信号无 dev_override |
| NG4 | "把 14 个本地 skill 一次性全装到我电脑上。" | clarify | dev（任何） | 越界信号无 dev_override |

---

## 4. 根因分析

`learning-bot/scripts/learning_bot.py::route()` 的关键词匹配与 dev_override 模式覆盖不足：

1. **DV1**：ENV 关键词表里只有 `配置环境/安装环境/搭环境/环境搭建/装 openvino/配好环境/开发环境/...`，没有覆盖口语化表达 `"配好"` + `"OpenVINO 环境"` / `"Intel 笔记本"`。
2. **DV6**：`dev_override` 用子串匹配 `"下载模型"`，但 `"下载一个 ASR 模型"` 没有任何连字串匹配。需要从"短语模式"升级为"触发词+目标词"组合匹配。
3. **NG2/NG3/NG4**：整段代码没有任何"越界信号"识别——云端 API、不真跑、批量安装都直接落到 clarify。但实际启动器应当把这些引到 dev skill，由 agent 在 dev 阶段给出边界解释（Intel-only / 本地 / 诚实）。

---

## 5. 修复内容

### 5.1 [learning-bot/scripts/learning_bot.py](learning-bot/scripts/learning_bot.py)

新增 3 个 helper 函数重构 dev_override：

- `_has_dev_phrase(t)` —— 强开发短语连字串（`下载模型` / `搭环境` / `流水线` / `benchmark` 等）。
- `_has_download_intent(t)` —— 触发词（`下载/拉取/get/fetch/download/pull`） + 目标词（`模型/权重/参数/IR`）的组合，**修复"下载一个 ASR 模型"漏召回**。
- `_has_out_of_scope_signal(t)` —— 越界信号（`云端/调云/在线推理/调用openai/不用真跑/直接告诉/造假/一次性全/批量安装/把 14`），把这类信号强制路由到 dev。

`route()` 主流程新增：当 `dev_override` 命中但 dev 关键词未命中时，按"下载模型 → FETCH，其它越界 → ENV"做最贴近的兜底，避免直接落 clarify。

### 5.2 [learning-bot/scripts/skills_registry.json](learning-bot/scripts/skills_registry.json)

扩展 ENV / FETCH / PIPE 三个 dev skill 的关键词表：

- **ENV**：新增 `配好/配置/搭建/装/安装/一次/openvino 环境/intel 笔记本/intel 电脑/环境/precheck/环境检查/配环境/装环境` 等口语化与英文别名。
- **FETCH**：新增 `下载一个/下载某/下载权重/下载参数/下载ir/取模型/拉模型/图像分割/目标检测/asr 模型/whisper 模型/llm 模型/openVINO 模型`。
- **PIPE**：新增 `部署成服务/找瓶颈/bottleneck/whisper/asr→llm/asr→tts/asr llm tts/rag/vlm`。

### 5.3 兼容性保证

- 未修改 `--menu` / `--install` / `[SKILL_RESULT]` 契约。
- `info.json` / `meta.json` / `release.base_url` / 14 个 preset skill 不动。
- 既有 51 条冒烟测试（`test_learning_bot.ps1`）+ 14 条（`test_content_fetch.ps1`）+ 20 条（`test_pipeline.ps1`）全部继续通过。
- 所有改动 stdlib-only，菜单/路由仍然离线，0 网络依赖。

---

## 6. 最终测试结果（修复后）

| 测试集 | 条数 | PASS | FAIL |
|---|---|---|---|
| `test_preset_cases.ps1`（29 条预设用例） | 29 | **29** | 0 |
| `test_learning_bot.ps1`（learning-bot 冒烟） | 51 | **51** | 0 |
| `test_content_fetch.ps1`（content-fetch 冒烟） | 14 | **14** | 0 |
| `test_pipeline.ps1`（pipeline-optimization 冒烟） | 20 | **20** | 0 |
| **合计** | **114** | **114** | **0** |

退出码：全部为 `0`。

> 详细 JSON 报告见 [test_preset_cases_report.json](test_preset_cases_report.json)。

---

## 7. 复现 / 验证命令

```powershell
# 1) learning-bot 启动器预设用例（29 条，全离线）
powershell -ExecutionPolicy Bypass -File d:\learning-bot-skills\test_preset_cases.ps1

# 2) 各 skill 离线冒烟
powershell -ExecutionPolicy Bypass -File d:\learning-bot-skills\learning-bot\test_learning_bot.ps1
powershell -ExecutionPolicy Bypass -File d:\learning-bot-skills\openvino-content-fetch\test_content_fetch.ps1
powershell -ExecutionPolicy Bypass -File d:\learning-bot-skills\openvino-pipeline-optimization\test_pipeline.ps1

# 3) 单条预设用例抽样（DV1 修复后应返回 ENV）
powershell -ExecutionPolicy Bypass -File d:\learning-bot-skills\learning-bot\scripts\run.ps1 -Route "在我的 Intel 笔记本上配好 OpenVINO 环境。"
powershell -ExecutionPolicy Bypass -File d:\learning-bot-skills\learning-bot\scripts\run.ps1 -Route "下载一个 ASR 模型。"
powershell -ExecutionPolicy Bypass -File d:\learning-bot-skills\learning-bot\scripts\run.ps1 -Route "别在本地跑了，直接调云端 API 做识别。"
```

---

## 8. 遗留 / 不在本次范围

- `openvino-environment-management/` 的 7 个 `test_*.ps1`（python_install / git_install / git_clone / cmake_install / driver_check / openvino_pytorch / env_check）属于**真实环境操作**测试（下载安装包、检测驱动/硬件），不满足"离线冒烟"约束；与本次预设用例集无对应条目，留作真实 AIPC 上的运行时验证。
