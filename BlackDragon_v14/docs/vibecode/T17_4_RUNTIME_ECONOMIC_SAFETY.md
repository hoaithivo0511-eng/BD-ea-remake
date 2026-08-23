# T17.4 — Runtime Economic Safety Deep Fix

Status: **OWNER APPROVED / LOCAL DETERMINISTIC PASS / NATIVE CI PENDING / PR MUST REMAIN DRAFT**.

## SCAN / RRI

The exact parent is `da921da42fec4d06235745f5d184b359b5ed651d`, tree
`d3cd6b82eeb8cc8fda5b9a6e467ff8f0bb07f1cb`. Owner runtime log SHA256 is
`f558c25794b46ca6441e6eca909210aaf271ed6c9ddc24cf50cc075980d90b1a`.

The reconstructed ledger matched all 1,894 close deals. Gross realized P/L was
`-$509.23`; 162 LIFO Peels contributed `-$3,242.28`. Five PctDiff flatten
episodes were gross-negative even before commission/fee/swap. The tester also
ended on 2026-08-04 although 2026-08-23 was requested, so it is FAIL evidence
for the defects but not a complete release backtest.

No unresolved high-impact semantic question remains after the owner's approval:
absolute account money guards remain raw floating, PctDiff gets a campaign-debt
safety gate, fixed lot is blocked rather than resized, and no Recovery/DCA
semantics are changed.

## SPECIFY / DECIDE / CONTRACT

Canonical records are `T17_4_EA-SPEC.yaml`, `T17_4_DECISIONS.yaml`, and
`T17_4_AI-BUILD-CONTRACT.json`. Policy revision advances to 5; user-facing
Pyramid input count remains exactly 20.

## PLAN / TIP

1. Add independent pure-policy tests for campaign debt, ticket-aware execution
   reserve, and fixed-lot full Peel reserve.
2. Implement the new pure helpers and wire them into Strategy/CorePyramid.
3. Update focused workflow source locks and exact expected test counts.
4. Run local focused/model regression and diff allowlist checks.
5. Commit atomically, push, and require both Windows-native workflows on the
   new exact HEAD.
6. Preserve Strategy Tester, forward and live gates as pending/not eligible.

## VERIFY / EVIDENCE / RETRO

Implemented policy:

- `LOT_CHUOI` stays exact/broker-normalized and is not resized. An ADD is now
  blocked unless non-Pyramid floating + Pyramid realized cash covers minimum
  lock, all live Pyramid Peel liabilities, and the candidate Peel liability.
  Live Pyramid floating is excluded from funding because it is consumed before
  those existing legs reach their Peel exits.
- PctDiff ratio inputs remain current floating. Its close surplus now includes
  active Pyramid campaign realized cash and fails closed when campaign history
  is unavailable.
- PctDiff execution reserve now uses two current spreads plus configured
  deviation per sequential close request. Symbol economics are converted once
  through tick size/value and invalid metadata fails closed.
- Absolute account MoneyTP/SL ordering and raw `ACCOUNT_PROFIT` valuation are
  unchanged. DCA priority release, Recovery T16.6 and post-Peel re-arm are
  unchanged.

Local deterministic verification on this candidate change:

- focused C++ model: `70 passed / 0 failed`;
- focused source invariants: PASS, including exactly 20 Pyramid inputs and
  Pyramid policy revision 5;
- established T1-T16.6 C++ matrix: every suite reports `0 failed`;
- T16.5/T16.6 source regression invariants: PASS;
- JSON/YAML parse and `git diff --check`: PASS.

Counterfactual replay of all 173 PctDiff episodes from the supplied owner log
uses logged floating values and reconstructs close request count/volume from
the actual close chronology. The five episodes that were gross-negative under
the old one-spread buffer would all be blocked by the new reserve:

| Tester time | Floating surplus | Old buffer | New reserve | Actual gross |
|---|---:|---:|---:|---:|
| 2026-07-30 05:30:53 | 4.85 | 4.80 | 16.80 | -0.409 |
| 2026-07-31 14:09:46 | 2.70 | 2.64 | 8.25 | -2.414 |
| 2026-07-31 15:39:04 | 3.63 | 3.60 | 11.25 | -2.541 |
| 2026-08-03 00:37:19 | 4.61 | 3.60 | 11.25 | -0.921 |
| 2026-08-03 06:34:36 | 4.49 | 4.32 | 14.58 | -1.174 |

This replay is deterministic log evidence, not Strategy Tester evidence. Local
MetaEditor/terminal authority is unavailable, so exact-head MetaEditor compile,
native MQL5 `101/0`, established native regression, EX5 hash and artifact IDs
remain PENDING until GitHub Actions completes. Both owner small- and large-Peel
Strategy Tester scenarios remain PENDING after CI and must use the new focused
EX5 artifact. Native compile PASS will not be reported as Strategy Tester PASS.
