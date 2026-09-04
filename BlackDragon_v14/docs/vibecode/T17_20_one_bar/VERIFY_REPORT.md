# T17.20 verification guide

`RecoveryOneOrderPerBar_` is a bool input in Recovery group 16, default false.
OFF retains the original opening path. ON checks the current chart candle,
symbol, RecoveryMagic and RH direction before each RH opening admission.
An RH opening remains counted after BE/SL closes it; resetting generation state
does not erase that opening from broker history. Core DCA/Pyramid orders do not
consume the RH slot. The first RH retains its existing trigger when the slot
is free. All existing lot, price, coverage, NewCycle, timing and exit rules remain.

The shared gate is inserted before durable opening admission at every production
RH opening site. It reads current broker positions and opening deal history.
Data unavailable means WAIT; it does not introduce a new execution-error latch.
The implementation adds no persistence schema or retained cache.

Verification sources:

- `t1720_one_bar_model.cpp` executes the actual runtime gate with controlled
  broker/series inputs, including closed positions, restart reconstruction,
  candle boundaries, opposite direction, rejection, and missing evidence.
- `RunT1720RhOneBarTests.mq5` checks the pure admission/ownership policy natively.
- `t1720_source_contract.py` checks gate placement, disabled-path behavior and
  preservation of the existing production calculations.
- The current CI workflow compiles and runs the existing regression matrix plus
  the new cases on the exact branch head.
- `OWNER_QA_CHECKLIST.md` describes remaining broker/restart acceptance cases.

Detailed execution evidence is delivered separately to the owner. This public
file contains no private VPS/job identifiers, execution timestamps, artifact
hashes, host metadata or runtime audit payload.

This input controls opening timing only. Earlier RH drawdown/coverage and
protective-SL audit changes are excluded by the owner's instruction.
Release, forward, live and merge remain disabled; the PR remains Draft.
