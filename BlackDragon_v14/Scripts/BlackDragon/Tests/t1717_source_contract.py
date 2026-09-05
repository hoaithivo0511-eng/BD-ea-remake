from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


policy = read("Include/BlackDragon/Recovery/RecoveryT1717StopLivenessPolicy.mqh")
coord = read("Include/BlackDragon/Recovery/RecoveryExitCoordinatorT177Base.mqh")
overlap = read("Include/BlackDragon/Overlap/OverlapT177Coordinator.mqh")
strategy = read("Include/BlackDragon/Strategy.mqh")
config = read("Include/BlackDragon/Config.mqh")

checks = []


def ck(ok: bool, name: str):
    checks.append((ok, name))


ck("owner != RECOVERY_T1717_OWNER_ACCOUNT" in policy,
   "exact SL bypass excludes account-wide authority")
ck("Recovery_T1717CoordinatorOwnerPure(m_accountWidePending" in coord and
   "m_cycle[idx].active" in coord,
   "runtime distinguishes side and account coordinator ownership")
ck("T16ExpectedBrokerSlDeal(trans.deal)" in coord and
   "Recovery_T1717ExpectedArcsSlBypassPure" in coord,
   "exact ARCS identity drives bypass")
ck("return false;" in coord[coord.index("T17.17 expected ARCS Broker SL"):],
   "expected SL reaches ARCS deal accounting")
ck("Recovery_ExitExternalDealReason(reason)" in coord,
   "generic unknown broker close remains fail closed")
ck("FinalizeConfirmedAccountWideFlat" in overlap and
   "PositionsTotal()" in overlap and "m_exec.HasPending()" in overlap and
   "m_recoveryExit.HasBlockingWork()" in overlap,
   "Overlap reset revalidates account execution and Recovery quiet")
ck("SOverlapT177Side oldBuy" in overlap and
   "m_globalReconcile = oldGlobalReconcile" in overlap,
   "failed persistence restores fail-closed Overlap state")
ck("guardBefore == GUARD_CLOSE_ACCOUNT" in strategy and
   "m_guardLatched == GUARD_NONE" in strategy,
   "reset authority is exact completed account guard transition")
ck("m_guardLatched = GUARD_CLOSE_ACCOUNT" in strategy and
   "Recovery_T1717RelatchAccountGuardPure" in strategy,
   "reset failure remains retryable under account guard")
ck("Strategy remains closed for completion tick" in strategy,
   "verified reset does not reopen on same tick")
ck("input " not in policy and config.count("input ") > 0,
   "T17.17 adds no public input")

failed = [name for ok, name in checks if not ok]
for ok, name in checks:
    print(("PASS: " if ok else "FAIL: ") + name)
print(f"T17.17 source contract: {len(checks)-len(failed)} passed, {len(failed)} failed")
if failed:
    raise SystemExit(1)
print("ALL GREEN")
