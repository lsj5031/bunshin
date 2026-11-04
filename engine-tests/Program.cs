using Bunshin.Gui;
using System.Diagnostics;
using System.Security.AccessControl;
using System.Security.Principal;

// A standalone public-engine harness: no WPF, NuGet packages, or private hooks.
var suite = Path.Combine(Path.GetTempPath(), "bunshin-engine-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(suite);
var errors = new List<string>();
var tested = 0;
var engine = new CopyEngine();
try
{
    await Test("missing source cannot copy or verify successfully", async root =>
    {
        var source = Path.Combine(root, "missing");
        var target = Path.Combine(root, "target");
        Directory.CreateDirectory(target);
        File.WriteAllText(Path.Combine(target, "keep"), "precious");
        await MustFailCopy(source, target, true);
        Check(File.ReadAllText(Path.Combine(target, "keep")) == "precious", "mirror deleted existing data");
        await MustFailVerify(source, target);
    });

    await Test("overlap, ancestors, self-copy rejected", async root =>
    {
        var source = Path.Combine(root, "source");
        Directory.CreateDirectory(source);
        File.WriteAllText(Path.Combine(source, "keep"), "precious");
        await MustFailCopy(source, source, true);
        await MustFailCopy(source, Path.Combine(source, "child"), false);
        await MustFailCopy(source, root, true);
        await MustFailCopy(Path.Combine(source, "keep"), source, false);
        await MustFailCopy(source.ToUpperInvariant() + "\\.\\", source, false);
        await MustFailCopy(@"\\?\" + source, source + "\\child", false);
        await MustFailCopy(Path.GetPathRoot(root)!, root, false);
        Check(File.ReadAllText(Path.Combine(source, "keep")) == "precious", "source changed");
        Check(!Directory.Exists(Path.Combine(source, "child")), "overlap created output");
        var sibling = await engine.CopyAsync(source, source + "-backup", false, null, null, default);
        Check(sibling.ExitCode == 0 && sibling.Copied == 1, "boundary-safe sibling incorrectly blocked");
    });

    await Test("missing source verification fails independently", async root =>
    {
        var target = Path.Combine(root, "target");
        Directory.CreateDirectory(target);
        await MustFailVerify(Path.Combine(root, "missing"), target);
    });

    await Test("Windows trailing-dot aliases cannot bypass overlap guard", async root =>
    {
        var source = Path.Combine(root, "source");
        Directory.CreateDirectory(source);
        File.WriteAllText(Path.Combine(source, "keep"), "precious");
        Check(Directory.Exists(root + "."), "fixture alias does not resolve on this filesystem");
        await MustFailCopy(source, root + ".", true);
        Check(File.ReadAllText(Path.Combine(source, "keep")) == "precious", "source deleted through Windows alias");
    });

    await Test("empty source requires an existing verification target", async root =>
    {
        var source = Path.Combine(root, "source");
        var parent = Path.Combine(root, "backup");
        var target = Path.Combine(parent, "source");
        Directory.CreateDirectory(source);
        Directory.CreateDirectory(parent);
        await MustFailVerify(source, target);
        Check(!Directory.Exists(target), "verification created its target");
        Directory.CreateDirectory(target);
        var verified = await engine.VerifyAsync(source, target, "empty", null, default);
        Check(verified.Checked == 0 && verified.Failed == 0, "valid empty directory failed verification");
        Directory.Delete(target);
        File.WriteAllText(target, "not a directory");
        await MustFailVerify(source, target);
    });

    await Test("inaccessible source content is never omitted", async root =>
    {
        var source = Path.Combine(root, "source");
        var denied = Path.Combine(source, "private");
        var target = Path.Combine(root, "target");
        Directory.CreateDirectory(denied);
        Directory.CreateDirectory(target);
        File.WriteAllText(Path.Combine(denied, "hidden-data"), "must be included");
        File.WriteAllText(Path.Combine(target, "extra"), "preserve");
        await DenyListing(denied, async () =>
        {
            await MustFailCopy(source, target, true);
            Check(File.ReadAllText(Path.Combine(target, "extra")) == "preserve", "incomplete source pruned destination");
            await MustFailVerify(source, target);
            Check(CopyEngine.CountFiles(source) == 0, "best-effort CountFiles contract changed");
        });
    });

    await Test("inaccessible destination prevents all mirror deletion", async root =>
    {
        var source = Path.Combine(root, "source");
        var target = Path.Combine(root, "target");
        var denied = Path.Combine(target, "private");
        Directory.CreateDirectory(source);
        Directory.CreateDirectory(denied);
        File.WriteAllText(Path.Combine(target, "extra"), "preserve");
        await DenyListing(denied, async () =>
        {
            await MustFailCopy(source, target, true);
            Check(File.ReadAllText(Path.Combine(target, "extra")) == "preserve", "partial destination scan pruned data");
        });
    });

    await Test("source disappearing after scan prevents mirror deletion", async root =>
    {
        var source = Path.Combine(root, "source");
        var target = Path.Combine(root, "target");
        Directory.CreateDirectory(source);
        Directory.CreateDirectory(target);
        File.WriteAllText(Path.Combine(target, "extra"), "preserve");
        var result = await engine.CopyAsync(source, target, true, null,
            new Immediate<CopyProgress>(_ => { if (Directory.Exists(source)) Directory.Delete(source); }), default);
        Check(result.ExitCode != 0 && result.Failed > 0, "disappearing empty source falsely succeeded");
        Check(File.ReadAllText(Path.Combine(target, "extra")) == "preserve", "vanished source triggered deletion");
    });

    await Test("junction aliases rejected and source child junction skipped", async root =>
    {
        var source = Path.Combine(root, "source");
        var alias = Path.Combine(root, "alias");
        var target = Path.Combine(root, "target");
        Directory.CreateDirectory(source);
        File.WriteAllText(Path.Combine(source, "keep"), "precious");
        Junction(alias, source);
        try
        {
            await MustFailCopy(source, alias, true);
            await MustFailVerify(source, alias);
            await MustFailCopy(alias, target, false);
            Directory.CreateDirectory(target);
            Directory.CreateDirectory(Path.Combine(source, "child"));
            File.WriteAllText(Path.Combine(source, "child", "keep"), "precious");
            File.WriteAllText(Path.Combine(target, "keep"), "precious");
            Junction(Path.Combine(target, "child"), source);
            await MustFailCopy(source, target, false);
            await MustFailVerify(source, target);
            Directory.Delete(Path.Combine(target, "child"));
            Junction(Path.Combine(source, "loop"), source);
            var result = await engine.CopyAsync(source, target, false, null, null, default);
            Check(result.ExitCode == 0 && result.Copied + result.Skipped == 2 && !Directory.Exists(Path.Combine(target, "loop")), "child junction was traversed");
            Check(File.ReadAllText(Path.Combine(source, "keep")) == "precious", "source changed through alias");
        }
        finally
        {
            foreach (var link in new[] { alias, Path.Combine(source, "loop"), Path.Combine(target, "child") })
                if (Directory.Exists(link) && (File.GetAttributes(link) & FileAttributes.ReparsePoint) != 0)
                    Directory.Delete(link);
        }
    });

    await Test("cancelled overwrite preserves existing destination", async root =>
    {
        var source = Path.Combine(root, "source.bin");
        var target = Path.Combine(root, "target");
        Directory.CreateDirectory(target);
        using (var stream = File.Create(source)) stream.SetLength(64 * 1024 * 1024);
        var dest = Path.Combine(target, "source.bin");
        File.WriteAllText(dest, "previous valid content");
        var time = File.GetLastWriteTimeUtc(dest);
        using var cancel = new CancellationTokenSource();
        var callbacks = 0;
        var result = await engine.CopyAsync(source, target, false, null,
            new Immediate<CopyProgress>(p => { if (p.Current.Length > 0) { callbacks++; cancel.Cancel(); } }), cancel.Token);
        Check(callbacks > 0 && result.Cancelled, "did not cancel inside copy");
        Check(File.Exists(dest) && File.ReadAllText(dest) == "previous valid content", "old file lost on cancel");
        Check(File.GetLastWriteTimeUtc(dest) == time, "old timestamp changed");
        Check(Directory.GetFiles(target).Length == 1, "temporary copy left behind");
    });

    await Test("copy failure suppresses mirror deletion", async root =>
    {
        var source = Path.Combine(root, "source");
        var target = Path.Combine(root, "target");
        Directory.CreateDirectory(source);
        Directory.CreateDirectory(target);
        var file = Path.Combine(source, "locked");
        File.WriteAllText(file, "new data");
        File.WriteAllText(Path.Combine(target, "locked"), "old valid data");
        File.WriteAllText(Path.Combine(target, "extra"), "keep on failure");
        using var locked = new FileStream(file, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        await MustFailCopy(source, target, true);
        Check(File.ReadAllText(Path.Combine(target, "extra")) == "keep on failure", "extras removed after copy failure");
        Check(File.ReadAllText(Path.Combine(target, "locked")) == "old valid data", "failed overwrite lost data");
    });

    await Test("locked destination preserves old file and removes staging file", async root =>
    {
        var source = Path.Combine(root, "data");
        var target = Path.Combine(root, "target");
        Directory.CreateDirectory(target);
        File.WriteAllText(source, "replacement");
        var dest = Path.Combine(target, "data");
        File.WriteAllText(dest, "previous valid content");
        using (var locked = new FileStream(dest, FileMode.Open, FileAccess.Read, FileShare.Read))
            await MustFailCopy(source, target, false);
        Check(File.ReadAllText(dest) == "previous valid content", "failed publish destroyed original");
        Check(Directory.GetFiles(target).Length == 1, "failed publish leaked staging file");
    });

    await Test("directory creation failure suppresses mirror deletion", async root =>
    {
        var source = Path.Combine(root, "source");
        var target = Path.Combine(root, "target");
        Directory.CreateDirectory(Path.Combine(source, "empty"));
        Directory.CreateDirectory(target);
        File.WriteAllText(Path.Combine(target, "empty"), "file obstructing directory");
        File.WriteAllText(Path.Combine(target, "extra"), "preserve");
        await MustFailCopy(source, target, true);
        Check(File.ReadAllText(Path.Combine(target, "extra")) == "preserve", "directory failure permitted prune");
    });

    await Test("scan cancellation leaves destination untouched", async root =>
    {
        var source = Path.Combine(root, "source");
        var target = Path.Combine(root, "target");
        Directory.CreateDirectory(source);
        for (var i = 0; i < 6000; i++) File.WriteAllText(Path.Combine(source, i.ToString()), "x");
        using var countCancel = new CancellationTokenSource();
        countCancel.CancelAfter(1);
        var countCancelled = false;
        try { _ = await Task.Run(() => CopyEngine.CountFiles(source, countCancel.Token)); }
        catch (OperationCanceledException) { countCancelled = true; }
        Check(countCancelled, "CountFiles suppressed cancellation");
        using var cancel = new CancellationTokenSource();
        cancel.CancelAfter(1);
        try
        {
            var result = await engine.CopyAsync(source, target, true, null, null, cancel.Token);
            Check(result.Cancelled, "scan cancellation was ignored");
        }
        catch (OperationCanceledException) { }
        Check(!Directory.Exists(target), "cancelled scan created output");
    });

    await Test("large-file verification responds to cancellation", async root =>
    {
        var source = Path.Combine(root, "large");
        var target = Path.Combine(root, "target");
        Directory.CreateDirectory(target);
        using (var file = File.Create(source)) file.SetLength(1024L * 1024 * 1024);
        using (var file = File.Create(Path.Combine(target, "large"))) file.SetLength(1024L * 1024 * 1024);
        using var cancel = new CancellationTokenSource();
        cancel.CancelAfter(25);
        var cancelled = false;
        var rows = 0;
        try { await engine.VerifyAsync(source, target, "large", new Immediate<VerifyRow>(_ => rows++), cancel.Token); }
        catch (OperationCanceledException) { cancelled = true; }
        Check(cancelled && rows == 0, "large file was marked verified after cancellation");
    });

    await Test("nesting, empty dirs, skips, SHA-256 and successful mirror", async root =>
    {
        var source = Path.Combine(root, "photos");
        var target = Path.Combine(root, "backup", "photos"); // shell supplies Explorer nesting
        Directory.CreateDirectory(Path.Combine(source, "empty"));
        File.WriteAllText(Path.Combine(source, "тест-文件.txt"), "abcde");
        var stamp = new DateTime(2024, 3, 5, 7, 9, 11, DateTimeKind.Utc);
        Directory.SetLastWriteTimeUtc(Path.Combine(source, "empty"), stamp);
        var first = await engine.CopyAsync(source, target, false, null, null, default);
        Check(first.ExitCode == 0 && first.Copied == 1, "initial copy failed");
        Check(Path.GetDirectoryName(first.LogPath) == CopyEngine.LogDirectory &&
            CopyEngine.LogDirectory.EndsWith(@"\bunshin\logs", StringComparison.Ordinal), "wrong log location");
        Check(File.ReadAllText(first.LogPath).StartsWith("Bunshin GUI"), "old log branding remains");
        Check(Directory.Exists(Path.Combine(target, "empty")), "empty directory missing");
        Check(Directory.GetLastWriteTimeUtc(Path.Combine(target, "empty")) == stamp, "directory timestamp missing");
        var second = await engine.CopyAsync(source, target, false, null, null, default);
        Check(second.ExitCode == 0 && second.Skipped == 1, "size+mtime skip changed");
        Check(first.LogPath != second.LogPath, "per-job log collision");
        var verified = await engine.VerifyAsync(source, target, "test", null, default);
        Check(verified.Checked == 1 && verified.Failed == 0, "clean verify failed");
        var dest = Path.Combine(target, "тест-文件.txt");
        var fileTime = File.GetLastWriteTimeUtc(dest);
        File.WriteAllText(dest, "abXde");
        File.SetLastWriteTimeUtc(dest, fileTime);
        var skipCorrupt = await engine.CopyAsync(source, target, false, null, null, default);
        Check(skipCorrupt.Skipped == 1, "skip should remain size+mtime based");
        verified = await engine.VerifyAsync(source, target, "test", null, default);
        Check(verified.Checked == 1 && verified.Failed == 1, "SHA-256 missed same-size corruption");
        File.SetLastWriteTimeUtc(dest, fileTime.AddDays(-1));
        File.WriteAllText(Path.Combine(target, "extra"), "remove");
        Directory.CreateDirectory(Path.Combine(target, "extra-dir"));
        var mirror = await engine.CopyAsync(source + "\\", target + "\\", true, null, null, default);
        Check(mirror.ExitCode == 0 && mirror.Copied == 1, "mirror copy failed");
        Check(!File.Exists(Path.Combine(target, "extra")) && !Directory.Exists(Path.Combine(target, "extra-dir")), "extras remain");
        Check(File.ReadAllText(dest) == "abcde", "replacement content wrong");
    });

    await Test("long paths and extended targets survive copy, verify and mirror", async root =>
    {
        var source = Path.Combine(root, "source");
        var target = Path.Combine(root, "target");
        var relative = Path.Combine(new string('a', 95), new string('b', 95), "文件.txt");
        var file = Path.Combine(source, relative);
        Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        File.WriteAllText(file, "long-path data");
        var first = await engine.CopyAsync(source, @"\\?\" + target, false, null, null, default);
        Check(first.ExitCode == 0 && first.Copied == 1, "long path copy failed");
        var pairs = CopyEngine.BuildPairs(@"\\?\" + source, target).ToList();
        Check(pairs.Count == 1 && pairs[0].Dest == Path.Combine(target, relative), "extended mapping differs");
        var verified = await engine.VerifyAsync(source, @"\\?\" + target, "long", null, default);
        Check(verified.Checked == 1 && verified.Failed == 0, "long path verify failed");
        File.WriteAllText(Path.Combine(target, "extra"), "remove");
        var mirror = await engine.CopyAsync(source, @"\\?\" + target + "\\", true, null, null, default);
        Check(mirror.ExitCode == 0 && mirror.Skipped == 1 && File.Exists(pairs[0].Dest), "mirror deleted expected long file");
        Check(!File.Exists(Path.Combine(target, "extra")), "long path mirror did not delete extra");
        Check(CopyEngine.CountFiles(source) == 1, "long path count failed");
    });

    await Test("root and extended UNC normalization", root =>
    {
        Check(CopyEngine.LongPath(@"C:\") == @"C:\", "drive root lost");
        var unc = @"\\server\share\" + new string('a', 250);
        Check(CopyEngine.LongPath(unc) == @"\\?\UNC\server\share\" + new string('a', 250), "long UNC prefix invalid");
        Check(CopyEngine.LongPath(@"\\?\UNC\server\share\folder") == @"\\?\UNC\server\share\folder", "extended UNC changed");
        return Task.CompletedTask;
    });
}
finally { Directory.Delete(suite, true); }
Console.WriteLine($"{tested - errors.Count}/{tested} scenarios passed");
return errors.Count == 0 ? 0 : 1;

async Task Test(string name, Func<string, Task> run)
{
    tested++;
    var root = Path.Combine(suite, Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(root);
    try { await run(root); Console.WriteLine("PASS " + name); }
    catch (Exception ex) { errors.Add(name); Console.WriteLine("FAIL " + name + ": " + ex.Message); }
}

async Task MustFailCopy(string source, string target, bool mirror)
{
    CopyResult result;
    try { result = await engine.CopyAsync(source, target, mirror, null, null, default); }
    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException) { return; }
    Check(result.ExitCode != 0 && result.Failed > 0, "copy falsely succeeded");
}

async Task MustFailVerify(string source, string target)
{
    VerifyResult result;
    try { result = await engine.VerifyAsync(source, target, "test", null, default); }
    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or ArgumentException) { return; }
    Check(result.Failed > 0, "verification falsely succeeded");
}

static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }

static async Task DenyListing(string path, Func<Task> run)
{
    var dir = new DirectoryInfo(path);
    var denied = dir.GetAccessControl();
    var rule = new FileSystemAccessRule(WindowsIdentity.GetCurrent().User!,
        FileSystemRights.ListDirectory, AccessControlType.Deny);
    denied.AddAccessRule(rule);
    dir.SetAccessControl(denied);
    try
    {
        var blocked = false;
        try { _ = Directory.GetFiles(path); }
        catch (UnauthorizedAccessException) { blocked = true; }
        Check(blocked, "fixture did not deny directory enumeration");
        await run();
    }
    finally
    {
        denied.RemoveAccessRuleSpecific(rule);
        dir.SetAccessControl(denied);
    }
}

static void Junction(string link, string target)
{
    var start = new ProcessStartInfo("cmd.exe") { RedirectStandardOutput = true, RedirectStandardError = true };
    foreach (var arg in new[] { "/c", "mklink", "/J", link, target }) start.ArgumentList.Add(arg);
    using var process = Process.Start(start)!;
    process.WaitForExit();
    Check(process.ExitCode == 0, "junction fixture failed: " + process.StandardError.ReadToEnd());
}

sealed class Immediate<T>(Action<T> action) : IProgress<T>
{
    public void Report(T value) => action(value);
}

// Matches the engine's row DTO without bringing in the GUI's WPF brush properties.
namespace Bunshin.Gui
{
    public sealed class VerifyRow
    {
        public required string Job { get; init; }
        public required string File { get; init; }
        public required string Status { get; init; }
        public required string Source { get; init; }
        public required string Destination { get; init; }
        public string Size { get; init; } = "";
    }
}
