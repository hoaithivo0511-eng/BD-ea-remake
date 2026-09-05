//+------------------------------------------------------------------+
//| RecoveryT177HedgeLadder.mqh — T17.7 C4 executable Hedge ladder  |
//| Canonical final target + broker-unit stage de-duplication.       |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_T177_HEDGE_LADDER_MQH
#define BD_RECOVERY_T177_HEDGE_LADDER_MQH

#include "RecoveryT16Config.mqh"

#define BD_T177_HEDGE_LADDER_POLICY_REV 1

// T17.16: while a layer is BUILDING, the TP-close ledger fields are not yet
// active. They durably carry the currently-admitted logical Hedge stage so a
// broker-split child can continue after restart without letting a later Core
// denominator rebase impersonate that partial child.
bool Recovery_T1716BrokerPartialStagePure(const long liveUnits,
                                           const long previousStageTargetUnits,
                                           const int currentStageNo,
                                           const long currentStageTargetUnits,
                                           const int admittedStageNo,
                                           const long admittedStageTargetUnits)
{
   if(liveUnits <= previousStageTargetUnits ||
      liveUnits >= currentStageTargetUnits)
      return false;
   return admittedStageNo == currentStageNo &&
          admittedStageTargetUnits == currentStageTargetUnits;
}

struct SRecoveryT177HedgeStage
{
   int    sourceIndex;
   double requestedCoverage;
   long   generationTargetUnits;
   long   totalTargetUnits;
   double effectiveCoverage;
   double gapFromPreviousPips;
};

double Recovery_T177EffectiveFinalCoveragePercentPure(const double requestedFinalPercent,
                                                       const double absoluteMaxPercent)
{
   if(requestedFinalPercent <= 0.0) return 0.0;
   if(absoluteMaxPercent > 0.0 && requestedFinalPercent > absoluteMaxPercent)
      return absoluteMaxPercent;
   return requestedFinalPercent;
}

long Recovery_T177CoverageTotalUnitsPure(const long coreUnits,
                                         const double coveragePercent)
{
   return Recovery_T16PercentUnitsPure(coreUnits, coveragePercent);
}

long Recovery_T177ExecutableGenerationTargetPure(const long coreUnits,
                                                  const long retainedBeforeGenerationUnits,
                                                  const double coveragePercent,
                                                  const long minUnits,
                                                  const long finalGenerationRawUnits)
{
   if(coreUnits <= 0 || coveragePercent <= 0.0 || finalGenerationRawUnits <= 0)
      return 0;
   long desiredTotal = Recovery_T177CoverageTotalUnitsPure(coreUnits, coveragePercent);
   long retained = retainedBeforeGenerationUnits > 0 ? retainedBeforeGenerationUnits : 0;
   long raw = desiredTotal > retained ? desiredTotal - retained : 0;
   if(raw <= 0) return 0;
   long planned = raw;
   if(minUnits > 0 && planned < minUnits) planned = minUnits;
   // Hard-cap invariant: broker minimum may not inflate a staged target beyond
   // the executable final target. In that case this stage is not executable.
   if(planned > finalGenerationRawUnits) return 0;
   return planned;
}

long Recovery_T177FinalGenerationRawUnitsPure(const long coreUnits,
                                               const long retainedBeforeGenerationUnits,
                                               const double finalCoveragePercent)
{
   long desiredTotal = Recovery_T177CoverageTotalUnitsPure(coreUnits,
                                                            finalCoveragePercent);
   long retained = retainedBeforeGenerationUnits > 0 ? retainedBeforeGenerationUnits : 0;
   return desiredTotal > retained ? desiredTotal - retained : 0;
}

double Recovery_T177ActualCoveragePercentPure(const long coreUnits,
                                               const long totalHedgeUnits)
{
   if(coreUnits <= 0 || totalHedgeUnits <= 0) return 0.0;
   return (double)totalHedgeUnits * 100.0 / (double)coreUnits;
}

// Builds the executable stage ladder from an already canonical ascending
// percentage ladder. Stages that map to the same broker-unit target keep the
// FIRST requested stage. Their transition gap is accumulated into the next
// executable stage, preserving cumulative favorable-price geometry instead
// of accelerating exposure after broker-volume de-duplication.
int Recovery_T177BuildExecutableHedgeLadderPure(const double &coverage[],
                                                 const double &gaps[],
                                                 const long coreUnits,
                                                 const long retainedBeforeGenerationUnits,
                                                 const long minUnits,
                                                 SRecoveryT177HedgeStage &out[])
{
   ArrayResize(out, 0);
   int n = ArraySize(coverage);
   if(n <= 0 || coreUnits <= 0) return 0;

   double finalCoverage = coverage[n-1];
   long finalRaw = Recovery_T177FinalGenerationRawUnitsPure(coreUnits,
                                                             retainedBeforeGenerationUnits,
                                                             finalCoverage);
   if(finalRaw <= 0) return 0;
   if(minUnits > 0 && finalRaw < minUnits) return 0;

   bool haveKept = false;
   long lastKeptTarget = 0;
   double gapAccumulator = 0.0;

   for(int i = 0; i < n; i++)
   {
      if(i > 0)
         gapAccumulator += Pyramid_SeqValue(gaps, i - 1);

      long planned = Recovery_T177ExecutableGenerationTargetPure(coreUnits,
                                                                  retainedBeforeGenerationUnits,
                                                                  coverage[i],
                                                                  minUnits,
                                                                  finalRaw);
      if(planned <= 0)
      {
         // Already-covered leading stages must not make the first new stage
         // wait for historical gaps that occurred before this generation.
         if(!haveKept) gapAccumulator = 0.0;
         continue;
      }
      if(haveKept && planned <= lastKeptTarget)
      {
         // Duplicate executable target: keep the first stage and carry this
         // stage's transition distance forward to the next distinct target.
         continue;
      }

      int k = ArraySize(out);
      ArrayResize(out, k + 1);
      out[k].sourceIndex = i;
      out[k].requestedCoverage = coverage[i];
      out[k].generationTargetUnits = planned;
      long retained = retainedBeforeGenerationUnits > 0 ? retainedBeforeGenerationUnits : 0;
      out[k].totalTargetUnits = retained + planned;
      out[k].effectiveCoverage = Recovery_T177ActualCoveragePercentPure(coreUnits,
                                                                         out[k].totalTargetUnits);
      out[k].gapFromPreviousPips = haveKept ? gapAccumulator : 0.0;
      haveKept = true;
      lastKeptTarget = planned;
      gapAccumulator = 0.0;
   }
   return ArraySize(out);
}

bool Recovery_T177StageSourceKeptPure(const int sourceIndex,
                                      const SRecoveryT177HedgeStage &plan[])
{
   for(int i = 0; i < ArraySize(plan); i++)
      if(plan[i].sourceIndex == sourceIndex) return true;
   return false;
}

#endif // BD_RECOVERY_T177_HEDGE_LADDER_MQH
