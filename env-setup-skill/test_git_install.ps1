Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=== Git and Git-LFS Installation Test ===" -ForegroundColor Cyan

Write-Host ""
Write-Host "[1/5] Check if Git is installed..." -ForegroundColor White

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
    Write-Host "  Found Git: $gitPath"
    
    try {
        $versionOutput = & $gitPath --version
        Write-Host "  Current version: $versionOutput"
        Write-Host "  Git already installed, skipping" -ForegroundColor Green
        $gitInstalled = $true
    } catch {
        Write-Host "  Cannot get Git version" -ForegroundColor Yellow
    }
} else {
    Write-Host "  Git not found, need to install" -ForegroundColor White
}

if (-not $gitInstalled) {
    Write-Host ""
    Write-Host "[2/5] Download and install Git (Portable version)..." -ForegroundColor White
    
    $gitVersion = "2.55.0.windows.2"
    $gitInstaller = "$env:TEMP\PortableGit-2.55.0.2-64-bit.7z.exe"
    $gitTargetDir = "$env:LOCALAPPDATA\Programs\Git"

    $gitDownloadUrls = @(
        "https://github.com/git-for-windows/git/releases/download/v$gitVersion/PortableGit-2.55.0.2-64-bit.7z.exe",
        "https://ghproxy.net/https://github.com/git-for-windows/git/releases/download/v$gitVersion/PortableGit-2.55.0.2-64-bit.7z.exe"
    )

    $downloadSuccess = $false
    foreach ($gitUrl in $gitDownloadUrls) {
        Write-Host "  Download URL: $gitUrl"
        Write-Host "  Install path: $gitTargetDir"
        Write-Host "  Starting download..."
        
        try {
            $headers = @{
                "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            }
            Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing -Headers $headers -ErrorAction Stop
            $downloadSuccess = $true
            Write-Host "  Download complete!"
            break
        } catch {
            Write-Host "  Download failed, trying next URL..." -ForegroundColor Yellow
        }
    }
    
    if ($downloadSuccess) {
        if (Test-Path $gitTargetDir) {
            Remove-Item $gitTargetDir -Recurse -Force
        }
        
        Write-Host "  Extracting (no UAC required)..."
        Start-Process -FilePath $gitInstaller -ArgumentList "-y -o`"$gitTargetDir`"" -Wait -NoNewWindow
        Remove-Item $gitInstaller -Force
        
        $env:PATH = "$gitTargetDir\bin;$gitTargetDir\cmd;" + $env:PATH
        
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
        if ($currentPath -notlike "*$gitTargetDir\bin*") {
            [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$gitTargetDir\bin;$gitTargetDir\cmd", "User")
            Write-Host "  Git path added to User PATH" -ForegroundColor Green
        }
        
        Write-Host "  Git installation complete. Verifying..."
        git --version
        Write-Host "  Git installed successfully!" -ForegroundColor Green
    } else {
        Write-Host "  All downloads failed!" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "[3/5] Check if Git-LFS is installed..." -ForegroundColor White

$gitLfsInstalled = $false

try {
    $gitLfsVersion = git lfs version 2>&1
    if ($gitLfsVersion -match "git-lfs") {
        Write-Host "  Git-LFS already installed: $gitLfsVersion" -ForegroundColor Green
        $gitLfsInstalled = $true
    }
} catch {
    Write-Host "  Git-LFS not found, need to install" -ForegroundColor White
}

if (-not $gitLfsInstalled) {
    Write-Host ""
    Write-Host "[4/5] Download and install Git-LFS..." -ForegroundColor White
    
    $gitLfsUrl = "https://github.com/git-lfs/git-lfs/releases/download/v3.7.1/git-lfs-windows-v3.7.1.exe"
    $gitLfsInstaller = "$env:TEMP\git-lfs-windows-v3.7.1.exe"

    Write-Host "  Download URL: $gitLfsUrl"
    Write-Host "  Starting download..."
    
    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        Invoke-WebRequest -Uri $gitLfsUrl -OutFile $gitLfsInstaller -UseBasicParsing -Headers $headers -ErrorAction Stop
        Write-Host "  Download complete!"
        
        Write-Host "  Installing..."
        Start-Process -FilePath $gitLfsInstaller -ArgumentList "/S" -Wait -NoNewWindow
        Remove-Item $gitLfsInstaller -Force
        
        Write-Host "  Git-LFS installation complete. Verifying..."
        git lfs version
        Write-Host "  Git-LFS installed successfully!" -ForegroundColor Green
    } catch {
        Write-Host "  Git-LFS installation failed: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "[5/5] Configure Git mirror..." -ForegroundColor White

git config --global url."https://ghproxy.net/https://github.com/".insteadOf "https://github.com/"
Write-Host "  Git mirror configured: ghproxy.net for github.com" -ForegroundColor Green

Write-Host ""
Write-Host "=== Installation Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Verification:"
Write-Host "  git --version: $(git --version)"
Write-Host "  git lfs version: $(git lfs version)"
Write-Host "  git config --global --get url.https://ghproxy.net/https://github.com/.insteadOf: $(git config --global --get url.https://ghproxy.net/https://github.com/.insteadOf)"
