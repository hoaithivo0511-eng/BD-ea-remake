#include <algorithm>
#include <cmath>
#include <iostream>
#include <vector>

struct Stage { int source; double req; long gen; long total; double eff; double gap; };
long pct(long core,double p){ return core<=0||p<=0?0:(long)std::floor(core*p/100.0+1e-9); }
double final_pct(double requested,double cap){ return requested<=0?0:(cap>0&&requested>cap?cap:requested); }
long final_raw(long core,long retained,double p){ long d=pct(core,p); retained=std::max(0L,retained); return d>retained?d-retained:0; }
long executable(long core,long retained,double p,long minU,long finalRaw){
  if(core<=0||p<=0||finalRaw<=0) return 0;
  long raw=std::max(0L,pct(core,p)-std::max(0L,retained));
  if(raw<=0) return 0;
  long planned=(minU>0&&raw<minU)?minU:raw;
  return planned>finalRaw?0:planned;
}
double seq(const std::vector<double>&v,int i){ if(v.empty()) return 0; if(i<0)i=0; if(i>=(int)v.size())i=(int)v.size()-1; return v[i]; }
std::vector<Stage> build(const std::vector<double>&cov,const std::vector<double>&gaps,long core,long retained,long minU){
  std::vector<Stage> out; if(cov.empty()||core<=0)return out;
  long fr=final_raw(core,retained,cov.back()); if(fr<=0||(minU>0&&fr<minU))return out;
  bool have=false; long last=0; double acc=0;
  for(int i=0;i<(int)cov.size();++i){
    if(i>0) acc+=seq(gaps,i-1);
    long p=executable(core,retained,cov[i],minU,fr);
    if(p<=0){ if(!have) acc=0; continue; }
    if(have&&p<=last) continue;
    long total=std::max(0L,retained)+p;
    out.push_back({i,cov[i],p,total,100.0*total/core,have?acc:0.0});
    have=true; last=p; acc=0;
  }
  return out;
}
int main(){
  int pass=0,fail=0; auto ck=[&](const char*n,bool v){if(v)++pass;else{++fail;std::cerr<<"FAIL "<<n<<"\n";}};
  ck("final 160 capped to 90", std::abs(final_pct(160,90)-90)<1e-9);
  ck("zero cap leaves requested final", std::abs(final_pct(160,0)-160)<1e-9);
  ck("core42 80pct floors33", pct(42,80)==33);
  ck("core42 81pct floors34", pct(42,81)==34);
  ck("core42 82pct floors34", pct(42,82)==34);
  ck("core42 85pct floors35", pct(42,85)==35);
  auto p=build({80,81,82,85},{10,10,15},42,0,1);
  ck("80-81-82-85 dedups to 3 executable stages",p.size()==3);
  ck("first executable stage keeps source 80",p.size()==3&&p[0].source==0&&p[0].gen==33);
  ck("duplicate 82 keeps first 81 target",p.size()==3&&p[1].source==1&&p[1].gen==34);
  ck("final executable stage is 85 target35",p.size()==3&&p[2].source==3&&p[2].gen==35);
  ck("gap 80 to81 remains10",p.size()==3&&std::abs(p[1].gap-10)<1e-9);
  ck("skipped82 remaps gap 81 to85 as25",p.size()==3&&std::abs(p[2].gap-25)<1e-9);
  ck("effective 85 stage is 83.333pct",p.size()==3&&std::abs(p[2].eff-83.3333333333)<1e-6);
  auto r=build({80,81,82,85},{10,10,15},42,33,1);
  ck("already-covered leading stage gives first new gap0",r.size()>=1&&r[0].source==1&&std::abs(r[0].gap)<1e-9);
  ck("retained path still dedups82",r.size()==2&&r[0].source==1&&r[1].source==3);
  ck("retained duplicate gap to85 stays25",r.size()==2&&std::abs(r[1].gap-25)<1e-9);
  ck("final raw 108core retained30 at90 is67",final_raw(108,30,90)==67);
  ck("broker min may not inflate beyond final cap",executable(100,0,1.0,2,1)==0);
  auto tiny=build({0.5,1.0},{10},100,0,2);
  ck("unexecutable final below broker min produces no stage",tiny.empty());
  ck("executable target never exceeds final raw",executable(42,0,82,1,35)<=35);
  std::cout<<"T17.7 C4 Hedge ladder model: "<<pass<<" passed, "<<fail<<" failed\n";
  if(fail==0) std::cout<<"ALL GREEN\n";
  return fail==0?0:1;
}
