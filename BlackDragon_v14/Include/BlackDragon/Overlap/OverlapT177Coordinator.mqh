//+------------------------------------------------------------------+
//| OverlapT177Coordinator.mqh — T17.7 C5 consolidated policy gate  |
//| Existing durable C3 obligation always survives policy changes.   |
//+------------------------------------------------------------------+
#ifndef BD_OVERLAP_T177_COORDINATOR_T177_C5_WRAPPER_MQH
#define BD_OVERLAP_T177_COORDINATOR_T177_C5_WRAPPER_MQH

#include <BlackDragon/Recovery/RecoveryT177MigrationPolicy.mqh>

#define COverlapT177Coordinator COverlapT177CoordinatorT177C3Base
#include "OverlapT177CoordinatorT177C3Base.mqh"
#undef COverlapT177Coordinator

class COverlapT177Coordinator : public COverlapT177CoordinatorT177C3Base
{
private:
   CRecoveryEngine *m_c5Recovery;

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
         if(Recovery_T177OverlapCoreOnlyBlockedPure(cycle.state,
                                                    cycle.activeHedgeLots))
         {
            why = "Side đang có trạng thái/Hedge Recovery; chế độ CORE_ONLY không tạo cặp mới";
            return false;
         }
      }
      return COverlapT177CoordinatorT177C3Base::Arm(dir, firstTicket,
                                                     lastTicket, now, why);
   }
};

#endif // BD_OVERLAP_T177_COORDINATOR_T177_C5_WRAPPER_MQH
