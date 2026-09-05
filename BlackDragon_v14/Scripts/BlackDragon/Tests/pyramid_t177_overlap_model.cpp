#include <cmath>
#include <cfloat>
#include <iostream>
#include <string>

enum State { IDLE=0, PAIR_ARMED, LEG1_SUBMITTED, LEG1_CONFIRMED, LEG2_RECHECK,
             LEG2_WAIT_SAFE, LEG2_SUBMITTED, COMPLETE, RECONCILE };
enum Drive { NO_EFFECT=0, WAIT, MUTATED, PENDING, DRIVE_RECONCILE };
enum Obs { OBS_PENDING=0, OBS_CONFIRMED, OBS_REJECTED, OBS_RECONCILE };

bool overlap_hit(int count,int from,bool on,double first,double last,double pct){
    if(!on || count<from || first>=0) return false;
    return last>0 && last >= -first*(100.0+pct)/100.0;
}
bool execution_safe(double first,double last,double reserve){
    if(reserve==DBL_MAX) return false;
    return first+last+1e-9 >= std::max(reserve,0.0);
}
bool preleg(int count,int from,bool on,double first,double last,double pct,double reserve){
    return overlap_hit(count,from,on,first,last,pct) && execution_safe(first,last,reserve);
}
bool leg2safe(double realized,double floating,double reserve){
    if(reserve==DBL_MAX) return false;
    return realized+floating+1e-9 >= std::max(reserve,0.0);
}
Obs observe(bool loaded,bool live,bool pending,bool reconcile){
    if(reconcile) return OBS_RECONCILE;
    if(pending) return OBS_PENDING;
    if(!live) return OBS_CONFIRMED;
    if(loaded) return OBS_RECONCILE;
    return OBS_REJECTED;
}
bool consumes(Drive d){return d==MUTATED||d==PENDING||d==DRIVE_RECONCILE;}
bool blocks(State s){return s!=IDLE && s!=COMPLETE;}
bool submitted(State s){return s==LEG1_SUBMITTED||s==LEG2_SUBMITTED;}

int main(){
    int pass=0,fail=0;
    auto check=[&](const std::string& n,bool ok){ if(ok) ++pass; else {++fail; std::cout<<"FAIL: "<<n<<"\n";} };
    check("preleg accepts ratio+reserve", preleg(8,8,true,-100,110,3,5));
    check("preleg rejects ratio", !preleg(8,8,true,-100,102,3,1));
    check("preleg rejects reserve", !preleg(8,8,true,-100,105,3,10));
    check("preleg rejects disabled", !preleg(8,8,false,-100,110,3,1));
    check("preleg rejects invalid economics", !preleg(8,8,true,-100,110,3,DBL_MAX));
    check("leg2 safe after actual fill", leg2safe(110,-100,5));
    check("leg2 unsafe after adverse fill", !leg2safe(102,-100,5));
    check("leg2 equality safe", leg2safe(105,-100,5));
    check("leg2 invalid reserve waits", !leg2safe(200,-100,DBL_MAX));
    check("pending observation", observe(false,true,true,false)==OBS_PENDING);
    check("ticket gone confirmed", observe(false,false,false,false)==OBS_CONFIRMED);
    check("restart live becomes reconcile", observe(true,true,false,false)==OBS_RECONCILE);
    check("same-session rejection is not ambiguity", observe(false,true,false,false)==OBS_REJECTED);
    check("reconcile dominates pending", observe(false,true,true,true)==OBS_RECONCILE);
    check("idle does not block side", !blocks(IDLE));
    check("armed blocks side", blocks(PAIR_ARMED));
    check("leg2 wait blocks same side", blocks(LEG2_WAIT_SAFE));
    check("complete releases side", !blocks(COMPLETE));
    check("wait yields strategy", !consumes(WAIT));
    check("no-effect yields strategy", !consumes(NO_EFFECT));
    check("mutation consumes strategy", consumes(MUTATED));
    check("pending consumes strategy", consumes(PENDING));
    check("reconcile consumes strategy", consumes(DRIVE_RECONCILE));
    check("leg1 state is submitted", submitted(LEG1_SUBMITTED));
    check("leg2 state is submitted", submitted(LEG2_SUBMITTED));
    check("wait state is not submitted", !submitted(LEG2_WAIT_SAFE));
    std::cout << "T17.7 C3 Overlap model: "<<pass<<" passed, "<<fail<<" failed\n";
    if(fail==0) std::cout << "ALL GREEN\n";
    return fail==0?0:1;
}
