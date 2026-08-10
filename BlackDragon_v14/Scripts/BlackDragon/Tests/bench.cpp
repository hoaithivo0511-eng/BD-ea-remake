// Micro-benchmark: BlackDragon v14.7.1 hot-path computational core
#include <cmath>
#include <cstdio>
#include <chrono>
#include <vector>
using namespace std;
using Clock = chrono::high_resolution_clock;

struct SWmfState { bool seeded; double maxVal, minVal; bool uptrend; double stop, ema; };
static void WMF_Step(SWmfState &st, double src, double atrM, double a){
   if(!st.seeded){ st.maxVal=src; st.minVal=src; st.uptrend=true; st.stop=0; st.ema=src; st.seeded=true; }
   else st.ema += a*(src-st.ema);
   st.maxVal = st.maxVal>src?st.maxVal:src; st.minVal = st.minVal<src?st.minVal:src;
   st.stop = st.uptrend ? (st.stop>st.maxVal-atrM?st.stop:st.maxVal-atrM) : (st.stop<st.minVal+atrM?st.stop:st.minVal+atrM);
   bool p=st.uptrend; st.uptrend=(src-st.stop)>=0;
   if(st.uptrend!=p){ st.maxVal=src; st.minVal=src; st.stop=st.uptrend?st.maxVal-atrM:st.minVal+atrM; }
}
static double Grid_ChainLot(double base,int count,const vector<double>&m,double cap){
   double lot=base; int n=(int)m.size();
   for(int k=0;k<count;k++) lot*=m[k>n-1?n-1:k];
   return lot>cap?cap:lot;
}
struct PendingLite { int action; bool active; };
static bool Exec_PendingReady(bool stateResolved){ return stateResolved; }
static bool HasAnyPendingClose(const PendingLite *j,int n){
   for(int i=n-1;i>=0;i--) if(j[i].active && j[i].action==3) return true;
   return false;
}
int main(){
   const long N = 10000000;
   volatile double sink = 0;
   // 1) WMF step (per closed bar in the EA, benchmarked per-op here)
   SWmfState st{}; double price=3350;
   auto t0=Clock::now();
   for(long i=0;i<N;i++){ price += ((i*2654435761u)%100-50)*0.01; WMF_Step(st,price,2.0,2.0/3.0); sink += st.stop; }
   auto t1=Clock::now();
   // 2) chain lot, count=20 (called only khi trigger khop)
   vector<double> m={1.03,1.03,1.03,1.3,1.3,1.3,1.3,1.25,1.5};
   auto t2=Clock::now();
   for(long i=0;i<N;i++) sink += Grid_ChainLot(0.01,20,m,100);
   auto t3=Clock::now();
   // 3) full per-tick arithmetic model: BE weighted avg + TP/SL/trail checks, 20 positions
   double open[20], lots[20];
   for(int i=0;i<20;i++){ open[i]=3350-i*2; lots[i]=0.01*pow(1.5,i); }
   auto t4=Clock::now();
   for(long i=0;i<N/10;i++){
      double ws=0,ls=0; for(int k=0;k<20;k++){ ws+=open[k]*lots[k]; ls+=lots[k]; }
      double be=ws/ls, tp=be+2.0, bid=3340+((i*40503u)%100)*0.01;
      sink += (bid>=tp) + (bid<=be-5) + (bid<=be+1);
   }
   auto t5=Clock::now();
   // 4) BD-002 pure completion predicate (called on trade events/watchdog)
   auto t6=Clock::now();
   for(long i=0;i<N;i++) sink += Exec_PendingReady((i&1)!=0);
   auto t7=Clock::now();
   // 5) BD-001 ordinary-tick pending-close guard, 0..8 journal entries
   PendingLite journal[8]={{1,true},{2,true},{4,true},{1,true},{2,true},{4,true},{1,true},{3,true}};
   for(long i=0;i<N;i++) sink += HasAnyPendingClose(journal,(int)(i%9));
   auto t8=Clock::now();
   auto ns=[&](auto a,auto b,long n){ return (double)chrono::duration_cast<chrono::nanoseconds>(b-a).count()/n; };
   printf("WMF_Step:            %6.2f ns/op  (goi 1 lan MOI NEN DONG)\n", ns(t0,t1,N));
   printf("Grid_ChainLot(20):   %6.2f ns/op  (goi 1 lan MOI LENH MO)\n", ns(t2,t3,N));
   printf("Tick-model 20 lenh:  %6.2f ns/tick (BE+TP/SL/trail arithmetic)\n", ns(t4,t5,N/10));
   printf("BD-002 ready check:  %6.2f ns/op  (trade-event/watchdog only)\n", ns(t6,t7,N));
   printf("BD-001 close guard:  %6.2f ns/tick (scan 0..8 journal entries)\n", ns(t7,t8,N));
   printf("sink=%f\n", sink);
   return 0;
}
