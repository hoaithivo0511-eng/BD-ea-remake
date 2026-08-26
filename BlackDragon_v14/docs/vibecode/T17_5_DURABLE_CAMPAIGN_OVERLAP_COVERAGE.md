# T17.5 — Durable Campaign, Overlap Reserve, Unordered Coverage

Status: **OWNER APPROVED / LOCAL DETERMINISTIC PASS / NATIVE CI PENDING / PR MUST REMAIN DRAFT**.

## SCAN / RRI

Parent source is remote HEAD `85bc75060e5e166715cd113685c1e01b752c181c`,
tree `8867225ea69724132cf82259c3d54ad6457a848c`. Owner tester log SHA256 is
`6d73ac277009e6e550ead9d1aa867f0fd5b890e5a5c0f5d821f787a7ab9f04f6`.

The log proves two P1 defects. Overlap can remove the current oldest live seed
while the Core side remains non-flat, causing T17.4 to rebase history and erase
prior Pyramid realized loss/serial state. Separately, 150 ms sequential Overlap
execution produced recurring gross-negative realized pairs. The owner also
explicitly requires `HedgePyramidCoverageSequence_` to accept ratios without a
strictly increasing input order.

## SPECIFY / DECIDE / CONTRACT

Canonical records are `T17_5_EA-SPEC.yaml`, `T17_5_DECISIONS.yaml`, and
`T17_5_AI-BUILD-CONTRACT.json`. Policy revision advances to 6. The existing 20
Pyramid inputs, names, types and defaults are preserved.

Coverage values are targets, not increments. Runtime applies existing caps,
sorts targets ascending and removes duplicates. It never interprets a lower
token as an instruction to close Hedge. Gap values map to the resulting
ascending transitions.

## PLAN / BUILD

1. Reconstruct the active campaign from exact Core-owned position IDs and
   signed broker volume units back to the latest flat-to-nonflat transition.
2. Keep that boundary stable in memory until the side becomes flat; use it for
   every serial/realized/mutation history refresh.
3. Add an execution-cash reserve to legacy Overlap after its existing relative
   percentage gate and before any close request.
4. Normalize unordered Hedge coverage targets once at initialization.
5. Lock all three behaviors in C++ and native MQL5 pure-policy tests and source
   invariants; rerun the complete T1-T16.6 regression matrix.
6. Build an exact-head Windows MetaEditor artifact, then require owner Strategy
   Tester replay before any forward/merge decision.

## VERIFY / EVIDENCE / RETRO

Local deterministic evidence on the candidate tree:

- focused C++ model: **85 passed / 0 failed**;
- T17.5 source/contract invariants: **PASS**;
- exactly **20** Pyramid inputs; policy revision **6**;
- established T1-T16.6 C++ matrix: every suite reports **0 failed**;
- JSON/YAML parse and `git diff --check`: **PASS**;
- local MetaEditor/terminal: **UNTESTABLE** (not installed in this Linux environment).

Windows-native MetaEditor, native MQL5 `116/0`, exact EX5 hash and full native
regression remain `PENDING` until both GitHub workflows pass on the exact new
HEAD. Strategy Tester remains `FAIL_INCOMPLETE`; forward/live remain not eligible.
Fixed-Pyramid Peel admission remains the approved T17.4 configured-gap reserve;
the separate fill-overshoot P2 question is intentionally outside T17.5.
