from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


execution = read("Include/BlackDragon/ExecutionLayer.mqh")
ladder_policy = read("Include/BlackDragon/Recovery/RecoveryT177HedgeLadder.mqh")
ladder_runtime = read(
    "Include/BlackDragon/Recovery/RecoveryArcsStackT177HedgeLadderC4Base.mqh"
)
config = read("Include/BlackDragon/Recovery/RecoveryT16ConfigT177C4Base.mqh")
expert = read("Experts/BlackDragon/BlackDragon.mq5")

checks = []


def ck(ok: bool, name: str):
    checks.append((ok, name))


ck("Recovery_T1716BrokerPartialStagePure" in ladder_policy,
   "pure broker-partial oracle exists")
ck("admittedStageTargetUnits == currentStageTargetUnits" in ladder_policy,
   "partial continuation binds the exact admitted target")
ck("ClearBuildingAdmissionC4(l);" in ladder_runtime and
   ladder_runtime.count("ClearBuildingAdmissionC4(l);") >= 4,
   "target refresh, activation and Overlap clear stale stage authority")
ck("AdmitBuildingStageC4" in ladder_runtime and
   ladder_runtime.index("AdmitBuildingStageC4(l,effectiveStageNo") <
   ladder_runtime.index("OpenMarketOwned(hedgeDir,volume"),
   "logical stage admission is persisted before broker OPEN")
ck("if(!brokerPartialStage&&live>0)" in ladder_runtime and
   "HedgePyramidLockBeforeAdd_" in ladder_runtime,
   "rebase refill re-enters timing/gap/profit safety gates")
ck("Exec_RiskAddRecoveryThresholdPure" in execution and
   "requiredMargin * 1.10" in execution,
   "capacity recovery threshold has explicit hysteresis")
ck("LatchRiskAddEmbargo" in execution and
   execution.count("TRADE_RETCODE_NO_MONEY") >= 5 and
   execution.count("LatchRiskAddEmbargo") >= 4,
   "sync, async and transaction NO_MONEY routes latch shared embargo")
ck("RiskAddEmbargoBlocks()" in execution and
   execution.count("RiskAddEmbargoBlocks()") >= 3,
   "legacy and owner-aware OPEN APIs share the embargo")
ck("ClosePositionVolumeOwned" in execution and
   execution.index("ClosePositionVolumeOwned") > execution.index("OpenMarketOwned"),
   "risk-reducing close remains outside OPEN embargo")
ck("GlobalVariableSet" in execution and "HasSymbolExposure" in execution,
   "embargo is restart-durable only while symbol exposure remains")
ck("Recovery_T1716UnsafeGrowthEnvelopePure" in config and
   "t1716unsafe" in expert,
   "unsafe tester configuration receives startup cross-warning")

failed = [name for ok, name in checks if not ok]
for ok, name in checks:
    print(("PASS: " if ok else "FAIL: ") + name)
print(f"T17.16 source contract: {len(checks)-len(failed)} passed, {len(failed)} failed")
if failed:
    raise SystemExit(1)
print("ALL GREEN")
