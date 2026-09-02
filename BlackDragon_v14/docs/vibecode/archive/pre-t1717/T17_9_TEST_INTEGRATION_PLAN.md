# T17.9 Test / Integration Plan

The independent model and native script simulate four old Core identifiers sharing one REAL TP. A fifth Core/Pyramid add becomes eligible at the hit boundary, then callbacks for the four old identifiers interleave with scheduler observations.

Assertions:

- the hit observation freezes settlement before the add decision;
- all four old identifiers classify as expected broker TP even when a newer live Core has another TP;
- no Seed/DCA/Core-Pyramid add is submitted while the side barrier is active;
- no callback takes the external/manual path, reconciliation path or tester-stop path;
- vanished cached tickets are rejected before modify submission;
- after all epoch members and Recovery exposure settle, the barrier clears and a later campaign may start.

Native CI compiles `RunT179RealTpTests.mq5` and the full EA with 0 errors / 0 warnings, executes the focused script, then the final workflow replays the established T1–T17 suites from the exact final head.

