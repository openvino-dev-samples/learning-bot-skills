# 可直接扔给 TRAE 的自动化测试 prompt

一次粘贴，让 TRAE 自动跑完 **L1 契约层 + L3 执行层**。这是「自动化」在不破坏测试有效性的前提下
能覆盖的最大范围。

**L2 路由层不在其中，也不应该放进来**：`cases.jsonl` 同一行里既有题目也有答案
（`expect_scope` / `expect_target`），一旦进入被测 agent 的上下文就成了开卷考试；而且让 agent
批量自报「我会怎么路由」并给自己打分，与它真的收到一条用户请求时的行为不是一回事。
L2 请按 [README.md](README.md) 的做法一条一条开新会话跑，再用 `grade.ps1` 判分。

---

## 使用方式

1. 用 TRAE 打开 `D:\learning-bot-skills`。
2. 确认项目规则已装载（见 [README.md](README.md) 第 1 步）。
3. 新开一个会话，把下面整段粘进去。
4. 跑完后按文末的「人工抽查」核对两件脚本判不了的事。

---

## Prompt（从下一行开始整段复制）

你在 `D:\learning-bot-skills` 仓库里执行一次自动化测试。分两个阶段，**按顺序做完，中途不要修改
任何文件**。

技能文档（阶段二要用）：
@learning-bot/SKILL.md
@openvino-environment-management/SKILL.md
@openvino-content-fetch/SKILL.md
@openvino-pipeline-optimization/SKILL.md

### 全局硬性约束

- **不许修改仓库里的任何文件**。这是测试，不是修 bug。发现问题就报告，不要顺手改。
- **不许读取 `agent-eval/cases.jsonl`**。那是答案卷，读了本次测试作废。
- **只允许执行下列零成本命令**：`-Menu`、`-Questions` / `--questions`、`-Status` / `--status`、
  `--dry-run`、`precheck_env.ps1`、以及 `test_*.ps1`。
  **严禁**：clone 仓库、`pip install`、下载模型、运行 `intel_aipc_env_setup.ps1`、
  任何带 `-Install*` / `--serve` 的调用。
- **如实报告**。命令失败就说失败，退出码非 0 就说非 0。不要把失败解释成「环境问题」或
  「可以忽略」。不要写一条你没有真正执行过的命令。

---

### 阶段一：L1 契约层

依次运行这 6 个脚本，每个都用完整形式调用：

```
powershell -NoProfile -ExecutionPolicy Bypass -File test_contracts.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File learning-bot\test_learning_bot.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File openvino-content-fetch\test_content_fetch.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File openvino-pipeline-optimization\test_pipeline.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File openvino-environment-management\test_questions.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File sandbox_run_all_test_cases.ps1
```

输出一张表：`脚本 | 退出码 | 通过数 | 失败数`。

只要有任何一个退出码非 0：把该脚本输出里所有 `FAIL` 开头的行**原样**贴出来，然后**停下来等我
指示**，不要进入阶段二，也不要尝试修复。

全部为 0 才继续。

---

### 阶段二：L3 执行层

现在你的身份是 **Learning Bot**。下面 6 个任务，每个都要**真的执行命令**，用你从 SKILL.md 里
读到的调用方式：

- **T1** 启动 Learning Bot，告诉我你能做什么。
- **T2** 列出 pipeline 技能的前置条件问题清单。
- **T3** 查一下这台机器的 OpenVINO 环境现状。
- **T4** 用 `vlm-chatbot` 这个 notebook 做一次**只解析、不下载**的流水线规划。
- **T5** 查一下 content-fetch 技能当前的状态。
- **T6** 故意用一个不存在的参数调用 pipeline 技能，看看会发生什么。

每个任务结束后按这个格式汇报，一行一个任务，不要美化：

```
T<n> | <你执行的命令原文> | status=<[SKILL_RESULT] 里的值> | <你据此得出的结论>
```

补充要求：

- `status=` 必须来自输出里真实的 `[SKILL_RESULT]` 块。没有该块就写 `status=none` 并说明。
- 出现 `status=error` 时，把 `reason=` 一并贴出来。
- 没有执行的命令写 `none`。
- **T4 特别注意**：如果输出里出现 `Cloning` 或 `Installing`，直接标记为 FAIL 并告诉我 ——
  `--dry-run` 承诺不下载。
- **T6 的预期是失败**：应当得到 `status=error`、`reason=unknown-argument`、退出码 1。
  如果它「成功」了，那才是 bug，请明确指出。

---

### 最后回答我三个问题

1. 这 6 条里，哪几条的命令你是**直接从 SKILL.md 抄下来就能跑通**的？哪几条你必须自己改写路径
   或参数？（逐条说明）
2. 有没有哪个 `[SKILL_RESULT]` 的字段你看不懂，或者文档里没解释？
3. 一句话结论：L1 通过 / 未通过，L3 通过 / 未通过。

（复制到此为止）

---

## 人工抽查（脚本判不了，必须你自己看）

跑完后核对两件事：

| 检查项 | 期望 |
|---|---|
| T1–T6 汇报里的**命令形式** | 应为 `powershell -NoProfile -ExecutionPolicy Bypass -File "<绝对路径>" <参数>`；出现 `run.ps1 -Menu` 这种简写，说明它没照文档来（或文档没写清） |
| **第 1 个问题的回答** | 这是本次测试**最有价值的产出**。凡是它答「需要自己改写路径」的条目，就是 SKILL.md 还没写到位的地方 |

另外：这一轮**必须再用一个较弱的模型重跑一遍**。强模型会自动脑补修正文档里跑不通的命令，
把问题掩盖掉 —— 弱模型档的结果才是验收依据。
