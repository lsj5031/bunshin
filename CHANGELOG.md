# Changelog

## 0.1.0-preview.3 — 2026-11-05

- Integrated branded header replaces the standard Windows title bar while
  retaining native dragging, double-click maximize, edge resizing and safe close.
- Rounded window corners and slim scrollbars with hover/drag feedback, page
  clicks, wheel and keyboard scrolling; removed duplicate Queued detail text.
- Rounded text fields and flat file-table headers using the app's typography,
  palette and focus treatment; column sorting and resize handles retained.
- Matching branded error and confirmation dialogs, with explicit destructive
  actions and safe Cancel defaults. Windows file/folder pickers remain native.
- Wrapped resolved targets, full inline errors for failures without file results,
  and additional scroll space around keyboard-focused actions.
- Twin-sheet Bunshin logo in the header, executable, taskbar and Send To shortcut.
- Reusable SVG, transparent PNG and multi-resolution Windows icon in the bundle.

## 0.1.0-preview.2 — 2026-11-05

- Quiet precision desktop redesign: light surfaces, source-to-target mapping,
  explicit operation modes, and separate copy, verification and result phases.
- Prominent verification outcomes with expandable file details and activity log.
- Readable hover, pressed and keyboard focus states, with restrained motion that
  respects Windows animation settings.
- Offline Bricolage Grotesque, Space Grotesk and IBM Plex Mono fonts; their SIL OFL
  licenses and provenance are included in the portable package.
- Copy/mirror preflight, cancellation cleanup and durable audit safeguards retained.

## 0.1.0-preview.1 — 2026-11-05

First Bunshin preview, evolved from the local `vcopy` prototype.

- Bunshin branding across the desktop app, CLI, Explorer shortcut and logs.
- Portable Windows x64 build script, bundled CLI and SHA-256 release checksum.
- Copy and verify queue, per-file SHA-256 verdicts, verify-only mode and per-job logs.
- Safety hardening and regression coverage for copy and mirror operations.
- Desktop confirmation and cancellation improvements.

This preview is unsigned and not yet published. See `HANDOFF.md` for executed
checks and remaining release gaps.
