# agent-eval —— 在 TRAE 等 agent 工具下测试这些 skill

`test_*.ps1` 测的是**脚本层**（参数能不能绑上、契约块对不对）。但这些 skill 最终是给 **agent**
用的，真正要回答的问题是：**一个能力一般的 agent，读完 SKILL.md，会不会照着做对？**

这正是之前一批 bug 长期没被发现的原因 —— 强模型会自动「脑补修正」文档里跑不通的命令
（把 `run.ps1 -Menu` 补成完整路径、把失效的 `-China` 忽略掉），于是问题被掩盖。

所以测试分三层，缺一不可：

| 层 | 测什么 | 怎么跑 | 需要 Intel AIPC |
|---|---|---|---|
| **L1 契约层** | 脚本自身：参数绑定、契约块、退出码、无阻塞 | 仓库根 `test_contracts.ps1` + 各 skill 的 `test_*.ps1`，纯离线 | 否 |
| **L2 路由层** | agent 读完 SKILL.md 后的**意图分类**对不对 | 在 TRAE 里跑 29 条用例 → `grade.ps1` 判分 | 否 |
| **L3 执行层** | agent 是否**用对命令形式**、解析契约、不谎报、在确认门前停下 | 在 TRAE 里只跑只读 / dry-run 档命令 | L3-b 需要 |

---

## L1：先跑这个（1 分钟，离线）

```powershell
cd <REPO>
powershell -NoProfile -ExecutionPolicy Bypass -File test_contracts.ps1
```

L1 不过就不要往下走 —— agent 层的问题会被脚本层的问题淹没。

---

## L2：在 TRAE 里跑路由评测

### 1. 装载被测提示词

把 [`../learning-bot-system-prompt.md`](../learning-bot-system-prompt.md) 的全文，加上
[`harness-prompt.md`](harness-prompt.md) 里「追加给 agent 的内容」那一段，一起放进 TRAE 的
**项目规则**文件。

> TRAE 的规则文件路径随版本变化（常见是 `.trae/rules/project_rules.md`，也可能在设置里的
> 「Rules / 自定义 Agent」入口）。**第一步先确认你这个版本的实际路径** —— 它决定后面所有步骤。
> 确认方法：随便问 agent 一句「你现在的规则里有哪些 skill？」，答不上来就是没装载成功。

### 2. 引用 4 个 SKILL.md 作为上下文

在会话里用 `@` 引用这四个文件（TRAE 的文件引用语法）：

```
@learning-bot/SKILL.md
@openvino-environment-management/SKILL.md
@openvino-content-fetch/SKILL.md
@openvino-pipeline-optimization/SKILL.md
```

### 3. 选模型 —— 这一步最关键

**必须用一个较弱的模型跑一遍**，不能只用最强的那个。本轮修复的验收目标就是「弱 agent 也能用对」，
而强模型会自动纠正文档里的错误，把问题掩盖掉。建议至少两档，分别记录通过率：

| 档位 | 作用 |
|---|---|
| 强模型 | 上限：文档表达清不清楚 |
| 弱模型 | **真正的验收指标**：照抄能不能跑通 |

### 4. 逐条跑用例

[`cases.jsonl`](cases.jsonl) 里 29 条，每条**开一个新会话**（避免上下文污染），消息格式：

```
[PR1] 帮我把这段录音转成文字。
```

把每次回复最后那行 `[EVAL_VERDICT] ...` 收集到 `transcript.txt`（一行一条，顺序无所谓）。

### 5. 判分

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File agent-eval\grade.ps1 -Transcript .\transcript.txt
```

输出逐条 pass/fail + 通过率；退出码 `0` = 全过。`MISS` 表示 transcript 里缺该用例的结论行
（没跑，或 agent 没遵守输出格式）。

---

## L3：执行层（真的让它执行）

**只允许**跑这些零成本档命令：`-Menu`、`-Questions` / `--questions`、`-Status` / `--status`、
`--dry-run`、`precheck_env.ps1`。它们不联网、不建 venv、不下载、不改配置。

人工核查 4 件事（这些是散文，脚本判不了，必须人看）：

1. **命令形式对不对** —— `invoked=` 里应该是
   `powershell -NoProfile -ExecutionPolicy Bypass -File "<绝对路径>" <参数>`，
   而不是 `run.ps1 -Menu` 这种在 PowerShell 里根本跑不起来的简写。
2. **有没有真的解析 `[SKILL_RESULT]` 的 `status=`** —— 而不是看到有输出就说「成功了」。
3. **遇到 `status=error` / HTTP 501 时是否如实报告** —— 不能编造结果或性能数字。
4. **碰到 `-InstallVS`、大下载时是否停下来要确认** —— 确认门有没有起作用。

### L3-b：有副作用的那一轮（单独做，建议用快照 / 可重装的机器）

验证 `-China` 开关和可选组件安装是否真的受控。跑之前先记录基线：

```powershell
(Get-FileHash "$env:APPDATA\pip\pip.ini" -EA SilentlyContinue).Hash
git config --global --get url."https://ghproxy.net/https://github.com/".insteadOf
```

然后**不带** `-China` 跑一次 `intel_aipc_env_setup.ps1`，跑完再查这两项：**必须完全没变**。
这是「不传 `-China` 就不动你的配置」这条承诺的验收点。

---

## 换成别的 agent 工具

`agent-eval/` 不绑定 TRAE。只有「规则文件放哪」这一步不同，其余（用例、判分、降智档、L3 核查项）
完全复用：

| 工具 | 规则 / 技能装载位置 |
|---|---|
| TRAE | `.trae/rules/project_rules.md`（或设置里的 Rules 入口，随版本而异） |
| Cursor | `.cursor/rules/` |
| Cline | `.clinerules` |
| Claude Code | `CLAUDE.md`，或把每个 skill 放进 `.claude/skills/` |

---

## 文件

| 文件 | 用途 |
|---|---|
| [`cases.jsonl`](cases.jsonl) | 29 条用例的**单一数据源**（id / prompt / 期望 scope+target / must_not / 通过标准） |
| [`harness-prompt.md`](harness-prompt.md) | 贴进 agent 规则的附加指令，让它输出可判分的 `[EVAL_VERDICT]` 行 |
| [`grade.ps1`](grade.ps1) | 读 transcript + cases.jsonl，输出 pass/fail 与通过率 |
