------------------------------ MODULE Bunshin ------------------------------
\* Design model for the Bunshin GUI job pipeline.
\*
\* Scope: the *protocol* between queue, copy phase, verify phase and the result
\* table. It does not model robocopy, SHA-256 or the UI toolkit. It answers:
\*   - can the app ever claim a job is verified when a file was not?
\*   - can a verdict be written before that job's copy finished?
\*   - does "retry" ever keep a stale "ok" from the previous attempt?
\*
\* Each job owns its destination namespace (dst[j]). Jobs targeting the same
\* physical folder are out of scope; the UI must serialise or refuse those.

EXTENDS Naturals, FiniteSets

CONSTANTS Files, Jobs, Hashes, NULL, jobFiles

Phases == {"queued", "copying", "copied", "verifying", "done", "failed", "cancelled"}
Terminal == {"done", "failed", "cancelled"}
Verdicts == {"none", "ok", "bad"}

VARIABLES src, dst, phase, verdict

vars == <<src, dst, phase, verdict>>

TypeOK ==
    /\ src \in [Files -> Hashes]
    /\ dst \in [Jobs -> [Files -> Hashes \cup {NULL}]]
    /\ phase \in [Jobs -> Phases]
    /\ verdict \in [Jobs -> [Files -> Verdicts]]

Init ==
    /\ src \in [Files -> Hashes]
    /\ dst = [j \in Jobs |-> [f \in Files |-> NULL]]
    /\ phase = [j \in Jobs |-> "queued"]
    /\ verdict = [j \in Jobs |-> [f \in Files |-> "none"]]

\* ------------------------------------------------------------------ copy ---

StartCopy(j) ==
    /\ phase[j] = "queued"
    /\ phase' = [phase EXCEPT ![j] = "copying"]
    /\ UNCHANGED <<src, dst, verdict>>

CopyFile(j, f) ==
    /\ phase[j] = "copying"
    /\ f \in jobFiles[j]
    \* A copy can land correctly, or be corrupt/interrupted/blocked and land
    \* with the wrong bytes. Both outcomes are reachable, so verification has
    \* real work to do in the model.
    /\ \E h \in Hashes : dst' = [dst EXCEPT ![j][f] = h]
    /\ UNCHANGED <<src, phase, verdict>>

FinishCopy(j) ==
    \* robocopy has exited: from here on nothing in this job writes to dst.
    /\ phase[j] = "copying"
    /\ phase' = [phase EXCEPT ![j] = "copied"]
    /\ UNCHANGED <<src, dst, verdict>>

\* ---------------------------------------------------------------- verify ---

StartVerify(j) ==
    \* The load-bearing guard: verification never overlaps its own copy.
    /\ phase[j] = "copied"
    /\ phase' = [phase EXCEPT ![j] = "verifying"]
    /\ UNCHANGED <<src, dst, verdict>>

VerifyFile(j, f) ==
    /\ phase[j] = "verifying"
    /\ f \in jobFiles[j]
    /\ verdict[j][f] = "none"
    /\ verdict' = [verdict EXCEPT ![j][f] = IF dst[j][f] = src[f] THEN "ok" ELSE "bad"]
    /\ UNCHANGED <<src, dst, phase>>

FinishVerify(j) ==
    \* No result row may still be pending, so the table is never "complete"
    \* while a file was not looked at.
    /\ phase[j] = "verifying"
    /\ \A f \in jobFiles[j] : verdict[j][f] # "none"
    /\ phase' = [phase EXCEPT ![j] =
           IF \A f \in jobFiles[j] : verdict[j][f] = "ok" THEN "done" ELSE "failed"]
    /\ UNCHANGED <<src, dst, verdict>>

\* ------------------------------------------------------------------ user ---

Restart(j) ==
    \* "Retry" in the UI: copy again and forget the previous attempt's verdicts.
    /\ phase[j] = "failed"
    /\ phase' = [phase EXCEPT ![j] = "copying"]
    /\ verdict' = [verdict EXCEPT ![j] = [f \in Files |-> "none"]]
    /\ UNCHANGED <<src, dst>>

Cancel(j) ==
    /\ phase[j] \in {"queued", "copying", "copied", "verifying"}
    /\ phase' = [phase EXCEPT ![j] = "cancelled"]
    /\ UNCHANGED <<src, dst, verdict>>

Next ==
    \E j \in Jobs :
        \/ StartCopy(j)
        \/ FinishCopy(j)
        \/ StartVerify(j)
        \/ FinishVerify(j)
        \/ Restart(j)
        \/ Cancel(j)
        \/ \E f \in Files : CopyFile(j, f) \/ VerifyFile(j, f)

\* Every enabled step of a job is eventually taken, so a queue that can make
\* progress does make progress.
Fair ==
    \A j \in Jobs :
        /\ \A f \in Files : WF_vars(CopyFile(j, f)) /\ WF_vars(VerifyFile(j, f))
        /\ WF_vars(StartCopy(j))
        /\ WF_vars(FinishCopy(j))
        /\ WF_vars(StartVerify(j))
        /\ WF_vars(FinishVerify(j))

Spec == Init /\ [][Next]_vars /\ Fair

\* ------------------------------------------------------------ properties ---

\* A done job means every file was copied correctly and checked.
DoneMeansMatch ==
    \A j \in Jobs :
        phase[j] = "done" =>
            \A f \in jobFiles[j] : dst[j][f] = src[f] /\ verdict[j][f] = "ok"

\* No result row ever says ok for bytes that are not identical.
NoFalseOk ==
    \A j \in Jobs : \A f \in Files :
        verdict[j][f] = "ok" => dst[j][f] = src[f]

\* The table cannot show a verdict while that job is still copying. A
\* cancelled job may keep the rows it had already checked, hence "cancelled".
VerdictOnlyAfterCopy ==
    \A j \in Jobs : \A f \in Files :
        verdict[j][f] # "none" => phase[j] \in {"verifying", "done", "failed", "cancelled"}

\* Every queued job eventually reaches a terminal state.
EventuallyTerminal ==
    \A j \in Jobs : (phase[j] = "queued") ~> (phase[j] \in Terminal)

=============================================================================
