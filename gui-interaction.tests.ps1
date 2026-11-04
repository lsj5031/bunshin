# Run with Windows PowerShell 5.1 on an interactive desktop:
# powershell.exe -NoProfile -STA -File .\gui-interaction.tests.ps1
param(
    [string]$Executable,
    [string]$Artifacts
)
$ErrorActionPreference = 'Stop'
if (!$Executable) { $Executable = Join-Path $PSScriptRoot 'gui\bin\Debug\net10.0-windows\Bunshin.exe' }
if (!$Artifacts) { $Artifacts = Join-Path $PSScriptRoot '.amp\in\artifacts\gui' }
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class BunshinTestWindow {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hwnd, uint msg, IntPtr w, string text);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hwnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
}
'@
[BunshinTestWindow]::SetProcessDPIAware() | Out-Null
$scope = [System.Windows.Automation.TreeScope]::Descendants
$root = [System.Windows.Automation.AutomationElement]::RootElement
$fixture = Join-Path $env:TEMP ('bunshin-ui-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $fixture, $Artifacts | Out-Null
$script:app = $null
$script:window = $null
$script:passed = 0

function Assert($condition, [string]$message) {
    if (!$condition) { throw $message }
    $script:passed++
    Write-Host "PASS $message"
}
function Wait-For([scriptblock]$condition, [int]$seconds = 15) {
    $until = [DateTime]::UtcNow.AddSeconds($seconds)
    do {
        $value = & $condition
        if ($value) { return $value }
        Start-Sleep -Milliseconds 80
    } while ([DateTime]::UtcNow -lt $until)
    throw "Timed out: $condition"
}
function Find-Id([string]$id, $within = $script:window) {
    $found = $within.FindAll($scope, (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id)))
    if ($found.Count -gt 1) {
        $native = @($found | Where-Object { $_.Current.ClassName -in 'Button','Edit' })
        if ($native.Count) { return $native[0] }
    }
    if ($found.Count) { return $found[0] }
}
function Find-Name([string]$name, $within = $script:window) {
    $within.FindFirst($scope, (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::NameProperty, $name)))
}
function Invoke-Element($element) {
    $pattern = $null
    if ($element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) { $pattern.Invoke() }
    else {
        # Native common-dialog controls expose only HWND panes on this host.
        [BunshinTestWindow]::PostMessage([IntPtr]$element.Current.NativeWindowHandle, 0xF5, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    }
}
function Click([string]$id) { Invoke-Element (Find-Id $id) }
function Set-Text($element, [string]$value) {
    $pattern = $null
    if ($element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) {
        $pattern.SetValue($value)
        $expectedText = $value
        try { Wait-For { $pattern.Current.Value -ceq $expectedText } | Out-Null }
        catch { throw "Text update did not settle: expected '$expectedText', actual '$($pattern.Current.Value)'." }
    }
    else { [BunshinTestWindow]::SendMessage([IntPtr]$element.Current.NativeWindowHandle, 0xC, [IntPtr]::Zero, $value) | Out-Null }
}
function Select-Mode([string]$id) {
    (Find-Id $id).GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    $selected = @('CopyModeCheck','MirrorCheck','VerifyOnlyCheck' | Where-Object {
        (Find-Id $_).GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Current.IsSelected
    })
    Assert ($selected.Count -eq 1 -and $selected[0] -eq $id) "$id is the only selected transfer mode"
}
function Text-Of([string]$id) { (Find-Id $id).Current.Name }
function Assert-DefaultCancel($dialog, [string]$message) {
    $name = $dialog.Current.Name
    $decline = Find-Id '7' $dialog
    Assert ($decline.Current.HasKeyboardFocus) "$message defaults keyboard focus to No"
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Wait-For { !(Find-Dialog $name) } | Out-Null
}
function Destination-Snapshot([string]$path) {
    # Include entries, file bytes and write times: verify-only must not mutate any destination content.
    @(Get-ChildItem -LiteralPath $path -Recurse -Force | Sort-Object FullName | ForEach-Object {
        $hash = if (!$_.PSIsContainer) { (Get-FileHash -LiteralPath $_.FullName).Hash } else { '<directory>' }
        "$($_.FullName)|$hash|$($_.LastWriteTimeUtc.Ticks)"
    }) -join "`n"
}
function Check-MinimumKeyboardReach {
    $bounds = $script:window.Current.BoundingRectangle
    $hwnd = [IntPtr]$script:window.Current.NativeWindowHandle
    $scale = [BunshinTestWindow]::GetDpiForWindow($hwnd) / 96.0
    $work = [System.Windows.Forms.Screen]::FromHandle($hwnd).WorkingArea
    $transform = $script:window.GetCurrentPattern([System.Windows.Automation.TransformPattern]::Pattern)
    try {
        $transform.Resize(760 * $scale, 640 * $scale)
        $transform.Move($work.Left, $work.Top)
        [BunshinTestWindow]::SetForegroundWindow($hwnd) | Out-Null
        (Find-Id 'DestinationBox').SetFocus()
        Wait-For { (Find-Id 'DestinationBox').Current.HasKeyboardFocus } | Out-Null
        for ($tab = 0; $tab -lt 30 -and !(Find-Id 'CopyButton').Current.HasKeyboardFocus; $tab++) {
            [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
            Start-Sleep -Milliseconds 40
        }
        Assert ((Find-Id 'CopyButton').Current.HasKeyboardFocus) 'Tab navigation reaches primary action at minimum window size'
        $action = (Find-Id 'CopyButton').Current
        $view = $script:window.Current.BoundingRectangle
        Assert (!$action.IsOffscreen -and $action.BoundingRectangle.Top -ge $view.Top -and $action.BoundingRectangle.Bottom + 4 * $scale -le [Math]::Min($view.Bottom, $work.Bottom)) 'Focused primary action and focus ring scroll fully into visible window and work area'
        Shot '12-minimum-keyboard-action'
        Write-Host "Minimum resize checked at $([int]($scale * 100))% DPI; work area $($work.Width)x$($work.Height) physical pixels"
    } finally {
        $transform.Resize($bounds.Width, $bounds.Height)
        $transform.Move($bounds.Left, $bounds.Top)
    }
}
function Start-App {
    $script:app = Start-Process $Executable -PassThru
    $script:window = Wait-For {
        $root.FindFirst($scope, [System.Windows.Automation.AndCondition]::new(
            [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $script:app.Id),
            [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)))
    }
    [BunshinTestWindow]::SetForegroundWindow([IntPtr]$script:window.Current.NativeWindowHandle) | Out-Null
}
function Close-App {
    if ($script:app -and !$script:app.HasExited) {
        [BunshinTestWindow]::PostMessage([IntPtr]$script:window.Current.NativeWindowHandle, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        Wait-For { $script:app.HasExited } | Out-Null
    }
}
function Find-Dialog([string]$name) {
    $root.FindFirst($scope, [System.Windows.Automation.AndCondition]::new(
        [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty, $name),
        [System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)))
}
function Dialog([string]$name) { Wait-For { Find-Dialog $name } }
function Add-Source([string]$path, [switch]$Folder) {
    if ($Folder) { Click 'AddFolderButton'; $dialogName = 'Add folder'; $editId = '1152' }
    else { Click 'AddFilesButton'; $dialogName = 'Add files'; $editId = '1148' }
    $dialog = Dialog $dialogName
    $edit = Wait-For { Find-Id $editId $dialog }
    Set-Text $edit $path
    Invoke-Element (Find-Id '1' $dialog)
    Wait-For { !(Find-Dialog $dialogName) } | Out-Null
}
function Wait-Done {
    Wait-For { (Text-Of 'StatusText') -like 'This run:*' } 60 | Out-Null
}
function Job-Logs([string]$sourcePath) {
    @(Get-ChildItem "$env:LOCALAPPDATA\bunshin\logs\gui-*$($script:app.Id)*.log" | Where-Object {
        [IO.File]::ReadAllText($_.FullName).Contains("source: $sourcePath" + [Environment]::NewLine)
    })
}
function Shot([string]$name) {
    Start-Sleep -Milliseconds 180
    $dialogs = $script:window.FindAll($scope, (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)))
    $windows = @($script:window) + @($dialogs | ForEach-Object { $_ })
    $bounds = @($windows | ForEach-Object { $_.Current.BoundingRectangle })
    $left = ($bounds.Left | Measure-Object -Minimum).Minimum
    $top = ($bounds.Top | Measure-Object -Minimum).Minimum
    $right = ($bounds.Right | Measure-Object -Maximum).Maximum
    $bottom = ($bounds.Bottom | Measure-Object -Maximum).Maximum
    $left -= 16
    $top -= 16
    $right += 16
    $bottom += 16
    $image = New-Object System.Drawing.Bitmap([int]($right - $left), [int]($bottom - $top))
    $graphics = [System.Drawing.Graphics]::FromImage($image)
    try {
        $graphics.Clear([System.Drawing.Color]::FromArgb(15,18,22))
        # Capture each HWND at its physical size; the canvas includes complete dialogs.
        foreach ($capture in $windows) {
            $dr = $capture.Current.BoundingRectangle
            $overlay = New-Object System.Drawing.Bitmap([int]$dr.Width, [int]$dr.Height)
            $og = [System.Drawing.Graphics]::FromImage($overlay)
            $dc = $og.GetHdc()
            try { [BunshinTestWindow]::PrintWindow([IntPtr]$capture.Current.NativeWindowHandle, $dc, 2) | Out-Null }
            finally { $og.ReleaseHdc($dc); $og.Dispose() }
            $graphics.DrawImageUnscaled($overlay, [int]($dr.X - $left), [int]($dr.Y - $top))
            $overlay.Dispose()
        }
        $image.Save((Join-Path $Artifacts ($name + '.png')))
    } finally { $graphics.Dispose(); $image.Dispose() }
}
try {
    $source = Join-Path $fixture 'photos'
    $dest = Join-Path $fixture 'backup'
    New-Item -ItemType Directory -Force $source, "$source\empty", "$dest\photos" | Out-Null
    [IO.File]::WriteAllText("$source\trip.txt", 'Bunshin UI copy fixture')
    [IO.File]::WriteAllText("$source\photo-文件.txt", 'Unicode preserved')
    [IO.File]::WriteAllText("$dest\photos\extra.txt", 'mirror sentinel')
    Start-App
    Assert (!(Find-Id 'CopyButton').Current.IsEnabled) 'Empty startup cannot start a transfer'
    Assert (!(Find-Id 'RemoveButton').Current.IsEnabled -and !(Find-Id 'ClearButton').Current.IsEnabled) 'Empty startup disables remove and clear finished'
    foreach ($id in 'DetailsExpander','LogExpander') {
        Assert ((Find-Id $id).GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Current.ExpandCollapseState -eq 'Collapsed') "$id starts collapsed"
    }
    Shot '01-ready'
    $original = "$fixture\plan-original\photos"
    $queuedSource = "$fixture\plan-backup\photos"
    New-Item -ItemType Directory -Force $original, $queuedSource | Out-Null
    [IO.File]::WriteAllText("$original\keep.txt", 'FIRST SOURCE BYTES')
    [IO.File]::WriteAllText("$queuedSource\keep.txt", 'SECOND SOURCE MUST SURVIVE')
    Add-Source $original -Folder
    Add-Source $queuedSource -Folder
    Assert (!(Find-Id 'CopyButton').Current.IsEnabled) 'Queued sources still require a destination'
    foreach ($spelling in 'regular','extended','dot-segments','extended-dot-segments','mixed-case') {
        $planDestination = "$fixture\plan-backup"
        if ($spelling -like '*dot-segments') { $planDestination += '\..\plan-backup\.' }
        if ($spelling -eq 'extended') { $planDestination = "\\?\$planDestination" }
        if ($spelling -eq 'extended-dot-segments') { $planDestination = "\\?\$planDestination" }
        if ($spelling -eq 'mixed-case') { $planDestination = $planDestination.ToUpperInvariant() + '\' }
        Set-Text (Find-Id 'DestinationBox') $planDestination
        foreach ($mode in 'copy','mirror','verify only') {
            $modeId = switch ($mode) { 'copy' { 'CopyModeCheck' } 'mirror' { 'MirrorCheck' } 'verify only' { 'VerifyOnlyCheck' } }
            Select-Mode $modeId
            Click 'CopyButton'
            $prompt = Dialog 'Bunshin'
            $expectedOutput = $queuedSource
            if ($spelling -eq 'mixed-case') { $expectedOutput = "$($fixture.ToUpperInvariant())\PLAN-BACKUP\photos" }
            $warning = "The queued sources and destinations overlap. No jobs were started.`n`nDestination: $expectedOutput`nSource: $queuedSource`n`nChoose a separate destination or remove the conflicting source."
            Assert ([bool](Find-Name $warning $prompt)) "$mode with $spelling paths rejects the whole overlapping plan before starting"
            if ($mode -eq 'copy' -and $spelling -eq 'regular') { Shot '09-overlap-after' }
            Invoke-Element (Find-Id '2' $prompt)
            Assert ([IO.File]::ReadAllText("$queuedSource\keep.txt") -eq 'SECOND SOURCE MUST SURVIVE') "$mode with $spelling paths leaves queued source B original bytes unchanged"
            Assert ((Text-Of 'QueueSummary') -eq '2 pending' -and @(Job-Logs $original).Count -eq 0 -and @(Job-Logs $queuedSource).Count -eq 0) "$mode with $spelling paths starts no jobs or audit logs for the rejected plan"
        }
    }
    Select-Mode 'CopyModeCheck'
    foreach ($unused in 1..2) {
        $items = (Find-Id 'JobsList').FindAll($scope, (New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)))
        $items[0].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
        Click 'RemoveButton'
    }
    foreach ($topology in 'output-contains-source','output-inside-source','output-contains-source-file') {
        $crossRoot = Join-Path $fixture $topology
        $crossDestination = Join-Path $crossRoot 'backup'
        $output = Join-Path $crossDestination 'photos'
        $crossSource = switch ($topology) {
            'output-contains-source' { Join-Path $output 'nested' }
            'output-inside-source' { $crossDestination }
            'output-contains-source-file' { Join-Path $output 'keep.txt' }
        }
        New-Item -ItemType Directory -Force $crossDestination, (Split-Path $crossSource) | Out-Null
        if ($topology -eq 'output-contains-source-file') { [IO.File]::WriteAllText($crossSource, 'QUEUED FILE MUST SURVIVE') }
        else {
            New-Item -ItemType Directory -Force $crossSource | Out-Null
            [IO.File]::WriteAllText((Join-Path $crossSource 'sentinel.txt'), 'QUEUED FOLDER MUST SURVIVE')
        }
        Add-Source $original -Folder
        if ($topology -eq 'output-contains-source-file') { Add-Source $crossSource }
        else { Add-Source $crossSource -Folder }
        $beforeOverlap = Destination-Snapshot $crossDestination
        foreach ($modeId in 'CopyModeCheck','MirrorCheck','VerifyOnlyCheck') {
            Select-Mode $modeId
            Set-Text (Find-Id 'DestinationBox') "\\?\$crossDestination"
            Click 'CopyButton'
            $prompt = Dialog 'Bunshin'
            $warning = "The queued sources and destinations overlap. No jobs were started.`n`nDestination: $output`nSource: $crossSource`n`nChoose a separate destination or remove the conflicting source."
            Assert ([bool](Find-Name $warning $prompt)) "$modeId rejects $topology across distinct queued jobs"
            Invoke-Element (Find-Id '2' $prompt)
            Assert ((Destination-Snapshot $crossDestination) -ceq $beforeOverlap) "$modeId preserves all bytes and entries for $topology"
            Assert ((Text-Of 'QueueSummary') -eq '2 pending' -and @(Job-Logs $original).Count -eq 0 -and @(Job-Logs $crossSource).Count -eq 0) "$modeId starts no jobs or audit logs for $topology"
        }
        foreach ($unused in 1..2) {
            $items = (Find-Id 'JobsList').FindAll($scope, (New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)))
            $items[0].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
            Click 'RemoveButton'
        }
    }
    Select-Mode 'CopyModeCheck'
    Add-Source ([IO.Path]::GetPathRoot($fixture)) -Folder
    $prompt = Dialog 'Bunshin'
    Assert ((Text-Of 'QueueCount') -eq '0 items') 'Drive root is rejected before queueing'
    Invoke-Element (Find-Id '2' $prompt)
    Add-Source $source -Folder
    Assert ((Text-Of 'QueueCount') -eq '1 item') 'Native folder picker queues a folder'
    Add-Source $source -Folder
    Assert ((Text-Of 'QueueCount') -eq '1 item') 'Duplicate source is ignored'
    Set-Text (Find-Id 'DestinationBox') $dest
    Wait-For { Find-Name "→ $dest\photos" } | Out-Null
    Assert ([bool](Find-Name "→ $dest\photos")) 'Folder mapping shows the resolved nested target before starting'
    Shot '10-queued-target'
    Check-MinimumKeyboardReach
    Select-Mode 'MirrorCheck'
    Assert ((Find-Id 'CopyButton').Current.Name -eq 'Mirror and verify') 'Mirror mode explicitly labels the primary action'
    New-Item -ItemType Directory -Force "$fixture\other\photos" | Out-Null
    Add-Source "$fixture\other\photos" -Folder
    Click 'CopyButton'
    $prompt = Dialog 'Bunshin'
    Assert ([bool](Find-Name 'These mirror jobs have overlapping destinations. A later job could delete files copied by an earlier job. Queue one source folder per destination, or turn Mirror off.' $prompt)) 'Overlapping mirror jobs are rejected before deletion'
    Invoke-Element (Find-Id '2' $prompt)
    $items = (Find-Id 'JobsList').FindAll($scope, (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)))
    $items[1].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Click 'RemoveButton'
    Assert ((Text-Of 'QueueCount') -eq '1 item') 'Remove deletes only the selected queued job'
    Click 'CopyButton'
    $prompt = Dialog 'Bunshin — confirm mirror'
    Assert ([bool](Find-Name ("Mirror permanently deletes destination files and folders that are absent from the source.`n`nAffected destinations:`n$dest\photos`n`nThese deletions cannot be undone. Continue with mirror?") $prompt)) 'Mirror warning identifies the actual target'
    Shot '02-mirror-confirmation'
    Assert-DefaultCancel $prompt 'Mirror confirmation'
    Assert (Test-Path "$dest\photos\extra.txt") 'Declining mirror preserves destination extras'
    Assert (!(Test-Path "$dest\photos\trip.txt")) 'Declining mirror does not start copying'
    Click 'CopyButton'
    $prompt = Dialog 'Bunshin — confirm mirror'
    Invoke-Element (Find-Id '6' $prompt)
    Wait-Done
    Assert (!(Test-Path "$dest\photos\extra.txt")) 'Approving mirror deletes extras'
    Assert ((Get-FileHash "$source\trip.txt").Hash -eq (Get-FileHash "$dest\photos\trip.txt").Hash) 'Copied file bytes match source'
    Assert (Test-Path "$dest\photos\empty" -PathType Container) 'Empty folder is preserved'
    Assert ((Text-Of 'StatusText') -like 'This run: 1 verified, 0 failed*') 'Copy finishes with verified status'
    Assert ((Text-Of 'OutcomeTitle') -eq 'Your copy is verified.') 'Verified outcome is prominent and persistent'
    $logs = @(Job-Logs $source)
    Assert ($logs.Count -eq 1) 'Copy and verification share one persistent job log'
    Assert ([IO.File]::ReadAllText($logs[0].FullName).Contains('SHA-256: 2 checked, 0 failed')) 'Copy log persists the verification summary'
    Shot '03-verified'
    Assert ((Find-Id 'OpenDestinationButton').Current.IsEnabled) 'Verified result offers Open destination'
    $shell = New-Object -ComObject Shell.Application
    $existingExplorer = @($shell.Windows() | ForEach-Object { $_.HWND })
    Click 'OpenDestinationButton'
    $opened = Wait-For { @($shell.Windows() | Where-Object { $_.Document.Folder.Self.Path -eq $dest }) | Select-Object -First 1 }
    Assert ($opened.Document.Folder.Self.Path -eq $dest) 'Open destination opens the completed run destination in Explorer'
    if ($opened.HWND -notin $existingExplorer) { $opened.Quit() }
    [BunshinTestWindow]::SetForegroundWindow([IntPtr]$script:window.Current.NativeWindowHandle) | Out-Null
    Click 'ViewLogButton'
    Wait-For { (Find-Id 'LogBox').Current.HasKeyboardFocus } | Out-Null
    Assert ((Find-Id 'LogExpander').GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Current.ExpandCollapseState -eq 'Expanded') 'View log discloses the activity log and moves keyboard focus into it'
    Shot '11-activity-log'
    $items = (Find-Id 'JobsList').FindAll($scope, (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)))
    $items[0].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Assert ((Text-Of 'LogHeader') -eq 'LOG · PHOTOS') 'Selecting queue item switches log lane'
    Click 'AllLanesButton'
    Assert ((Text-Of 'LogHeader') -eq 'LOG · ALL JOBS') 'All jobs restores merged log lane'
    $previousLog = (Find-Id 'LogBox').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
    Add-Source "$source\photo-文件.txt"
    Assert ((Text-Of 'OutcomeTitle') -eq 'Ready to check every file.') 'Adding another source replaces the previous run verdict with planning state'
    Assert ((Find-Id 'Progress').GetCurrentPattern([System.Windows.Automation.RangeValuePattern]::Pattern).Current.Value -eq 0) 'New plan clears completed progress'
    Assert ([bool](Find-Name 'Verified' (Find-Id 'JobsList'))) 'New plan preserves the old job verdict'
    (Find-Id 'DetailsExpander').GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
    Wait-For { Find-Id 'ResultsCount' } | Out-Null
    Assert ((Text-Of 'ResultsCount') -eq '2 files') 'New plan preserves previous per-file results'
    Assert ((Find-Id 'LogBox').GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value -ceq $previousLog) 'New plan preserves previous activity logs'
    (Find-Id 'DetailsExpander').GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse()
    (Find-Id 'LogExpander').GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse()
    Shot '13-new-plan-after-verified'
    Set-Text (Find-Id 'DestinationBox') ''
    Assert ((Text-Of 'OutcomeTitle') -eq 'Choose where it goes.' -and !(Find-Id 'CopyButton').Current.IsEnabled) 'Clearing destination shows planning guidance and disables start'
    Set-Text (Find-Id 'DestinationBox') $dest
    $items = (Find-Id 'JobsList').FindAll($scope, (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::ListItem)))
    $items[1].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Click 'RemoveButton'
    (Find-Id 'LogExpander').GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse()
    Click 'ClearButton'
    Assert ((Text-Of 'QueueCount') -eq '0 items') 'Clear finished removes terminal jobs'
    Add-Source "$source\trip.txt"
    Assert ((Text-Of 'QueueCount') -eq '1 item') 'Native file picker queues a file'
    Click 'CopyButton'
    $prompt = Dialog 'Bunshin'
    Assert ([bool](Find-Name 'Mirror requires source folders. Remove file sources or turn Mirror off; a single file cannot define a safe destination folder to mirror.' $prompt)) 'Single-file mirror is rejected before confirmation'
    Invoke-Element (Find-Id '2' $prompt)
    Select-Mode 'VerifyOnlyCheck'
    Assert ((Find-Id 'CopyButton').Current.Name -eq 'Verify only') 'Verify-only mode labels the primary action'
    Assert ((Find-Id 'MirrorCheck').Current.IsEnabled) 'Verify-only allows switching directly to another exclusive mode'
    $missing = Join-Path $fixture 'must-not-be-created'
    Set-Text (Find-Id 'DestinationBox') $missing
    Click 'CopyButton'
    $prompt = Dialog 'Bunshin'
    Invoke-Element (Find-Id '2' $prompt)
    Assert (!(Test-Path $missing)) 'Verify-only refuses a missing destination without creating it'
    [IO.File]::WriteAllText("$dest\photos\trip.txt", 'Bunshin UI copy fixturE')
    $beforeVerify = Destination-Snapshot $dest
    Set-Text (Find-Id 'DestinationBox') "$dest\photos"
    Assert ([bool](Find-Name "→ $dest\photos\trip.txt")) 'File mapping shows the full output filename before verification'
    Click 'CopyButton'
    Wait-Done
    Assert ((Destination-Snapshot $dest) -ceq $beforeVerify) 'Verify-only leaves destination names, bytes and write times unchanged'
    Assert ((Text-Of 'StatusText') -like 'This run: 0 verified, 1 failed*') 'Verify-only detects a same-size mismatch'
    Assert ((Text-Of 'ProgressText') -eq 'Finished with failures') 'Failure is explicit in progress summary'
    Assert ((Text-Of 'OutcomeTitle') -eq '1 file differs.') 'Mismatch gets a prominent outcome'
    Assert ((Find-Id 'DetailsExpander').GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Current.ExpandCollapseState -eq 'Expanded') 'Mismatch automatically reveals file details'
    $logs = @(Job-Logs "$source\trip.txt")
    Assert ($logs.Count -eq 1) 'Verify-only creates a persistent job log'
    $audit = [IO.File]::ReadAllText($logs[0].FullName)
    Assert ($audit.Contains('verdict: Mismatch') -and $audit.Contains('result: Failed')) 'Verify-only log records the failed file and final verdict'
    Shot '04-mismatch'
    Click 'ClearButton'
    Add-Source "$source\photo-文件.txt"
    Remove-Item -LiteralPath "$source\photo-文件.txt"
    Click 'CopyButton'
    Wait-Done
    Assert ((Text-Of 'StatusText') -like 'This run: 0 verified, 1 failed*') 'Source disappearing after queueing is reported as a failure'
    Assert ((Text-Of 'OutcomeTitle') -eq 'This run needs attention.') 'Missing source is distinguished from a byte mismatch'
    Assert ((Text-Of 'OutcomeError').Contains("$source\photo-文件.txt")) 'Missing-source outcome exposes the complete failed path inline'
    Assert ((Find-Id 'DetailsExpander').GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Current.ExpandCollapseState -eq 'Collapsed') 'Failure without file results does not open an empty table'
    Wait-For { (Find-Id 'ViewLogButton').Current.HasKeyboardFocus } | Out-Null
    Assert ((Find-Id 'ViewLogButton').Current.HasKeyboardFocus) 'Failure without file results prioritizes View log'
    $logs = @(Job-Logs "$source\photo-文件.txt")
    $audit = [IO.File]::ReadAllText($logs[0].FullName)
    Assert ($audit.Contains('result: Failed') -and $audit.Contains('SHA-256: Incomplete')) 'Preflight exception persists an incomplete verification record'
    Shot '08-source-missing'
    Close-App

    # Hashing a large file keeps verification active while busy controls are inspected.
    $large = Join-Path $fixture 'large.bin'
    $stream = [IO.File]::Create($large)
    $stream.SetLength(1GB)
    $stream.Dispose()
    Start-App
    Add-Source $large
    Set-Text (Find-Id 'DestinationBox') (Join-Path $fixture 'cancel-copy')
    Click 'CopyButton'
    Wait-For { (Find-Id 'CancelButton').Current.IsEnabled } | Out-Null
    foreach ($id in 'CopyButton','BrowseButton','AddFilesButton','AddFolderButton','RemoveButton','ClearButton','DestinationBox','CopyModeCheck','MirrorCheck','VerifyOnlyCheck') {
        Assert (!(Find-Id $id).Current.IsEnabled) "$id is disabled while busy"
    }
    Wait-For { (Text-Of 'StatusText') -like 'Verifying*' } | Out-Null
    Assert ((Text-Of 'OutcomeTitle') -eq 'Checking your copy.') 'Hashing gets a distinct verification headline'
    Assert ((Text-Of 'ProgressText') -like 'Hashing*files checked') 'Verification progress states honest checked-file counts'
    Shot '05-verifying'
    Click 'CancelButton'
    Wait-Done
    Assert ((Text-Of 'StatusText') -like '*1 cancelled*') 'Cancel stops the active job'
    Assert ((Text-Of 'ProgressText') -eq 'Stopped · verification incomplete') 'Cancel never claims verification completed'
    Assert ((Text-Of 'OutcomeTitle') -like 'Stopped*') 'Stopped outcome remains prominent'
    Assert ((Get-FileHash $large).Hash -eq (Get-FileHash "$fixture\cancel-copy\large.bin").Hash) 'Cancelling verification keeps the completed copy intact'
    Assert ((Find-Id 'AddFilesButton').Current.IsEnabled) 'Queue controls recover after cancellation'
    $logs = @(Job-Logs $large)
    Assert ([IO.File]::ReadAllText($logs[0].FullName).Contains('result: Cancelled')) 'Cancellation is persisted in the job log'
    Shot '06-cancelled'
    Close-App

    $stream = [IO.File]::OpenWrite($large)
    $stream.SetLength(4GB)
    $stream.Dispose()
    Start-App
    Add-Source $large
    Set-Text (Find-Id 'DestinationBox') (Join-Path $fixture 'close-copy')
    Click 'CopyButton'
    Wait-For { (Find-Id 'CancelButton').Current.IsEnabled } | Out-Null
    [BunshinTestWindow]::PostMessage([IntPtr]$script:window.Current.NativeWindowHandle, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    $prompt = Dialog 'Bunshin — stop and close?'
    Assert-DefaultCancel $prompt 'Busy close confirmation'
    Assert (!$script:app.HasExited) 'Declining close leaves the application open'
    [BunshinTestWindow]::PostMessage([IntPtr]$script:window.Current.NativeWindowHandle, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    $prompt = Dialog 'Bunshin — stop and close?'
    Shot '07-close-confirmation'
    Invoke-Element (Find-Id '6' $prompt)
    Wait-For { $script:app.HasExited } | Out-Null
    Assert $script:app.HasExited 'Approving close waits for stop then exits'
    $logs = @(Job-Logs $large)
    Assert ([IO.File]::ReadAllText($logs[0].FullName).Contains('result: Cancelled')) 'Close waits for cancellation to be persisted'
    Write-Host "UI interaction checks passed: $script:passed"
} finally {
    if ($script:app -and !$script:app.HasExited) { Close-App }
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
