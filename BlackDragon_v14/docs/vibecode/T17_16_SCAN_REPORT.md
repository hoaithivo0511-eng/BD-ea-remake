# T17.16 SCAN Report

- Owner log SHA256: `887d7551f798d1a7f9d354d80d288e1cc0eb492067a5379bd83a6e1d32d5cad4`.
- Tester stopped at 12% after account stopout; 625 Recovery Hedge tickets, 612 Core Pyramid opens and five DCA `NO_MONEY` rejects were observed.
- One SELL G1 stage emitted 96 same-stage Hedge children while Core Pyramid repeatedly raised the denominator.
- A losing-Hedge lock message was followed by Core Pyramid ADD and immediate same-stage Recovery refill.
- Source root cause: `live > previousTarget` conflated broker-child continuation with a target raised by Core denominator growth.
- Capacity root cause: T17.11 latch was exact-DCA/per-bar; owner-aware Pyramid and Recovery OPEN APIs had no shared capacity state.
- Native Windows compile is available through GitHub Actions; local MetaEditor/Strategy Tester is unavailable.
