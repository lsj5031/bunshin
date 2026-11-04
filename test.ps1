#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Join-Path $env:TEMP 'bunshin-test'
Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue

$src = Join-Path $root 'src'
New-Item -ItemType Directory -Force (Join-Path $src 'sub\deep'), (Join-Path $src 'empty') | Out-Null
'hello world' | Set-Content (Join-Path $src 'a.txt')
'unicode content' | Set-Content (Join-Path $src 'тест-文件.txt')
$bytes = New-Object byte[] 1048576
(New-Object Random 42).NextBytes($bytes)
[IO.File]::WriteAllBytes((Join-Path $src 'sub\b.bin'), $bytes)
'deep' | Set-Content (Join-Path $src 'sub\deep\c.txt')

$vc = Join-Path $PSScriptRoot 'bunshin.ps1'
$script:failed = 0

function Section {
    param([string] $Name)
    "`n[$Name]"
}

function Assert-Equal {
    param([string] $Label, $Actual, $Expected)
    if ($Actual -eq $Expected) {
        "  ok   $Label = $Actual"
    } else {
        "  FAIL ${Label}: got '$Actual', expected '$Expected'"
        $script:failed++
    }
}

function Assert-True {
    param([string] $Label, $Condition)
    if ($Condition) {
        "  ok   $Label"
    } else {
        "  FAIL $Label"
        $script:failed++
    }
}

$dest1 = Join-Path $root 'dest1'
$sourceA = Join-Path $src 'a.txt'
$destA = Join-Path $dest1 'src\a.txt'

Section '1. clean copy + verify'
& $vc $src $dest1 -Verify -Quiet
Assert-Equal 'exit' $LASTEXITCODE 0
Assert-True 'empty dir copied' (Test-Path (Join-Path $dest1 'src\empty'))
Assert-True 'unicode filename' (Test-Path (Join-Path $dest1 'src\тест-文件.txt'))
Assert-True 'nested file' (Test-Path (Join-Path $dest1 'src\sub\deep\c.txt'))

Section '2. verify-only on the clean tree'
& $vc $src $dest1 -VerifyOnly -Quiet
Assert-Equal 'exit' $LASTEXITCODE 0

Section '3. corrupt destination, verify-only (same size, same timestamp)'
# a.txt is "hello world" + CRLF = 13 bytes. Corrupt it with 13 bytes so robocopy
# cannot detect the damage by size.
[IO.File]::WriteAllText($destA, "aello world`r`n")
(Get-Item -LiteralPath $destA).LastWriteTimeUtc = (Get-Item -LiteralPath $sourceA).LastWriteTimeUtc
Assert-Equal 'corrupt size' (Get-Item -LiteralPath $destA).Length (Get-Item -LiteralPath $sourceA).Length

$logDir = Join-Path $root 'logs'
& $vc $src $dest1 -VerifyOnly -Quiet -LogDirectory $logDir
Assert-Equal 'exit' $LASTEXITCODE 2
$log = Get-Content -LiteralPath (Get-ChildItem $logDir -Filter *.log | Sort-Object LastWriteTime | Select-Object -Last 1).FullName -Raw
Assert-True 'log names the mismatch' ($log -match 'Mismatch' -and $log -match 'a\.txt')

Section '4. full copy + verify still catches it (robocopy skips the same file)'
& $vc $src $dest1 -Verify -Quiet
Assert-Equal 'exit' $LASTEXITCODE 2
Assert-True 'robocopy left the bad bytes in place' ([IO.File]::ReadAllText($destA) -like 'aello*')

Section '5. deleting the destination file repairs it'
Remove-Item -LiteralPath $destA -Force
& $vc $src $dest1 -Verify -Quiet
Assert-Equal 'exit' $LASTEXITCODE 0
Assert-True 'content restored' ((Get-Content -LiteralPath $destA -Raw) -eq "hello world`r`n")

Section '6. extra file in destination, then mirror'
'extra' | Set-Content (Join-Path $dest1 'src\extra.txt')
& $vc $src $dest1 -Mode Mirror -Force -Quiet
Assert-Equal 'exit' $LASTEXITCODE 0
Assert-True 'extra removed' (-not (Test-Path (Join-Path $dest1 'src\extra.txt')))

Section '7. single-file source'
& $vc $sourceA (Join-Path $root 'file-dest') -Verify -Quiet
Assert-Equal 'exit' $LASTEXITCODE 0
Assert-True 'file copied' (Test-Path (Join-Path $root 'file-dest\a.txt'))

Section '8. contents-only merge'
& $vc $src (Join-Path $root 'merged') -ContentsOnly -Verify -Quiet
Assert-Equal 'exit' $LASTEXITCODE 0
Assert-True 'contents merged, not nested' (Test-Path (Join-Path $root 'merged\a.txt'))
Assert-True 'not nested twice' (-not (Test-Path (Join-Path $root 'merged\src')))

Section '9. missing source'
$threw = $null
try { & $vc (Join-Path $root 'nope') $dest1 -Quiet } catch { $threw = $_.Exception.Message }
Assert-True 'throws Source not found' ($threw -match 'Source not found')

function Assert-Refused {
    param([string] $Label, [scriptblock] $Action, [string] $Pattern)
    $message = ''
    try { & $Action } catch { $message = $_.Exception.Message }
    Assert-True $Label ($message -match $Pattern)
}

Section '10. overlapping paths are refused before copying or moving'
Assert-Refused 'same tree' { & $vc $src $src -ContentsOnly -Quiet } 'overlap'
Assert-Refused 'child destination' { & $vc $src (Join-Path $src 'backup') -Quiet } 'overlap'
Assert-True 'child destination not created' (-not (Test-Path (Join-Path $src 'backup')))
Assert-Refused 'ancestor mirror' { & $vc $src $root -ContentsOnly -Mode Mirror -Force -Quiet } 'overlap'
Assert-Refused 'self move' { & $vc $sourceA $src -Mode Move -Quiet } 'overlap'
Assert-True 'source survived' (Test-Path $sourceA)
# A textual prefix alone is not containment.
& $vc $src (Join-Path $root 'src-backup') -ContentsOnly -Quiet
Assert-Equal 'sibling prefix allowed' $LASTEXITCODE 0

Section '11. ambiguous mirror plans are refused as a whole'
$second = Join-Path $root 'other\src'
New-Item -ItemType Directory -Path $second -Force | Out-Null
'second' | Set-Content (Join-Path $second 'unique.txt')
$mirrorDest = Join-Path $root 'unsafe-mirror'
Assert-Refused 'same leaf target' { & $vc $src,$second $mirrorDest -Mode Mirror -Force -Quiet } 'targets overlap'
Assert-Refused 'contents-only collision' { & $vc $src,$second $mirrorDest -ContentsOnly -Mode Mirror -Force -Quiet } 'targets overlap'
Assert-Refused 'single-file mirror' { & $vc $sourceA $mirrorDest -Mode Mirror -Force -Quiet } 'directory sources'
Assert-True 'refused plans created no destination' (-not (Test-Path $mirrorDest))

Section '12. all sources are validated before any destination write'
$untouched = Join-Path $root 'untouched'
Assert-Refused 'missing second source' { & $vc $src,(Join-Path $root 'absent') $untouched -Quiet } 'Source not found'
Assert-Refused 'missing verify source' { & $vc (Join-Path $root 'absent') $untouched -VerifyOnly -Quiet } 'Source not found'
Assert-True 'no destination created' (-not (Test-Path $untouched))

Section '13. verify-only skips junctions consistently with copy /XJ'
$external = Join-Path $root 'external'
New-Item -ItemType Directory -Path $external -Force | Out-Null
'outside' | Set-Content (Join-Path $external 'outside.txt')
$junction = Join-Path $src 'junction'
New-Item -ItemType Junction -Path $junction -Target $external | Out-Null
try {
    & $vc $src $dest1 -VerifyOnly -Quiet
    Assert-Equal 'external file is excluded' $LASTEXITCODE 0
    & $vc $src (Join-Path $root 'junction-copy') -Verify -Quiet
    Assert-Equal 'copy and verify agree' $LASTEXITCODE 0
    Assert-True 'junction not copied' (-not (Test-Path (Join-Path $root 'junction-copy\src\junction')))
    Assert-Refused 'source alias refused' { & $vc $junction (Join-Path $root 'alias-dest') -Quiet } 'Reparse'
} finally { [IO.Directory]::Delete($junction) }

Section '14. destination junctions cannot redirect copying or verification'
$destJunction = Join-Path $dest1 'src\sub'
Remove-Item -LiteralPath $destJunction -Recurse -Force
New-Item -ItemType Junction -Path $destJunction -Target $external | Out-Null
try {
    Assert-Refused 'nested destination junction' { & $vc $src $dest1 -Quiet } 'Reparse'
    & $vc $src $dest1 -VerifyOnly -Quiet
    Assert-Equal 'verification rejects redirected files' $LASTEXITCODE 2
    Assert-True 'external directory not written' (-not (Test-Path (Join-Path $external 'b.bin')))
} finally { [IO.Directory]::Delete($destJunction) }

Section '15. empty source with absent destination cannot verify successfully'
& $vc (Join-Path $src 'empty') (Join-Path $root 'absent-empty') -VerifyOnly -Quiet -LogDirectory $logDir
Assert-Equal 'empty missing destination exit' $LASTEXITCODE 2
Assert-True 'read-only destination remains absent' (-not (Test-Path (Join-Path $root 'absent-empty')))
& $vc (Join-Path $src 'empty') (Join-Path $root 'file-dest') -VerifyOnly -Quiet -LogDirectory $logDir
Assert-Equal 'missing empty target in existing destination exit' $LASTEXITCODE 2

Section '16. unreadable source files fail verification and leave evidence'
$locked = [IO.File]::Open($sourceA, 'Open', 'ReadWrite', 'None')
try {
    & $vc $sourceA (Join-Path $root 'file-dest') -VerifyOnly -Quiet -LogDirectory $logDir
    Assert-Equal 'locked source exit' $LASTEXITCODE 2
} finally { $locked.Dispose() }
$latest = Get-ChildItem $logDir -Filter *.log | Sort-Object LastWriteTime | Select-Object -Last 1
Assert-True 'read error logged' ((Get-Content $latest.FullName -Raw) -match 'Error:')

Section '17. inaccessible source directory is a logged verification failure'
$denied = Join-Path $root 'denied'
New-Item -ItemType Directory -Path $denied | Out-Null
'hidden' | Set-Content (Join-Path $denied 'hidden.txt')
$acl = Get-Acl $denied
$denyAcl = Get-Acl $denied
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
$rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'ListDirectory', 'Deny')
$denyAcl.AddAccessRule($rule)
try {
    Set-Acl -LiteralPath $denied -AclObject $denyAcl
    & $vc $denied (Join-Path $root 'file-dest') -VerifyOnly -Quiet -LogDirectory $logDir
    Assert-Equal 'inaccessible enumeration exit' $LASTEXITCODE 2
} finally { Set-Acl -LiteralPath $denied -AclObject $acl }
$latest = Get-ChildItem $logDir -Filter *.log | Sort-Object LastWriteTime | Select-Object -Last 1
Assert-True 'enumeration error logged' ((Get-Content $latest.FullName -Raw) -match 'Cannot enumerate')

Section '18. logs preserve all sources and verification remains opt-in'
$runLogs = Join-Path $root 'combined-logs'
& $vc $src,$second (Join-Path $root 'combined') -Verify -Quiet -LogDirectory $runLogs
Assert-Equal 'multi-source verified exit' $LASTEXITCODE 0
$combinedLog = Get-ChildItem $runLogs -Filter 'bunshin-*.log' | Select-Object -First 1
$text = Get-Content $combinedLog.FullName -Raw
# Robocopy expands 8.3 aliases (including the hosted runner's TEMP path).
Assert-True 'first source retained' ($text.Contains((Get-Item -LiteralPath $src).FullName))
Assert-True 'second source retained' ($text.Contains((Get-Item -LiteralPath $second).FullName))
Assert-True 'verification verdict retained' ($text -match 'all files verified')
# With unchanged size/mtime, plain copy must still skip hashing by default.
$singleDest = Join-Path $root 'file-dest\a.txt'
[IO.File]::WriteAllText($singleDest, "aello world`r`n")
(Get-Item $singleDest).LastWriteTimeUtc = (Get-Item $sourceA).LastWriteTimeUtc
& $vc $sourceA (Join-Path $root 'file-dest') -Quiet -LogDirectory $runLogs
Assert-Equal 'plain copy does not verify' $LASTEXITCODE 0
& $vc $sourceA (Join-Path $root 'file-dest') -VerifyOnly -Quiet -LogDirectory $runLogs
Assert-Equal 'opt-in detects corruption' $LASTEXITCODE 2

Section '19. incomplete source enumeration aborts the entire mirror plan'
$mirrorA = Join-Path $root 'mirror-a'
$mirrorB = Join-Path $root 'mirror-b'
$blocked = Join-Path $mirrorB 'blocked'
$mirrorOutput = Join-Path $root 'mirror-output'
New-Item -ItemType Directory -Path $mirrorA,$blocked | Out-Null
'first' | Set-Content (Join-Path $mirrorA 'first.txt')
'blocked' | Set-Content (Join-Path $blocked 'hidden.txt')
& $vc $mirrorA,$mirrorB $mirrorOutput -Quiet
$extraA = Join-Path $mirrorOutput 'mirror-a\extra.txt'
$extraB = Join-Path $mirrorOutput 'mirror-b\extra.txt'
$extraBlocked = Join-Path $mirrorOutput 'mirror-b\blocked\extra.txt'
foreach ($extra in $extraA,$extraB,$extraBlocked) { 'preserve me' | Set-Content $extra }
$originalAcl = Get-Acl $blocked
$blockedAcl = Get-Acl $blocked
$blockedAcl.AddAccessRule($rule)
try {
    Set-Acl -LiteralPath $blocked -AclObject $blockedAcl
    Assert-Refused 'mirror scan failure is fatal' { & $vc $mirrorA,$mirrorB $mirrorOutput -Mode Mirror -Force -Quiet } 'enumerat'
    foreach ($extra in $extraA,$extraB,$extraBlocked) {
        Assert-True "extra preserved: $extra" (Test-Path -LiteralPath $extra)
    }
} finally { Set-Acl -LiteralPath $blocked -AclObject $originalAcl }

Section '20. extended path spellings cannot hide cross-source overlap'
$aliasSource = Join-Path $root 'alias-original\photos'
$aliasOutput = Join-Path $root 'alias-backup'
$queuedSource = Join-Path $aliasOutput 'photos'
New-Item -ItemType Directory -Path $aliasSource,$queuedSource -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $aliasSource 'sentinel.txt'), 'FIRST SOURCE BYTES')
foreach ($extendedDestination in @($false, $true)) {
    [IO.File]::WriteAllText((Join-Path $queuedSource 'sentinel.txt'), 'SECOND SOURCE MUST SURVIVE')
    $queuedPath = if ($extendedDestination) { $queuedSource } else { '\\?\' + $queuedSource }
    $outputPath = if ($extendedDestination) { '\\?\' + $aliasOutput } else { $aliasOutput }
    Assert-Refused "mixed extended overlap refused (destination=$extendedDestination)" {
        & $vc -Path @($aliasSource,$queuedPath) -Destination $outputPath -Quiet
    } 'overlap'
    Assert-Equal 'queued source bytes preserved' ([IO.File]::ReadAllText((Join-Path $queuedSource 'sentinel.txt'))) 'SECOND SOURCE MUST SURVIVE'
}

"`n$($script:failed) failure(s)"
exit ([int]($script:failed -gt 0))
