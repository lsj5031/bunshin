#!/usr/bin/env python3
"""
Exhaustive checker for the Bunshin.tla state machine.

TLC (tla2tools.jar) could not be fetched on this machine - both github.com and
repo1.maven.org time out from the shell - so this mirrors the TLA+ spec action
for action and explores the whole reachable state space, which for 2 jobs /
2 files / 2 hashes is exactly what TLC would enumerate.

Run:  python spec/check_model.py
      python spec/check_model.py --mutate

--mutate models "Retry keeps the previous verdicts" and is expected to violate
NoFalseOk, which shows the check is not vacuous.
"""

import itertools
import sys
from collections import deque

FILES = ("f1", "f2")
JOBS = ("j1", "j2")
HASHES = ("h1", "h2")
NULL = None
JOB_FILES = {"j1": ("f1",), "j2": ("f1", "f2")}
TERMINAL = {"done", "failed", "cancelled"}
PHASES = ("queued", "copying", "copied", "verifying", "done", "failed", "cancelled")
NO_VERDICT = "none"


def initial_state(src):
    dst = tuple(tuple(NULL for _ in FILES) for _ in JOBS)
    phase = tuple("queued" for _ in JOBS)
    verdict = tuple(tuple(NO_VERDICT for _ in FILES) for _ in JOBS)
    return (src, dst, phase, verdict)


def with_item(seq, index, value):
    return seq[:index] + (value,) + seq[index + 1:]


def successors(state, restart_resets=True):
    src, dst, phase, verdict = state

    for ji, j in enumerate(JOBS):
        job_files = JOB_FILES[j]
        indices = [FILES.index(f) for f in job_files]

        # StartCopy
        if phase[ji] == "queued":
            yield (src, dst, with_item(phase, ji, "copying"), verdict)

        # CopyFile (correct or corrupt)
        if phase[ji] == "copying":
            for fi in indices:
                for h in HASHES:
                    yield (src, with_item(dst, ji, with_item(dst[ji], fi, h)), phase, verdict)

        # FinishCopy
        if phase[ji] == "copying":
            yield (src, dst, with_item(phase, ji, "copied"), verdict)

        # StartVerify - only once this job's copy has finished
        if phase[ji] == "copied":
            yield (src, dst, with_item(phase, ji, "verifying"), verdict)

        # VerifyFile
        if phase[ji] == "verifying":
            for fi in indices:
                if verdict[ji][fi] != NO_VERDICT:
                    continue
                result = "ok" if dst[ji][fi] == src[fi] else "bad"
                yield (src, dst, phase, with_item(verdict, ji, with_item(verdict[ji], fi, result)))

        # FinishVerify - refuses to finish while any row is pending
        if phase[ji] == "verifying":
            pending = [fi for fi in indices if verdict[ji][fi] == NO_VERDICT]
            if not pending:
                all_ok = all(verdict[ji][fi] == "ok" for fi in indices)
                yield (src, dst, with_item(phase, ji, "done" if all_ok else "failed"), verdict)

        # Restart
        if phase[ji] == "failed":
            fresh = verdict[ji] if not restart_resets else tuple(NO_VERDICT for _ in FILES)
            yield (src, dst, with_item(phase, ji, "copying"), with_item(verdict, ji, fresh))

        # Cancel
        if phase[ji] in ("queued", "copying", "copied", "verifying"):
            yield (src, dst, with_item(phase, ji, "cancelled"), verdict)


def violations(state):
    src, dst, phase, verdict = state
    found = []

    for ji, j in enumerate(JOBS):
        if phase[ji] == "done":
            for f in JOB_FILES[j]:
                fi = FILES.index(f)
                if dst[ji][fi] != src[fi] or verdict[ji][fi] != "ok":
                    found.append(("DoneMeansMatch", j, f))

        for fi, f in enumerate(FILES):
            if verdict[ji][fi] == "ok" and dst[ji][fi] != src[fi]:
                found.append(("NoFalseOk", j, f))

        # A cancelled job may keep the rows it had already checked.
        if phase[ji] not in ("verifying", "done", "failed", "cancelled"):
            for f in JOB_FILES[j]:
                fi = FILES.index(f)
                if verdict[ji][fi] != NO_VERDICT:
                    found.append(("VerdictOnlyAfterCopy", j, f))

        if phase[ji] in TERMINAL:
            for f in JOB_FILES[j]:
                fi = FILES.index(f)
                # a cancelled job may keep partial verdicts; only prove done is clean
                if phase[ji] == "done" and verdict[ji][fi] == NO_VERDICT:
                    found.append(("DoneHasPendingRow", j, f))

    return found


def explore(restart_resets=True):
    seen = set()
    queue = deque()

    for values in itertools.product(HASHES, repeat=len(FILES)):
        state = initial_state(values)
        seen.add(state)
        queue.append(state)

    bad = []
    while queue:
        state = queue.popleft()
        for problem in violations(state):
            if problem not in bad:
                bad.append(problem)
        for nxt in successors(state, restart_resets):
            if nxt not in seen:
                seen.add(nxt)
                queue.append(nxt)

    return len(seen), bad


def main():
    mutate = "--mutate" in sys.argv

    count, bad = explore(restart_resets=not mutate)
    print(f"model          : {'retry keeps stale verdicts' if mutate else 'Bunshin protocol model'}")
    print(f"states explored: {count}")

    if mutate:
        if any(v[0] == "NoFalseOk" for v in bad):
            print("mutation detected: NoFalseOk violated (the check has teeth)")
            return 0
        print("MUTATION NOT DETECTED - the properties are too weak")
        return 1

    if bad:
        print(f"VIOLATIONS: {len(bad)}")
        for problem in bad[:10]:
            print("  ", problem)
        return 1

    print("violations     : 0")
    print("checked        : DoneMeansMatch, NoFalseOk, VerdictOnlyAfterCopy, DoneHasPendingRow")
    print("\nEvery reachable interleaving of queue -> copy -> verify -> done satisfies all four.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
