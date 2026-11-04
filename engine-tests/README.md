# Bunshin engine regression harness

Run on Windows with the .NET 10 SDK, from the project root:

```powershell
dotnet run --project engine-tests/EngineTests.csproj
```

No test framework, third-party packages, WPF startup, or installation is needed.
The executable links the production `gui/CopyEngine.cs`; its small `VerifyRow`
DTO omits only the shell's WPF brush property. All checks call public engine APIs.
Exit code 0 means every scenario passed; any failure returns 1.

Fixtures use unique temporary directories, Windows directory ACLs and local
junctions (Windows `cmd /c mklink /J`). They restore their ACLs, remove junctions,
and delete their temporary trees. Large-file cancellation creates two 1 GiB
logical files; allow sufficient temporary disk space. Normal engine logs remain
under `%LOCALAPPDATA%\bunshin\logs` for inspection.

Coverage includes missing/denied sources, overlap and self-copy, junction
aliases, copy/publish/directory failures, mirror inventory failures and source
disappearance, cancellation during overwrite/scanning/verification, Explorer
target mapping, directory timestamps, size+mtime skips, same-size corruption,
long Unicode paths, and drive-root/extended-UNC path formatting.

`CopyAsync` and `VerifyAsync` retain their signatures. Preflight/scan failures
fault the task instead of returning a successful empty job. Scan cancellation
throws `OperationCanceledException`; cancellation during the transfer returns
`CopyResult.Cancelled`. `CountFiles` remains a best-effort UI estimate returning
0 on scan failure and must not be used as proof of a successful scan. Its new
`CountFiles(string, CancellationToken)` overload checks traversal cancellation
and throws `OperationCanceledException`; the original overload still works.
Verification requires an existing target directory even for an empty source,
and rejects target reparse ancestors, including those on individual file paths.

UNC formatting is tested without connecting to a share. Actual SMB copy,
power-loss durability, concurrent filesystem mutation and alternate drive/share
aliases still require separate validation. Source directory junction children
remain excluded; root or destination paths through reparse points are rejected.
