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
   'm_group[d].candidate=PyProtect_StrongerPure' in wait and
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
   'm_ops[found].complete=true' in protect and
   'requestedSl=m_members[mi].confirmedSl' in protect,
   'F02 definitive reject terminates exact durable op and rolls back requested SL')
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
   replay.index('if(!mapped || dealDir!=dir) continue;') < replay.index('ArrayResize(replay, n + 1);'),
   'F03 replay filters exact direction before the deal can enter the batch')
ck('TrackCursor(dir, deal);' in arcs and
   'ReplayAfterCursor(recovery_CORE_BUY,why)' in arcs and
   'ReplayAfterCursor(recovery_CORE_SELL,why)' in arcs,
   'F03 retains durable per-direction cursors and both callback replay paths')
ck(all(x in wf for x in ['t1723_audit_regression_model.cpp',
                         't1723_source_contract.py',
                         'RunT1723AuditRegressionTests']),
   'canonical workflow enrolls T17.23 model source and native gates')

fails=[n for ok,n in checks if not ok]
print(f'T17.23 source contract: {len(checks)-len(fails)} passed, {len(fails)} failed')
for n in fails: print('FAIL:',n)
if fails: sys.exit(1)
print('ALL GREEN')
