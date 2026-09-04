#include <iostream>
#include <string>
#include <vector>
#include <cstdlib>
using string=std::string;
using datetime=long;
int StringLen(const string&s){return static_cast<int>(s.size());}
int StringFind(const string&s,const string&n,int start=0){auto p=s.find(n,static_cast<size_t>(start));return p==string::npos?-1:static_cast<int>(p);}
string StringSubstr(const string&s,int p,int n=-1){return s.substr(static_cast<size_t>(p),n<0?string::npos:static_cast<size_t>(n));}
long StringToInteger(const string&s){return std::strtol(s.c_str(),nullptr,10);}
int StringGetCharacter(const string&s,int p){return static_cast<unsigned char>(s[static_cast<size_t>(p)]);}
string IntegerToString(int n){return std::to_string(n);}
#define BD_RECOVERY_TYPES_MQH
long RecoveryMagic_=20260807;
string _Symbol="XAUUSDm";
enum {POSITION_TYPE_BUY=0,POSITION_TYPE_SELL=1,DEAL_TYPE_BUY=0,DEAL_TYPE_SELL=1,
 DEAL_ENTRY_IN=0,DEAL_ENTRY_OUT=1,DEAL_ENTRY_INOUT=2,POSITION_SYMBOL=10,POSITION_MAGIC=11,
 POSITION_TYPE=12,POSITION_COMMENT=13,DEAL_SYMBOL=20,DEAL_MAGIC=21,DEAL_TYPE=22,DEAL_ENTRY=23,DEAL_COMMENT=24};
struct Item {string comment="RH-S|G1|N1";long type=1,owner=20260807,entry=0;string symbol="XAUUSDm";};
std::vector<Item> live,history;
int selected=0;bool historyReady=true;
int PositionsTotal(){return static_cast<int>(live.size());}
unsigned long PositionGetTicket(int i){selected=i;return static_cast<unsigned long>(i+1);}
string PositionGetString(int prop){return prop==POSITION_SYMBOL?live[selected].symbol:live[selected].comment;}
long PositionGetInteger(int prop){return prop==POSITION_MAGIC?live[selected].owner:live[selected].type;}
datetime TimeCurrent(){return 10000;}
bool HistorySelect(datetime,datetime){return historyReady;}
int HistoryDealsTotal(){return static_cast<int>(history.size());}
unsigned long HistoryDealGetTicket(int i){return static_cast<unsigned long>(i+1);}
string HistoryDealGetString(unsigned long n,int prop){return prop==DEAL_SYMBOL?history[n-1].symbol:history[n-1].comment;}
long HistoryDealGetInteger(unsigned long n,int prop){return prop==DEAL_MAGIC?history[n-1].owner:prop==DEAL_TYPE?history[n-1].type:history[n-1].entry;}
#include "../../../Include/BlackDragon/Recovery/RecoveryOrderComment.mqh"
int passed=0,failed=0;
void T1721Check(const string&name,bool ok){if(ok)++passed;else{++failed;std::cerr<<"FAIL "<<name<<'\n';}}
#include "t1721_comment_cases.mqh"
void Reset(){live.clear();history.clear();historyReady=true;}
int main()
{
 T1721CodecCases();
 Reset();T1721Check("runtime first RH",Recovery_BuildReadableComment(1,1,1,1,1,false)=="RH-S|G1|P1|N1");
 history.push_back({});T1721Check("runtime closed BE first reentry",Recovery_BuildReadableComment(1,1,1,1,1,true)=="RHSL1-S|G1|P1|N1");
 T1721Check("rejected request consumes no ordinal",Recovery_BuildReadableComment(1,1,1,1,1,true)=="RHSL1-S|G1|P1|N1");
 history.push_back({"RHSL1-S|G1|P1|N1"});live.push_back(history.back());
 T1721Check("restart after fill retains ordinal",Recovery_BuildReadableComment(1,1,1,2,2,true)=="RHSL1-S|G1|P2|N2");
 history.push_back({"RHSL1-S|G1|P2|N2"});live.push_back(history.back());
 T1721Check("broker partial fill same order no extra round",Recovery_BuildReadableComment(1,1,1,2,3,true)=="RHSL1-S|G1|P2|N3");
 live.erase(live.begin());T1721Check("closed earlier child does not reuse N",Recovery_BuildReadableComment(1,1,1,3,2,true)=="RHSL1-S|G1|P3|N3");
 live.clear();T1721Check("second protective reset increments",Recovery_BuildReadableComment(1,1,1,1,1,true)=="RHSL2-S|G1|P1|N1");
 T1721Check("new generation retains protective round",Recovery_BuildReadableComment(1,2,2,1,1,true)=="RHSL1-S|G2|P1|N1");
 T1721Check("fresh Core cycle resets label",Recovery_BuildReadableComment(1,1,1,1,1,false)=="RH-S|G1|P1|N1");
 history.push_back({"RHSL99-B|G1|N1",0});T1721Check("opposite side excluded",Recovery_BuildReadableComment(1,1,1,1,1,true)=="RHSL2-S|G1|P1|N1");
 history.push_back({"RHSL99-S|G1|N1",1,999});T1721Check("other owner excluded",Recovery_BuildReadableComment(1,1,1,1,1,true)=="RHSL2-S|G1|P1|N1");
 history.push_back({"RHSL99-S|G1|N1",1,20260807,0,"EURUSDm"});T1721Check("other symbol excluded",Recovery_BuildReadableComment(1,1,1,1,1,true)=="RHSL2-S|G1|P1|N1");
 history.push_back({"[sl]",0,20260807,1});T1721Check("close comment does not replace opening authority",Recovery_BuildReadableComment(1,1,1,1,1,true)=="RHSL2-S|G1|P1|N1");
 Reset();history.push_back({"BDR|C=1|G=1|B=1|N=1"});T1721Check("upgrade never invents ordinal",Recovery_BuildReadableComment(1,1,1,1,1,true)=="RHSL?-S|G1|P1|N1");
 historyReady=false;T1721Check("history failure stays display-only",Recovery_BuildReadableComment(1,1,1,1,1,true)=="RHSL?-S|G1|P1|N1");
 T1721Check("first entry does not need old history",Recovery_BuildReadableComment(1,1,1,1,1,false)=="RH-S|G1|P1|N1");
 Reset();history.push_back({"RH-B|G1|N1",0});T1721Check("BUY RH protective round",Recovery_BuildReadableComment(2,1,1,0,1,true)=="RHSL1-B|G1|N1");
 std::cout<<"T17.21 comment model: "<<passed<<" passed, "<<failed<<" failed\n";
 if(!failed)std::cout<<"ALL GREEN\n";
 return failed?1:0;
}
