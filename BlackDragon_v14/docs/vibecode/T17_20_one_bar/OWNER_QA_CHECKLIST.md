# T17.20 owner QA — RecoveryOneOrderPerBar_

- Default `false`: reproduce the same T17.19 settings; existing RH first-entry, lots, price, stages, SL/TP and re-entry semantics remain.
- `true`: at most one RH opening order per chart candle and Recovery direction. A Core DCA earlier in the candle does not delay the first RH.
- Open RH, close it via BE/SL in the same candle, then trigger G1 again: no second opening in that candle. If the closed RH opened in an earlier candle, re-entry may occur now under all existing gates.
- A generation transition and another child of the same stage must obey the same candle slot.
- BUY and SELL Recovery directions remain independent; Core DCA and Core Pyramid are not counted as RH.
- Restart or toggle ON with an RH opened/closed this candle: broker history must still block a duplicate. Missing series/history causes WAIT and retry, not a broker-error latch.
- On the next bar, retain current lot/price/cap/MinuteStop/SL and async journal rules. The new gate does not promise an order each candle.
- Test M1 and a larger chart timeframe, both sync and async, including partial fill/definite reject. Broker-owned partial fills of one submitted order remain one admission.
- Preserve the owner-log DD and SL-classification findings as known baseline behavior; this task intentionally does not fix them.
- Attach exact EX5 hash, input set, full tester report/log and actual date range. No compile/model result is owner runtime acceptance.

Release/forward/live/merge remain false.
