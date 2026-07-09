Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== Visual Studio Community 2022 安装 ===" -ForegroundColor Cyan

$vsInstallerUrl = "https://aka.ms/vs/17/release/vs_community.exe"
$vsInstaller = "$env:TEMP\vs_community.exe"
$vsInstallPath = "C:\Program Files\Microsoft Visual Studio\2022\Community"

Write-Host ""
Write-Host "[1/3] 正在检查 Visual Studio 是否已安装..." -ForegroundColor White

if (Test-Path "$vsInstallPath\Common7\IDE\devenv.exe") {
    Write-Host "  Visual Studio 已安装到: $vsInstallPath" -ForegroundColor Green
    Write-Host "  正在验证..." -ForegroundColor White
    & "$vsInstallPath\Common7\IDE\devenv.exe" --version
    Write-Host ""
    Write-Host "=== 安装完成（已安装） ===" -ForegroundColor Cyan
    exit 0
}

Write-Host "  未找到 Visual Studio，开始安装..." -ForegroundColor White

Write-Host ""
Write-Host "[2/3] 正在下载 Visual Studio 安装程序..." -ForegroundColor White
Write-Host "  URL: $vsInstallerUrl"

try {
    $headers = @{
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }
    Invoke-WebRequest -Uri $vsInstallerUrl -OutFile $vsInstaller -UseBasicParsing -Headers $headers -ErrorAction Stop
    Write-Host "  下载完成！" -ForegroundColor Green
} catch {
    Write-Host "  下载失败: $_" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[3/3] 正在安装 Visual Studio（可能需要 10-30 分钟）..." -ForegroundColor White
Write-Host "  安装路径: $vsInstallPath"
Write-Host "  工作负载: 本地桌面开发 (C++ 开发)"
Write-Host "  组件: VC 工具, Windows 10/11 SDK"

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
    Write-Host "  安装成功！" -ForegroundColor Green
    Write-Host "  正在验证..." -ForegroundColor White
    if (Test-Path "$vsInstallPath\Common7\IDE\devenv.exe") {
        & "$vsInstallPath\Common7\IDE\devenv.exe" --version
    }
    Write-Host ""
    Write-Host "=== 安装完成 ===" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "  安装失败，退出码: $exitCode" -ForegroundColor Red
    Write-Host "  注意: Visual Studio 安装需要管理员权限。" -ForegroundColor Yellow
    Write-Host "  请以管理员身份运行此脚本或手动安装。" -ForegroundColor Yellow
    exit $exitCode
}
