# T17.22 owner QA checklist

- Confirm the attached EX5 provenance matches the exact Draft PR HEAD/tree.
- Run `PyramidSLMode_=OFF` and compare behavior with T17.21 using the same set/history.
- Run `VIRTUAL` for BUY and SELL PY cohorts; verify one group trigger closes only PY after any required RH trim.
- Run `BROKER`; inspect every live PY ticket for the same monotone group SL and confirm the SL never weakens.
- Enable trailing and confirm BUY SL only rises and SELL SL only falls.
- Trigger a Core PY LIFO Peel while RH is open; verify `PY EXIT WAIT RH`, RH trim, PY close, then `PY EXIT SETTLED`.
- Restart while WATCH, PREPARE, ARMED and CLOSING; confirm exact member IDs, stop, operation and cash floor recover.
- Force reject/timeout/no-effect paths; confirm additions stay blocked until exact reconciliation.
- After partial PY close and full PY flat, confirm later PY starts a new serial and recalculates lots, weighted price and booked cash from fresh fills.
- Review `T17.22 PERF` counters; exposure/history scans must remain event or mutation bound, not one per quiet tick.
- Keep Strategy Tester, forward and live acceptance pending until owner signs the economic results.
