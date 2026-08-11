# VERIFY REPORT — v14.7.2 (BD-R1..R9)

- Base: `908ab4c` (v14.7.1, after BD-001/BD-002)
- Branch: `fix/bd-r2-r4-r5-r7-r8`
- Method: vibecode-kit v5.1, REVIEW mode (SCAN -> VERIFY) with RRI-T
- Date: 11/08/2026 (wave 1: TIP-501..505; wave 2: TIP-506..508 after the
  owner's decisions on Q1/Q2/Q5 the same day; wave 3: self-audit correction
  + tests + doc drift; wave 4: TIP-509 + release bookkeeping)

## Overall status

**NOT RELEASABLE.** Every behavioural claim in this document is a STATIC
review claim, not test evidence. In this environment there was no MQL5
toolchain, no MetaEditor, no strategy tester and no network, so:

| Gate | Result |
| --- | --- |
| MetaEditor compile (0 errors / 0 warnings) | NOT RUN |
| Strategy Tester A/B vs v14.7.1 baseline | NOT RUN |
| Offline suite (277/277 previously) | NOT RUN |
| UBSan / ASan | NOT RUN |
| Brace + preprocessor balance | NOT RUN (no local checkout) |
| Static read of all 20 MQL files | PASS |
| Post-commit blob verification of every pushed file | PASS — **caught 1 half-landed commit**, see below |

The asserts are no longer a promise: **37 asserts for BD-R1..R9 are WRITTEN**
in `Scripts/BlackDragon/Tests/RunTests.mq5` (7 BD-R2, 5 BD-R4, 1 BD-R5,
8 BD-R1, 7 BD-R6, 9 BD-R9). They have **not been executed** — that needs
MetaEditor. BD-R3, BD-R7 and BD-R8 have no pure surface to assert and stay in
the manual checklist below.

## Corrections made during this review

> Recorded per rubric A12: a review that hides its own misses is worth less
> than the misses cost.

**TIP-506 landed only half, and this report claimed it was done.** The wave-2
commit `67cd217` was supposed to touch two files. `Config.mqh` received
`BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC = 10` and `Strategy.mqh` received the BD-R1
decision comment, but `ExecutionLayer.mqh` came back byte-identical to its
pre-wave-2 blob (`c8f82b38`). `Exec_HardTimeoutSec()` did not exist and
`Watchdog()` still compared every journal entry against
`BD_ASYNC_HARD_TIMEOUT_SEC`. Net effect: a new constant that nothing read, a
report and a PR body both asserting BD-R1 was fixed, and a guard that in
reality still froze for 30s.

- **How it was caught:** re-reading the blob SHA of every file the wave-2
  commits claimed to touch, instead of trusting the success response. A
  successful push proves a commit exists, not that its content changed.
- **Closed by:** the ExecutionLayer half was pushed separately; the blob
  moved `c8f82b38` -> `a9cea6af` (23,377 -> 25,813 bytes) and
  `Exec_HardTimeoutSec` now has three references (definition, `Watchdog()`
  branch, `"wdog"` log) plus 8 asserts.
- **Rule added to HANDOFF §8 and ARCHITECTURE §6:** after each commit, grep
  the new constant/function name. If it appears exactly once — at its
  declaration — the fix is half done.
- **Rule applied to every later commit.** Waves 3 and 4 verified each blob
  after pushing; TIP-509 moved `EntryFilters.mqh` `a818b954` -> `753221ec`
  and `Strategy.mqh` `359220bf` -> `9b79bbcb` (13,325 -> 14,219 bytes)
  before the fix was written up as done.

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
| BD-R1 | P1 | TIP-506 | Keep the ordering, shorten the freeze | `BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC = 10` + pure `Exec_HardTimeoutSec(action)` wired into `Watchdog()`; OPEN keeps 30s. Worst-case guard freeze after a lost close reply: 30s -> 10s. *(Completed in wave 3 — see Corrections.)* |
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

### Wave 3 — self-audit, tests and documentation

| Item | Status |
| --- | --- |
| TIP-506 ExecutionLayer half | Pushed (see Corrections) |
| 28 asserts for the new pure functions | Written in `RunTests.mq5`, not run |
| Assert-count drift (P3 #6) | Fixed — ARCHITECTURE and HANDOFF now point at the number the script prints instead of quoting a stale one |
| Owner decision log | HANDOFF §3 gained entries 10/11/12 for the 11/08/2026 decisions |
| BD15 -> BD16 state reset | Promoted to a warning box in HANDOFF §0 (it was only a residual-risk line here) |

### Wave 4 — BD-R9 and release bookkeeping

The owner read the P3 backlog and pulled item #4 into scope by name.

| ID | Pri | TIP | Symptom | Fix |
| --- | --- | --- | --- | --- |
| BD-R9 | P3 by odds, P1 by consequence | TIP-509 | `Flag_Use_hedge = false` + exposure on both sides -> both `TryGridAdd` gates false forever. The basket freezes at its worst average price while the exits keep running, with no path back. | The hedge test moved to `Hedge_AllowsNewSeries()` (v13 rule, unchanged) and the DCA gate became `Hedge_AllowsGridAdd(ownCount)` — both pure, both in `EntryFilters.mqh`. |

The two gates were **mutually exclusive**: `(useHedge || sell.count == 0)` and
`(useHedge || buy.count == 0)` cannot both be true once both sides are open
and hedging is off. Nothing in the tick loop could clear that state.

Two-sided exposure is reachable even with hedge OFF, which is why this is a
real defect and not a theoretical one: the panel's Open Buy / Open Sell
buttons bypass the hedge test by design, and `flag_Hand_Ord = true` counts
manual magic-0 orders into both sides. The gate also contradicted the
invariant written at the top of `Strategy.mqh` — "grid adds are gated by
pause/news/one-per-bar/MinuteStop only".

`Flag_Use_hedge` is deliberately **not** a parameter of
`Hedge_AllowsGridAdd()`. Reading the signature is enough to see that the
absence of a hedge test is intentional rather than an accidental deletion.

Assert #9 of the BD-R9 block pins the thing that matters most: in the exact
deadlock state, DCA is unblocked **and** a new opposite series is still
refused. The v13 no-hedge protection was not weakened. Assert #7 rebuilds the
**old** gate and proves it false on both sides simultaneously — kept as
executable code rather than prose so nobody restores it by accident.

Also in wave 4:

| Item | Status |
| --- | --- |
| `BD_VERSION` -> `"14.7.2"`, `#property version` -> `"14.72"` | Done, one commit, deliberately together |
| Root-level `BlackDragon_v14.7.1_..._FIXED.zip` (202 KB, P3 #7) | Deleted — a second source of truth git cannot diff, two versions stale |
| `CHANGELOG.md` v14.7.2 entry | See the bookkeeping note below |

## P3 backlog (still open, owner's call)

1. Sell-trail arming compares an ask-based extreme against a bid-based level.
2. `positionVolumeBefore = req.volume` is a misnomer (it holds the target).
3. Async-open journal can sit to the hard timeout when `positionCountBefore`
   is stale.
4. ~~Hedge OFF + two-sided manual orders can deadlock both `TryGridAdd`
   paths~~ — fixed in wave 4 as BD-R9 / TIP-509.
5. WMF re-`Seed()`s 1000 bars per chart bar when `WmfTF` < chart TF.
6. ~~Doc drift: ~80 vs ~180 vs 277 asserts~~ — fixed in wave 3.
7. ~~Root-level zip duplicates the whole tree (rubric A12)~~ — deleted in
   wave 4.

Items 1, 3 and 5 change behaviour and were excluded from this round by the
owner on 11/08/2026. Item 2 is safe but cosmetic: the rename would force a
full re-emit of `ExecutionLayer.mqh` (26 KB) and `Types.mqh` with no compiler
available to catch a slip, which is a bad trade for zero behavioural value.

## Required terminal tests before merge

1. MetaEditor compile: 0 errors, 0 warnings.
2. `RunTests.mq5` green — the new v14.7.2 section must report 0 failures —
   and the offline C++ suite still 277/277.
3. Tester A/B on the baseline `.set`: trade list identical to v14.7.1.
   All nine patches are specified as tester no-ops on default inputs —
   TIP-506 touches an error path only, TIP-507 needs `iTS != 0` (default 0),
   TIP-508 needs `flag_Hand_Ord = true` (default false), TIP-509 needs
   `Flag_Use_hedge = false` (default true).
4. 3-digit gold demo: journal shows `deviation` scaled x10 (BD-R2).
5. Live/demo: trigger a daily SL, restart the terminal, confirm the halt
   survives and the journal prints the restore line (BD-R4).
6. Demo: place an undeletable mobile pending, confirm one INFO + throttled
   WARN and no state-file churn (BD-R5).
7. Async + `MoneySLAllAccount != 0`, close reply dropped: the guard fires
   within ~10s of the soft timeout, not ~30s; a dropped OPEN reply still
   waits the full 30s and never produces a second order (BD-R1/TIP-506).
   **This is the test that would have caught the half-landing** — run it
   before trusting the fix.
8. `iTS != 0` + `Trail_Mode = Real`, buy basket armed, then a DCA add: the
   trail must NOT re-arm on the add tick; it re-arms only past
   `new breakeven + TrailStart`; exactly one `"trailclr"` warn per side per
   60s. Repeat with an overlap trim: the extreme must survive (BD-R3/TIP-507).
9. `flag_Hand_Ord = true`: close a manual magic-0 order in profit — the day
   total must not fall; with `flag_Hand_Ord = false` magic-0 deals stay out
   (BD-R6/TIP-508).
10. `Flag_Use_hedge = false`: open one manual buy and one manual sell, then
    let price travel past the DCA distance on each side. **Both** sides must
    resume grid adds. In the same state, confirm the EA still refuses to open
    a NEW opposite series — if it opens one, the fix went too far
    (BD-R9/TIP-509).

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
- **BD-R9 residual, pre-existing but now met more often.** With
  `flag_Hand_Ord = true`, an EA-owned side can now DCA while manual orders
  sit on the opposite side, and `TryGridAdd` may stack martingale legs onto
  what is effectively a manual basket. This is `flag_Hand_Ord` behaviour, not
  something BD-R9 introduced — it already applied whenever only one side held
  manual orders — but the fix removes the accidental lock that was hiding it.
  Operators who use `flag_Hand_Ord` should read test 10 before enabling it.
- **The 37 new asserts have never been compiled.** MQL5 is not C++: a typo in
  an enum name or an implicit conversion warning will surface only in
  MetaEditor. Treat test 2 as a compile gate as much as a behaviour gate.
- **Release bookkeeping is partly done.** `BD_VERSION` and
  `#property version` are both at 14.7.2 (bumped together on purpose — split
  them and the journal line disagrees with the About box). `CHANGELOG.md`
  is the remaining item.

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
- Rubric A12 held twice. First: the missing evidence is stated up front
  instead of being implied by "reviewed OK". Second, and more expensively:
  when the self-audit found that TIP-506 had half-landed and that this very
  report was over-claiming, the correction was written into the report
  rather than quietly patched. A verify report that only records successes
  is not a verify report.
- **New rubric candidate (earned here):** "a write that succeeds is not a
  write that changed anything". Verify the artefact, not the API response —
  for a file, that means re-reading its hash; for a fix, that means grepping
  the new symbol and counting references.
- **Second candidate, earned by BD-R9:** when two guards protect the same
  invariant from opposite directions, check whether they can be false at the
  same time. `(hedge || sell == 0)` and `(hedge || buy == 0)` each look
  reasonable in isolation; read together they are a deadlock with no exit.
  A gate copied from the "open a new series" path to the "add to an existing
  series" path is a smell in itself — the two paths do not share a
  precondition just because they both open an order.
