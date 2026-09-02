# T17.9 Master Plan

Baseline: `0f608ef97a1265521ed32443b5d504ceb9b7ef8d` / tree `affca27b84038e126ded6f73c373bf02a7fab6c0`.

1. SCAN/RRI — reproduce the mutable-live-cohort failure and lock A1/A2/A5/A6/A7/A8/A10/A12 guards.
2. SPECIFY/DECIDE/CONTRACT — freeze exact-identifier epoch, side-local barrier and stale-ticket validation.
3. BUILD — add policy/model tests, implement epoch/classifier/barrier, then harden mutation selection.
4. VERIFY — focused Linux model/source, MetaEditor focused/full 0/0, native T17.9, exact-head T1–T17 matrix.
5. EVIDENCE — record final HEAD/TREE/EX5 SHA256 and package exact-head artefacts.
6. RETRO — update PR Draft handover; owner reruns Strategy Tester using only the proven EX5.

Stop conditions: ambiguous ownership, epoch persistence failure, native compile warning/error, any regression failure, or PR head movement.

