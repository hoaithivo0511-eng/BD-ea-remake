#!/usr/bin/env python3
"""T17.24 integration wiring and scope contract; native evidence is separate."""
from pathlib import Path
import fnmatch, hashlib, json, re

REPO=Path(__file__).resolve().parents[4]
ROOT=REPO/'BlackDragon_v14'; INC=ROOT/'Include/BlackDragon'
D=ROOT/'docs/vibecode/BD_PR28_REMEDIATION'
checks=[]
def ck(ok,name): checks.append((bool(ok),name))
def rd(p): return Path(p).read_text(encoding='utf-8-sig')
def body(s,start,end): return s[s.index(start):s.index(end,s.index(start))]

c=json.loads(rd(D/'AI-BUILD-CONTRACT.json'));a=json.loads(rd(D/'BUILD_AUTHORITY.json'))
b=json.loads(rd(D/'BASELINE_SOURCE.json'))
ck(a['baseline_head']==b['head']==c['implementation_baseline']['head'],'exact implementation baseline bound')
ck(a['owner_request'].startswith('Dùng @Vibecode MQL5') and a['approval_kind']=='explicit natural-language task instruction','real instruction authorizes build')
allowed=c['allowed_path_scopes']['all']
for x in b['files']:
 p=REPO/x['path'];s=rd(p)
 ck(re.findall(r'^\s*input\s+(?!group\b)[^;]+;',s,re.M)==x['inputs'],'inputs preserved: '+p.name)
 if not any(fnmatch.fnmatch(x['path'],pat) for pat in allowed):
  ck(hashlib.sha256(p.read_bytes()).hexdigest()==x['sha256'],'out-of-scope runtime preserved: '+p.name)
cash=rd(INC/'CashLedger.mqh');basket=rd(INC/'BasketManager.mqh')
guard=rd(INC/'Recovery/RecoveryT165GuardScope.mqh');entry=rd(ROOT/'Experts/BlackDragon/BlackDragon.mq5')
ck('CScopedDayCashLedger m_dayCash' in basket and 'CScopedDayCashLedger g_t1724RecoveryDayCash' in guard,'Core/Recovery share the reducer')
ck('m_dayCash.DayStart()' in basket and 'AccountInfoDouble(ACCOUNT_BALANCE)-m_dayProfit' in basket,'approved scoped denominator retained')
ck('DayCashReady()' in rd(INC/'StrategyT176Base.mqh') and 'm.historyOk=g_t1724RecoveryDayCash.Refresh(now)' in guard and 'if(m.historyOk)' in guard,'daily guards consume validity')
ck('HistorySelectByPosition(id)' in cash and 'LowerOwner' in cash and 'LowerDeal' in cash,'immutable ownership and exact deal lookup')
ck(cash.index('ids[i]=HistoryDealGetTicket(i)')<cash.index('if(!Read(ids[i]'),'seed freezes IDs before resetting history')
ck('m_cash+=cash-m_deals[at].cash' in cash and 'stamp<day || stamp>=day+86400' in cash,'idempotent corrected booking-day cash')
ck('m_commissionRetryAt=ctx.now+1' in basket and 'ctx.now>=m_commissionRetryAt' in basket,'commission availability retries without topology event')
ck('TRADE_TRANSACTION_DEAL_UPDATE' in entry and 'g_basket.InvalidateDayCash()' in entry and 'Recovery_T165InvalidateGuardCash()' in entry,'history corrections invalidate both ledgers')
suppressed=body(entry,'else if(trans.type == TRADE_TRANSACTION_DEAL_ADD','if(trans.type == TRADE_TRANSACTION_POSITION')
ck('Recovery_T165GuardObserveDeal(trans.deal,TimeCurrent())' in suppressed,'exit coordinator suppression still observes Recovery cash')
arcs=rd(INC/'Recovery/RecoveryArcsStack.mqh')
replay=body(arcs,'bool ReplayAfterCursor(','bool ValidateLiveBook(')
ck(replay.index('HistoryDealGetTicket(i)')<replay.index('owner=ResolveClosedOwnerMagic(deal)'),'replay freezes selected IDs before owner lookup')
ck('stamps[j]==keyMsc && replay[j]>key' in replay,'stable timestamp/ticket replay ordering')
ck('broker history correction requires funding-ledger reconciliation' in arcs,'correction does not leave funding silently valid')
execution=rd(INC/'ExecutionLayer.mqh');protect=rd(INC/'Pyramid/PyramidProtection.mqh')
ck('protectedPositionId' in execution and 'protectedNonce' in execution and 'PendingIdentity(' in execution,'executor captures immutable ID and nonce')
ck('m_journal[i].observedVolume>0' in execution and 'm_journal[i].serverDeal!=0' in execution,'fill evidence prevents false no-effect classification')
ck(execution.count('Exec_AmbiguousRetcode(res.retcode) || res.retcode==0')==2,'sync and async zero/ambiguous outcomes retained')
reject=body(protect,'bool OnDefinitiveReject(','bool AllowsRequest(')
ck('PyProtect_ExactRejectIdentityPure' in reject and 'POSITION_SL)-op.targetSl' in reject and 'POSITION_VOLUME)<op.beforeLots' in reject,'reject consumer checks identity and contradictory live effects')
ck(reject.index('RecordNoEffectReject(op,retcode)')<reject.index('EraseOperationAt(found)')<reject.index('if(!Save())'),'retry outcome persisted before ACK')
ck('h.version==1 || h.version==2' in protect and 'h.version>=2' in protect and 'FileWriteStruct(f,m_retry[d])' in protect,'v1 reader and v2 retry payload writer wired')
ck('m_retry[d].rejects>=8' in protect and 'TimeCurrent()>=m_retry[d].nextEligible' in protect,'bounded retry budget and deadline')
tick=body(entry,'void OnTick()','void OnTradeTransaction(')
ck(tick.index('g_bdObservationBook.Begin')<tick.index('g_recovery.OnTick')<tick.index('g_bdObservationBook.End')<tick.index('g_strategy.OnTick'),'observation cache ends before mutation chain')
book=rd(INC/'PositionBook.mqh')
ck('OrderSend' not in book and 'FileWrite' not in book and 'ArrayResize' not in book,'aggregate observation is allocation-free and has no side effects')
ck('m_enabled=false' in book and 'PositionsTotal()!=count' in book,'partial observation falls back to live reads')
rb=rd(INC/'Recovery/RecoveryArcsBook.mqh')
layer=body(rb,'long Recovery_ArcsLayerUnits(','long Recovery_ArcsTotalHedgeUnits(')
ck('ArrayResize' not in layer and 'SortPositions' not in layer and 'units+=volumeUnits' in layer,'layer sum avoids allocation/sort')
campaign=body(rd(INC/'Pyramid/CorePyramid.mqh'),'bool RefreshCampaignStats(','bool CampaignHistoryReady(')
ck('m_statsRevision[dir]==g_pyramidDealRevision' in campaign and 'm_statsAt[dir] == now' not in campaign,'quiet campaign totals use event revision')
wf=rd(REPO/'.github/workflows/verify-current.yml')
ck(all(x in wf for x in ['t1724_source_contract.py','t1724_integration.py','RunT1724CashLedgerTests']),'all new evidence layers enrolled in canonical CI')
ck(not a['release_eligible'] and not a['forward_eligible'] and not a['live_eligible'],'no unsupported release promotion')
fails=[n for ok,n in checks if not ok]
print(f'T17.24 source contract: {len(checks)-len(fails)} passed, {len(fails)} failed')
for n in fails: print('FAIL:',n)
if fails: raise SystemExit(1)
print('ALL GREEN')
