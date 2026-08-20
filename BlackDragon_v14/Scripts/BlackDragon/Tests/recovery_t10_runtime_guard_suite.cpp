#include <cmath>
#include <iostream>
static int p=0,f=0;
#define C(n,x) do{if(x)++p;else{++f;std::cout<<"FAIL "<<n<<"\n";}}while(0)
enum S{CORE_ONLY,ARMED,HEDGE_BUILDING,HEDGE_ACTIVE,HEDGE_TP_PENDING,CORE_CLOSE_PENDING,HEDGE_LOCK_PENDING,HEDGE_LOCKED,REHEDGE_PENDING};
static constexpr long R_CLIENT=0,R_EXPERT=3,R_SL=4;
bool ExpectedLockSl(const S s,const long r,const double price,const double target,const double tol){
 if(r!=R_SL)return false;
 if(s!=HEDGE_LOCK_PENDING&&s!=HEDGE_LOCKED)return false;
 if(price<=0.0||target<=0.0||tol<0.0)return false;
 return std::fabs(price-target)<=tol+1e-12;
}
int main(){
 C("locked SL near target",ExpectedLockSl(HEDGE_LOCKED,R_SL,4531.979,4531.999,0.025));
 C("lock pending SL near target",ExpectedLockSl(HEDGE_LOCK_PENDING,R_SL,4531.980,4531.999,0.025));
 C("ACTIVE SL external",!ExpectedLockSl(HEDGE_ACTIVE,R_SL,4531.979,4531.999,0.025));
 C("client external",!ExpectedLockSl(HEDGE_LOCKED,R_CLIENT,4531.979,4531.999,0.025));
 C("expert not lock-SL",!ExpectedLockSl(HEDGE_LOCKED,R_EXPERT,4531.979,4531.999,0.025));
 C("far SL external",!ExpectedLockSl(HEDGE_LOCKED,R_SL,4531.700,4531.999,0.025));
 C("zero price rejected",!ExpectedLockSl(HEDGE_LOCKED,R_SL,0.0,4531.999,0.025));
 C("zero target rejected",!ExpectedLockSl(HEDGE_LOCKED,R_SL,4531.979,0.0,0.025));
 C("negative tolerance rejected",!ExpectedLockSl(HEDGE_LOCKED,R_SL,4531.979,4531.999,-0.01));
 std::cout<<p<<" passed, "<<f<<" failed\n"; return f?1:0;
}
