#include <algorithm>
#include <cmath>
#include <iostream>

long pct(long core, double p)
{
  return core<=0||p<=0?0:(long)std::floor(core*p/100.0+1e-9);
}

long staged_total_cap(long core,long retained,long live,double coverage)
{
  long desired=pct(core,coverage);
  long before=std::max(0L,retained);
  long generation=std::max(0L,desired-before);
  return std::max(live,generation);
}

long rebase_add_only(long live,long computed)
{
  return std::max(live,std::max(0L,computed));
}

int main()
{
  int pass=0;
  auto ck=[&](const char*n,bool v){
    if(!v){std::cerr<<"FAIL "<<n<<"\n";return;}
    ++pass;
  };

  // Reconstruct the latest runtime smoking gun in volume-step units:
  // Core 1.08, retained older Hedge .30, current G3 live .18, hard cap 90%.
  ck("target before retained SL is .67", staged_total_cap(108,30,18,90.0)==67);
  ck("target rises to .97 after retained SL", staged_total_cap(108,0,18,90.0)==97);
  ck("policy rebase accepts target increase", rebase_add_only(18,97)==97);
  ck("policy rebase never reduces live", rebase_add_only(18,12)==18);
  ck("stage 30 pct subtracts retained .30", staged_total_cap(108,30,0,30.0)==2);
  ck("stage 45 pct subtracts retained .30", staged_total_cap(108,30,2,45.0)==18);

  // Absolute staged total coverage cap.
  ck("100 pct total cap with .50 retained means .50 new", staged_total_cap(100,50,0,100.0)==50);
  ck("90 pct total cap with .30 retained means .60 new", staged_total_cap(100,30,0,90.0)==60);

  auto attainable=[](double target,double hard){return hard>0?std::min(target,hard):target;};
  ck("DCA 80 reachable under target90", 80.0<=attainable(160,90)+1e-9);
  ck("DCA 100 unreachable under target90", !(100.0<=attainable(160,90)+1e-9));

  std::cout<<"T17.6 pure model: "<<pass<<" passed, 0 failed\n";
  if(pass==10) std::cout<<"ALL GREEN\n";
  return pass==10?0:1;
}
