//+------------------------------------------------------------------+
//| RecoveryEngine.mqh — T14 identity compatibility layer            |
//|                                                                   |
//| T13 implementation is pinned byte-for-byte in                    |
//| RecoveryEngineT13Base.mqh. This wrapper changes only the durable |
//| OPEN effect predicate: aggregate volume remains the fast path,   |
//| while exact current-runtime or historical execution identity can |
//| prove a completed Recovery OPEN whose net exposure is unchanged. |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ENGINE_T14_WRAPPER_MQH
#define BD_RECOVERY_ENGINE_T14_WRAPPER_MQH

// Pre-load these before the narrow macro below. The base then sees their
// include guards and cannot rewrite the original pure helper declaration.
#include <BlackDragon/ExecutionLayer.mqh>
#include "RecoveryPersistence.mqh"

bool Recovery_T14HistoryOpenProof(const eRecoveryCoreDirection dir,
                                  const SRecoveryPersistPending &p)
{
   if(!p.active || p.commandType != EXEC_CMD_RECOVERY_OPEN ||
      p.cycleKey != Recovery_CycleKey(dir) || p.ownerMagic <= 0 ||
      p.targetUnits <= 0 || p.startedAt <= 0)
      return false;

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) return false;
   double targetVolume = Recovery_UnitsToVolume(p.targetUnits, step);
   double eps = step * 0.5;

   // Current-runtime proof is strongest: ExecutionLayer recorded the exact
   // request_id + server order/deal + owner/cycle/volume before compacting the
   // journal. This is the normal tester sync-fallback path.
   if(Exec_T14OpenProofMatches(p.cycleKey, p.ownerMagic,
                               p.targetUnits, p.startedAt))
      return true;

   // Restart/crash fallback: the durable Recovery command already persists
   // cycle/generation/bundle identity. Recovery market OPEN comments carry the
   // same tuple (BDR|C=...|G=...|B=...). Require exactly one matching entry
   // deal after the command start and exact requested volume. Ambiguous or
   // duplicate candidates remain fail-closed.
   datetime from = p.startedAt > 2 ? p.startedAt - 2 : 0;
   if(!HistorySelect(from, TimeCurrent())) return false;

   string prefix = "BDR|C=" + (string)p.cycleKey +
                   "|G=" + (string)p.generation +
                   "|B=" + (string)p.bundleId + "|";
   long expectedType = Recovery_HedgeDirection(dir) == 0 ? DEAL_TYPE_BUY : DEAL_TYPE_SELL;
   int matches = 0;
   double matchedVolume = 0.0;
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0) continue;
      long timeMsc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
      if(timeMsc + 999 < (long)p.startedAt * 1000) continue;
      if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
         HistoryDealGetInteger(deal, DEAL_MAGIC) != p.ownerMagic ||
         HistoryDealGetInteger(deal, DEAL_TYPE) != expectedType)
         continue;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
      string comment = HistoryDealGetString(deal, DEAL_COMMENT);
      if(StringFind(comment, prefix) != 0) continue;
      if((ulong)HistoryDealGetInteger(deal, DEAL_ORDER) == 0) continue;
      matches++;
      matchedVolume += HistoryDealGetDouble(deal, DEAL_VOLUME);
   }

   return matches == 1 && MathAbs(matchedVolume - targetVolume) <= eps;
}

bool Recovery_T14PendingVolumeEffectConfirmed(const bool isOpen,
                                              const long beforeUnits,
                                              const long targetUnits,
                                              const long currentUnits,
                                              const eRecoveryCoreDirection dir,
                                              const SRecoveryPersistPending &p)
{
   // Preserve every T9/T13 aggregate rule first. Identity is additive proof,
   // never a relaxation for CLOSE/MODIFY or invalid metadata.
   if(Recovery_PendingVolumeEffectConfirmed(isOpen, beforeUnits,
                                            targetUnits, currentUnits))
      return true;
   if(!isOpen || p.commandType != EXEC_CMD_RECOVERY_OPEN) return false;
   if(beforeUnits != p.observedUnitsBefore || targetUnits != p.targetUnits)
      return false;
   return Recovery_T14HistoryOpenProof(dir, p);
}

// Narrow dependency injection into the two OPEN/CLOSE calls inside the pinned
// T13 CRecoveryEngine::PendingEffectConfirmed(). RecoveryPersistence.mqh was
// already parsed above, so its original helper remains untouched for all tests
// and all other callers.
#define Recovery_PendingVolumeEffectConfirmed(isOpen,beforeUnits,targetUnits,currentUnits) \
   Recovery_T14PendingVolumeEffectConfirmed((isOpen),(beforeUnits),(targetUnits),(currentUnits),dir,p)
#include "RecoveryEngineT13Base.mqh"
#undef Recovery_PendingVolumeEffectConfirmed

#endif // BD_RECOVERY_ENGINE_T14_WRAPPER_MQH
