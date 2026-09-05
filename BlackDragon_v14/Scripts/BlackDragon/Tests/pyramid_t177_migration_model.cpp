#include <algorithm>
#include <cmath>
#include <iostream>
#include <string>

enum Policy { LEG=-1, OFF=0, CORE=1, ALLOW=2 };

Policy policy(Policy req, bool overlap, bool after)
{
  if(req!=LEG) return req;
  if(after) return ALLOW;
  return overlap ? CORE : OFF;
}

bool enabled(Policy req,bool overlap,bool after)
{ return policy(req,overlap,after)!=OFF; }

double target(double requested,double legacy)
{ return requested>0.0 ? requested : legacy; }

double cap(double requested,double legacy)
{ return requested>=0.0 ? requested : legacy; }

double final_cov(double requested,double requestedCap,double legacyTarget,double legacyCap)
{
  double t=target(requested,legacyTarget), h=cap(requestedCap,legacyCap);
  if(t<=0.0) return 0.0;
  return h>0.0 ? std::min(t,h) : t;
}

int global_after(bool legacyEnable,int n)
{ return (!legacyEnable || n<=0) ? 0 : n; }

bool legacy_selectors(Policy p,double t,double c,bool legacyEnable,int n)
{
  if(p!=LEG || t>0.0 || c>=0.0) return false;
  if(legacyEnable && n<=0) return false;
  return true;
}

std::string dca_text(bool enabled,double min,double corridor)
{
  std::string s="continue="+std::to_string(enabled);
  if(enabled) s += "|min="+std::to_string(min)+"|corridor="+std::to_string(corridor);
  return s;
}

std::string global_text(int after,double profit,double buffer)
{
  std::string s="after="+std::to_string(after);
  if(after>0) s += "|profit="+std::to_string(profit)+"|buffer="+std::to_string(buffer);
  return s;
}

std::string overlap_text(Policy p,int from,double pct,bool manual)
{
  std::string s="policy="+std::to_string((int)p);
  if(p!=OFF) s += "|from="+std::to_string(from)+"|pct="+std::to_string(pct)+"|manual="+std::to_string(manual);
  return s;
}

long raw_units(long core,long existing,double pct)
{
  long desired=(long)std::floor((double)core*pct/100.0+1e-9);
  return desired>existing ? desired-existing : 0;
}

long staged_units(long core,long existing,double pct,long minUnits)
{
  long raw=raw_units(core,existing,pct);
  if(raw<=0) return 0;
  if(minUnits>0 && raw<minUnits) return 0; // no broker-min inflation above target
  return raw;
}

bool core_only_blocked(int state,double hedgeLots)
{
  if(hedgeLots>1e-12) return true;
  return !(state==0 || state==1 || state==13); // CORE_ONLY, ARMED, COMPLETED
}

int main()
{
  int pass=0, fail=0;
  auto ck=[&](const char* n,bool ok){ if(ok) ++pass; else { ++fail; std::cerr<<"FAIL "<<n<<"\n"; } };

  ck("legacy both false off", policy(LEG,false,false)==OFF);
  ck("legacy overlap core", policy(LEG,true,false)==CORE);
  ck("legacy after wins", policy(LEG,true,true)==ALLOW);
  ck("legacy contradictory after wins", policy(LEG,false,true)==ALLOW);
  ck("explicit off overrides", policy(OFF,true,true)==OFF);
  ck("explicit allow overrides", policy(ALLOW,false,false)==ALLOW);
  ck("decision off", !enabled(OFF,true,true));
  ck("decision explicit core with old off", enabled(CORE,false,false));

  ck("target legacy", std::abs(target(0,160)-160)<1e-9);
  ck("target new", std::abs(target(85,160)-85)<1e-9);
  ck("cap legacy", std::abs(cap(-1,90)-90)<1e-9);
  ck("cap disabled", std::abs(cap(0,90))<1e-9);
  ck("final hard cap", std::abs(final_cov(100,85,160,90)-85)<1e-9);
  ck("final no hard cap", std::abs(final_cov(100,0,160,90)-100)<1e-9);

  ck("global old off", global_after(false,5)==0);
  ck("global zero off", global_after(true,0)==0);
  ck("global active", global_after(true,5)==5);

  ck("legacy selectors", legacy_selectors(LEG,0,-1,true,5));
  ck("explicit target not legacy", !legacy_selectors(LEG,85,-1,true,5));
  ck("new global zero not old-valid", !legacy_selectors(LEG,0,-1,true,0));

  ck("inactive dca ignores knobs", dca_text(false,80,20)==dca_text(false,120,99));
  ck("active dca hashes knobs", dca_text(true,80,20)!=dca_text(true,120,99));
  ck("inactive global ignores knobs", global_text(0,3,10)==global_text(0,99,77));
  ck("active global hashes knobs", global_text(5,3,10)!=global_text(5,99,77));
  ck("overlap off ignores knobs", overlap_text(OFF,8,3,false)==overlap_text(OFF,20,50,true));
  ck("overlap active hashes knobs", overlap_text(CORE,8,3,false)!=overlap_text(CORE,20,50,true));

  ck("broker min does not inflate staged target", staged_units(10,0,85,10)==0);
  ck("broker min exact is executable", staged_units(100,0,10,10)==10);
  ck("retained hedge subtracts from final", staged_units(100,80,85,1)==5);

  ck("core only blocks live hedge", core_only_blocked(0,0.01));
  ck("core only allows armed no hedge", !core_only_blocked(1,0));
  ck("core only blocks active state", core_only_blocked(3,0));

  std::cout<<"T17.7 C5 migration model: "<<pass<<" passed, "<<fail<<" failed\n";
  if(fail==0) std::cout<<"ALL GREEN\n";
  return fail==0 ? 0 : 1;
}
