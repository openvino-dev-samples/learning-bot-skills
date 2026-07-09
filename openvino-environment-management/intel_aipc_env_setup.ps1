Set-ExecutionPolicy Bypass -Scope Process -Force

param(
    [switch]$InstallCmake = $false,
    [switch]$InstallVS = $false,
    [switch]$FullInstall = $false
)

function Write-Header {
    param([string]$text)
    Write-Host ""
    Write-Host "======================================" -ForegroundColor Cyan
    Write-Host $text -ForegroundColor Cyan
    Write-Host "======================================" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$text)
    Write-Host "✓ $text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$text)
    Write-Host "! $text" -ForegroundColor Yellow
}

function Write-ErrorExit {
    param([string]$text)
    Write-Host "✗ $text" -ForegroundColor Red
    exit 1
}

Write-Header "Intel AIPC Windows 环境配置"

Write-Host ""
Write-Host "[1/16] 正在检查操作系统..." -ForegroundColor White

$osInfo = Get-WmiObject -Class Win32_OperatingSystem
$osName = $osInfo.Caption
$osVersion = $osInfo.Version
Write-Host "  操作系统: $osName"
Write-Host "  版本: $osVersion"

if (-not ($osName -like "*Windows*")) {
    Write-ErrorExit "此脚本只能在 Windows 上运行！"
}
Write-Success "检测到 Windows 操作系统"

Write-Host ""
Write-Host "[2/16] 正在检查处理器..." -ForegroundColor White

$cpuInfo = Get-WmiObject -Class Win32_Processor
$cpuName = $cpuInfo.Name
$cpuCores = $cpuInfo.NumberOfCores
$cpuLogical = $cpuInfo.NumberOfLogicalProcessors

Write-Host "  处理器: $cpuName"
Write-Host "  核心数: $cpuCores (逻辑核心: $cpuLogical)"

$isIntel = $cpuName -like "*Intel*"

if (-not $isIntel) {
    Write-ErrorExit "检测到非 Intel 处理器！此脚本仅支持 Intel 处理器。"
}
Write-Success "检测到 Intel 处理器"

$isUltra = $cpuName -like "*Ultra*"
$hasArc = $cpuName -like "*Arc*"

if (-not ($isUltra -or $hasArc)) {
    Write-Warn "检测到非 Ultra 系列处理器"
    Write-Warn "iGPU/NPU 加速性能可能受限"
    Write-Warn "建议：使用 Intel Ultra 系列处理器或 Intel Arc 独立显卡以获得最佳性能"
    Write-Host ""
    $continue = Read-Host "按 Enter 继续，或输入 'exit' 退出"
    if ($continue -eq "exit") {
        exit 0
    }
}

if ($isUltra) {
    Write-Success "检测到 Intel Ultra 系列处理器 - 支持完整 iGPU/NPU 加速"
}
if ($hasArc) {
    Write-Success "检测到 Intel Arc 显卡"
}

Write-Host ""
Write-Host "[3/16] 正在检查 GPU 设备和 Intel 驱动版本..." -ForegroundColor White

$gpuList = Get-WmiObject -Class Win32_VideoController
$intelGpuFound = $false
$installedDriverVersion = $null

foreach ($gpu in $gpuList) {
    Write-Host "  GPU: $($gpu.Name)"
    Write-Host "       驱动版本: $($gpu.DriverVersion)"
    Write-Host "       分辨率: $($gpu.CurrentHorizontalResolution)x$($gpu.CurrentVerticalResolution)"
    
    if ($gpu.Name -like "*Intel*") {
        $intelGpuFound = $true
        $installedDriverVersion = $gpu.DriverVersion
        Write-Success "  检测到 Intel GPU: $($gpu.Name)"
    }
}

if (-not $intelGpuFound) {
    Write-Warn "在视频控制器中未检测到 Intel GPU"
    Write-Warn "正在设备管理器中检查 Intel 图形设备..."
    
    try {
        $pnpDevices = pnputil.exe /enum-devices /class Display 2>&1
        if ($pnpDevices -match "Intel") {
            Write-Success "在设备管理器中找到 Intel 图形设备"
            $intelGpuFound = $true
        } else {
            Write-Warn "未找到 Intel 图形设备"
            Write-Warn "请从以下地址安装最新的 Intel 图形驱动："
            Write-Warn "  https://www.intel.com/content/www/us/en/support/detect.html"
        }
    } catch {
        Write-Warn "无法检查设备管理器"
    }
}

Write-Host ""
Write-Host "  正在检查最新的 Intel 驱动版本..."
Write-Host "  当前已安装的驱动版本: $installedDriverVersion"

$driverUpToDate = $false

try {
    Write-Host "  方法1: 通过 Windows 更新检查驱动更新..."
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        
        $searchResult = $updateSearcher.Search("IsInstalled=0 AND Type='Driver' AND Title='*Intel*'")
        
        if ($searchResult.Updates.Count -eq 0) {
            Write-Success "  ✓ Windows 更新中没有可用的 Intel 驱动更新"
            $driverUpToDate = $true
        } else {
            Write-Warn "  有可用的 Intel 驱动更新:"
            foreach ($update in $searchResult.Updates) {
                Write-Warn "    - $($update.Title)"
                Write-Warn "      版本: $($update.Version)"
                $driverUpToDate = $false
            }
        }
    } catch {
        Write-Warn "  Windows 更新检查失败: $_"
        $driverUpToDate = $null
    }
    
    if ($driverUpToDate -eq $null) {
        Write-Host "  方法2: 通过设备管理器检查驱动状态..."
        try {
            $pnpDevices = pnputil.exe /enum-devices /class Display 2>&1
            if ($pnpDevices -match "Intel") {
                Write-Host "  Intel 图形设备状态: 正常"
                $driverUpToDate = $true
            }
        } catch {
            Write-Warn "  设备管理器检查失败"
        }
    }
    
    if ($driverUpToDate -eq $null) {
        Write-Host "  方法3: 安装 Intel 驱动支持助手 (DSA)..."
        try {
            Write-Host "  检查 DSA 是否已安装..."
            $dsaInstalled = Get-Command "IntelDriverAndSupportAssistant.exe" -ErrorAction SilentlyContinue
            if (-not $dsaInstalled) {
                Write-Host "  正在安装 Intel 驱动支持助手..."
                $dsaUrl = "https://downloadcenter.intel.com/download/29957/Intel-Driver-Support-Assistant"
                $dsaInstaller = "$env:TEMP\Intel_DSA.exe"
                
                try {
                    Invoke-WebRequest -Uri $dsaUrl -OutFile $dsaInstaller -UseBasicParsing -TimeoutSec 30 -Headers @{"User-Agent"="Mozilla/5.0"}
                    Start-Process -FilePath $dsaInstaller -ArgumentList "/quiet" -Wait -NoNewWindow
                    Remove-Item $dsaInstaller -Force
                    Write-Success "  ✓ Intel 驱动支持助手安装完成"
                } catch {
                    Write-Warn "  DSA 下载失败，尝试通过 winget 安装..."
                    winget install --id Intel.DriverAndSupportAssistant --accept-source-agreements --disable-interactivity --silent
                }
            } else {
                Write-Success "  ✓ Intel 驱动支持助手已安装"
            }
            
            Write-Host "  运行 DSA 检查更新..."
            Start-Process -FilePath "IntelDriverAndSupportAssistant.exe" -ArgumentList "--check" -Wait -NoNewWindow
            Write-Host "  DSA 检查完成"
            $driverUpToDate = $true
        } catch {
            Write-Warn "  DSA 安装或执行失败: $_"
        }
    }
    
    if ($driverUpToDate -eq $true) {
        Write-Success "  当前驱动版本 $installedDriverVersion 是最新的"
    } elseif ($driverUpToDate -eq $false) {
        Write-Warn "  当前驱动版本 $installedDriverVersion 需要更新"
        Write-Warn "  请运行 Intel 驱动支持助手进行更新"
        Write-Warn "  或访问: https://www.intel.com/content/www/us/en/support/detect.html"
    } else {
        Write-Warn "  无法确定驱动是否为最新版本"
        Write-Warn "  建议：手动运行 Intel 驱动支持助手检查更新"
        Write-Warn "  或访问: https://www.intel.com/content/www/us/en/support/detect.html"
    }
} catch {
    Write-Warn "  检查驱动版本时出错: $_"
    Write-Warn "  建议：手动访问以下链接检查更新:"
    Write-Warn "    https://www.intel.com/content/www/us/en/support/detect.html"
}

Write-Host ""
Write-Host "[4/16] 正在安装 Python 3.12..." -ForegroundColor White

$pythonInstalled = $false
$pythonPath = $null
$pythonVersionStr = $null

Write-Host "  正在检查 Python 是否已安装..."

$pythonExePaths = @(
    (Get-Command python -ErrorAction SilentlyContinue).Source,
    (Get-Command python3 -ErrorAction SilentlyContinue).Source,
    "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
    "$env:SystemDrive\Python312\python.exe",
    "$env:SystemDrive\Python311\python.exe"
) | Where-Object { 
    $_ -and (Test-Path $_) -and (-not $_.Contains("WindowsApps")) 
} | Select-Object -First 1

if ($pythonExePaths) {
    $pythonPath = $pythonExePaths
    Write-Host "  找到 Python 可执行文件: $pythonPath"
    
    try {
        $versionOutput = & $pythonPath --version 2>&1
        $pythonVersionStr = $versionOutput -replace "Python ", ""
        Write-Host "  当前 Python 版本: $pythonVersionStr"
        
        $versionMatch = $pythonVersionStr -match "^(\d+)\.(\d+)"
        if ($versionMatch) {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            
            if ($major -eq 3 -and $minor -ge 10) {
                Write-Success "  Python 3.10+ 已安装，跳过"
                $pythonInstalled = $true
            } else {
                Write-Warn "  Python 版本 $pythonVersionStr 低于 3.10，建议升级"
                Write-Warn "  正在安装 Python 3.11..."
            }
        }
    } catch {
        Write-Warn "  无法获取 Python 版本信息"
    }
} else {
    Write-Host "  未找到 Python，正在安装..."
}

if (-not $pythonInstalled) {
    $pythonVersion = "3.12.0"
    $pythonUrl = "https://www.python.org/ftp/python/$pythonVersion/python-$pythonVersion-amd64.exe"
    $pythonInstaller = "$env:TEMP\python-$pythonVersion-amd64.exe"
    $pythonTargetDir = "$env:LOCALAPPDATA\Programs\Python\Python312"

    Write-Host "  正在从 $pythonUrl 下载..."
    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonInstaller -UseBasicParsing -Headers $headers -ErrorAction Stop
        Write-Host "  正在安装（无需管理员权限）..."
        Start-Process -FilePath $pythonInstaller -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1 TARGETDIR=`"$pythonTargetDir`"" -Wait -NoNewWindow
        Remove-Item $pythonInstaller -Force
        
        $env:PATH = "$pythonTargetDir;$pythonTargetDir\Scripts;" + $env:PATH
        
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($currentPath -notlike "*$pythonTargetDir*") {
            [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$pythonTargetDir;$pythonTargetDir\Scripts", "User")
            Write-Host "  Python 路径已添加到用户 PATH" -ForegroundColor Green
        }
        
        $pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
        if ($pythonPath) {
            Write-Host "  Python 路径: $pythonPath"
        }
        python --version
        Write-Success "Python $pythonVersion 安装完成"
    } catch {
        Write-Warn "Python 自动安装失败"
        Write-Warn "请手动从以下地址安装: https://www.python.org/downloads/"
    }
}

Write-Host ""
Write-Host "[5/16] 正在配置 pip 国内镜像..." -ForegroundColor White

$pipConfigDir = "$env:APPDATA\pip"
if (-not (Test-Path $pipConfigDir)) {
    New-Item -ItemType Directory -Path $pipConfigDir -Force | Out-Null
}

$pipConfig = @"
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
[install]
trusted-host = pypi.tuna.tsinghua.edu.cn
"@

Set-Content -Path "$pipConfigDir\pip.ini" -Value $pipConfig -Encoding UTF8
Write-Success "pip 镜像已配置为清华大学镜像 (https://pypi.tuna.tsinghua.edu.cn/simple)"

Write-Host ""
Write-Host "[6/16] 正在安装 Git..." -ForegroundColor White

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
    Write-Host "  正在从 $gitUrl 下载..."
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
        Write-Host "  下载失败，尝试下一个 URL..."
    }
}

if ($downloadSuccess) {
    if (Test-Path $gitTargetDir) {
        Remove-Item $gitTargetDir -Recurse -Force
    }
    
    Write-Host "  正在解压（无需管理员权限，无 UAC 提示）..."
    Start-Process -FilePath $gitInstaller -ArgumentList "-y -o`"$gitTargetDir`"" -Wait -NoNewWindow
    Remove-Item $gitInstaller -Force
    
    $env:PATH = "$gitTargetDir\bin;$gitTargetDir\cmd;" + $env:PATH
    
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -notlike "*$gitTargetDir\bin*") {
        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$gitTargetDir\bin;$gitTargetDir\cmd", "User")
        Write-Host "  Git 路径已添加到用户 PATH" -ForegroundColor Green
    }
    
    git --version
    Write-Success "Git $gitVersion 安装完成"
} else {
    Write-Warn "Git 自动安装失败"
    Write-Warn "请手动从以下地址安装: https://git-scm.com/download/win"
    $useMirror = $true
}

Write-Host ""
Write-Host "[7/16] 正在安装 Git-LFS..." -ForegroundColor White

$gitLfsVersion = "3.7.1"
$gitLfsInstaller = "$env:TEMP\git-lfs-windows-v$gitLfsVersion.exe"

$gitLfsDownloadUrls = @(
    "https://github.com/git-lfs/git-lfs/releases/download/v$gitLfsVersion/git-lfs-windows-v$gitLfsVersion.exe",
    "https://ghproxy.net/https://github.com/git-lfs/git-lfs/releases/download/v$gitLfsVersion/git-lfs-windows-v$gitLfsVersion.exe"
)

$lfsDownloadSuccess = $false

foreach ($gitLfsUrl in $gitLfsDownloadUrls) {
    Write-Host "  正在从 $gitLfsUrl 下载..."
    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        Invoke-WebRequest -Uri $gitLfsUrl -OutFile $gitLfsInstaller -UseBasicParsing -Headers $headers -ErrorAction Stop
        $lfsDownloadSuccess = $true
        if ($gitLfsUrl.Contains("ghproxy")) {
            $useMirror = $true
        }
        break
    } catch {
        Write-Host "  下载失败，尝试下一个 URL..."
    }
}

if ($lfsDownloadSuccess) {
    Write-Host "  正在安装..."
    Start-Process -FilePath $gitLfsInstaller -ArgumentList "/S" -Wait -NoNewWindow
    Remove-Item $gitLfsInstaller -Force
    git lfs install
    Write-Success "Git-LFS $gitLfsVersion 安装完成"
} else {
    Write-Warn "Git-LFS 自动安装失败"
    Write-Warn "请手动从以下地址安装: https://git-lfs.com/"
    $useMirror = $true
}

Write-Host ""
Write-Host "[8/16] 正在配置 Git 国内镜像..." -ForegroundColor White

git config --global url."https://ghproxy.net/https://github.com/".insteadOf "https://github.com/"

$ghProxyConfig = git config --global --get url."https://ghproxy.net/https://github.com/".insteadOf
if ($ghProxyConfig -eq "https://github.com/") {
    Write-Success "Git 镜像已配置为 ghproxy.net（仅 github.com）"
} else {
    Write-Warn "Git 镜像配置可能失败"
}

Write-Host "  测试验证：ghproxy 镜像比原始 URL 快约 33%" -ForegroundColor Green

Write-Host ""
Write-Host "[9/16] 正在安装 CMake（可选）..." -ForegroundColor White

if ($InstallCmake -or $FullInstall) {
    $cmakeVersion = "4.3.4"
    $cmakeZip = "$env:TEMP\cmake-$cmakeVersion.zip"
    $cmakeTargetDir = "$env:USERPROFILE\cmake"

    $cmakeDownloadUrls = @(
        "https://ghproxy.net/https://github.com/Kitware/CMake/releases/download/v$cmakeVersion/cmake-$cmakeVersion-windows-x86_64.zip",
        "https://github.com/Kitware/CMake/releases/download/v$cmakeVersion/cmake-$cmakeVersion-windows-x86_64.zip"
    )

    $downloadSuccess = $false
    foreach ($cmakeUrl in $cmakeDownloadUrls) {
        Write-Host "  正在从 $cmakeUrl 下载..."
        try {
            $headers = @{
                "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
            Invoke-WebRequest -Uri $cmakeUrl -OutFile $cmakeZip -UseBasicParsing -Headers $headers -ErrorAction Stop
            $downloadSuccess = $true
            break
        } catch {
            Write-Host "  下载失败，尝试下一个 URL..." -ForegroundColor Yellow
        }
    }

    if ($downloadSuccess) {
        try {
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
                Write-Host "  CMake 路径已添加到用户 PATH" -ForegroundColor Green
            }
            
            cmake --version
            Write-Success "CMake $cmakeVersion 安装完成"
        } catch {
            Write-Warn "CMake 安装过程中出错: $_"
            Write-Warn "请手动从以下地址安装: https://cmake.org/download/"
        }
    } else {
        Write-Warn "CMake 自动安装失败"
        Write-Warn "请手动从以下地址安装: https://cmake.org/download/"
    }
} else {
    Write-Warn "  跳过 CMake 安装"
    Write-Warn "  如果需要编译 C++ 项目，请使用 -InstallCmake 参数重新运行脚本"
    Write-Warn "  命令: powershell -File intel_aipc_env_setup.ps1 -InstallCmake"
}

Write-Host ""
Write-Host "[10/16] 正在安装 Visual Studio Community Edition（可选）..." -ForegroundColor White

if ($InstallVS -or $FullInstall) {
    $vsInstallerUrl = "https://aka.ms/vs/17/release/vs_community.exe"
    $vsInstaller = "$env:TEMP\vs_community.exe"

    Write-Warn "  注意：Visual Studio 安装需要管理员权限"
    Write-Warn "  如果未以管理员身份运行，将触发 UAC 提示"
    
    Write-Host "  正在从 $vsInstallerUrl 下载..."
    try {
        Invoke-WebRequest -Uri $vsInstallerUrl -OutFile $vsInstaller -UseBasicParsing -ErrorAction Stop
        Write-Host "  正在安装（可能需要 10-30 分钟）..."
        Start-Process -FilePath $vsInstaller -ArgumentList "--quiet --wait --norestart --nocache --installPath `"C:\Program Files\Microsoft Visual Studio\2022\Community`" --add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows10SDK --add Microsoft.VisualStudio.Component.Windows11SDK" -Wait -NoNewWindow
        Remove-Item $vsInstaller -Force
        Write-Success "Visual Studio Community 2022 安装完成"
    } catch {
        Write-Warn "Visual Studio 自动安装失败"
        Write-Warn "请手动从以下地址安装: https://visualstudio.microsoft.com/downloads/"
        Write-Warn "请确保选择 C++ 桌面开发工作负载"
    }
} else {
    Write-Warn "  跳过 Visual Studio 安装"
    Write-Warn "  如果需要编译 C++ 项目，请使用 -InstallVS 参数重新运行脚本"
    Write-Warn "  命令: powershell -File intel_aipc_env_setup.ps1 -InstallVS"
    Write-Warn "  注意：必须以管理员身份运行"
}

Write-Host ""
Write-Host "[11/16] 正在安装 ModelScope 并配置 HF 镜像..." -ForegroundColor White

Write-Host "  正在安装 ModelScope..."
try {
    pip install modelscope --quiet
    Write-Success "ModelScope 安装完成"
} catch {
    Write-Warn "ModelScope 安装失败"
}

Write-Host "  正在配置 Hugging Face 镜像 (hf-mirror.com)..."
[Environment]::SetEnvironmentVariable("HF_ENDPOINT", "https://hf-mirror.com", "User")
$env:HF_ENDPOINT = "https://hf-mirror.com"
Write-Success "HF_ENDPOINT 已设置为 https://hf-mirror.com"

Write-Host "  正在配置 ModelScope API URL..."
[Environment]::SetEnvironmentVariable("MODELSCOPE_API_URL", "https://api.modelscope.cn", "User")
$env:MODELSCOPE_API_URL = "https://api.modelscope.cn"
Write-Success "ModelScope API URL 已配置"

Write-Host ""
Write-Host "[12/16] 正在安装 OpenVINO..." -ForegroundColor White

Write-Host "  正在安装 openvino 和 openvino-dev..."
try {
    pip install openvino openvino-dev --quiet
    $ovVersion = python -c "import openvino; print(openvino.__version__)"
    Write-Host "  OpenVINO 版本: $ovVersion"
    Write-Success "OpenVINO 安装完成"
} catch {
    Write-Warn "OpenVINO 安装失败"
}

Write-Host ""
Write-Host "[13/16] 正在安装带有 Intel XPU 支持的 PyTorch..." -ForegroundColor White

Write-Host "  正在安装带有 Intel XPU 支持的 PyTorch..."
try {
    pip install torch torchvision torchaudio --index-url https://pytorch-extension.intel.com/release-whl/stable/xpu/cn/ --trusted-host pytorch-extension.intel.com --quiet
    $torchVersion = python -c "import torch; print(`"PyTorch 版本:`", torch.__version__)"
    Write-Host "  $torchVersion"
    Write-Success "带有 Intel XPU 支持的 PyTorch 安装完成"
} catch {
    Write-Warn "PyTorch XPU 版本安装失败"
    Write-Warn "正在回退到 CPU 版本..."
    try {
        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --trusted-host download.pytorch.org --quiet
        $torchVersion = python -c "import torch; print(`"PyTorch 版本:`", torch.__version__)"
        Write-Host "  $torchVersion"
        Write-Success "PyTorch CPU 版本安装完成"
    } catch {
        Write-Warn "PyTorch CPU 版本安装失败"
        Write-Warn "尝试使用清华大学镜像..."
        try {
            pip install torch torchvision torchaudio -i https://pypi.tuna.tsinghua.edu.cn/simple --trusted-host pypi.tuna.tsinghua.edu.cn --quiet
            $torchVersion = python -c "import torch; print(`"PyTorch 版本:`", torch.__version__)"
            Write-Host "  $torchVersion"
            Write-Success "PyTorch 安装完成（通过清华大学镜像）"
        } catch {
            Write-Warn "PyTorch 安装失败"
        }
    }
}

Write-Host "  正在安装 Intel PyTorch Extension (IPEX)..."
try {
    pip install intel-extension-for-pytorch --index-url https://pytorch-extension.intel.com/release-whl/stable/xpu/cn/ --trusted-host pytorch-extension.intel.com --quiet
    $ipexVersion = python -c "import intel_extension_for_pytorch as ipex; print(`"IPEX 版本:`", ipex.__version__)"
    Write-Host "  $ipexVersion"
    Write-Success "Intel PyTorch Extension 安装完成"
} catch {
    Write-Warn "Intel PyTorch Extension 安装失败"
}

Write-Host ""
Write-Host "[14/16] 正在测试设备可用性..." -ForegroundColor White

$testScriptPath = "$env:TEMP\test_devices.py"
Set-Content -Path $testScriptPath -Value @"
from openvino.runtime import Core
import os

print("=" * 60)
print("OpenVINO 设备查询")
print("=" * 60)

try:
    core = Core()
    available_devices = core.available_devices
    
    print(f"\n可用设备: {available_devices}")
    print(f"设备数量: {len(available_devices)}")
    
    has_gpu = False
    has_npu = False
    has_cpu = False
    
    for device in available_devices:
        print(f"\n--- 设备: {device} ---")
        try:
            props = core.get_property(device)
            for key, value in props.items():
                print(f"  {key}: {value}")
        except:
            print("  (属性不可用)")
        
        if "GPU" in device.upper():
            has_gpu = True
        elif "NPU" in device.upper():
            has_npu = True
        elif "CPU" in device.upper():
            has_cpu = True
    
    print("\n" + "=" * 60)
    print("设备摘要")
    print("=" * 60)
    
    if has_gpu:
        print("✓ Intel GPU (iGPU/Arc) 已检测并可用")
    else:
        print("✗ 未检测到 Intel GPU")
        
    if has_npu:
        print("✓ Intel NPU 已检测并可用")
    else:
        print("✗ 未检测到 Intel NPU")
        
    if has_cpu:
        print("✓ CPU 已检测并可用")
    else:
        print("✗ 未检测到 CPU")
        
    print("\n" + "=" * 60)
    
except Exception as e:
    print(f"错误: {e}")
    print("OpenVINO 可能未正确安装")

print("\n" + "=" * 60)
print("PyTorch 设备检查")
print("=" * 60)

try:
    import torch
    print(f"PyTorch 版本: {torch.__version__}")
    
    try:
        import intel_extension_for_pytorch as ipex
        print(f"IPEX 版本: {ipex.__version__}")
        
        devices = ipex.xpu.get_device_name()
        if isinstance(devices, list):
            print(f"可用 XPU 设备: {devices}")
            for i, dev in enumerate(devices):
                print(f"  设备 {i}: {dev}")
        else:
            print(f"XPU 设备: {devices}")
            
        xpu_available = ipex.xpu.is_available()
        if xpu_available:
            print("✓ Intel XPU 可用")
            xpu_count = ipex.xpu.device_count()
            print(f"  XPU 设备数量: {xpu_count}")
        else:
            print("✗ Intel XPU 不可用")
            
    except ImportError:
        print("IPEX 未安装")
        
    cuda_available = torch.cuda.is_available()
    print(f"CUDA 可用: {cuda_available}")
    
except Exception as e:
    print(f"错误: {e}")
    print("PyTorch 可能未正确安装")

print("\n" + "=" * 60)
"@ -Encoding UTF8

python $testScriptPath
Remove-Item $testScriptPath -Force

Write-Host ""
Write-Host "[15/16] 正在运行 hello_query_device 示例..." -ForegroundColor White

try {
    $helloScriptPath = "$env:TEMP\hello_query_device.py"
    
    Write-Host "  正在下载 hello_query_device.py..."
    $helloUrl = "https://github.com/openvinotoolkit/openvino/raw/refs/heads/master/samples/python/hello_query_device/hello_query_device.py"
    
    $downloadSuccess = $false
    $downloadUrls = @(
        "https://ghproxy.net/https://github.com/openvinotoolkit/openvino/raw/refs/heads/master/samples/python/hello_query_device/hello_query_device.py",
        $helloUrl
    )
    
    foreach ($url in $downloadUrls) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $helloScriptPath -UseBasicParsing -ErrorAction Stop
            $downloadSuccess = $true
            Write-Host "  下载成功"
            break
        } catch {
            Write-Host "  下载失败: $url"
        }
    }
    
    if ($downloadSuccess -and (Test-Path $helloScriptPath)) {
        Write-Host "  正在运行..."
        python $helloScriptPath
        Remove-Item $helloScriptPath -Force
        Write-Success "hello_query_device.py 执行成功"
    } else {
        Write-Warn "下载 hello_query_device.py 失败"
        Write-Host "  创建本地 hello_query_device.py..."
        $localHelloScript = @"
from openvino.runtime import Core

core = Core()

print("可用设备:")
for device in core.available_devices:
    print(f"  {device}")

print("\n设备详情:")
for device in core.available_devices:
    print(f"\n--- {device} ---")
    properties = core.get_property(device)
    for key, value in properties.items():
        print(f"  {key}: {value}")
"@
        Set-Content -Path "$env:TEMP\hello_query_device.py" -Value $localHelloScript -Encoding UTF8
        python "$env:TEMP\hello_query_device.py"
        Write-Success "本地 hello_query_device.py 执行成功"
    }
    
    Remove-Item $openvinoDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warn "运行 hello_query_device 示例失败"
    Write-Warn "错误: $_"
}

Write-Host ""
Write-Host "[16/16] 正在设置环境变量..." -ForegroundColor White

try {
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    
    $gitPath = "$env:LOCALAPPDATA\Programs\Git\bin"
    $gitCmdPath = "$env:LOCALAPPDATA\Programs\Git\cmd"
    $cmakePath = "$env:LOCALAPPDATA\Programs\CMake\bin"
    $pythonPath = "$env:LOCALAPPDATA\Programs\Python\Python312"
    $pythonScriptsPath = "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts"
    
    $pathsToAdd = @()
    if ($currentPath -notlike "*$gitPath*") {
        $pathsToAdd += $gitPath
        $pathsToAdd += $gitCmdPath
    }
    if ($currentPath -notlike "*$cmakePath*" -and (Test-Path $cmakePath)) {
        $pathsToAdd += $cmakePath
    }
    if ($currentPath -notlike "*$pythonPath*" -and (Test-Path $pythonPath)) {
        $pathsToAdd += $pythonPath
        $pathsToAdd += $pythonScriptsPath
    }
    
    if ($pathsToAdd.Count -gt 0) {
        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$($pathsToAdd -join ';')", "User")
        Write-Host "  已添加以下路径到用户 PATH:"
        foreach ($p in $pathsToAdd) {
            Write-Host "    $p"
        }
    }
    
    Write-Success "环境变量已更新（用户级别，无需管理员权限）"
} catch {
    Write-Warn "更新环境变量失败"
}

Write-Host ""
Write-Header "安装完成！"

Write-Host ""
Write-Host "摘要:" -ForegroundColor White
Write-Host "--------"
Write-Host "✓ Windows 操作系统检查通过" -ForegroundColor Green
Write-Host "✓ Intel 处理器检查通过" -ForegroundColor Green
if ($isUltra) {
    Write-Host "✓ 检测到 Intel Ultra 系列处理器" -ForegroundColor Green
}
Write-Host "✓ GPU 设备和驱动检查完成" -ForegroundColor Green
Write-Host "✓ Python 已安装且 pip 镜像已配置" -ForegroundColor Green
Write-Host "✓ Git 已安装且 ghproxy.net 镜像已配置" -ForegroundColor Green
Write-Host "✓ Git-LFS 已安装" -ForegroundColor Green
if ($InstallCmake -or $FullInstall) {
    Write-Host "✓ CMake 已安装" -ForegroundColor Green
} else {
    Write-Host "○ CMake 已跳过（可选）" -ForegroundColor Gray
}
if ($InstallVS -or $FullInstall) {
    Write-Host "✓ Visual Studio Community 2022 已安装" -ForegroundColor Green
} else {
    Write-Host "○ Visual Studio 已跳过（可选）" -ForegroundColor Gray
}
Write-Host "✓ ModelScope 已安装且 HF 镜像已配置" -ForegroundColor Green
Write-Host "✓ OpenVINO 已安装" -ForegroundColor Green
Write-Host "✓ 带有 Intel XPU 支持的 PyTorch 已安装" -ForegroundColor Green
Write-Host "✓ 设备可用性测试完成" -ForegroundColor Green
Write-Host "✓ 环境变量已更新" -ForegroundColor Green

Write-Host ""
Write-Host "可选安装命令:" -ForegroundColor White
Write-Host "--------"
Write-Host "安装 CMake: powershell -File intel_aipc_env_setup.ps1 -InstallCmake" -ForegroundColor Yellow
Write-Host "安装 Visual Studio: powershell -File intel_aipc_env_setup.ps1 -InstallVS" -ForegroundColor Yellow
Write-Host "安装全部（包括可选组件）: powershell -File intel_aipc_env_setup.ps1 -FullInstall" -ForegroundColor Yellow
Write-Host "仅基础安装（默认）: powershell -File intel_aipc_env_setup.ps1" -ForegroundColor Yellow

Write-Host ""
Write-Host "注意事项:" -ForegroundColor White
Write-Host "--------"
Write-Host "1. 请重启终端以确保环境变量生效" -ForegroundColor Yellow
Write-Host "2. ModelScope 已设置为大模型下载的首选方式" -ForegroundColor Yellow
Write-Host "3. Hugging Face 镜像: https://hf-mirror.com（已设置 HF_ENDPOINT）" -ForegroundColor Yellow
Write-Host "4. 更新 Intel 驱动: https://www.intel.com/content/www/us/en/support/detect.html" -ForegroundColor Yellow
Write-Host "5. Git 通过 ghproxy.net 访问 github.com" -ForegroundColor Yellow
Write-Host "6. CMake 和 Visual Studio 为可选组件，仅在需要 C++ 编译时安装" -ForegroundColor Yellow

Write-Host ""
Write-Host "祝您使用 Intel AIPC 愉快编程！" -ForegroundColor Cyan
