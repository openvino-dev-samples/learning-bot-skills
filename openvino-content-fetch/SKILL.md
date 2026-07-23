---
name: openvino-content-fetch
description: |
  从 OpenVINO GitHub 仓库、ModelScope Intel AI PC Zone 和 CSDN Intel 开发者专区抓取、解析并索引
  notebook、示例代码、模型和文章 —— 同时从 ModelScope（Model Repo + Intel AI PC Zone）和 Intel
  OpenVINO Model Hub 定位/下载模型及预转换的 OpenVINO IR，用于在 Intel AIPC 上进行本地推理。
  当学习者或 learning-bot 需要 notebook、教程、示例代码、ModelScope 更新、CSDN 开发者文章、学习
  路径推荐，或者需要查找 / 解析 / 下载模型或预转换 IR 用于本地 OpenVINO 推理时，调用本技能。
  触发词：fetch notebooks、get tutorials、find OpenVINO samples、get articles、ModelScope updates、
  CSDN posts、content fetch、recommend notebooks、download model、get IR、resolve model、
  find OpenVINO-optimized model。
---

# OpenVINO Content Fetch —— learning bot 流水线步骤

本技能同时负责 learning bot 的**内容**和**模型文件**两部分：

1. **内容** —— 来自 OpenVINO GitHub 仓库、ModelScope AI PC Zone 和 CSDN Intel 开发者专区的
   notebook、教程、示例代码和文章。它会爬取/读取这些资源，并在标准的 `[SKILL_RESULT]` 块中返回
   干净、结构化的索引。GitHub notebook 列表**实时从 `latest` 分支拉取**（GitHub API），因此推荐
   始终反映当前的 notebook；内置的种子列表仅在离线/失败时作为回退使用。
2. **模型文件 / IR** —— 它从 ModelScope（Model Repo + Intel AI PC Zone）和 Intel OpenVINO Model
   Hub 定位并下载模型及**预转换的 OpenVINO IR**。它会解析 model id，优先选择已有的 OpenVINO IR，
   在大文件下载前报告大小/许可证，并把文件下载到本地目录，用于在 Intel AIPC 上进行本地 OpenVINO 推理。

## 参数

| 参数 | 说明 |
|---|---|
| -Source | github（notebook）、modelscope（AI PC zone）、csdn（Intel 开发者专区），或 all（默认） |
| -Download | 要下载的 model id（例如 `Qwen2.5-7B-Instruct-INT4-OV`）；触发下载模式 |
| -OutDir | 模型 / IR 下载到的本地目录（默认为 `~/.openvino/models`） |
| -Questions | 输出准备好的问题：`preset` / `preflight` / `clarify` / `all`（`[SKILL_QUESTIONS]` 契约，离线） |
| -China | 切换为使用国内镜像/端点 |

```powershell
# 仅抓取 GitHub notebook
run.ps1 -Source github

# 使用国内镜像抓取全部内容
run.ps1 -Source all -China

# 从 ModelScope 下载预转换的 OpenVINO IR 模型
run.ps1 -Download "Qwen2.5-7B-Instruct-INT4-OV" -OutDir "D:\models\qwen2.5-7b"
```

## 准备好的问题（Prepared Questions）

在抓取/下载前，本技能可以先给用户**一组准备好的问题**（离线、无需 venv/网络）：

```powershell
run.ps1 -Questions preset      # 推荐问题："你可以让我帮你找内容 / 找模型"
run.ps1 -Questions preflight   # 前置条件多选（能否直连、找内容还是下模型、磁盘空间）
run.ps1 -Questions clarify     # 澄清追问（内容 vs 模型、source、-China）
run.ps1 -Questions all         # 以上全部（默认）
```

### `[SKILL_QUESTIONS]` 契约
```
[SKILL_QUESTIONS]
skill=openvino-content-fetch
type=preset|preflight|clarify|all
count=<问题块数>
data=<紧凑 JSON 数组；每个块 {type,id,prompt,multiselect,options:[{key,label,example?,exclusive?,on_missing?}]}>
[/SKILL_QUESTIONS]
```

**agent 约定：** 需求含糊时先走 `-Questions clarify` 收敛意图；对 `preflight` 里**没勾**的项按 `on_missing`
调整（如 `self:-China` 表示改用国内镜像）。问题清单在 [scripts/questions.json](scripts/questions.json)，由共享的
[scripts/questions.ps1](scripts/questions.ps1) 输出。

## 内容抓取 —— [SKILL_RESULT]（抓取契约）

```
[SKILL_RESULT]
status=ok|error
source=github|modelscope|csdn|all
count=<抓取到的条目数>
data=[JSON 格式的条目列表]
[/SKILL_RESULT]
```

## 模型下载

### 在哪里找模型

1. **ModelScope —— OpenVINO 组织（优先选预转换 IR）**
   - **URL：** https://www.modelscope.cn/organization/OpenVINO
   - OpenVINO 优化过的模型，很多已导出为 IR。优先选这些 —— 无需转换。
2. **ModelScope —— Intel AI PC Zone 模型列表**
   - **URL：** https://modelscope.cn/brand/view/AI_PC?branch=2&tree=1
   - 面向 Intel AI PC 精选的模型；下载源模型前先检查是否有 IR / OpenVINO 变体。
3. **Intel OpenVINO Model Hub**
   - **URL：** https://www.intel.com/content/www/us/en/developer/tools/openvino-toolkit/model-hub.html
   - 针对 Intel 硬件优化的模型的回退来源（页面结构与 ModelScope 不同）。

### 下载流程

1. **解析** model id（来自用户，或通过 `-Source modelscope` 在上述来源中搜索）。优先选择已经附带
   OpenVINO IR（`openvino_model.xml/.bin`）的变体；如果只有源模型，标注需要转换（通过
   `openvino-pipeline-optimization`）。
2. **下载前先报告：** model id、大小、许可证以及是否有 IR —— 在拉取数 GB 资产前先确认。
3. **下载**到本地目录，使用 ModelScope SDK：
   ```python
   from modelscope import snapshot_download
   local_dir = snapshot_download("OpenVINO/<model-id>")   # 例如某个 OpenVINO 优化过的仓库
   ```
   ModelScope 是国内源（在中国默认较快）。设置 `local_dir=` 为持久化路径，这样重试时不会重复下载。
4. **报告结果：** 本地路径 + 包含哪些文件（IR vs 源模型），以便 pipeline / env 技能后续使用。

### 模型下载 —— [SKILL_RESULT]（下载契约）

```
[SKILL_RESULT]
status=ok|error
action=download
model_id=<解析出的 model id>
local_dir=<绝对本地路径>
has_ir=true|false
[/SKILL_RESULT]
```

## API 参考（ModelScope）

在 ModelScope 上以编程方式查找 / 下载模型：

**Base URL：** https://modelscope.cn/openapi/v1  ·  **鉴权：** Bearer Token

- `GET /models` —— 列出 / 搜索模型（按 task、关键词过滤）
- `GET /models/{owner}/{repo_name}` —— 模型详情（文件、大小、许可证）

**OpenAPI 文档：** https://modelscope.cn/docs/openapi

## 测试
运行离线冒烟测试（仅使用标准库路径 + 内置种子回退；无需 venv、bs4 或网络）来验证抓取和下载契约：
```powershell
powershell -ExecutionPolicy Bypass -File test_content_fetch.ps1
```
退出码 `0` = 所有检查通过。它会断言每个 source 都有格式良好的 `[SKILL_RESULT]`（status/count），
以及 `action=download` 契约。
