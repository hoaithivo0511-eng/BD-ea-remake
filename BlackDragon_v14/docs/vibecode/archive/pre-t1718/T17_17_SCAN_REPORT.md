# T17.17 SCAN Report

- Owner tester log `20260830.log` SHA256: `abb6accfe563fc5e07e57e47b5451fec5457cceef1a3c4951320891d787ba713`.
- Tester completed normally with final balance `10572.84`; the EA itself stopped submitting trades for roughly 69 model-hours.
- At `2026-08-26 02:53:25`, twelve exact Recovery Hedge positions closed by broker SL while an Overlap SELL close-cycle was active.
- Earlier expected ARCS broker SLs in the same run were classified correctly when no side coordinator cycle was active.
- The `!coordinatorOwned` gate therefore made a valid exact ARCS SL fall through to the generic non-EXPERT external-close classifier, latching Recovery and then Overlap RECONCILE.
- At `03:00`, `MoneyTPAllAccount=100` closed the account to verified flat and Recovery re-armed, but Overlap retained its RECONCILE state and consumed every later Strategy tick.
- The loaded EX5 size was `665185`, while the proven T17.16 artifact size was `665152`; without a runtime hash the owner log cannot be bound to the exact official EX5.
- Local MetaEditor and Strategy Tester are unavailable; Windows compile/native evidence must come from exact-head GitHub Actions and owner Strategy Tester remains pending.

