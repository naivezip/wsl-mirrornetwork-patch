<#
.SYNOPSIS
    Uninstaller for WSL Mirrored Network & TUN Loopback Deadlock Patch.
.DESCRIPTION
    1. Unregisters the scheduled task 'DisableEthernetForwarding'.
    2. Removes C:\ProgramData\DisableEthernetForwarding.ps1.
    3. Checks WSL distros and informs/cleans /etc/wsl.conf hook if desired.
.LINK
    https://naivezip.github.io/2026/10/12/wsl2-mirrored-tun-loopback-deadlock/
    https://github.com/naivezip/wsl-mirrornetwork-patch
#>

[CmdletBinding()]
param(
    [switch]$AutoCleanWSL,
    [switch]$NonInteractive
)

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[!] 请求以管理员权限运行..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath) {
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        if ($AutoCleanWSL) { $argList += " -AutoCleanWSL" }
        if ($NonInteractive) { $argList += " -NonInteractive" }
        Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Verb RunAs
    } else {
        Write-Error "请以管理员身份打开 PowerShell 重新执行此脚本！"
    }
    exit
}

Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host "   WSL2 镜像网络 + TUN 死锁修复补丁 卸载程序   " -ForegroundColor Yellow
Write-Host "   项目地址: https://github.com/naivezip/wsl-mirrornetwork-patch" -ForegroundColor DarkYellow
Write-Host "==========================================================" -ForegroundColor Yellow
Write-Host ""

# 1. Remove scheduled task
$taskName = "DisableEthernetForwarding"
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Write-Host "[1/3] 正在注销计划任务 $taskName ..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "  [✓] 计划任务已注销" -ForegroundColor Green
} else {
    Write-Host "[1/3] 未检测到计划任务 $taskName，跳过。" -ForegroundColor Gray
}

# 2. Remove script file
$targetFile = "C:\ProgramData\DisableEthernetForwarding.ps1"
if (Test-Path $targetFile) {
    Write-Host "[2/3] 正在删除脚本文件 $targetFile ..." -ForegroundColor Yellow
    Remove-Item -Path $targetFile -Force -ErrorAction SilentlyContinue
    Write-Host "  [✓] 脚本文件已删除" -ForegroundColor Green
} else {
    Write-Host "[2/3] 脚本文件不存在，跳过。" -ForegroundColor Gray
}

# 3. Check WSL Hook
Write-Host "[3/3] 检查 WSL 启动 Hook..." -ForegroundColor Yellow
if (Get-Command "wsl.exe" -ErrorAction SilentlyContinue) {
    $rawList = (wsl.exe -l -q 2>$null)
    $distros = @()
    if ($rawList) {
        $distros = ($rawList -replace "`0", "").Split("`r`n", [System.StringSplitOptions]::RemoveEmptyEntries) | 
                   ForEach-Object { $_.Trim() } | 
                   Where-Object { $_ -and $_ -notmatch 'docker' }
    }

    foreach ($distro in $distros) {
        $confContent = wsl.exe -d $distro -u root cat /etc/wsl.conf 2>$null
        if ($confContent -match "DisableEthernetForwarding") {
            $shouldRemove = $false
            if ($AutoCleanWSL) {
                $shouldRemove = $true
            } elseif (-not $NonInteractive -and [Environment]::UserInteractive) {
                $choice = Read-Host "  [?] 检测到 WSL 分发版 [$distro] 的 /etc/wsl.conf 中包含启动 Hook，是否自动移除? (y/N)"
                if ($choice -match "^[yY]") {
                    $shouldRemove = $true
                }
            }

            if ($shouldRemove) {
                $cleanScript = @'
sed -i '/DisableEthernetForwarding/d' /etc/wsl.conf
# 如果 [boot] 节下为空，清理空行
sed -i '/^\[boot\][[:space:]]*$/{N; /^\n$/d}' /etc/wsl.conf
'@
                wsl.exe -d $distro -u root bash -c $cleanScript
                Write-Host "  [✓] 已从分发版 [$distro] 的 /etc/wsl.conf 中移除 Hook" -ForegroundColor Green
            } else {
                Write-Host "  [i] 分发版 [$distro] 中的 /etc/wsl.conf 仍保留 Hook 命令。" -ForegroundColor Cyan
                Write-Host "      若需手动清理，请进入 WSL 执行: sudo nano /etc/wsl.conf 移除 command 行。" -ForegroundColor Gray
            }
        }
    }
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "   补丁已完全卸载！   " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
if (-not $NonInteractive -and [Environment]::UserInteractive) {
    Write-Host "按任意键退出..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
