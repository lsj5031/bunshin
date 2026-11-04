# Bunshin redesign GUI acceptance

## Preview.3 — branded chrome and scrollbar polish

The coordinating thread ran the strict GUI suite against the final
self-contained preview.3 candidate: **178 assertions passed, exit 0**. Executable
SHA-256: `807db0bdee58ea9afc8cda94361865f4fc7da13f9eea0d4e7b03167b2e7dce2c`.

An additional temporary live probe passed **23 assertions**: Windows accepted
the rounded-corner preference, minimize/maximize/restore/close worked, caption
double-click maximized, native drag/resize hit tests were retained, minimum-size
Tab/scroll worked at actual 200% DPI, custom vertical thumb dragging, track page
clicks and mouse wheel scrolling changed content, horizontal log-thumb dragging
exposed long lines, real copy/verify succeeded, and View log retained focus.
Rounded text fields retained keyboard select-all/deletion. Flat column headers
sorted both directions and retained drag resizing. Escape and dialog close
cancelled mirror without destination writes. Error and confirmation dialogs
share the crisp vector brand and rounded control treatment. Missing-source
errors now show the full wrapped cause beside the outcome, keep the empty file
table closed and focus View log. Resolved outputs wrap to preserve the leaf;
minimum-size keyboard focus includes clearance below the action's focus ring.
The logo's alpha channel spans 0–255; light/dark composites were inspected for
halos. The multi-size ICO is embedded in the executable and reused by Send To.

Local-only evidence archive: `bunshin-v3-reviewed.log`,
`bunshin-v3-reviewed-chrome.log`, and `bunshin-v3-reviewed\` screenshots. Actual screen
captures 15–20 show rounded corners, dialogs and custom scrollbars; captures 01–13 cover
the full regression states. An earlier candidate run failed minimum-size Tab
reachability; a focused reproduction and the final unchanged suite both passed.
No cause for that earlier intermittent failure was established.

The same preview.2 coverage limits below still apply. No OS settings or real
profile shortcuts were changed. Font assets and the copy engine are unchanged.

## Previous preview.2 acceptance

**Passed: 175 assertions, exit 0**, Windows PowerShell 5.1 STA on Windows 11 build 22631, 2026-11-05 (Pacific/Auckland). Tested the delivered self-contained executable at `dist\candidate-preview.2-r2\Bunshin.exe`, SHA-256 `982036f365157d35f2ba1b551a0365f5c98452e03bb33a205e729df894cb3ac9`. Final run retained every strict assertion with no workaround. Parent owns final ZIP identity/packaging smoke.

Desktop was handed over explicitly by the GUI owner before automation. No global Windows settings were changed. No Bunshin test process remains running.

## Exercised executable acceptance

- Exclusive Copy & verify / Verify only / Mirror selection and mode-specific start labels; startup action availability.
- Cross-job equal output/source with regular, extended, dot-segment, extended dot-segment and mixed-case/trailing-separator paths in all three modes (15 rejected plans).
- Cross-job output containing another source folder, output inside another source folder, and output containing another source file, using extended paths in all three modes (9 rejected plans). Rejected plans preserve destination snapshots and start neither jobs nor audit logs.
- Drive-root rejection, duplicate source handling, native file/folder pickers, selected-item removal and clear-finished behavior.
- Overlapping mirror destinations and single-file mirror refusal; actual target in destructive confirmation; default No keyboard focus and Enter cancellation; approved mirror deletes only intended extras and preserves copied bytes and empty folders.
- Folder and individual-file resolved output paths before starting.
- Verified, mismatch, active hashing and stopped headlines; automatic mismatch detail disclosure; View log expansion and keyboard focus; selected-job and merged activity logs.
- Actual Open destination invocation opens the completed run destination in Explorer. Only the Explorer window created by this test is closed.
- After success, a distinct Unicode file is added without clearing: headline becomes Ready to check every file, progress becomes zero, original folder remains Verified, two previous per-file results and exact activity log content remain. Clearing destination changes headline to Choose where it goes and disables start. Screenshot confirms neutral heading and phase styling.
- Verify-only missing-destination refusal and same-size mismatch detection, with unchanged destination names, hashes and write times.
- Busy mutation locks across every source/destination/mode control; cancellation while hashing a 1 GB file preserves the complete copied file (independent source/destination hashes match). Cancel and busy close using a 4 GB fixture persist Cancelled audit results before exit. Close defaults to No; Enter declines and keeps the app open.
- Source disappearing after queueing shows This run needs attention and persists an incomplete verification record, distinct from a byte mismatch.
- At minimum 760×640 DIPs, Tab navigation from destination reaches the primary action and scrolls it fully inside the window/work area. Actual display scaling was **200%**, work area **3840×2064 physical pixels**. Original window bounds were restored.

## Defect found and retested

Candidate r1 (`0780fd68f9d0969ce4b7017a6e3e44a5b87b170921a337ff0dd99dd9c7df0c84`) expanded Activity log but left keyboard focus on ViewLogButton. A separate normal-copy probe confirmed LogBox was visible and keyboard-focusable but not focused; the strict suite timed out after 15 seconds. GUI owner changed source to defer focus until layout. **The same strict HasKeyboardFocus assertion passed in r2.**

An r1 diagnostic continuation manually focused the log solely to collect further cases; it is not a passing acceptance run. It also exposed a test issue reading ResultsCount while File details was collapsed. The suite now opens the disclosure before checking retained rows. The final r2 run includes both assertions unchanged thereafter.

## Fonts, screenshots and limits

WPF `GlyphTypeface` opened all six source TTFs successfully. Internal names match XAML: Bricolage Grotesque (Medium, SemiBold), Space Grotesk (Regular, Medium, SemiBold), IBM Plex Mono (Regular). This validates source font metadata only; it does not establish embedded resource resolution or displayed glyph selection.

Additionally instantiated the final Release WPF window without showing it and resolved actual control typefaces: window → Space Grotesk Regular, OutcomeTitle → Bricolage Grotesque Medium, DestinationBox → IBM Plex Mono Regular. All resolved to `pack://application:,,,/Bunshin;component/Fonts/...` resources rather than a system-font fallback. This was a compiled Release resource check; parent independently byte-compared all six resources embedded in the candidate to source assets.

Local-only evidence archive: `bunshin-v2` (not distributed in this repository).

- `gui-r2.log`: full successful strict run; `gui-acceptance.log`: original focus failure; `gui-continuation.log`: diagnostic-only run.
- Final executable captures: `packaged-screens\01-ready.png` through `13-new-plan-after-verified.png`. `14-log-focus-probe.png` deliberately retains r1 failure evidence and is not a final UI screenshot.
- Inspected actual ready, verified, mismatch, verifying, cancelled, mirror/close confirmation, missing-source, activity-log, minimum-keyboard and new-plan captures. Light hierarchy, persistent verdicts and phase distinctions are clear. Some long queue paths intentionally ellipsize (full paths are available through tooltip/details); expanded diagnostics may require outer scrolling at reduced height. The minimum-size primary-action capture is fully visible and focused. Native dialogs extend beyond their owner but are fully captured and readable.

Limits: 150% scaling was not exercised; current 200% minimum-size reachability was. No global high-contrast or animation-setting changes were made, so theme changes and enabled-animation timing are not certified by this pass. GUI owner separately reports ClientAreaAnimation=False and pointer hover/pressed identity checks. No screen-reader session or complete accessibility certification was performed.

Parent-reported contrast calculations from actual XAML active text pairs: body 13.90:1, secondary 5.93:1, primary 5.60:1, hover 7.27:1, pressed 9.72:1, success 5.59:1, failure 5.92:1. These are color-pair calculations, not blanket accessibility certification. Parent also reports 18 engine scenarios, CLI regression suites (20 sections / 62 assertions on each host), 23 QA stories per host, and model/mutation coverage; this GUI task did not rerun those suites.

Only `gui-interaction.tests.ps1` and this report were changed by this acceptance task. Source fixes were made by their owner. No commits, pushes or profile installation were performed.
