//+------------------------------------------------------------------+
//| StrategyT1711Admission.mqh — Core/DCA capacity admission         |
//| Pure, non-persisted NO_MONEY latch keyed to one exact intent.    |
//+------------------------------------------------------------------+
#ifndef BD_STRATEGY_T1711_ADMISSION_MQH
#define BD_STRATEGY_T1711_ADMISSION_MQH

struct SCoreCapacityLatch
{
   bool     active;
   int      direction;
   int      dcaIndex;
   double   normalizedVolume;
   datetime barTime;
   double   requiredMargin;
};

void Strategy_T1711ResetCapacityLatch(SCoreCapacityLatch &latch)
{
   latch.active           = false;
   latch.direction        = -1;
   latch.dcaIndex         = 0;
   latch.normalizedVolume = 0.0;
   latch.barTime          = 0;
   latch.requiredMargin   = 0.0;
}

bool Recovery_T1711CapacityLatchBlocksPure(const SCoreCapacityLatch &latch,
                                           const int direction,
                                           const int dcaIndex,
                                           const double normalizedVolume,
                                           const datetime barTime,
                                           const double freeMargin,
                                           const double volumeStep)
{
   if(!latch.active) return false;
   if(latch.direction != direction || latch.dcaIndex != dcaIndex) return false;
   double epsilon = MathMax(1e-12, MathAbs(volumeStep) * 0.25);
   if(MathAbs(latch.normalizedVolume - normalizedVolume) > epsilon) return false;
   if(latch.barTime != barTime) return false;
   if(latch.requiredMargin > 0.0 && freeMargin >= latch.requiredMargin) return false;
   return true;
}

void Strategy_T1711LatchCapacity(SCoreCapacityLatch &latch,
                                 const int direction,
                                 const int dcaIndex,
                                 const datetime barTime,
                                 const SExecSubmitOutcome &outcome)
{
   latch.active           = true;
   latch.direction        = direction;
   latch.dcaIndex         = dcaIndex;
   latch.normalizedVolume = outcome.normalizedVolume;
   latch.barTime          = barTime;
   latch.requiredMargin   = outcome.requiredMargin;
}

#endif // BD_STRATEGY_T1711_ADMISSION_MQH
