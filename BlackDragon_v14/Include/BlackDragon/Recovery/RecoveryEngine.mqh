//+------------------------------------------------------------------+
//| RecoveryEngine.mqh — T14 identity + T16 ARCS compatibility layer|
//| Exact T13/T14 engine remains available for the legacy contract.  |
//| T16 routes new sizing/stack/SL semantics into CRecoveryArcsStack.|
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ENGINE_T16_WRAPPER_MQH
#define BD_RECOVERY_ENGINE_T16_WRAPPER_MQH

#include <BlackDragon/ExecutionLayer.mqh>
#include "RecoveryPersistence.mqh"
#include "RecoveryT16Config.mqh"

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

   if(Exec_T14OpenProofMatches(p.cycleKey, p.ownerMagic,
                               p.targetUnits, p.startedAt))
      return true;

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
   if(Recovery_PendingVolumeEffectConfirmed(isOpen, beforeUnits,
                                            targetUnits, currentUnits))
      return true;
   if(!isOpen || p.commandType != EXEC_CMD_RECOVERY_OPEN) return false;
   if(beforeUnits != p.observedUnitsBefore || targetUnits != p.targetUnits)
      return false;
   return Recovery_T14HistoryOpenProof(dir, p);
}

// Preserve the exact T13/T14 engine as a named compatibility base. No T16
// semantics are injected into the pinned source file itself.
#define CRecoveryEngine CRecoveryEngineT15Base
#define Recovery_PendingVolumeEffectConfirmed(isOpen,beforeUnits,targetUnits,currentUnits) \
   Recovery_T14PendingVolumeEffectConfirmed((isOpen),(beforeUnits),(targetUnits),(currentUnits),dir,p)
#include "RecoveryEngineT13Base.mqh"
#undef Recovery_PendingVolumeEffectConfirmed
#undef CRecoveryEngine

#include "RecoveryArcsStackHardened.mqh"

class CRecoveryEngine : public CRecoveryEngineT15Base
{
private:
   CRecoveryArcsStack m_arcs;

   bool UseT16() const
   {
      return RecoveryMode_ != recovery_OFF && Recovery_T16UseStackEngine();
   }

public:
   bool Init()
   {
      if(UseT16()) return m_arcs.Init();
      return CRecoveryEngineT15Base::Init();
   }

   void OnTick(const EAContext &ctx)
   {
      if(UseT16()) { m_arcs.OnTick(ctx); return; }
      CRecoveryEngineT15Base::OnTick(ctx);
   }

   void OnTradeTransaction(const MqlTradeTransaction &trans)
   {
      if(UseT16()) { m_arcs.OnTradeTransaction(trans); return; }
      CRecoveryEngineT15Base::OnTradeTransaction(trans);
   }

   bool StartupReconcile(CExecutionLayer &exec, string &why)
   {
      if(UseT16()) return m_arcs.StartupReconcile(exec, why);
      return CRecoveryEngineT15Base::StartupReconcile(exec, why);
   }

   bool ActiveReady() const
   {
      if(UseT16()) return m_arcs.ActiveReady();
      return CRecoveryEngineT15Base::ActiveReady();
   }

   bool FlushPersistence()
   {
      if(UseT16()) return m_arcs.FlushPersistence();
      return CRecoveryEngineT15Base::FlushPersistence();
   }

   void RecordDealCursor(const ulong deal)
   {
      if(UseT16()) { m_arcs.RecordDealCursor(deal); return; }
      CRecoveryEngineT15Base::RecordDealCursor(deal);
   }

   bool DriveActive(CExecutionLayer &exec, const EAContext &ctx, string &why)
   {
      if(UseT16()) return m_arcs.Drive(exec, ctx, why);
      return CRecoveryEngineT15Base::DriveActive(exec, ctx, why);
   }

   long RehedgeRequiredUnits(const eRecoveryCoreDirection dir) const
   {
      if(UseT16()) return m_arcs.NextGenerationUnits(dir);
      return CRecoveryEngineT15Base::RehedgeRequiredUnits(dir);
   }

   long RehedgeAnchorTicks(const eRecoveryCoreDirection dir)
   {
      if(UseT16()) return m_arcs.RehedgeAnchorTicks(dir);
      return CRecoveryEngineT15Base::RehedgeAnchorTicks(dir);
   }

   double LockTargetPrice(const eRecoveryCoreDirection dir)
   {
      if(UseT16()) return m_arcs.LockTargetPrice(dir);
      return CRecoveryEngineT15Base::LockTargetPrice(dir);
   }

   void GetCycle(const eRecoveryCoreDirection dir, SRecoveryCycle &out) const
   {
      if(UseT16()) { m_arcs.GetCycle(dir, out); return; }
      CRecoveryEngineT15Base::GetCycle(dir, out);
   }

   void GetT5Runtime(const eRecoveryCoreDirection dir,
                     SRecoveryT5CycleRuntime &out)
   {
      if(UseT16()) { m_arcs.GetT5Runtime(dir, out); return; }
      CRecoveryEngineT15Base::GetT5Runtime(dir, out);
   }

   bool HasDurableCommand(const eRecoveryCoreDirection dir) const
   {
      if(UseT16()) return m_arcs.HasExternalPending(dir);
      return CRecoveryEngineT15Base::HasDurableCommand(dir);
   }

   bool ArmDurableCommand(const eRecoveryCoreDirection dir,
                          const eExecCommandType commandType,
                          const long ownerMagic,
                          const ulong ticket,
                          const long targetUnits,
                          const long observedUnitsBefore,
                          const double targetPrice,
                          const int generation,
                          const int bundleId,
                          string &why)
   {
      if(UseT16())
         return m_arcs.ArmExternalPending(dir, commandType, ownerMagic, ticket,
                                          targetUnits, observedUnitsBefore,
                                          targetPrice, why);
      return CRecoveryEngineT15Base::ArmDurableCommand(dir, commandType, ownerMagic,
                                                       ticket, targetUnits,
                                                       observedUnitsBefore,
                                                       targetPrice, generation,
                                                       bundleId, why);
   }

   bool CancelDurableCommand(const eRecoveryCoreDirection dir)
   {
      if(UseT16()) return m_arcs.CancelExternalPending(dir);
      return CRecoveryEngineT15Base::CancelDurableCommand(dir);
   }

   bool ResolveDurableCommand(CExecutionLayer &exec,
                              const eRecoveryCoreDirection dir,
                              const datetime now,
                              string &why)
   {
      if(UseT16()) return m_arcs.ResolveExternalPending(exec, dir, why);
      return CRecoveryEngineT15Base::ResolveDurableCommand(exec, dir, now, why);
   }

   bool FinalizeConfirmedGlobalFlatten(CExecutionLayer &exec,
                                       const datetime now,
                                       string &why)
   {
      if(UseT16()) return m_arcs.FinalizeConfirmedGlobalFlatten(exec, now, why);
      return CRecoveryEngineT15Base::FinalizeConfirmedGlobalFlatten(exec, now, why);
   }

   bool FinalizeConfirmedSideMutation(CExecutionLayer &exec,
                                      const eRecoveryCoreDirection dir,
                                      const datetime now,
                                      string &why)
   {
      if(UseT16()) return m_arcs.FinalizeConfirmedSideMutation(exec, dir, now, why);
      return CRecoveryEngineT15Base::FinalizeConfirmedSideMutation(exec, dir, now, why);
   }

   bool T16HasExposure(const eRecoveryCoreDirection dir) const
   {
      return UseT16() && m_arcs.HasExposure(dir);
   }

   bool T16ExpectedBrokerSlDeal(const ulong deal)
   {
      return UseT16() && m_arcs.ExpectedBrokerSlDeal(deal);
   }

   void T16LatchExternalMutation(const eRecoveryCoreDirection dir,
                                 const string reason)
   {
      if(UseT16()) m_arcs.LatchExternalMutation(dir, reason);
   }

   int AuditStoredCount() const
   {
      if(UseT16()) return m_arcs.AuditStoredCount();
      return CRecoveryEngineT15Base::AuditStoredCount();
   }

   int AuditTotalCount() const
   {
      if(UseT16()) return m_arcs.AuditTotalCount();
      return CRecoveryEngineT15Base::AuditTotalCount();
   }
};

#endif // BD_RECOVERY_ENGINE_T16_WRAPPER_MQH
