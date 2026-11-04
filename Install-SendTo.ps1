#Requires -Version 5.1
<#
.SYNOPSIS
    Adds (or removes) the "Bunshin" entry to the Explorer Send To menu.

.DESCRIPTION
    Creates a shortcut in the current user's SendTo folder. No admin rights and
    no registry changes - delete the shortcut from shell:sendto to undo.
#>
[CmdletBinding()]
param(
    [switch] $Uninstall,
    [string] $SendToDirectory = [Environment]::GetFolderPath('SendTo')
)

$ErrorActionPreference = 'Stop'

$sendTo = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SendToDirectory)
$linkPath = Join-Path $sendTo 'Bunshin.lnk'
$scriptPath = Join-Path $PSScriptRoot 'SendTo-Bunshin.ps1'

if ($Uninstall) {
    if (Test-Path -LiteralPath $linkPath) {
        Remove-Item -LiteralPath $linkPath -Force
        Write-Host "Removed $linkPath" -ForegroundColor Green
    } else {
        Write-Host 'Nothing to remove.' -ForegroundColor Yellow
    }
    exit 0
}

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Missing $scriptPath"
}

New-Item -ItemType Directory -Path $sendTo -Force | Out-Null
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($linkPath)
$link.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$link.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $scriptPath
$link.WorkingDirectory = $PSScriptRoot
$iconPath = Join-Path $PSScriptRoot 'Branding\bunshin.ico'
if (-not (Test-Path -LiteralPath $iconPath)) { $iconPath = Join-Path $PSScriptRoot 'gui\Branding\bunshin.ico' }
$link.IconLocation = "$iconPath,0"
$link.Description = 'Copy with SHA-256 verification (robocopy)'
$link.Save()

Write-Host "Installed: $linkPath" -ForegroundColor Green
Write-Host 'Right-click any file or folder -> Send to -> Bunshin' -ForegroundColor Cyan
exit 0
