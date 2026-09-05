#!/usr/bin/env python3
"""T17.23 external-audit regression source contract."""
from pathlib import Path
import sys

REPO=Path(__file__).resolve().parents[4]
ROOT=REPO/'BlackDragon_v14'
INC=ROOT/'Include/BlackDragon'
WF=REPO/'.github/workflows/verify-current.yml'
checks=[]
def ck(ok,name): checks.append((bool(ok),name))
def rd(p): return Path(p).read_text(encoding='utf-8')

policy=rd(INC/'Pyramid/PyramidProtectionPolicy.mqh')
protect=rd(INC/'Pyramid/PyramidProtection.mqh')
wf=rd(WF)

ck('PyProtect_PrepareDecisionPure' in policy and
   'PY_PREPARE_WAIT_UNFUNDED' in policy,
   'F01 pure prepare outcome is explicit')
ck('PY_DRIVE_WAIT_UNFUNDED' in protect and
   'không ARM bằng candidate cũ' in protect,
   'F01 runtime has a distinct unfunded wait disposition')
wait=protect[protect.index('int PrepareBeforeArm('):protect.index('int DriveBrokerStops(')]
ck('m_group[d].phase=PY_PREPARE' in wait and
   'obligation=PyProtect_StrongerPure' in wait and 'm_group[d].candidate=obligation' in wait and
   'return PY_DRIVE_WAIT_UNFUNDED' in wait,
   'F01 unfunded state persists PREPARE candidate and cannot fall through to ARM')
ck('status==PY_DRIVE_ALLOW || status==PY_DRIVE_WAIT_UNFUNDED' in protect,
   'F01 wait yields the Strategy tick without globally deadlocking recovery')
fund=protect[protect.index('bool FundedPyramidAdd('):protect.index('bool AllowsPreparedDeal(')]
ck('m_group[d].phase==PY_PREPARE' in fund and
   'obligation=PyProtect_StrongerPure' in fund and
   'NetAt(d,obligation)' in fund,
   'F01 later PY add is charged against durable PREPARE obligation')
ck('OnDefinitiveReject' in protect and
   'PyProtect_RejectMatchesOperationPure' in protect and
   'EraseOperationAt(found);' in protect and
   'requestedSl=m_members[mi].confirmedSl' in protect,
   'F02 definitive reject consumes exact durable op and rolls back requested SL')
execution=rd(INC/'ExecutionLayer.mqh')
ck('g_pyramidProtection.OnDefinitiveReject' in execution and
   'm_journal[i].reconcileRequired=true' in execution and
   'definitive PY reject did not match durable operation' in execution,
   'F02 executor routes exact reject and fails closed if durable consumer is missing')
types=rd(INC/'Types.mqh')
ck('virtual bool OnDefinitiveReject' in types,
   'F02 reject callback is explicit in the optional PY adapter interface')
arcs=rd(INC/'Recovery/RecoveryArcsStack.mqh')
replay=arcs[arcs.index('bool ReplayAfterCursor('):arcs.index('bool ValidateLiveBook(')]
ck('eRecoveryCoreDirection dealDir=DirectionForClose(owner,type,mapped);' in replay and
   'if(!mapped || dealDir!=dir) continue;' in replay and
   replay.index('if(!mapped || dealDir!=dir) continue;') < replay.index('ArrayResize(replay, n + 1,128)'),
   'F03 replay filters exact direction before the deal can enter the batch')
ck('TrackCursor(dir, deal);' in arcs and
   'ReplayAfterCursor(recovery_CORE_BUY,why)' in arcs and
   'ReplayAfterCursor(recovery_CORE_SELL,why)' in arcs,
   'F03 retains durable per-direction cursors and both callback replay paths')
basket=rd(INC/'BasketManager.mqh')
ck('HistorySelectByPosition(s.pos[i].positionId)' in basket and
   'HistorySelectByPosition(s.pos[i].ticket)' not in basket and
   'bool TrySumCommission' in basket,
   'F05 commission history uses immutable position identifier')
ck('CommissionHistoryReady() const' in basket and
   'm_commissionBuyValid' in basket and 'm_commissionSellValid' in basket and
   'UseCommissionInBE && !commissionValid' in basket,
   'F05 history failure is explicit and cannot degrade to zero commission')
strategy=rd(INC/'Strategy.mqh')
ck('if(!m_basket.CommissionHistoryReady())' in strategy and
   strategy.index('if(!m_basket.CommissionHistoryReady())') >
   strategy.index('if(ApplyExitT177(ctx, m_basket.sell, BD_DIR_SELL))') and
   strategy.index('if(!m_basket.CommissionHistoryReady())') <
   strategy.index('if(m_pyramid != NULL)'),
   'F05 keeps risk-reducing exits ahead of fail-closed risk-add gate')
entry=rd(ROOT/'Experts/BlackDragon/BlackDragon.mq5')
# T17.24 moves the reducer into a shared production class. The common fixture
# executes this exact class for both ownership scopes (not a mirrored model).
cash=rd(INC/'CashLedger.mqh')
ck('CScopedDayCashLedger m_dayCash' in basket and
   'm_dayCash.Observe(deal,TimeCurrent())' in basket and
   'HistoryDealGetDouble(deal,DEAL_FEE)' in cash and
   'g_basket.OnDealCash(trans.deal' in entry,
   'F04 seed and callback use one net cash scope including fee')
ck('DEAL_ENTRY_IN' in cash and 'DEAL_ENTRY_OUT' in cash and
   'DEAL_ENTRY_INOUT' in cash and 'DEAL_ENTRY_OUT_BY' in cash and
   'ArrayResize(m_deals,0)' in cash and
   'm_cash+=cash-m_deals[at].cash' in cash,
   'F04 covers entry/exit/close-by cash and deduplicates exact deal ids per day')
ck('OnDealClosed' not in basket and
   'DEAL_ENTRY) == DEAL_ENTRY_OUT' not in entry,
   'F04 legacy close-only day accounting path is removed')
adx=rd(INC/'Filters/AdxFilter.mqh')
ck('CopyBuffer(m_handle, 0, 1, 1, adx) != 1' in adx and
   'return false;' in adx and
   'return true;   // fail-open' not in adx,
   'F07 ADX data failure blocks new-series admission')
ck('T17.23 ADX filter enabled nhưng init thất bại — fail closed' in entry and
   'return INIT_FAILED;' in entry,
   'F07 enabled ADX init failure aborts initialization instead of bypassing filter')
ck('PyProtect_StateCountAllowedPure(ArraySize(m_members))' in protect and
   'PyProtect_StateCountAllowedPure(ArraySize(m_ops))' in protect and
   'PyProtect_StateCountAllowedPure(h.members)' in protect and
   'PyProtect_StateCountAllowedPure(h.operations)' in protect,
   'F06 writer and loader enforce the same state-count bound')
ck('CompactTerminalNonRhOperations' in protect and
   'if(op.kind!=EXEC_CMD_PY_RH_TRIM) EraseOperationAt(i);' in protect and
   'EraseOperationAt(found);' in protect and
   'operation state đạt hard cap' in protect and
   'member state đạt hard cap' in protect,
   'F06 no-effect/non-RH terminal operations compact and append paths are bounded')
ck('CompactStaleMembersBeforeBind();' in protect and
   protect.index('CompactStaleMembersBeforeBind();') <
   protect.index('BindSide(m_basket.buy,0,m_buy)'),
   'F06 stale member tombstones compact before either side binding is indexed')
ck(all(x in wf for x in ['t1723_audit_regression_model.cpp',
                         't1723_source_contract.py',
                         'RunT1723AuditRegressionTests']),
   'canonical workflow enrolls T17.23 model source and native gates')

fails=[n for ok,n in checks if not ok]
print(f'T17.23 source contract: {len(checks)-len(fails)} passed, {len(fails)} failed')
for n in fails: print('FAIL:',n)
if fails: sys.exit(1)
print('ALL GREEN')
