---
name: learning-bot
description: |
  Learning Bot 的入口 / 启动 skill。调用本技能即可"开启 Learning Bot"：它会把一组**预设问题**推荐
  给用户，每条预设问题对应一个在 Intel AIPC 上本地运行的 aipc-skill（ASR、TTS、实时翻译、OCR(NPU/GPU)、
  MinerU 文档解析、文生图、图生图、文生视频、超分、YOLO26 目标检测、截图问答、电脑自动化、显存查看）。
  当用户问到这些预设问题时，本技能负责下载并调用对应的本地 skill；当用户的需求**超出**这些预设本地
  能力时，本技能会根据实际需求改为路由到三个开发类 skill：openvino-environment-management（配环境）、
  openvino-content-fetch（找 notebook / 下载模型）、openvino-pipeline-optimization（组装 / 优化 / 部署
  流水线）。
  当用户想启动 / 打开 learning bot、想知道"你能做什么 / 有哪些功能"、或提出上述任一本地推理需求时调用
  本技能。触发词：start learning bot、open learning bot、启动 / 开启 learning bot、你能做什么、
  有哪些功能、推荐一些能力、语音转文字、文字转语音、实时翻译、OCR、识别文字、解析 PDF、文生图、
  图生图、文生视频、超分、目标检测、截图问答、电脑自动化、查看显存。
  需要 Intel AIPC (Windows)。
---

# Learning Bot —— 入口 / 启动 skill

本技能是 Learning Bot 的**入口**。调用它 = "开启 Learning Bot"：向用户推荐一组预设问题，并根据用户
的问题把请求路由到正确的下游 skill。它自己不做推理，而是负责**推荐 + 路由 + 安装**：

1. **推荐（Menu）** —— 被调用时，把下面 14 条预设问题推荐给用户。每条预设问题都对应一个在本机
   （Intel AIPC）离线运行的 aipc-skill。
2. **路由（Route）** —— 判断用户的话属于哪一类：
   - **命中预设** → 下载并调用对应的本地 aipc-skill。
   - **超出预设范围** → 根据实际需求路由到三个开发类 skill（ENV / FETCH / PIPE）。
   - **无法归类** → 先向用户追问（任务 / 模态 / 目标），不做静默假设。
3. **安装（Install）** —— 从 aipc-skills 的 1.0.6 release 下载并解压所选 skill 的 zip 到本地。

> 路由脚本给出的是**建议**，不是硬性判决。最终由 agent 结合上下文决定调用哪个 skill。

---

## 预设问题（推荐给用户 · 14 个本地能力）

调用本技能时，把这些问题原样推荐给用户（"你可以直接问我下面这些……"）。用户问到其中任意一条，就
下载 + 调用对应 skill。

| # | 预设问题（推荐话术） | 本地 skill | key |
|---|---|---|---|
| 1 | "帮我把这段录音/语音转成文字。" | 本地语音识别 (ASR) | `asr` |
| 2 | "把这段文字读出来，生成一段语音。" | 本地语音合成 (TTS) | `tts` |
| 3 | "帮我实时翻译这段对话/语音。" | 本地实时翻译 | `realtime-translator` |
| 4 | "用 NPU 识别这张图片里的文字。" | 本地 OCR (NPU) | `ocr-npu` |
| 5 | "用 GPU 识别这张图/文档里的文字。" | 本地 OCR (GPU) | `ocr-gpu` |
| 6 | "帮我解析这个 PDF，转成 Markdown / 结构化文本。" | 本地文档解析 (MinerU) | `mineru` |
| 7 | "根据这段描述生成一张图片。" | 本地文生图 (Text-to-Image) | `txt2img` |
| 8 | "把这张图改成某种风格 / 基于这张图生成新图。" | 本地图生图 (Image-to-Image) | `img2img` |
| 9 | "根据这段描述生成一段视频。" | 本地文生视频 (Text-to-Video) | `txt2video` |
| 10 | "把这张模糊/低清的图片变清晰、放大。" | 本地超分辨率 (Super-Resolution) | `sr` |
| 11 | "帮我检测这张图片里有哪些物体。" | 本地目标检测 (YOLO26) | `yolo26` |
| 12 | "帮我截个屏，然后回答关于屏幕内容的问题。" | 本地截图问答 | `screenshot-qa` |
| 13 | "帮我自动操作电脑完成某个任务。" | 本地电脑自动化 (Computer Use) | `computer-use` |
| 14 | "看看我现在的显存 / VRAM 占用情况。" | 本地显存查看 (VRAM) | `vram` |

> OCR 同时提供 NPU 与 GPU 两个变体：用户明确说 "GPU" 就用 `ocr-gpu`，否则默认 `ocr-npu`。

这 14 个 skill 的下载地址（zip 文件名 + release）由 [`scripts/skills_registry.json`](scripts/skills_registry.json)
统一维护，release 基址为
`https://github.com/makejiang/aipc-skills/releases/download/1.0.6/`。

---

## 超出预设范围 → 路由到开发类 skill

当用户的需求不是上面 14 个"开箱即用的本地能力"，而是**开发 / 构建**类需求时，改为路由到本仓库的三个
开发类 skill（见 [../README.md](../README.md)）：

| skill | 何时用 |
|---|---|
| [`openvino-environment-management`](../openvino-environment-management/) (ENV) | 需要在 Intel AIPC 上搭建 / 配置 OpenVINO 开发环境 |
| [`openvino-content-fetch`](../openvino-content-fetch/) (FETCH) | 找 notebook / 教程 / 示例 / 文章，或搜索 / 下载模型与预转换 IR |
| [`openvino-pipeline-optimization`](../openvino-pipeline-optimization/) (PIPE) | 把多个模型组装成流水线、优化设备/精度、做基准测试或部署为服务 |

判断优先级：**预设本地能力 → 开发类 skill → 追问澄清**。但当用户带有明确的开发意图词
（"下载模型 / 找模型 / 部署 / 流水线 / benchmark / 搭环境 / notebook / 教程 / 学习路径"）时，
即使句子里出现了某个模态词，也优先走开发类 skill（例如 "下载 ASR 模型" 是 FETCH 的活，不是 `asr`）。

---

## 参数

| 参数 | 说明 |
|---|---|
| -Menu | 打印推荐给用户的预设问题（默认动作 = 启动 Learning Bot） |
| -Route "\<text\>" | 对一句用户输入给出路由建议（preset / dev / clarify） |
| -Install \<key\> | 下载并解压对应的 aipc-skill（key 见上表） |
| -OutDir | -Install 的目标目录（默认 `~/.aipc-skills`） |

```powershell
# 启动 Learning Bot：推荐预设问题
run.ps1 -Menu

# 对用户输入做路由（返回 preset / dev / clarify 建议）
run.ps1 -Route "帮我把这段录音转成文字"

# 安装某个预设本地 skill
run.ps1 -Install asr
```

---

## [SKILL_RESULT] 契约

### 推荐（menu）

```
[SKILL_RESULT]
status=ok
action=menu
count=14
data=[{"key":..,"name":..,"question":..}, ...]
[/SKILL_RESULT]
```

### 路由（route）

```
[SKILL_RESULT]
status=ok
action=route
matched=true|false
scope=preset|dev|clarify
target=<skill key 或 ENV/FETCH/PIPE 的 skill 名；clarify 时为空>
reason=<归类理由>
[/SKILL_RESULT]
```

### 安装（install）

```
[SKILL_RESULT]
status=ok|error
action=install
skill=<key>
url=<下载地址>
install_dir=<解压到的本地路径>
[/SKILL_RESULT]
```

安装失败时（无网络 / 下载不到）返回 `status=error`，并把 `url` 和 `install_dir` 一并给出，方便用户
手动下载 zip 后解压 —— **绝不伪造成功**。

---

## agent 使用约定

- 被调用时先输出预设问题清单（`-Menu`），让用户知道能问什么。
- 拿到用户具体请求后用 `-Route` 得到建议，再据此决定：`preset` → `-Install <key>` 并调用该 skill；
  `dev` → 转交对应开发类 skill；`clarify` → 先追问。
- 解析每个 `[SKILL_RESULT]` 的 `status`；安装/调用失败不要谎报成功。
- 仅限 Intel AIPC (Windows)、本地离线运行；非 Intel 硬件或云端推理请求要明确拒绝。

## 测试
运行离线冒烟测试（stdlib-only，menu/route 不联网；不校验真实下载）：
```powershell
powershell -ExecutionPolicy Bypass -File test_learning_bot.ps1
```
退出码 `0` = 所有检查通过。它会校验 registry（14 个预设 skill + release 地址）、menu / route 的
`[SKILL_RESULT]` 契约，以及预设 vs. 非预设输入的路由建议是否符合预期。
