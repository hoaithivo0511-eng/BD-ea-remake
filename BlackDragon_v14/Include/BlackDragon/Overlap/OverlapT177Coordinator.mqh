//+------------------------------------------------------------------+
//| OverlapT177Coordinator.mqh — T17.12 durable same-pair WAIT      |
//| C5 policy gate retained; T17.12 overrides PAIR_ARMED liveness   |
//| only so temporary economics/Recovery WAIT is read-only.          |
//+------------------------------------------------------------------+
#ifndef BD_OVERLAP_T177_COORDINATOR_T177_C5_WRAPPER_MQH
#define BD_OVERLAP_T177_COORDINATOR_T177_C5_WRAPPER_MQH

#include <BlackDragon/Recovery/RecoveryT177MigrationPolicy.mqh>

// Same wrapper technique already used by Strategy: keep the verified C3 base
// implementation intact and expose internals only to this compatibility layer.
#define private protected
#define COverlapT177Coordinator COverlapT177CoordinatorT177C3Base
#include "OverlapT177CoordinatorT177C3Base.mqh"
#undef COverlapT177Coordinator
#undef private

class COverlapT177Coordinator : public COverlapT177CoordinatorT177C3Base
{
private:
   CRecoveryEngine *m_c5Recovery;

   eOverlapT177DriveDisposition DriveArmedT1712(const int idx,
                                                const EAContext &ctx,
                                                const BasketSide &side)
   {
      SOverlapT177Side s = m_side[idx];
      bool firstExists = false, lastExists = false;
      double firstVolume = 0.0, lastVolume = 0.0;
      double firstFloating = 0.0, lastFloating = 0.0;
      if(!ReadLiveTicket(s.firstTicket, s.dir, s.firstOwnerMagic, s.firstPositionId,
                         firstExists, firstVolume, firstFloating) ||
         !ReadLiveTicket(s.lastTicket, s.dir, s.lastOwnerMagic, s.lastPositionId,
                         lastExists, lastVolume, lastFloating))
      {
         LatchReconcile(idx, "pair identity đổi trước leg 1");
         return overlap_T177_DRIVE_RECONCILE;
      }

      // No Overlap-owned mutation exists yet. A broker-observable stale pair
      // remains a valid cancellation reason; this is not an economic WAIT.
      if(!firstExists || !lastExists)
      {
         ResetSide(idx);
         string why = "";
         SaveAll(why);
         return overlap_T177_DRIVE_WAIT;
      }

      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double eps = step > 0.0 ? step * 0.5 : 1e-9;
      if(MathAbs(firstVolume - s.firstVolume) > eps ||
         MathAbs(lastVolume - s.lastVolume) > eps)
      {
         // External volume mutation invalidates the locked obligation identity.
         ResetSide(idx);
         string why = "";
         SaveAll(why);
         return overlap_T177_DRIVE_WAIT;
      }

      double reserve = ExecutionReserveCash(ctx, firstVolume + lastVolume, 2);
      if(!Overlap_T177PreLeg1EligiblePure(side.count, OverlapOrderNumber, Overlap,
                                          firstFloating, lastFloating,
                                          OverlapPercent, reserve))
      {
         // T17.12 P1-B: the exact same-side pair stays durably PAIR_ARMED.
         // No reset, no persistence rewrite and therefore no ARM churn on the
         // next tick. Strategy still yields because WAIT does not consume the
         // global mutation tick, so opposite-side work remains eligible.
         Log_WarnEvery("Overlap", "t1712pairwait" + (string)idx,
                       "CHỜ " + (idx == 0 ? "BUY" : "SELL") +
                       " | Cặp Overlap đã khóa, tạm chưa đủ economics; giữ nguyên nghĩa vụ",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return overlap_T177_DRIVE_WAIT;
      }
      return SubmitLeg(idx, true, ctx);
   }

public:
   COverlapT177Coordinator(void) : COverlapT177CoordinatorT177C3Base()
   {
      m_c5Recovery = NULL;
   }

   bool Init(CExecutionLayer *exec,
             CRecoveryEngine *recovery,
             CRecoveryExitCoordinator *recoveryExit,
             string &why)
   {
      m_c5Recovery = recovery;
      return COverlapT177CoordinatorT177C3Base::Init(exec, recovery,
                                                      recoveryExit, why);
   }

   bool Arm(const int dir, const ulong firstTicket, const ulong lastTicket,
            const datetime now, string &why)
   {
      why = "";
      eOverlapPolicyT177 policy = Recovery_T177EffectiveOverlapPolicyC5();
      if(policy == OVERLAP_OFF)
      {
         why = "Overlap đang tắt";
         return false;
      }
      if(policy == OVERLAP_CORE_ONLY && RecoveryMode_ == recovery_ACTIVE &&
         m_c5Recovery != NULL)
      {
         eRecoveryCoreDirection rdir = dir == BD_DIR_BUY ? recovery_CORE_BUY
                                                         : recovery_CORE_SELL;
         SRecoveryCycle cycle;
         m_c5Recovery.GetCycle(rdir, cycle);
         bool terminalNoHedge = m_c5Recovery.TerminalNoHedge(rdir);
         if(Recovery_T1711OverlapCoreOnlyBlockedPure(cycle.state,
                                                     cycle.activeHedgeLots,
                                                     terminalNoHedge,
                                                     ContinueDcaAfterHedge_))
         {
            why = "Side đang có trạng thái/Hedge Recovery; chế độ CORE_ONLY không tạo cặp mới";
            return false;
         }
      }
      return COverlapT177CoordinatorT177C3Base::Arm(dir, firstTicket,
                                                     lastTicket, now, why);
   }

   eOverlapT177DriveDisposition DriveSide(const EAContext &ctx,
                                          const BasketSide &side,
                                          const int dir)
   {
      int idx = Index(dir);
      if(m_globalReconcile) return overlap_T177_DRIVE_RECONCILE;
      eOverlapT177State state = (eOverlapT177State)m_side[idx].state;
      if(state == overlap_T177_PAIR_ARMED)
         return DriveArmedT1712(idx, ctx, side);
      return COverlapT177CoordinatorT177C3Base::DriveSide(ctx, side, dir);
   }

   eOverlapT177DriveDisposition Drive(const EAContext &ctx,
                                      const BasketSide &buy,
                                      const BasketSide &sell)
   {
      if(m_globalReconcile) return overlap_T177_DRIVE_RECONCILE;
      eOverlapT177DriveDisposition b = DriveSide(ctx, buy, BD_DIR_BUY);
      if(Overlap_T177ConsumesStrategyTickPure(b)) return b;
      eOverlapT177DriveDisposition s = DriveSide(ctx, sell, BD_DIR_SELL);
      if(Overlap_T177ConsumesStrategyTickPure(s)) return s;
      if(b == overlap_T177_DRIVE_WAIT || s == overlap_T177_DRIVE_WAIT)
         return overlap_T177_DRIVE_WAIT;
      return overlap_T177_DRIVE_NO_EFFECT;
   }
};

#endif // BD_OVERLAP_T177_COORDINATOR_T177_C5_WRAPPER_MQH
