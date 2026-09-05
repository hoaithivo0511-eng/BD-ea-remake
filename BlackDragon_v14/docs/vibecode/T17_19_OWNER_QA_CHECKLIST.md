# T17.19 Owner QA Checklist

- Confirm `MaxRecoveryReentryCycles_=0` preserves terminal behavior without re-entry.
- Test BUY-Core and SELL-Core terminal positive protective closes separately.
- Confirm no new RH opens on the SL callback or before the reset buffer is reached.
- Confirm WAIT_RESET/ARMED blocks adverse Core DCA.
- With Core Pyramid enabled, confirm favorable ADD remains possible through all existing settings/gates during WAIT_RESET/ARMED.
- Return through the exact anchor and confirm the new RH starts as G1 using fresh Core volume and the configured Hedge Pyramid ladder.
- Restart MT5 in WAIT_RESET, ARMED and TRIGGER_PENDING; confirm exactly-once continuation.
- Exhaust the outer-cycle cap; confirm DCA and Pyramid ADD stop while Peel/close remain functional.
- Repeat with broker SL and virtual SL modes.
- Inspect gaps/slippage, margin waits, execution journal and re-entry telemetry.
- Record symbol, broker, account mode, MT5 build, `.set`, dates, ticks/model, deposit, leverage, spread and final report/log hashes.

Do not enable live trading from this checklist. Strategy Tester remains
`PENDING_OWNER` until the report and journal are reviewed.
