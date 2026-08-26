#include <cmath>
#include <iostream>
#include <vector>

enum AnchorMode { DYNAMIC=0, FIRST_CORE_CUMULATIVE=1 };
static int pass=0, fail=0;
void check(const char* n,bool c){ if(c) ++pass; else {++fail; std::cerr<<"FAIL: "<<n<<"\n";} }
bool near(double a,double b){ return std::fabs(a-b)<=1e-9; }
bool valid(int mode){ return mode==DYNAMIC || mode==FIRST_CORE_CUMULATIVE; }
double seq(const std::vector<double>& v,int idx){ if(v.empty()) return 0; if(idx<0) idx=0; if(idx>=(int)v.size()) idx=(int)v.size()-1; return v[idx]; }
double cumulative(const std::vector<double>& v,int serial){ if(serial<=0||v.empty()) return 0; double s=0; for(int i=0;i<serial;i++) s+=seq(v,i); return s; }
double trigger(int dir,double anchor,double gap){ if(anchor<=0||gap<0) return 0; return dir==0?anchor+gap:anchor-gap; }
bool hit(int dir,double anchor,double bid,double ask,double gap){ if(anchor<=0||bid<=0||ask<=0||gap<0) return false; double t=trigger(dir,anchor,gap); return dir==0?ask+1e-12>=t:bid-1e-12<=t; }
int main(){
  std::vector<double> d{25,35,38};
  check("dynamic valid",valid(DYNAMIC));
  check("first-core valid",valid(FIRST_CORE_CUMULATIVE));
  check("invalid rejected",!valid(99));
  check("L1 cumulative 25",near(cumulative(d,1),25));
  check("L2 cumulative 60",near(cumulative(d,2),60));
  check("L3 cumulative 98",near(cumulative(d,3),98));
  check("L4 repeats last => 136",near(cumulative(d,4),136));
  check("L5 repeats last => 174",near(cumulative(d,5),174));
  check("BUY trigger symmetric",near(trigger(0,2000,98),2098));
  check("SELL trigger symmetric",near(trigger(1,2000,98),1902));
  check("BUY equality hit",hit(0,2000,2097.9,2098,98));
  check("BUY below target waits",!hit(0,2000,2097.8,2097.9,98));
  check("SELL equality hit",hit(1,2000,1902,1902.1,98));
  check("SELL above target waits",!hit(1,2000,1902.1,1902.2,98));
  std::cout<<"T17.7 C2 anchor model: "<<pass<<" passed, "<<fail<<" failed\n";
  if(!fail) std::cout<<"ALL GREEN\n";
  return fail?1:0;
}
