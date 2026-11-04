#Requires -Version 7.0
<#
.SYNOPSIS
    Records the showcase scenarios to an asciinema v2 cast.

.DESCRIPTION
    Runs real Bunshin commands and writes their real output with wall-clock
    timings, so the file plays back as a terminal session. No editing, no
    staged text: the numbers are from this machine.
#>
[CmdletBinding()]
param(
    [string] $OutFile = (Join-Path $PSScriptRoot 'bunshin-demo.cast')
)

$ErrorActionPreference = 'Stop'
$vc = Join-Path $PSScriptRoot '..\bunshin.ps1'
$root = Join-Path $env:TEMP 'bunshin-demo'
$start = [DateTime]::UtcNow
$events = [System.Collections.Generic.List[string]]::new()

function Emit {
    param([string] $Text)
    $seconds = [math]::Round(([DateTime]::UtcNow - $start).TotalSeconds, 3)
    $events.Add(('[{0}, "o", {1}]' -f $seconds, ($Text | ConvertTo-Json -Compress)))
}

function Say {
    param([string] $Text)
    Emit ($Text + "`r`n")
}

function Run-Bunshin {
    param([hashtable] $Parameters)
    $shown = ($Parameters.GetEnumerator() | Sort-Object Name |
        ForEach-Object { '-{0} {1}' -f $_.Key, $_.Value }) -join ' '
    Say ('PS> .\bunshin.ps1 ' + $shown)
    $output = & $vc @Parameters *>&1
    foreach ($line in $output) { Say ([string]$line) }
    Say ("exit code: $LASTEXITCODE`r`n")
    Start-Sleep -Milliseconds 700
}

# ------------------------------------------------------------------ setup ---

Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
$src = Join-Path $root 'photos'
New-Item -ItemType Directory -Force (Join-Path $src '2024'), (Join-Path $src 'empty') | Out-Null
'hello world' | Set-Content (Join-Path $src 'a.txt')
$bytes = New-Object byte[] 524288
(New-Object Random 3).NextBytes($bytes)
[IO.File]::WriteAllBytes((Join-Path $src '2024\b.bin'), $bytes)
'unicode' | Set-Content (Join-Path $src 'тест-文件.txt')

Say 'Bunshin - Copy. Verify. Be sure.'
Say '------------------------------------'
Say ''

# ------------------------------------------------------------------ scene ---

Say '1. copy + verify, clean'
Run-Bunshin -Parameters @{ Path = $src; Destination = (Join-Path $root 'backup'); Verify = $true }

Say '2. same file, corrupted in place (same size, same timestamp)'
$bad = Join-Path $root 'backup\photos\a.txt'
[IO.File]::WriteAllText($bad, "aello world`r`n")
(Get-Item -LiteralPath $bad).LastWriteTimeUtc = (Get-Item -LiteralPath (Join-Path $src 'a.txt')).LastWriteTimeUtc
Say "   (dest a.txt is $((Get-Item $bad).Length) bytes, same mtime as source)"

Say '3. re-check the archive without copying anything'
Run-Bunshin -Parameters @{ Path = $src; Destination = (Join-Path $root 'backup'); VerifyOnly = $true }

Say '4. the same corruption, this time during a normal copy'
Run-Bunshin -Parameters @{ Path = $src; Destination = (Join-Path $root 'backup'); Verify = $true }

Say '5. mirror, unattended, without -Force'
'extra' | Set-Content (Join-Path $root 'backup\photos\extra.txt')
Run-Bunshin -Parameters @{ Path = $src; Destination = (Join-Path $root 'backup'); Mode = 'Mirror'; Quiet = $true }

Say '6. mirror, confirmed'
Run-Bunshin -Parameters @{ Path = $src; Destination = (Join-Path $root 'backup'); Mode = 'Mirror'; Force = $true }

Say 'done - logs are under %LOCALAPPDATA%\bunshin\logs'

# ----------------------------------------------------------------- output ---

$header = '{"version": 2, "width": 104, "height": 34, "timestamp": ' +
          [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + ', "env": {"SHELL": "pwsh", "TERM": "xterm-256color"}}'

$lines = @($header) + $events
Set-Content -LiteralPath $OutFile -Value $lines -Encoding utf8

Write-Host "Wrote $OutFile" -ForegroundColor Green
Write-Host ("{0} events, {1:0.0}s" -f $events.Count, ([DateTime]::UtcNow - $start).TotalSeconds) -ForegroundColor Gray
Write-Host "Play: asciinema play $OutFile" -ForegroundColor Cyan
