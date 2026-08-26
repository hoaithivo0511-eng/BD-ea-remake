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

# T17.12 composes over the frozen T17.6 base in the public T17.7+ Strategy wrapper.
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
assert 'recoveryRealizedToday' not in p, 'T17.12 cycle exit policy must not substitute day-realized Recovery cash'
assert 'rt.ledger.hedgeNetCash - rt.ledger.coreLossSpent' in strategy

# T17.9 durable REAL-TP cohort/settlement contract remains present.
coord=text(INC/'Recovery'/'RecoveryExitCoordinator.mqh')
for token in ('PrepareRealTpEpoch','ObserveRealTpSettlement','POSITION_IDENTIFIER','DEAL_REASON_TP','BlocksSameSideAdd'):
    assert token in coord, f'T17.9 regression: missing {token}'

# P1-B: temporarily unsafe economics must preserve the durable pair instead of ResetSide -> re-arm churn.
overlap=text(INC/'Overlap'/'OverlapT177CoordinatorT177C3Base.mqh')
needle='if(!Overlap_T177PreLeg1EligiblePure(side.count, OverlapOrderNumber, Overlap,'
pos=overlap.find(needle)
assert pos>=0, 'Overlap pre-leg1 economics gate missing'
window=overlap[pos:pos+900]
assert 'ResetSide(idx)' not in window, 'RED T17.12: unsafe Overlap economics still resets durable pair'
assert 'return overlap_T177_DRIVE_WAIT;' in window

# P1-C: account TP gets an account-scope close reserve without changing raw trigger semantics.
money=text(INC/'MoneyGuard.mqh')
assert 'bool MG_MoneyTpHit' in money
assert 'MG_AccountTpCloseReserveLegCashPure' in money
base=text(INC/'StrategyT176Base.mqh')
assert 'AccountTpExecutionReserveCashT1712' in base
assert 'm_guardAccountTpReserve' in base

# P2-D: invalid init must make recovery persistence flush a no-op.
engine=text(INC/'Recovery'/'RecoveryEngine.mqh')
assert 'm_initialized' in engine
assert 'if(!m_initialized) return true;' in engine

# Frozen user-facing semantics: no T17.12 inputs are introduced.
config=text(INC/'Config.mqh')
assert 'input group "T17.12' not in config
assert 'input double RecoveryExitEconomic' not in config
assert 'input double MoneyTpReserve' not in config

print('T17.12 SOURCE CONTRACT GREEN')
