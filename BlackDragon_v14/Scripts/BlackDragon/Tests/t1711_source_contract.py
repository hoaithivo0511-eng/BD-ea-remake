from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
INC = ROOT / "Include" / "BlackDragon"
EA = ROOT / "Experts" / "BlackDragon" / "BlackDragon.mq5"


def check(name: str, condition: bool) -> bool:
    if not condition:
        print(f"FAIL {name}")
    return condition


def main() -> int:
    arcs = (INC / "Recovery" / "RecoveryArcsStackT177HedgeLadder.mqh").read_text(encoding="utf-8")
    base = (INC / "Recovery" / "RecoveryArcsStack.mqh").read_text(encoding="utf-8")
    policy163 = (INC / "Recovery" / "RecoveryT163Policy.mqh").read_text(encoding="utf-8")
    engine = (INC / "Recovery" / "RecoveryEngine.mqh").read_text(encoding="utf-8")
    dca = (INC / "Recovery" / "RecoveryDca.mqh").read_text(encoding="utf-8")
    execution = (INC / "ExecutionLayer.mqh").read_text(encoding="utf-8")
    strategy = (INC / "StrategyT176Base.mqh").read_text(encoding="utf-8")
    types = (INC / "Types.mqh").read_text(encoding="utf-8")
    filters = (INC / "EntryFilters.mqh").read_text(encoding="utf-8")
    oninit = EA.read_text(encoding="utf-8")

    results = [
        check("R11-01 no global BUY passive early return",
              "if(TryYieldStableActiveTpWaitT178(recovery_CORE_BUY, ctx, why)) return false;" not in arcs),
        check("R11-01 stable PrepareTp read-only",
              "Recovery_T1711ActiveTpSnapshotChangedPure" in base),
        check("R11-02 terminalNoHedge authoritative predicate",
              "Recovery_T1711TerminalNoHedgePure" in policy163 and "TerminalNoHedge" in engine),
        check("R11-02 DCA consumes explicit terminal status",
              "TerminalNoHedge" in dca and "terminalNoHedge" in dca and "m_recovery->" not in dca),
        check("R11-03 complete validator exists",
              all(token in dca for token in ["Recovery_ValidateCompleteConfig", "Recovery_ValidateT5Config", "Recovery_ValidateT6Config", "Recovery_T16ValidateConfig"])),
        check("R11-03 OnInit uses complete validator",
              "Recovery_ValidateCompleteConfig" in oninit),
        check("R11-04 typed legacy open outcome",
              all(token in execution for token in ["OpenMarketOutcome", "EXEC_SUBMIT_CAPACITY_BLOCKED", "TakeLegacyCapacityReject", "RecordLegacyCapacityRejectAt"]) and
              "#define BD_DIR_BUY  0" in types and "#define BD_DIR_SELL 1" in types and
              "#define BD_DIR_BUY" not in filters and "#define BD_DIR_SELL" not in filters),
        check("R11-04 strategy capacity latch",
              "m_capacityLatch" in strategy and "Recovery_T1711CapacityLatchBlocksPure" in strategy),
    ]
    passed = sum(results)
    failed = len(results) - passed
    print(f"T17.11 source contract: {passed} passed, {failed} failed")
    if failed == 0:
        print("ALL GREEN")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
