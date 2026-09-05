//+------------------------------------------------------------------+
//| RecoveryT1719ReentryPolicy.mqh — terminal RH re-entry policy    |
//| Pure direction geometry and independent Core-growth admission.  |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T1719_REENTRY_POLICY_MQH
#define BD_RECOVERY_T1719_REENTRY_POLICY_MQH

#include "RecoveryTypes.mqh"

enum eRecoveryReentryPhaseT1719
{
   RECOVERY_REENTRY_NONE = 0,
   RECOVERY_REENTRY_COLLECTING = 1,
   RECOVERY_REENTRY_WAIT_RESET = 2,
   RECOVERY_REENTRY_ARMED = 3,
   RECOVERY_REENTRY_TRIGGER_PENDING = 4,
   RECOVERY_REENTRY_IN_CYCLE = 5,
   RECOVERY_REENTRY_EXHAUSTED = 6
};

struct SRecoveryReentryStateT1719
{
   eRecoveryReentryPhaseT1719 phase;
   int      completedCycles;
   long     anchorTicks;
   double   anchorPrice;
   double   lastFillPrice;
   ulong    sourceDeal;
   long     sourceDealTimeMsc;
   int      sourceGeneration;
   double   sourceNetCash;
   bool     candidateAllExact;
   long     cycleStartedTimeMsc;
   datetime candidateObservedAt;
   ulong    campaignAnchorPosition;
   datetime campaignAnchorTime;
};

void Recovery_T1719ResetState(SRecoveryReentryStateT1719 &state)
{
   ZeroMemory(state);
   state.phase = RECOVERY_REENTRY_NONE;
}

bool Recovery_T1719PhaseValidPure(const int phase)
{
   return phase >= (int)RECOVERY_REENTRY_NONE &&
          phase <= (int)RECOVERY_REENTRY_EXHAUSTED;
}

bool Recovery_T1719PositiveChainPure(const double netCash,
                                     const double epsilon)
{
   return epsilon >= 0.0 && netCash >= -epsilon;
}

bool Recovery_T1719TerminalEligiblePure(const bool exactOwnedProtectiveClose,
                                        const int generation,
                                        const int maxGeneration,
                                        const long coreUnits,
                                        const long hedgeUnits,
                                        const double netCash,
                                        const double epsilon,
                                        const int completedCycles,
                                        const int maxCycles)
{
   return exactOwnedProtectiveClose && maxGeneration > 0 &&
          generation >= maxGeneration && coreUnits > 0 && hedgeUnits == 0 &&
          Recovery_T1719PositiveChainPure(netCash, epsilon) &&
          maxCycles > 0 && completedCycles < maxCycles;
}

bool Recovery_T1719ResetHitPure(const eRecoveryCoreDirection dir,
                                const long anchorTicks,
                                const long bidTicks,
                                const long askTicks,
                                const long bufferTicks)
{
   if(anchorTicks <= 0 || bufferTicks <= 0) return false;
   if(dir == recovery_CORE_BUY)
      return askTicks >= anchorTicks + bufferTicks;
   return bidTicks <= anchorTicks - bufferTicks;
}

bool Recovery_T1719ReturnHitPure(const eRecoveryCoreDirection dir,
                                 const long anchorTicks,
                                 const long bidTicks,
                                 const long askTicks)
{
   if(anchorTicks <= 0) return false;
   if(dir == recovery_CORE_BUY) return bidTicks <= anchorTicks;
   return askTicks >= anchorTicks;
}

bool Recovery_T1719BlocksCoreDcaPure(const eRecoveryReentryPhaseT1719 phase)
{
   return phase == RECOVERY_REENTRY_WAIT_RESET ||
          phase == RECOVERY_REENTRY_ARMED ||
          phase == RECOVERY_REENTRY_TRIGGER_PENDING ||
          phase == RECOVERY_REENTRY_EXHAUSTED;
}

bool Recovery_T1719BlocksCorePyramidAddPure(const eRecoveryReentryPhaseT1719 phase)
{
   // Owner amendment: WAIT_RESET/ARMED must keep Core Pyramid ADD eligible
   // for its existing settings, timing, profit, room, risk and execution gates.
   return phase == RECOVERY_REENTRY_TRIGGER_PENDING ||
          phase == RECOVERY_REENTRY_EXHAUSTED;
}

bool Recovery_T1719AllowsCorePyramidAddPure(const eRecoveryReentryPhaseT1719 phase)
{
   // Explicit owner policy: only Core DCA is suppressed while the terminal
   // re-entry latch waits. The Pyramid engine must still apply all of its own
   // mode, count, timing, trend, room, profit, risk and execution gates.
   return phase == RECOVERY_REENTRY_WAIT_RESET ||
          phase == RECOVERY_REENTRY_ARMED;
}

bool Recovery_T1719AllowsCorePyramidPeelPure(const eRecoveryReentryPhaseT1719 phase)
{
   return phase == RECOVERY_REENTRY_WAIT_RESET ||
          phase == RECOVERY_REENTRY_ARMED ||
          phase == RECOVERY_REENTRY_EXHAUSTED;
}

eRecoveryReentryPhaseT1719 Recovery_T1719TerminalPhasePure(
   const int completedCycles,
   const int maxCycles)
{
   if(maxCycles > 0 && completedCycles < maxCycles)
      return RECOVERY_REENTRY_WAIT_RESET;
   return RECOVERY_REENTRY_EXHAUSTED;
}

string Recovery_T1719PhaseName(const eRecoveryReentryPhaseT1719 phase)
{
   switch(phase)
   {
      case RECOVERY_REENTRY_NONE:            return "NONE";
      case RECOVERY_REENTRY_COLLECTING:      return "COLLECTING";
      case RECOVERY_REENTRY_WAIT_RESET:      return "WAIT_RESET";
      case RECOVERY_REENTRY_ARMED:           return "ARMED";
      case RECOVERY_REENTRY_TRIGGER_PENDING: return "TRIGGER_PENDING";
      case RECOVERY_REENTRY_IN_CYCLE:        return "IN_CYCLE";
      case RECOVERY_REENTRY_EXHAUSTED:       return "EXHAUSTED";
   }
   return "INVALID";
}

#endif // BD_RECOVERY_T1719_REENTRY_POLICY_MQH
