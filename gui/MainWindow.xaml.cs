using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;

namespace Bunshin.Gui;

public partial class MainWindow : Window
{
    private readonly ObservableCollection<CopyJob> _jobs = new();
    private readonly ObservableCollection<VerifyRow> _rows = new();
    private readonly CopyEngine _engine = new();
    private readonly Dictionary<CopyJob, List<string>> _jobLogs = new();
    private readonly List<string> _allLog = new();
    private CancellationTokenSource? _cts;
    private CopyJob? _lane;
    private int _boxLines;
    private bool _closeAfterCancel;
    private bool _planning = true;
    private string? _lastDestination;
    private readonly Dictionary<string, object> _standardBrushes = new();

    private const int MaxLogLines = 2000;

    public MainWindow()
    {
        InitializeComponent();
        JobsList.ItemsSource = _jobs;
        ResultsGrid.ItemsSource = _rows;
        _jobs.CollectionChanged += (_, _) => RefreshCounts();
        _rows.CollectionChanged += (_, _) => RefreshCounts();
        RefreshCounts();
        Loaded += Preview_Loaded;
        foreach (var key in new[] { "Paper", "Ink", "Dim", "Line", "Accent", "PrimaryHover", "PrimaryPressed", "OnAccent", "Hover", "Pressed", "Success", "Failure" })
            _standardBrushes[key] = Resources[key];
        ApplyAccessibilityPalette();
        SourceInitialized += (_, _) => App.RoundWindow(this);
        SystemParameters.StaticPropertyChanged += SystemSettings_Changed;
        Closed += (_, _) => SystemParameters.StaticPropertyChanged -= SystemSettings_Changed;
    }

    private void Minimize_Click(object sender, RoutedEventArgs e) => SystemCommands.MinimizeWindow(this);

    private void Maximize_Click(object sender, RoutedEventArgs e)
    {
        if (WindowState == WindowState.Maximized) SystemCommands.RestoreWindow(this);
        else SystemCommands.MaximizeWindow(this);
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    private void AddPaths(IEnumerable<string> paths)
    {
        if (_cts is not null) return;
        var added = 0;
        foreach (var candidate in paths)
        {
            if (string.IsNullOrWhiteSpace(candidate)) continue;
            if (!Directory.Exists(candidate) && !File.Exists(candidate)) continue;
            var path = CopyEngine.Normalize(candidate);
            if (Directory.Exists(path) && IsVolumeRoot(path))
            {
                BunshinDialog.Show(this, "Choose a folder inside the drive. Copying a drive or share root is not supported, so mirror cannot accidentally target the whole destination.", "Bunshin");
                continue;
            }
            if (_jobs.Any(j => string.Equals(j.Source, path, StringComparison.OrdinalIgnoreCase))) continue;

            var job = new CopyJob(path);
            job.PropertyChanged += Job_PropertyChanged;
            _planning = true;
            _jobs.Add(job);
            added++;
        }

        if (added > 0)
        {
            SetStatus($"{added} item(s) queued. {_jobs.Count} total.");
            RefreshCounts();
        }
    }

    private void Job_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(CopyJob.ResolvedTarget)) RefreshCounts();
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        e.Effects = _cts is null && e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private void OnDrop(object sender, DragEventArgs e)
    {
        if (e.Data.GetData(DataFormats.FileDrop) is string[] paths) AddPaths(paths);
        e.Handled = true;
    }

    private void AddFiles_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog { Title = "Add files", Multiselect = true };
        if (dialog.ShowDialog(this) == true) AddPaths(dialog.FileNames);
    }

    private void AddFolder_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "Add folder", Multiselect = true };
        if (dialog.ShowDialog(this) == true) AddPaths(dialog.FolderNames);
    }

    private void Remove_Click(object sender, RoutedEventArgs e)
    {
        if (_cts is not null) return;
        var removedLane = false;
        foreach (var job in JobsList.SelectedItems.OfType<CopyJob>().ToList())
        {
            job.PropertyChanged -= Job_PropertyChanged;
            _jobLogs.Remove(job);
            _jobs.Remove(job);
            removedLane |= ReferenceEquals(job, _lane);
        }
        if (removedLane) ShowLane(null);
        RefreshCounts();
    }

    private void Clear_Click(object sender, RoutedEventArgs e)
    {
        if (_cts is not null) return;
        _planning = true;
        foreach (var job in _jobs.Where(j => j.IsTerminal).ToList())
        {
            job.PropertyChanged -= Job_PropertyChanged;
            _jobs.Remove(job);
        }
        _rows.Clear();
        _jobLogs.Clear();
        _allLog.Clear();
        ShowLane(null);
        OutcomeTitle.Text = "A copy you can trust.";
        OutcomeTitle.SetResourceReference(TextBlock.ForegroundProperty, "Ink");
        Progress.Value = 0;
        ProgressText.Text = "Ready when you are";
        SetPhase(0);
        SetStatus("Cleared finished jobs and results.");
        RefreshCounts();
    }

    private void BrowseDestination_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { Title = "Copy to" };
        if (dialog.ShowDialog(this) != true) return;
        DestinationBox.Text = dialog.FolderName;
        SetStatus($"Destination: {dialog.FolderName}");
    }

    private async void Copy_Click(object sender, RoutedEventArgs e)
    {
        if (_cts is not null) return;

        var destination = DestinationBox.Text.Trim();
        if (destination.Length == 0)
        {
            BunshinDialog.Show(this, "Choose a destination folder first.", "Bunshin");
            return;
        }

        if (!_jobs.Any(j => !j.IsTerminal))
        {
            SetStatus("Nothing queued.");
            return;
        }

        try
        {
            destination = CopyEngine.Normalize(destination);
            if (VerifyOnlyCheck.IsChecked == true && !Directory.Exists(destination))
            {
                BunshinDialog.Show(this, "Verify only needs an existing destination folder. Nothing was created or copied.", "Bunshin");
                return;
            }
            ValidatePlan(destination);
        }
        catch (Exception ex)
        {
            BunshinDialog.Show(this, ex.Message, "Bunshin");
            return;
        }

        if (MirrorCheck.IsChecked == true && VerifyOnlyCheck.IsChecked != true)
        {
            if (_jobs.Any(j => !j.IsTerminal && !Directory.Exists(j.Source)))
            {
                BunshinDialog.Show(this, "Mirror requires source folders. Remove file sources or turn Mirror off; a single file cannot define a safe destination folder to mirror.", "Bunshin");
                return;
            }
            var targets = _jobs.Where(j => !j.IsTerminal).Select(j => Path.TrimEndingDirectorySeparator(TargetFor(j.Source, destination))).ToArray();
            for (var i = 0; i < targets.Length; i++)
            for (var j = 0; j < i; j++)
            {
                if (string.Equals(targets[i], targets[j], StringComparison.OrdinalIgnoreCase) ||
                    targets[i].StartsWith(targets[j] + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) ||
                    targets[j].StartsWith(targets[i] + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                {
                    BunshinDialog.Show(this, "These mirror jobs have overlapping destinations. A later job could delete files copied by an earlier job. Queue one source folder per destination, or turn Mirror off.", "Bunshin");
                    return;
                }
            }
            var message = "Mirror permanently deletes destination files and folders that are absent from the source.\n\nAffected destinations:\n" +
                string.Join("\n", targets) + "\n\nThese deletions cannot be undone. Continue with mirror?";
            if (BunshinDialog.Show(this, message, "Bunshin — confirm mirror", confirm: true) != MessageBoxResult.Yes) return;
        }

        await RunQueueAsync(destination);
    }

    private static bool IsVolumeRoot(string source) => string.Equals(
        Path.GetFullPath(source).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
        Path.GetPathRoot(Path.GetFullPath(source))?.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
        StringComparison.OrdinalIgnoreCase);

    private static string TargetFor(string source, string destination)
    {
        if (!Directory.Exists(source)) return destination;
        if (IsVolumeRoot(source)) throw new IOException("Drive and share roots are not supported. Choose a folder inside the drive or share.");
        return Path.Combine(destination, Path.GetFileName(source.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)));
    }

    private void ValidatePlan(string destination)
    {
        var plan = _jobs.Where(j => !j.IsTerminal).Select(job =>
        {
            var source = CopyEngine.Normalize(job.Source);
            var directory = Directory.Exists(source);
            var target = TargetFor(source, destination);
            var output = directory ? target : Path.Combine(target, Path.GetFileName(source));
            return (Source: source, Output: CopyEngine.Normalize(output), Directory: directory);
        }).ToArray();

        foreach (var output in plan)
        foreach (var source in plan)
        {
            if (string.Equals(output.Output, source.Source, StringComparison.OrdinalIgnoreCase) ||
                (source.Directory && output.Output.StartsWith(source.Source + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) ||
                (output.Directory && source.Source.StartsWith(output.Output + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)))
                throw new IOException($"The queued sources and destinations overlap. No jobs were started.\n\nDestination: {output.Output}\nSource: {source.Source}\n\nChoose a separate destination or remove the conflicting source.");
        }
    }

    private async Task RunQueueAsync(string destination)
    {
        var batch = _jobs.Where(j => !j.IsTerminal).ToList();
        _rows.Clear();
        Progress.Value = 0;
        ProgressText.Text = "";
        OutcomeError.Visibility = Visibility.Collapsed;
        OutcomeError.Text = "";
        _cts = new CancellationTokenSource();
        _planning = false;
        _lastDestination = destination;
        SetRunning(true);

        try
        {
            foreach (var job in batch)
            {
                if (_cts.IsCancellationRequested) break;
                await RunJobAsync(job, destination, _cts.Token);
                RefreshCounts();
            }
        }
        finally
        {
            _cts.Dispose();
            _cts = null;
            SetRunning(false);
            Progress.IsIndeterminate = false;
            if (_closeAfterCancel) Close();
        }

        var verified = batch.Count(j => j.State == JobState.Verified);
        var failed = batch.Count(j => j.State == JobState.Failed);
        var stopped = batch.Count(j => j.State == JobState.Cancelled);
        var pending = batch.Count(j => j.State == JobState.Queued);
        ProgressText.Text = failed > 0 ? "Finished with failures" : stopped > 0 || pending > 0 ? "Stopped · verification incomplete" : "Verification complete";
        SetPhase(3);
        var differences = _rows.Count(row => row.Status == "Mismatch");
        OutcomeTitle.Text = failed > 0
            ? differences > 0 ? $"{differences} file{(differences == 1 ? " differs" : "s differ")}." : "This run needs attention."
            : stopped > 0 || pending > 0 ? "Stopped — verification incomplete." : "Your copy is verified.";
        var verdictBrush = failed > 0 ? "Failure" : stopped > 0 || pending > 0 ? "Dim" : "Success";
        OutcomeTitle.SetResourceReference(TextBlock.ForegroundProperty, verdictBrush);
        Progress.SetResourceReference(ProgressBar.ForegroundProperty, verdictBrush);
        var noFileResults = failed > 0 && _rows.Count == 0;
        if (failed > 0) DetailsExpander.IsExpanded = !noFileResults;
        if (noFileResults)
        {
            OutcomeError.Text = string.Join("\n\n", batch.Where(job => job.State == JobState.Failed).Select(job => $"{job.Name}: {job.Detail}"));
            OutcomeError.Visibility = Visibility.Visible;
            LogExpander.IsExpanded = false;
            _ = Dispatcher.InvokeAsync(() => ViewLogButton.Focus(), DispatcherPriority.Input);
        }
        SetStatus($"This run: {verified} verified, {failed} failed, {stopped} cancelled, {pending} still queued. " +
            (noFileResults ? "Review the error below or open the activity log."
            : failed > 0 ? "Review the file details and activity log before relying on this copy."
            : stopped > 0 || pending > 0 ? "Completed files are kept; the destination is not fully verified."
            : "Every checked file matches its source with SHA-256."));
    }

    /// <summary>
    /// Preview harness, used for screenshots and as an end-to-end smoke test:
    ///   Bunshin.exe --demo &lt;source&gt; &lt;destination&gt;
    ///                [--corrupt] [--mirror] [--cancel-after &lt;ms&gt;] [--shot out.png]
    /// Queues the source, runs the normal copy+verify path, optionally flips one
    /// byte in the destination to show a real mismatch, then writes a PNG.
    /// </summary>
    private async void Preview_Loaded(object sender, RoutedEventArgs e)
    {
        var args = Environment.GetCommandLineArgs();
        var at = Array.IndexOf(args, "--demo");
        if (at < 0 || at + 2 >= args.Length) return;

        var source = args[at + 1];
        var destination = args[at + 2];
        var shotAt = Array.IndexOf(args, "--shot");
        var shot = shotAt >= 0 && shotAt + 1 < args.Length ? args[shotAt + 1] : null;

        try
        {
            DestinationBox.Text = destination;
            if (Array.IndexOf(args, "--mirror") >= 0) MirrorCheck.IsChecked = true;

            var cancelAt = Array.IndexOf(args, "--cancel-after");
            if (cancelAt >= 0 && cancelAt + 1 < args.Length && int.TryParse(args[cancelAt + 1], out var cancelMs))
                _ = Task.Delay(cancelMs).ContinueWith(_ => Dispatcher.Invoke(() => _cts?.Cancel()));

            AddPaths(new[] { source });
            await RunQueueAsync(destination);

            if (Array.IndexOf(args, "--corrupt") >= 0)
                await CorruptThenReverifyAsync(source);
        }
        catch (Exception ex)
        {
            SetStatus("Preview failed: " + ex.Message);
        }

        if (shot is null) return;

        await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
        UpdateLayout();
        SaveScreenshot(shot);
        Application.Current.Shutdown();
    }

    private async Task CorruptThenReverifyAsync(string source)
    {
        var job = _jobs.FirstOrDefault();
        if (job is null) return;

        var pair = CopyEngine.BuildPairs(source, job.Target).FirstOrDefault();
        if (pair.Source is null) return;

        // Flip the first byte, keeping the length: the case a size/time check misses.
        var bytes = await File.ReadAllBytesAsync(pair.Dest);
        if (bytes.Length == 0) return;
        bytes[0] ^= 0xFF;
        await File.WriteAllBytesAsync(pair.Dest, bytes);

        _rows.Clear();
        var verify = await _engine.VerifyAsync(source, job.Target, job.Name,
            new Progress<VerifyRow>(row => _rows.Add(row)), CancellationToken.None);

        job.State = verify.Failed == 0 ? JobState.Verified : JobState.Failed;
        job.Detail = $"{verify.Checked} checked, {verify.Failed} failed";
        SetPhase(3);
        OutcomeTitle.Text = $"{verify.Failed} file{(verify.Failed == 1 ? " differs" : "s differ")}.";
        OutcomeTitle.SetResourceReference(TextBlock.ForegroundProperty, "Failure");
        Progress.SetResourceReference(ProgressBar.ForegroundProperty, "Failure");
        ProgressText.Text = $"{verify.Checked} checked · {verify.Failed} mismatched";
        DetailsExpander.IsExpanded = true;
        SetStatus($"{verify.Failed} mismatch - the destination no longer matches the source.");
        RefreshCounts();
    }

    private void SaveScreenshot(string path)
    {
        var root = (FrameworkElement)Content;
        var margin = root.Margin;
        var width = (int)Math.Ceiling(root.ActualWidth + margin.Left + margin.Right);
        var height = (int)Math.Ceiling(root.ActualHeight + margin.Top + margin.Bottom);

        // RenderTargetBitmap starts empty, so lay down the window background
        // first or the PNG is transparent between the cards.
        var backdrop = new DrawingVisual();
        using (var dc = backdrop.RenderOpen())
            dc.DrawRectangle(Background, null, new Rect(0, 0, width, height));

        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(backdrop);
        bitmap.Render(root);

        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        encoder.Save(stream);
    }

    private async Task RunJobAsync(CopyJob job, string destination, CancellationToken token)
    {
        var source = job.Source;
        string? logPath = null;
        var verification = "Incomplete — no verification verdict";
        var verdicts = new List<string>();
        var clock = Stopwatch.StartNew();
        try
        {
            job.Target = TargetFor(source, destination);
            if (VerifyOnlyCheck.IsChecked != true)
            {
                job.State = JobState.Copying;
                SetPhase(1);
                OutcomeTitle.Text = "Copying your files.";
                job.Detail = "scanning";
                SetStatus($"Copying {job.Name} → {job.Target}. Verification follows the copy.");
                Progress.IsIndeterminate = SystemParameters.ClientAreaAnimation;
                ProgressText.Text = "Scanning source…";
                AppendLog(job, $"--- {job.Name} -> {job.Target}");

                var copy = await _engine.CopyAsync(
                    source, job.Target, MirrorCheck.IsChecked == true,
                    new Progress<string>(line => AppendLog(job, line)),
                    new Progress<CopyProgress>(p =>
                    {
                        Progress.IsIndeterminate = false;
                        var pct = p.BytesTotal > 0 ? 100.0 * p.BytesDone / p.BytesTotal : 100;
                        Progress.Value = pct;
                        ProgressText.Text =
                            $"Copy: {CopyEngine.FormatSize(p.BytesDone)} / {CopyEngine.FormatSize(p.BytesTotal)}" +
                            $"   {CopyEngine.FormatSize((long)p.BytesPerSecond)}/s";
                        job.Detail = $"{p.FilesDone} / {p.FilesTotal} files · {pct:0}%";
                    }),
                    token);
                logPath = copy.LogPath;

                if (copy.Cancelled)
                {
                    job.State = JobState.Cancelled;
                    job.Detail = "cancelled";
                    return;
                }

                if (copy.ExitCode != 0)
                {
                    job.State = JobState.Failed;
                    job.Detail = $"{copy.Failed} file(s) could not be copied";
                    return;
                }
            }

            token.ThrowIfCancellationRequested();
            job.State = JobState.Verifying;
            SetPhase(2);
            OutcomeTitle.Text = "Checking your copy.";
            job.Detail = "hashing";
            SetStatus($"Verifying {job.Name} with SHA-256. The copy is not verified until this finishes.");
            Progress.IsIndeterminate = SystemParameters.ClientAreaAnimation;
            Progress.Value = 0;
            ProgressText.Text = "Scanning for verification…";

            var total = await Task.Run(() => CopyEngine.CountFiles(source, token), token);
            token.ThrowIfCancellationRequested();
            Progress.IsIndeterminate = SystemParameters.ClientAreaAnimation;
            ProgressText.Text = $"Hashing · 0 / {total} files checked";
            var seen = 0;
            var verify = await _engine.VerifyAsync(
                source, job.Target, job.Name,
                new Progress<VerifyRow>(row =>
                {
                    _rows.Add(row);
                    if (row.Status != "OK")
                        verdicts.Add($"verdict: {row.Status} | source: {row.Source} | destination: {row.Destination}");
                    seen++;
                    ProgressText.Text = $"Hashing · {seen} / {total} files checked";
                    job.Detail = $"{seen} / {total} checked";
                }), token);

            token.ThrowIfCancellationRequested();
            Progress.IsIndeterminate = false;
            Progress.Value = 100;
            job.Detail = $"{verify.Checked} checked, {verify.Failed} failed";
            verification = job.Detail;
            job.State = verify.Failed == 0 ? JobState.Verified : JobState.Failed;
            AppendLog(job, $"SHA-256: {job.Detail}");
        }
        catch (OperationCanceledException)
        {
            job.State = JobState.Cancelled;
            job.Detail = "stopped · not fully verified";
        }
        catch (Exception ex)
        {
            job.State = JobState.Failed;
            job.Detail = ex.Message;
        }
        finally
        {
            clock.Stop();
            job.Elapsed = clock.Elapsed.ToString(@"m\:ss");
            // Extend the engine's copy log rather than producing two logs for one job.
            // Verify-only and preflight failures still get their own durable record.
            logPath ??= Path.Combine(CopyEngine.LogDirectory, $"gui-{DateTime.Now:yyyyMMdd-HHmmss-fff}-{Environment.ProcessId}-{Guid.NewGuid():N}.log");
            var audit = new List<string>
            {
                "", $"Bunshin job completed: {DateTimeOffset.Now:O}",
                $"source: {source}", $"destination: {job.Target}",
                $"mode: {(VerifyOnlyCheck.IsChecked == true ? "verify only" : MirrorCheck.IsChecked == true ? "mirror + verify" : "copy + verify")}",
                $"SHA-256: {verification}"
            };
            audit.AddRange(verdicts);
            audit.Add($"result: {job.StateText} — {job.Detail}; elapsed: {job.Elapsed}");
            try
            {
                Directory.CreateDirectory(CopyEngine.LogDirectory);
                await File.AppendAllLinesAsync(logPath, audit, new UTF8Encoding(false));
                AppendLog(job, $"Log saved: {logPath}");
            }
            catch (Exception ex)
            {
                job.State = JobState.Failed;
                job.Detail = $"Log could not be saved: {ex.Message}";
                AppendLog(job, job.Detail);
            }
        }
    }

    private void Cancel_Click(object sender, RoutedEventArgs e)
    {
        if (_cts is null) return;
        _cts?.Cancel();
        OutcomeTitle.Text = "Stopping safely…";
        CancelButton.IsEnabled = false;
        Progress.IsIndeterminate = false;
        SetStatus("Stopping safely… Waiting for the current operation to finish cleanup. Completed files are kept; verification may be incomplete.");
    }

    private void Window_Closing(object? sender, CancelEventArgs e)
    {
        if (_cts is null) return;
        e.Cancel = true;
        if (_closeAfterCancel) return;
        if (BunshinDialog.Show(this, "A job is still running. Stop the queue and close after cleanup? Completed files are kept; the destination may not be fully verified.",
            "Bunshin — stop and close?", confirm: true) != MessageBoxResult.Yes) return;
        // The dispatcher keeps processing work while the confirmation is open.
        if (_cts is null)
        {
            e.Cancel = false;
            return;
        }
        _closeAfterCancel = true;
        Cancel_Click(this, new RoutedEventArgs());
    }

    private void Mode_Changed(object sender, RoutedEventArgs e)
    {
        if (CopyButton is null) return;
        if (_cts is null && _jobs.Any(job => !job.IsTerminal)) _planning = true;
        CopyButton.Content = VerifyOnlyCheck.IsChecked == true ? "Verify only" : MirrorCheck.IsChecked == true ? "Mirror and verify" : "Copy and verify";
        ModeDescription.Text = VerifyOnlyCheck.IsChecked == true
            ? "Compare source and destination with SHA-256. Nothing is copied or deleted."
            : MirrorCheck.IsChecked == true ? "Copy and verify folders. Extra files in each resolved destination are permanently deleted."
            : "Copy files, then compare every file with SHA-256.";
        CopyPhase.Text = VerifyOnlyCheck.IsChecked == true ? "01  Copy skipped" : "01  Copy";
        RefreshActions();
    }

    private void SetRunning(bool running)
    {
        CancelButton.IsEnabled = running;
        CancelButton.Visibility = running ? Visibility.Visible : Visibility.Collapsed;
        CopyButton.Visibility = running ? Visibility.Collapsed : Visibility.Visible;
        MirrorCheck.IsEnabled = !running;
        CopyModeCheck.IsEnabled = !running;
        VerifyOnlyCheck.IsEnabled = !running;
        DestinationBox.IsEnabled = !running;
        BrowseButton.IsEnabled = !running;
        AddFilesButton.IsEnabled = !running;
        AddFolderButton.IsEnabled = !running;
        RemoveButton.IsEnabled = !running;
        ClearButton.IsEnabled = !running;
        AllowDrop = !running;
        if (running)
        {
            OutcomeTitle.SetResourceReference(TextBlock.ForegroundProperty, "Ink");
            Progress.SetResourceReference(ProgressBar.ForegroundProperty, "Accent");
        }
        RefreshActions();
        if (running) CancelButton.Focus();
        else if (OpenDestinationButton.IsEnabled && OpenDestinationButton.IsVisible) OpenDestinationButton.Focus();
        else if (CopyButton.IsEnabled) CopyButton.Focus();
    }

    private void RefreshCounts()
    {
        var items = _jobs.Count;
        QueueCount.Text = $"{items} item{(items == 1 ? "" : "s")}";
        ResultsCount.Text = $"{_rows.Count} file{(_rows.Count == 1 ? "" : "s")}";

        EmptyHint.Visibility = items == 0 ? Visibility.Visible : Visibility.Collapsed;
        ResultsHint.Visibility = _rows.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        var pending = _jobs.Count(j => !j.IsTerminal);
        var verified = _jobs.Count(j => j.State == JobState.Verified);
        var failed = _jobs.Count(j => j.State == JobState.Failed);
        var cancelled = _jobs.Count(j => j.State == JobState.Cancelled);

        QueueSummary.Text = pending > 0
            ? $"{pending} pending"
            : items > 0 ? $"{verified} verified, {failed} failed" + (cancelled > 0 ? $", {cancelled} cancelled" : "") : "";
        RefreshMappings();
        RefreshActions();
    }

    private void Jobs_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        ShowLane(JobsList.SelectedItem as CopyJob);
        RefreshActions();
    }

    private void AllLanes_Click(object sender, RoutedEventArgs e)
    {
        JobsList.SelectedItem = null;
        ShowLane(null);
    }

    /// <summary>
    /// One lane per job plus a merged view. Only the visible lane is appended to
    /// on the hot path; switching rebuilds the box once from the capped buffer.
    /// </summary>
    private void ShowLane(CopyJob? job)
    {
        _lane = job;
        LogHeader.Text = job is null ? "LOG · ALL JOBS" : $"LOG · {job.Name.ToUpperInvariant()}";
        AllLanesButton.Visibility = job is null ? Visibility.Collapsed : Visibility.Visible;

        LogBox.Clear();
        _boxLines = 0;
        foreach (var line in job is null ? _allLog : LaneFor(job)) AppendToBox(line);
    }

    private List<string> LaneFor(CopyJob job)
    {
        if (!_jobLogs.TryGetValue(job, out var lane))
        {
            lane = new List<string>();
            _jobLogs[job] = lane;
        }
        return lane;
    }

    private void AppendLog(CopyJob job, string line)
    {
        var lane = LaneFor(job);
        lane.Add(line);
        _allLog.Add($"[{job.Name}] {line}");
        Trim(lane);
        Trim(_allLog);

        if (_lane is null || ReferenceEquals(_lane, job)) AppendToBox(line);
    }

    private static void Trim(List<string> lines)
    {
        if (lines.Count > MaxLogLines) lines.RemoveRange(0, lines.Count - MaxLogLines);
    }

    private void AppendToBox(string line)
    {
        if (++_boxLines > MaxLogLines * 2)
        {
            LogBox.Clear();
            _boxLines = 1;
        }
        LogBox.AppendText(line + Environment.NewLine);
        LogBox.ScrollToEnd();
    }

    private void SetStatus(string text) => StatusText.Text = text;

    private void Destination_Changed(object sender, TextChangedEventArgs e)
    {
        if (CopyButton is null) return;
        if (_cts is null && _jobs.Any(job => !job.IsTerminal)) _planning = true;
        RefreshMappings();
        RefreshActions();
    }

    private void RefreshMappings()
    {
        foreach (var job in _jobs.Where(job => !job.IsTerminal))
        {
            try
            {
                var destination = DestinationBox.Text.Trim();
                var target = destination.Length == 0 ? null : TargetFor(job.Source, CopyEngine.Normalize(destination));
                job.ResolvedTarget = target is null ? "→ Choose a destination" : "→ " +
                    (Directory.Exists(job.Source) ? target : Path.Combine(target, Path.GetFileName(job.Source)));
            }
            catch { job.ResolvedTarget = "→ Enter a valid destination path"; }
        }
    }

    private void RefreshActions()
    {
        var idle = _cts is null;
        CopyButton.IsEnabled = idle && _jobs.Any(job => !job.IsTerminal) && !string.IsNullOrWhiteSpace(DestinationBox.Text);
        RemoveButton.IsEnabled = idle && JobsList.SelectedItems.Count > 0;
        ClearButton.IsEnabled = idle && _jobs.Any(job => job.IsTerminal);
        OpenDestinationButton.Visibility = idle && _jobs.Any(job => job.IsTerminal) ? Visibility.Visible : Visibility.Collapsed;
        OpenDestinationButton.IsEnabled = _lastDestination is not null && Directory.Exists(_lastDestination);
        ViewLogButton.Visibility = idle && _allLog.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        if (idle && (_planning || _jobs.Count == 0))
        {
            OutcomeError.Visibility = Visibility.Collapsed;
            OutcomeError.Text = "";
            var pending = _jobs.Count(job => !job.IsTerminal);
            OutcomeTitle.Text = pending == 0 ? "Choose what to copy." : string.IsNullOrWhiteSpace(DestinationBox.Text)
                ? "Choose where it goes." : "Ready to check every file.";
            OutcomeTitle.SetResourceReference(TextBlock.ForegroundProperty, "Ink");
            Progress.SetResourceReference(ProgressBar.ForegroundProperty, "Accent");
            Progress.IsIndeterminate = false;
            Progress.Value = 0;
            ProgressText.Text = pending == 0 ? "Ready when you are" : $"{pending} source{(pending == 1 ? "" : "s")} ready";
            SetPhase(0);
            SetStatus(pending == 0 ? "Add your sources and choose a destination to begin."
                : string.IsNullOrWhiteSpace(DestinationBox.Text) ? "Choose a destination to preview where each source will go."
                : "Review the resolved paths above, then start. Previous job verdicts remain in the source list.");
        }
    }

    private void SetPhase(int phase)
    {
        CopyPhase.SetResourceReference(TextBlock.ForegroundProperty, phase == 1 ? "Accent" : "Dim");
        VerifyPhase.SetResourceReference(TextBlock.ForegroundProperty, phase == 2 ? "Accent" : "Dim");
        ResultPhase.SetResourceReference(TextBlock.ForegroundProperty, phase == 3 ? "Accent" : "Dim");
        CopyPhase.FontWeight = phase == 1 ? FontWeights.SemiBold : FontWeights.Normal;
        VerifyPhase.FontWeight = phase == 2 ? FontWeights.SemiBold : FontWeights.Normal;
        ResultPhase.FontWeight = phase == 3 ? FontWeights.SemiBold : FontWeights.Normal;
    }

    private void OpenDestination_Click(object sender, RoutedEventArgs e)
    {
        if (_lastDestination is null) return;
        try { Process.Start(new ProcessStartInfo(_lastDestination) { UseShellExecute = true }); }
        catch (Exception ex) { BunshinDialog.Show(this, ex.Message, "Bunshin — open destination"); }
    }

    private void ViewLog_Click(object sender, RoutedEventArgs e)
    {
        LogExpander.IsExpanded = true;
        // Expansion must complete layout before the log can receive keyboard focus.
        Dispatcher.InvokeAsync(() =>
        {
            LogBox.BringIntoView();
            Keyboard.Focus(LogBox);
        }, DispatcherPriority.Input);
    }

    private void Actions_GotKeyboardFocus(object sender, KeyboardFocusChangedEventArgs e)
    {
        // Include the panel's child margins so keyboard focus never hugs the
        // viewport edge or clips the button's focus adornment.
        Dispatcher.InvokeAsync(() => ActionsPanel.BringIntoView(), DispatcherPriority.Input);
    }

    private void Button_PointerDown(object sender, MouseButtonEventArgs e)
    {
        if (!SystemParameters.ClientAreaAnimation || sender is not Button button || !button.IsEnabled) return;
        button.RenderTransform = new ScaleTransform(0.98, 0.98);
    }

    private void Button_PointerUp(object sender, MouseEventArgs e)
    {
        if (sender is not Button button || button.RenderTransform is not ScaleTransform scale) return;
        if (!SystemParameters.ClientAreaAnimation) { button.RenderTransform = Transform.Identity; return; }
        var release = new DoubleAnimation(1, TimeSpan.FromMilliseconds(100)) { EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut } };
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, release);
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, release);
    }

    private void SystemSettings_Changed(object? sender, PropertyChangedEventArgs e) => Dispatcher.Invoke(() =>
    {
        ApplyAccessibilityPalette();
        foreach (var job in _jobs) job.RefreshBrush();
        foreach (var row in _rows) row.RefreshBrush();
        if (!SystemParameters.ClientAreaAnimation) Progress.IsIndeterminate = false;
    });

    private void ApplyAccessibilityPalette()
    {
        if (!SystemParameters.HighContrast)
        {
            foreach (var entry in _standardBrushes) Resources[entry.Key] = entry.Value;
            return;
        }
        Resources["Paper"] = SystemColors.WindowBrush;
        Resources["Ink"] = Resources["Dim"] = SystemColors.WindowTextBrush;
        Resources["Success"] = Resources["Failure"] = SystemColors.WindowTextBrush;
        Resources["Line"] = SystemColors.WindowTextBrush;
        Resources["Accent"] = Resources["PrimaryHover"] = Resources["PrimaryPressed"] = SystemColors.HighlightBrush;
        Resources["OnAccent"] = SystemColors.HighlightTextBrush;
        Resources["Hover"] = Resources["Pressed"] = SystemColors.ControlBrush;
    }
}
  
