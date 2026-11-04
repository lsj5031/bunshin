# Open-source readiness

Prepared for the 0.1.0-preview.3 source repository. This is a release checklist,
not a security audit or a claim that every filesystem configuration is safe.

## Closed gaps

- MIT license for original code; contributor licensing policy.
- Separate notices for OFL fonts, .NET runtime, and demo-only GSAP/audio.
- Portable builder bundles exact restored runtime notices, project license,
  user guide, screenshots and demo. It does not bundle internal handoff reports.
- User-focused README with real screenshots and a 25-second GIF linked to MP4.
- Public screenshots recaptured using disposable sample paths; historical
  machine-local captures, handoff files, build output and scratch files excluded.
- Contribution guide, bug template, PR template and private security-report route.
- Windows CI with read-only repository token, no persisted checkout credentials,
  pinned action revisions, a timeout and Dependabot action updates.
- Build/CLI/engine/model checks documented. GUI acceptance needs a real Windows
  desktop; CI does not pretend that a headless build verifies the UI.

## Before switching repository visibility

1. Confirm CI is green on the intended commit and its portable artifact exists.
2. Review the repository name/branding and MIT license choice as owner.
3. Confirm GitHub private vulnerability reporting is available; SECURITY.md also
   supplies an email fallback. Configure branch protection/required CI to suit
   the account plan and maintainer workflow.
4. Decide whether to distribute an unsigned preview or arrange Windows signing.
   Signing is not set up by this preparation.
5. Publish a tagged release with the portable ZIP, checksum and clear preview
   notes when ready. Update the README download entry from CI artifacts to that
   release. No public release or visibility change is performed automatically.

## Known product limits

Network shares, alternate physical path aliases, concurrent filesystem changes,
power loss and screen-reader/high-contrast variants need broader coverage.
See the user guide and QA reports. Bunshin remains preview software and does
not replace a separate backup.

The optional video renderer uses GSAP under its own Standard License; this is
not part of the MIT application or needed to build/run it. The soundtrack is
CC BY 4.0, not MIT. Preserve attribution when redistributing the video.
