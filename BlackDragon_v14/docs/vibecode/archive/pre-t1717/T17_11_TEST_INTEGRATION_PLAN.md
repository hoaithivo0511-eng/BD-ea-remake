# T17.11 TEST / INTEGRATION PLAN

## Focused deterministic cases

- Scheduler: BUY passive/SELL actionable, mirror, both passive, passive/opposite idle, TP hit, pending/reconcile precedence.
- Terminal no-Hedge: exact max boundary, pre-max rejection, zero Core rejection, non-locked rejection, Continue true/false, live-Hedge metrics unchanged.
- Validation: partial `150`, `0`, negative reject; `100` pass; negative TP, invalid CoreClose and invalid T6 reject; OFF parity.
- Admission: first NO_MONEY latches; same bar blocks; next bar retries once; new index, smaller volume and sufficient free margin release; accepted result clears; directions independent; transient price result does not capacity-latch.

## Required commands

```text
g++ -std=c++17 -O2 -Wall -Wextra t1711_runtime_model.cpp
python t1711_source_contract.py
all existing C++ model suites
MetaEditor RunT1711RuntimeTests.mq5 + BlackDragon.mq5: 0/0
native RunT1711RuntimeTests: 0 failed
all established T1-T17.10 workflows on exact final HEAD
```

Strategy Tester fixtures remain owner-only evidence and are listed in the owner checklist.

## Red baseline

At exact baseline `e0ad9c59bac25e3e194d7bd917a80864cf4eecd9`, the focused
source contract was intentionally RED at `0 passed / 8 failed` (two checks for
each contracted runtime defect). Green acceptance is `8/0` plus the independent
runtime model and native suite; the red result is not waived or replaced by a
post-hoc source assertion.
