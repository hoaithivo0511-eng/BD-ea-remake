#!/usr/bin/env python3
"""Bind comment writers/readers and preserve the full unrelated runtime tree."""
from pathlib import Path
import hashlib,json,re
from t1721_comment_baseline import before_comments,MANIFEST,REPO
ROOT=REPO/'BlackDragon_v14'; D=ROOT/'docs/vibecode/T17_21_comments'
contract=json.loads((D/'AI-BUILD-CONTRACT.json').read_text()); checks=[]
superseded_t1722={
 'BlackDragon_v14/Include/BlackDragon/Recovery/RecoveryArcsStack.mqh',
 'BlackDragon_v14/Include/BlackDragon/Recovery/RecoveryEngine.mqh',
 'BlackDragon_v14/Include/BlackDragon/Recovery/RecoveryArcsStackT1719Reentry.mqh',
 'BlackDragon_v14/Include/BlackDragon/BasketManager.mqh',
 'BlackDragon_v14/Include/BlackDragon/ExecutionLayer.mqh',
 'BlackDragon_v14/Include/BlackDragon/Strategy.mqh',
 'BlackDragon_v14/Include/BlackDragon/Types.mqh',
 'BlackDragon_v14/Include/BlackDragon/Config.mqh',
 'BlackDragon_v14/Include/BlackDragon/Pyramid/CorePyramid.mqh',
 'BlackDragon_v14/Include/BlackDragon/Recovery/RecoveryArcsStackHardened.mqh',
 'BlackDragon_v14/Include/BlackDragon/Recovery/RecoveryArcsStackPostDealT162Base.mqh',
 'BlackDragon_v14/Include/BlackDragon/Recovery/RecoveryExitCoordinatorT177Base.mqh',
}
def ck(ok,name): checks.append((bool(ok),name))
for path,sha in MANIFEST['original_sha256'].items():
    if path in superseded_t1722: continue
    text=before_comments(path,(REPO/path).read_text())
    ck(hashlib.sha256(text.encode()).hexdigest()==sha,'only comment changes: '+Path(path).name)
for path,sha in contract['protected_source_sha256'].items():
    if path in superseded_t1722: continue
    ck(hashlib.sha256((REPO/path).read_bytes()).hexdigest()==sha,'unchanged: '+Path(path).name)
rh=ROOT/'Include/BlackDragon/Recovery'; sites=[]
for path in rh.glob('*.mqh'):
    text=path.read_text()
    for match in re.finditer(r'exec\.OpenMarketOwned\(',text):
        before=text[:match.start()]; pos=before.rfind('Recovery_BuildReadableComment(')
        sites.append(path.name)
        span=before[pos:] if pos>=0 else ''
        call=text[match.start():text.find(';',match.start())]
        ck(pos>=0 and 'comment)' in call and not re.search(r'\bcomment\s*=',span),'new writer connected: '+path.name)
ck(len(sites)==5,'all five RH submission paths')
codec=(ROOT/'Include/BlackDragon/OrderCommentCodec.mqh').read_text()
helper=(rh/'RecoveryOrderComment.mqh').read_text()
ck('"-S|G"' in codec and '"|P"' in codec and '"|N"' in codec,'owner pipe separator')
ck('"BDR|C="' in codec and '"BDP|"' in codec,'legacy readers remain')
ck('HistorySelect(0,TimeCurrent())' in helper and 'DEAL_ENTRY_INOUT' in helper,'opening-history reconstruction')
ck('DEAL_MAGIC' in helper and 'DEAL_SYMBOL' in helper and 'DEAL_TYPE' in helper,'exact owned history scope')
ck(not any(token in helper for token in ['OrderSend(', 'Save(', 'FileWrite', 'GlobalVariableSet', 'LatchReconcile(']), 'presentation has no new execution/persistence gate')
ck('OC_RhMatchesBundle(comment, p.cycleKey, p.generation, p.bundleId)' in (rh/'RecoveryEngine.mqh').read_text(),'pending proof supports both formats')
ck((rh/'RecoveryArcsStackT1719Reentry.mqh').read_text().count('OC_RhMatchesCycle(')==3,'all reentry history consumers support both formats')
wf=(REPO/'.github/workflows/verify-current.yml').read_text()
ck(all(n in wf for n in ['t1721_comment_model.cpp','t1721_source_contract.py','RunT1721OrderCommentTests','E=58']), 'all verification layers in canonical workflow')
fails=[n for ok,n in checks if not ok]
print(f'T17.21 source contract: {len(checks)-len(fails)} passed, {len(fails)} failed')
for n in fails:print('FAIL:',n)
if fails:raise SystemExit(1)
print('ALL GREEN')
