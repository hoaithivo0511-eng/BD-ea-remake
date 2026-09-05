//+------------------------------------------------------------------+
//| OverlapT177Coordinator.mqh — T17.13 non-exclusive pre-leg wait  |
//| Durable execution identity remains; read-only WAIT cannot starve |
//| same-side Core DCA/Pyramid growth.                               |
//+------------------------------------------------------------------+
#ifndef BD_OVERLAP_T177_COORDINATOR_T177_C5_WRAPPER_MQH
#define BD_OVERLAP_T177_COORDINATOR_T177_C5_WRAPPER_MQH

#include <BlackDragon/Recovery/RecoveryT177MigrationPolicy.mqh>

#define private protected
#define COverlapT177Coordinator COverlapT177CoordinatorT177C3Base
#include "OverlapT177CoordinatorT177C3Base.mqh"
#undef COverlapT177Coordinator
#undef private

class COverlapT177Coordinator : public COverlapT177CoordinatorT177C3Base
{
private:
   CRecoveryEngine *m_c5Recovery;

   eOverlapT177DriveDisposition SoftReleaseArmedT1713(const int idx,
                                                       const string reason)
   {
      ResetSide(idx);
      string why = "";
      if(!SaveAll(why) && why != "")
      {
         LatchReconcile(idx, "T17.13 soft-release persistence failed: " + why);
         return overlap_T177_DRIVE_RECONCILE;
      }
      Log_WarnEvery("Overlap", "t1713softrelease" + (string)idx,
                    "T17.13 soft-release " + (idx == 0 ? "BUY" : "SELL") +
                    " | chưa có broker mutation; Core DCA/Pyramid không bị khóa | " + reason,
                    Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
      return overlap_T177_DRIVE_WAIT;
   }

   eOverlapT177DriveDisposition DriveArmedT1713(const int idx,
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

      if(!firstExists || !lastExists)
         return SoftReleaseArmedT1713(idx, "pair candidate không còn live");

      double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      double eps = step > 0.0 ? step * 0.5 : 1e-9;
      if(MathAbs(firstVolume - s.firstVolume) > eps ||
         MathAbs(lastVolume - s.lastVolume) > eps)
         return SoftReleaseArmedT1713(idx, "Core volume thay đổi trước leg1; tính lại candidate mới");

      double reserve = ExecutionReserveCash(ctx, firstVolume + lastVolume, 2);
      bool economicsSafe = Overlap_T177PreLeg1EligiblePure(side.count,
                                                            OverlapOrderNumber,
                                                            Overlap,
                                                            firstFloating,
                                                            lastFloating,
                                                            OverlapPercent,
                                                            reserve);
      bool defer = false;
      RouteForSide(s.dir, defer);
      if(!Overlap_T1713MayCommitPairPure(economicsSafe, defer))
      {
         string reason = !economicsSafe ? "economics chưa đủ để submit leg1"
                                        : "Recovery route đang read-only DEFER";
         return SoftReleaseArmedT1713(idx, reason);
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
      bool ok = COverlapT177CoordinatorT177C3Base::Init(exec, recovery,
                                                        recoveryExit, why);
      if(!ok || m_globalReconcile) return ok;

      // T17.13 migration: an old persisted PAIR_ARMED proves no broker close
      // was submitted yet. Release it and let current basket economics choose
      // a fresh candidate; submitted/reconcile states remain durable.
      bool released = false;
      for(int i = 0; i < 2; i++)
      {
         if((eOverlapT177State)m_side[i].state == overlap_T177_PAIR_ARMED)
         {
            ResetSide(i);
            released = true;
         }
      }
      if(released)
      {
         string persistWhy = "";
         if(!SaveAll(persistWhy) && persistWhy != "")
         {
            m_globalReconcile = true;
            why = "T17.13 không clear được persisted pre-leg pair: " + persistWhy;
            return true;
         }
         Log_Warn("Overlap", "t1713migrate",
                  "T17.13 soft-release persisted PAIR_ARMED: chưa có broker mutation, candidate sẽ được tính lại");
      }
      return true;
   }

   bool FinalizeConfirmedAccountWideFlat(const bool accountGuardCompleted,
                                         string &why)
   {
      why = "";
      bool executionPending = m_exec == NULL || m_exec.HasPending();
      bool recoveryBlocking = m_recoveryExit == NULL ||
                              m_recoveryExit.HasBlockingWork();
      if(!Recovery_T1717VerifiedAccountFlatResetPure(accountGuardCompleted,
                                                      PositionsTotal(),
                                                      executionPending,
                                                      recoveryBlocking))
      {
         why = "Overlap reset cần account guard complete + account flat + execution/Recovery quiet";
         return false;
      }

      SOverlapT177Side oldBuy = m_side[0];
      SOverlapT177Side oldSell = m_side[1];
      bool oldLoadedBuy = m_loadedFromDisk[0];
      bool oldLoadedSell = m_loadedFromDisk[1];
      bool oldGlobalReconcile = m_globalReconcile;

      ResetSide(0);
      ResetSide(1);
      m_globalReconcile = false;
      bool saved = SaveAll(why);
      bool persistenceSkipped = MQLInfoInteger(MQL_TESTER) &&
                                !RecoveryTesterResumeState_;
      if(saved && !persistenceSkipped &&
         (FileIsExist(m_file) || FileIsExist(m_temp)))
      {
         saved = false;
         why = "terminal Overlap flat reset còn sót state file";
      }
      if(saved)
         return true;

      m_side[0] = oldBuy;
      m_side[1] = oldSell;
      m_loadedFromDisk[0] = oldLoadedBuy;
      m_loadedFromDisk[1] = oldLoadedSell;
      m_globalReconcile = oldGlobalReconcile;
      if(why == "") why = "không persist được terminal Overlap flat reset";
      return false;
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

      bool defer = false;
      RouteForSide(dir, defer);
      if(!Overlap_T1713MayCommitPairPure(true, defer))
      {
         why = "Recovery đang read-only DEFER; pair chỉ là soft candidate, chưa persist/khóa side";
         return false;
      }
      return COverlapT177CoordinatorT177C3Base::Arm(dir, firstTicket,
                                                     lastTicket, now, why);
   }

   bool BlocksCoreGrowth(const int dir) const
   {
      if(m_globalReconcile)
      {
         Log_WarnEvery("Overlap", "t1713coreblockglobal",
                       "T17.13 Core growth blocked: Overlap đang RECONCILE hai phía",
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
         return true;
      }
      int idx = Index(dir);
      eOverlapT177State state = (eOverlapT177State)m_side[idx].state;
      bool blocked = Overlap_T1713BlocksCoreGrowthPure(state);
      if(blocked)
         Log_WarnEvery("Overlap", "t1713coreblock" + (string)idx,
                       "T17.13 Core growth blocked only by Overlap broker mutation/reconcile state=" +
                       Overlap_T177StateNameVi(state),
                       Recovery_T165WaitLogSecondsPure(RecoveryWaitLogSeconds_));
      return blocked;
   }

   eOverlapT177DriveDisposition DriveSide(const EAContext &ctx,
                                          const BasketSide &side,
                                          const int dir)
   {
      int idx = Index(dir);
      if(m_globalReconcile) return overlap_T177_DRIVE_RECONCILE;
      eOverlapT177State state = (eOverlapT177State)m_side[idx].state;
      if(state == overlap_T177_PAIR_ARMED)
         return DriveArmedT1713(idx, ctx, side);
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
