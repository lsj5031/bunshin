# Bunshin CLI and Explorer validation

Validated locally on Windows 11 (build 22631), 2026-11-05.

| Host | `test.ps1` | `qa/Run-Stories.ps1` |
| --- | --- | --- |
| Windows PowerShell 5.1.22621.6133 | 20 sections, 62 assertions, 0 failures | 23/23 passed |
| PowerShell 7.6.9 | 20 sections, 62 assertions, 0 failures | 23/23 passed |

Both QA runs used the default invocation and wrote existing feature rows through
the QA runner. No manual feature-sheet edits were made by this CLI task. S01 and
S02 now have sandbox installation evidence. The interactive folder picker and
Explorer selection flow (S03) remain unautomated.

The first GitHub CI run exposed two log assertions comparing an 8.3 TEMP alias
against robocopy's expanded source paths. Both sources were present in the log.
Reproduced locally with a real short-path TEMP directory, then corrected the
expected paths using filesystem-expanded names. The same alias assumption in
the shortcut story was corrected to match the installer's expanded script root.
No CLI or installer behavior changed.

## Changes and CLI contract

- Renamed `vcopy.ps1` to `bunshin.ps1` and `SendTo-VerifiedCopy.ps1` to
  `SendTo-Bunshin.ps1`; no old-name compatibility shims remain.
- Installer creates `Bunshin.lnk`. `-SendToDirectory <path>` overrides the real
  SendTo folder for both install and uninstall. Successful installation explicitly
  returns 0, matching uninstall.
- Existing CLI flags and verification opt-in are preserved. Explorer still passes
  `-Verify`. Default logs are under `%LOCALAPPDATA%\bunshin\logs` with lowercase
  `bunshin-` filenames. All source copy logs and verification verdicts are retained
  in the run log rather than overwriting earlier sources.
- Source/target overlap (including cross-source overlap), reparse ancestors,
  destination reparse entries in copy trees, single-file mirrors, and overlapping
  mirror targets are refused with terminating errors (process exit 1).
- Every mirror source must enumerate successfully before the first copy starts.
  Mirror progress scans also fail closed. Other copy progress scans remain best
  effort; robocopy still reports transfer failures as exit 1.
- Verification skips source reparse entries to match `/XJ`, refuses destination
  reparse traversal, logs enumeration/read failures, and exits 2 for those failures
  or missing destination trees, including empty source trees. Missing source roots
  continue to throw rather than verifying an empty set successfully. Exit 3 remains
  the unattended/declined mirror guard; Move plus verification remains refused.
- Test and QA scripts retain UTF-8 BOMs for Windows PowerShell Unicode parsing.
  QA initializes script-relative default paths in its body for the PS5.1 `-File`
  entry point and creates its long-path fixture through .NET extended paths.

## Safety regression evidence

An ACL-denied subtree in source 2 of a two-source mirror reproduced deletion of
root extras in both destination trees before the mirror preflight fix. The new
regression initially failed three assertions. After the fix, both hosts refuse
the mirror before invoking robocopy and preserve extras in source 1's target,
source 2's target, and the blocked subtree's target. The temporary ACL is restored
in `finally`.

Other regressions cover same/child/ancestor overlap, single-file self-move,
same-leaf mirror collisions, contents-only collisions, all-source validation,
junction exclusion, destination junction refusal, locked source files, denied
directory enumeration, missing empty targets, opt-in verification, and combined
log retention.

The coordinating thread also reproduced an extended-path bypass: a queued source
spelled with `\\?\` was overwritten by the previous job before self-copy failed.
Canonicalization now removes extended local/UNC prefixes before full-path and
overlap checks. Section 20 tests both extended source and extended destination
spellings, asserting the queued source's original bytes are preserved. Both
PowerShell hosts pass all 20 sections after this fix.

Installer stories copy the actual scripts to a portable bundle directory with
spaces, install into a separate SendTo directory with spaces, inspect the `.lnk`
target/quoted arguments/working directory, execute its actual PowerShell command
with no selection, run the bundled core with spaced paths, and uninstall twice
while preserving an unrelated shortcut. The real SendTo directory listing was
unchanged across the validation. No real-profile installation, registry writes,
publication, or commits were performed.

## Evidence and limits

Full local outputs are retained in `.amp/in/artifacts/`: `cli-ps51.txt`,
`cli-pwsh.txt`, `stories-ps51.txt`, `stories-pwsh.txt`, host-specific story CSVs,
and `mirror-before.txt`. `qa/results.csv` contains the latest canonical story
results; the coordinating thread also reran both default host invocations.

- Local long paths exceeding 260 characters pass on both hosts on this machine.
  UNC/SMB paths and long UNC paths remain untested; extended UNC prefix formatting
  is corrected, but this is not network validation.
- Safety checks are preflight checks, not a filesystem snapshot or protection
  against concurrent changes. Alternate volume mappings and 8.3 aliases are not
  validated by this suite.
- Robocopy summary parsing still assumes English output; Ctrl+C reporting remains
  a limitation. No ACL/owner preservation or resume support was added.
- The no-selection shortcut command is exercised; actual Explorer UI selection,
  folder picker cancellation, and a verified copy through the picker are not.
