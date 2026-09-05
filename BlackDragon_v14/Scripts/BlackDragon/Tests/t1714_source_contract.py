from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")

policy = read("Include/BlackDragon/Recovery/RecoveryT1714InterleavePolicy.mqh")
hardened = read("Include/BlackDragon/Recovery/RecoveryArcsStackHardened.mqh")
postdeal = read("Include/BlackDragon/Recovery/RecoveryArcsStackPostDealT162Base.mqh")
guard_policy = read("Include/BlackDragon/StrategyT1714GuardPolicy.mqh")
strategy = read("Include/BlackDragon/StrategyT176Base.mqh")
coordinator = read("Include/BlackDragon/Recovery/RecoveryExitCoordinatorT13Base.mqh")

checks = []
def ck(ok: bool, name: str):
    checks.append((ok, name))

ck("Recovery_T1714LayerRefreshPure" in policy,
   "exact protective layer refresh policy exists")
ck("provenProtectiveCloseUnits != observedCloseUnits" in policy,
   "partial and over-counted proof are rejected")
ck("RepairProtectiveLayerDecreases" in hardened and
   "Recovery_T1714LayerRefreshPure" in hardened,
   "runtime repair uses the locking pure policy")
ck("RefreshExpectedProtectiveCloseOwnership" in hardened,
   "hardened ARCS exposes exact protective ownership refresh")
ck("RefreshExpectedProtectiveCloseOwnership" in postdeal and
   postdeal.index("RefreshExpectedProtectiveCloseOwnership") < postdeal.index("ValidateLiveBook(dir, why)"),
   "post-Overlap finalizer repairs exact protective closes before validation")
ck("Strategy_T1714AccountGuardPreemptsRecoveryPure" in guard_policy,
   "account guard preemption policy exists")
ck("Strategy_T1714AccountGuardPreemptsRecoveryPure" in strategy,
   "Strategy dispatch uses account preemption policy")
ck("if(m_accountWidePending) return;" in coordinator,
   "global-flatten begin is idempotent across repeated guard ticks")
pending_open_at = strategy.find("if(pendingOpen)")
account_preempt_at = strategy.find("Strategy_T1714AccountGuardPreemptsRecoveryPure")
ck(pending_open_at >= 0 and account_preempt_at >= 0 and pending_open_at < account_preempt_at,
   "pending OPEN ordering remains ahead of account preemption")
ck("GUARD_CLOSE_BUY" in strategy and "GUARD_CLOSE_MAGIC" in strategy,
   "scoped guard coordinator paths remain present")

failed = [name for ok, name in checks if not ok]
for ok, name in checks:
    print(("PASS: " if ok else "FAIL: ") + name)
print(f"T17.14 source contract: {len(checks)-len(failed)} passed, {len(failed)} failed")
if failed:
    raise SystemExit(1)
print("ALL GREEN")
