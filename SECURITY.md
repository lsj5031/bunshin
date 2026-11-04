# Security and data-loss reports

Only the latest preview is maintained. Bunshin is unsigned preview software;
use a separate backup for irreplaceable data and review the documented
[filesystem boundaries](docs/USAGE.md#logs-and-boundaries).

Please report vulnerabilities and reproducible data-loss bugs through
[GitHub's private vulnerability reporting](https://github.com/lsj5031/bunshin/security/advisories/new).
If that option is unavailable, email **lsj5031@gmail.com** with the subject
“Bunshin security report”. Please do not post exploit details or private data
in a public issue before the report has been assessed.

Include the version, Windows build, mode, a minimal disposable reproduction,
expected versus actual behavior, and redacted logs. Never send credentials or
your original personal files. Best effort is made to acknowledge reports within
seven days; there is no guaranteed response or fix deadline.

## Trust boundaries

- Bunshin runs with your Windows account's file permissions. It needs no admin
  rights, runs no background service, and adds no network service or telemetry.
- Mirror intentionally deletes destination extras after confirmation.
- Preflight checks reject common source/output overlaps and reparse-point
  hazards. Physical aliases are not all resolved and concurrent filesystem
  changes are not isolated by a snapshot.
- Logs contain file paths and verification results. Treat them as private data.
- Stop safely allows cleanup; force termination and power loss have no crash
  recovery guarantee.

CI verifies behavior on Windows. That is not a security audit, a certification,
or a guarantee against every filesystem race or storage failure.
