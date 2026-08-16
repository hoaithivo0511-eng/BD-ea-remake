//+------------------------------------------------------------------+
//| RecoveryRegistry.mqh — T3 BUY/SELL cycle registry                |
//| Invariants: two independent Core cycles; bounded in-memory audit.|
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_REGISTRY_MQH
#define BD_RECOVERY_REGISTRY_MQH

#include "RecoveryStateMachine.mqh"

#define BD_RECOVERY_ENTRY_EVIDENCE_CAP 16
#define BD_RECOVERY_TRANSITION_AUDIT_CAP 32

struct SRecoveryEntryEvidence
{
   bool                   valid;
   eRecoveryCoreDirection direction;
   ulong                  deal;
   ulong                  position;
   double                 price;
   datetime               time;
};

struct SRecoveryTransitionAudit
{
   int                    sequence;
   int                    cycleKey;
   eRecoveryState         fromState;
   eRecoveryState         toState;
   datetime               time;
   string                 reason;
};

struct SRecoveryCycle
{
   int                    cycleKey;
   eRecoveryCoreDirection direction;
   eRecoveryState         state;
   bool                   armed;
   int                    cycleSerial;

   int                    coreCount;
   double                 coreLots;
   double                 coreNetBE;
   double                 activeHedgeLots;
   double                 hedgeNetBE;
   double                 coveragePercent;
   double                 corridorPrice;

   int                    armedDcaCount;
   ulong                  anchorDeal;
   ulong                  anchorPosition;
   double                 anchorPrice;
   long                   anchorTicks;
   datetime               anchorTime;

   eRecoveryShadowDecision shadowDecision;
   bool                   shadowDecisionLatched;
   long                   shadowTargetUnits;
   double                 shadowTriggerPrice;
   datetime               shadowDecisionAt;

   bool                   anchorEvidenceWaitLogged;
   int                    transitionSequence;
   datetime               lastTransitionAt;
};

class CRecoveryRegistry
{
private:
   SRecoveryCycle           m_cycle[2];
   SRecoveryEntryEvidence   m_entryEvidence[BD_RECOVERY_ENTRY_EVIDENCE_CAP];
   int                      m_entryWrite;
   int                      m_entryStored;
   SRecoveryTransitionAudit m_audit[BD_RECOVERY_TRANSITION_AUDIT_CAP];
   int                      m_auditTotal;

   int Index(const eRecoveryCoreDirection dir) const
   {
      return dir == recovery_CORE_BUY ? 0 : 1;
   }

   void ClearCycleRuntime(SRecoveryCycle &c, const bool keepSerial)
   {
      int serial = keepSerial ? c.cycleSerial : 1;
      c.cycleKey                 = Recovery_CycleKey(c.direction);
      c.state                    = recovery_CORE_ONLY;
      c.armed                    = false;
      c.cycleSerial              = serial;
      c.coreCount                = 0;
      c.coreLots                 = 0.0;
      c.coreNetBE                = 0.0;
      c.activeHedgeLots          = 0.0;
      c.hedgeNetBE               = 0.0;
      c.coveragePercent          = 0.0;
      c.corridorPrice            = 0.0;
      c.armedDcaCount            = 0;
      c.anchorDeal               = 0;
      c.anchorPosition           = 0;
      c.anchorPrice              = 0.0;
      c.anchorTicks              = 0;
      c.anchorTime               = 0;
      c.shadowDecision           = recovery_SHADOW_NONE;
      c.shadowDecisionLatched    = false;
      c.shadowTargetUnits        = 0;
      c.shadowTriggerPrice       = 0.0;
      c.shadowDecisionAt         = 0;
      c.anchorEvidenceWaitLogged = false;
      c.transitionSequence       = 0;
      c.lastTransitionAt         = 0;
   }

   void AddAudit(const int idx, const eRecoveryState fromState,
                 const eRecoveryState toState, const datetime now,
                 const string reason)
   {
      int slot = m_auditTotal % BD_RECOVERY_TRANSITION_AUDIT_CAP;
      m_audit[slot].sequence  = m_auditTotal + 1;
      m_audit[slot].cycleKey  = m_cycle[idx].cycleKey;
      m_audit[slot].fromState = fromState;
      m_audit[slot].toState   = toState;
      m_audit[slot].time      = now;
      m_audit[slot].reason    = reason;
      m_auditTotal++;
   }

public:
   void Init()
   {
      m_cycle[0].direction = recovery_CORE_BUY;
      m_cycle[1].direction = recovery_CORE_SELL;
      ClearCycleRuntime(m_cycle[0], false);
      ClearCycleRuntime(m_cycle[1], false);

      m_entryWrite  = 0;
      m_entryStored = 0;
      m_auditTotal  = 0;
      for(int i = 0; i < BD_RECOVERY_ENTRY_EVIDENCE_CAP; i++)
         m_entryEvidence[i].valid = false;
   }

   void GetCycle(const eRecoveryCoreDirection dir, SRecoveryCycle &out) const
   {
      out = m_cycle[Index(dir)];
   }

   bool Transition(const eRecoveryCoreDirection dir, const eRecoveryState toState,
                   const datetime now, const string reason)
   {
      int idx = Index(dir);
      eRecoveryState fromState = m_cycle[idx].state;
      if(!Recovery_StateTransitionAllowed(fromState, toState)) return false;
      m_cycle[idx].state = toState;
      m_cycle[idx].transitionSequence++;
      m_cycle[idx].lastTransitionAt = now;
      AddAudit(idx, fromState, toState, now, reason);
      return true;
   }

   void ObserveCore(const eRecoveryCoreDirection dir, const int count,
                    const double lots, const double coreNetBE,
                    const datetime now)
   {
      int idx = Index(dir);
      SRecoveryCycle before = m_cycle[idx];

      // A completed slot is reusable only when a new Core series is observed.
      if(m_cycle[idx].state == recovery_COMPLETED && count > 0)
      {
         int nextSerial = m_cycle[idx].cycleSerial + 1;
         eRecoveryState oldState = m_cycle[idx].state;
         ClearCycleRuntime(m_cycle[idx], true);
         m_cycle[idx].cycleSerial = nextSerial;
         AddAudit(idx, oldState, recovery_CORE_ONLY, now, "new Core series observed");
      }

      m_cycle[idx].coreCount       = count < 0 ? 0 : count;
      m_cycle[idx].coreLots        = lots > 0.0 ? lots : 0.0;
      m_cycle[idx].coreNetBE       = coreNetBE > 0.0 ? coreNetBE : 0.0;
      m_cycle[idx].coveragePercent = Recovery_CoveragePercent(m_cycle[idx].coreLots,
                                                              m_cycle[idx].activeHedgeLots);
      m_cycle[idx].corridorPrice   = Recovery_CorridorPrice(dir,
                                                            m_cycle[idx].coreNetBE,
                                                            m_cycle[idx].hedgeNetBE);

      // SHADOW has no hedge mutation. If its Core disappears, complete the
      // logical cycle once. A partial removal does NOT clear the armed latch.
      if(count == 0 && before.coreCount > 0 && m_cycle[idx].armed &&
         m_cycle[idx].state == recovery_ARMED)
         Transition(dir, recovery_COMPLETED, now, "Core became flat in SHADOW");
   }

   void ObserveHedgeMetrics(const eRecoveryCoreDirection dir,
                            const double activeLots, const double hedgeNetBE)
   {
      int idx = Index(dir);
      m_cycle[idx].activeHedgeLots = activeLots > 0.0 ? activeLots : 0.0;
      m_cycle[idx].hedgeNetBE      = hedgeNetBE > 0.0 ? hedgeNetBE : 0.0;
      m_cycle[idx].coveragePercent = Recovery_CoveragePercent(m_cycle[idx].coreLots,
                                                              m_cycle[idx].activeHedgeLots);
      m_cycle[idx].corridorPrice   = Recovery_CorridorPrice(dir,
                                                            m_cycle[idx].coreNetBE,
                                                            m_cycle[idx].hedgeNetBE);
   }

   void RecordCoreEntryEvidence(const eRecoveryCoreDirection dir,
                                const ulong deal, const ulong position,
                                const double price, const datetime time)
   {
      if(deal == 0 || position == 0 || price <= 0.0) return;
      int slot = m_entryWrite;
      m_entryEvidence[slot].valid     = true;
      m_entryEvidence[slot].direction = dir;
      m_entryEvidence[slot].deal      = deal;
      m_entryEvidence[slot].position  = position;
      m_entryEvidence[slot].price     = price;
      m_entryEvidence[slot].time      = time;
      m_entryWrite = (m_entryWrite + 1) % BD_RECOVERY_ENTRY_EVIDENCE_CAP;
      if(m_entryStored < BD_RECOVERY_ENTRY_EVIDENCE_CAP) m_entryStored++;
   }

   bool FindCoreEntryEvidence(const eRecoveryCoreDirection dir,
                              const ulong position,
                              SRecoveryEntryEvidence &out) const
   {
      if(position == 0) return false;
      for(int n = 0; n < m_entryStored; n++)
      {
         int slot = m_entryWrite - 1 - n;
         while(slot < 0) slot += BD_RECOVERY_ENTRY_EVIDENCE_CAP;
         if(m_entryEvidence[slot].valid &&
            m_entryEvidence[slot].direction == dir &&
            m_entryEvidence[slot].position == position)
         {
            out = m_entryEvidence[slot];
            return true;
         }
      }
      return false;
   }

   bool LatchArmed(const eRecoveryCoreDirection dir,
                   const SRecoveryEntryEvidence &evidence,
                   const int dcaCount, const long anchorTicks,
                   const datetime now)
   {
      int idx = Index(dir);
      if(m_cycle[idx].armed || m_cycle[idx].state != recovery_CORE_ONLY) return false;
      if(!evidence.valid || evidence.deal == 0 || evidence.position == 0 ||
         evidence.price <= 0.0 || anchorTicks <= 0)
         return false;

      if(!Transition(dir, recovery_ARMED, now, "configured DCA threshold confirmed"))
         return false;

      m_cycle[idx].armed                 = true;
      m_cycle[idx].armedDcaCount         = dcaCount;
      m_cycle[idx].anchorDeal            = evidence.deal;
      m_cycle[idx].anchorPosition        = evidence.position;
      m_cycle[idx].anchorPrice           = evidence.price;
      m_cycle[idx].anchorTicks           = anchorTicks;
      m_cycle[idx].anchorTime            = evidence.time;
      m_cycle[idx].anchorEvidenceWaitLogged = false;
      return true;
   }

   bool MarkShadowHedgeDecision(const eRecoveryCoreDirection dir,
                                const long targetUnits,
                                const double triggerPrice,
                                const datetime now)
   {
      int idx = Index(dir);
      if(!m_cycle[idx].armed || m_cycle[idx].state != recovery_ARMED ||
         m_cycle[idx].shadowDecisionLatched || targetUnits <= 0)
         return false;

      m_cycle[idx].shadowDecision        = recovery_SHADOW_WOULD_OPEN_HEDGE;
      m_cycle[idx].shadowDecisionLatched = true;
      m_cycle[idx].shadowTargetUnits     = targetUnits;
      m_cycle[idx].shadowTriggerPrice    = triggerPrice;
      m_cycle[idx].shadowDecisionAt      = now;
      return true;
   }

   bool AnchorEvidenceWaitLogged(const eRecoveryCoreDirection dir) const
   {
      return m_cycle[Index(dir)].anchorEvidenceWaitLogged;
   }

   void MarkAnchorEvidenceWaitLogged(const eRecoveryCoreDirection dir)
   {
      m_cycle[Index(dir)].anchorEvidenceWaitLogged = true;
   }

   int AuditStoredCount() const
   {
      return m_auditTotal < BD_RECOVERY_TRANSITION_AUDIT_CAP ?
             m_auditTotal : BD_RECOVERY_TRANSITION_AUDIT_CAP;
   }

   int AuditTotalCount() const { return m_auditTotal; }
};

#endif // BD_RECOVERY_REGISTRY_MQH
