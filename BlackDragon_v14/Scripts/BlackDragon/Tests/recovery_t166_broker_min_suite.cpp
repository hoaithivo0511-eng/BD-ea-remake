// T16.6 broker-min generation + active-layer partial-close pure regression.
#include <algorithm>
#include <cmath>
#include <iostream>
using std::cout;
static int passed=0, failed=0;
#define CHECK(name,expr) do{if(expr){++passed;}else{++failed;cout<<"FAIL "<<name<<"\n";}}while(0)

static long percentUnits(long core,double pct){
  if(core<=0||pct<=0.0) return 0;
  return (long)std::floor((double)core*pct/100.0+1e-9);
}
static long rawGeneration(bool stacked,long core,long existing,double pct){
  long desired=percentUnits(core,pct);
  if(desired<=0) return 0;
  if(stacked) return desired;
  existing=std::max(0L,existing);
  return desired>existing?desired-existing:0;
}
static long clampGeneration(long raw,long minUnits){
  if(raw<=0) return 0;
  if(minUnits<=0) return raw;
  return raw<minUnits?minUnits:raw;
}
static long executablePartial(long active,double pct,long minUnits){
  if(active<=0||pct<=0.0||pct>100.0||minUnits<=0) return 0;
  if(active<minUnits) return 0;
  if(pct>=100.0-1e-12) return active;
  long target=(long)std::floor((double)active*pct/100.0+1e-9);
  if(target<minUnits) target=minUnits;
  if(target>=active) return active;
  long remaining=active-target;
  if(remaining==0||remaining>=minUnits) return target;
  long reduced=active-minUnits;
  if(reduced>=minUnits&&reduced<target) return reduced;
  return active;
}

int main(){
  CHECK("zero raw does not invent Hedge", clampGeneration(0,2)==0);
  CHECK("sub-min raw clamps to broker minimum", clampGeneration(1,2)==2);
  CHECK("exact broker minimum unchanged", clampGeneration(2,2)==2);
  CHECK("above broker minimum unchanged", clampGeneration(5,2)==5);
  CHECK("balanced raw deficit reproduces five units", rawGeneration(false,80,87,115.0)==5);
  CHECK("balanced raw five clamps to min ten", clampGeneration(rawGeneration(false,80,87,115.0),10)==10);

  CHECK("active56 pct15 closes8", executablePartial(56,15.0,1)==8);
  CHECK("active45 pct15 closes6", executablePartial(45,15.0,1)==6);
  CHECK("active7 pct15 closes1", executablePartial(7,15.0,1)==1);
  CHECK("active6 pct15 closes1", executablePartial(6,15.0,1)==1);
  CHECK("G7 active5 pct15 closes1", executablePartial(5,15.0,1)==1);
  CHECK("one-min layer full closes", executablePartial(1,15.0,1)==1);
  CHECK("illegal remainder reduces to legal close", executablePartial(25,90.0,10)==15);
  CHECK("no legal partial full closes tiny layer", executablePartial(15,15.0,10)==15);
  CHECK("illegal live exposure below min stays fail-closed", executablePartial(9,15.0,10)==0);
  CHECK("100 percent remains full close", executablePartial(5,100.0,1)==5);

  cout<<"Recovery T16.6 broker-min model: "<<passed<<" passed, "<<failed<<" failed\n";
  if(failed==0) cout<<"ALL GREEN — T16.6 broker-min generation/partial-close policy passed.\n";
  return failed==0?0:1;
}
