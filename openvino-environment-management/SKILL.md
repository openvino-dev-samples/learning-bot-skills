---
name: "openvino-environment-management"
description: "Two-phase environment setup for Intel AIPC development on Windows. Phase 1: Run precheck_env.ps1 (PC1-PC10) to assess current state. Phase 2: Run intel_aipc_env_setup.ps1 (ST1-ST9) for missing components. Pre-checks verify: OS, Intel CPU, drivers, Python, pip mirror, Git, Git mirror, HF/ModelScope, OpenVINO, PyTorch. Use -China for domestic mirrors. CMake (ST8) and VS (ST9) are optional."
---

# Intel AIPC Environment Management

## Agent Usage Guide

This skill is designed for **AI agents** to set up Intel AIPC development environments on Windows. Follow this two-phase workflow:

### Phase 1: Pre-Check (Diagnose)
Run the standalone pre-check script first to assess the current environment. This helps identify what needs to be installed or configured.

```powershell
powershell -ExecutionPolicy Bypass -File precheck_env.ps1
```

The script outputs a JSON summary between `[AGENT_OUTPUT]` and `[/AGENT_OUTPUT]` tags for programmatic parsing.

### Phase 2: Setup (Install/Configure)
Based on pre-check results, run the setup script for missing components.

```powershell
# Basic setup (no mirrors)
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1

# With domestic mirrors (Mainland China)
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -China

# Include optional components
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -InstallCmake
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -InstallVS
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -FullInstall
```

## Script Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-InstallCmake` | Install CMake | `$false` |
| `-InstallVS` | Install Visual Studio Community Edition | `$false` |
| `-FullInstall` | Install all components (including optional) | `$false` |
| `-China` | Use domestic mirrors (Tsinghua pip + ghproxy.net for github.com) | `$false` |

## Pre-Check Phase (PC1-PC10)

### PC1: Check Windows Operating System
**Purpose**: Verify the system is running Windows.
**Action if FAIL**: Exit - this script only supports Windows.

### PC2: Check Intel Processor
**Purpose**: Verify Intel CPU is present.
**Action if FAIL**: Exit - only Intel processors are supported.
**Action if WARN**: Continue but note limited iGPU/NPU performance.

### PC3: Check Graphics Drivers
**Purpose**: Verify Intel graphics driver is installed.
**Action if WARN**: Install/update Intel driver manually.

### PC4: Check Python Installation
**Purpose**: Verify Python 3.10+ is installed with pip.
**Action if FAIL/WARN**: Run [ST1](#st1-install-python).

### PC5: Check pip Mirror Configuration
**Purpose**: Verify Tsinghua mirror is configured.
**Action if WARN**: Run [ST2](#st2-configure-pip-mirror) with `-China`.

### PC6: Check Git Installation
**Purpose**: Verify Git is installed.
**Action if FAIL**: Run [ST3](#st3-install-git).

### PC7: Check Git Mirror Configuration
**Purpose**: Verify ghproxy mirror is configured.
**Action if WARN**: Run [ST4](#st4-configure-git-mirror) with `-China`.

### PC8: Check HF_ENDPOINT and ModelScope
**Purpose**: Verify Hugging Face and ModelScope mirrors are set.
**Action if WARN**: Run [ST5](#st5-install-modelscope-and-configure-mirrors).

### PC9: Check OpenVINO Installation
**Purpose**: Verify OpenVINO is installed.
**Action if WARN**: Run [ST6](#st6-install-openvino).

### PC10: Check PyTorch Installation
**Purpose**: Verify PyTorch is installed.
**Action if WARN**: Run [ST7](#st7-install-pytorch-cpu).

## Setup Phase (ST1-ST9)

### ST1: Install Python
**Triggers**: PC4 FAIL/WARN

```powershell
Write-Host "`n=== Installing Python 3.12 ==="

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

Write-Host "Python installation completed. Verifying..."
python --version
pip --version
```

**Notes**: Installs Python 3.12 to `%LOCALAPPDATA%\Programs\Python\Python312`, no admin rights needed.

### ST2: Configure pip Mirror
**Triggers**: PC5 WARN, `-China` flag

```powershell
Write-Host "`n=== Configuring pip domestic mirror ==="

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

Write-Host "pip mirror configured to Tsinghua University mirror."
```

**Notes**: Configures Tsinghua University mirror for pip.

### ST3: Install Git
**Triggers**: PC6 FAIL

```powershell
Write-Host "`n=== Installing Git ==="

$gitVersion = "2.55.0.windows.2"
$gitInstaller = "$env:TEMP\PortableGit-2.55.0.2-64-bit.7z.exe"
$gitTargetDir = "$env:LOCALAPPDATA\Programs\Git"

$gitDownloadUrls = @(
    "https://github.com/git-for-windows/git/releases/download/v$gitVersion/PortableGit-2.55.0.2-64-bit.7z.exe",
    "https://ghproxy.net/https://github.com/git-for-windows/git/releases/download/v$gitVersion/PortableGit-2.55.0.2-64-bit.7z.exe"
)

$downloadSuccess = $false
foreach ($gitUrl in $gitDownloadUrls) {
    Write-Host "  Downloading from $gitUrl..."
    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing -Headers $headers -ErrorAction Stop
        $downloadSuccess = $true
        break
    } catch {
        Write-Host "  Download failed, trying next URL..."
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

Write-Host "Git installation completed. Verifying..."
git --version
```

**Notes**: Installs Git to `%LOCALAPPDATA%\Programs\Git`, no admin rights needed.

### ST4: Configure Git Mirror
**Triggers**: PC7 WARN, `-China` flag

```powershell
Write-Host "`n=== Configuring Git domestic mirror ==="

git config --global url."https://ghproxy.net/https://github.com/".insteadOf "https://github.com/"

$ghProxyConfig = git config --global --get url."https://ghproxy.net/https://github.com/".insteadOf
if ($ghProxyConfig -eq "https://github.com/") {
    Write-Host "Git mirror configured to ghproxy.net (for github.com only)."
} else {
    Write-Host "Git mirror configuration may have failed."
}
```

**Notes**: Configures ghproxy.net for github.com access.

### ST5: Install ModelScope and Configure Mirrors
**Triggers**: PC8 WARN

```powershell
Write-Host "`n=== Installing ModelScope ==="
pip install modelscope

Write-Host "`n=== Configuring Hugging Face Mirror ==="
[Environment]::SetEnvironmentVariable("HF_ENDPOINT", "https://hf-mirror.com", "User")
$env:HF_ENDPOINT = "https://hf-mirror.com"

Write-Host "`n=== Configuring ModelScope API URL ==="
[Environment]::SetEnvironmentVariable("MODELSCOPE_API_URL", "https://api.modelscope.cn", "User")
$env:MODELSCOPE_API_URL = "https://api.modelscope.cn"

Write-Host "ModelScope installation completed, mirrors configured."
```

**Notes**: Installs ModelScope, sets HF_ENDPOINT and MODELSCOPE_API_URL.

### ST6: Install OpenVINO
**Triggers**: PC9 WARN

```powershell
Write-Host "`n=== Installing OpenVINO ==="

pip install openvino

Write-Host "OpenVINO installation completed. Verifying..."
python -c "import openvino; print('OpenVINO version:', openvino.__version__)"
```

### ST7: Install PyTorch (CPU)
**Triggers**: PC10 WARN

```powershell
Write-Host "`n=== Installing PyTorch (CPU Version) ==="

try {
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --trusted-host download.pytorch.org
    Write-Host "CPU version installed successfully"
} catch {
    Write-Host "CPU version installation failed, trying Tsinghua mirror..."
    pip install torch torchvision torchaudio -i https://pypi.tuna.tsinghua.edu.cn/simple --trusted-host pypi.tuna.tsinghua.edu.cn
    Write-Host "Installed via Tsinghua mirror successfully"
}

Write-Host "PyTorch installation completed. Verifying..."
python -c "import torch; print('PyTorch version:', torch.__version__)"
```

**Important Notes**:
- **Version Reference**: Specific PyTorch versions should be referenced from the target notebook project. This installation provides a base CPU environment only.
- **Virtual Environment Strategy**: For actual deployment, create project-specific virtual environments instead of using Jupyter directly. Each reference notebook project should have its own isolated virtual environment with exact package versions matching the notebook requirements.
- **No Jupyter in Deployment**: When the agent deploys actual projects referenced from notebooks, do not use Jupyter. Instead, create standalone scripts and run them in dedicated virtual environments.

### ST8: Install CMake (Optional)
**Triggers**: `-InstallCmake` or `-FullInstall`

```powershell
Write-Host "`n=== Installing CMake (Optional) ==="

$cmakeVersion = "4.3.4"
$cmakeZip = "$env:TEMP\cmake-$cmakeVersion.zip"
$cmakeTargetDir = "$env:USERPROFILE\cmake"

$cmakeDownloadUrls = @(
    "https://ghproxy.net/https://github.com/Kitware/CMake/releases/download/v$cmakeVersion/cmake-$cmakeVersion-windows-x86_64.zip",
    "https://github.com/Kitware/CMake/releases/download/v$cmakeVersion/cmake-$cmakeVersion-windows-x86_64.zip"
)

$downloadSuccess = $false
foreach ($cmakeUrl in $cmakeDownloadUrls) {
    Write-Host "Trying download: $cmakeUrl"
    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        Invoke-WebRequest -Uri $cmakeUrl -OutFile $cmakeZip -UseBasicParsing -Headers $headers
        $downloadSuccess = $true
        break
    } catch {
        Write-Host "Download failed, trying next URL..."
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

    Write-Host "CMake installation completed. Verifying..."
    cmake --version
} else {
    Write-Host "All downloads failed. Please install manually."
}
```

**Notes**: Required for C++ project compilation.

### ST9: Install Visual Studio (Optional)
**Triggers**: `-InstallVS` or `-FullInstall`

> **⚠️ Important**: Requires administrator privileges.

```powershell
Write-Host "`n=== Installing Visual Studio Community Edition (Optional) ==="

$vsInstallerUrl = "https://aka.ms/vs/17/release/vs_community.exe"
$vsInstaller = "$env:TEMP\vs_community.exe"

Invoke-WebRequest -Uri $vsInstallerUrl -OutFile $vsInstaller -UseBasicParsing

Start-Process -FilePath $vsInstaller -ArgumentList "--quiet --wait --norestart --nocache --installPath C:\Program Files\Microsoft Visual Studio\2022\Community --add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows10SDK --add Microsoft.VisualStudio.Component.Windows11SDK" -Wait

Remove-Item $vsInstaller

Write-Host "Visual Studio Community installation completed."
```

**Notes**: Requires administrator privileges, installs Desktop development with C++ workload.

## Hardware Detection Standard

> **⚠️ Important**: When detecting CPU, GPU, NPU, or any hardware information, you **MUST** use the OpenVINO `hello_query_device.py` script as the primary method. Do NOT use PowerShell WMI/CIM queries as the final result.

### Why hello_query_device.py?

- It provides **complete hardware information** including device name, architecture, optimization capabilities, GOPS, and memory
- It covers **all three devices**: CPU, GPU (Intel Arc), and NPU (Intel AI Boost)
- It is the **official OpenVINO diagnostic tool** and reflects the actual hardware accessible by OpenVINO

### Download and Run

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
        Write-Host "Download failed, trying next URL..."
    }
}

if ($downloadSuccess -and (Test-Path $helloScriptPath)) {
    python $helloScriptPath
    Remove-Item $helloScriptPath -Force
}
```

### Expected Output Example (Intel Ultra 9 285H Processor)

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

## Verification Process (Optional)

### Test OpenVINO Installation

```powershell
python -c "import openvino; print('OpenVINO version:', openvino.__version__)"
```

### Test PyTorch Installation

```powershell
python -c "import torch; print('PyTorch version:', torch.__version__); print('CUDA available:', torch.cuda.is_available())"
```

### Test Device Availability

```powershell
python $env:TEMP\hello_query_device.py
```

## Pre-Check to Setup Mapping

| Pre-Check | Status | Setup Action |
|-----------|--------|--------------|
| PC1: OS | FAIL → Exit | - |
| PC2: Intel CPU | FAIL → Exit | - |
| PC3: Drivers | WARN | Manual update |
| PC4: Python | FAIL/WARN | ST1 |
| PC5: pip mirror | WARN (+China) | ST2 |
| PC6: Git | FAIL | ST3 |
| PC7: Git mirror | WARN (+China) | ST4 |
| PC8: HF/ModelScope | WARN | ST5 |
| PC9: OpenVINO | WARN | ST6 |
| PC10: PyTorch | WARN | ST7 |

## Error Scenarios

| Error | Root Cause | Pre-Check | Fix |
|-------|------------|-----------|-----|
| `'python' is not recognized` | Python not installed | PC4 | Run ST1 |
| `pip install` timeout | No domestic mirror | PC5 | Run ST2 with `-China` |
| `git clone` timeout | GitHub access blocked | PC6, PC7 | Run ST3 + ST4 with `-China` |
| `import torch` failed | PyTorch not installed | PC10 | Run ST7 |

## Script Files

| File | Purpose |
|------|---------|
| `precheck_env.ps1` | Standalone pre-check script (PC1-PC10) with JSON output |
| `intel_aipc_env_setup.ps1` | Main setup script (ST1-ST9) |

## Configuration Safety

- `-China` flag only modifies config when explicitly requested
- Existing `pip.ini` is backed up to `pip.ini.bak` before overwriting
- Git mirror is a single `insteadOf` rule that can be easily removed

**Restore commands**:
```powershell
# Restore pip config
Move-Item -Force "$env:APPDATA\pip\pip.ini.bak" "$env:APPDATA\pip\pip.ini"

# Remove git mirror
git config --global --unset url."https://ghproxy.net/https://github.com/".insteadOf
```
