#Requires -Version 5.1
<#
.SYNOPSIS
  Capture iPhone Wi-Fi/Personal Hotspot network state before and after enabling hotspot.
.DESCRIPTION
  Uses only the OpenSSH client included with Windows 10/11. All commands on the
  iPhone are read-only. The three reports are written ONLY to the PC's Desktop.
.NOTES
  For reliable reconnects, configure SSH public-key authentication on your phone.
  Password authentication also works, but ssh.exe may ask again on each retry.
#>
[CmdletBinding()]
param(
    [string]$Device = 'mobile@10.5.5.187',
    [string]$OutputDirectory = (Join-Path $env:USERPROFILE 'Desktop'),
    [ValidateRange(1, 100)][int]$RetryCount = 10,
    [ValidateRange(1, 60)][int]$RetryDelaySeconds = 3
)

$ErrorActionPreference = 'Stop'
$ssh = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
if (-not (Test-Path -LiteralPath $ssh)) {
    throw "Windows OpenSSH client not found at $ssh. Enable 'OpenSSH Client' in Windows Optional Features."
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$beforePath = Join-Path $OutputDirectory 'wifi_before.txt'
$afterPath  = Join-Path $OutputDirectory 'wifi_after.txt'
$diffPath   = Join-Path $OutputDirectory 'wifi_diff.txt'

# One SSH session per snapshot. No scripts, settings, or temporary files are
# created on the phone. The markers delimit the four requested commands.
$remote = @'
printf '\n===== IFCONFIG =====\n'; ifconfig -a 2>&1
printf '\n===== NETSTAT =====\n'; netstat -rn -f inet 2>&1
printf '\n===== ROUTE =====\n'; route -n get default 2>&1
printf '\n===== FORWARDING =====\n'; sysctl net.inet.ip.forwarding 2>&1
printf '\n===== END =====\n'
'@
$remote = $remote -replace "`r", ''

function Get-Snapshot {
    param([string]$Destination, [int]$Attempts)

    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        Write-Host "SSH snapshot attempt $attempt/$Attempts -> $Device"
        # PowerShell 5.1 can treat native stderr as an error record. Keep
        # connection failures non-terminating so that the retry loop runs.
        $previousPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $output = @(& $ssh -T `
                -o ConnectTimeout=6 `
                -o ConnectionAttempts=1 `
                -o ServerAliveInterval=3 `
                -o ServerAliveCountMax=1 `
                -o StrictHostKeyChecking=accept-new `
                $Device $remote 2>&1 | ForEach-Object { $_.ToString() })
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousPreference
        }
        $body = $output -join "`n"

        # Do not accept a partial / interrupted SSH read as a valid snapshot.
        $complete = ($exitCode -eq 0) -and
            ($body -match '===== IFCONFIG =====') -and
            ($body -match '===== NETSTAT =====') -and
            ($body -match '===== ROUTE =====') -and
            ($body -match '===== FORWARDING =====') -and
            ($body -match '===== END =====')

        if ($complete) {
            $header = @(
                "# Recorded on Windows: $(Get-Date -Format o)",
                "# SSH target: $Device",
                '# Commands are read-only; all output is stored on the Windows PC.',
                ''
            )
            Set-Content -LiteralPath $Destination -Encoding UTF8 -Value ($header + $output)
            Write-Host "Saved: $Destination" -ForegroundColor Green
            return (Get-Content -LiteralPath $Destination -Raw)
        }

        Write-Warning "SSH snapshot failed/incomplete (exit $exitCode): $($body.Trim() -replace '[\r\n]+', ' ')"
        if ($attempt -lt $Attempts) {
            Start-Sleep -Seconds $RetryDelaySeconds
        }
    }
    throw "Could not get a complete network snapshot after $Attempts attempt(s). No partial output saved to $Destination."
}

function Get-Interface {
    param([string]$Text, [string]$Name)
    $escaped = [regex]::Escape($Name)
    $match = [regex]::Match($Text, "(?ms)^${escaped}: flags=.*?(?=^\S+: flags=|^===== NETSTAT =====|\z)")
    if (-not $match.Success) {
        return [pscustomobject]@{ Present = $false; AdminUp = $false; Link = 'unknown' }
    }
    $block = $match.Value
    $adminUp = $block -match '(?m)^\S+: flags=[^\r\n]*<[^>]*\bUP\b'
    $link = 'unknown'
    if ($block -match '(?m)^\s*status:\s*([^\r\n]+)') { $link = $Matches[1].Trim() }
    return [pscustomobject]@{ Present = $true; AdminUp = $adminUp; Link = $link }
}

function Get-DefaultInterface {
    param([string]$Text)
    $routePart = [regex]::Match($Text, '(?s)===== ROUTE =====(.*?)===== FORWARDING =====')
    if ($routePart.Success -and $routePart.Groups[1].Value -match '(?m)^\s*interface:\s*(\S+)') {
        return $Matches[1]
    }
    $netstatPart = [regex]::Match($Text, '(?s)===== NETSTAT =====(.*?)===== ROUTE =====')
    if ($netstatPart.Success) {
        foreach ($line in ($netstatPart.Groups[1].Value -split "`n")) {
            if ($line -match '^default\s+\S+\s+.*?\s+(\S+)\s*$') {
                return $Matches[1]
            }
        }
    }
    return 'unknown'
}

function Get-Forwarding {
    param([string]$Text)
    $part = [regex]::Match($Text, '(?s)===== FORWARDING =====(.*?)===== END =====')
    if ($part.Success -and $part.Groups[1].Value -match 'net\.inet\.ip\.forwarding\s*[:=]\s*([01])') {
        return [int]$Matches[1]
    }
    return $null
}

Write-Host 'STEP 1: Keep Personal Hotspot OFF and Wi-Fi connected to the source router.' -ForegroundColor Cyan
$before = Get-Snapshot -Destination $beforePath -Attempts 1

Write-Host ''
Read-Host 'STEP 2: Enable Personal Hotspot on the iPhone, then press Enter here'
$after = Get-Snapshot -Destination $afterPath -Attempts $RetryCount

# Built-in PowerShell diff; no git, diff.exe, or third-party tools required.
$left  = @(Get-Content -LiteralPath $beforePath | Where-Object { $_ -notmatch '^# ' })
$right = @(Get-Content -LiteralPath $afterPath  | Where-Object { $_ -notmatch '^# ' })
$changes = @(Compare-Object -ReferenceObject $left -DifferenceObject $right -SyncWindow 100)
$diffOutput = @(
    '# PowerShell line difference: - before-only; + after-only.',
    "# Before: $beforePath",
    "# After:  $afterPath",
    ''
)
foreach ($item in $changes) {
    $prefix = if ($item.SideIndicator -eq '<=') { '-' } else { '+' }
    $diffOutput += "$prefix $($item.InputObject)"
}
if ($changes.Count -eq 0) { $diffOutput += '(No line differences)' }
Set-Content -LiteralPath $diffPath -Encoding UTF8 -Value $diffOutput

$enBefore = Get-Interface -Text $before -Name 'en0'
$enAfter  = Get-Interface -Text $after  -Name 'en0'
$apBefore = Get-Interface -Text $before -Name 'ap1'
$apAfter  = Get-Interface -Text $after  -Name 'ap1'
$brBefore = Get-Interface -Text $before -Name 'bridge100'
$brAfter  = Get-Interface -Text $after  -Name 'bridge100'
$routeBefore = Get-DefaultInterface -Text $before
$routeAfter  = Get-DefaultInterface -Text $after
$fwdBefore = Get-Forwarding -Text $before
$fwdAfter  = Get-Forwarding -Text $after

function Format-Presence {
    param($Before, $After, [string]$Name)
    if (-not $Before.Present -and $After.Present) { return "$Name APPEARED after enabling hotspot" }
    if ($Before.Present -and $After.Present) { return "$Name was present both before and after" }
    if ($Before.Present -and -not $After.Present) { return "$Name DISAPPEARED after enabling hotspot" }
    return "$Name was not present in either snapshot"
}

Write-Host "`n===== DIVVY NETWORK SUMMARY =====" -ForegroundColor Cyan
if ($enBefore.Present -and $enAfter.Present -and $enBefore.AdminUp -and $enAfter.AdminUp) {
    Write-Host "en0: UP flag stayed set (before link=$($enBefore.Link), after link=$($enAfter.Link))."
    if ($enAfter.Link -eq 'inactive') { Write-Warning 'en0 is administratively UP but its link reports INACTIVE.' }
} else {
    Write-Host "en0: DID NOT stay administratively UP (before present/up=$($enBefore.Present)/$($enBefore.AdminUp); after=$($enAfter.Present)/$($enAfter.AdminUp))."
}
Write-Host (Format-Presence -Before $apBefore -After $apAfter -Name 'ap1')
Write-Host (Format-Presence -Before $brBefore -After $brAfter -Name 'bridge100')
Write-Host "Default IPv4 route interface: $routeBefore -> $routeAfter"
if ($routeBefore -ne 'pdp_ip0' -and $routeAfter -eq 'pdp_ip0') {
    Write-Host 'Default route SWITCHED to cellular (pdp_ip0).'
} elseif ($routeAfter -eq 'pdp_ip0') {
    Write-Host 'Default route uses cellular (pdp_ip0) after hotspot; it did not newly switch there.'
} elseif ($routeAfter -eq 'unknown') {
    Write-Host 'Default-route interface could not be determined.'
} else {
    Write-Host 'Default route did NOT switch to pdp_ip0.'
}
if ($null -eq $fwdBefore -or $null -eq $fwdAfter) {
    Write-Host 'ip.forwarding: unknown; check sysctl output for errors.'
} else {
    Write-Host "ip.forwarding: $fwdBefore -> $fwdAfter"
    if ($fwdBefore -eq 0 -and $fwdAfter -eq 1) { Write-Host 'IPv4 forwarding FLIPPED from 0 to 1.' }
    else { Write-Host 'IPv4 forwarding did NOT flip from 0 to 1.' }
}
Write-Host "`nReports: $beforePath; $afterPath; $diffPath" -ForegroundColor Green
Write-Host 'Reminder: these files may contain local IP addresses and hardware MAC addresses.'
