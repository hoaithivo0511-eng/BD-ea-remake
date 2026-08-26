//+------------------------------------------------------------------+
//| RecoveryExit.mqh — T16.6 virtual TP / executable close planning |
//| Invariants: pure planning/accounting only; no trade API calls.   |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_EXIT_MQH
#define BD_RECOVERY_EXIT_MQH

#include "RecoveryBundle.mqh"

struct SRecoveryCloseCandidate
{
   ulong    ticket;
   datetime openTime;
   long     units;
   double   floatingCash;
};

struct SRecoveryCloseAction
{
   ulong  ticket;
   long   units;
   double estimatedCashLoss;
};

struct SRecoveryRealizedLedger
{
   double hedgeNetCash;
   double coreLossSpent;
   double availableCredit;
   long   hedgeRealizedCloseUnits;
   bool   deficit;
};

struct SRecoveryT5CycleRuntime
{
   bool   tpLatched;
   long   hedgeCloseBaselineUnits;
   long   hedgeCloseTargetUnits;
   long   hedgeCloseObservedUnits;
   double hedgeNetBE;
   double tpTriggerPrice;
   SRecoveryRealizedLedger ledger;
};

double Recovery_DealCashPure(const double profit,
                             const double swap,
                             const double commission,
                             const double fee)
{
   return profit + swap + commission + fee;
}

void Recovery_LedgerInit(SRecoveryRealizedLedger &ledger)
{
   ledger.hedgeNetCash = 0.0;
   ledger.coreLossSpent = 0.0;
   ledger.availableCredit = 0.0;
   ledger.hedgeRealizedCloseUnits = 0;
   ledger.deficit = false;
}

void Recovery_LedgerRecompute(SRecoveryRealizedLedger &ledger)
{
   double positiveHedgeCredit = ledger.hedgeNetCash > 0.0 ? ledger.hedgeNetCash : 0.0;
   double raw = positiveHedgeCredit - ledger.coreLossSpent;
   ledger.availableCredit = raw > 0.0 ? raw : 0.0;
   // Negative/zero hedge realization with no Core spend is not a credit
   // deficit; it simply provides no spendable credit.
   ledger.deficit = ledger.coreLossSpent > positiveHedgeCredit + 1e-8;
}

void Recovery_LedgerApplyHedgeDeal(SRecoveryRealizedLedger &ledger,
                                   const double dealCash,
                                   const long closeUnits)
{
   ledger.hedgeNetCash += dealCash;
   if(closeUnits > 0) ledger.hedgeRealizedCloseUnits += closeUnits;
   Recovery_LedgerRecompute(ledger);
}

void Recovery_LedgerApplyCoreDeal(SRecoveryRealizedLedger &ledger,
                                  const double dealCash)
{
   if(dealCash < 0.0) ledger.coreLossSpent += -dealCash;
   Recovery_LedgerRecompute(ledger);
}

double Recovery_NetBreakevenFromCosts(const double weightedAvgOpen,
                                      const double totalLots,
                                      const double signedCostMoney,
                                      const double tickValue,
                                      const double tickSize,
                                      const bool isBuy)
{
   if(weightedAvgOpen <= 0.0 || totalLots <= 0.0 ||
      tickValue <= 0.0 || tickSize <= 0.0)
      return 0.0;
   double shift = signedCostMoney / (tickValue * totalLots) * tickSize;
   return isBuy ? weightedAvgOpen - shift : weightedAvgOpen + shift;
}

bool Recovery_VirtualHedgeTpHit(const eRecoveryCoreDirection coreDir,
                                const double hedgeNetBE,
                                const double bid,
                                const double ask,
                                const double tpDistancePrice)
{
   if(hedgeNetBE <= 0.0 || bid <= 0.0 || ask <= 0.0 || tpDistancePrice < 0.0)
      return false;
   if(coreDir == recovery_CORE_BUY)
      return ask <= hedgeNetBE - tpDistancePrice; // SELL hedge exits at ask
   return bid >= hedgeNetBE + tpDistancePrice;    // BUY hedge exits at bid
}

// T16.6 owner policy for the active Hedge generation only:
// - configured economic intent is floored as before;
// - if that intent is positive but below broker minimum, close minUnits;
// - if a requested partial would leave an illegal sub-minimum remainder,
//   reduce to the nearest legal non-overclose when possible;
// - if no legal partial exists, full-close the tiny layer rather than
//   classifying deterministic broker-grid quantization as RECONCILE.
long Recovery_T166ExecutablePartialCloseUnitsPure(const long activeUnits,
                                                  const double percent,
                                                  const long minUnits)
{
   if(activeUnits <= 0 || percent <= 0.0 || percent > 100.0 || minUnits <= 0)
      return 0;
   if(activeUnits < minUnits) return 0; // unexpected/illegal live exposure
   if(percent >= 100.0 - 1e-12) return activeUnits;

   long target = (long)MathFloor((double)activeUnits * percent / 100.0 + 1e-9);
   if(target < minUnits) target = minUnits;
   if(target >= activeUnits) return activeUnits;

   long remaining = activeUnits - target;
   if(remaining == 0 || remaining >= minUnits) return target;

   // Keep one broker minimum open if a smaller legal close can do so.
   long reduced = activeUnits - minUnits;
   if(reduced >= minUnits && reduced < target) return reduced;

   // No legal partial is representable on this broker grid. Full close is the
   // only executable non-overclose and leaves no retained layer to lock.
   return activeUnits;
}

long Recovery_PartialCloseTargetUnits(const long activeUnits,
                                      const double percent,
                                      const long minUnits)
{
   return Recovery_T166ExecutablePartialCloseUnitsPure(activeUnits,
                                                       percent,
                                                       minUnits);
}

long Recovery_LegalCloseUnits(const long requestedUnits,
                              const long positionUnits,
                              const long minUnits)
{
   if(requestedUnits <= 0 || positionUnits <= 0 || minUnits <= 0) return 0;
   if(requestedUnits >= positionUnits) return positionUnits;
   if(requestedUnits < minUnits) return 0;
   long target = requestedUnits;
   long remaining = positionUnits - target;
   if(remaining > 0 && remaining < minUnits)
   {
      target = positionUnits - minUnits;
      if(target < minUnits) return 0;
   }
   return target;
}

void Recovery_AppendCloseAction(SRecoveryCloseAction &actions[],
                                const ulong ticket,
                                const long units,
                                const double estimatedCashLoss)
{
   int n = ArraySize(actions);
   ArrayResize(actions, n + 1);
   actions[n].ticket = ticket;
   actions[n].units = units;
   actions[n].estimatedCashLoss = estimatedCashLoss > 0.0 ? estimatedCashLoss : 0.0;
}

void Recovery_SortHedgeCloseCandidates(SRecoveryCloseCandidate &items[])
{
   for(int i = 1; i < ArraySize(items); i++)
   {
      SRecoveryCloseCandidate key = items[i];
      int j = i - 1;
      while(j >= 0 &&
            (items[j].units < key.units ||
             (items[j].units == key.units && items[j].ticket > key.ticket)))
      {
         items[j + 1] = items[j];
         j--;
      }
      items[j + 1] = key;
   }
}

bool Recovery_BuildHedgeClosePlan(SRecoveryCloseCandidate &candidates[],
                                  const long targetUnits,
                                  const long minUnits,
                                  SRecoveryCloseAction &actions[],
                                  string &why)
{
   ArrayResize(actions, 0);
   why = "";
   if(targetUnits <= 0 || minUnits <= 0)
   {
      why = "invalid hedge close target/minimum";
      return false;
   }

   SRecoveryCloseCandidate sorted[];
   ArrayResize(sorted, ArraySize(candidates));
   for(int i = 0; i < ArraySize(candidates); i++) sorted[i] = candidates[i];
   Recovery_SortHedgeCloseCandidates(sorted);

   long remaining = targetUnits;
   for(int i = 0; i < ArraySize(sorted) && remaining > 0; i++)
   {
      if(sorted[i].ticket == 0 || sorted[i].units <= 0) continue;
      if(remaining >= sorted[i].units)
      {
         Recovery_AppendCloseAction(actions, sorted[i].ticket, sorted[i].units, 0.0);
         remaining -= sorted[i].units;
         continue;
      }
      long partial = Recovery_LegalCloseUnits(remaining, sorted[i].units, minUnits);
      if(partial == remaining)
      {
         Recovery_AppendCloseAction(actions, sorted[i].ticket, partial, 0.0);
         remaining = 0;
      }
   }

   if(remaining != 0)
   {
      ArrayResize(actions, 0);
      why = "exact logical hedge partial-close target is not executable without over-close";
      return false;
   }
   return ArraySize(actions) > 0;
}

double Recovery_LossPerUnit(const SRecoveryCloseCandidate &c)
{
   if(c.units <= 0 || c.floatingCash >= 0.0) return 0.0;
   return -c.floatingCash / (double)c.units;
}

bool Recovery_CoreBefore(const SRecoveryCloseCandidate &a,
                         const SRecoveryCloseCandidate &b,
                         const eRecoveryCoreCloseMode mode)
{
   if(mode == recovery_Newest)
   {
      if(a.openTime != b.openTime) return a.openTime > b.openTime;
      return a.ticket > b.ticket;
   }
   if(mode == recovery_Lossiest)
   {
      double la = Recovery_LossPerUnit(a);
      double lb = Recovery_LossPerUnit(b);
      if(MathAbs(la - lb) > 1e-12) return la > lb;
   }
   if(a.openTime != b.openTime) return a.openTime < b.openTime;
   return a.ticket < b.ticket;
}

void Recovery_SortCoreCandidates(SRecoveryCloseCandidate &items[],
                                 const eRecoveryCoreCloseMode mode)
{
   for(int i = 1; i < ArraySize(items); i++)
   {
      SRecoveryCloseCandidate key = items[i];
      int j = i - 1;
      while(j >= 0 && !Recovery_CoreBefore(items[j], key, mode))
      {
         items[j + 1] = items[j];
         j--;
      }
      items[j + 1] = key;
   }
}

bool Recovery_BuildCoreClosePlan(SRecoveryCloseCandidate &candidates[],
                                 const eRecoveryCoreCloseMode mode,
                                 const double availableCredit,
                                 const long minUnits,
                                 SRecoveryCloseAction &actions[],
                                 double &estimatedLoss,
                                 string &why)
{
   ArrayResize(actions, 0);
   estimatedLoss = 0.0;
   why = "";
   if(!Recovery_CoreCloseModeValid(mode) || availableCredit <= 0.0 || minUnits <= 0)
   {
      why = "no spendable realized credit or invalid allocator settings";
      return false;
   }

   SRecoveryCloseCandidate sorted[];
   ArrayResize(sorted, ArraySize(candidates));
   for(int i = 0; i < ArraySize(candidates); i++) sorted[i] = candidates[i];
   Recovery_SortCoreCandidates(sorted, mode);
   double remainingCredit = availableCredit;

   if(mode == recovery_ProRata)
   {
      double totalLoss = 0.0;
      for(int i = 0; i < ArraySize(sorted); i++)
         if(sorted[i].units > 0 && sorted[i].floatingCash < 0.0)
            totalLoss += -sorted[i].floatingCash;
      if(totalLoss <= 0.0)
      {
         why = "no losing Core exposure to allocate";
         return false;
      }

      double fraction = MathMin(1.0, availableCredit / totalLoss);
      int n = ArraySize(sorted);
      long planned[];
      double remainderRank[];
      ArrayResize(planned, n);
      ArrayResize(remainderRank, n);
      for(int i = 0; i < n; i++)
      {
         planned[i] = 0;
         remainderRank[i] = -1.0;
         if(sorted[i].units <= 0 || sorted[i].floatingCash >= 0.0) continue;
         double raw = (double)sorted[i].units * fraction;
         long wanted = (long)MathFloor(raw + 1e-9);
         planned[i] = Recovery_LegalCloseUnits(wanted, sorted[i].units, minUnits);
         remainderRank[i] = raw - MathFloor(raw);
         if(planned[i] > 0)
         {
            double loss = Recovery_LossPerUnit(sorted[i]) * planned[i];
            if(loss <= remainingCredit + 1e-8) remainingCredit -= loss;
            else planned[i] = 0;
         }
      }

      // Largest-remainder pass: deterministic by rank then current stable
      // order. At most one extra volume-step per losing ticket.
      bool used[];
      ArrayResize(used, n);
      for(int i = 0; i < n; i++) used[i] = false;
      for(int pass = 0; pass < n; pass++)
      {
         int best = -1;
         for(int i = 0; i < n; i++)
         {
            if(used[i] || remainderRank[i] < 0.0) continue;
            if(best < 0 || remainderRank[i] > remainderRank[best] + 1e-12)
               best = i;
         }
         if(best < 0) break;
         used[best] = true;

         long requested = planned[best] > 0 ? planned[best] + 1 : minUnits;
         long next = Recovery_LegalCloseUnits(requested, sorted[best].units, minUnits);
         if(next <= planned[best]) continue;
         long delta = next - planned[best];
         double extraLoss = Recovery_LossPerUnit(sorted[best]) * delta;
         if(extraLoss <= remainingCredit + 1e-8)
         {
            planned[best] = next;
            remainingCredit -= extraLoss;
         }
      }

      for(int i = 0; i < n; i++)
      {
         if(planned[i] <= 0) continue;
         double loss = Recovery_LossPerUnit(sorted[i]) * planned[i];
         Recovery_AppendCloseAction(actions, sorted[i].ticket, planned[i], loss);
         estimatedLoss += loss;
      }
   }
   else
   {
      for(int i = 0; i < ArraySize(sorted) && remainingCredit > 1e-8; i++)
      {
         double lossPerUnit = Recovery_LossPerUnit(sorted[i]);
         if(lossPerUnit <= 0.0) continue;
         long maxByCredit = (long)MathFloor(remainingCredit / lossPerUnit + 1e-9);
         if(maxByCredit <= 0) continue;
         long wanted = sorted[i].units < maxByCredit ? sorted[i].units : maxByCredit;
         long closeUnits = Recovery_LegalCloseUnits(wanted, sorted[i].units, minUnits);
         if(closeUnits <= 0) continue;
         double loss = lossPerUnit * closeUnits;
         if(loss > remainingCredit + 1e-8) continue;
         Recovery_AppendCloseAction(actions, sorted[i].ticket, closeUnits, loss);
         estimatedLoss += loss;
         remainingCredit -= loss;
      }
   }

   if(ArraySize(actions) == 0)
   {
      why = "realized credit cannot fund a legal losing-Core partial close at current broker volume grid";
      return false;
   }
   return true;
}

void Recovery_T5RuntimeInit(SRecoveryT5CycleRuntime &rt)
{
   rt.tpLatched = false;
   rt.hedgeCloseBaselineUnits = 0;
   rt.hedgeCloseTargetUnits = 0;
   rt.hedgeCloseObservedUnits = 0;
   rt.hedgeNetBE = 0.0;
   rt.tpTriggerPrice = 0.0;
   Recovery_LedgerInit(rt.ledger);
}

#endif // BD_RECOVERY_EXIT_MQH
