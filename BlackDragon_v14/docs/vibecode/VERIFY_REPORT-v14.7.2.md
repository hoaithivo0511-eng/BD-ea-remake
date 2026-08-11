# VERIFY REPORT — v14.7.2 (BD-R1..R8)

- Base: `908ab4c` (v14.7.1, after BD-001/BD-002)
- Branch: `fix/bd-r2-r4-r5-r7-r8`
- Method: vibecode-kit v5.1, REVIEW mode (SCAN -> VERIFY) with RRI-T
- Date: 11/08/2026 (wave 1: TIP-501..505; wave 2: TIP-506..508 after the
  owner's decisions on Q1/Q2/Q5 the same day)

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

The 27 asserts specified across TIP-501..508 are **specified, not written**
(18 from wave 1, 9 from wave 2: 5 for `Exec_HardTimeoutSec`, 4 for
`Basket_OwnsMagic`).

## Findings fixed on this branch

### Wave 1 — no owner decision needed

| ID | Pri | Module | Symptom |
| --- | --- | --- | --- |
| BD-R2 | P1 | ExecutionLayer | `Slippage_` never multiplied by `PointScale`; 3-digit gold allowed 0.03 USD slip instead of 0.30 |
| BD-R4 | P1 | MoneyGuard | Daily SL/TP halt lost on any restart/recompile the same day |
| BD-R5 | P2 | MobileControl | Undeletable pending -> `Persist_Save()` + panel redraw twice a second, forever |
| BD-R7 | P2 | BasketManager | Vanished ticket still counted in `count`/`totalLots` for one full tick |
| BD-R8 | P2 | BlackDragon.mq5 | `DrawLevels` on every tick, against ARCHITECTURE rule C3 |

### Wave 2 — behaviour-changing, patched only after the owner chose

Per rubric A3 these were raised as questions first (Q1/Q2/Q5) and patched
only once the owner picked the behaviour, on 11/08/2026.

| ID | Pri | TIP | Decision taken | What shipped |
| --- | --- | --- | --- | --- |
| BD-R1 | P1 | TIP-506 | Keep the ordering, shorten the freeze | `BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC = 10` + pure `Exec_HardTimeoutSec(action)`; OPEN keeps 30s. Worst-case guard freeze after a lost close reply: 30s -> 10s |
| BD-R3 | P1 | TIP-507 | Clearing the SL is accepted, but the trail must re-arm from the NEW breakeven | Trail extreme became monotonic session state with a leg anchor; re-anchored only by a NEWER leg; `"trailclr"` warn when a real stop is actually dropped |
| BD-R6 | P2 | TIP-508 | Count manual realized P/L too | Pure `Basket_OwnsMagic()` shared by the position scan, `SeedDayProfit()` and `OnTradeTransaction` |

**BD-R3 note.** While writing TIP-507 a second, worse consequence of the same
root cause surfaced and is fixed by the same patch: because `SeedExtreme()`
re-derived the extreme from "bars since the newest leg" on EVERY `Rebuild()`,
the window right after a DCA add still contained the pre-add part of the
current bar. A high printed while the basket had a higher breakeven could arm
the trail on the same tick as the add, against the new lower breakeven — in
Virt mode closing the basket immediately, in Real mode pushing a stop on the
wrong side of price. The anchor rule removes that path.

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
2. Offline suite + `RunTests.mq5` green, with the 27 new asserts added.
3. Tester A/B on the baseline `.set`: trade list identical to v14.7.1.
   All eight patches are specified as tester no-ops on default inputs —
   TIP-506 touches an error path only, TIP-507 needs `iTS != 0` (default 0),
   TIP-508 needs `flag_Hand_Ord = true` (default false).
4. 3-digit gold demo: journal shows `deviation` scaled x10 (BD-R2).
5. Live/demo: trigger a daily SL, restart the terminal, confirm the halt
   survives and the journal prints the restore line (BD-R4).
6. Demo: place an undeletable mobile pending, confirm one INFO + throttled
   WARN and no state-file churn (BD-R5).
7. Async + `MoneySLAllAccount != 0`, close reply dropped: the guard fires
   within ~10s of the soft timeout, not ~30s; a dropped OPEN reply still
   waits the full 30s and never produces a second order (BD-R1/TIP-506).
8. `iTS != 0` + `Trail_Mode = Real`, buy basket armed, then a DCA add: the
   trail must NOT re-arm on the add tick; it re-arms only past
   `new breakeven + TrailStart`; exactly one `"trailclr"` warn per side per
   60s. Repeat with an overlap trim: the extreme must survive (BD-R3/TIP-507).
9. `flag_Hand_Ord = true`: close a manual magic-0 order in profit — the day
   total must not fall; with `flag_Hand_Ord = false` magic-0 deals stay out
   (BD-R6/TIP-508).

## Residual risks

- **State file magic BD15 -> BD16.** On first run of this branch the old
  state file is ignored ONCE: panel toggles (pause buy/sell, new cycle,
  edit lot, remote stop) fall back to input defaults. Note it before
  deploying on a live chart with a paused side.
- **BD-R7 timing change.** The DCA index counts OPEN orders, so after a leg
  vanishes the index now steps back on the same tick instead of the next
  one. Intended, but it is the one patch here that could in principle move
  a fill by one tick. Verify with test 3.
- **BD-R1 residual exposure (accepted).** The money/daily guard still does
  not run while an async close is unresolved. The window is now bounded at
  10s instead of 30s; it is not zero, by decision.
- **BD-R3 trail arming is now slightly later** in one case: intra-bar highs
  printed after a DCA add but before the next tick are no longer folded into
  the extreme. Under-arming was chosen deliberately over the previous
  over-arming, which could close a basket instantly.
- **BD-R6 widens the DAILY scope when `flag_Hand_Ord = true`** to "this bot +
  manual orders on this symbol". That is what the floating side already
  meant; `MoneyTPAll/SLAll` (magic scope) are untouched. Default settings are
  unaffected.
- `BD_VERSION`, `#property version` and `CHANGELOG.md` were deliberately
  NOT touched — version/release bookkeeping is the owner's call.

## Retro

- No historical regression: every AU-14-xx, BD-001, BD-002 and FIX-x patch
  is still correctly in place. The new findings all live in the SEAMS
  between modules (guard vs execution, guard vs persistence, cache vs
  consumers), which is exactly where rubric A5 says to look after a
  refactor round.
- Rubric A3 held: 3 of 8 findings became questions instead of patches, and
  stayed unwritten until the owner answered. All three answers arrived on
  11/08/2026 and each patch implements the chosen option, not the reviewer's
  preference.
- Rubric A12 held: the missing evidence is stated up front instead of being
  implied by "reviewed OK". That is still true after wave 2 — nothing here
  has been compiled or run.
