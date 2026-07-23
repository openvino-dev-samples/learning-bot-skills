---
name: "openvino-environment-management"
description: "Intel AIPC 开发环境在 Windows 上的两阶段配置。阶段1：运行 precheck_env.ps1 (PC1-PC10) 评估当前状态。阶段2：运行 intel_aipc_env_setup.ps1 (ST1-ST9) 安装缺失组件。预检查验证：操作系统、Intel CPU、驱动、Python、pip 镜像、Git、Git 镜像、HF/ModelScope、OpenVINO、PyTorch。使用 -China 参数启用国内镜像。CMake (ST8) 和 VS (ST9) 为可选组件。"
---

# Intel AIPC 环境管理

## 智能体使用指南

本技能专为**AI 智能体**设计，用于在 Windows 上配置 Intel AIPC 开发环境。请遵循以下两阶段工作流程：

### 阶段1：预检查（诊断）
首先运行独立的预检查脚本评估当前环境状态。这有助于确定需要安装或配置的组件。

```powershell
powershell -ExecutionPolicy Bypass -File precheck_env.ps1
```

脚本会在 `[AGENT_OUTPUT]` 和 `[/AGENT_OUTPUT]` 标签之间输出 JSON 摘要，便于程序化解析。

### 阶段2：配置（安装/配置）
根据预检查结果，运行配置脚本安装缺失组件。

```powershell
# 基础配置（不使用镜像）
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1

# 使用国内镜像（中国大陆）
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -China

# 包含可选组件
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -InstallCmake
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -InstallVS
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -FullInstall
```

## 脚本参数

| 参数 | 说明 | 默认值 |
|-----------|-------------|---------|
| `-InstallCmake` | 安装 CMake | `$false` |
| `-InstallVS` | 安装 Visual Studio Community 版本 | `$false` |
| `-FullInstall` | 安装所有组件（包括可选组件） | `$false` |
| `-China` | 使用国内镜像（清华 pip 镜像 + ghproxy.net 用于 github.com） | `$false` |

## 准备好的问题（Prepared Questions）

在配置前，本技能可以先给用户**一组准备好的问题**（离线、无需网络）：让用户勾选「已具备哪些前提」，
再据此只安装缺失部分。三类问题以统一的 `[SKILL_QUESTIONS]` 契约输出：

```powershell
# 本技能的脚本在技能根目录（无 run.ps1），直接调用 questions.ps1：
powershell -ExecutionPolicy Bypass -File questions.ps1 -Type preset      # 推荐能做的事
powershell -ExecutionPolicy Bypass -File questions.ps1 -Type preflight   # 前置条件多选（OS/Intel CPU/Python/Git/OpenVINO+PyTorch 是否就绪）
powershell -ExecutionPolicy Bypass -File questions.ps1 -Type clarify      # 澄清（-China？装 CMake/VS？）
powershell -ExecutionPolicy Bypass -File questions.ps1 -Type all          # 全部（默认）
```

### `[SKILL_QUESTIONS]` 契约
```
[SKILL_QUESTIONS]
skill=openvino-environment-management
type=preset|preflight|clarify|all
count=<问题块数>
data=<紧凑 JSON 数组；每个块 {type,id,prompt,multiselect,options:[{key,label,example?,exclusive?,on_missing?}]}>
[/SKILL_QUESTIONS]
```

**agent 约定：** `preflight` 各项与预检查 PC1–PC10 对应；用户**没勾**的项通过 `on_missing` 指向对应的
安装步骤（如 `self:ST1` 装 Python、`self:ST5-ST7` 装 OpenVINO/PyTorch），随后调用 `intel_aipc_env_setup.ps1`
补齐。问题清单在 [questions.json](questions.json)，由 [questions.ps1](questions.ps1) 输出。这一步是「用提问代替
自动探测」的补充，`precheck_env.ps1` 仍可用于程序化诊断。

## 预检查阶段 (PC1-PC10)

### PC1: 检查 Windows 操作系统
**目的**：验证系统是否运行 Windows。
**失败时操作**：退出 - 此脚本仅支持 Windows。

### PC2: 检查 Intel 处理器
**目的**：验证是否存在 Intel CPU。
**失败时操作**：退出 - 仅支持 Intel 处理器。
**警告时操作**：继续但记录 iGPU/NPU 性能可能受限。

### PC3: 检查图形驱动
**目的**：验证 Intel 图形驱动是否已安装。
**警告时操作**：手动安装/更新 Intel 驱动。

### PC4: 检查 Python 安装
**目的**：验证是否已安装 Python 3.10+ 和 pip。
**失败/警告时操作**：运行 [ST1](#st1-安装-python)。

### PC5: 检查 pip 镜像配置
**目的**：验证是否已配置清华镜像。
**警告时操作**：使用 `-China` 参数运行 [ST2](#st2-配置-pip-镜像)。

### PC6: 检查 Git 安装
**目的**：验证是否已安装 Git。
**失败时操作**：运行 [ST3](#st3-安装-git)。

### PC7: 检查 Git 镜像配置
**目的**：验证是否已配置 ghproxy 镜像。
**警告时操作**：使用 `-China` 参数运行 [ST4](#st4-配置-git-镜像)。

### PC8: 检查 HF_ENDPOINT 和 ModelScope
**目的**：验证 Hugging Face 和 ModelScope 镜像是否已设置。
**警告时操作**：运行 [ST5](#st5-安装-modelscope-并配置镜像)。

### PC9: 检查 OpenVINO 安装
**目的**：验证是否已安装 OpenVINO。
**警告时操作**：运行 [ST6](#st6-安装-openvino)。

### PC10: 检查 PyTorch 安装
**目的**：验证是否已安装 PyTorch。
**警告时操作**：运行 [ST7](#st7-安装-pytorch-cpu)。

## 配置阶段 (ST1-ST9)

### ST1: 安装 Python
**触发条件**：PC4 失败/警告

```powershell
Write-Host "`n=== 正在安装 Python 3.12 ==="

$pythonUrl = "https://www.python.org/ftp/python/3.12.0/python-3.12.0-amd64.exe"
$pythonInstaller = "$env:TEMP\python-3.12.0-amd64.exe"
$pythonTargetDir = "$env:LOCALAPPDATA\Programs\Python\Python312"

$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
}
Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonInstaller -UseBasicParsing -Headers $headers

Start-Process -FilePath $pythonInstaller -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1 TARGETDIR=`"$pythonTargetDir`"" -Wait
Remove-Item $pythonInstaller

$env:PATH = "$pythonTargetDir;$pythonTargetDir\Scripts;" + $env:PATH

$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$pythonTargetDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$pythonTargetDir;$pythonTargetDir\Scripts", "User")
}

Write-Host "Python 安装完成。正在验证..."
python --version
pip --version
```

**注意**：将 Python 3.12 安装到 `%LOCALAPPDATA%\Programs\Python\Python312`，无需管理员权限。

### ST2: 配置 pip 镜像
**触发条件**：PC5 警告，`-China` 标志

```powershell
Write-Host "`n=== 正在配置 pip 国内镜像 ==="

$pipConfigDir = "$env:APPDATA\pip"
if (-not (Test-Path $pipConfigDir)) {
    New-Item -ItemType Directory -Path $pipConfigDir -Force | Out-Null
}

$pipIni = "$pipConfigDir\pip.ini"
if ((Test-Path $pipIni) -and (-not (Test-Path "$pipIni.bak"))) {
    Copy-Item $pipIni "$pipIni.bak" -Force
}

$pipConfig = @"
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
[install]
trusted-host = pypi.tuna.tsinghua.edu.cn
"@

Set-Content -Path $pipIni -Value $pipConfig -Encoding UTF8

Write-Host "pip 镜像已配置为清华大学镜像。"
```

**注意**：为 pip 配置清华大学镜像。

### ST3: 安装 Git
**触发条件**：PC6 失败

```powershell
Write-Host "`n=== 正在安装 Git ==="

$gitVersion = "2.55.0.windows.2"
$gitInstaller = "$env:TEMP\PortableGit-2.55.0.2-64-bit.7z.exe"
$gitTargetDir = "$env:LOCALAPPDATA\Programs\Git"

$gitDownloadUrls = @(
    "https://github.com/git-for-windows/git/releases/download/v$gitVersion/PortableGit-2.55.0.2-64-bit.7z.exe",
    "https://ghproxy.net/https://github.com/git-for-windows/git/releases/download/v$gitVersion/PortableGit-2.55.0.2-64-bit.7z.exe"
)

$downloadSuccess = $false
foreach ($gitUrl in $gitDownloadUrls) {
    Write-Host "  正在从 $gitUrl 下载..."
    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing -Headers $headers -ErrorAction Stop
        $downloadSuccess = $true
        break
    } catch {
        Write-Host "  下载失败，尝试下一个 URL..."
    }
}

if ($downloadSuccess) {
    if (Test-Path $gitTargetDir) {
        Remove-Item $gitTargetDir -Recurse -Force
    }
    Start-Process -FilePath $gitInstaller -ArgumentList "-y -o`"$gitTargetDir`"" -Wait
    Remove-Item $gitInstaller
    $env:PATH = "$gitTargetDir\bin;$gitTargetDir\cmd;" + $env:PATH
    
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -notlike "*$gitTargetDir\bin*") {
        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$gitTargetDir\bin;$gitTargetDir\cmd", "User")
    }
}

Write-Host "Git 安装完成。正在验证..."
git --version
```

**注意**：将 Git 安装到 `%LOCALAPPDATA%\Programs\Git`，无需管理员权限。

### ST4: 配置 Git 镜像
**触发条件**：PC7 警告，`-China` 标志

```powershell
Write-Host "`n=== 正在配置 Git 国内镜像 ==="

git config --global url."https://ghproxy.net/https://github.com/".insteadOf "https://github.com/"

$ghProxyConfig = git config --global --get url."https://ghproxy.net/https://github.com/".insteadOf
if ($ghProxyConfig -eq "https://github.com/") {
    Write-Host "Git 镜像已配置为 ghproxy.net（仅用于 github.com）。"
} else {
    Write-Host "Git 镜像配置可能失败。"
}
```

**注意**：为 github.com 访问配置 ghproxy.net。

### ST5: 安装 ModelScope 并配置镜像
**触发条件**：PC8 警告

```powershell
Write-Host "`n=== 正在安装 ModelScope ==="
pip install modelscope

Write-Host "`n=== 正在配置 Hugging Face 镜像 ==="
[Environment]::SetEnvironmentVariable("HF_ENDPOINT", "https://hf-mirror.com", "User")
$env:HF_ENDPOINT = "https://hf-mirror.com"

Write-Host "`n=== 正在配置 ModelScope API URL ==="
[Environment]::SetEnvironmentVariable("MODELSCOPE_API_URL", "https://api.modelscope.cn", "User")
$env:MODELSCOPE_API_URL = "https://api.modelscope.cn"

Write-Host "ModelScope 安装完成，镜像已配置。"
```

**注意**：安装 ModelScope，设置 HF_ENDPOINT 和 MODELSCOPE_API_URL。

### ST6: 安装 OpenVINO
**触发条件**：PC9 警告

```powershell
Write-Host "`n=== 正在安装 OpenVINO ==="

pip install openvino

Write-Host "OpenVINO 安装完成。正在验证..."
python -c "import openvino; print('OpenVINO 版本:', openvino.__version__)"
```

### ST7: 安装 PyTorch (CPU)
**触发条件**：PC10 警告

```powershell
Write-Host "`n=== 正在安装 PyTorch (CPU 版本) ==="

try {
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --trusted-host download.pytorch.org
    Write-Host "CPU 版本安装成功"
} catch {
    Write-Host "CPU 版本安装失败，尝试清华大学镜像..."
    pip install torch torchvision torchaudio -i https://pypi.tuna.tsinghua.edu.cn/simple --trusted-host pypi.tuna.tsinghua.edu.cn
    Write-Host "通过清华大学镜像安装成功"
}

Write-Host "PyTorch 安装完成。正在验证..."
python -c "import torch; print('PyTorch 版本:', torch.__version__)"
```

**重要说明**：
- **版本参考**：特定的 PyTorch 版本应参考目标 notebook 项目。此安装仅提供基础 CPU 环境。
- **虚拟环境策略**：实际部署时，应创建项目特定的虚拟环境，而不是直接使用 Jupyter。每个参考 notebook 项目应有自己独立的虚拟环境，包版本与 notebook 要求完全匹配。
- **部署时不使用 Jupyter**：当智能体部署从 notebook 引用的实际项目时，不要使用 Jupyter。相反，应创建独立脚本并在专用虚拟环境中运行。

### ST8: 安装 CMake（可选）
**触发条件**：`-InstallCmake` 或 `-FullInstall`

```powershell
Write-Host "`n=== 正在安装 CMake（可选） ==="

$cmakeVersion = "4.3.4"
$cmakeZip = "$env:TEMP\cmake-$cmakeVersion.zip"
$cmakeTargetDir = "$env:USERPROFILE\cmake"

$cmakeDownloadUrls = @(
    "https://ghproxy.net/https://github.com/Kitware/CMake/releases/download/v$cmakeVersion/cmake-$cmakeVersion-windows-x86_64.zip",
    "https://github.com/Kitware/CMake/releases/download/v$cmakeVersion/cmake-$cmakeVersion-windows-x86_64.zip"
)

$downloadSuccess = $false
foreach ($cmakeUrl in $cmakeDownloadUrls) {
    Write-Host "尝试下载: $cmakeUrl"
    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        Invoke-WebRequest -Uri $cmakeUrl -OutFile $cmakeZip -UseBasicParsing -Headers $headers
        $downloadSuccess = $true
        break
    } catch {
        Write-Host "下载失败，尝试下一个 URL..."
    }
}

if ($downloadSuccess) {
    if (Test-Path $cmakeTargetDir) {
        Remove-Item $cmakeTargetDir -Recurse -Force
    }
    Expand-Archive -Path $cmakeZip -DestinationPath $cmakeTargetDir -Force
    Remove-Item $cmakeZip -Force

    $cmakeBinDir = Get-ChildItem -Path $cmakeTargetDir -Directory | Select-Object -First 1
    $cmakeBinDir = "$($cmakeBinDir.FullName)\bin"

    $env:PATH = "$cmakeBinDir;" + $env:PATH

    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $oldPaths = @(
        "C:\Users\intel\AppData\Local\Programs\CMake\bin",
        "$env:LOCALAPPDATA\Programs\CMake\bin",
        "$env:USERPROFILE\tools\cmake\bin"
    )
    foreach ($oldPath in $oldPaths) {
        $currentPath = $currentPath -replace [regex]::Escape($oldPath), ""
    }
    $currentPath = $currentPath -replace ";;", ";"
    if ($currentPath -notlike "*$cmakeBinDir*") {
        $currentPath = "$cmakeBinDir;$currentPath"
        [Environment]::SetEnvironmentVariable("PATH", $currentPath, "User")
    }

    Write-Host "CMake 安装完成。正在验证..."
    cmake --version
} else {
    Write-Host "所有下载均失败。请手动安装。"
}
```

**注意**：C++ 项目编译所需。

### ST9: 安装 Visual Studio（可选）
**触发条件**：`-InstallVS` 或 `-FullInstall`

> **⚠️ 重要**：需要管理员权限。

```powershell
Write-Host "`n=== 正在安装 Visual Studio Community Edition（可选） ==="

$vsInstallerUrl = "https://aka.ms/vs/17/release/vs_community.exe"
$vsInstaller = "$env:TEMP\vs_community.exe"

Invoke-WebRequest -Uri $vsInstallerUrl -OutFile $vsInstaller -UseBasicParsing

Start-Process -FilePath $vsInstaller -ArgumentList "--quiet --wait --norestart --nocache --installPath C:\Program Files\Microsoft Visual Studio\2022\Community --add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows10SDK --add Microsoft.VisualStudio.Component.Windows11SDK" -Wait

Remove-Item $vsInstaller

Write-Host "Visual Studio Community 安装完成。"
```

**注意**：需要管理员权限，安装 C++ 桌面开发工作负载。

## 硬件检测标准

> **⚠️ 重要**：检测 CPU、GPU、NPU 或任何硬件信息时，**必须**使用 OpenVINO 的 `hello_query_device.py` 脚本作为主要方法。**不要**使用 PowerShell WMI/CIM 查询作为最终结果。

### 为什么使用 hello_query_device.py？

- 提供**完整的硬件信息**，包括设备名称、架构、优化能力、GOPS 和内存
- 覆盖**所有三种设备**：CPU、GPU（Intel Arc）和 NPU（Intel AI Boost）
- 是**官方 OpenVINO 诊断工具**，反映 OpenVINO 可访问的实际硬件

### 下载并运行

```powershell
$helloScriptPath = "$env:TEMP\hello_query_device.py"
$downloadUrls = @(
    "https://ghproxy.net/https://github.com/openvinotoolkit/openvino/raw/refs/heads/master/samples/python/hello_query_device/hello_query_device.py",
    "https://github.com/openvinotoolkit/openvino/raw/refs/heads/master/samples/python/hello_query_device/hello_query_device.py"
)

$downloadSuccess = $false
foreach ($url in $downloadUrls) {
    try {
        Invoke-WebRequest -Uri $url -OutFile $helloScriptPath -UseBasicParsing -ErrorAction Stop
        $downloadSuccess = $true
        break
    } catch {
        Write-Host "下载失败，尝试下一个 URL..."
    }
}

if ($downloadSuccess -and (Test-Path $helloScriptPath)) {
    python $helloScriptPath
    Remove-Item $helloScriptPath -Force
}
```

### 预期输出示例（Intel Ultra 9 285H 处理器）

```
[ INFO ] Available devices:
[ INFO ] CPU : Intel(R) Core(TM) Ultra 9 285H
[ INFO ]        OPTIMIZATION_CAPABILITIES: FP32, FP16, INT8, BIN, EXPORT_IMPORT
[ INFO ]        DEVICE_TYPE: Type.INTEGRATED
[ INFO ] GPU : Intel(R) Arc(TM) 140T (16GB)
[ INFO ]        ARCHITECTURE: Intel Xe2 Architecture
[ INFO ]        OPTIMIZATION_CAPABILITIES: FP32, FP16, INT8, BIN, EXPORT_IMPORT
[ INFO ]        GOPS: 1848.000000
[ INFO ] NPU : Intel(R) AI Boost (NPU)
[ INFO ]        DEVICE_TYPE: Type.INTEGRATED
```

## 验证流程（可选）

### 测试 OpenVINO 安装

```powershell
python -c "import openvino; print('OpenVINO 版本:', openvino.__version__)"
```

### 测试 PyTorch 安装

```powershell
python -c "import torch; print('PyTorch 版本:', torch.__version__); print('CUDA 可用:', torch.cuda.is_available())"
```

### 测试设备可用性

```powershell
python $env:TEMP\hello_query_device.py
```

## 预检查到配置映射

| 预检查 | 状态 | 配置操作 |
|-----------|--------|--------------|
| PC1: 操作系统 | 失败 → 退出 | - |
| PC2: Intel CPU | 失败 → 退出 | - |
| PC3: 驱动 | 警告 | 手动更新 |
| PC4: Python | 失败/警告 | ST1 |
| PC5: pip 镜像 | 警告 (+China) | ST2 |
| PC6: Git | 失败 | ST3 |
| PC7: Git 镜像 | 警告 (+China) | ST4 |
| PC8: HF/ModelScope | 警告 | ST5 |
| PC9: OpenVINO | 警告 | ST6 |
| PC10: PyTorch | 警告 | ST7 |

## 错误场景

| 错误 | 根本原因 | 预检查 | 修复 |
|-------|------------|-----------|-----|
| `'python' is not recognized` | Python 未安装 | PC4 | 运行 ST1 |
| `pip install` 超时 | 未配置国内镜像 | PC5 | 使用 `-China` 参数运行 ST2 |
| `git clone` 超时 | GitHub 访问被阻止 | PC6, PC7 | 使用 `-China` 参数运行 ST3 + ST4 |
| `import torch` 失败 | PyTorch 未安装 | PC10 | 运行 ST7 |

## 脚本文件

| 文件 | 用途 |
|------|---------|
| `precheck_env.ps1` | 独立预检查脚本（PC1-PC10），带 JSON 输出 |
| `intel_aipc_env_setup.ps1` | 主配置脚本（ST1-ST9） |

## 配置安全性

- `-China` 标志仅在明确请求时修改配置
- 覆盖前会将现有的 `pip.ini` 备份到 `pip.ini.bak`
- Git 镜像只是一个 `insteadOf` 规则，可以轻松移除

**恢复命令**：
```powershell
# 恢复 pip 配置
Move-Item -Force "$env:APPDATA\pip\pip.ini.bak" "$env:APPDATA\pip\pip.ini"

# 移除 git 镜像
git config --global --unset url."https://ghproxy.net/https://github.com/".insteadOf
```