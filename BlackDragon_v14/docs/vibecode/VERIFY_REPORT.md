# VERIFY REPORT — BlackDragon v14.7.1 BD-001 / BD-002

## Overall status

**IMPLEMENTATION VERIFIED OFFLINE — NEEDS MT5 VERIFY BEFORE LIVE**

BD-001 and the immediate REQUEST-unlock race of BD-002 are removed from source.
The result is not declared release-ready because MQL compilation, terminal
tests, golden baseline and broker async soak remain unavailable here, and other
P1 findings from the full deep review are out of scope.

## Test results

| Test | Result |
|---|---|
| Original offline baseline | 254/254 PASS |
| Updated offline suite | 277/277 PASS |
| UBSan | 277/277 PASS |
| ASan/LSan | UNTESTABLE: sandbox `/proc`/ptrace restriction |
| MQL `RunTests.mq5` | 9 additional source assertions; not executed |
| Brace/preprocessor balance | PASS, 20 MQL files |
| Trade API ownership | PASS: only `ExecutionLayer.mqh` |
| Chart object ownership | PASS: only `Panel.mqh` |
| `Sleep` in executable code | PASS: none |

## RRI-T scenarios

| ID | Scenario | Result |
|---|---|---|
| BD-D2-001 | Guard close and entry/DCA simultaneously eligible | PASS model/source |
| BD-D2-002 | Simultaneous BUY/SELL exits | PASS model/source |
| BD-D2-003 | Pending close on following tick | PASS model/source |
| BD-D2-004 | REQUEST accepted without resulting state | PASS |
| BD-D2-005 | REQUEST→DEAL→STATE | PASS |
| BD-D2-006 | DEAL→REQUEST→STATE | PASS |
| BD-D2-007 | State observed before REQUEST callback | PASS |
| BD-D5-008 | Partial close volume | PASS |
| BD-D7-009 | Rejected request | PASS |
| BD-D7-010 | Soft/hard watchdog | PASS |
| BD-D7-011 | D-chain empty test-the-test | PASS with real empty array |

## Performance

Five benchmark runs on the review host:

- BD-002 lifecycle predicate: 3.29–3.67 ns per event.
- BD-001 pending-close journal scan (0–8 entries): 3.39–4.57 ns per tick.
- Existing WMF/Grid/tick arithmetic values overlap the original build's
  run-to-run variation.

The first `OrderSendAsync` call is not delayed. Additional position scans run
on request/event/watchdog paths. Their real MT5 API cost cannot be measured by
the C++ harness.

## Technical review

- No lot, DCA, signal, TP/SL/trailing or overlap formula changed.
- No blocking waits or `Sleep` were added.
- Simultaneous side exits remain supported.
- DEAL alone cannot unlock the journal; resulting state is required.
- Inactive journal entries remain bounded by existing compaction behavior.

## Residual risks and required terminal tests

1. Compile v14.7.1 with MetaEditor: zero errors; triage every warning.
2. Run `RunTests.mq5`: ALL GREEN.
3. Run sync golden baseline against v13.
4. On demo hedging account, force callback permutations/delays where possible.
5. Disconnect/reconnect during open, close and SL/TP modify.
6. Verify partial fill and rejected request behavior.
7. Soak sync vs async for 2–4 weeks and compare deal logs.
8. Observe hard-timeout behavior; there must be no duplicate request.

## Retro

- Fixed the original test mirage: accepted callback is not resulting state.
- Tightened the first implementation during review so DEAL metadata also cannot
  unlock before position/SLTP visibility.
- Preserved test independence with explicit lifecycle evidence and
  close-volume pure functions.

