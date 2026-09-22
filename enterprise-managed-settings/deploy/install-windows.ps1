<#
.SYNOPSIS
    Install a managed-settings file into the Windows file-based policy location.

.DESCRIPTION
    File-based delivery is the fastest way to demo enterprise managed settings:
    no enterprise, no .github-private repository, no MDM server. It applies to
    whoever is signed in on this machine.

    Run from an elevated PowerShell prompt.

.EXAMPLE
    .\install-windows.ps1 ..\scenarios\01-lock-down-bypass.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Source
)

$ErrorActionPreference = "Stop"

$targetDir = Join-Path $env:ProgramFiles "GitHubCopilot"
$target = Join-Path $targetDir "managed-settings.json"
$backup = "$target.demo-backup"

if (-not (Test-Path $Source)) {
    throw "$Source does not exist"
}

# A malformed policy is rejected outright, which is a confusing way to discover
# a typo mid-demo.
try {
    Get-Content $Source -Raw | ConvertFrom-Json | Out-Null
} catch {
    throw "$Source is not valid JSON: $_"
}

$identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this from an elevated PowerShell prompt: $targetDir is not user-writable."
}

New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

if ((Test-Path $target) -and -not (Test-Path $backup)) {
    Write-Host "Backing up the existing policy to $backup"
    Copy-Item $target $backup
}

Copy-Item $Source $target -Force

Write-Host ""
Write-Host "Installed -> $target"
Write-Host ""
Get-Content $target
Write-Host ""
Write-Host "Restart the GitHub Copilot app so it reloads policy at startup."
Write-Host "Then confirm what the runtime actually enforced:"
Write-Host ""
Write-Host "  cd ..\..\validate; npm install; node validate-managed-settings.mjs"
