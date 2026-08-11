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

Shared files (must land in one branch, which is what this PR does):

```text
Config.mqh          <- TIP-502, TIP-503
BlackDragon.mq5     <- TIP-502, TIP-505
```

Blocked on a Chu nha decision — NOT written yet:

```text
Q1 -> TIP-506 (BD-R1, P1)  guard/close-all above HasAnyPendingClose()
Q2 -> TIP-507 (BD-R3, P1)  real-mode trailing SL wiped by a DCA add
Q5 -> TIP-508 (BD-R6, P2)  magic-0 manual orders in the daily P/L
```
