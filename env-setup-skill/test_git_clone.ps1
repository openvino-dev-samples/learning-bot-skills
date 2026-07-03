Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== Git Clone Speed Test ===" -ForegroundColor Cyan

$gitPath = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $gitPath) {
    $gitPath = "$env:LOCALAPPDATA\Programs\Git\bin\git.exe"
}

if (-not (Test-Path $gitPath)) {
    Write-Host "Git not found! Please install Git first." -ForegroundColor Red
    exit 1
}

$repoUrl = "https://github.com/adriancable/8086tiny.git"
$testDir = "$env:TEMP\git_clone_test"

if (Test-Path $testDir) {
    Remove-Item $testDir -Recurse -Force
}
New-Item -ItemType Directory -Path $testDir | Out-Null

Write-Host ""
Write-Host "[1/2] Test 1: Clone with original URL" -ForegroundColor White
Write-Host "  Repo: $repoUrl"

$startTime = Get-Date
& $gitPath clone $repoUrl "$testDir\original" --depth 1 2>&1
$exitCode = $LASTEXITCODE
$endTime = Get-Date
$duration1 = ($endTime - $startTime).TotalSeconds

if ($exitCode -eq 0) {
    $size = (Get-ChildItem "$testDir\original" -Recurse | Measure-Object -Property Length -Sum).Sum / 1KB
    Write-Host "  ✓ Success!" -ForegroundColor Green
    Write-Host "  Size: $($size.ToString('F2')) KB"
    Write-Host "  Time: $($duration1.ToString('F2')) seconds"
} else {
    Write-Host "  ✗ Failed with exit code $exitCode" -ForegroundColor Red
    Write-Host "  Time: $($duration1.ToString('F2')) seconds"
}

Write-Host ""
Write-Host "[2/2] Test 2: Clone with ghproxy mirror" -ForegroundColor White
Write-Host "  Repo: https://ghproxy.net/$repoUrl"

$startTime = Get-Date
& $gitPath clone "https://ghproxy.net/$repoUrl" "$testDir\mirror" --depth 1 2>&1
$exitCode = $LASTEXITCODE
$endTime = Get-Date
$duration2 = ($endTime - $startTime).TotalSeconds

if ($exitCode -eq 0) {
    $size = (Get-ChildItem "$testDir\mirror" -Recurse | Measure-Object -Property Length -Sum).Sum / 1KB
    Write-Host "  ✓ Success!" -ForegroundColor Green
    Write-Host "  Size: $($size.ToString('F2')) KB"
    Write-Host "  Time: $($duration2.ToString('F2')) seconds"
} else {
    Write-Host "  ✗ Failed with exit code $exitCode" -ForegroundColor Red
    Write-Host "  Time: $($duration2.ToString('F2')) seconds"
}

Write-Host ""
Write-Host "=== Results ===" -ForegroundColor Cyan
Write-Host "Original URL: $($duration1.ToString('F2')) seconds"
Write-Host "ghproxy Mirror: $($duration2.ToString('F2')) seconds"

if ($duration1 -lt $duration2) {
    $diff = $duration2 - $duration1
    Write-Host "Original URL is faster by $($diff.ToString('F2')) seconds" -ForegroundColor Green
} elseif ($duration2 -lt $duration1) {
    $diff = $duration1 - $duration2
    Write-Host "ghproxy Mirror is faster by $($diff.ToString('F2')) seconds" -ForegroundColor Green
} else {
    Write-Host "Both have similar speed" -ForegroundColor Yellow
}

Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
