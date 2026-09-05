#ifndef BD_PYRAMID_PROTECTION_POLICY_MQH
#define BD_PYRAMID_PROTECTION_POLICY_MQH
// digits-tested: 3, 5

// Pure policy: actual PY direction (BUY=0, SELL=1), never Hedge direction.
double PyProtect_LockPricePure(const int dir,const double weighted,
                              const double lots,const double cash,
                              const double required,const double valuePerPrice,
                              const double tick)
{
   if(dir<0 || dir>1 || weighted<=0 || lots<=0 || valuePerPrice<=0 || tick<=0)
      return 0.0;
   double shift=(required-cash)/(lots*valuePerPrice);
   double raw=dir==0 ? weighted+shift : weighted-shift;
   return dir==0 ? MathCeil(raw/tick-1e-9)*tick : MathFloor(raw/tick+1e-9)*tick;
}

double PyProtect_StrongerPure(const int dir,const double previous,const double candidate)
{
   if(previous<=0) return candidate;
   if(candidate<=0) return previous;
   return dir==0 ? MathMax(previous,candidate) : MathMin(previous,candidate);
}

bool PyProtect_HitPure(const int dir,const double bid,const double ask,const double stop)
{
   if(stop<=0 || bid<=0 || ask<=0) return false;
   return dir==0 ? bid<=stop : ask>=stop;
}

double PyProtect_NetAtPricePure(const int dir,const double weighted,const double lots,
                               const double price,const double valuePerPrice,
                               const double bookedCash,const double liveSwap,
                               const double exitReserve)
{
   double delta=dir==0 ? price-weighted : weighted-price;
   return delta*lots*valuePerPrice+bookedCash+liveSwap-exitReserve;
}

long PyProtect_CapUnitsPure(const long core,const long reserved,const double capPct)
{
   if(core<=reserved || capPct<=0) return 0;
   return (long)MathFloor((double)(core-reserved)*capPct/100.0+1e-9);
}

bool PyProtect_ArmablePure(const int dir,const double bid,const double ask,
                          const double stop,const double minDistance)
{
   if(stop<=0 || bid<=0 || ask<=0 || minDistance<0) return false;
   return dir==0 ? bid-stop>minDistance : stop-ask>minDistance;
}

// T17.23 F01: distinguish "continue to arm" from "wait until the RH trim can
// be funded". UNKNOWN/BLOCK is intentionally separate so missing trim evidence
// never degrades into a successful pre-arm path.
enum ePyProtectPrepareDecision
{
   PY_PREPARE_BLOCK_UNKNOWN = -1,
   PY_PREPARE_CONTINUE = 0,
   PY_PREPARE_WAIT_UNFUNDED,
   PY_PREPARE_TRIM_READY
};

ePyProtectPrepareDecision PyProtect_PrepareDecisionPure(const long excess,
                                                        const bool trimSelected,
                                                        const bool fundedArmable)
{
   if(excess<=0) return PY_PREPARE_CONTINUE;
   if(!trimSelected) return PY_PREPARE_BLOCK_UNKNOWN;
   return fundedArmable ? PY_PREPARE_TRIM_READY : PY_PREPARE_WAIT_UNFUNDED;
}

bool PyProtect_AddFundedPure(const int dir,const double stop,const double fill,
                            const double lots,const double slope,const double existingNet,
                            const double floor,const double costs)
{
   if(stop<=0) return true;
   if(fill<=0 || lots<=0 || slope<=0 || costs<0) return false;
   double delta=dir==0 ? stop-fill : fill-stop;
   return existingNet+delta*lots*slope-costs+1e-8>=floor;
}

bool PyProtect_ExpectedBrokerSlPure(const bool brokerMode,const long groupSerial,
                                    const long memberSerial,const double programmed,
                                    const double confirmed,const double requested,
                                    const double tick)
{
   if(!brokerMode || groupSerial!=memberSerial || programmed<=0 || tick<=0) return false;
   if(confirmed>0 && MathAbs(programmed-confirmed)<tick*0.5) return true;
   return requested>0 && MathAbs(programmed-requested)<tick*0.5;
}
#endif
