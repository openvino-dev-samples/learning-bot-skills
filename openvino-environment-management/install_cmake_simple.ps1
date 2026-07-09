Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== 简易 CMake 安装 ===" -ForegroundColor Cyan

$cmakeVersion = "4.3.4"
$cmakeZip = "$env:TEMP\cmake-$cmakeVersion.zip"
$cmakeTargetDir = "$env:USERPROFILE\cmake"

Write-Host ""
Write-Host "[1/3] 正在下载 CMake..." -ForegroundColor White

$cmakeUrl = "https://ghproxy.net/https://github.com/Kitware/CMake/releases/download/v$cmakeVersion/cmake-$cmakeVersion-windows-x86_64.zip"
Write-Host "  URL: $cmakeUrl"

try {
    $headers = @{"User-Agent"="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
    Invoke-WebRequest -Uri $cmakeUrl -OutFile $cmakeZip -UseBasicParsing -Headers $headers
    Write-Host "  下载完成！" -ForegroundColor Green
} catch {
    Write-Host "  下载失败！" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "[2/3] 正在解压到 $cmakeTargetDir..." -ForegroundColor White

if (Test-Path $cmakeTargetDir) { Remove-Item $cmakeTargetDir -Recurse -Force }
Expand-Archive -Path $cmakeZip -DestinationPath $cmakeTargetDir -Force
Remove-Item $cmakeZip -Force

$cmakeBinDir = Get-ChildItem -Path $cmakeTargetDir -Directory | Select-Object -First 1
$cmakeBinDir = "$($cmakeBinDir.FullName)\bin"
Write-Host "  CMake bin 路径: $cmakeBinDir"

Write-Host ""
Write-Host "[3/3] 正在设置 PATH..." -ForegroundColor White

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
}
[Environment]::SetEnvironmentVariable("PATH", $currentPath, "User")

Write-Host "  PATH 更新成功" -ForegroundColor Green

Write-Host ""
Write-Host "=== 正在验证 ===" -ForegroundColor Cyan
cmake --version

Write-Host ""
Write-Host "=== 安装完成 ===" -ForegroundColor Cyan
Write-Host "CMake 已安装到: $cmakeTargetDir"
