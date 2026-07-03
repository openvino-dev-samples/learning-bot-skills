Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== Visual Studio Community 2022 Installation ===" -ForegroundColor Cyan

$vsInstallerUrl = "https://aka.ms/vs/17/release/vs_community.exe"
$vsInstaller = "$env:TEMP\vs_community.exe"
$vsInstallPath = "C:\Program Files\Microsoft Visual Studio\2022\Community"

Write-Host ""
Write-Host "[1/3] Checking if Visual Studio is already installed..." -ForegroundColor White

if (Test-Path "$vsInstallPath\Common7\IDE\devenv.exe") {
    Write-Host "  Visual Studio is already installed at: $vsInstallPath" -ForegroundColor Green
    Write-Host "  Verifying..." -ForegroundColor White
    & "$vsInstallPath\Common7\IDE\devenv.exe" --version
    Write-Host ""
    Write-Host "=== Installation Complete (already installed) ===" -ForegroundColor Cyan
    exit 0
}

Write-Host "  Visual Studio not found, starting installation..." -ForegroundColor White

Write-Host ""
Write-Host "[2/3] Downloading Visual Studio installer..." -ForegroundColor White
Write-Host "  URL: $vsInstallerUrl"

try {
    $headers = @{
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }
    Invoke-WebRequest -Uri $vsInstallerUrl -OutFile $vsInstaller -UseBasicParsing -Headers $headers -ErrorAction Stop
    Write-Host "  Download complete!" -ForegroundColor Green
} catch {
    Write-Host "  Download failed: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[3/3] Installing Visual Studio (this may take 10-30 minutes)..." -ForegroundColor White
Write-Host "  Install path: $vsInstallPath"
Write-Host "  Workloads: Native Desktop (C++ development)"
Write-Host "  Components: VC Tools, Windows 10/11 SDK"

$arguments = @(
    "--quiet",
    "--wait",
    "--norestart",
    "--nocache",
    "--installPath `"$vsInstallPath`"",
    "--add Microsoft.VisualStudio.Workload.NativeDesktop",
    "--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
    "--add Microsoft.VisualStudio.Component.Windows10SDK",
    "--add Microsoft.VisualStudio.Component.Windows11SDK"
)

Start-Process -FilePath $vsInstaller -ArgumentList $arguments -Wait -NoNewWindow
$exitCode = $LASTEXITCODE

Remove-Item $vsInstaller -Force -ErrorAction SilentlyContinue

if ($exitCode -eq 0) {
    Write-Host ""
    Write-Host "  Installation successful!" -ForegroundColor Green
    Write-Host "  Verifying..." -ForegroundColor White
    if (Test-Path "$vsInstallPath\Common7\IDE\devenv.exe") {
        & "$vsInstallPath\Common7\IDE\devenv.exe" --version
    }
    Write-Host ""
    Write-Host "=== Installation Complete ===" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "  Installation failed with exit code: $exitCode" -ForegroundColor Red
    Write-Host "  Note: Visual Studio installation requires administrator privileges." -ForegroundColor Yellow
    Write-Host "  Please run this script as administrator or install manually." -ForegroundColor Yellow
    exit $exitCode
}
