Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== Git Clone 速度测试 ===" -ForegroundColor Cyan

$gitPath = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $gitPath) {
    $gitPath = "$env:LOCALAPPDATA\Programs\Git\bin\git.exe"
}

if (-not (Test-Path $gitPath)) {
    Write-Host "未找到 Git！请先安装 Git。" -ForegroundColor Red
    exit 1
}

$repoUrl = "https://github.com/adriancable/8086tiny.git"
$testDir = "$env:TEMP\git_clone_test"

if (Test-Path $testDir) {
    Remove-Item $testDir -Recurse -Force
}
New-Item -ItemType Directory -Path $testDir | Out-Null

Write-Host ""
Write-Host "[1/2] 测试1: 使用原始 URL 克隆" -ForegroundColor White
Write-Host "  仓库: $repoUrl"

$startTime = Get-Date
& $gitPath clone $repoUrl "$testDir\original" --depth 1 2>&1
$exitCode = $LASTEXITCODE
$endTime = Get-Date
$duration1 = ($endTime - $startTime).TotalSeconds

if ($exitCode -eq 0) {
    $size = (Get-ChildItem "$testDir\original" -Recurse | Measure-Object -Property Length -Sum).Sum / 1KB
    Write-Host "  ✓ 成功！" -ForegroundColor Green
    Write-Host "  大小: $($size.ToString('F2')) KB"
    Write-Host "  时间: $($duration1.ToString('F2')) 秒"
} else {
    Write-Host "  ✗ 失败，退出码 $exitCode" -ForegroundColor Red
    Write-Host "  时间: $($duration1.ToString('F2')) 秒"
}

Write-Host ""
Write-Host "[2/2] 测试2: 使用 ghproxy 镜像克隆" -ForegroundColor White
Write-Host "  仓库: https://ghproxy.net/$repoUrl"

$startTime = Get-Date
& $gitPath clone "https://ghproxy.net/$repoUrl" "$testDir\mirror" --depth 1 2>&1
$exitCode = $LASTEXITCODE
$endTime = Get-Date
$duration2 = ($endTime - $startTime).TotalSeconds

if ($exitCode -eq 0) {
    $size = (Get-ChildItem "$testDir\mirror" -Recurse | Measure-Object -Property Length -Sum).Sum / 1KB
    Write-Host "  ✓ 成功！" -ForegroundColor Green
    Write-Host "  大小: $($size.ToString('F2')) KB"
    Write-Host "  时间: $($duration2.ToString('F2')) 秒"
} else {
    Write-Host "  ✗ 失败，退出码 $exitCode" -ForegroundColor Red
    Write-Host "  时间: $($duration2.ToString('F2')) 秒"
}

Write-Host ""
Write-Host "=== 结果 ===" -ForegroundColor Cyan
Write-Host "原始 URL: $($duration1.ToString('F2')) 秒"
Write-Host "ghproxy 镜像: $($duration2.ToString('F2')) 秒"

if ($duration1 -lt $duration2) {
    $diff = $duration2 - $duration1
    Write-Host "原始 URL 快 $($diff.ToString('F2')) 秒" -ForegroundColor Green
} elseif ($duration2 -lt $duration1) {
    $diff = $duration1 - $duration2
    Write-Host "ghproxy 镜像快 $($diff.ToString('F2')) 秒" -ForegroundColor Green
} else {
    Write-Host "两者速度相近" -ForegroundColor Yellow
}

Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
