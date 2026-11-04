# Bunshin showcase

The console recording runs real commands against a temporary test tree. The
desktop demo arguments drive the real copy engine and capture the WPF window;
they supplement, rather than replace, interaction tests.

## Scenarios worth showing

1. **Copy and verify:** a folder lands under its own name, empty directories and
   Unicode names survive, and every file receives a SHA-256 verdict.
2. **Same-size corruption:** change a destination file's contents while preserving
   its size and timestamp. The copy phase skips it, but hashing reports a mismatch.
3. **Verify only:** re-check an existing copy without writing files or creating a
   missing destination.
4. **Mirror confirmation:** an unattended CLI mirror refuses to delete unless
   `-Force` is supplied. The desktop app asks for confirmation before it runs.
5. **Cancellation:** stop an in-flight copy and inspect the destination and logs.

## Console recording

```powershell
pwsh -NoProfile -File demo\Record-Demo.ps1
asciinema play demo\bunshin-demo.cast
```

Generated console casts and historical prototype screenshots are kept local.
Current public screenshots are under `docs/images`; the 25-second product tour
and editable composition are under `demo/brag-output`.

## Desktop demo captures

Build first, then use a disposable source and destination:

```powershell
dotnet build gui\Bunshin.Gui.csproj
gui\bin\Debug\net10.0-windows\Bunshin.exe --demo <src> <dest> --shot <output.png>
```

Additional arguments: `--corrupt`, `--mirror`, `--cancel-after <milliseconds>`.
The demo modifies its destination (including deliberate corruption when asked).
Use only scratch data. Always supply `--shot` for an unattended run so the
window exits when the capture is complete.

Current Bunshin screenshots and executed interaction checks are linked from
`HANDOFF.md`.
