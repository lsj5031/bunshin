# Bunshin

**Copy. Verify. Be sure.**

Bunshin is a Windows file-copy utility with SHA-256 verification. Queue files
and folders in the desktop app, choose a destination, and see a verdict for
each file. The command-line tool also lets you check an existing copy without
copying it again.

This is unsigned **0.1.0**. Local disk workflows are tested; network
shares and unusual filesystem configurations still need broader testing.

## Start here

Extract the portable Windows x64 ZIP into a permanent folder and open
`Bunshin.exe`. No administrator privileges or separately installed .NET runtime
are required for the portable build. Windows may show a warning for the
unsigned executable; verify the download's SHA-256 against its `.sha256` file.

```powershell
Get-FileHash .\bunshin-0.1.0-win-x64.zip -Algorithm SHA256
```

1. Drop files or folders into the queue, or use **Add files** / **Add folder**.
2. Choose the destination folder and review the resolved target for each source.
3. Choose **Copy and verify**, **Verify only**, or **Mirror and verify**.
4. Start the operation. Copying and verification are separate phases; wait for
   the final verification verdict before relying on the destination.

The light desktop interface keeps the transfer and outcome in view. Expand
**File details** for individual verification results and source/destination
paths, or **Activity log** for diagnostics. **Stop safely** requests cancellation
and waits for cleanup; stopped work is not reported as fully verified.

The integrated Bunshin header replaces the standard title bar. Drag its empty
area to move the window; double-click to maximize or restore. Window controls,
edge resizing and Alt+F4 remain available. Rounded window edges and slim,
draggable scrollbars match the light interface. The twin-sheet logo appears in the
header, executable/taskbar icon and optional Send To shortcut. Reusable SVG,
transparent PNG and multi-size ICO assets ship in `Branding`.

Errors and confirmations use the same interface. Destructive confirmations
default to **Cancel**; Escape or closing the dialog also cancels the action.
Failures without per-file results show their complete error beside the outcome.

A folder named `Photos` lands at `<destination>\Photos`. Existing files with
matching size and last-write time are skipped during copying, but the subsequent
hash check still checks their contents. A mismatch is reported; it is not
silently repaired. Remove the bad destination file and copy again to repair it.

**Verify only** compares an existing destination with the source without copying.
**Mirror and verify** deletes extra destination files and requires confirmation. Use it only
when the destination is dedicated to that source. Mirror accepts folders only;
queued mirror destinations must be separate trees. The desktop app accepts
folders inside a drive or share, rather than the drive/share root itself.

## Command line

The CLI uses Windows' built-in robocopy and works independently of the desktop
app. Verification is explicit: include `-Verify` when copying important files.

```powershell
.\bunshin.ps1 'D:\Photos' 'E:\Backup' -Verify
.\bunshin.ps1 'D:\Photos' 'E:\Backup' -VerifyOnly
.\bunshin.ps1 'D:\Photos' 'E:\Backup' -ContentsOnly -Verify
.\bunshin.ps1 'D:\Work' 'E:\Mirror' -Mode Mirror -Force -Verify
```

If Windows' execution policy blocks a script, launch that command in a separate
process, without changing the machine's policy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\bunshin.ps1 'D:\Photos' 'E:\Backup' -Verify
```

| Option | Behavior |
| --- | --- |
| `-Path <string[]>`, `-Destination <string>` | Source paths and destination directory; also accepted positionally. |
| `-Verify` | Compare source and destination file contents using SHA-256 after copying. |
| `-VerifyOnly` | Check existing files without copying or creating a destination. |
| `-ContentsOnly` | Merge a source folder's contents directly into the destination. |
| `-Mode Merge\|Mirror\|Move` | Merge is the default. Mirror deletes extras; Move removes source files and cannot be combined with verification. |
| `-Force` | Confirm a destructive mirror operation without a prompt. |
| `-Threads 1..128` | robocopy copy concurrency; default 16. Hashing remains sequential. |
| `-Quiet`, `-LogDirectory <path>` | Suppress normal console output or choose a log directory. |

Exit codes: `0` success, `1` copy failure, `2` verification failure, `3` mirror
confirmation declined or required. Invalid arguments and unsafe paths fail
before copying. An unhandled error in a standalone PowerShell process exits
nonzero.

## Explorer integration (optional)

Run `Install-SendTo.ps1` from the extracted folder to create **Bunshin** in
Explorer's **Send to** menu. This changes only the current user's shortcut
folder; it does not write registry entries. Keep the extracted folder in place
while the shortcut is installed. `Install-SendTo.ps1 -Uninstall` removes it.

The Explorer entry opens a destination picker and runs the CLI with `-Verify`.
It does not replace Explorer's built-in copy handler.

## Logs and boundaries

Logs are stored under `%LOCALAPPDATA%\bunshin\logs`. The desktop app shows
separate job log lanes and per-file verification results. Earlier prototype logs
under `%LOCALAPPDATA%\vcopy\logs` are retained and are not migrated automatically.

- Verification checks file contents at the time they are read. Close applications
  that are changing the source; Bunshin does not create filesystem snapshots.
- This is a copy utility, not a versioned backup system. It does not provide
  history, resumable transfer, ACL/owner preservation, or recovery from a failed drive.
- Reparse-point directories are excluded to avoid traversing junctions.
- Overlapping source/output paths and destination reparse-point aliases are
  refused. Avoid paths that refer to the same physical location through different
  mapped drives or share names; those aliases are not resolved by the checks.
- The desktop app stages replacement files beside their destinations, so a
  cancelled or failed overwrite keeps the previous file. Allow room for both
  copies during replacement. Force-killing the app can leave a staging file.
- GUI copying is sequential; the CLI supports robocopy's multithreaded copying.
- Localized robocopy summaries and clean CLI Ctrl+C reporting remain limitations.
- Long paths have local test coverage. SMB/UNC destinations still need testing
  against real network shares.

## Build and verify

Development requires Windows and the .NET 10 SDK; the CLI requires Windows
PowerShell 5.1 or PowerShell 7. Python is only needed for the model checker and
the optional feature dashboard server.

```powershell
dotnet run --project gui\Bunshin.Gui.csproj
pwsh -NoProfile -File test.ps1
pwsh -NoProfile -File qa\Run-Stories.ps1
dotnet run --project engine-tests
python spec\check_model.py
python spec\check_model.py --mutate
.\Publish-Portable.ps1
```

`Publish-Portable.ps1` builds a self-contained `win-x64` app and bundles the CLI,
Explorer scripts, release metadata and this documentation into `dist\`, with a
SHA-256 checksum alongside the ZIP. It does not sign, install, upload, or publish
the release, and refuses to overwrite an existing version.

The optional engineering dashboard (`dashboard\serve.ps1`) displays
`features.csv`. Current verification coverage and limits are recorded under
`qa\`. The Python state checker checks a bounded protocol model, not the
compiled app or the TLA+ file itself.

The Windows CI workflow runs the CLI on both PowerShell hosts, the copy engine
regressions and the protocol checker, then builds a portable artifact. The real
desktop interaction suite requires an interactive Windows session:

```powershell
powershell.exe -NoProfile -STA -File .\gui-interaction.tests.ps1
```

Run the two PowerShell regression suites sequentially: they share a temporary
fixture directory.

## Typography

The desktop bundles Bricolage Grotesque for headings, Space Grotesk for interface
text, and IBM Plex Mono for paths and technical details, following the typography
of [Metic Studio](https://metic.studio/en). Fonts load offline; no system font
installation is needed. All three use the SIL Open Font License 1.1. The portable
ZIP includes their licenses and provenance under `ThirdPartyNotices\Fonts`;
source copies live in `gui\Fonts`.

## Name

分身 (*bunshin*) evokes a double or another self: a copy that matches its
original. Product name: **Bunshin**; command: `bunshin.ps1`.
