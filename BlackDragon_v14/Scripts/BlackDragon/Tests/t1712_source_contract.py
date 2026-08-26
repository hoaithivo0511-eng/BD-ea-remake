from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
INC=ROOT/'Include'/'BlackDragon'

def text(p):
    return p.read_text(encoding='utf-8')

policy=INC/'Recovery'/'RecoveryT1712EconomicPolicy.mqh'
assert policy.exists(), 'RED T17.12: recovery-aware economic policy header is missing'
p=text(policy)
for token in (
    'SRecoveryT1712ExitEconomicSnapshot',
    'Recovery_T1712ExitFundedPure',
    'Recovery_T1712ProjectedTpPure',
    'Recovery_T1712ProjectedPriceFundedPure',
    'Recovery_T1712NominalTargetCashPure',
    'Recovery_T1712CashSlopePerPricePure',
    'Recovery_T1712LiquidationReserveCashPure',
):
    assert token in p, f'RED T17.12: missing policy token {token}'

strategy=text(INC/'Strategy.mqh')
for token in (
    'RecoveryT1712EconomicPolicy.mqh',
    'BuildRecoveryExitSnapshotT1712',
    'RecoveryExitFundedT1712',
    'ProjectedRecoveryRealTpT1712',
    'ApplyRealLevelsT1712',
):
    assert token in strategy, f'RED T17.12 Strategy integration missing {token}'
assert 'd.kind == EXIT_TP || d.kind == EXIT_TRAIL' in strategy
assert 'Recovery_T1712ProjectedPriceFundedPure' in strategy
assert 'recoveryRealizedToday' not in p
assert 'rt.ledger.hedgeNetCash - rt.ledger.coreLossSpent' in strategy

coord=text(INC/'Recovery'/'RecoveryExitCoordinator.mqh')
for token in ('PrepareRealTpEpoch','ObserveRealTpSettlement','POSITION_IDENTIFIER','DEAL_REASON_TP','BlocksSameSideAdd'):
    assert token in coord, f'T17.9 regression: missing {token}'

overlap=text(INC/'Overlap'/'OverlapT177Coordinator.mqh')
for token in ('DriveArmedT1712','t1712pairwait','return overlap_T177_DRIVE_WAIT;'):
    assert token in overlap, f'RED T17.12 Overlap WAIT integration missing {token}'
wait_pos=overlap.find('t1712pairwait')
assert wait_pos>=0
wait_window=overlap[max(0,wait_pos-700):wait_pos+700]
assert 'ResetSide(idx)' not in wait_window

# Owner correction after Strategy Tester liveness failure:
# MoneyTPAllAccount is again a direct raw ACCOUNT_PROFIT close threshold.
money=text(INC/'MoneyGuard.mqh')
base=text(INC/'StrategyT176Base.mqh')
assert 'bool MG_MoneyTpHit' in money
assert 'profit >= tp' in money
assert 'eGuardAction action = m_guard.CheckFloatingPriority' in base
assert 'LatchGuard(action, ctx.now);' in base
assert 'return DriveGuardLatch(ctx, rg);' in base
assert 'if(ApplyGuardPriority(ctx))' in strategy
for forbidden in (
    'MG_AccountTpCloseReserveLegCashPure',
    'AccountTpExecutionReserveCashT1712',
    'AccountTpAdmissionReadyT1712',
    'm_guardAccountTpReserve',
    'm_guardAccountTpReserveRequired',
    'm_guardAccountTpAdmitted',
    'LatchGuardT1712',
    'DriveGuardLatchT1712',
    't1712tpaccwait',
    't1712tpaccmeta',
):
    assert forbidden not in money + strategy, f'RED MoneyTP immediate-close contract violated by {forbidden}'

engine=text(INC/'Recovery'/'RecoveryEngine.mqh')
assert 'm_initialized' in engine
assert 'if(!m_initialized) return true;' in engine

config=text(INC/'Config.mqh')
assert 'input group "T17.12' not in config
assert 'input double RecoveryExitEconomic' not in config
assert 'input double MoneyTpReserve' not in config

print('T17.12 SOURCE CONTRACT GREEN')
