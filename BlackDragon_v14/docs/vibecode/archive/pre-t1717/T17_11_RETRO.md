# T17.11 RETRO — Runtime liveness and admission

## Outcome

The four baseline defects are locked by deterministic source/model tests and a
dedicated native suite. The implementation stays inside Recovery scheduling,
configuration admission and legacy Core/DCA submission feedback; no strategy,
unit-profile, input or persisted-state semantic changed.

## Red-to-green record

At baseline `e0ad9c59bac25e3e194d7bd917a80864cf4eecd9`, the focused source contract
reported `0 passed / 8 failed`: two independent checks for each R11-01..R11-04.
After implementation it reports `8 passed / 0 failed`; the independent runtime
model reports `25 passed / 0 failed`.

## Lessons converted to guards

- A per-direction passive state must never own a global scheduler return.
- A stable read-only wait must not produce persistence writes merely to make
  progress appear visible.
- Terminal topology must be derived from authoritative generation, phase and
  live Core/Hedge facts; log text and compatibility projections are not state.
- Adding a validator is incomplete until the active top-level initializer
  composes it before mutation.
- Execution must return a typed broker disposition when callers need admission
  policy. A boolean cannot distinguish capacity from transport or rejection.
- Capacity suppression belongs to the Core/DCA strategy intent that owns it,
  not to global execution or Recovery-owned commands.

These guards are permanent regression requirements. Strategy Tester remains
`PENDING OWNER`; deterministic/native PASS does not establish release or live
eligibility.
