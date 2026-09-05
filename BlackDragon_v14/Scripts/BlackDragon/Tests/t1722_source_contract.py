#!/usr/bin/env python3
"""T17.22 structural contract for Core-PY group protection and PY-RH settlement."""
from pathlib import Path
import json,re,sys

REPO=Path(__file__).resolve().parents[4]
ROOT=REPO/'BlackDragon_v14'
INC=ROOT/'Include/BlackDragon'
ENTRY=ROOT/'Experts/BlackDragon/BlackDragon.mq5'
DOC=ROOT/'docs/vibecode/T17_22_py_protection'
WF=REPO/'.github/workflows/verify-current.yml'
checks=[]
def ck(ok,name): checks.append((bool(ok),name))
def rd(path): return Path(path).read_text(encoding='utf-8')

config=rd(INC/'Config.mqh'); types=rd(INC/'Types.mqh'); basket=rd(INC/'BasketManager.mqh')
policy=rd(INC/'Pyramid/PyramidProtectionPolicy.mqh')
protect=rd(INC/'Pyramid/PyramidProtection.mqh')
corepy=rd(INC/'Pyramid/CorePyramid.mqh'); execution=rd(INC/'ExecutionLayer.mqh')
strategy=rd(INC/'Strategy.mqh'); arcs=rd(INC/'Recovery/RecoveryArcsStack.mqh')
hardened=rd(INC/'Recovery/RecoveryArcsStackHardened.mqh')
reentry=rd(INC/'Recovery/RecoveryArcsStackT1719Reentry.mqh')
coord=rd(INC/'Recovery/RecoveryExitCoordinatorT177Base.mqh')
post=rd(INC/'Recovery/RecoveryArcsStackPostDealT162Base.mqh')
engine=rd(INC/'Recovery/RecoveryEngine.mqh'); entry=rd(ENTRY); wf=rd(WF)

defaults={
 'PyramidSLMode_':'py_protect_OFF', 'PyramidBETriggerPips_':'10.0',
 'PyramidLockProfitPips_':'3.0', 'PyramidLockSafetyPips_':'1.0',
 'PyramidTrailGapPips_':'0.0'}
for name,value in defaults.items():
    ck(re.search(rf'input\s+[^;\n]*\b{re.escape(name)}\s*=\s*{re.escape(value)}\s*;',config) is not None,
       f'default locked {name}={value}')
ck('py_protect_OFF=0' in config and 'py_protect_VIRTUAL=1' in config and 'py_protect_BROKER=2' in config,
   'explicit OFF VIRTUAL BROKER modes')
ck('if(!Enabled()) return;' in protect and 'if(!Enabled())' in protect,'OFF short-circuits adapter')

ck('bool     isPyramid;' in types and 'ulong    positionId;' in types,'basket carries exact PY role and immutable identity')
ck('OC_IsPyramid(PositionGetString(POSITION_COMMENT))' in basket and 'POSITION_IDENTIFIER' in basket,
   'existing basket scan classifies PY and binds position identifier')
ck('Snapshot(m_basket.buy,0,m_buy)' in protect and 'Snapshot(m_basket.sell,1,m_sell)' in protect,
   'BUY and SELL PY groups are independent')
ck('if(!side.pos[i].isPyramid) continue;' in protect and 'm_members[member].serial=m_group[dir].serial' in protect,
   'group membership is PY-only and episode-bound')
ck('m_group[dir].serial++' in protect and 'm_members[i].serial!=m_group[d].serial' in protect,
   'fresh episode excludes old realized member cash')

ck(all(x in policy for x in ['PyProtect_LockPricePure','PyProtect_StrongerPure','PyProtect_HitPure',
                              'PyProtect_NetAtPricePure','PyProtect_CapUnitsPure','PyProtect_AddFundedPure',
                              'PyProtect_ExpectedBrokerSlPure']),
   'pure price cash cap and ADD policies exist')
ck('return dir==0 ? MathMax(previous,candidate) : MathMin(previous,candidate);' in policy,
   'BUY stop rises and SELL stop falls only')
ck('bookedCash+liveSwap-exitReserve' in policy and
   'HistoryDealGetDouble(deal,DEAL_COMMISSION)+HistoryDealGetDouble(deal,DEAL_FEE)' in protect,
   'net floor includes exact booked cash swap commission fee and reserve')
ck('m_snap[d].floating+m_snap[d].booked-Reserve' in protect and
   'PyramidBETriggerPips_*unitCash' in protect,'arming uses total current PY group net')
ck('candidate=PyProtect_StrongerPure(d,m_group[d].stop,candidate)' in protect and
   'm_group[d].floorCash=MathMax(required,NetAt(d,candidate))' in protect,
   'price stop and cash floor cannot weaken')
ck('PyramidTrailGapPips_>0' in protect and 'm_group[d].peak' in protect,
   'trailing is optional and reuses monotone stop')
ck('m_group[d].phase==PY_PREPARE && m_group[d].candidate>0' in protect and
   'PyProtect_StrongerPure(d,m_group[d].candidate,coverage)' in protect,
   'PREPARE keeps a durable candidate and raises it only for fresh cost coverage')
ck('PyProtect_AddFundedPure' in protect and
   ('m_group[d].stop>0' in protect or 'm_group[view.dir].stop>0' in protect),
   'later PY ADD cannot spend protected cash floor')
ck('DriveFlatSettlement' in protect and
   'hedge-PyProtect_CapUnitsPure(core,reserved,CapPct())' in protect and
   'T1722FinalizePyMutation' in protect,
   'autonomous PY flatten trims RH against fresh denominator before finalization')

observe=protect[protect.index('void Observe(const EAContext'):protect.index('void OnTransaction(',protect.index('void Observe(const EAContext'))]
ck('PositionsTotal(' not in observe and 'HistorySelect' not in observe,
   'quiet Observe performs no whole-account or history scan')
ck('m_basketRevision!=m_basket.Revision()' in observe and 'm_historyDirty' in observe,
   'snapshot/history refresh is revision and event driven')
ck('m_historyRefreshes++' in protect and 'm_exposureScans++' in protect and
   'T17.22 PERF | observe=' in protect,'runtime scan counters are emitted')
ck('g_pyProtection.ReportPerformance()' in entry,'performance report is bound to deinit')
ck('m_statsRevision[dir]==g_pyramidDealRevision' in corepy and
   'm_statsRevision[dir] = g_pyramidDealRevision' in corepy,
   'Core PY history cache is event revision keyed')

start=protect[protect.index('bool StartOperation('):protect.index('bool SettleOperation(')]
ck(start.index('if(!Save()) return false;') < start.index('ModifySlTpOwned(') and
   start.index('if(!Save()) return false;') < start.index('ClosePositionVolumeOwned('),
   'durable intent is saved before every broker side effect')
ck(all(x in types for x in ['EXEC_CMD_PY_PROTECT_CLOSE','EXEC_CMD_PY_PROTECT_MODIFY','EXEC_CMD_PY_RH_TRIM']),
   'executor has distinct PY protection command identities')
ck('Exec_ModifyProofMatchesCommand' in execution and 'EXEC_CMD_PY_PROTECT_MODIFY' in protect,
   'requested broker SL requires exact executor proof until confirmed')
ck('confirmed>0 && MathAbs(programmed-confirmed)' in policy and 'DEAL_REASON_SL' in protect,
   'durable confirmed SL identifies delayed broker SL fills')
ck('groupSerial!=memberSerial' in policy and
   'retains the current-serial member as a' in protect and
   'tombstone' in protect and
   'PyProtect_ExpectedBrokerSlPure(true,m_group[d].serial,m_members[i].serial' in protect and
   'requestedSl was persisted before the broker side effect' in protect,
   'same-event and delayed broker SL use durable price proof scoped by episode')
ck('ExpectedT1722PySl(mapped,ownerMagic,trans.deal)' in coord and
   'g_pyramidProtection.ExpectedPySl(deal)' in coord,
   'only exact PY broker SL bypasses generic external-close latch')
ck('SetExitOverride(true)' in strategy and 'if(ApplyGuardPriority(ctx))' in strategy,
   'account emergency remains higher priority than group protection')
ck('PreserveSl(ticket,sl)' in strategy and 'OwnsSl(req.position)' in protect,
   'legacy real-level writer cannot erase independent PY SL')

ck('releaseTicket' in protect and 'PY EXIT WAIT RH' in protect and
   'meta.commandType==EXEC_CMD_CORE_PYRAMID_CLOSE' in protect,
   'standalone Core PY exit is durably coordinated with RH')
ck('PyProtect_CapUnitsPure(coreNow-release,reservedNow-release,CapPct())' in protect,
   'standalone exit reserves the exact post-PY exposure denominator')
ck('PyProtect_CapUnitsPure(core,reserved,CapPct())' in protect and
   'if(core<=reserved || capPct<=0) return 0;' in policy,
   'group exit cap excludes all PY units that can close autonomously')
ck('EXEC_CMD_PY_RH_TRIM' in protect and 'SelectTrim(d,excess' in protect,
   'RH excess is reduced before PY exit/stop authority')
ck('ExpectedRhTrim(deal)' in arcs and 'l.realizedOtherCash += cash' in arcs and
   'l.realizedFundingCash += cash' in arcs,'RH trim cash is separate from RH funding cash')
ck('l.tpBaselineUnits=l.tpBaselineUnits>units ? l.tpBaselineUnits-units : 0' in arcs,
   'coordinator trim cannot fabricate RH TP funding units')
ck('ExpectedRhTrim(trans.deal)' in hardened and 'ExpectedRhTrim(trans.deal)' in reentry,
   'expected RH trim bypasses generic mutation and RHSL re-entry classification')
ck('CoordinationCash(dir)' in strategy and 'campaignTrimCash' in protect,
   'PY-funded RH coordination cash enters whole-cycle economics once')

ck('DEAL_TIME_MSC' in arcs and 'priorMsc==keyMsc && replay[j]<key' in arcs,
   'replay is deterministically sorted by time_msc and ticket')
ck('CursorAfter(' in arcs and 'TrackCursor(dir, deal)' in arcs,
   'deal replay is exactly-once per durable direction cursor')
ck(protect.count('T1722FinalizePyMutation')>=3 and 'ValidateLiveBook' in post and 'RebaseArmed' in post,
   'every PY/RH settlement revalidates and rebases Recovery from fresh live units')
ck('m_historyDirty=true; m_basket.Invalidate()' in protect and 'tính lại snapshot từ fills mới' in protect,
   'standalone PY exit invalidates all cached lots/prices before continuation')
ck('m_group[d].phase=PY_CLOSING' in protect and 'DriveFlatSettlement' in protect and
   'if(m_snap[d].count!=0) return PY_DRIVE_NEXT' in protect,
   'latched group trigger remains active until exact PY flat')
ck('m_exec.HasReconcileRequired(Key(op.dir))' in protect and 'Fault("request outcome ambiguous")' in protect,
   'ambiguous broker outcome is fail closed')
flat=protect[protect.index('int DriveFlatSettlement('):protect.index('int DriveClosing(')]
ck(flat.index('m_exec.HasPendingMutation()') < flat.index('Exposure(d,core,hedge,reserved)') and
   flat.index('T1722PyMutationQuiet') < flat.index('Exposure(d,core,hedge,reserved)'),
   'flat settlement waits for quiet owners before any exposure scan')

ck('#include <BlackDragon/Pyramid/PyramidProtection.mqh>' in entry and
   'g_pyProtection.Observe(ctx)' in entry and 'g_pyramidProtection.Drive(ctx)' in strategy,
   'composition root observes once and Strategy drives mutations')
ck('g_exec.OnTransaction(trans, request, result);' in entry and
   entry.index('g_exec.OnTransaction(trans, request, result);') < entry.index('g_pyProtection.OnTransaction(trans);'),
   'executor proof is recorded before PY transaction classification')
ck(all(x in wf for x in ['t1722_protection_model.cpp','t1722_source_contract.py',
                          'RunT1722PyProtectionTests','E=45']),
   'canonical workflow enrolls all T17.22 verification layers')
decisions=rd(DOC/'DECISIONS.yaml')
ck(decisions.count('status: APPROVED')==5 and all(f'D1722-0{i}' in decisions for i in range(1,6)),
   'all five implementation decisions are owner approved')
contract=json.loads(rd(DOC/'AI-BUILD-CONTRACT.json'))
ck(contract['status'] in ('OWNER_PLAN_APPROVED','IMPLEMENTED_LOCAL_VPS_VERIFIED_CI_PENDING','VERIFIED') and len(contract['guards'])==12,
   'Full build contract retains twelve hard retro guards')

fails=[name for ok,name in checks if not ok]
print(f'T17.22 source contract: {len(checks)-len(fails)} passed, {len(fails)} failed')
for name in fails: print('FAIL:',name)
if fails: sys.exit(1)
print('ALL GREEN')
