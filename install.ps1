<#
.SYNOPSIS
    One-click installer for WSL Mirrored Network & TUN Loopback Deadlock Patch.
.DESCRIPTION
    1. Deploys DisableEthernetForwarding.ps1 to C:\ProgramData\DisableEthernetForwarding.ps1.
    2. Registers the scheduled task 'DisableEthernetForwarding' running under SYSTEM.
    3. Auto-detects WSL distros and configures /etc/wsl.conf boot hook.
    4. Executes the fix immediately.
.LINK
    https://naivezip.github.io/2026/10/12/wsl2-mirrored-tun-loopback-deadlock/
    https://github.com/naivezip/wsl-mirrornetwork-patch
#>

[CmdletBinding()]
param(
    [switch]$AutoWSL,
    [switch]$SkipWSL,
    [switch]$NonInteractive
)

# 1. Check Administrator Privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[!] 检测到当前非管理员权限，正在请求提升管理员权限..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath) {
        $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        if ($AutoWSL) { $argList += " -AutoWSL" }
        if ($SkipWSL) { $argList += " -SkipWSL" }
        if ($NonInteractive) { $argList += " -NonInteractive" }
        Start-Process -FilePath "powershell.exe" -ArgumentList $argList -Verb RunAs
    } else {
        Write-Error "请以管理员身份打开 PowerShell 重新执行此脚本！"
    }
    exit
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   WSL2 镜像网络 + TUN 死锁修复补丁 一键安装程序   " -ForegroundColor Cyan
Write-Host "   项目地址: https://github.com/naivezip/wsl-mirrornetwork-patch" -ForegroundColor DarkCyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$targetFile = "C:\ProgramData\DisableEthernetForwarding.ps1"
$sourceFile = if ($PSScriptRoot) { Join-Path $PSScriptRoot "DisableEthernetForwarding.ps1" } else { $null }

# 2. Deploy Script
Write-Host "[1/4] 部署核心脚本至 $targetFile ..." -ForegroundColor Yellow
if ($sourceFile -and (Test-Path $sourceFile)) {
    Copy-Item -Path $sourceFile -Destination $targetFile -Force
} else {
    # Standalone mode: Write embedded payload if run from web one-liner (irm | iex)
    $embeddedScript = @'
<#
.SYNOPSIS
    Disables IPv4 Forwarding on connected physical network adapters in Windows.
#>
[CmdletBinding()]
param([switch]$VerboseOutput)
try {
    $excludePattern = 'vEthernet|Loopback|Mihomo|Clash|Sing-box|Tailscale|ZeroTier|VMware|VirtualBox|Radmin|utun|wintun|tap|wireguard|docker|container'
    $interfaces = Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $_.ConnectionState -eq 'Connected' -and
        $_.Forwarding -eq 'Enabled' -and
        $_.InterfaceAlias -notmatch $excludePattern
    }
    $count = 0
    foreach ($if in $interfaces) {
        if ($VerboseOutput) { Write-Host "[+] Disabling IPv4 Forwarding on: $($if.InterfaceAlias) (Index: $($if.InterfaceIndex))" -ForegroundColor Green }
        Set-NetIPInterface -InterfaceIndex $if.InterfaceIndex -AddressFamily IPv4 -Forwarding Disabled -PolicyStore ActiveStore -ErrorAction SilentlyContinue
        Set-NetIPInterface -InterfaceIndex $if.InterfaceIndex -AddressFamily IPv4 -Forwarding Disabled -PolicyStore PersistentStore -ErrorAction SilentlyContinue
        $count++
    }
    if ($VerboseOutput) {
        if ($count -eq 0) {
            Write-Host "[✓] All physical interfaces are already in Forwarding: Disabled state." -ForegroundColor Gray
        } else {
            Write-Host "[✓] Successfully disabled Forwarding on $count interface(s)." -ForegroundColor Green
        }
    }
} catch {
    if ($VerboseOutput) { Write-Error $_ }
}
'@
    Set-Content -Path $targetFile -Value $embeddedScript -Encoding UTF8 -Force
}
Write-Host "  [✓] 核心脚本部署成功" -ForegroundColor Green

# 3. Register Scheduled Task
Write-Host "[2/4] 注册 SYSTEM 权限后台计划任务 (Session 0 静默运行)..." -ForegroundColor Yellow
try {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$targetFile`""
    $triggerStartup = New-ScheduledTaskTrigger -AtStartup
    $triggerStartup.Delay = "PT15S"
    $triggerHourly = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration (New-TimeSpan -Days 3650)
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew

    Register-ScheduledTask -TaskName "DisableEthernetForwarding" -Action $action -Trigger @($triggerStartup, $triggerHourly) -Principal $principal -Settings $settings -Force | Out-Null
    Write-Host "  [✓] 计划任务 'DisableEthernetForwarding' 注册成功 (开机15秒自启 + 每小时轮询)" -ForegroundColor Green
} catch {
    Write-Error "注册计划任务失败: $_"
}

# 4. Immediate execution
Write-Host "[3/4] 立即执行一次网络修复..." -ForegroundColor Yellow
& $targetFile -VerboseOutput
Write-Host "  [✓] 当前网络物理网卡 Forwarding 已重置为 Disabled" -ForegroundColor Green

# 5. WSL Configuration
Write-Host "[4/4] 检查 WSL 分发版启动 Hook..." -ForegroundColor Yellow
if (Get-Command "wsl.exe" -ErrorAction SilentlyContinue) {
    $rawList = (wsl.exe -l -q 2>$null)
    $distros = @()
    if ($rawList) {
        $distros = ($rawList -replace "`0", "").Split("`r`n", [System.StringSplitOptions]::RemoveEmptyEntries) | 
                   ForEach-Object { $_.Trim() } | 
                   Where-Object { $_ -and $_ -notmatch 'docker' }
    }

    if ($distros.Count -eq 0) {
        Write-Host "  [-] 未检测到已安装的 WSL Linux 分发版，跳过 WSL Hook 注入。" -ForegroundColor Gray
    } else {
        foreach ($distro in $distros) {
            $confContent = wsl.exe -d $distro -u root cat /etc/wsl.conf 2>$null
            if ($confContent -match "DisableEthernetForwarding") {
                Write-Host "  [✓] WSL 分发版 [$distro] 已配置启动 Hook，无需重复配置。" -ForegroundColor Green
            } else {
                $shouldConfig = $false
                if ($AutoWSL) {
                    $shouldConfig = $true
                } elseif (-not $SkipWSL) {
                    if ([Environment]::UserInteractive -and -not $NonInteractive) {
                        $choice = Read-Host "  [?] 是否自动为 WSL 分发版 [$distro] 配置 /etc/wsl.conf 启动 Hook? (Y/n)"
                        if ($choice -eq "" -or $choice -match "^[yY]") {
                            $shouldConfig = $true
                        }
                    } else {
                        # Non-interactive default to configuring automatically
                        $shouldConfig = $true
                    }
                }

                if ($shouldConfig) {
                    $hookCmd = '/mnt/c/Windows/System32/schtasks.exe /run /tn DisableEthernetForwarding'
                    $pyOrBashScript = @"
if [ ! -f /etc/wsl.conf ]; then
    printf '[boot]\nsystemd=true\ncommand=\"$hookCmd\"\n' > /etc/wsl.conf
else
    if grep -q '^\[boot\]' /etc/wsl.conf; then
        if grep -q 'command[[:space:]]*=' /etc/wsl.conf; then
            sed -i '/command[[:space:]]*=/ s|\"$|; $hookCmd\"|' /etc/wsl.conf
        else
            sed -i '/^\[boot\]/a command=\"$hookCmd\"' /etc/wsl.conf
        fi
    else
        printf '\n[boot]\nsystemd=true\ncommand=\"$hookCmd\"\n' >> /etc/wsl.conf
    fi
fi
"@
                    wsl.exe -d $distro -u root bash -c $pyOrBashScript
                    Write-Host "  [✓] 已成功为 WSL 分发版 [$distro] 注入启动 Hook (/etc/wsl.conf)" -ForegroundColor Green
                } else {
                    Write-Host "  [i] 已跳过自动配置。您可以手动在 WSL 的 /etc/wsl.conf 中添加:" -ForegroundColor Cyan
                    Write-Host "      [boot]`n      systemd=true`n      command=`"/mnt/c/Windows/System32/schtasks.exe /run /tn DisableEthernetForwarding`"" -ForegroundColor Gray
                }
            }
        }
    }
} else {
    Write-Host "  [-] 系统未安装 WSL 命令，跳过 WSL 检测。" -ForegroundColor Gray
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "   补丁部署完成！WSL 镜像网络与 TUN 代理已可正常共存。   " -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host ""
if (-not $AutoWSL -and -not $NonInteractive -and [Environment]::UserInteractive) {
    Write-Host "按任意键退出..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
