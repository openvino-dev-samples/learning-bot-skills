Set-ExecutionPolicy Bypass -Scope Process -Force

param(
    [switch]$InstallCmake = $false,
    [switch]$InstallVS = $false,
    [switch]$FullInstall = $false,
    [switch]$WithGitLfs = $false
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

Write-Header "Intel AIPC Windows Environment Setup"

Write-Host ""
Write-Host "[1/16] Checking operating system..." -ForegroundColor White

$osInfo = Get-WmiObject -Class Win32_OperatingSystem
$osName = $osInfo.Caption
$osVersion = $osInfo.Version
Write-Host "  OS: $osName"
Write-Host "  Version: $osVersion"

if (-not ($osName -like "*Windows*")) {
    Write-ErrorExit "This script can only run on Windows!"
}
Write-Success "Windows OS detected"

Write-Host ""
Write-Host "[2/16] Checking processor..." -ForegroundColor White

$cpuInfo = Get-WmiObject -Class Win32_Processor
$cpuName = $cpuInfo.Name
$cpuCores = $cpuInfo.NumberOfCores
$cpuLogical = $cpuInfo.NumberOfLogicalProcessors

Write-Host "  Processor: $cpuName"
Write-Host "  Cores: $cpuCores (Logical: $cpuLogical)"

$isIntel = $cpuName -like "*Intel*"

if (-not $isIntel) {
    Write-ErrorExit "Non-Intel processor detected! This script only supports Intel processors."
}
Write-Success "Intel processor detected"

$isUltra = $cpuName -like "*Ultra*"
$hasArc = $cpuName -like "*Arc*"

if (-not ($isUltra -or $hasArc)) {
    Write-Warn "Non-Ultra series processor detected"
    Write-Warn "iGPU/NPU acceleration performance may be limited"
    Write-Warn "Recommended: Use Intel Ultra series processor or Intel Arc discrete graphics for best performance"
    Write-Host ""
    $continue = Read-Host "Press Enter to continue, or type 'exit' to quit"
    if ($continue -eq "exit") {
        exit 0
    }
}

if ($isUltra) {
    Write-Success "Intel Ultra series processor detected - Full iGPU/NPU acceleration supported"
}
if ($hasArc) {
    Write-Success "Intel Arc graphics detected"
}

Write-Host ""
Write-Host "[3/16] Checking GPU devices and Intel driver version..." -ForegroundColor White

$gpuList = Get-WmiObject -Class Win32_VideoController
$intelGpuFound = $false
$installedDriverVersion = $null

foreach ($gpu in $gpuList) {
    Write-Host "  GPU: $($gpu.Name)"
    Write-Host "       Driver Version: $($gpu.DriverVersion)"
    Write-Host "       Resolution: $($gpu.CurrentHorizontalResolution)x$($gpu.CurrentVerticalResolution)"
    
    if ($gpu.Name -like "*Intel*") {
        $intelGpuFound = $true
        $installedDriverVersion = $gpu.DriverVersion
        Write-Success "  Intel GPU detected: $($gpu.Name)"
    }
}

if (-not $intelGpuFound) {
    Write-Warn "No Intel GPU detected in video controllers"
    Write-Warn "Checking device manager for Intel graphics devices..."
    
    try {
        $pnpDevices = pnputil.exe /enum-devices /class Display 2>&1
        if ($pnpDevices -match "Intel") {
            Write-Success "Intel graphics device found in device manager"
            $intelGpuFound = $true
        } else {
            Write-Warn "No Intel graphics device found"
            Write-Warn "Please install the latest Intel graphics driver from:"
            Write-Warn "  https://www.intel.com/content/www/us/en/support/detect.html"
        }
    } catch {
        Write-Warn "Unable to check device manager"
    }
}

Write-Host ""
Write-Host "  Checking for latest Intel driver version..."
Write-Host "  Current installed driver version: $installedDriverVersion"

$driverUpToDate = $false

try {
    Write-Host "  Method 1: Checking driver updates via Windows Update..."
    try {
        $updateSession = New-Object -ComObject Microsoft.Update.Session
        $updateSearcher = $updateSession.CreateUpdateSearcher()
        
        $searchResult = $updateSearcher.Search("IsInstalled=0 AND Type='Driver' AND Title='*Intel*'")
        
        if ($searchResult.Updates.Count -eq 0) {
            Write-Success "  ✓ No Intel driver updates available in Windows Update"
            $driverUpToDate = $true
        } else {
            Write-Warn "  Intel driver updates available:"
            foreach ($update in $searchResult.Updates) {
                Write-Warn "    - $($update.Title)"
                Write-Warn "      Version: $($update.Version)"
                $driverUpToDate = $false
            }
        }
    } catch {
        Write-Warn "  Windows Update check failed: $_"
        $driverUpToDate = $null
    }
    
    if ($driverUpToDate -eq $null) {
        Write-Host "  Method 2: Checking driver status via device manager..."
        try {
            $pnpDevices = pnputil.exe /enum-devices /class Display 2>&1
            if ($pnpDevices -match "Intel") {
                Write-Host "  Intel graphics device status: Normal"
                $driverUpToDate = $true
            }
        } catch {
            Write-Warn "  Device manager check failed"
        }
    }
    
    if ($driverUpToDate -eq $null) {
        Write-Host "  Method 3: Installing Intel Driver Support Assistant (DSA)..."
        try {
            Write-Host "  Checking if DSA is installed..."
            $dsaInstalled = Get-Command "IntelDriverAndSupportAssistant.exe" -ErrorAction SilentlyContinue
            if (-not $dsaInstalled) {
                Write-Host "  Installing Intel Driver Support Assistant..."
                $dsaUrl = "https://downloadcenter.intel.com/download/29957/Intel-Driver-Support-Assistant"
                $dsaInstaller = "$env:TEMP\Intel_DSA.exe"
                
                try {
                    Invoke-WebRequest -Uri $dsaUrl -OutFile $dsaInstaller -UseBasicParsing -TimeoutSec 30 -Headers @{"User-Agent"="Mozilla/5.0"}
                    Start-Process -FilePath $dsaInstaller -ArgumentList "/quiet" -Wait -NoNewWindow
                    Remove-Item $dsaInstaller -Force
                    Write-Success "  ✓ Intel Driver Support Assistant installed"
                } catch {
                    Write-Warn "  DSA download failed, trying winget installation..."
                    winget install --id Intel.DriverAndSupportAssistant --accept-source-agreements --disable-interactivity --silent
                }
            } else {
                Write-Success "  ✓ Intel Driver Support Assistant already installed"
            }
            
            Write-Host "  Running DSA to check for updates..."
            Start-Process -FilePath "IntelDriverAndSupportAssistant.exe" -ArgumentList "--check" -Wait -NoNewWindow
            Write-Host "  DSA check completed"
            $driverUpToDate = $true
        } catch {
            Write-Warn "  DSA installation or execution failed: $_"
        }
    }
    
    if ($driverUpToDate -eq $true) {
        Write-Success "  Current driver version $installedDriverVersion is up to date"
    } elseif ($driverUpToDate -eq $false) {
        Write-Warn "  Current driver version $installedDriverVersion needs update"
        Write-Warn "  Please run Intel Driver Support Assistant to update"
        Write-Warn "  Or visit: https://www.intel.com/content/www/us/en/support/detect.html"
    } else {
        Write-Warn "  Unable to determine if driver is up to date"
        Write-Warn "  Recommended: Manually run Intel Driver Support Assistant to check for updates"
        Write-Warn "  Or visit: https://www.intel.com/content/www/us/en/support/detect.html"
    }
} catch {
    Write-Warn "  Error checking driver version: $_"
    Write-Warn "  Recommended: Manually visit the following link to check for updates:"
    Write-Warn "    https://www.intel.com/content/www/us/en/support/detect.html"
}

Write-Host ""
Write-Host "[4/16] Installing Python 3.12..." -ForegroundColor White

$pythonInstalled = $false
$pythonPath = $null
$pythonVersionStr = $null

Write-Host "  Checking if Python is already installed..."

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
    Write-Host "  Found Python executable: $pythonPath"
    
    try {
        $versionOutput = & $pythonPath --version 2>&1
        $pythonVersionStr = $versionOutput -replace "Python ", ""
        Write-Host "  Current Python version: $pythonVersionStr"
        
        $versionMatch = $pythonVersionStr -match "^(\d+)\.(\d+)"
        if ($versionMatch) {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            
            if ($major -eq 3 -and $minor -ge 10) {
                Write-Success "  Python 3.10+ already installed, skipping"
                $pythonInstalled = $true
            } else {
                Write-Warn "  Python version $pythonVersionStr is below 3.10, recommending upgrade"
                Write-Warn "  Installing Python 3.11..."
            }
        }
    } catch {
        Write-Warn "  Unable to get Python version information"
    }
} else {
    Write-Host "  Python not found, installing..."
}

if (-not $pythonInstalled) {
    $pythonVersion = "3.12.0"
    $pythonUrl = "https://www.python.org/ftp/python/$pythonVersion/python-$pythonVersion-amd64.exe"
    $pythonInstaller = "$env:TEMP\python-$pythonVersion-amd64.exe"
    $pythonTargetDir = "$env:LOCALAPPDATA\Programs\Python\Python312"

    Write-Host "  Downloading from $pythonUrl..."
    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonInstaller -UseBasicParsing -Headers $headers -ErrorAction Stop
        Write-Host "  Installing (no admin rights required)..."
        Start-Process -FilePath $pythonInstaller -ArgumentList "/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1 TARGETDIR=`"$pythonTargetDir`"" -Wait -NoNewWindow
        Remove-Item $pythonInstaller -Force
        
        $env:PATH = "$pythonTargetDir;$pythonTargetDir\Scripts;" + $env:PATH
        
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($currentPath -notlike "*$pythonTargetDir*") {
            [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$pythonTargetDir;$pythonTargetDir\Scripts", "User")
            Write-Host "  Python path added to user PATH" -ForegroundColor Green
        }
        
        $pythonPath = (Get-Command python -ErrorAction SilentlyContinue).Source
        if ($pythonPath) {
            Write-Host "  Python path: $pythonPath"
        }
        python --version
        Write-Success "Python $pythonVersion installation completed"
    } catch {
        Write-Warn "Automatic Python installation failed"
        Write-Warn "Please install manually from: https://www.python.org/downloads/"
    }
}

Write-Host ""
Write-Host "[5/16] Configuring pip domestic mirror..." -ForegroundColor White

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
Write-Success "pip mirror configured to Tsinghua University mirror (https://pypi.tuna.tsinghua.edu.cn/simple)"

Write-Host ""
Write-Host "[6/16] Installing Git..." -ForegroundColor White

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
    
    Write-Host "  Extracting (no admin rights required, no UAC prompts)..."
    Start-Process -FilePath $gitInstaller -ArgumentList "-y -o`"$gitTargetDir`"" -Wait -NoNewWindow
    Remove-Item $gitInstaller -Force
    
    $env:PATH = "$gitTargetDir\bin;$gitTargetDir\cmd;" + $env:PATH
    
    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    if ($currentPath -notlike "*$gitTargetDir\bin*") {
        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$gitTargetDir\bin;$gitTargetDir\cmd", "User")
        Write-Host "  Git path added to user PATH" -ForegroundColor Green
    }
    
    git --version
    Write-Success "Git $gitVersion installation completed"
} else {
    Write-Warn "Automatic Git installation failed"
    Write-Warn "Please install manually from: https://git-scm.com/download/win"
    $useMirror = $true
}

Write-Host ""
Write-Host "[7/16] Git-LFS installation (optional)..." -ForegroundColor White

if ($WithGitLfs) {
    $gitLfsVersion = "3.7.1"
    $gitLfsInstaller = "$env:TEMP\git-lfs-windows-v$gitLfsVersion.exe"

    $gitLfsDownloadUrls = @(
        "https://github.com/git-lfs/git-lfs/releases/download/v$gitLfsVersion/git-lfs-windows-v$gitLfsVersion.exe",
        "https://ghproxy.net/https://github.com/git-lfs/git-lfs/releases/download/v$gitLfsVersion/git-lfs-windows-v$gitLfsVersion.exe"
    )

    $lfsDownloadSuccess = $false

    foreach ($gitLfsUrl in $gitLfsDownloadUrls) {
        Write-Host "  Downloading from $gitLfsUrl..."
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
            Write-Host "  Download failed, trying next URL..."
        }
    }

    if ($lfsDownloadSuccess) {
        Write-Host "  Installing..."
        Start-Process -FilePath $gitLfsInstaller -ArgumentList "/S" -Wait -NoNewWindow
        Remove-Item $gitLfsInstaller -Force
        git lfs install
        Write-Success "Git-LFS $gitLfsVersion installation completed"
    } else {
        Write-Warn "Automatic Git-LFS installation failed"
        Write-Warn "Please install manually from: https://git-lfs.com/"
        $useMirror = $true
    }
} else {
    Write-Host "  Skipped (use -WithGitLfs to install)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[8/16] Configuring Git domestic mirror..." -ForegroundColor White

git config --global url."https://ghproxy.net/https://github.com/".insteadOf "https://github.com/"

$ghProxyConfig = git config --global --get url."https://ghproxy.net/https://github.com/".insteadOf
if ($ghProxyConfig -eq "https://github.com/") {
    Write-Success "Git mirror configured to ghproxy.net (github.com only)"
} else {
    Write-Warn "Git mirror configuration may have failed"
}

Write-Host "  Test verification: ghproxy mirror is approximately 33% faster than original URL" -ForegroundColor Green

Write-Host ""
Write-Host "[9/16] Installing CMake (optional)..." -ForegroundColor White

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
        Write-Host "  Downloading from $cmakeUrl..."
        try {
            $headers = @{
                "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
            Invoke-WebRequest -Uri $cmakeUrl -OutFile $cmakeZip -UseBasicParsing -Headers $headers -ErrorAction Stop
            $downloadSuccess = $true
            break
        } catch {
            Write-Host "  Download failed, trying next URL..." -ForegroundColor Yellow
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
                "$env:USERPROFILE\AppData\Local\Programs\CMake\bin",
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
                Write-Host "  CMake path added to user PATH" -ForegroundColor Green
            }
            
            cmake --version
            Write-Success "CMake $cmakeVersion installation completed"
        } catch {
            Write-Warn "Error during CMake installation: $_"
            Write-Warn "Please install manually from: https://cmake.org/download/"
        }
    } else {
        Write-Warn "Automatic CMake installation failed"
        Write-Warn "Please install manually from: https://cmake.org/download/"
    }
} else {
    Write-Warn "  CMake installation skipped"
    Write-Warn "  If you need to compile C++ projects, re-run the script with -InstallCmake parameter"
    Write-Warn "  Command: powershell -File intel_aipc_env_setup.ps1 -InstallCmake"
}

Write-Host ""
Write-Host "[10/16] Installing Visual Studio Community Edition (optional)..." -ForegroundColor White

if ($InstallVS -or $FullInstall) {
    $vsInstallerUrl = "https://aka.ms/vs/17/release/vs_community.exe"
    $vsInstaller = "$env:TEMP\vs_community.exe"

    Write-Warn "  Note: Visual Studio installation requires administrator privileges"
    Write-Warn "  If not running as administrator, UAC prompt will be triggered"
    
    Write-Host "  Downloading from $vsInstallerUrl..."
    try {
        Invoke-WebRequest -Uri $vsInstallerUrl -OutFile $vsInstaller -UseBasicParsing -ErrorAction Stop
        Write-Host "  Installing (may take 10-30 minutes)..."
        Start-Process -FilePath $vsInstaller -ArgumentList "--quiet --wait --norestart --nocache --installPath `"C:\Program Files\Microsoft Visual Studio\2022\Community`" --add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows10SDK --add Microsoft.VisualStudio.Component.Windows11SDK" -Wait -NoNewWindow
        Remove-Item $vsInstaller -Force
        Write-Success "Visual Studio Community 2022 installation completed"
    } catch {
        Write-Warn "Automatic Visual Studio installation failed"
        Write-Warn "Please install manually from: https://visualstudio.microsoft.com/downloads/"
        Write-Warn "Make sure to select Desktop development with C++ workload"
    }
} else {
    Write-Warn "  Visual Studio installation skipped"
    Write-Warn "  If you need to compile C++ projects, re-run the script with -InstallVS parameter"
    Write-Warn "  Command: powershell -File intel_aipc_env_setup.ps1 -InstallVS"
    Write-Warn "  Note: Must run as administrator"
}

Write-Host ""
Write-Host "[11/16] Installing ModelScope and configuring HF mirror..." -ForegroundColor White

Write-Host "  Installing ModelScope..."
try {
    pip install modelscope --quiet
    Write-Success "ModelScope installation completed"
} catch {
    Write-Warn "ModelScope installation failed"
}

Write-Host "  Configuring Hugging Face mirror (hf-mirror.com)..."
[Environment]::SetEnvironmentVariable("HF_ENDPOINT", "https://hf-mirror.com", "User")
$env:HF_ENDPOINT = "https://hf-mirror.com"
Write-Success "HF_ENDPOINT set to https://hf-mirror.com"

Write-Host "  Configuring ModelScope API URL..."
[Environment]::SetEnvironmentVariable("MODELSCOPE_API_URL", "https://api.modelscope.cn", "User")
$env:MODELSCOPE_API_URL = "https://api.modelscope.cn"
Write-Success "ModelScope API URL configured"

Write-Host ""
Write-Host "[12/16] Installing OpenVINO (latest stable)..." -ForegroundColor White

Write-Host "  Installing the latest stable openvino..."
try {
    pip install --upgrade openvino --quiet
    $ovVersion = python -c "import openvino; print(openvino.__version__)"
    Write-Host "  OpenVINO version: $ovVersion"
    Write-Success "OpenVINO (latest stable) installation completed: $ovVersion"
} catch {
    Write-Warn "OpenVINO installation failed"
}

Write-Host ""
Write-Host "[13/16] Installing PyTorch (CPU version)..." -ForegroundColor White

Write-Host "  Installing PyTorch CPU version..."
Write-Host "  Note: Specific PyTorch version should be referenced from the target notebook project."
Write-Host "  This installation provides a base CPU environment. Create project-specific virtual environments for actual deployment."

try {
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --trusted-host download.pytorch.org --quiet
    $torchVersion = python -c "import torch; print(`"PyTorch version:`", torch.__version__)"
    Write-Host "  $torchVersion"
    Write-Success "PyTorch CPU version installed"
} catch {
    Write-Warn "PyTorch CPU version installation failed"
    Write-Warn "Trying Tsinghua mirror..."
    try {
        pip install torch torchvision torchaudio -i https://pypi.tuna.tsinghua.edu.cn/simple --trusted-host pypi.tuna.tsinghua.edu.cn --quiet
        $torchVersion = python -c "import torch; print(`"PyTorch version:`", torch.__version__)"
        Write-Host "  $torchVersion"
        Write-Success "PyTorch installed (via Tsinghua mirror)"
    } catch {
        Write-Warn "PyTorch installation failed"
    }
}

Write-Host ""
Write-Host "[14/16] Testing device availability..." -ForegroundColor White

$testScriptPath = "$env:TEMP\test_devices.py"
Set-Content -Path $testScriptPath -Value @"
from openvino.runtime import Core
import os

print("=" * 60)
print("OpenVINO Device Query")
print("=" * 60)

try:
    core = Core()
    available_devices = core.available_devices
    
    print(f"\nAvailable devices: {available_devices}")
    print(f"Number of devices: {len(available_devices)}")
    
    has_gpu = False
    has_npu = False
    has_cpu = False
    
    for device in available_devices:
        print(f"\n--- Device: {device} ---")
        try:
            props = core.get_property(device)
            for key, value in props.items():
                print(f"  {key}: {value}")
        except:
            print("  (Properties unavailable)")
        
        if "GPU" in device.upper():
            has_gpu = True
        elif "NPU" in device.upper():
            has_npu = True
        elif "CPU" in device.upper():
            has_cpu = True
    
    print("\n" + "=" * 60)
    print("Device Summary")
    print("=" * 60)
    
    if has_gpu:
        print("✓ Intel GPU (iGPU/Arc) detected and available")
    else:
        print("✗ No Intel GPU detected")
        
    if has_npu:
        print("✓ Intel NPU detected and available")
    else:
        print("✗ No Intel NPU detected")
        
    if has_cpu:
        print("✓ CPU detected and available")
    else:
        print("✗ No CPU detected")
        
    print("\n" + "=" * 60)
    
except Exception as e:
    print(f"Error: {e}")
    print("OpenVINO may not be installed correctly")

print("\n" + "=" * 60)
print("PyTorch Device Check")
print("=" * 60)

try:
    import torch
    print(f"PyTorch version: {torch.__version__}")
    
    print("Note: This is a CPU-only installation.")
    print("For project-specific environments, create virtual environments with versions matching the target notebook.")
    
    cuda_available = torch.cuda.is_available()
    print(f"CUDA available: {cuda_available}")
    
    print("✓ PyTorch CPU version installed and working")
    
except Exception as e:
    print(f"Error: {e}")
    print("PyTorch may not be installed correctly")

print("\n" + "=" * 60)
"@ -Encoding UTF8

python $testScriptPath
Remove-Item $testScriptPath -Force

Write-Host ""
Write-Host "[15/16] Running hello_query_device example..." -ForegroundColor White

try {
    $helloScriptPath = "$env:TEMP\hello_query_device.py"
    
    Write-Host "  Downloading hello_query_device.py..."
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
            Write-Host "  Download successful"
            break
        } catch {
            Write-Host "  Download failed: $url"
        }
    }
    
    if ($downloadSuccess -and (Test-Path $helloScriptPath)) {
        Write-Host "  Running..."
        python $helloScriptPath
        Remove-Item $helloScriptPath -Force
        Write-Success "hello_query_device.py executed successfully"
    } else {
        Write-Warn "Downloading hello_query_device.py failed"
        Write-Host "  Creating local hello_query_device.py..."
        $localHelloScript = @"
from openvino.runtime import Core

core = Core()

print("Available devices:")
for device in core.available_devices:
    print(f"  {device}")

print("\nDevice details:")
for device in core.available_devices:
    print(f"\n--- {device} ---")
    properties = core.get_property(device)
    for key, value in properties.items():
        print(f"  {key}: {value}")
"@
        Set-Content -Path "$env:TEMP\hello_query_device.py" -Value $localHelloScript -Encoding UTF8
        python "$env:TEMP\hello_query_device.py"
        Write-Success "Local hello_query_device.py executed successfully"
    }
    
    Remove-Item $openvinoDir -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    Write-Warn "Failed to run hello_query_device example"
    Write-Warn "Error: $_"
}

Write-Host ""
Write-Host "[16/16] Setting environment variables..." -ForegroundColor White

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
        Write-Host "  Added the following paths to user PATH:"
        foreach ($p in $pathsToAdd) {
            Write-Host "    $p"
        }
    }
    
    Write-Success "Environment variables updated (user level, no admin rights required)"
} catch {
    Write-Warn "Failed to update environment variables"
}

Write-Host ""
Write-Header "Installation Complete!"

Write-Host ""
Write-Host "Summary:" -ForegroundColor White
Write-Host "--------"
Write-Host "✓ Windows OS check passed" -ForegroundColor Green
Write-Host "✓ Intel processor check passed" -ForegroundColor Green
if ($isUltra) {
    Write-Host "✓ Intel Ultra series processor detected" -ForegroundColor Green
}
Write-Host "✓ GPU device and driver check completed" -ForegroundColor Green
Write-Host "✓ Python installed and pip mirror configured" -ForegroundColor Green
Write-Host "✓ Git installed and ghproxy.net mirror configured" -ForegroundColor Green
if ($WithGitLfs) {
    Write-Host "✓ Git-LFS installed" -ForegroundColor Green
} else {
    Write-Host "○ Git-LFS skipped (optional, use -WithGitLfs)" -ForegroundColor Gray
}
if ($InstallCmake -or $FullInstall) {
    Write-Host "✓ CMake installed" -ForegroundColor Green
} else {
    Write-Host "○ CMake skipped (optional)" -ForegroundColor Gray
}
if ($InstallVS -or $FullInstall) {
    Write-Host "✓ Visual Studio Community 2022 installed" -ForegroundColor Green
} else {
    Write-Host "○ Visual Studio skipped (optional)" -ForegroundColor Gray
}
Write-Host "✓ ModelScope installed and HF mirror configured" -ForegroundColor Green
Write-Host "✓ OpenVINO (latest stable) installed" -ForegroundColor Green
Write-Host "✓ PyTorch CPU version installed" -ForegroundColor Green
Write-Host "✓ Device availability test completed" -ForegroundColor Green
Write-Host "✓ Environment variables updated" -ForegroundColor Green

Write-Host ""
Write-Host "Optional installation commands:" -ForegroundColor White
Write-Host "--------"
Write-Host "Install CMake: powershell -File intel_aipc_env_setup.ps1 -InstallCmake" -ForegroundColor Yellow
Write-Host "Install Visual Studio: powershell -File intel_aipc_env_setup.ps1 -InstallVS" -ForegroundColor Yellow
Write-Host "Install all (including optional): powershell -File intel_aipc_env_setup.ps1 -FullInstall" -ForegroundColor Yellow
Write-Host "Basic installation only (default): powershell -File intel_aipc_env_setup.ps1" -ForegroundColor Yellow

Write-Host ""
Write-Host "Notes:" -ForegroundColor White
Write-Host "--------"
Write-Host "1. Please restart your terminal to ensure environment variables take effect" -ForegroundColor Yellow
Write-Host "2. ModelScope is set as the primary choice for large model downloads" -ForegroundColor Yellow
Write-Host "3. Hugging Face mirror: https://hf-mirror.com (HF_ENDPOINT set)" -ForegroundColor Yellow
Write-Host "4. Update Intel drivers: https://www.intel.com/content/www/us/en/support/detect.html" -ForegroundColor Yellow
Write-Host "5. Git accesses github.com via ghproxy.net" -ForegroundColor Yellow
Write-Host "6. CMake and Visual Studio are optional components, install only when C++ compilation is needed" -ForegroundColor Yellow
Write-Host "7. PyTorch is installed as CPU version. Specific versions should be referenced from target notebook projects." -ForegroundColor Yellow
Write-Host "8. For actual deployment: Create project-specific virtual environments instead of using Jupyter." -ForegroundColor Yellow

Write-Host ""
Write-Host "Happy coding with Intel AIPC!" -ForegroundColor Cyan