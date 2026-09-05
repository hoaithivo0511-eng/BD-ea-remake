from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")

policy = read("Include/BlackDragon/Recovery/RecoveryMutationPolicy.mqh")
execution = read("Include/BlackDragon/ExecutionLayer.mqh")
exit_base = read("Include/BlackDragon/Recovery/RecoveryExitCoordinatorT13Base.mqh")
exit_coord = read("Include/BlackDragon/Recovery/RecoveryExitCoordinatorT177Base.mqh")
overlap = read("Include/BlackDragon/Overlap/OverlapT177CoordinatorT177C3Base.mqh")
ladder = read("Include/BlackDragon/Recovery/RecoveryArcsStackT177HedgeLadderC4Base.mqh")

checks = []
def ck(ok: bool, name: str):
    checks.append((ok, name))

ck("Recovery_OverlapCapabilityPolicyPure" in policy and
   "state == recovery_HEDGE_BUILDING" in policy,
   "capability policy explicitly admits quiet HEDGE_BUILDING")
ck("recoveryMutationPending" in policy and "journalMutationPending" in policy and
   "coordinatorPending" in policy,
   "capability policy names all mutation blockers")
ck("Recovery_OverlapRetainedWithinHardCapPure" in policy,
   "projected retained-Hedge hard-cap oracle exists")
ck("HasPendingMutation" in execution,
   "ExecutionLayer exposes read-only unresolved-mutation capability")
ck("OverlapCapabilityPolicy" in exit_base and
   "HasPendingMutation" in exit_base and
   "HasDurableCommand" in exit_base,
   "Recovery exit coordinator derives capability from live journals")
ck("Recovery_OverlapRetainedWithinHardCapPure" in exit_coord and
   exit_coord.index("Recovery_OverlapRetainedWithinHardCapPure") <
   exit_coord.index("m_cycle[idx].active          = true"),
   "projected hard cap is checked before Overlap close cycle is latched")
ck("OverlapCapabilityPolicy" in overlap and
   "Recovery_OverlapPolicyPure(cycle.state)" not in overlap,
   "Overlap route uses runtime capability instead of state-only policy")
ck("FinalizeExpectedOverlapMutation" in ladder and
   "BuildExecutablePlanC4" in ladder and
   "post-Overlap target refresh" in ladder,
   "C4 finalizer recomputes the active BUILDING ladder target after trim")
ck("Recovery_OverlapRetainedWithinHardCapPure" in ladder,
   "post-trim finalizer verifies retained Hedge hard cap")

failed=[name for ok,name in checks if not ok]
for ok,name in checks:
    print(("PASS: " if ok else "FAIL: ")+name)
print(f"T17.15 source contract: {len(checks)-len(failed)} passed, {len(failed)} failed")
if failed:
    raise SystemExit(1)
print("ALL GREEN")
