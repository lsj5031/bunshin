#Requires -Version 5.1
<#
.SYNOPSIS
    SendTo entry point: pick a destination folder, then run bunshin.ps1 with verification.

.DESCRIPTION
    Explains itself: receives the paths selected in Explorer's "Send to" menu,
    asks for a destination with a folder picker, then copies with verification.
#>
[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Paths
)

$ErrorActionPreference = 'Stop'
$core = Join-Path $PSScriptRoot 'bunshin.ps1'

if (-not $Paths -or $Paths.Count -eq 0) {
    Write-Host 'No files were passed. Use this from Explorer: right-click -> Send to -> Bunshin.' -ForegroundColor Yellow
    Read-Host 'Press Enter to close'
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms

$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = "Copy $($Paths.Count) item(s) to..."
$dialog.ShowNewFolderButton = $true
if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
    Write-Host 'Cancelled.' -ForegroundColor Yellow
    Start-Sleep -Milliseconds 400
    exit 0
}

$destination = $dialog.SelectedPath
Write-Host "`nCopying $($Paths.Count) item(s) to $destination ...`n" -ForegroundColor Cyan

& $core -Path $Paths -Destination $destination -Verify
$code = $LASTEXITCODE

switch ($code) {
    0 { Write-Host "`nDone - all files verified." -ForegroundColor Green }
    2 { Write-Host "`nCopy finished, but verification FAILED. See log above." -ForegroundColor Red }
    default { Write-Host "`nCopy reported errors (exit $code). See log above." -ForegroundColor Red }
}

Read-Host 'Press Enter to close'
exit $code
