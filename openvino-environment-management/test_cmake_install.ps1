Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== CMake Installation Test ===" -ForegroundColor Cyan

$cmakeVersion = "4.3.4"
$cmakeZip = "$env:TEMP\cmake-$cmakeVersion.zip"
$cmakeTargetDir = "$env:USERPROFILE\cmake"

$cmakeDownloadUrls = @(
    "https://ghproxy.net/https://github.com/Kitware/CMake/releases/download/v$cmakeVersion/cmake-$cmakeVersion-windows-x86_64.zip",
    "https://github.com/Kitware/CMake/releases/download/v$cmakeVersion/cmake-$cmakeVersion-windows-x86_64.zip"
)

Write-Host "[1/4] Downloading CMake $cmakeVersion..." -ForegroundColor White
$downloadSuccess = $false
foreach ($cmakeUrl in $cmakeDownloadUrls) {
    Write-Host "  Trying: $cmakeUrl"
    try {
        $headers = @{"User-Agent"="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
        Invoke-WebRequest -Uri $cmakeUrl -OutFile $cmakeZip -UseBasicParsing -Headers $headers
        $downloadSuccess = $true
        Write-Host "  Download successful!" -ForegroundColor Green
        break
    } catch {
        Write-Host "  Download failed" -ForegroundColor Yellow
    }
}

if (-not $downloadSuccess) {
    Write-Host "All downloads failed!" -ForegroundColor Red
    exit 1
}

Write-Host "[2/4] Extracting to $cmakeTargetDir..." -ForegroundColor White
if (Test-Path $cmakeTargetDir) { Remove-Item $cmakeTargetDir -Recurse -Force }
Expand-Archive -Path $cmakeZip -DestinationPath $cmakeTargetDir -Force
Remove-Item $cmakeZip -Force

$cmakeBinDir = Get-ChildItem -Path $cmakeTargetDir -Directory | Select-Object -First 1
$cmakeBinDir = "$($cmakeBinDir.FullName)\bin"

Write-Host "[3/4] Setting PATH..." -ForegroundColor White
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
    Write-Host "  Added to User PATH" -ForegroundColor Green
}

Write-Host "[4/4] Verifying..." -ForegroundColor White
if (Test-Path "$cmakeBinDir\cmake.exe") {
    cmake --version
    Write-Host ""
    Write-Host "=== Installation Complete ===" -ForegroundColor Cyan
} else {
    Write-Host "CMake not found in expected path!" -ForegroundColor Red
    exit 1
}
