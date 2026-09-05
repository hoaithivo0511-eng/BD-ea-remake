#!/usr/bin/env python3
"""Production-body host integration adapters. Not a native MetaEditor build.

Only dynamic-array syntax and the platform API seam are adapted. Original
method/header hashes are emitted; model PASS must not promote native gates.
"""
from pathlib import Path
import argparse, hashlib, json, re, subprocess

REPO=Path(__file__).resolve().parents[4]
parser=argparse.ArgumentParser()
parser.add_argument('--out',type=Path,default=Path('/tmp/bd-t1724-integration'))
parser.add_argument('--replay-baseline',default=None)
args=parser.parse_args();OUT=args.out.resolve();OUT.mkdir(parents=True,exist_ok=True)
INC=REPO/'BlackDragon_v14/Include/BlackDragon'
TEST=Path(__file__).resolve().parent
manifest=[]
def adapt_arrays(s):
    return re.sub(r'\b(ulong|long|SBDCashDeal)\s+(\w+)\[\];',r'std::vector<\1> \2;',s)
def extract(s,sig):
    a=s.index(sig);i=s.index('{',a)+1;depth=1
    while depth:
        depth+=(s[i]=='{')-(s[i]=='}');i+=1
    body=s[a:i]
    manifest.append({'signature':sig,'line':s[:a].count('\n')+1,'sha256':hashlib.sha256(body.encode()).hexdigest()})
    return body
def run(name,source,extra=()):
    cpp=OUT/(name+'.cpp');cpp.write_text(source)
    exe=OUT/name
    command=['g++','-std=c++17','-O2','-Wall','-Wextra','-Wno-unused-parameter',str(cpp),'-I',str(OUT/'include'),'-o',str(exe),*extra]
    c=subprocess.run(command,text=True,capture_output=True)
    (OUT/(name+'.compile.log')).write_text(c.stdout+c.stderr)
    if c.returncode:print(c.stderr);raise SystemExit(c.returncode)
    r=subprocess.run([str(exe)],text=True,capture_output=True)
    (OUT/(name+'.log')).write_text(r.stdout+r.stderr)
    print(r.stdout,end='')
    return r.returncode

bridge=r'''
#include <algorithm>
#include <cmath>
#include <iostream>
#include <string>
#include <vector>
using string=std::string;using datetime=long;
template<class T> int ArraySize(const std::vector<T>&v){return (int)v.size();}
template<class T> int ArrayResize(std::vector<T>&v,int n,int reserve=0){if(n<0)return -1;if(reserve>0&&n>(int)v.capacity())v.reserve(n+reserve);v.resize(n);return n;}
double MathAbs(double a){return std::abs(a);}double MathMax(double a,double b){return std::max(a,b);}
double MathMin(double a,double b){return std::min(a,b);}double MathCeil(double a){return std::ceil(a);}
double MathFloor(double a){return std::floor(a);}bool MathIsValidNumber(double a){return std::isfinite(a);}
enum {TIME_DATE=1};
string TimeToString(long t,int){return std::to_string(t/86400*86400);}
long StringToTime(const string &s){return std::stol(s);}
enum {DEAL_ENTRY_IN=10,DEAL_ENTRY_OUT,DEAL_ENTRY_INOUT,DEAL_ENTRY_OUT_BY};
enum {DEAL_TYPE_BUY=100,DEAL_TYPE_SELL=101};
enum {DEAL_MAGIC=200,DEAL_ENTRY,DEAL_TYPE,DEAL_POSITION_ID,DEAL_TIME_MSC,DEAL_TIME,DEAL_SYMBOL,DEAL_PROFIT,DEAL_SWAP,DEAL_COMMISSION,DEAL_FEE};
int passed=0,failed=0;
void T1724Check(const string& name,bool ok){if(ok)passed++;else{failed++;std::cout<<"FAIL: "<<name<<"\n";}}
'''
header=(INC/'CashLedger.mqh').read_text()
inc=OUT/'include/BlackDragon';inc.mkdir(parents=True,exist_ok=True)
(inc/'CashLedger.mqh').write_text(adapt_arrays(header))
manifest.append({'path':'BlackDragon_v14/Include/BlackDragon/CashLedger.mqh','sha256':hashlib.sha256(header.encode()).hexdigest(),'adapter':'dynamic array declarations -> std::vector; platform functions use shared history fixture'})
cash=bridge+'\n#include "'+str(INC/'Pyramid/PyramidProtectionPolicy.mqh')+'"\n#include "'+str(TEST/'t1724_cash_fixture.mqh')+'"\n'
cash+='int main(){T1724RunCashCases();std::cout<<"T17.24 production cash fixture: "<<passed<<" passed, "<<failed<<" failed\\n";return failed?1:0;}\n'
cash_rc=run('cash_integration',cash)

rel='BlackDragon_v14/Include/BlackDragon/Recovery/RecoveryArcsStack.mqh'
s=(REPO/rel).read_text() if not args.replay_baseline else subprocess.check_output(['git','show',args.replay_baseline+':'+rel],cwd=REPO,text=True)
signatures=['bool CursorAfter(', 'void TrackCursor(', 'long ResolveClosedOwnerMagic(',
 'eRecoveryCoreDirection DirectionForClose(', 'bool T1722DealAfterCursor(',
 'void ApplyCloseDeal(', 'bool ReplayAfterCursor(']
bodies='\n'.join(extract(s,n) for n in signatures)
replay=bridge+r'''
enum eRecoveryCoreDirection {recovery_CORE_BUY=0,recovery_CORE_SELL=1};
enum {ARCS_CORE_FUNDING=14};
int PyramidSLMode_=1;const int py_protect_OFF=0;long Magic=100,RecoveryMagic_=200;
string _Symbol="fixture";
struct Deal {ulong id;long time;double cash;};
std::vector<Deal> db={{2,150000,-50},{3,250000,-5}};
std::vector<ulong> selected;
bool HistorySelect(datetime a,datetime b){selected.clear();for(auto d:db)if(d.time>=a*1000&&d.time<=b*1000)selected.push_back(d.id);return true;}
bool HistoryDealSelect(ulong id){for(auto d:db)if(d.id==id){selected={id};return true;}return false;}
bool HistorySelectByPosition(ulong){selected.clear();return false;}
int HistoryDealsTotal(){return selected.size();}
ulong HistoryDealGetTicket(int i){return selected.at(i);}
long HistoryDealGetInteger(ulong id,int k){if(k==DEAL_MAGIC)return Magic;if(k==DEAL_TYPE)return DEAL_TYPE_BUY;if(k==DEAL_ENTRY)return DEAL_ENTRY_OUT;for(auto d:db)if(d.id==id)return d.time;return 0;}
string HistoryDealGetString(ulong,int){return _Symbol;}
double HistoryDealGetDouble(ulong id,int k){if(k!=DEAL_PROFIT)return 0;for(auto d:db)if(d.id==id)return d.cash;return 0;}
long TimeCurrent(){return 300;}
double Recovery_DealCashPure(double p,double s,double c,double f){return p+s+c+f;}
struct State {long lastDealTimeMsc=0;ulong lastDealTicket=0;int phase=ARCS_CORE_FUNDING;double coreLossSpent=0;};
void Recovery_ArcsRecomputeCredit(State&){}
struct OptionalProtect {bool operator!=(std::nullptr_t){return false;}bool ExpectedRhTrim(ulong){return false;}} g_pyramidProtection;
class Fixture {public:
 State m_dir[2];bool m_dirty=false;
 int Idx(eRecoveryCoreDirection d)const{return d;}
 void ApplyRecoveryCloseDeal(ulong,eRecoveryCoreDirection,int,double,bool){}
'''+adapt_arrays(bodies).replace('g_pyramidProtection!=NULL','g_pyramidProtection!=nullptr')+r'''
};
int main(){
 Fixture f;f.m_dir[0].lastDealTimeMsc=200000;f.m_dir[0].lastDealTicket=1;
 f.m_dir[1].lastDealTimeMsc=100000;f.m_dir[1].lastDealTicket=1;
 string why;bool ok=f.ReplayAfterCursor(recovery_CORE_BUY,why)&&f.ReplayAfterCursor(recovery_CORE_SELL,why);
 double first=f.m_dir[1].coreLossSpent;
 bool again=f.ReplayAfterCursor(recovery_CORE_BUY,why)&&f.ReplayAfterCursor(recovery_CORE_SELL,why);
 T1724Check("Q11 full batch consumes both closes despite HistoryDealSelect list reset",ok&&first==55);
 T1724Check("Q12 duplicate replay exact once",again&&f.m_dir[1].coreLossSpent==55);
 std::cout<<"T17.24 production replay fixture: actual="<<first<<" expected=55; "<<passed<<" passed, "<<failed<<" failed\n";
 return failed?1:0;
}
'''
replay_rc=run('replay_integration',replay)

protect=(INC/'Pyramid/PyramidProtection.mqh').read_text()
structs=protect[protect.index('enum ePyProtectPhase'):protect.index('struct SPyProtectBinding')]
bodies='\n'.join(extract(protect,n) for n in [
 'int Pending()','int Find(','void EraseOperationAt(','bool RetryAllowed(',
 'void RecordNoEffectReject(','bool PendingIdentity(','bool OnDefinitiveReject(',
 'double Reserve(','double NetAt(','bool CandidateReady(','int PrepareBeforeArm(','int DriveSide('])
protection=bridge+r"""
#define Log_Info(...) do {} while(false)
#define Log_Error(...) do {} while(false)
#define Log_WarnEvery(...) do {} while(false)
template<class T>void ZeroMemory(T&v){v=T{};}
enum {py_protect_OFF=0,py_protect_VIRTUAL=1,py_protect_BROKER=2,recovery_ACTIVE=1};
enum {PY_DRIVE_NEXT=-1,PY_DRIVE_ALLOW=0,PY_DRIVE_BLOCK=1,PY_DRIVE_WAIT_UNFUNDED=2};
enum {EXEC_CMD_PY_RH_TRIM=1,EXEC_CMD_PY_PROTECT_MODIFY=2,EXEC_CMD_PY_PROTECT_CLOSE=3};
enum {POSITION_VOLUME=1,POSITION_SL=2,POSITION_IDENTIFIER=3,SYMBOL_TRADE_STOPS_LEVEL=4,SYMBOL_TRADE_FREEZE_LEVEL=5};
long serverNow=100;long TimeCurrent(){return serverNow;}
int PyramidSLMode_=py_protect_VIRTUAL,RecoveryMode_=recovery_ACTIVE;
double PyramidLockProfitPips_=3,PyramidBETriggerPips_=10,PyramidLockSafetyPips_=1,PyramidTrailGapPips_=0;
struct Config {double SlippagePrice=0;} Cfg;
string _Symbol="fixture";int _Digits=2;
bool positionPresent=true;double brokerSl=3000,brokerLots=1;ulong brokerId=1;
bool PositionSelectByTicket(ulong){return positionPresent;}
long PositionGetInteger(int){return brokerId;}
double PositionGetDouble(int k){return k==POSITION_SL?brokerSl:brokerLots;}
long SymbolInfoInteger(string,int){return 0;}
struct EAContext {double bid=3005,ask=3005.2;long now=100;};
struct FakeExec {bool HasPendingMutation(){return false;}};
struct FakeRecovery {bool T1722PyMutationQuiet(int){return true;}};
struct FakeBasket {void Invalidate(){}};
"""+'\n#include "'+str(INC/'Pyramid/PyramidProtectionPolicy.mqh')+'"\n'+structs+r"""
class ProtectionFixture {public:
 SPyProtectGroup m_group[2]{};SPyProtectSnapshot m_snap[2]{};SPyProtectRetry m_retry[2]{};
 std::vector<SPyProtectOperation> m_ops;std::vector<SPyProtectMember> m_members;
 FakeExec m_exec;FakeRecovery m_recovery;FakeBasket m_basket;
 bool m_fault=false,m_historyDirty=false,saveOk=true;int saves=0,sends=0;
 double m_tick=.01,m_step=.01,m_pip=.1,m_point=.01,m_slope=100;
 long core=100,hedge=100,reserved=40;double trimNet=-120;
 bool Enabled(){return true;}bool Save(){saves++;return saveOk;}
 void Fault(string){m_fault=true;}int Rdir(int d){return d;}
 bool Exposure(int,long&c,long&h,long&r){c=core;h=hedge;r=reserved;return true;}
 double CapPct(){return 100;}
 bool SelectTrim(int,long,ulong&t,double&lots,double&net){t=9;lots=.4;net=trimNet;return true;}
 bool StartOperation(int,int,ulong,double,double){sends++;return true;}
 int DriveRelease(int,const EAContext&){return PY_DRIVE_NEXT;}
 int DriveFlatSettlement(int,const EAContext&){return PY_DRIVE_NEXT;}
 int DriveClosing(int){return PY_DRIVE_NEXT;}
 int DriveBrokerStops(int,double){return PY_DRIVE_NEXT;}
"""+bodies+r"""
};
int main(){
 EAContext ctx;ProtectionFixture f;
 f.m_group[0].phase=PY_WATCH;f.m_group[0].serial=1;
 f.m_snap[0].valid=true;f.m_snap[0].count=1;f.m_snap[0].lots=.2;
 f.m_snap[0].weighted=3000;f.m_snap[0].floating=100;
 int status=f.DriveSide(0,ctx);
 T1724Check("Q02 unfunded RH cannot arm PY",status==PY_DRIVE_WAIT_UNFUNDED&&f.m_group[0].phase==PY_PREPARE&&f.sends==0);
 double floor=f.m_group[0].candidate;int saves=f.saves;
 f.PrepareBeforeArm(0,ctx,6,2,.01);
 T1724Check("T1724 extra: unchanged durable wait avoids repeated write",f.saves==saves&&f.m_group[0].candidate==floor);
 ctx.bid=3020;ctx.ask=3020.2;status=f.DriveSide(0,ctx);
 T1724Check("Q04 funded improvement progresses to RH trim",f.sends==1&&f.m_group[0].phase==PY_PREPARE&&status==PY_DRIVE_BLOCK);
 ProtectionFixture a;a.m_group[0].phase=PY_PREPARE;a.m_group[0].serial=1;a.m_members.resize(1);
 a.m_members[0].id=1;a.m_members[0].requestedSl=3001;a.m_members[0].confirmedSl=3000;
 SPyProtectOperation op{};op.id=1;op.ticket=99;op.dir=0;op.serial=1;op.nonce=42;
 op.kind=EXEC_CMD_PY_PROTECT_MODIFY;op.targetSl=3001;op.beforeLots=1;
 a.m_ops.push_back(op);ulong id=0;long nonce=0;
 T1724Check("Q09 submission captures exact immutable identity",a.PendingIdentity(172200,op.kind,99,id,nonce)&&id==1&&nonce==42);
 T1724Check("Q09 stale nonce cannot settle new op",!a.OnDefinitiveReject(172200,op.kind,99,1,41,10006)&&a.m_ops.size()==1);
 T1724Check("Q09 wrong ID cannot settle",!a.OnDefinitiveReject(172200,op.kind,99,2,42,10006)&&a.m_ops.size()==1);
 brokerSl=3001;
 T1724Check("Q10 live SL contradicts no-effect reject",!a.OnDefinitiveReject(172200,op.kind,99,1,42,10006)&&a.m_ops.size()==1);
 brokerSl=3000;
 T1724Check("Q07 exact no-effect reject ACK after save",a.OnDefinitiveReject(172200,op.kind,99,1,42,10006)&&a.m_ops.empty()&&a.saves==1);
 T1724Check("Q07 requested SL rolled back confirmed SL",a.m_members[0].requestedSl==3000);
 T1724Check("Q07 group obligation retained",a.m_group[0].phase==PY_PREPARE);
 T1724Check("Q29 no immediate retry",!a.RetryAllowed(0,op.kind,1)&&a.m_retry[0].nextEligible==101);
 serverNow=101;
 T1724Check("Q29 due retry admitted",a.RetryAllowed(0,op.kind,1));
 for(int i=1;i<8;i++){a.RecordNoEffectReject(op,10006);serverNow=a.m_retry[0].nextEligible;}
 T1724Check("Q30 exhausted budget reconciles obligation",a.m_retry[0].rejects==8&&a.m_retry[0].reconcile&&!a.RetryAllowed(0,op.kind,1)&&a.m_group[0].phase==PY_PREPARE);
 ProtectionFixture close;op.kind=EXEC_CMD_PY_PROTECT_CLOSE;op.requestedLots=1;close.m_ops.push_back(op);brokerLots=.5;
 T1724Check("Q08 partial volume contradicts reject",!close.OnDefinitiveReject(172200,op.kind,99,1,42,10006)&&close.m_ops.size()==1);
 brokerLots=1;close.saveOk=false;
 T1724Check("Q10 save failure refuses ACK and latches fault",!close.OnDefinitiveReject(172200,op.kind,99,1,42,10006)&&close.m_fault);
 std::cout<<"T17.24 production protection fixture: "<<passed<<" passed, "<<failed<<" failed\n";
 return failed?1:0;
}
"""
protection_rc=run('protection_integration',protection)

position_header=(INC/'PositionBook.mqh').read_text()
manifest.append({'path':'BlackDragon_v14/Include/BlackDragon/PositionBook.mqh','sha256':hashlib.sha256(position_header.encode()).hexdigest(),'adapter':'includes replaced by API fixture and exact production unit-floor helper; OC_IsPyramid role lookup stubbed'})
position_header=re.sub(r'^#include .+$','',position_header,flags=re.M)
math=(INC/'Recovery/RecoveryMath.mqh').read_text()
position=bridge+r"""
enum {POSITION_TYPE_BUY=0,POSITION_TYPE_SELL=1};
enum {POSITION_SYMBOL=300,POSITION_MAGIC,POSITION_TYPE,POSITION_VOLUME,POSITION_PRICE_OPEN,POSITION_COMMENT,POSITION_IDENTIFIER,POSITION_SL,POSITION_TP,POSITION_SWAP,POSITION_PROFIT};
struct Position {ulong ticket;long owner,type;double lots;string symbol,comment;};
std::vector<Position> positions={{1,100,0,.30,"fixture","Seed"},{2,100,0,.20,"fixture","PY"},{3,100,1,.10,"fixture","DCA"},{4,200,1,.40,"fixture","RH"},{5,200,0,.15,"fixture","RH"},{6,300,0,10,"fixture","foreign"},{7,100,0,20,"else","Seed"}};
int selectedPosition=0;bool badTicket=false;
int PositionsTotal(){return positions.size();}
ulong PositionGetTicket(int i){selectedPosition=i;return badTicket?0:positions.at(i).ticket;}
long PositionGetInteger(int k){auto p=positions.at(selectedPosition);return k==POSITION_MAGIC?p.owner:(k==POSITION_IDENTIFIER?(long)p.ticket+1000:p.type);}
double PositionGetDouble(int k){return k==POSITION_VOLUME?positions.at(selectedPosition).lots:3000;}
string PositionGetString(int k){auto p=positions.at(selectedPosition);return k==POSITION_SYMBOL?p.symbol:p.comment;}
bool OC_IsPyramid(const string&s){return s=="PY";}
bool PositionSelectByTicket(ulong ticket){for(int i=0;i<(int)positions.size();i++)if(positions[i].ticket==ticket){selectedPosition=i;return true;}return false;}
"""+extract(math,'long Recovery_VolumeToUnitsFloor(')+'\n'+position_header+r"""
struct PositionInfo {ulong ticket=0,positionId=0;double lots=0,openPrice=0,sl=0,tp=0,swap=0,profit=0;};
struct BasketSide {int count=0;double totalLots=0,totalProfit=0,swapSum=0;std::vector<PositionInfo> pos;};
class BasketFixture {public:bool m_dirty=false;ulong m_revision=0;
"""+extract((INC/'BasketManager.mqh').read_text(),'bool RefreshFloating(')+r"""
};
int main(){
 CObservationPositionBook book;
 T1724Check("Q27 full observation capture",book.Begin("fixture",100,200,.01));
 T1724Check("Q27 matching scope valid",book.Matches("fixture",100,200,.01));
 T1724Check("Q27 economic Core includes Pyramid",book.CoreUnits(0)==50&&book.CoreUnits(1)==10);
 T1724Check("Q28 trigger count excludes Pyramid",book.CoreCount(0)==1&&book.CoreCount(1)==1);
 T1724Check("Q28 hedge mapped by protected Core direction",book.HedgeUnits(0)==40&&book.HedgeUnits(1)==15);
 T1724Check("Q27 wrong symbol/magic/step cannot use snapshot",!book.Matches("else",100,200,.01)&&!book.Matches("fixture",999,200,.01)&&!book.Matches("fixture",100,200,.1));
 T1724Check("Q33 one account enumeration",book.Scans()==1&&book.Visits()==7);
 book.End();
 T1724Check("Q55 snapshot unavailable at mutation boundary",!book.Matches("fixture",100,200,.01));
 positions[0].lots=.12;book.Begin("fixture",100,200,.01);
 T1724Check("Q55 new capture sees external volume change",book.CoreUnits(0)==32);
 badTicket=true;
 T1724Check("Q27 partial read never published",!book.Begin("fixture",100,200,.01)&&!book.Matches("fixture",100,200,.01));
 BasketFixture basket;BasketSide side;side.count=1;side.pos.resize(1);side.pos[0].ticket=1;
 side.pos[0].positionId=1001;side.pos[0].openPrice=3000;side.pos[0].lots=.30;
 T1724Check("T1724 external volume change requires same-tick second pass",basket.RefreshFloating(side)&&basket.m_dirty);
 T1724Check("T1724 basket live lots refreshed in OFF path",std::abs(side.totalLots-.12)<1e-9);
 T1724Check("T1724 unchanged live basket does not force another pass",!basket.RefreshFloating(side));
 std::cout<<"T17.24 production observation fixture: "<<passed<<" passed, "<<failed<<" failed\n";
 return failed?1:0;
}
"""
position_rc=run('position_integration',position)
(OUT/'extraction.json').write_text(json.dumps(manifest,indent=2))
(OUT/'results.json').write_text(json.dumps({'cash_rc':cash_rc,'replay_rc':replay_rc,'protection_rc':protection_rc,'position_rc':position_rc,'replay_source':args.replay_baseline or 'working_tree','native':False},indent=2))
raise SystemExit(cash_rc or replay_rc or protection_rc or position_rc)
