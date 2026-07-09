Set-ExecutionPolicy Bypass -Scope Process -Force

param(
    [switch]$WithGitLfs = $false
)

Write-Host "=== Git 和 Git-LFS 安装测试 ===" -ForegroundColor Cyan

Write-Host ""
Write-Host "[1/4] 检查 Git 是否已安装..." -ForegroundColor White

$gitInstalled = $false
$gitPath = $null

$gitExePaths = @(
    (Get-Command git -ErrorAction SilentlyContinue).Source,
    "$env:LOCALAPPDATA\Programs\Git\bin\git.exe"
) | Where-Object { 
    $_ -and (Test-Path $_) 
} | Select-Object -First 1

if ($gitExePaths) {
    $gitPath = $gitExePaths
    Write-Host "  找到 Git: $gitPath"
    
    try {
        $versionOutput = & $gitPath --version
        Write-Host "  当前版本: $versionOutput"
        Write-Host "  Git 已安装，跳过" -ForegroundColor Green
        $gitInstalled = $true
    } catch {
        Write-Host "  无法获取 Git 版本" -ForegroundColor Yellow
    }
} else {
    Write-Host "  未找到 Git，需要安装" -ForegroundColor White
}

if (-not $gitInstalled) {
    Write-Host ""
    Write-Host "[2/4] 下载并安装 Git（便携版）..." -ForegroundColor White
    
    $gitVersion = "2.55.0.windows.2"
    $gitInstaller = "$env:TEMP\PortableGit-2.55.0.2-64-bit.7z.exe"
    $gitTargetDir = "$env:LOCALAPPDATA\Programs\Git"

    $gitDownloadUrls = @(
        "https://github.com/git-for-windows/git/releases/download/v$gitVersion/PortableGit-2.55.0.2-64-bit.7z.exe",
        "https://ghproxy.net/https://github.com/git-for-windows/git/releases/download/v$gitVersion/PortableGit-2.55.0.2-64-bit.7z.exe"
    )

    $downloadSuccess = $false
    foreach ($gitUrl in $gitDownloadUrls) {
        Write-Host "  下载 URL: $gitUrl"
        Write-Host "  安装路径: $gitTargetDir"
        Write-Host "  开始下载..."
        
        try {
            $headers = @{
                "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
            Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing -Headers $headers -ErrorAction Stop
            $downloadSuccess = $true
            Write-Host "  下载完成！"
            break
        } catch {
            Write-Host "  下载失败，尝试下一个 URL..." -ForegroundColor Yellow
        }
    }
    
    if ($downloadSuccess) {
        if (Test-Path $gitTargetDir) {
            Remove-Item $gitTargetDir -Recurse -Force
        }
        
        Write-Host "  正在解压（无需 UAC）..."
        Start-Process -FilePath $gitInstaller -ArgumentList "-y -o`"$gitTargetDir`"" -Wait -NoNewWindow
        Remove-Item $gitInstaller -Force
        
        $env:PATH = "$gitTargetDir\bin;$gitTargetDir\cmd;" + $env:PATH
        
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($currentPath -notlike "*$gitTargetDir\bin*") {
            [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$gitTargetDir\bin;$gitTargetDir\cmd", "User")
            Write-Host "  Git 路径已添加到用户 PATH" -ForegroundColor Green
        }
        
        Write-Host "  Git 安装完成。正在验证..."
        git --version
        Write-Host "  Git 安装成功！" -ForegroundColor Green
    } else {
        Write-Host "  所有下载均失败！" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "[3/4] 配置 Git 镜像..." -ForegroundColor White

git config --global url."https://ghproxy.net/https://github.com/".insteadOf "https://github.com/"
Write-Host "  Git 镜像已配置: ghproxy.net for github.com" -ForegroundColor Green

Write-Host ""
Write-Host "[4/4] Git-LFS 安装（可选）..." -ForegroundColor White

if ($WithGitLfs) {
    $gitLfsInstalled = $false

    try {
        $gitLfsVersion = git lfs version 2>&1
        if ($gitLfsVersion -match "git-lfs") {
            Write-Host "  Git-LFS 已安装: $gitLfsVersion" -ForegroundColor Green
            $gitLfsInstalled = $true
        }
    } catch {
        Write-Host "  未找到 Git-LFS，需要安装" -ForegroundColor White
    }

    if (-not $gitLfsInstalled) {
        Write-Host ""
        Write-Host "  正在下载 Git-LFS..." -ForegroundColor White
        
        $gitLfsUrl = "https://github.com/git-lfs/git-lfs/releases/download/v3.7.1/git-lfs-windows-v3.7.1.exe"
        $gitLfsInstaller = "$env:TEMP\git-lfs-windows-v3.7.1.exe"

        Write-Host "  下载 URL: $gitLfsUrl"
        Write-Host "  开始下载..."
        
        try {
            $headers = @{
                "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
            Invoke-WebRequest -Uri $gitLfsUrl -OutFile $gitLfsInstaller -UseBasicParsing -Headers $headers -ErrorAction Stop
            Write-Host "  下载完成！"
            
            Write-Host "  正在安装..."
            Start-Process -FilePath $gitLfsInstaller -ArgumentList "/S" -Wait -NoNewWindow
            Remove-Item $gitLfsInstaller -Force
            
            Write-Host "  Git-LFS 安装完成。正在验证..."
            git lfs version
            Write-Host "  Git-LFS 安装成功！" -ForegroundColor Green
        } catch {
            Write-Host "  Git-LFS 安装失败: $_" -ForegroundColor Red
            exit 1
        }
    }
} else {
    Write-Host "  已跳过（使用 -WithGitLfs 参数安装）" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== 安装完成 ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "验证:"
Write-Host "  git --version: $(git --version)"
if ($WithGitLfs) {
    Write-Host "  git lfs version: $(git lfs version)"
}
Write-Host "  git config --global --get url.https://ghproxy.net/https://github.com/.insteadOf: $(git config --global --get url.https://ghproxy.net/https://github.com/.insteadOf)"
