#Requires -Version 5.1
<#
.SYNOPSIS
    Verified copy wrapper around robocopy.

.DESCRIPTION
    Copies files/directories with robocopy, translates its exit codes, and
    optionally re-verifies every copied file by SHA-256.

    Explorer-like semantics: a source folder is copied *into* the destination
    (D:\dest\folderName). Use -ContentsOnly to merge the folder's contents
    directly into the destination instead (robocopy's native behaviour).

    With -VerifyOnly nothing is copied: source and destination are compared
    directly, which makes it usable as a "re-check this backup" command and as
    a deterministic test of the verification path.

    Verification stays opt-in. Source reparse entries are skipped, like /XJ.
    Overlapping source/target trees, reparse ancestors and reparse entries in
    copy targets are refused. Mirror requires directories with disjoint targets.
    These checks are a preflight, not protection against concurrent path changes.

.PARAMETER Path
    One or more files or directories to copy (or, with -VerifyOnly, to check).

.PARAMETER Destination
    Destination directory (created if missing).

.PARAMETER Mode
    Merge (default), Mirror (/MIR - deletes extra files in destination), Move (/MOV).

.PARAMETER Verify
    After copying, compare SHA-256 of every source file against its copy.

.PARAMETER VerifyOnly
    Skip the copy and only verify source against destination (implies -Verify).
    The destination is not created. Exit code 2 when a file is missing, differs,
    or cannot be read.

.EXAMPLE
    .\bunshin.ps1 'D:\Photos' 'E:\Backup' -Verify

.EXAMPLE
    .\bunshin.ps1 'D:\Photos' 'E:\Backup' -VerifyOnly
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0)]
    [string[]] $Path,

    [Parameter(Mandatory, Position = 1)]
    [string] $Destination,

    [ValidateSet('Merge', 'Mirror', 'Move')]
    [string] $Mode = 'Merge',

    [ValidateRange(1, 128)]
    [int] $Threads = 16,

    [switch] $Verify,
    [switch] $VerifyOnly,
    [switch] $ContentsOnly,
    [switch] $Force,
    [switch] $Quiet,
    [string] $LogDirectory = (Join-Path $env:LOCALAPPDATA 'bunshin\logs')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Move deletes the source before verification could compare against it.
if ($Mode -eq 'Move' -and ($Verify -or $VerifyOnly)) {
    throw 'Move mode deletes the source, so -Verify and -VerifyOnly cannot prove anything. Copy with -Verify first, then delete the source.'
}

# ---------------------------------------------------------------- helpers ---

function Resolve-FullPath {
    param([string] $Path)
    $p = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    # Compare one spelling of each path; an extended prefix must not hide overlap.
    if ($p.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) {
        $p = '\\' + $p.Substring(8)
    } elseif ($p.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        $p = $p.Substring(4)
    }
    [IO.Path]::GetFullPath($p)
}

function Add-LongPath {
    param([string] $Path)
    if ($Path.StartsWith('\\?\') -or $Path.Length -lt 240) { return $Path }
    if ($Path.StartsWith('\\')) { return '\\?\UNC\' + $Path.Substring(2) }
    '\\?\' + $Path
}

function Get-Sha256 {
    param([string] $Path)
    $full = Add-LongPath $Path
    $fs = [IO.File]::Open($full, 'Open', 'Read', 'ReadWrite')
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { [BitConverter]::ToString($sha.ComputeHash($fs)).Replace('-', '') }
        finally { $sha.Dispose() }
    }
    finally { $fs.Dispose() }
}

function Get-RelativeFiles {
    param([string] $Root, [switch] $RejectReparse)
    $pending = New-Object 'Collections.Generic.Stack[string]'
    $pending.Push($Root)
    while ($pending.Count) {
        $dir = $pending.Pop()
        foreach ($entry in [IO.Directory]::EnumerateFileSystemEntries((Add-LongPath $dir))) {
            $attributes = [IO.File]::GetAttributes($entry)
            # Match robocopy /XJ: do not follow junctions or symbolic links.
            if ($attributes -band [IO.FileAttributes]::ReparsePoint) {
                if ($RejectReparse) { throw "Reparse-point destination is unsafe: $entry" }
                continue
            }
            if ($attributes -band [IO.FileAttributes]::Directory) {
                $pending.Push($entry)
            } else {
                $clean = if ($entry.StartsWith('\\?\UNC\')) { '\\' + $entry.Substring(8) }
                    elseif ($entry.StartsWith('\\?\')) { $entry.Substring(4) } else { $entry }
                [pscustomobject]@{
                    Full = $clean
                    Relative = $clean.Substring($Root.TrimEnd('\').Length).TrimStart('\')
                }
            }
        }
    }
}

function Test-Within {
    param([string] $Child, [string] $Parent)
    $Child = $Child.TrimEnd('\')
    $Parent = $Parent.TrimEnd('\')
    $Child.Equals($Parent, [StringComparison]::OrdinalIgnoreCase) -or
        $Child.StartsWith($Parent + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparseAncestor {
    param([string] $Path)
    $current = $Path
    while ($current) {
        if (Test-Path -LiteralPath (Add-LongPath $current)) {
            $attributes = [IO.File]::GetAttributes((Add-LongPath $current))
            if ($attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse-point path is unsafe: $current"
            }
        }
        $current = Split-Path -Parent $current
    }
}

function Write-Info {
    param([string] $Message, [string] $Color = 'Cyan')
    if (-not $Quiet) { Write-Host $Message -ForegroundColor $Color }
}

# ------------------------------------------------------------------- setup ---

$Destination = Resolve-FullPath $Destination
$destExists = Test-Path -LiteralPath (Add-LongPath $Destination)

if ($Mode -eq 'Mirror' -and -not $Force -and -not $VerifyOnly) {
    if ($Quiet) {
        [Console]::Error.WriteLine("Mirror deletes extra files in '$Destination'; refusing to do that unattended. Pass -Force to confirm.")
        exit 3
    }
    Write-Info "Mirror mode deletes anything in '$Destination' that is not in the source." 'Yellow'
    $answer = Read-Host 'Continue? (y/N)'
    if ($answer -notmatch '^y') { Write-Info 'Aborted.' 'Yellow'; exit 3 }
}

if (-not (Test-Path -LiteralPath (Add-LongPath $LogDirectory))) {
    New-Item -ItemType Directory -Path (Add-LongPath $LogDirectory) -Force | Out-Null
}
$logPath = Join-Path $LogDirectory ("bunshin-{0:yyyyMMdd-HHmmss-fff}-{1}.log" -f (Get-Date), $PID)

# -------------------------------------------------------------------- plan ---

$plan = @(foreach ($raw in $Path) {
    $src = Resolve-FullPath $raw
    if (-not (Test-Path -LiteralPath (Add-LongPath $src))) {
        throw "Source not found: $raw"
    }
    $isDir = (Get-Item -LiteralPath (Add-LongPath $src)).PSIsContainer
    $target = if ($isDir -and -not $ContentsOnly) {
        Join-Path $Destination (Split-Path -Leaf $src.TrimEnd('\'))
    } else {
        $Destination
    }
    [pscustomobject]@{ Source = $src; Target = $target; IsDir = $isDir }
})

# Validate the entire plan before creating destinations or invoking robocopy.
Assert-NoReparseAncestor $Destination
foreach ($item in $plan) {
    Assert-NoReparseAncestor $item.Source
    Assert-NoReparseAncestor $item.Target
    if (-not $VerifyOnly -and (Test-Path -LiteralPath (Add-LongPath $item.Target))) {
        if ($item.IsDir) {
            Get-RelativeFiles $item.Target -RejectReparse | Out-Null
        } else {
            Assert-NoReparseAncestor (Join-Path $item.Target (Split-Path -Leaf $item.Source))
        }
    }
    if ($Mode -eq 'Mirror' -and -not $item.IsDir -and -not $VerifyOnly) {
        throw 'Mirror requires directory sources; a filename filter cannot safely define a mirror.'
    }
    $output = if ($item.IsDir) { $item.Target } else { Join-Path $item.Target (Split-Path -Leaf $item.Source) }
    foreach ($source in $plan) {
        if ((Test-Within $output $source.Source) -or (Test-Within $source.Source $output)) {
            throw "Source/destination overlap is unsafe: $($source.Source) -> $output"
        }
    }
    if ($Mode -eq 'Mirror' -and -not $VerifyOnly) {
        foreach ($other in $plan) {
            if (-not [object]::ReferenceEquals($item, $other) -and
                ((Test-Within $item.Target $other.Target) -or (Test-Within $other.Target $item.Target))) {
                throw 'Mirror targets overlap; each source requires a separate destination tree.'
            }
        }
        # Validate every source before any mirror can delete destination extras.
        try { Get-RelativeFiles $item.Source | Out-Null }
        catch { throw "Cannot enumerate mirror source $($item.Source): $($_.Exception.Message)" }
    }
}
if (-not $VerifyOnly -and -not $destExists) {
    New-Item -ItemType Directory -Path (Add-LongPath $Destination) -Force | Out-Null
}

# --------------------------------------------------------------- copy loop ---

$started = Get-Date
$exitCode = 0
$copiedFiles = 0
$totalFiles = 0

if ($VerifyOnly) {
    Write-Info "`n==> Verify only - nothing will be copied." 'Cyan'
}

if (-not $VerifyOnly) {
    foreach ($item in $plan) {
        # Pre-count for the progress bar (cheap enough up to ~200k files).
        $expected = 0
        $srcFiles = @()
        if ($item.IsDir) {
            try {
                $srcFiles = @(Get-RelativeFiles $item.Source)
                $expected = $srcFiles.Count
                $totalFiles += $expected
            } catch {
                if ($Mode -eq 'Mirror') { throw "Cannot enumerate mirror source $($item.Source): $($_.Exception.Message)" }
                $expected = 0
            }
        } else {
            $expected = 1
            $totalFiles += 1
        }

        $roboArgs = if ($item.IsDir) {
            @(
                $item.Source
                $item.Target
                '/E'
                '/COPY:DAT'
                '/DCOPY:DAT'
                '/R:2'
                '/W:2'
                '/XJ'
                '/NP'
                '/NDL'
                "/MT:$Threads"
                "/LOG+:$logPath"
            )
        } else {
            # robocopy needs a directory source plus a filename filter for single files.
            @(
                (Split-Path -Parent $item.Source)
                $item.Target
                (Split-Path -Leaf $item.Source)
                '/COPY:DAT'
                '/R:2'
                '/W:2'
                '/NP'
                '/NDL'
                '/XJ'
                "/LOG+:$logPath"
            )
        }
        if ($Mode -eq 'Mirror') { $roboArgs += '/MIR' }
        if ($Mode -eq 'Move') { $roboArgs += '/MOV' }

        Write-Info "`n==> $($item.Source)"
        Write-Info "    -> $($item.Target)"

        $processed = 0
        $fileLine = '^\s*(New File|Newer|Older|Changed|\*EXTRA File|Same)\b'

        & robocopy @roboArgs 2>&1 | ForEach-Object {
            $line = [string]$_
            if (-not $Quiet) { Write-Host $line }
            if ($line -match $fileLine) {
                $processed++
                if ($expected -gt 0 -and -not $Quiet) {
                    $pct = [math]::Min(100, [math]::Round(100 * $processed / $expected))
                    Write-Progress -Activity "Copying" -Status "$processed / $expected files" -PercentComplete $pct
                }
            }
        }
        $rc = $LASTEXITCODE
        if (-not $Quiet) { Write-Progress -Activity "Copying" -Completed }
        $copiedFiles += $processed

        # robocopy: 0-7 are success flags, >=8 means at least one failure.
        if ($rc -ge 8) {
            Write-Info "    robocopy exit code $rc (failure)" 'Red'
            $exitCode = 1
        }
    }
}

# ---------------------------------------------------------------- verify ---

$verifyFailures = @()
if ($Verify -or $VerifyOnly) {
    $scanFailures = @()
    $pairs = @(
        foreach ($item in $plan) {
            if ($item.IsDir -and -not [IO.Directory]::Exists((Add-LongPath $item.Target))) {
                $scanFailures += "Destination directory not found: $($item.Target)"
            }
            if (-not $item.IsDir) {
                $destFile = Join-Path $item.Target (Split-Path -Leaf $item.Source)
                [pscustomobject]@{ Source = $item.Source; Dest = $destFile }
                continue
            }
            try {
                foreach ($f in (Get-RelativeFiles $item.Source)) {
                    [pscustomobject]@{
                        Source = $f.Full
                        Dest   = Join-Path $item.Target $f.Relative
                    }
                }
            } catch {
                $scanFailures += "Cannot enumerate $($item.Source): $($_.Exception.Message)"
            }
        }
    )

    Write-Info "`n==> Verifying SHA-256 of $($pairs.Count) file(s) ..."

    $results = foreach ($pair in $pairs) {
        try {
            Assert-NoReparseAncestor $pair.Dest
            if (-not [IO.File]::Exists((Add-LongPath $pair.Dest))) {
                [pscustomobject]@{ Pair = $pair; Status = 'Missing' }
            } else {
                $sh = Get-Sha256 $pair.Source
                $dh = Get-Sha256 $pair.Dest
                [pscustomobject]@{ Pair = $pair; Status = $(if ($sh -eq $dh) { 'OK' } else { 'Mismatch' }) }
            }
        } catch {
            [pscustomobject]@{ Pair = $pair; Status = "Error: $($_.Exception.Message)" }
        }
    }

    $verifyFailures = @($results | Where-Object { $_.Status -ne 'OK' })
    foreach ($f in $verifyFailures) {
        Write-Info ("    {0}: {1}" -f $f.Status, $f.Pair.Source) 'Red'
    }
    foreach ($failure in $scanFailures) { Write-Info $failure 'Red' }
    if ($verifyFailures.Count -eq 0 -and $scanFailures.Count -eq 0) {
        Write-Info ("    all {0} file(s) verified" -f $pairs.Count) 'Green'
    } else {
        $exitCode = 2
    }

    # Keep verification verdicts alongside the copy log, including scan errors.
    if ($VerifyOnly -or $Verify) {
        $detail = if ($verifyFailures.Count -eq 0 -and $scanFailures.Count -eq 0) {
            @('all files verified')
        } else {
            @($scanFailures) + @($verifyFailures | ForEach-Object { '{0}: {1} -> {2}' -f $_.Status, $_.Pair.Source, $_.Pair.Dest })
        }
        $head = @(
            "bunshin verification  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            "destination : $Destination"
            "files       : $($pairs.Count)"
            "failed      : $($verifyFailures.Count + $scanFailures.Count)"
            ''
        )
        Add-Content -LiteralPath $logPath -Value ($head + $detail) -Encoding utf8
    }
}

# --------------------------------------------------------------- summary ---

$elapsed = (Get-Date) - $started
$lines = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath } else { @() }
$filesLine = $lines | Where-Object { $_ -match '^\s*Files\s*:\s+(\d+)\s+(\d+)' } | Select-Object -Last 1
$bytesLine = $lines | Where-Object { $_ -match '^\s*Bytes\s*:' } | Select-Object -Last 1
$rcLine = $lines | Where-Object { $_ -match '^\s*Ended\s*:' } | Select-Object -Last 1

Write-Info "`n--- summary ---"
Write-Info ("mode      : {0}" -f $(if ($VerifyOnly) { 'VerifyOnly' } else { $Mode })) 'Gray'
Write-Info ("elapsed   : {0:mm\:ss}" -f $elapsed) 'Gray'
if ($filesLine) { Write-Info ("files     :{0}" -f ($filesLine -replace '^\s*Files\s*:\s*', ' ')) 'Gray' }
if ($bytesLine) { Write-Info ("bytes     :{0}" -f ($bytesLine -replace '^\s*Bytes\s*:\s*', ' ')) 'Gray' }
if ($rcLine) { Write-Info ("robocopy  :{0}" -f ($rcLine -replace '^\s*Ended\s*:\s*', ' ')) 'Gray' }
if ($Verify -or $VerifyOnly) {
    $failureCount = $verifyFailures.Count + $scanFailures.Count
    $status = if ($failureCount -eq 0) { 'all files verified' } else { "$failureCount failed" }
    Write-Info ("verify    : {0}" -f $status) $(if ($failureCount -eq 0) { 'Green' } else { 'Red' })
}
if (Test-Path -LiteralPath $logPath) { Write-Info ("log       : {0}" -f $logPath) 'Gray' }

exit $exitCode
