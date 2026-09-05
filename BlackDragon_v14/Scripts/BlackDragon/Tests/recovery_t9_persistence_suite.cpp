#include <cstdint>
#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
#include <sstream>
#include <iomanip>
using std::cout;

static int passed=0, failed=0;
#define CHECK(name, expr) do { if(expr){++passed;} else {++failed; cout << "FAIL " << name << "\n";} } while(0)

enum State {
  CORE_ONLY, ARMED, HEDGE_BUILDING, HEDGE_ACTIVE, HEDGE_TP_PENDING,
  CORE_CLOSE_PENDING, HEDGE_LOCK_PENDING, HEDGE_LOCKED, REHEDGE_PENDING,
  PAUSE_SOFT, PAUSE_HARD, RECONCILE_REQUIRED, GLOBAL_STOP, COMPLETED
};
enum Cmd { LEGACY, OPEN, CLOSE, MODIFY };
enum Startup { BOOTSTRAP, READY, RECONCILE, BLOCKED };

struct Cursor { long long ms; unsigned long long ticket; };
struct Pending {
  bool active=false; Cmd cmd=LEGACY; long owner=0; long target=0; long before=0;
  bool modifySatisfied=false;
};

struct RecoverySemanticConfig {
  int mode=2;
  long long recoveryMagic=20260807;
  int startAfterDca=3;
  double hedgeGapPips=3.0;
  double hedgeTpPips=8.0;
  double hedgePartialClosePercent=50.0;
  int coreCloseMode=1;
  double hedgeLockNetProfitPips=2.0;
  double hedgeLockSafetyBufferPips=1.0;
  double reHedgeGapPips=5.0;
  int maxHedgeGenerations=3;
  bool continueDcaAfterHedge=false;
  double minHedgeCoveragePercent=0.0;
  double targetRecoveryCorridorPips=0.0;
};

static uint32_t fnv1a(const std::vector<uint8_t>& b){
  uint32_t h=2166136261u;
  for(uint8_t v:b){ h^=v; h*=16777619u; }
  return h;
}

static uint32_t fnvUtf16Ascii(const std::string &s){
  uint32_t h=2166136261u;
  for(unsigned char ch:s){
    h^=static_cast<uint32_t>(ch); h*=16777619u;
    h^=0u; h*=16777619u;
  }
  return h;
}

static std::string d12(double v){
  std::ostringstream os;
  os << std::fixed << std::setprecision(12) << v;
  return os.str();
}

static uint32_t semanticFingerprint(const RecoverySemanticConfig &c){
  std::string canonical =
    "mode=" + std::to_string(c.mode) +
    "|recoveryMagic=" + std::to_string(c.recoveryMagic) +
    "|startAfterDca=" + std::to_string(c.startAfterDca) +
    "|hedgeGap=" + d12(c.hedgeGapPips) +
    "|hedgeTp=" + d12(c.hedgeTpPips) +
    "|partial=" + d12(c.hedgePartialClosePercent) +
    "|coreClose=" + std::to_string(c.coreCloseMode) +
    "|lockProfit=" + d12(c.hedgeLockNetProfitPips) +
    "|lockBuffer=" + d12(c.hedgeLockSafetyBufferPips) +
    "|rehedgeGap=" + d12(c.reHedgeGapPips) +
    "|maxGen=" + std::to_string(c.maxHedgeGenerations) +
    "|continueDca=" + std::string(c.continueDcaAfterHedge ? "1" : "0") +
    "|minCoverage=" + d12(c.minHedgeCoveragePercent) +
    "|targetCorridor=" + d12(c.targetRecoveryCorridorPips);
  return fnvUtf16Ascii(canonical);
}

static bool reusePersistedState(bool isTester,bool testerResumeState){
  return !isTester || testerResumeState;
}

static bool after(Cursor d, Cursor c){ return d.ms>c.ms || (d.ms==c.ms && d.ticket>c.ticket); }
static bool volumeEffect(bool open,long before,long target,long current){
  if(before<0||target<=0||current<0) return false;
  if(open) return current>=before+target;
  long expected=before>target?before-target:0;
  return current<=expected;
}
static bool pendingEffect(const Pending&p,long recoveryUnits,long coreUnits){
  if(!p.active) return true;
  if(p.cmd==OPEN) return volumeEffect(true,p.before,p.target,recoveryUnits);
  if(p.cmd==CLOSE) return volumeEffect(false,p.before,p.target,p.owner==2222?recoveryUnits:coreUnits);
  if(p.cmd==MODIFY) return p.modifySatisfied;
  return false;
}
static bool stateValueValid(int s){ return s>=CORE_ONLY && s<=COMPLETED; }
static bool stateNeedsCore(State s){
  return s==ARMED||s==HEDGE_BUILDING||s==HEDGE_ACTIVE||s==HEDGE_TP_PENDING||
         s==CORE_CLOSE_PENDING||s==HEDGE_LOCK_PENDING||s==HEDGE_LOCKED||s==REHEDGE_PENDING;
}
static Startup missingPolicy(bool activeMode,long recoveryUnits){
  if(!activeMode) return READY;
  return recoveryUnits>0?BLOCKED:BOOTSTRAP;
}
static Startup restartPolicy(State s,long core,long hedge,long bundleTarget,long baseline,
                             bool hasAnchor,bool t5Valid,bool lockAnchor,bool durableResolved){
  if(!stateValueValid((int)s)||!durableResolved) return RECONCILE;
  switch(s){
    case CORE_ONLY: return hedge==0?READY:RECONCILE;
    case ARMED: return core>0&&hedge==0&&hasAnchor?READY:RECONCILE;
    case HEDGE_BUILDING:{
      long confirmed=hedge-baseline;
      return core>0&&bundleTarget>0&&baseline>=0&&confirmed>=0&&confirmed<=bundleTarget?READY:RECONCILE;
    }
    case HEDGE_ACTIVE: return core>0&&hedge>0?READY:RECONCILE;
    case HEDGE_TP_PENDING: return core>0&&t5Valid?READY:RECONCILE;
    case CORE_CLOSE_PENDING: return hedge>0&&t5Valid?READY:RECONCILE;
    case HEDGE_LOCK_PENDING: return hedge>0&&lockAnchor?READY:RECONCILE;
    case HEDGE_LOCKED:
    case REHEDGE_PENDING: return core>0&&hedge>0&&lockAnchor?READY:RECONCILE;
    case COMPLETED: return core==0&&hedge==0?READY:RECONCILE;
    case PAUSE_SOFT:
    case PAUSE_HARD:
    case RECONCILE_REQUIRED:
    case GLOBAL_STOP: return RECONCILE;
  }
  return RECONCILE;
}
static bool schedulerTerminal(State s,bool trigger,bool pending,bool submitAccepted,bool strictAmbiguous){
  if(pending||strictAmbiguous) return true;
  if(s==ARMED||s==HEDGE_ACTIVE||s==HEDGE_LOCKED) return trigger;
  if(s==HEDGE_BUILDING||s==HEDGE_TP_PENDING||s==CORE_CLOSE_PENDING||s==HEDGE_LOCK_PENDING)
    return submitAccepted;
  if(s==REHEDGE_PENDING) return trigger;
  return false;
}
static bool offMutatesFile(bool activeMode,bool dirty){ return activeMode&&dirty; }

int main(){
  // checksum / corruption detection model
  CHECK("fnv empty", fnv1a({})==2166136261u);
  CHECK("fnv a", fnv1a({'a'})==0xe40c292cu);
  CHECK("fnv hello", fnv1a({'h','e','l','l','o'})==0x4f9f2cabu);
  std::vector<uint8_t> payload={1,2,3,4,5,6,7,8};
  auto h1=fnv1a(payload); auto copy=payload;
  CHECK("checksum deterministic", fnv1a(copy)==h1);
  copy[3]^=0x01;
  CHECK("single byte corruption", fnv1a(copy)!=h1);
  copy=payload; copy.push_back(0);
  CHECK("length change corruption", fnv1a(copy)!=h1);

  // T15 / RETRO-A7: independent tester passes must not inherit durable state
  // unless restart/resume testing is explicitly requested. Live/forward always
  // retains the durable restart contract.
  CHECK("T15 tester default isolates persistence", !reusePersistedState(true,false));
  CHECK("T15 tester explicit resume reuses persistence", reusePersistedState(true,true));
  CHECK("T15 live false flag still reuses persistence", reusePersistedState(false,false));
  CHECK("T15 live true flag reuses persistence", reusePersistedState(false,true));

  // T15 semantic fingerprint: any Recovery policy mutation invalidates an old
  // durable snapshot. The tester-only resume switch is intentionally not a
  // trading semantic and therefore is not part of this fingerprint model.
  RecoverySemanticConfig base;
  const uint32_t fp=semanticFingerprint(base);
  CHECK("T15 fingerprint deterministic", semanticFingerprint(base)==fp);
  {
    auto x=base; x.mode=1; CHECK("T15 fp mode", semanticFingerprint(x)!=fp);
    x=base; x.recoveryMagic++; CHECK("T15 fp recoveryMagic", semanticFingerprint(x)!=fp);
    x=base; x.startAfterDca++; CHECK("T15 fp startAfterDca", semanticFingerprint(x)!=fp);
    x=base; x.hedgeGapPips+=0.1; CHECK("T15 fp hedgeGap", semanticFingerprint(x)!=fp);
    x=base; x.hedgeTpPips+=0.1; CHECK("T15 fp hedgeTp", semanticFingerprint(x)!=fp);
    x=base; x.hedgePartialClosePercent+=0.1; CHECK("T15 fp partial", semanticFingerprint(x)!=fp);
    x=base; x.coreCloseMode=2; CHECK("T15 fp coreClose", semanticFingerprint(x)!=fp);
    x=base; x.hedgeLockNetProfitPips+=0.1; CHECK("T15 fp lockProfit", semanticFingerprint(x)!=fp);
    x=base; x.hedgeLockSafetyBufferPips+=0.1; CHECK("T15 fp lockBuffer", semanticFingerprint(x)!=fp);
    x=base; x.reHedgeGapPips+=0.1; CHECK("T15 fp rehedgeGap", semanticFingerprint(x)!=fp);
    x=base; x.maxHedgeGenerations++; CHECK("T15 fp maxGen", semanticFingerprint(x)!=fp);
    x=base; x.continueDcaAfterHedge=true; CHECK("T15 fp continueDca", semanticFingerprint(x)!=fp);
    x=base; x.minHedgeCoveragePercent=30.0; CHECK("T15 fp minCoverage", semanticFingerprint(x)!=fp);
    x=base; x.targetRecoveryCorridorPips=20.0; CHECK("T15 fp targetCorridor", semanticFingerprint(x)!=fp);
  }

  // cursor strict ordering / already-booked dedupe
  Cursor c{1000,50};
  CHECK("cursor later ms", after({1001,1},c));
  CHECK("cursor same ms later ticket", after({1000,51},c));
  CHECK("cursor exact duplicate false", !after({1000,50},c));
  CHECK("cursor older ticket false", !after({1000,49},c));
  CHECK("cursor older ms false", !after({999,999},c));
  Cursor z{0,0};
  CHECK("cursor first deal", after({1,1},z));

  // exact durable OPEN/CLOSE effect confirmation
  CHECK("open exact", volumeEffect(true,500,200,700));
  CHECK("open more", volumeEffect(true,500,200,701));
  CHECK("open partial not confirmed", !volumeEffect(true,500,200,699));
  CHECK("open zero target invalid", !volumeEffect(true,500,0,500));
  CHECK("open negative before invalid", !volumeEffect(true,-1,10,9));
  CHECK("close exact", volumeEffect(false,700,200,500));
  CHECK("close more risk reduction", volumeEffect(false,700,200,450));
  CHECK("close partial not confirmed", !volumeEffect(false,700,200,501));
  CHECK("close to zero", volumeEffect(false,100,200,0));
  CHECK("close residual invalid", !volumeEffect(false,100,200,1));

  Pending p;
  CHECK("no pending resolved", pendingEffect(p,0,0));
  p={true,OPEN,2222,200,500,false};
  CHECK("pending recovery open exact", pendingEffect(p,700,1000));
  CHECK("pending recovery open partial fail", !pendingEffect(p,699,1000));
  p={true,CLOSE,2222,200,700,false};
  CHECK("pending recovery close exact", pendingEffect(p,500,1000));
  CHECK("pending recovery close partial fail", !pendingEffect(p,501,1000));
  p={true,CLOSE,1111,300,1000,false};
  CHECK("pending core close exact", pendingEffect(p,500,700));
  CHECK("pending core close partial fail", !pendingEffect(p,500,701));
  p={true,MODIFY,2222,0,500,true};
  CHECK("pending modify satisfied", pendingEffect(p,500,1000));
  p.modifySatisfied=false;
  CHECK("pending modify unresolved", !pendingEffect(p,500,1000));
  p={true,LEGACY,1111,10,10,false};
  CHECK("legacy cannot be durable", !pendingEffect(p,0,0));

  // state enum structural bounds
  for(int s=CORE_ONLY;s<=COMPLETED;s++) CHECK("state valid", stateValueValid(s));
  CHECK("state below invalid", !stateValueValid(-1));
  CHECK("state above invalid", !stateValueValid(COMPLETED+1));

  // missing-state policy and OFF no-mutation invariant
  CHECK("OFF ignores persistence", missingPolicy(false,999)==READY);
  CHECK("ACTIVE missing flat bootstrap", missingPolicy(true,0)==BOOTSTRAP);
  CHECK("ACTIVE missing hedge blocked", missingPolicy(true,1)==BLOCKED);
  CHECK("OFF clean no file mutation", !offMutatesFile(false,true));
  CHECK("OFF clean dirty still no file mutation", !offMutatesFile(false,true));
  CHECK("ACTIVE dirty persists", offMutatesFile(true,true));
  CHECK("ACTIVE clean no write", !offMutatesFile(true,false));

  // clean restart state matrix
  CHECK("restart CORE_ONLY", restartPolicy(CORE_ONLY,0,0,0,0,false,false,false,true)==READY);
  CHECK("restart CORE_ONLY with core", restartPolicy(CORE_ONLY,500,0,0,0,false,false,false,true)==READY);
  CHECK("restart CORE_ONLY naked hedge", restartPolicy(CORE_ONLY,0,100,0,0,false,false,false,true)==RECONCILE);
  CHECK("restart ARMED", restartPolicy(ARMED,600,0,0,0,true,false,false,true)==READY);
  CHECK("restart ARMED missing anchor", restartPolicy(ARMED,600,0,0,0,false,false,false,true)==RECONCILE);
  CHECK("restart ARMED flat", restartPolicy(ARMED,0,0,0,0,true,false,false,true)==RECONCILE);
  CHECK("restart ARMED unexpected hedge", restartPolicy(ARMED,600,10,0,0,true,false,false,true)==RECONCILE);
  CHECK("restart BUILDING zero confirmed", restartPolicy(HEDGE_BUILDING,600,0,600,0,true,false,false,true)==READY);
  CHECK("restart BUILDING partial", restartPolicy(HEDGE_BUILDING,600,250,600,0,true,false,false,true)==READY);
  CHECK("restart BUILDING exact", restartPolicy(HEDGE_BUILDING,600,600,600,0,true,false,false,true)==READY);
  CHECK("restart BUILDING over", restartPolicy(HEDGE_BUILDING,600,601,600,0,true,false,false,true)==RECONCILE);
  CHECK("restart BUILDING below baseline", restartPolicy(HEDGE_BUILDING,600,99,600,100,true,false,false,true)==RECONCILE);
  CHECK("restart BUILDING no target", restartPolicy(HEDGE_BUILDING,600,0,0,0,true,false,false,true)==RECONCILE);
  CHECK("restart ACTIVE", restartPolicy(HEDGE_ACTIVE,600,600,0,0,true,false,false,true)==READY);
  CHECK("restart ACTIVE no core", restartPolicy(HEDGE_ACTIVE,0,600,0,0,0,false,false,true)==RECONCILE);
  CHECK("restart ACTIVE no hedge", restartPolicy(HEDGE_ACTIVE,600,0,0,0,true,false,false,true)==RECONCILE);
  CHECK("restart TP pending", restartPolicy(HEDGE_TP_PENDING,600,300,0,0,true,true,false,true)==READY);
  CHECK("restart TP missing runtime", restartPolicy(HEDGE_TP_PENDING,600,300,0,0,true,false,false,true)==RECONCILE);
  CHECK("restart CORE_CLOSE", restartPolicy(CORE_CLOSE_PENDING,500,300,0,0,true,true,false,true)==READY);
  CHECK("restart CORE_CLOSE no hedge", restartPolicy(CORE_CLOSE_PENDING,500,0,0,0,true,true,false,true)==RECONCILE);
  CHECK("restart LOCK pending", restartPolicy(HEDGE_LOCK_PENDING,500,300,0,0,true,true,true,true)==READY);
  CHECK("restart LOCK no anchor", restartPolicy(HEDGE_LOCK_PENDING,500,300,0,0,true,true,false,true)==RECONCILE);
  CHECK("restart LOCKED", restartPolicy(HEDGE_LOCKED,500,300,0,0,true,true,true,true)==READY);
  CHECK("restart LOCKED flat core", restartPolicy(HEDGE_LOCKED,0,300,0,0,true,true,true,true)==RECONCILE);
  CHECK("restart REHEDGE", restartPolicy(REHEDGE_PENDING,500,300,0,0,true,true,true,true)==READY);
  CHECK("restart REHEDGE no hedge", restartPolicy(REHEDGE_PENDING,500,0,0,0,true,true,true,true)==RECONCILE);
  CHECK("restart COMPLETED", restartPolicy(COMPLETED,0,0,0,0,false,false,false,true)==READY);
  CHECK("restart COMPLETED external core", restartPolicy(COMPLETED,1,0,0,0,false,false,false,true)==RECONCILE);
  CHECK("restart PAUSE_SOFT", restartPolicy(PAUSE_SOFT,1,1,0,0,true,true,true,true)==RECONCILE);
  CHECK("restart PAUSE_HARD", restartPolicy(PAUSE_HARD,1,1,0,0,true,true,true,true)==RECONCILE);
  CHECK("restart RECONCILE", restartPolicy(RECONCILE_REQUIRED,1,1,0,0,true,true,true,true)==RECONCILE);
  CHECK("restart GLOBAL_STOP", restartPolicy(GLOBAL_STOP,1,1,0,0,true,true,true,true)==RECONCILE);
  CHECK("unresolved durable blocks any state", restartPolicy(HEDGE_ACTIVE,500,500,0,0,true,true,true,false)==RECONCILE);

  // Core-state expectation helper
  CHECK("CORE_ONLY no core requirement", !stateNeedsCore(CORE_ONLY));
  CHECK("ARMED core required", stateNeedsCore(ARMED));
  CHECK("BUILDING core required", stateNeedsCore(HEDGE_BUILDING));
  CHECK("ACTIVE core required", stateNeedsCore(HEDGE_ACTIVE));
  CHECK("TP core required", stateNeedsCore(HEDGE_TP_PENDING));
  CHECK("CORE_CLOSE core tracked", stateNeedsCore(CORE_CLOSE_PENDING));
  CHECK("LOCK_PENDING core tracked", stateNeedsCore(HEDGE_LOCK_PENDING));
  CHECK("LOCKED core required", stateNeedsCore(HEDGE_LOCKED));
  CHECK("REHEDGE core required", stateNeedsCore(REHEDGE_PENDING));
  CHECK("COMPLETED no core requirement", !stateNeedsCore(COMPLETED));

  // Scheduler terminal contract: only an actual transition/mutation/pending
  // suppresses later legacy work; stable non-triggered states fall through.
  CHECK("ARMED no gap falls through", !schedulerTerminal(ARMED,false,false,false,false));
  CHECK("ARMED gap terminal", schedulerTerminal(ARMED,true,false,false,false));
  CHECK("ACTIVE no TP falls through", !schedulerTerminal(HEDGE_ACTIVE,false,false,false,false));
  CHECK("ACTIVE TP terminal", schedulerTerminal(HEDGE_ACTIVE,true,false,false,false));
  CHECK("LOCKED no rehedge falls through", !schedulerTerminal(HEDGE_LOCKED,false,false,false,false));
  CHECK("LOCKED rehedge terminal", schedulerTerminal(HEDGE_LOCKED,true,false,false,false));
  CHECK("BUILDING accepted child terminal", schedulerTerminal(HEDGE_BUILDING,false,false,true,false));
  CHECK("BUILDING reject falls through risk exits", !schedulerTerminal(HEDGE_BUILDING,false,false,false,false));
  CHECK("TP accepted close terminal", schedulerTerminal(HEDGE_TP_PENDING,false,false,true,false));
  CHECK("CORE accepted close terminal", schedulerTerminal(CORE_CLOSE_PENDING,false,false,true,false));
  CHECK("LOCK accepted modify terminal", schedulerTerminal(HEDGE_LOCK_PENDING,false,false,true,false));
  CHECK("any execution pending terminal", schedulerTerminal(CORE_ONLY,false,true,false,false));
  CHECK("strict ambiguous terminal current tick", schedulerTerminal(CORE_ONLY,false,false,false,true));
  CHECK("REHEDGE prepared terminal", schedulerTerminal(REHEDGE_PENDING,true,false,false,false));
  CHECK("RECONCILE falls through risk exits", !schedulerTerminal(RECONCILE_REQUIRED,false,false,false,false));

  // two-cycle independence / no cross-credit or pending effect
  Pending buy{true,OPEN,2222,100,500,false};
  Pending sell{true,CLOSE,2222,50,300,false};
  CHECK("buy pending own hedge", pendingEffect(buy,600,1000));
  CHECK("sell pending own hedge", pendingEffect(sell,250,1000));
  CHECK("sell values do not satisfy buy", !pendingEffect(buy,250,1000));
  CHECK("buy values do not satisfy sell", !pendingEffect(sell,600,1000));

  cout << passed << " passed, " << failed << " failed\n";
  return failed==0?0:1;
}
