//+------------------------------------------------------------------+
//| RecoveryArcsStackPostDeal.mqh — T16.1 symmetric event-order gate |
//| Handles the opposite valid order: DEAL_ADD is consumed before a  |
//| later OnTick can observe that the protected position disappeared. |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_STACK_POST_DEAL_MQH
#define BD_RECOVERY_ARCS_STACK_POST_DEAL_MQH

#include "RecoveryArcsStackHardened.mqh"

class CRecoveryArcsStackFinal : public CRecoveryArcsStack
{
private:
   bool ResumeDealFirstClose(const eRecoveryCoreDirection dir,
                             const EAContext &ctx,
                             string &why)
   {
      int di = Idx(dir);
      if(m_dir[di].phase != ARCS_LOCKED || m_dir[di].activeLayer < 0)
         return false;

      int li = m_dir[di].activeLayer;
      SArcsLayer layer;
      GetLayer(dir, li, layer);

      // Tick-before-DEAL uses PROTECTIVE_CLOSE_WAIT and leaves a non-zero
      // protectiveCloseObservedAt; the hardened base already resumes it.
      // This branch is ONLY for DEAL-before-tick: the exact closing DEAL has
      // already been consumed by RefreshClosedGenerationFromDeal(), which is
      // the only path that can retire a LOCK_PENDING active layer before the
      // wait timestamp exists.
      if(!layer.used || layer.state != ARCS_LAYER_CLOSED ||
         layer.protectiveCloseObservedAt > 0)
         return false;

      // No generation reuse or new mutation occurred before exact DEAL proof.
      // Now that the layer is CLOSED under the same active-layer identity,
      // normal ARCS progression may continue/retry.
      return AfterLayerLocked(dir, ctx.now, why);
   }

public:
   bool Drive(CExecutionLayer &exec, const EAContext &ctx, string &why)
   {
      why = "";
      if(ResumeDealFirstClose(recovery_CORE_BUY, ctx, why)) return true;
      if(ResumeDealFirstClose(recovery_CORE_SELL, ctx, why)) return true;
      return CRecoveryArcsStack::Drive(exec, ctx, why);
   }
};

#endif // BD_RECOVERY_ARCS_STACK_POST_DEAL_MQH
