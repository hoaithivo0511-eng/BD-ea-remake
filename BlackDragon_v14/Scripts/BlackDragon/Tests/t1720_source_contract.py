#!/usr/bin/env python3
"""Bind the additive gate to all RH opens and byte-preserve unrelated logic."""
from pathlib import Path
import hashlib,json,re
ROOT=Path(__file__).resolve().parents[3]
REPO=ROOT.parent
C=ROOT/'docs/vibecode/T17_20_one_bar/AI-BUILD-CONTRACT.json'
contract=json.loads(C.read_text())
checks=[]
def ck(ok,name):checks.append((bool(ok),name))
def read(p):return (REPO/p).read_text()
prefix='BlackDragon_v14/Include/BlackDragon/Recovery/'
gate=read(prefix+'RecoveryOpenBarGate.mqh')
types=read(prefix+'RecoveryTypes.mqh')
ck(re.search(r'input\s+bool\s+RecoveryOneOrderPerBar_\s*=\s*false\s*;',types),'single additive default OFF input')
ck(gate.index('if(!RecoveryOneOrderPerBar_) return true;')<gate.index('iTime('),'OFF returns before any platform data reads')
ck('iTime(_Symbol, PERIOD_CURRENT, 0)' in gate,'same chart candle domain as Core DCA')
ck('HistorySelect(bar, now)' in gate and 'DEAL_ENTRY_IN' in gate,'closed RH openings remain in current-bar history')
ck('POSITION_TIME_MSC' in gate and 'DEAL_TIME_MSC' in gate,'millisecond opening boundary for live and closed positions')
ck('POSITION_MAGIC) == RecoveryMagic_' in gate and 'DEAL_MAGIC) == RecoveryMagic_' in gate,'exact Recovery Magic rather than Core owner')
ck('wantedPosition' in gate and 'wantedDeal' in gate,'independent directional scope')
ck(not any(x in gate for x in ['OrderSend(', 'OrderSendAsync(', 'FileWrite', 'GlobalVariableSet', 'LatchReconcile(', 'TesterStop(']),'data WAIT gate has no trading/persistence/error latch side effects')
ck('static ' not in gate,'no generation-local/transient bar counter')
for p,sha in contract['protected_source_sha256'].items():
 ck(hashlib.sha256((REPO/p).read_bytes()).hexdigest()==sha,'protected '+p.split('/')[-1])
for p,sha in contract['additive_source_sha256'].items():
 text=read(p)
 if p.endswith('RecoveryTypes.mqh'):
  text=re.sub(r'^input bool\s+RecoveryOneOrderPerBar_.*\n','',text,flags=re.M)
 else:
  text=text.replace('#include "RecoveryOpenBarGate.mqh"\n','')
  text=re.sub(r'      if\(!Recovery_OneOrderPerBarAllows\(hedgeDir, TimeCurrent\(\), why\)\)\n      \{\n         Log_WarnEvery\("Recovery", "t1720bar" \+ \(string\)(?:key|cycleKey), why, 60\);\n         return (?:true|false);\n      \}\n\n','',text)
 ck(hashlib.sha256(text.encode()).hexdigest()==sha,'only authorized additions '+p.split('/')[-1])
rh_sites=[]
for path in (ROOT/'Include/BlackDragon/Recovery').glob('*.mqh'):
 text=path.read_text()
 for m in re.finditer(r'exec\.OpenMarketOwned\(',text):
  before=text[:m.start()];g=before.rfind('Recovery_OneOrderPerBarAllows(')
  rh_sites.append(path.name)
  ck(g>=0 and m.start()-g<2100,'RH opening site gated '+path.name)
  after=before[g:]
  ck('SaveBeforeMutation(' in after or 'ArmDurableCommand(' in after,'gate precedes durable open admission '+path.name)
ck(len(rh_sites)==5,'all five RH submission sites covered')
workflow=read('.github/workflows/verify-current.yml')
ck('t1720_one_bar_model.cpp' in workflow and 't1720_source_contract.py' in workflow and 'RunT1720RhOneBarTests' in workflow,'canonical CI runs all new verification layers')
fails=[n for ok,n in checks if not ok]
print(f'T17.20 source contract: {len(checks)-len(fails)} passed, {len(fails)} failed')
for n in fails:print('FAIL:',n)
if fails:raise SystemExit(1)
print('ALL GREEN')
