# Task graph — v14.7.2 review round

Independent patches shipped on `fix/bd-r2-r4-r5-r7-r8` (no ordering
requirement between them, but they share files — see conflicts below):

```text
TIP-501 (BD-R2, P1)  ExecutionLayer + GridEngine
TIP-502 (BD-R4, P1)  Config + Persistence + MoneyGuard + BlackDragon.mq5
TIP-503 (BD-R5, P2)  MobileControl + Config
TIP-504 (BD-R7, P2)  BasketManager
TIP-505 (BD-R8, P2)  BlackDragon.mq5
```

Second wave — the three findings that needed a Chu nha decision first.
Decisions taken 11/08/2026, patches shipped on the same branch:

```text
TIP-506 (BD-R1, P1)  Config + ExecutionLayer
        decision: keep the BD-001/BD-002 ordering, shorten the freeze
        (close/modify unlock 10s, open stays 30s)
TIP-507 (BD-R3, P1)  BasketManager + Strategy
        decision: the real SL may be cleared by a DCA add, but the trail
        must re-arm from the NEW breakeven (and say so in the log)
TIP-508 (BD-R6, P2)  BasketManager + BlackDragon.mq5
        decision: count manual magic-0 REALIZED P/L in the daily net,
        symmetrical with the floating P/L that already counted
```

Third wave — self-audit: the half-landed TIP-506 ExecutionLayer patch, the
28 asserts, and the documentation that had drifted ahead of the code.

Fourth wave — one P3 promoted after the owner read the backlog and asked
for it by name (11/08/2026):

```text
TIP-509 (BD-R9, P3*)  EntryFilters + Strategy
        * P3 by how rarely the trigger is met, P1 by consequence: with
          hedge OFF and both sides open, EVERY grid add on BOTH sides was
          blocked permanently while the exits kept running.
        decision: the hedge rule gates a NEW series, never a DCA add —
          a DCA cannot create the opposite exposure it is blamed for,
          because its own side is already open and the other side exists
          regardless.
```

Shared files (must land in one branch, which is what this PR does):

```text
Config.mqh          <- TIP-502, TIP-503, TIP-506
ExecutionLayer.mqh  <- TIP-501, TIP-506
BasketManager.mqh   <- TIP-504, TIP-507, TIP-508
BlackDragon.mq5     <- TIP-502, TIP-505, TIP-508
Strategy.mqh        <- TIP-507, TIP-509
EntryFilters.mqh    <- TIP-509
```

Default-settings blast radius of waves 2-4:

```text
TIP-506  error path only (an async reply that never arrives)
TIP-507  no-op while iTS = 0 (default) — trail disabled
TIP-508  no-op while flag_Hand_Ord = false (default)
TIP-509  no-op while Flag_Use_hedge = true (default) — the deadlock needs
         hedge OFF *and* live exposure on both sides at the same time
```

Still open — deliberately NOT patched:

```text
P3 #1  sell-trail arming compares an ask-based extreme to a bid-based level
P3 #2  positionVolumeBefore misnomer (safe rename, but ExecutionLayer.mqh is
       26 KB and there is no compiler here to catch a slip)
P3 #3  async-open journal can sit to the hard timeout on a stale
       positionCountBefore
P3 #5  WMF re-Seed()s 1000 bars per chart bar when WmfTF < chart TF
```

The owner excluded #1, #3 and #5 from this round on 11/08/2026 — all three
change behaviour and none is urgent. #2 is safe but cosmetic and was left
out to keep the branch reviewable.

Closed from the original seven-item P3 list: **#4 -> TIP-509** (wave 4),
**#6** assert-count doc drift (wave 3), **#7** root-level duplicate zip
(deleted in wave 4).
