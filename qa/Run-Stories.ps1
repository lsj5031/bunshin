#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the automated user stories against bunshin.ps1 and updates features.csv.

.DESCRIPTION
    One Test-Story block per feature id in features.csv. Results are written to
    qa/results.csv and merged back into the canonical spreadsheet, so the live
    dashboard shows the new statuses as soon as this exits.

    Stories that need a human (Explorer, drag and drop) are left as Implemented.
#>
[CmdletBinding()]
param(
    [string] $FeatureFile,
    [string] $ResultFile,
    [string] $WorkRoot = (Join-Path $env:TEMP 'bunshin-qa')
)

$ErrorActionPreference = 'Stop'
# In Windows PowerShell -File, PSScriptRoot is unavailable in parameter defaults.
if (-not $FeatureFile) { $FeatureFile = Join-Path $PSScriptRoot '..\features.csv' }
if (-not $ResultFile) { $ResultFile = Join-Path $PSScriptRoot 'results.csv' }
$vc = Join-Path $PSScriptRoot '..\bunshin.ps1'
$script:results = [ordered]@{}

function Assert-Equal {
    param($Actual, $Expected, [string] $What)
    if ($Actual -ne $Expected) { throw "$What expected '$Expected', got '$Actual'" }
}

function Assert-True {
    param([bool] $Condition, [string] $What)
    if (-not $Condition) { throw "$What" }
}

function Test-Story {
    param([string] $Id, [string] $Name, [scriptblock] $Body)
    try {
        & $Body
        $script:results[$Id] = [pscustomobject]@{ Status = 'Verified'; Evidence = $Name }
        Write-Host "  PASS  $Id  $Name" -ForegroundColor Green
    } catch {
        $script:results[$Id] = [pscustomobject]@{ Status = 'Failed'; Evidence = "$Name - $($_.Exception.Message)" }
        Write-Host "  FAIL  $Id  $Name :: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function New-SourceTree {
    param([string] $Path, [string] $Label = 'source')
    New-Item -ItemType Directory -Force (Join-Path $Path 'sub\deep'), (Join-Path $Path 'empty') | Out-Null
    "$Label one`r`n" | Set-Content (Join-Path $Path 'a.txt')
    'unicode content' | Set-Content (Join-Path $Path 'тест-文件.txt')
    $bytes = New-Object byte[] 524288
    (New-Object Random 7).NextBytes($bytes)
    [IO.File]::WriteAllBytes((Join-Path $Path 'sub\b.bin'), $bytes)
    'deep' | Set-Content (Join-Path $Path 'sub\deep\c.txt')
}

Remove-Item $WorkRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $WorkRoot | Out-Null
$src = Join-Path $WorkRoot 'src'
New-SourceTree $src

Write-Host "`nbunshin story suite" -ForegroundColor Cyan
Write-Host "work: $WorkRoot`n" -ForegroundColor Gray

# ---------------------------------------------------------------- core ---

Test-Story C01 'folder copy nests the folder' {
    $dest = Join-Path $WorkRoot 'c01'
    & $vc $src $dest -Quiet
    Assert-Equal $LASTEXITCODE 0 'exit'
    Assert-True (Test-Path (Join-Path $dest 'src\sub\deep\c.txt')) 'nested file missing'
}

Test-Story C02 'contents-only merges into the destination' {
    $dest = Join-Path $WorkRoot 'c02'
    & $vc $src $dest -ContentsOnly -Quiet
    Assert-Equal $LASTEXITCODE 0 'exit'
    Assert-True (Test-Path (Join-Path $dest 'a.txt')) 'a.txt missing at the root'
    Assert-True (-not (Test-Path (Join-Path $dest 'src'))) 'unexpected extra folder level'
}

Test-Story C03 'single file lands in the destination folder' {
    $dest = Join-Path $WorkRoot 'c03'
    & $vc (Join-Path $src 'a.txt') $dest -Quiet
    Assert-Equal $LASTEXITCODE 0 'exit'
    Assert-True (Test-Path (Join-Path $dest 'a.txt')) 'a.txt missing'
}

Test-Story C04 'several sources in one run' {
    $second = Join-Path $WorkRoot 'src2'
    New-SourceTree $second 'second'
    $dest = Join-Path $WorkRoot 'c04'
    & $vc $src, $second $dest -Quiet
    Assert-Equal $LASTEXITCODE 0 'exit'
    Assert-True (Test-Path (Join-Path $dest 'src\a.txt')) 'first source missing'
    Assert-True (Test-Path (Join-Path $dest 'src2\a.txt')) 'second source missing'
}

Test-Story C05 'mirror deletes extra destination files' {
    $dest = Join-Path $WorkRoot 'c05'
    & $vc $src $dest -Quiet
    'extra' | Set-Content (Join-Path $dest 'src\extra.txt')
    & $vc $src $dest -Mode Mirror -Force -Quiet
    Assert-Equal $LASTEXITCODE 0 'exit'
    Assert-True (-not (Test-Path (Join-Path $dest 'src\extra.txt'))) 'extra file survived the mirror'
}

Test-Story C06 'unattended mirror without -Force is refused' {
    $dest = Join-Path $WorkRoot 'c06'
    & $vc $src $dest -Quiet
    'extra' | Set-Content (Join-Path $dest 'src\extra.txt')
    & $vc $src $dest -Mode Mirror -Quiet
    Assert-Equal $LASTEXITCODE 3 'exit'
    Assert-True (Test-Path (Join-Path $dest 'src\extra.txt')) 'file was deleted without confirmation'
}

Test-Story C07 'move removes the source' {
    $moveSrc = Join-Path $WorkRoot 'move-src'
    New-SourceTree $moveSrc 'move'
    $dest = Join-Path $WorkRoot 'c07'
    & $vc $moveSrc $dest -Mode Move -Quiet
    Assert-Equal $LASTEXITCODE 0 'exit'
    Assert-True (Test-Path (Join-Path $dest 'move-src\a.txt')) 'moved file missing'
    Assert-True (-not (Test-Path (Join-Path $moveSrc 'a.txt'))) 'source survived the move'
}

Test-Story C08 'clean copy verifies by SHA-256' {
    $dest = Join-Path $WorkRoot 'c08'
    & $vc $src $dest -Verify -Quiet
    Assert-Equal $LASTEXITCODE 0 'exit'
}

Test-Story C09 'verify-only passes a clean tree' {
    $dest = Join-Path $WorkRoot 'c09'
    & $vc $src $dest -Quiet
    & $vc $src $dest -VerifyOnly -Quiet
    Assert-Equal $LASTEXITCODE 0 'exit'
}

Test-Story C10 'verify detects a same-size corrupt file' {
    $dest = Join-Path $WorkRoot 'c10'
    & $vc $src $dest -Quiet
    $bad = Join-Path $dest 'src\a.txt'
    [IO.File]::WriteAllText($bad, "aello world`r`n")
    (Get-Item -LiteralPath $bad).LastWriteTimeUtc = (Get-Item -LiteralPath (Join-Path $src 'a.txt')).LastWriteTimeUtc
    & $vc $src $dest -VerifyOnly -Quiet
    Assert-Equal $LASTEXITCODE 2 'exit'
}

Test-Story C11 'empty directories are preserved' {
    $dest = Join-Path $WorkRoot 'c11'
    & $vc $src $dest -Quiet
    Assert-True (Test-Path (Join-Path $dest 'src\empty')) 'empty dir missing'
}

Test-Story C12 'unicode filenames survive the copy' {
    $dest = Join-Path $WorkRoot 'c12'
    & $vc $src $dest -Verify -Quiet
    Assert-Equal $LASTEXITCODE 0 'exit'
    Assert-True (Test-Path (Join-Path $dest 'src\тест-文件.txt')) 'unicode file missing'
}

Test-Story C18 'each run writes a log' {
    $logs = Join-Path $WorkRoot 'logs-c18'
    & $vc $src (Join-Path $WorkRoot 'c18') -Quiet -LogDirectory $logs
    $file = Get-ChildItem $logs -Filter *.log | Select-Object -First 1
    Assert-True ($null -ne $file) 'no log written'
    Assert-True ((Get-Content -LiteralPath $file.FullName -Raw) -match 'Ended') 'log has no robocopy summary'
}

Test-Story C19 'verify-only writes its own log' {
    $dest = Join-Path $WorkRoot 'c19'
    & $vc $src $dest -Quiet
    $logs = Join-Path $WorkRoot 'logs-c19'
    & $vc $src $dest -VerifyOnly -Quiet -LogDirectory $logs
    $file = Get-ChildItem $logs -Filter *.log | Select-Object -First 1
    Assert-True ($null -ne $file) 'no verify log written'
    Assert-True ((Get-Content -LiteralPath $file.FullName -Raw) -match 'all files verified') 'log does not record success'
}

Test-Story C20 'quiet mode prints nothing' {
    $output = & $vc $src (Join-Path $WorkRoot 'c20') -Quiet 6>&1 | Out-String
    Assert-Equal $output.Trim() '' 'output'
    Assert-Equal $LASTEXITCODE 0 'exit'
}

Test-Story C21 'exit codes are 0, 2 and 3' {
    $ok = Join-Path $WorkRoot 'c21-ok'
    & $vc $src $ok -Quiet
    Assert-Equal $LASTEXITCODE 0 'success exit'
    [IO.File]::WriteAllText((Join-Path $ok 'src\a.txt'), "aello world`r`n")
    (Get-Item (Join-Path $ok 'src\a.txt')).LastWriteTimeUtc = (Get-Item (Join-Path $src 'a.txt')).LastWriteTimeUtc
    & $vc $src $ok -VerifyOnly -Quiet
    Assert-Equal $LASTEXITCODE 2 'verify exit'
    'extra' | Set-Content (Join-Path $ok 'src\extra.txt')
    & $vc $src $ok -Mode Mirror -Quiet
    Assert-Equal $LASTEXITCODE 3 'mirror abort exit'
}

Test-Story C22 'a missing source fails loudly' {
    $message = $null
    try { & $vc (Join-Path $WorkRoot 'does-not-exist') (Join-Path $WorkRoot 'x') -Quiet }
    catch { $message = $_.Exception.Message }
    Assert-True ($message -match 'Source not found') "unexpected error: $message"
}

Test-Story C23 'the destination is created for a copy' {
    $dest = Join-Path $WorkRoot 'c23\deep\new'
    & $vc $src $dest -Quiet
    Assert-Equal $LASTEXITCODE 0 'exit'
    Assert-True (Test-Path $dest) 'destination not created'
}

Test-Story C24 'verify-only does not create the destination' {
    $dest = Join-Path $WorkRoot 'c24-missing'
    & $vc $src $dest -VerifyOnly -Quiet
    Assert-Equal $LASTEXITCODE 2 'exit'
    Assert-True (-not (Test-Path $dest)) 'destination was created by a read-only check'
}

Test-Story C27 'move plus verify is refused' {
    $message = $null
    try { & $vc $src (Join-Path $WorkRoot 'c27') -Mode Move -Verify -Quiet }
    catch { $message = $_.Exception.Message }
    Assert-True ($message -match 'Move') "expected a refusal, got: $message"
}

Test-Story C13 'a path longer than 260 characters' {
    $deep = Join-Path $WorkRoot 'long'
    foreach ($i in 1..6) { $deep = Join-Path $deep ('segment-' + ('x' * 28)) }
    # WinPS 5.1's Set-Content cannot create this fixture without an extended path.
    [IO.Directory]::CreateDirectory(('\\?\' + $deep)) | Out-Null
    [IO.File]::WriteAllText(('\\?\' + (Join-Path $deep 'f.txt')), 'long')
    $dest = Join-Path $WorkRoot 'c13'
    & $vc $deep $dest -Verify -Quiet
    Assert-Equal $LASTEXITCODE 0 'exit'
}

Test-Story S01 'sandbox install: quoted bundle path and real shortcut command' {
    $bundle = Join-Path $WorkRoot 'portable bundle with spaces'
    $sandbox = Join-Path $WorkRoot 'sandbox SendTo with spaces'
    New-Item -ItemType Directory -Path $bundle -Force | Out-Null
    $bundle = (Get-Item -LiteralPath $bundle).FullName # Match the installer's expanded PSScriptRoot.
    foreach ($name in 'Install-SendTo.ps1', 'SendTo-Bunshin.ps1', 'bunshin.ps1') {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "..\$name") -Destination $bundle
    }
    & (Join-Path $bundle 'Install-SendTo.ps1') -SendToDirectory $sandbox
    Assert-Equal $LASTEXITCODE 0 'installer exit'
    $shortcutPath = Join-Path $sandbox 'Bunshin.lnk'
    Assert-True (Test-Path -LiteralPath $shortcutPath) 'Bunshin shortcut missing'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    Assert-Equal $shortcut.TargetPath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') 'shortcut host'
    Assert-Equal $shortcut.Arguments ('-NoProfile -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $bundle 'SendTo-Bunshin.ps1')) 'quoted shortcut arguments'
    Assert-Equal $shortcut.WorkingDirectory $bundle 'working directory'
    # Execute the actual shortcut command without opening an interactive window.
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $shortcut.TargetPath
    $start.Arguments = $shortcut.Arguments
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($start)
    $process.StandardInput.WriteLine('')
    $process.StandardInput.Close()
    $output = $process.StandardOutput.ReadToEnd()
    $errors = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    Assert-Equal $process.ExitCode 1 'no-selection command exit'
    Assert-True ($output -match 'No files were passed' -and $output -match 'Bunshin') "unexpected output: $output $errors"
    $process.Dispose()
    & (Join-Path $bundle 'bunshin.ps1') $src (Join-Path $WorkRoot 'copied into path with spaces') -Verify -Quiet
    Assert-Equal $LASTEXITCODE 0 'bundled core with spaces'
}

Test-Story S02 'sandbox uninstall is idempotent and preserves unrelated shortcuts' {
    $sandbox = Join-Path $WorkRoot 'sandbox SendTo with spaces'
    $installer = Join-Path $WorkRoot 'portable bundle with spaces\Install-SendTo.ps1'
    'leave alone' | Set-Content (Join-Path $sandbox 'unrelated.lnk')
    & $installer -SendToDirectory $sandbox -Uninstall
    Assert-Equal $LASTEXITCODE 0 'uninstall exit'
    Assert-True (-not (Test-Path (Join-Path $sandbox 'Bunshin.lnk'))) 'shortcut survived uninstall'
    Assert-True (Test-Path (Join-Path $sandbox 'unrelated.lnk')) 'unrelated shortcut was removed'
    & $installer -SendToDirectory $sandbox -Uninstall
    Assert-Equal $LASTEXITCODE 0 'second uninstall exit'
}

# -------------------------------------------------------------- report ---

$resultRows = foreach ($id in $script:results.Keys) {
    [pscustomobject]@{
        id        = $id
        status    = $script:results[$id].Status
        evidence  = $script:results[$id].Evidence
        tested_at = (Get-Date -Format 's')
    }
}
$resultRows | Export-Csv -LiteralPath $ResultFile -NoTypeInformation -Encoding utf8

$features = Import-Csv -LiteralPath $FeatureFile
foreach ($row in $features) {
    if (-not $script:results.Contains($row.id)) { continue }
    $row.status = $script:results[$row.id].Status
    $row.evidence = $script:results[$row.id].Evidence
}
$features | Export-Csv -LiteralPath $FeatureFile -NoTypeInformation -Encoding utf8

$failed = @($resultRows | Where-Object status -eq 'Failed')
$passed = $resultRows.Count - $failed.Count
Write-Host ("`n{0} stories run, {1} passed, {2} failed" -f $resultRows.Count, $passed, $failed.Count) `
    -ForegroundColor $(if ($failed.Count) { 'Red' } else { 'Green' })
Write-Host "features.csv updated; dashboard reflects it" -ForegroundColor Gray

exit ([int]($failed.Count -gt 0))
