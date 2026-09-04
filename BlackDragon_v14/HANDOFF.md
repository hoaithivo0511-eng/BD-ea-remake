# BlackDragon v15.00 / T17.21 — current handoff

New RH comments use `RH-S|G1|P1|N1`; protective reset rounds use
`RHSL1-S|G1|P1|N1`, then RHSL2, etc. B/S means the order direction.
Core Pyramid uses `PYR-B#3` / `PYR-S#3`. Core DCA remains the configured
comment plus its existing ordinal. Readers accept old BDR/BDP positions.
An unknown migrated round is `RHSL?`, never an invented ordinal.

Trading calculations, T17.20 bar gating and persistence schemas remain unchanged.
See `docs/vibecode/T17_21_comments/` for the approved spec, exact reversible
source manifest and owner QA. Canonical CI requires 40 model suites, source
contracts through T17.21, full EA plus 30 native scripts with 0 errors/warnings,
and 1030 native assertions on the exact branch head. Owner acceptance remains
pending. PR #28 stays Draft; release/forward/live/merge remain false.

Publication uses Git-data on the exact T17.20 remote parent with force=false;
never push the divergent local ancestry. Prior behavior is recorded under T17_20_one_bar and the T17.19 specifications.
