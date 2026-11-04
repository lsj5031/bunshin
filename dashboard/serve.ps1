#Requires -Version 5.1
<#
.SYNOPSIS
    Serves the project root so dashboard/index.html can read ../features.csv.

.DESCRIPTION
    The dashboard refreshes itself every 1.5s. This server does nothing else;
    edit features.csv (or let qa/Run-Stories.ps1 edit it) and watch the page.
#>
[CmdletBinding()]
param(
    [int] $Port = 8787,
    [switch] $NoBrowser
)

$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$url = "http://localhost:$Port/dashboard/"

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw 'python was not found on PATH; any static file server rooted at the project folder works.'
}

Write-Host "Serving $root" -ForegroundColor Cyan
Write-Host "Dashboard: $url" -ForegroundColor Green
Write-Host 'Ctrl+C to stop.' -ForegroundColor Gray

if (-not $NoBrowser) { Start-Process $url }

Set-Location $root
python -m http.server $Port --bind 127.0.0.1
