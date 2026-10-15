<#
.SYNOPSIS
    Disables IPv4 Forwarding on connected physical network adapters in Windows.
.DESCRIPTION
    Fixes the issue where WSL2 Mirrored Networking (networkingMode=mirrored) causes
    Windows Host Network Service (HNS) to enable Forwarding on physical adapters in ActiveStore,
    which triggers loopback deadlocks in Mihomo / Clash TUN proxy modes (Mihomo #3186, #3229).
.LINK
    https://naivezip.github.io/2026/10/12/wsl2-mirrored-tun-loopback-deadlock/
    https://github.com/naivezip/wsl-mirrornetwork-patch
#>

[CmdletBinding()]
param(
    [switch]$VerboseOutput
)

try {
    # Match connected interfaces with Forwarding Enabled, excluding virtual/tunnel/container interfaces
    $excludePattern = 'vEthernet|Loopback|Mihomo|Clash|Sing-box|Tailscale|ZeroTier|VMware|VirtualBox|Radmin|utun|wintun|tap|wireguard|docker|container'
    
    $interfaces = Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $_.ConnectionState -eq 'Connected' -and
        $_.Forwarding -eq 'Enabled' -and
        $_.InterfaceAlias -notmatch $excludePattern
    }

    if ($VerboseOutput) {
        Write-Host "Checking network interfaces for IPv4 Forwarding..." -ForegroundColor Cyan
    }

    $count = 0
    foreach ($if in $interfaces) {
        if ($VerboseOutput) {
            Write-Host "[+] Disabling IPv4 Forwarding on: $($if.InterfaceAlias) (Index: $($if.InterfaceIndex))" -ForegroundColor Green
        }
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
    if ($VerboseOutput) {
        Write-Error "Error disabling interface forwarding: $_"
    }
}
