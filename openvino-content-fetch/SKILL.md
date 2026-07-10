---
name: openvino-content-fetch
description: |
  从 OpenVINO Notebooks 导航索引与 GitHub、ModelScope Intel AI PC Zone 和 CSDN Intel 开发者专区
  搜索、抓取、解析并索引 notebook、示例代码、模型和文章。同时从 ModelScope 和 Intel OpenVINO
  Model Hub 定位或下载模型及预转换的 OpenVINO IR，用于本地推理。当学习者需要按 AI Task 或
  Category 查找 notebook（包括文生图示例）、教程、示例代码、学习路径、文章、模型或 IR 时使用。
---

# OpenVINO 内容抓取

本技能同时负责 learning bot 的内容发现与模型文件获取。

## 搜索学习内容

搜索 `github` notebook 时，按以下顺序选择数据源：

1. 读取官方 [OpenVINO Notebooks 导航索引](https://openvinotoolkit.github.io/openvino_notebooks/)，
   获取当前 notebook 的标题、Categories、AI Tasks、Libraries 和 GitHub 链接。
2. 导航索引不可用时，回退到 `latest` 分支的实时目录列表。
3. GitHub API 不可用时，回退到本地已有的 `openvino_notebooks` 仓库。
4. 本地仓库也不可用时，使用内置的离线种子列表。

不要抓取导航页渲染后的 DOM。应读取其结构化数据文件 `notebooks-metadata-map.json`。先使用官方
标签筛选候选 notebook，再按需抓取 notebook 正文。导航结果包含 `categories`、`tasks`、
`libraries`、`url` 和 `raw_url`；只有下游确实需要 notebook 完整内容时才读取 `raw_url`。

### 参数

| 参数 | 说明 |
|---|---|
| `-Source` | `github`、`modelscope`、`csdn` 或 `all`（默认） |
| `-Query` | notebook 自由文本搜索；支持将“文生图”等常用中文表达映射为官方任务标签 |
| `-Task` | 导航页中的精确 AI Task，例如 `Text-to-Image` |
| `-Category` | 导航页中的精确 Category，例如 `Model Demos` 或 `Optimize` |
| `-Limit` | 最多返回的 notebook 数量 |
| `-Download` | 要下载的模型 ID；设置后进入下载模式 |
| `-OutDir` | 模型或 IR 下载目录；默认为 `~/.openvino/models` |
| `-China` | 在支持时使用国内镜像或端点 |

```powershell
# 获取带有官方导航元数据的当前 notebook 列表
run.ps1 -Source github

# 使用官方 AI Task 查找文生图示例
run.ps1 -Source github -Task "Text-to-Image" -Limit 10

# 学习者可直接使用中文表达
run.ps1 -Source github -Query "文生图"

# 组合自由文本与官方标签进行筛选
run.ps1 -Source github -Query "stable diffusion" -Task "Text-to-Image" -Category "Model Demos"

# 使用国内友好的端点抓取全部内容源
run.ps1 -Source all -China
```

### 内容抓取契约

```text
[SKILL_RESULT]
status=ok|error
source=github|modelscope|csdn|all
count=<匹配到的条目数>
data=[按数据源组织的 JSON 格式结果]
[/SKILL_RESULT]
```

筛选结果为空属于一次成功的搜索，返回 `count=0`，不应视为抓取错误。在
`data.sources.github.filters` 中保留实际使用的筛选条件，方便下游解释结果。

## 定位并下载模型

按以下优先级使用模型来源：

1. ModelScope OpenVINO 组织：`https://www.modelscope.cn/organization/OpenVINO`
2. ModelScope Intel AI PC Zone：`https://modelscope.cn/brand/view/AI_PC?branch=2&tree=1`
3. Intel OpenVINO Model Hub：`https://www.intel.com/content/www/us/en/developer/tools/openvino-toolkit/model-hub.html`

优先选择已经包含 OpenVINO IR（`openvino_model.xml` 和 `.bin`）的模型。如果只有源权重，报告需要
使用 `openvino-pipeline-optimization` 进行转换。下载数 GB 的模型前，先报告模型 ID、大小、
许可证和 IR 可用性，并获得确认。

```powershell
run.ps1 -Download "Qwen2.5-7B-Instruct-INT4-OV" -OutDir "D:\models\qwen2.5-7b"
```

### 模型下载契约

```text
[SKILL_RESULT]
status=ok|error
action=download
model_id=<解析出的模型 ID>
local_dir=<本地绝对路径>
has_ir=true|false
[/SKILL_RESULT]
```

## 测试

运行离线冒烟测试和单元测试：

```powershell
powershell -ExecutionPolicy Bypass -File test_content_fetch.ps1
```

退出码 `0` 表示全部检查通过。
