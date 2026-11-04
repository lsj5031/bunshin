using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace Bunshin.Gui;

/// <summary>
/// Copies with CopyFileEx so bytes in flight are visible, then re-reads the
/// result with SHA-256. The shell supplies Explorer nesting: a folder lands in
/// dest\folderName, a destination file with the same size and timestamp is
/// skipped the way robocopy skips it, and junctions are not traversed (/XJ).
/// </summary>
public sealed class CopyEngine
{
    private const int MaxAttempts = 3;
    private const int ReportIntervalMs = 100;

    private static readonly EnumerationOptions Scan = new()
    {
        RecurseSubdirectories = true,
        IgnoreInaccessible = false,
        AttributesToSkip = FileAttributes.ReparsePoint
    };

    public static string LongPath(string path)
    {
        var extended = path.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase);
        path = Normalize(path);
        if (path.Length < 240 && !extended) return path;
        return path.StartsWith(@"\\") ? @"\\?\UNC\" + path[2..] : @"\\?\" + path;
    }

    public static string LogDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "bunshin", "logs");

    /// <summary>Source file -> destination file, using the same mapping as the CLI.</summary>
    public static IEnumerable<(string Source, string Dest)> BuildPairs(string source, string target) =>
        BuildPairs(source, target, CancellationToken.None);

    private static IEnumerable<(string Source, string Dest)> BuildPairs(
        string source, string target, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        source = Normalize(source);
        target = Normalize(target);
        RejectReparseAncestors(source);
        if ((File.GetAttributes(LongPath(source)) & FileAttributes.Directory) == 0)
        {
            yield return (source, Path.Combine(target, Path.GetFileName(source)));
            yield break;
        }

        var root = source;
        foreach (var file in Walk(root, token).Files)
            yield return (file, Path.Combine(target, Path.GetRelativePath(root, file)));
    }

    public static long CountFiles(string source) => CountFiles(source, CancellationToken.None);

    public static long CountFiles(string source, CancellationToken token)
    {
        try
        {
            token.ThrowIfCancellationRequested();
            return File.Exists(LongPath(source)) ? 1 : Walk(Normalize(source), token).Files.Count;
        }
        catch (OperationCanceledException) { throw; }
        catch
        {
            return 0;
        }
    }

    public static string FormatSize(long bytes) => bytes switch
    {
        < 1024 => $"{bytes} B",
        < 1024 * 1024 => $"{bytes / 1024.0:0.#} KB",
        < 1024L * 1024 * 1024 => $"{bytes / (1024.0 * 1024):0.#} MB",
        _ => $"{bytes / (1024.0 * 1024 * 1024):0.##} GB"
    };

    /// <summary>
    /// Copies one job. <paramref name="log"/> receives one line per decision;
    /// <paramref name="progress"/> receives a byte snapshot at most every
    /// <see cref="ReportIntervalMs"/> milliseconds, from the copy callback.
    /// </summary>
    public async Task<CopyResult> CopyAsync(
        string source, string target, bool mirror,
        IProgress<string>? log, IProgress<CopyProgress>? progress, CancellationToken token)
    {
        return await Task.Run(() =>
        {
            token.ThrowIfCancellationRequested();
            source = Normalize(source);
            target = Normalize(target);
            RejectReparseAncestors(source);
            RejectReparseAncestors(target);
            var isFile = (File.GetAttributes(LongPath(source)) & FileAttributes.Directory) == 0;
            if (Within(source, target) || (!isFile && Within(target, source)))
                throw new IOException("Source and destination must not overlap.");
            var root = isFile ? Path.GetDirectoryName(source)! : source;

            var dirs = new List<(string Source, string Dest)>();
            var files = new List<(string Source, string Dest, string Rel)>();

            if (isFile)
            {
                files.Add((source, Path.Combine(target, Path.GetFileName(source)), Path.GetFileName(source)));
            }
            else
            {
                var (walkedDirs, walkedFiles) = Walk(root, token);
                foreach (var dir in walkedDirs)
                    dirs.Add((dir, dir == root ? target : Path.Combine(target, Path.GetRelativePath(root, dir))));
                foreach (var file in walkedFiles)
                {
                    var rel = Path.GetRelativePath(root, file);
                    files.Add((file, Path.Combine(target, rel), rel));
                }
            }

            long totalBytes = 0;
            foreach (var (src, _, _) in files)
            {
                token.ThrowIfCancellationRequested();
                totalBytes += new FileInfo(LongPath(src)).Length;
            }

            // Refuse destination aliases before creating anything or skipping a file.
            foreach (var (_, dest) in dirs) { token.ThrowIfCancellationRequested(); RejectReparseAncestors(dest); }
            foreach (var (_, dest, _) in files) { token.ThrowIfCancellationRequested(); RejectReparseAncestors(dest); }

            var logPath = Path.Combine(LogDirectory,
                $"gui-{DateTime.Now:yyyyMMdd-HHmmss-fff}-{Environment.ProcessId}-{Guid.NewGuid():N}.log");
            var text = new StringBuilder();

            void Emit(string line)
            {
                lock (text) text.AppendLine(line);
                log?.Report(line);
            }

            Emit($"Bunshin GUI  {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
            Emit($"source : {source}");
            Emit($"dest   : {target}");
            Emit($"mode   : {(mirror ? "mirror" : "merge")}");
            Emit($"files  : {files.Count} ({FormatSize(totalBytes)})");
            Emit("");

            long doneBytes = 0;
            int copied = 0, skipped = 0, failed = 0, deleted = 0;
            var cancelled = false;
            var clock = Stopwatch.StartNew();

            void Report(string current) => progress?.Report(new CopyProgress(
                doneBytes, totalBytes, copied + skipped + failed, files.Count, current,
                clock.Elapsed.TotalSeconds > 0.2 ? doneBytes / clock.Elapsed.TotalSeconds : 0));

            // Declared inside the loop on purpose: the callback must stay alive
            // for exactly one CopyFileEx call.
            void CopyOne(string src, string dst, string rel, long offset, int finishedFiles)
            {
                long last = 0;

                CopyProgressResult Routine(
                    long fileSize, long transferred,
                    long streamSize, long streamTransferred,
                    uint streamNumber, CopyProgressCallbackReason reason,
                    IntPtr hSource, IntPtr hDestination, IntPtr data)
                {
                    if (token.IsCancellationRequested) return CopyProgressResult.Cancel;

                    var now = Stopwatch.GetTimestamp();
                    if (reason == CopyProgressCallbackReason.ChunkFinished &&
                        now - last < Stopwatch.Frequency * ReportIntervalMs / 1000)
                        return CopyProgressResult.Continue;
                    last = now;

                    var elapsed = clock.Elapsed.TotalSeconds;
                    progress?.Report(new CopyProgress(
                        offset + transferred, totalBytes, finishedFiles, files.Count, rel,
                        elapsed > 0.2 ? (offset + transferred) / elapsed : 0));
                    return CopyProgressResult.Continue;
                }

                // CopyFileEx CANCEL deletes its output, even when it overwrote a
                // previously valid file. Only publish a complete sibling copy.
                var temporary = Path.Combine(Path.GetDirectoryName(dst)!, $".bunshin-{Guid.NewGuid():N}.tmp");
                try
                {
                    token.ThrowIfCancellationRequested();
                    RejectReparseAncestors(dst);
                    var cancel = 0;
                    if (!CopyFileEx(LongPath(src), LongPath(temporary), Routine, IntPtr.Zero, ref cancel, 1))
                    {
                        var code = Marshal.GetLastWin32Error();
                        token.ThrowIfCancellationRequested();
                        throw new IOException(new Win32Exception(code).Message, code);
                    }
                    token.ThrowIfCancellationRequested();
                    File.Move(LongPath(temporary), LongPath(dst), overwrite: true);
                }
                finally
                {
                    // CopyFileEx may preserve the source's read-only attribute.
                    if (File.Exists(LongPath(temporary)))
                    {
                        File.SetAttributes(LongPath(temporary), FileAttributes.Normal);
                        File.Delete(LongPath(temporary));
                    }
                }
            }

            try
            {
                token.ThrowIfCancellationRequested();
                Directory.CreateDirectory(LongPath(target));
                foreach (var (_, dest) in dirs)
                {
                    token.ThrowIfCancellationRequested();
                    try { Directory.CreateDirectory(LongPath(dest)); }
                    catch (Exception ex) { failed++; Emit($"FAIL   {dest}: {ex.Message}"); }
                }

                Report("");

                foreach (var (src, dst, rel) in files)
                {
                    token.ThrowIfCancellationRequested();

                    FileInfo info;
                    try
                    {
                        info = new FileInfo(LongPath(src));
                        _ = info.Length; // FileInfo is lazy; missing files must fail here.
                    }
                    catch (Exception ex)
                    {
                        failed++;
                        Emit($"FAIL   {rel}: {ex.Message}");
                        continue;
                    }

                    if (IsUnchanged(dst, info))
                    {
                        skipped++;
                        doneBytes += info.Length;
                        Emit($"same   {rel}");
                        Report(rel);
                        continue;
                    }

                    var ok = false;
                    for (var attempt = 1; attempt <= MaxAttempts && !ok; attempt++)
                    {
                        try
                        {
                            CopyOne(src, dst, rel, doneBytes, copied + skipped + failed);
                            ok = true;
                        }
                        catch (OperationCanceledException) { throw; }
                        catch (Exception ex)
                        {
                            if (attempt == MaxAttempts)
                            {
                                failed++;
                                Emit($"FAIL   {rel}: {ex.Message}");
                            }
                            else
                            {
                                Emit($"retry  {rel}: {ex.Message}");
                                if (token.WaitHandle.WaitOne(400 * attempt)) token.ThrowIfCancellationRequested();
                            }
                        }
                    }

                    if (!ok) continue;

                    copied++;
                    doneBytes += info.Length;
                    Emit($"copy   {rel}  {FormatSize(info.Length)}");
                    Report(rel);
                }

                token.ThrowIfCancellationRequested();
                if (mirror && failed != 0) Emit("mirror : skipped because the copy was incomplete");
                if (mirror && failed == 0)
                {
                    // A disappearing/unreadable source after the initial scan is
                    // not authority to delete destination data either.
                    if (isFile)
                        _ = File.GetAttributes(LongPath(source));
                    else
                    {
                        var current = Walk(root, token);
                        if (!new HashSet<string>(current.Dirs, StringComparer.OrdinalIgnoreCase)
                                .SetEquals(dirs.Select(d => d.Source)) ||
                            !new HashSet<string>(current.Files, StringComparer.OrdinalIgnoreCase)
                                .SetEquals(files.Select(f => f.Source)))
                            throw new IOException("Source inventory changed; mirror deletion was skipped.");
                    }
                    var expectedFiles = new HashSet<string>(files.Select(f => f.Dest), StringComparer.OrdinalIgnoreCase);
                    var expectedDirs = new HashSet<string>(dirs.Select(d => d.Dest), StringComparer.OrdinalIgnoreCase) { target };

                    // Complete both inventories before deleting anything. An
                    // inaccessible destination must not result in a partial prune.
                    var extras = new List<string>();
                    var leftovers = new List<string>();
                    foreach (var file in Directory.EnumerateFiles(LongPath(target), "*", Scan))
                    {
                        token.ThrowIfCancellationRequested();
                        extras.Add(file);
                    }
                    foreach (var dir in Directory.EnumerateDirectories(LongPath(target), "*", Scan))
                    {
                        token.ThrowIfCancellationRequested();
                        leftovers.Add(dir);
                    }

                    foreach (var extra in extras.Select(Unlong))
                    {
                        token.ThrowIfCancellationRequested();
                        if (expectedFiles.Contains(extra)) continue;
                        try
                        {
                            File.Delete(LongPath(extra));
                            deleted++;
                            Emit($"delete {Path.GetRelativePath(target, extra)}");
                        }
                        catch (Exception ex)
                        {
                            failed++;
                            Emit($"FAIL   delete {extra}: {ex.Message}");
                        }
                    }

                    foreach (var dir in leftovers.Select(Unlong)
                                 .Where(d => !expectedDirs.Contains(d))
                                 .OrderByDescending(d => d.Length))
                    {
                        token.ThrowIfCancellationRequested();
                        try
                        {
                            if (!Directory.EnumerateFileSystemEntries(LongPath(dir)).Any())
                            {
                                Directory.Delete(LongPath(dir));
                                Emit($"rmdir  {Path.GetRelativePath(target, dir)}");
                            }
                        }
                        catch (Exception ex) { failed++; Emit($"FAIL   rmdir {dir}: {ex.Message}"); }
                    }
                }

                // CopyFileEx carries file timestamps only; robocopy /DCOPY:DAT also did directories.
                foreach (var (srcDir, dstDir) in dirs.OrderByDescending(d => d.Dest.Length))
                {
                    token.ThrowIfCancellationRequested();
                    try { Directory.SetLastWriteTimeUtc(LongPath(dstDir), Directory.GetLastWriteTimeUtc(LongPath(srcDir))); }
                    catch { /* best effort */ }
                }
            }
            catch (OperationCanceledException)
            {
                cancelled = true;
                Emit("cancelled");
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                failed++;
                Emit($"FAIL   {ex.Message}");
            }
            finally
            {
                clock.Stop();
                Emit("");
                Emit($"copy   : {copied} copied, {skipped} same, {failed} failed, {deleted} deleted");
                Emit($"time   : {clock.Elapsed:mm\\:ss}");

                Directory.CreateDirectory(LogDirectory);
                string snapshot;
                lock (text) snapshot = text.ToString();
                File.WriteAllText(logPath, snapshot, new UTF8Encoding(false));
            }

            var exit = cancelled ? -1 : failed == 0 ? 0 : 1;
            return new CopyResult(exit, cancelled, logPath, copied, skipped, failed);
        }, CancellationToken.None);
    }

    public async Task<VerifyResult> VerifyAsync(
        string source, string target, string jobLabel,
        IProgress<VerifyRow>? rows, CancellationToken token)
    {
        source = Normalize(source);
        target = Normalize(target);
        return await Task.Run(() =>
        {
            token.ThrowIfCancellationRequested();
            RejectReparseAncestors(target);
            if ((File.GetAttributes(LongPath(target)) & FileAttributes.Directory) == 0)
                throw new IOException("Verification target must be an existing directory.");
            var checkedCount = 0;
            var failed = 0;

            foreach (var (src, dest) in BuildPairs(source, target, token))
            {
                token.ThrowIfCancellationRequested();
                checkedCount++;

                string status;
                var size = "";
                try
                {
                    RejectReparseAncestors(dest);
                    if (!File.Exists(LongPath(dest)))
                    {
                        status = "Missing";
                    }
                    else
                    {
                        size = FormatSize(new FileInfo(LongPath(src)).Length);
                        status = string.Equals(Hash(src, token), Hash(dest, token), StringComparison.Ordinal)
                            ? "OK"
                            : "Mismatch";
                    }
                }
                catch (OperationCanceledException) { throw; }
                catch (Exception ex)
                {
                    status = "Error: " + ex.Message;
                }

                if (status != "OK") failed++;

                rows?.Report(new VerifyRow
                {
                    Job = jobLabel,
                    File = Path.GetRelativePath(
                        Path.GetDirectoryName(source) ?? source,
                        src),
                    Status = status,
                    Size = size,
                    Source = src,
                    Destination = dest
                });
            }

            token.ThrowIfCancellationRequested();
            return new VerifyResult(checkedCount, failed);
        }, token);
    }

    private static bool IsUnchanged(string dest, FileInfo source)
    {
        try
        {
            if (!File.Exists(LongPath(dest))) return false;
            var copy = new FileInfo(LongPath(dest));
            return copy.Length == source.Length && copy.LastWriteTimeUtc == source.LastWriteTimeUtc;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>One pass over a tree: directories to create, files to copy. Junctions are skipped.</summary>
    private static (List<string> Dirs, List<string> Files) Walk(string root, CancellationToken token = default)
    {
        var dirs = new List<string>();
        var files = new List<string>();
        var pending = new Stack<string>();
        pending.Push(root);

        while (pending.Count > 0)
        {
            token.ThrowIfCancellationRequested();
            var dir = pending.Pop();
            dirs.Add(dir);
            foreach (var file in Directory.EnumerateFiles(LongPath(dir)))
            {
                token.ThrowIfCancellationRequested();
                if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException($"Reparse-point source file is not supported: {file}");
                files.Add(Unlong(file));
            }

            foreach (var sub in Directory.EnumerateDirectories(LongPath(dir)))
            {
                token.ThrowIfCancellationRequested();
                var clean = Unlong(sub);
                if ((File.GetAttributes(LongPath(clean)) & FileAttributes.ReparsePoint) != 0) continue;
                pending.Push(clean);
            }
        }

        return (dirs, files);
    }

    public static string Normalize(string path) =>
        Path.TrimEndingDirectorySeparator(Path.GetFullPath(Unlong(path)));

    private static string Unlong(string path) =>
        path.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase) ? @"\\" + path[8..] :
        path.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase) ? path[4..] : path;

    private static bool Within(string path, string root) =>
        path.Equals(root, StringComparison.OrdinalIgnoreCase) ||
        path.StartsWith(Path.EndsInDirectorySeparator(root) ? root : root + Path.DirectorySeparatorChar,
            StringComparison.OrdinalIgnoreCase);

    private static void RejectReparseAncestors(string path)
    {
        for (string? current = path; current is not null; current = Path.GetDirectoryName(current))
        {
            FileAttributes attributes;
            try { attributes = File.GetAttributes(LongPath(current)); }
            catch (Exception ex) when (ex is FileNotFoundException or DirectoryNotFoundException) { continue; }
            if ((attributes & FileAttributes.ReparsePoint) != 0)
                throw new IOException($"Reparse-point path is not supported: {current}");
        }
    }

    private static string Hash(string path, CancellationToken token)
    {
        using var stream = File.OpenRead(LongPath(path));
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        var buffer = new byte[128 * 1024];
        while (true)
        {
            token.ThrowIfCancellationRequested();
            var read = stream.Read(buffer);
            if (read == 0) break;
            hash.AppendData(buffer, 0, read);
        }
        return Convert.ToHexString(hash.GetHashAndReset());
    }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    private delegate CopyProgressResult CopyProgressRoutine(
        long totalFileSize, long totalBytesTransferred,
        long streamSize, long streamBytesTransferred,
        uint streamNumber, CopyProgressCallbackReason callbackReason,
        IntPtr sourceFile, IntPtr destinationFile, IntPtr data);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CopyFileExW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CopyFileEx(
        string existingFileName, string newFileName,
        CopyProgressRoutine progressRoutine, IntPtr data,
        ref int cancel, uint flags);

    private enum CopyProgressResult : uint { Continue = 0, Cancel = 1, Stop = 2, Quiet = 3 }

    private enum CopyProgressCallbackReason : uint { ChunkFinished = 0, StreamSwitch = 1 }
}

public readonly record struct CopyProgress(
    long BytesDone, long BytesTotal, int FilesDone, int FilesTotal, string Current, double BytesPerSecond);

public readonly record struct CopyResult(int ExitCode, bool Cancelled, string LogPath, int Copied, int Skipped, int Failed);
public readonly record struct VerifyResult(int Checked, int Failed);
