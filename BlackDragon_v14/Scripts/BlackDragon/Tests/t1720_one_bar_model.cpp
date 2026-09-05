// Compiles the actual MQL runtime gate against deterministic broker adapters.
#include <iostream>
#include <string>
#include <vector>
#include <algorithm>
using string=std::string;
using datetime=long;
#define BD_RECOVERY_TYPES_MQH
bool RecoveryOneOrderPerBar_=false;
long RecoveryMagic_=20260807;
string _Symbol="XAUUSDm";
enum {PERIOD_CURRENT=0,POSITION_TYPE_BUY=0,POSITION_TYPE_SELL=1,
      DEAL_TYPE_BUY=0,DEAL_TYPE_SELL=1,DEAL_ENTRY_IN=0,DEAL_ENTRY_OUT=1,
      DEAL_ENTRY_INOUT=2,DEAL_ENTRY_OUT_BY=3,POSITION_SYMBOL=10,
      POSITION_MAGIC=11,POSITION_TYPE=12,POSITION_TIME_MSC=13,
      DEAL_SYMBOL=20,DEAL_MAGIC=21,DEAL_TYPE=22,DEAL_ENTRY=23,DEAL_TIME_MSC=24};
struct Item {string symbol="XAUUSDm";long owner=20260807,type=1,entry=0,msc=6010000;};
std::vector<Item> live,history;
std::vector<int> selected;
datetime currentBar=6000;
bool historyReady=true,badPosition=false,badDeal=false;
int reads=0,positionIndex=0;
datetime iTime(const string&,int,int){++reads;return currentBar;}
int PositionsTotal(){++reads;return static_cast<int>(live.size());}
unsigned long PositionGetTicket(int i){positionIndex=i;return badPosition?0:static_cast<unsigned long>(i+1);}
string PositionGetString(int){return live[positionIndex].symbol;}
long PositionGetInteger(int prop){auto p=live[positionIndex];return prop==POSITION_MAGIC?p.owner:prop==POSITION_TYPE?p.type:p.msc;}
bool HistorySelect(datetime from,datetime to){++reads;selected.clear();if(!historyReady)return false;for(int i=0;i<static_cast<int>(history.size());++i)if(history[i].msc>=from*1000&&history[i].msc<=(to+1)*1000-1)selected.push_back(i);return true;}
int HistoryDealsTotal(){return static_cast<int>(selected.size());}
unsigned long HistoryDealGetTicket(int i){return badDeal?0:static_cast<unsigned long>(selected[i]+1);}
string HistoryDealGetString(unsigned long t,int){return history[t-1].symbol;}
long HistoryDealGetInteger(unsigned long t,int prop){auto p=history[t-1];return prop==DEAL_MAGIC?p.owner:prop==DEAL_TYPE?p.type:prop==DEAL_ENTRY?p.entry:p.msc;}
#include "../../../Include/BlackDragon/Recovery/RecoveryOpenBarGate.mqh"

void Reset(){RecoveryOneOrderPerBar_=true;live.clear();history.clear();selected.clear();currentBar=6000;historyReady=true;badPosition=badDeal=false;reads=0;}
int main(){
 int pass=0,fail=0;string why;
 auto ck=[&](const char* name,bool ok){if(ok)++pass;else{++fail;std::cerr<<"FAIL "<<name<<'\n';}};
 auto allow=[&](int dir=1,datetime now=6030){return Recovery_OneOrderPerBarAllows(dir,now,why);};
 Reset();RecoveryOneOrderPerBar_=false;currentBar=0;historyReady=false;live.push_back({});
 ck("OFF is exact no-read bypass",allow()&&reads==0&&why.empty());
 Reset();ck("first RH is immediately eligible",allow());
 Reset();Item core;core.owner=1111;live.push_back(core);history.push_back(core);ck("Core DCA does not consume first RH slot",allow());
 Reset();live.push_back({});ck("live RH blocks same direction",!allow());
 ck("live opposite RH direction remains independent",allow(0));
 Reset();history.push_back({});ck("closed SL opening remains counted",!allow());
 ck("new G1 cannot erase current-bar history",!allow());
 ck("restart without cache still finds closed RH",!allow());
 ck("history opposite direction remains independent",allow(0));
 Reset();Item be;history.push_back(be);be.entry=DEAL_ENTRY_OUT;be.type=0;be.msc=6020000;history.push_back(be);ck("BE close cannot refund its opening slot",!allow());
 Reset();Item old;old.msc=5999999;history.push_back(old);live.push_back(old);ck("prior candle RH does not consume new candle",allow());
 Item close=old;close.msc=6020000;close.entry=DEAL_ENTRY_OUT;close.type=0;history.push_back(close);ck("SL of prior-bar RH allows this-bar re-entry",allow());
 Reset();Item boundary;boundary.msc=6000000;history.push_back(boundary);ck("exact bar boundary counts",!allow());
 Reset();Item split;history.push_back(split);split.msc++;history.push_back(split);ck("multiple fills keep candle occupied",!allow());
 Reset();ck("definite rejection without fills permits retry",allow());history.push_back({});ck("accepted fill blocks next bundle child",!allow());
 currentBar=6060;ck("next bar releases bundle child",allow(1,6061));
 Reset();Item other;other.symbol="EURUSDm";history.push_back(other);live.push_back(other);ck("other symbol excluded",allow());
 Reset();other=Item{};other.owner=99;history.push_back(other);live.push_back(other);ck("other Magic excluded",allow());
 Reset();other=Item{};other.type=0;history.push_back(other);ck("BUY Recovery excluded from SELL gate",allow());ck("BUY Recovery counted in BUY gate",!allow(0));
 Reset();other=Item{};other.entry=DEAL_ENTRY_OUT;history.push_back(other);ck("closing deals excluded",allow());
 history[0].entry=DEAL_ENTRY_OUT_BY;ck("close-by excluded",allow());
 history[0].entry=DEAL_ENTRY_INOUT;ck("opening component of reversal counted",!allow());
 Reset();currentBar=0;ck("missing chart bar waits",!allow()&&!why.empty());
 Reset();ck("stale now before chart bar waits",!allow(1,5999));
 Reset();historyReady=false;ck("history failure waits",!allow()&&!why.empty());historyReady=true;ck("history retry releases without latch",allow());
 Reset();badPosition=true;live.push_back({});ck("incomplete position snapshot waits",!allow());
 Reset();badDeal=true;history.push_back({});ck("incomplete deal snapshot waits",!allow());
 Reset();ck("invalid direction waits",!allow(2));
 Reset();RecoveryOneOrderPerBar_=false;history.push_back({});ck("OFF ignores existing same-bar RH",allow());RecoveryOneOrderPerBar_=true;ck("toggle ON rebuilds from broker history",!allow());
 Reset();Item prior;prior.msc=5701000;live.push_back(prior);history.push_back(prior);ck("M1 sees earlier M1 bar",allow());currentBar=5700;ck("M5 current chart bar covers the same earlier open",!allow());
 std::cout<<"T17.20 RH one-bar model: "<<pass<<" passed, "<<fail<<" failed\n";
 if(!fail)std::cout<<"ALL GREEN\n";
 return fail?1:0;
}
