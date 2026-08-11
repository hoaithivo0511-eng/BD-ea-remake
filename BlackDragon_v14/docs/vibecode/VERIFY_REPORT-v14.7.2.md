# VERIFY REPORT — v14.7.2 (BD-R2/R4/R5/R7/R8)

- Base: `908ab4c` (v14.7.1, after BD-001/BD-002)
- Branch: `fix/bd-r2-r4-r5-r7-r8`
- Method: vibecode-kit v5.1, REVIEW mode (SCAN -> VERIFY) with RRI-T
- Date: 11/08/2026

## Overall status

**NOT RELEASABLE.** Every claim in this document is a STATIC review claim,
not test evidence. In this environment there was no MQL5 toolchain, no
MetaEditor, no strategy tester and no network, so:

| Gate | Result |
| --- | --- |
| MetaEditor compile (0 errors / 0 warnings) | NOT RUN |
| Strategy Tester A/B vs v14.7.1 baseline | NOT RUN |
| Offline suite (277/277 previously) | NOT RUN |
| UBSan / ASan | NOT RUN |
| Brace + preprocessor balance | NOT RUN (no local checkout) |
| Static read of all 20 MQL files | PASS |

The 18 asserts specified across TIP-501..505 are **specified, not written**.

## Findings fixed on this branch

| ID | Pri | Module | Symptom |
| --- | --- | --- | --- |
| BD-R2 | P1 | ExecutionLayer | `Slippage_` never multiplied by `PointScale`; 3-digit gold allowed 0.03 USD slip instead of 0.30 |
| BD-R4 | P1 | MoneyGuard | Daily SL/TP halt lost on any restart/recompile the same day |
| BD-R5 | P2 | MobileControl | Undeletable pending -> `Persist_Save()` + panel redraw twice a second, forever |
| BD-R7 | P2 | BasketManager | Vanished ticket still counted in `count`/`totalLots` for one full tick |
| BD-R8 | P2 | BlackDragon.mq5 | `DrawLevels` on every tick, against ARCHITECTURE rule C3 |

## Findings NOT fixed — need a Chu nha decision

Per rubric A3, a finding whose fix changes owner-visible behaviour is
raised as a question, never self-patched.

| ID | Pri | Question |
| --- | --- | --- |
| BD-R1 | P1 | Q1 — `Strategy::OnTick` returns on `HasAnyPendingClose()` BEFORE `ApplyGuard(ctx)`. In async mode one unresolved close freezes Money SL All account / Daily SL / the other basket's virtual SL for up to `BD_ASYNC_HARD_TIMEOUT_SEC` (30 s). May the guard run above that early return? |
| BD-R3 | P1 | Q2 — Real-mode trailing SL is wiped on every DCA add (`Invalidate` -> `Rebuild` -> `SeedExtreme` re-seeds from the newest leg -> `trailArmed=false` -> `RealLevels` returns `sl=0` but `true` -> `ModifySlTp(ticket, 0, tp)`). Only with `Trail_Mode=Real && iTS!=0`. Intended, or should the SL be kept? |
| BD-R6 | P2 | Q5 — With `flag_Hand_Ord=true`, magic-0 positions add FLOATING P/L to `dayNet` but their REALIZED P/L is filtered out of `m_dayProfit`. Should manual orders count toward the daily target? |

## P3 backlog (not addressed)

1. Sell-trail arming compares an ask-based extreme against a bid-based level.
2. `positionVolumeBefore = req.volume` is a misnomer (it holds the target).
3. Async-open journal can sit to the hard timeout when `positionCountBefore`
   is stale.
4. Hedge OFF + two-sided manual orders can deadlock both `TryGridAdd` paths.
5. WMF re-`Seed()`s 1000 bars per chart bar when `WmfTF` < chart TF.
6. Doc drift: ~80 vs ~180 vs 277 asserts across ARCHITECTURE / HANDOFF / this
   folder.
7. Root-level zip duplicates the whole tree (rubric A12).

## Required terminal tests before merge

1. MetaEditor compile: 0 errors, 0 warnings.
2. Offline suite + `RunTests.mq5` green, with the 18 new asserts added.
3. Tester A/B on the baseline `.set`: trade list identical to v14.7.1
   (all five patches are specified as tester no-ops).
4. 3-digit gold demo: journal shows `deviation` scaled x10 (BD-R2).
5. Live/demo: trigger a daily SL, restart the terminal, confirm the halt
   survives and the journal prints the restore line (BD-R4).
6. Demo: place an undeletable mobile pending, confirm one INFO + throttled
   WARN and no state-file churn (BD-R5).

## Residual risks

- **State file magic BD15 -> BD16.** On first run of this branch the old
  state file is ignored ONCE: panel toggles (pause buy/sell, new cycle,
  edit lot, remote stop) fall back to input defaults. Note it before
  deploying on a live chart with a paused side.
- **BD-R7 timing change.** The DCA index counts OPEN orders, so after a leg
  vanishes the index now steps back on the same tick instead of the next
  one. Intended, but it is the one patch here that could in principle move
  a fill by one tick. Verify with test 3.
- `BD_VERSION`, `#property version` and `CHANGELOG.md` were deliberately
  NOT touched — version/release bookkeeping is the owner's call.

## Retro

- No historical regression: every AU-14-xx, BD-001, BD-002 and FIX-x patch
  is still correctly in place. The new findings all live in the SEAMS
  between modules (guard vs execution, guard vs persistence, cache vs
  consumers), which is exactly where rubric A5 says to look after a
  refactor round.
- Rubric A3 held: 3 of 8 findings became questions instead of patches.
- Rubric A12 held: the missing evidence is stated up front instead of being
  implied by "reviewed OK".
