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

Shared files (must land in one branch, which is what this PR does):

```text
Config.mqh          <- TIP-502, TIP-503, TIP-506
ExecutionLayer.mqh  <- TIP-501, TIP-506
BasketManager.mqh   <- TIP-504, TIP-507, TIP-508
BlackDragon.mq5     <- TIP-502, TIP-505, TIP-508
Strategy.mqh        <- TIP-507
```

Default-settings blast radius of the second wave:

```text
TIP-506  error path only (an async reply that never arrives)
TIP-507  no-op while iTS = 0 (default) — trail disabled
TIP-508  no-op while flag_Hand_Ord = false (default)
```

Still open — deliberately NOT patched in this round:

```text
P3 x7   see VERIFY_REPORT-v14.7.2.md §5 (sell-trail bid/ask asymmetry,
        positionVolumeBefore misnomer, async-open journal hard-timeout
        path, hedge-OFF two-sided manual deadlock, WMF re-Seed cost,
        assert-count doc drift, root-level duplicate zip)
```
