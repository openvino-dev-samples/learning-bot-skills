---
name: "openvino-environment-management"
description: "Configure Intel AIPC development environment on Windows: install Python, Git, ModelScope, OpenVINO, PyTorch CPU. Pass -China to apply domestic mirrors (pip/git); otherwise existing config is left untouched. CMake and Visual Studio are optional components. Call this skill when you need to configure Intel AIPC development environment on Windows."
---

# Environment Management (Intel AIPC)

This skill configures Intel AIPC development environment on Windows, including basic environment (Python, Git, ModelScope, latest-stable OpenVINO, PyTorch CPU) and optional C++ compilation environment (CMake, Visual Studio).

## Script Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-InstallCmake` | Install CMake | `$false` |
| `-InstallVS` | Install Visual Studio Community Edition | `$false` |
| `-FullInstall` | Install all components (including optional) | `$false` |
| `-China` | Use domestic mirrors (Tsinghua pip + ghproxy.net for github.com). When omitted, existing pip/git config is left untouched. | `$false` |

```powershell
# Basic installation (default) — no mirror changes, existing pip/git config preserved
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1

# Mainland China / no VPN — apply domestic mirrors
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -China

# Install CMake
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -InstallCmake

# Install Visual Studio
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -InstallVS

# Install everything (including optional)
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -FullInstall
```

> **Config safety / restore:** `-China` only rewrites mirror config when explicitly requested. Any
> existing `pip.ini` is backed up to `pip.ini.bak` before being overwritten, and the git mirror is a
> single `insteadOf` rule. To restore the machine's defaults:
> ```powershell
> # restore pip config
> Move-Item -Force "$env:APPDATA\pip\pip.ini.bak" "$env:APPDATA\pip\pip.ini"
> # remove the git github->ghproxy rewrite
> git config --global --unset url."https://ghproxy.net/https://github.com/".insteadOf
> ```

## Pre-checks

### Step 1: Check Windows Operating System

```powershell
$osInfo = Get-WmiObject -Class Win32_OperatingSystem
Write-Host "OS Name: $($osInfo.Caption)"
Write-Host "OS Version: $($osInfo.Version)"

if (-not ($osInfo.Caption -like "*Windows*")) {
    Write-Error "Error: This script can only run on Windows!"
    exit 1
}
```

### Step 2: Check Intel Processor

```powershell
$cpuInfo = Get-WmiObject -Class Win32_Processor
$cpuName = $cpuInfo.Name
Write-Host "Processor: $cpuName"

$isIntel = $cpuName -like "*Intel*"
$isUltra = $cpuName -like "*Ultra*"
$hasArc = $cpuName -like "*Arc*"

if (-not $isIntel) {
    Write-Error "Error: Non-Intel processor detected! This script only supports Intel processors."
    exit 1
}

if (-not ($isUltra -or $hasArc)) {
    Write-Warning "Warning: Non-Ultra series processor detected. iGPU/NPU acceleration performance may be limited."
    Write-Warning "It is recommended to use Intel Ultra series processors or Intel Arc discrete graphics for best performance."
}
```

### Step 3: Check iGPU/NPU and Drivers

```powershell
Write-Host "`n=== Checking GPU Devices ==="
Get-WmiObject -Class Win32_VideoController | ForEach-Object {
    Write-Host "GPU Name: $($_.Name)"
    Write-Host "Driver Version: $($_.DriverVersion)"
    Write-Host "---"
}

Write-Host "`n=== Checking Intel Graphics Driver Version ==="
$intelDriver = Get-WmiObject -Class Win32_PnPSignedDriver | Where-Object {
    $_.DeviceName -like "*Intel*Graphics*" -or $_.DeviceName -like "*Intel*UHD*" -or $_.DeviceName -like "*Intel*Arc*"
}

if ($intelDriver) {
    Write-Host "Found Intel Graphics Driver:"
    $intelDriver | ForEach-Object {
        Write-Host "  Device: $($_.DeviceName)"
        Write-Host "  Driver Version: $($_.DriverVersion)"
        Write-Host "  Driver Date: $($_.DriverDate)"
    }
} else {
    Write-Warning "Warning: No Intel graphics driver found. Please install the latest Intel driver."
}

Write-Host "`n=== Checking for Latest Drivers ==="
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $searchResult = $updateSearcher.Search("IsInstalled=0 AND Type='Driver' AND Title='*Intel*'")
    
    if ($searchResult.Updates.Count -eq 0) {
        Write-Host "Current driver is up to date"
    } else {
        Write-Warning "Intel driver updates available, please run Intel Driver Support Assistant to update"
    }
} catch {
    Write-Warning "Unable to check driver updates, please manually visit: https://www.intel.com/content/www/us/en/support/detect.html"
}
```

## Environment Installation

### Step 4: Install Python (No admin rights required)

```powershell
Write-Host "`n=== Installing Python 3.12 ==="

$pythonUrl = "https://www.python.org/ftp/python/3.12.0/python-3.12.0-amd64.exe"
$pythonInstaller = "$env:TEMP\python-3.12.0-amd64.exe"
$pythonTargetDir = "$env:LOCALAPPDATA\Programs\Python\Python312"

$headers = @{
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}
Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonInstaller -UseBasicParsing -Headers $headers

Start-Process -FilePath $pythonInstaller -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1 TARGETDIR=`"$pythonTargetDir`"" -Wait

Remove-Item $pythonInstaller

$env:PATH = "$pythonTargetDir;$pythonTargetDir\Scripts;" + $env:PATH

$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$pythonTargetDir*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$pythonTargetDir;$pythonTargetDir\Scripts", "User")
    Write-Host "Python path added to user PATH"
}

Write-Host "Python installation completed. Verifying..."
python --version
pip --version
```

### Step 5: Configure pip Domestic Mirror

> Only applied with `-China`. Without it, the existing pip configuration is left untouched. When
> applied, any existing `pip.ini` is first backed up to `pip.ini.bak`.

```powershell
Write-Host "`n=== Configuring pip domestic mirror ==="

$pipConfigDir = "$env:APPDATA\pip"
if (-not (Test-Path $pipConfigDir)) {
    New-Item -ItemType Directory -Path $pipConfigDir -Force | Out-Null
}

$pipIni = "$pipConfigDir\pip.ini"
if ((Test-Path $pipIni) -and (-not (Test-Path "$pipIni.bak"))) {
    Copy-Item $pipIni "$pipIni.bak" -Force  # preserve original for restore
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

### Step 6: Install Git (No admin rights required, no UAC prompts)
> **Git-LFS is optional**: Add `-WithGitLfs` parameter to install. Default installation skips Git-LFS.

```powershell
$WithGitLfs = $false  # Set to $true to install Git-LFS

Write-Host "`n=== Installing Git ==="

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
$useMirror = $false

foreach ($gitUrl in $gitDownloadUrls) {
    Write-Host "  Downloading from $gitUrl..."
    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing -Headers $headers -ErrorAction Stop
        $downloadSuccess = $true
        if ($gitUrl.Contains("ghproxy")) {
            $useMirror = $true
        }
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
        Write-Host "Git path added to user PATH"
    }
}

if ($WithGitLfs) {
    Write-Host "`n=== Installing Git-LFS (optional) ==="
    
    $gitLfsVersion = "3.7.1"
    $gitLfsInstaller = "$env:TEMP\git-lfs-windows-v$gitLfsVersion.exe"
    
    $gitLfsDownloadUrls = @(
        "https://github.com/git-lfs/git-lfs/releases/download/v$gitLfsVersion/git-lfs-windows-v$gitLfsVersion.exe",
        "https://ghproxy.net/https://github.com/git-lfs/git-lfs/releases/download/v$gitLfsVersion/git-lfs-windows-v$gitLfsVersion.exe"
    )
    
    foreach ($gitLfsUrl in $gitLfsDownloadUrls) {
        Write-Host "  Downloading from $gitLfsUrl..."
        try {
            Invoke-WebRequest -Uri $gitLfsUrl -OutFile $gitLfsInstaller -UseBasicParsing -Headers $headers -ErrorAction Stop
            if ($gitLfsUrl.Contains("ghproxy")) {
                $useMirror = $true
            }
            break
        } catch {
            Write-Host "  Download failed, trying next URL..."
        }
    }
    
    Start-Process -FilePath $gitLfsInstaller -ArgumentList "/S" -Wait
    Remove-Item $gitLfsInstaller
    git lfs install
    Write-Host "  Git-LFS installation completed!" -ForegroundColor Green
} else {
    Write-Host "`n=== Git-LFS skipped (use -WithGitLfs to install when needed) ===" -ForegroundColor Yellow
}

Write-Host "Git installation completed. Verifying..."
git --version
```

### Step 7: Configure Git Domestic Mirror

> Only applied with `-China`. Without it, the global git config is left untouched. Restore later with
> `git config --global --unset url."https://ghproxy.net/https://github.com/".insteadOf`.

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

**Test Verification**: Based on actual testing, ghproxy mirror performs better in mainland China network environment:

| Method | Clone Time | Status |
|--------|-----------|--------|
| GitHub Original | 4.97 seconds | ✓ Success |
| ghproxy Mirror | 3.32 seconds | ✓ Success |

**Conclusion**: ghproxy mirror is approximately 33% faster (1.65 seconds) than the original URL, with complete and consistent downloaded files. ghproxy mirror is therefore used when `-China` is passed, for a better download experience in mainland China.

**How it works**: After configuration, all `git clone https://github.com/xxx` commands will automatically be converted to `git clone https://ghproxy.net/https://github.com/xxx`, no manual URL modification required.

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

### Hardware Info Summary

| Device | Name | Architecture | Key Feature |
|--------|------|--------------|-------------|
| CPU | Intel(R) Core(TM) Ultra 9 285H | Intel | 16 Cores |
| GPU | Intel(R) Arc(TM) 140T (16GB) | Intel Xe2 | 1848 GOPS |
| NPU | Intel(R) AI Boost | Intel | Low-power AI |

### Step 8: Install CMake (Optional, required for C++ project compilation)

```powershell
# Use -InstallCmake or -FullInstall parameter to install
# powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -InstallCmake

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
        Write-Host "CMake path added to user PATH"
    }

    Write-Host "CMake installation completed. Verifying..."
    cmake --version
} else {
    Write-Host "All downloads failed. Please install manually."
}
```

**Note**: Using ZIP archive extraction directly to user directory (`$env:USERPROFILE\cmake`), no admin rights required, no UAC prompts. ghproxy mirror is prioritized for download, falling back to official URL on failure.

### Step 9: Install Visual Studio Community Edition (Optional, required for C++ project compilation)

> **⚠️ Important**: Visual Studio installation **requires** administrator privileges, UAC prompt cannot be bypassed. Please run PowerShell as administrator before executing installation.

```powershell
# Use -InstallVS or -FullInstall parameter to install
# powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -InstallVS

Write-Host "`n=== Installing Visual Studio Community Edition (Optional) ==="

$vsInstallerUrl = "https://aka.ms/vs/17/release/vs_community.exe"
$vsInstaller = "$env:TEMP\vs_community.exe"

Invoke-WebRequest -Uri $vsInstallerUrl -OutFile $vsInstaller -UseBasicParsing

Start-Process -FilePath $vsInstaller -ArgumentList "--quiet --wait --norestart --nocache --installPath C:\Program Files\Microsoft Visual Studio\2022\Community --add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows10SDK --add Microsoft.VisualStudio.Component.Windows11SDK" -Wait

Remove-Item $vsInstaller

Write-Host "Visual Studio Community installation completed."
```

**Notes**:
- Install Path: `C:\Program Files\Microsoft Visual Studio\2022\Community`
- Components: Desktop development with C++ workload + VC Tools + Windows 10/11 SDK
- Installation Time: Approximately 10-30 minutes (depending on network speed)
- **Must run as administrator**, otherwise UAC prompt will be triggered or installation will fail

### Step 11: Install ModelScope and Configure HF Mirror

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

## Verification Process (Optional)

### Step 12: Install OpenVINO

```powershell
Write-Host "`n=== Installing OpenVINO ==="

pip install openvino

Write-Host "OpenVINO installation completed. Verifying..."
python -c "import openvino; print('OpenVINO version:', openvino.__version__)"
```

### Step 13: Install PyTorch (CPU Version)

```powershell
Write-Host "`n=== Installing PyTorch (CPU Version) ==="

# Install CPU version directly
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

**Important Notes:**
- **Version Reference**: Specific PyTorch versions should be referenced from the target notebook project. This installation provides a base CPU environment only.
- **Virtual Environment Strategy**: For actual deployment, create project-specific virtual environments instead of using Jupyter directly. Each reference notebook project should have its own isolated virtual environment with exact package versions matching the notebook requirements.
- **No Jupyter in Deployment**: When the agent deploys actual projects referenced from notebooks, do not use Jupyter. Instead, create standalone scripts and run them in dedicated virtual environments.

### Step 14: Test Device Availability with OpenVINO

```powershell
Write-Host "`n=== Testing Device Availability ==="

$testScript = @"
from openvino.runtime import Core

core = Core()
available_devices = core.available_devices

print("Available devices:", available_devices)

for device in available_devices:
    print(f"\n--- Device: {device} ---")
    device_properties = core.get_property(device)
    for key, value in device_properties.items():
        print(f"  {key}: {value}")

print("\n=== Checking Intel GPU/NPU ===")
has_intel_gpu = any('GPU' in dev.upper() for dev in available_devices)
has_intel_npu = any('NPU' in dev.upper() for dev in available_devices)

if has_intel_gpu:
    print("✓ Intel GPU detected")
else:
    print("✗ No Intel GPU detected")

if has_intel_npu:
    print("✓ Intel NPU detected")
else:
    print("✗ No Intel NPU detected")
"@

$testScript | python
```

### Step 15: Download and Run OpenVINO hello_query_device Example

```powershell
Write-Host "`n=== Downloading and running hello_query_device ==="

$helloScriptPath = "$env:TEMP\hello_query_device.py"
$downloadUrls = @(
    "https://ghproxy.net/https://github.com/openvinotoolkit/openvino/raw/refs/heads/master/samples/python/hello_query_device/hello_query_device.py",
    "https://github.com/openvinotoolkit/openvino/raw/refs/heads/master/samples/python/hello_query_device/hello_query_device.py"
)

$downloadSuccess = $false
foreach ($url in $downloadUrls) {
    try {
        Write-Host "  Trying download: $url"
        Invoke-WebRequest -Uri $url -OutFile $helloScriptPath -UseBasicParsing -ErrorAction Stop
        $downloadSuccess = $true
        break
    } catch {
        Write-Host "  Download failed"
    }
}

if ($downloadSuccess -and (Test-Path $helloScriptPath)) {
    Write-Host "  Download successful, running..."
    python $helloScriptPath
    Remove-Item $helloScriptPath -Force
} else {
    Write-Warning "Download failed, skipping this step"
}
```

**Expected Output Example** (Intel Ultra 7 155H Processor):

```
[ INFO ] Available devices:
[ INFO ] CPU :
[ INFO ]        FULL_DEVICE_NAME: Intel(R) Core(TM) Ultra 7 155H
[ INFO ]        OPTIMIZATION_CAPABILITIES: FP32, INT8, BIN, EXPORT_IMPORT
[ INFO ]        DEVICE_TYPE: Type.INTEGRATED
[ INFO ]        NUM_STREAMS: 1
[ INFO ]        INFERENCE_NUM_THREADS: 0
[ INFO ]
[ INFO ] GPU :
[ INFO ]        FULL_DEVICE_NAME: Intel(R) Arc(TM) Graphics (iGPU)
[ INFO ]        DEVICE_GOPS: {<Type: 'float16'>: 9216.0, <Type: 'float32'>: 4608.0, <Type: 'int8_t'>: 18432.0}
[ INFO ]        GPU_DEVICE_TOTAL_MEM_SIZE: 17716371456
[ INFO ]        GPU_EXECUTION_UNITS_COUNT: 128
[ INFO ]        OPTIMIZATION_CAPABILITIES: FP32, BIN, FP16, INT8, EXPORT_IMPORT
[ INFO ]
[ INFO ] NPU :
[ INFO ]        FULL_DEVICE_NAME: Intel(R) AI Boost
[ INFO ]        DEVICE_GOPS: {<Type: 'float16'>: 5734.4, <Type: 'int8_t'>: 11468.8}
[ INFO ]        NPU_DEVICE_TOTAL_MEM_SIZE: 17179869184
[ INFO ]        NPU_MAX_TILES: 2
[ INFO ]        OPTIMIZATION_CAPABILITIES: FP16, INT8, EXPORT_IMPORT
```

**Device Description**:

| Device | Name | Computing Power | Memory |
|--------|------|----------------|--------|
| CPU | Intel Core Ultra 7 155H | 22 threads, FP32/INT8 | - |
| GPU | Intel Arc Graphics (iGPU) | 128 execution units, 9.2 TFLOPS FP16 | 16GB |
| NPU | Intel AI Boost | 2 tiles, 5.7 TFLOPS FP16 | 16GB |

## Post-installation Environment Variable Configuration (User Level, No Admin Rights Required)

```powershell
Write-Host "`n=== Setting Environment Variables ==="

$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")

$gitPath = "$env:LOCALAPPDATA\Programs\Git\bin"
$cmakeTargetDir = "$env:USERPROFILE\cmake"
$cmakeBinDir = (Get-ChildItem -Path $cmakeTargetDir -Directory | Select-Object -First 1).FullName + "\bin"
$pythonPath = "$env:LOCALAPPDATA\Programs\Python\Python312"

if ($currentPath -notlike "*$gitPath*") {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$gitPath;$env:LOCALAPPDATA\Programs\Git\cmd", "User")
}
if ($currentPath -notlike "*$cmakeBinDir*" -and (Test-Path $cmakeBinDir)) {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$cmakeBinDir", "User")
}
if ($currentPath -notlike "*$pythonPath*" -and (Test-Path $pythonPath)) {
    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$pythonPath;$pythonPath\Scripts", "User")
}

Write-Host "Environment variables set (user level, no admin rights required). Please restart terminal."
```

## Run the Complete Script

The complete PowerShell script is located at `intel_aipc_env_setup.ps1`.

```powershell
# Basic installation (default, without CMake and VS)
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1

# Install CMake (for C++ project compilation)
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -InstallCmake

# Install Visual Studio (for C++ project compilation)
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -InstallVS

# Install all components
powershell -ExecutionPolicy Bypass -File intel_aipc_env_setup.ps1 -FullInstall
```

## Change Summary

1. **Python Version**: Updated to Python 3.12.0, download link changed to official FTP
2. **No Admin Rights Required**: Python, Git, CMake installed to user directory (`%LOCALAPPDATA%\Programs\`), environment variables written at user level
3. **Silent Installation**: Using `/quiet`, `/VERYSILENT`, `/qn` parameters, no popups, no interaction
4. **CMake and Visual Studio Made Optional**: Controlled via `-InstallCmake`, `-InstallVS`, `-FullInstall` parameters
5. **Driver Check**: Check driver updates via Windows Update API
6. **Git Mirror**: Use ghproxy.net to access github.com
7. **pip Mirror**: Configure Tsinghua University mirror
8. **HF/ModelScope Mirror**: Configure hf-mirror.com and domestic API URLs
9. **PyTorch CPU Version**: Changed from XPU to CPU version for broader compatibility
10. **Virtual Environment Strategy**: Each reference notebook project should use its own isolated virtual environment with exact package versions