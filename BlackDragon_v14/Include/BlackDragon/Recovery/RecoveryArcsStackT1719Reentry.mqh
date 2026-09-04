//+------------------------------------------------------------------+
//| RecoveryArcsStackT1719Reentry.mqh — terminal positive-SL rearm  |
//| Separate durable outer FSM over the verified T17.8 ARCS ladder. |
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_STACK_T1719_REENTRY_MQH
#define BD_RECOVERY_ARCS_STACK_T1719_REENTRY_MQH

#include "RecoveryArcsStackT177HedgeLadder.mqh"
#include "RecoveryT1719ReentryPersistence.mqh"

struct SRecoveryT1719CloseProbe
{
   bool recoveryOwned;
   bool protectiveCandidate;
   bool exactProtective;
   eRecoveryCoreDirection dir;
   int generation;
   double targetPrice;
   double fillPrice;
   ulong deal;
   long dealTimeMsc;
};

class CRecoveryArcsStackT1719 : public CRecoveryArcsStackT178
{
private:
   CRecoveryT1719ReentryPersistence m_reentryPersistence;
   SRecoveryReentryStateT1719 m_reentry[2];
   bool m_reentryReady;
   bool m_reentryBlocked;
   bool m_reentryMissing;
   long m_reentrySaveSequence;

   int ReentryIdxT1719(const eRecoveryCoreDirection dir) const
   {
      return dir == recovery_CORE_BUY ? 0 : 1;
   }

   eRecoveryCoreDirection ReentryDirT1719(const int index) const
   {
      return index == 0 ? recovery_CORE_BUY : recovery_CORE_SELL;
   }

   bool SaveReentryT1719(string &why)
   {
      why = "";
      if(RecoveryMode_ != recovery_ACTIVE) return true;
      if(m_reentryBlocked)
      {
         why = "T17.19 re-entry persistence đang fail-closed";
         return false;
      }
      if(!m_reentryPersistence.Save(m_reentrySaveSequence + 1,
                                    m_reentry[0], m_reentry[1], why))
      {
         m_reentryReady = false;
         m_reentryBlocked = true;
         return false;
      }
      m_reentrySaveSequence++;
      return true;
   }

   void FailReentryT1719(const eRecoveryCoreDirection dir,
                         const string reason)
   {
      m_reentryReady = false;
      m_reentryBlocked = true;
      LatchReconcile(dir, "T17.19 re-entry: " + reason);
      string ignored = "";
      Save(ignored);
      Log_Error("Recovery", "T17.19 re-entry fail-closed: " + reason);
   }

   void ClearReentryDirectionT1719(const eRecoveryCoreDirection dir)
   {
      Recovery_T1719ResetState(m_reentry[ReentryIdxT1719(dir)]);
   }

   bool RecoveryPositionIdentityT1719(const ulong positionId,
                                      long &ownerMagic,
                                      eRecoveryCoreDirection &dir,
                                      int &generation,
                                      string &openingComment,
                                      long &openingTimeMsc) const
   {
      ownerMagic = 0;
      dir = recovery_CORE_BUY;
      generation = -1;
      openingComment = "";
      openingTimeMsc = 0;
      if(positionId == 0 || !HistorySelectByPosition(positionId)) return false;

      ulong oldest = 0;
      long oldestMsc = 0;
      long openingType = -1;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
            continue;
         long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
         long tmsc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
         if(oldest == 0 || tmsc < oldestMsc ||
            (tmsc == oldestMsc && deal < oldest))
         {
            oldest = deal;
            oldestMsc = tmsc;
            ownerMagic = HistoryDealGetInteger(deal, DEAL_MAGIC);
            openingType = HistoryDealGetInteger(deal, DEAL_TYPE);
            openingComment = HistoryDealGetString(deal, DEAL_COMMENT);
         }
      }
      if(oldest == 0 || ownerMagic != (long)RecoveryMagic_) return false;
      generation = Recovery_ArcsGenerationFromComment(openingComment);
      if(generation < 1) return false;
      if(openingType == DEAL_TYPE_SELL) dir = recovery_CORE_BUY;
      else if(openingType == DEAL_TYPE_BUY) dir = recovery_CORE_SELL;
      else return false;
      openingTimeMsc = oldestMsc;
      return true;
   }

   bool SelectCloseDealT1719(const ulong deal, ulong &positionId) const
   {
      positionId = 0;
      if(deal == 0 || !HistoryDealSelect(deal)) return false;
      long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return false;
      positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      return positionId != 0;
   }

   bool OpeningIdentityMatchesCycleT1719(
      const long owner,
      const eRecoveryCoreDirection dir,
      const string openingComment,
      const long openingTimeMsc) const
   {
      if(owner != (long)RecoveryMagic_ || openingTimeMsc <= 0) return false;
      string prefix = "BDR|C=" + (string)Recovery_CycleKey(dir) + "|";
      return StringFind(openingComment, prefix) == 0;
   }

   bool ProtectiveLayerStateT1719(const eArcsLayerState state) const
   {
      return state == ARCS_LAYER_LOCK_PENDING ||
             state == ARCS_LAYER_PROTECTIVE_CLOSE_PENDING ||
             state == ARCS_LAYER_LOCKED ||
             state == ARCS_LAYER_GLOBAL_PROTECTED ||
             state == ARCS_LAYER_CLOSED;
   }

   double ProtectiveTargetT1719(const int directionIndex,
                                const SArcsLayer &layer) const
   {
      if(m_dir[directionIndex].globalSlArmed &&
         m_dir[directionIndex].globalSlPrice > 0.0)
         return m_dir[directionIndex].globalSlPrice;
      if(HedgeSLMode_ == SL_VIRTUAL && layer.virtualSlArmed &&
         layer.virtualSlPrice > 0.0)
         return layer.virtualSlPrice;
      return layer.lockTargetPrice;
   }

   bool ProtectiveCandidateT1719(const SArcsLayer &layer,
                                  const double target,
                                  const long reason) const
   {
      if(!ProtectiveLayerStateT1719(layer.state) || target <= 0.0)
         return false;
      if(HedgeSLMode_ == SL_BROKER) return reason == DEAL_REASON_SL;
      return HedgeSLMode_ == SL_VIRTUAL && reason == DEAL_REASON_EXPERT &&
             layer.virtualSlArmed;
   }

   bool EvaluateExactProtectiveT1719(const ulong deal,
                                     const SArcsLayer &layer,
                                     const double target,
                                     const double programmedSl,
                                     SRecoveryT1719CloseProbe &out)
   {
      if(HedgeSLMode_ == SL_BROKER)
      {
         out.exactProtective = ExpectedBrokerSlDeal(deal);
         if(out.exactProtective) out.targetPrice = programmedSl;
         return out.exactProtective;
      }
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * point;
      double fillTolerance = MathMax(25.0 * m_tickSize,
                                     2.0 * spread + 2.0 * m_tickSize);
      out.exactProtective = layer.virtualSlArmed && target > 0.0 &&
                            out.fillPrice > 0.0 &&
                            MathAbs(out.fillPrice - target) <=
                               fillTolerance + 1e-12;
      if(out.exactProtective) out.targetPrice = target;
      return out.exactProtective;
   }

   bool ExpectedProtectiveCloseT1719(const ulong deal,
                                      SRecoveryT1719CloseProbe &out)
   {
      ZeroMemory(out);
      out.deal = deal;
      ulong positionId = 0;
      if(!SelectCloseDealT1719(deal, positionId)) return false;
      long owner = 0;
      string openingComment = "";
      long openingMsc = 0;
      if(!RecoveryPositionIdentityT1719(positionId, owner, out.dir,
                                        out.generation, openingComment,
                                        openingMsc))
         return false;
      if(!OpeningIdentityMatchesCycleT1719(owner, out.dir, openingComment,
                                           openingMsc))
         return false;
      out.recoveryOwned = true;
      if(!HistoryDealSelect(deal)) return false;

      int di = ReentryIdxT1719(out.dir);
      int li = FindLayerByGeneration(out.dir, out.generation);
      if(li < 0) return true;
      SArcsLayer layer;
      GetLayer(out.dir, li, layer);
      long reason = HistoryDealGetInteger(deal, DEAL_REASON);
      double programmedSl = HistoryDealGetDouble(deal, DEAL_SL);
      out.fillPrice = HistoryDealGetDouble(deal, DEAL_PRICE);
      out.dealTimeMsc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
      double target = ProtectiveTargetT1719(di, layer);
      out.protectiveCandidate = layer.used &&
         ProtectiveCandidateT1719(layer, target, reason);
      if(!out.protectiveCandidate) return true;
      EvaluateExactProtectiveT1719(deal, layer, target, programmedSl, out);
      return true;
   }

   long FindCycleStartT1719(const eRecoveryCoreDirection dir) const
   {
      int di = ReentryIdxT1719(dir);
      datetime from = m_dir[di].anchorTime > 2 ? m_dir[di].anchorTime - 2 : 0;
      if(!HistorySelect(from, TimeCurrent())) return 0;
      long wanted = dir == recovery_CORE_BUY ? DEAL_TYPE_SELL : DEAL_TYPE_BUY;
      string prefix = "BDR|C=" + (string)Recovery_CycleKey(dir) + "|";
      long oldestMsc = 0;
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol ||
            HistoryDealGetInteger(deal, DEAL_MAGIC) != (long)RecoveryMagic_ ||
            HistoryDealGetInteger(deal, DEAL_TYPE) != wanted)
            continue;
         long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_IN && entry != DEAL_ENTRY_INOUT) continue;
         if(StringFind(HistoryDealGetString(deal, DEAL_COMMENT), prefix) != 0)
            continue;
         long tmsc = HistoryDealGetInteger(deal, DEAL_TIME_MSC);
         if(tmsc > 0 && (oldestMsc == 0 || tmsc < oldestMsc)) oldestMsc = tmsc;
      }
      return oldestMsc;
   }

   bool AggregateChainCashT1719(const eRecoveryCoreDirection dir,
                                const long cycleStartTimeMsc,
                                double &cash,
                                string &why) const
   {
      cash = 0.0;
      why = "";
      if(cycleStartTimeMsc <= 0)
      {
         why = "thiếu cycle-start cursor để tính net cash";
         return false;
      }
      datetime from = (datetime)(cycleStartTimeMsc / 1000);
      if(from > 2) from -= 2;
      if(!HistorySelect(from, TimeCurrent()))
      {
         why = "không đọc được history để tính net cash T17.19";
         return false;
      }
      ulong closeDeals[];
      ArrayResize(closeDeals, 0);
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0 || HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
            continue;
         long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
         if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) continue;
         if(HistoryDealGetInteger(deal, DEAL_TIME_MSC) < cycleStartTimeMsc)
            continue;
         int n = ArraySize(closeDeals);
         ArrayResize(closeDeals, n + 1);
         closeDeals[n] = deal;
      }

      string prefix = "BDR|C=" + (string)Recovery_CycleKey(dir) + "|";
      int matched = 0;
      for(int i = 0; i < ArraySize(closeDeals); i++)
      {
         ulong deal = closeDeals[i];
         if(!HistoryDealSelect(deal)) continue;
         ulong positionId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
         long owner = 0;
         eRecoveryCoreDirection ownedDir = recovery_CORE_BUY;
         int generation = -1;
         string openingComment = "";
         long openingMsc = 0;
         if(!RecoveryPositionIdentityT1719(positionId, owner, ownedDir,
                                           generation, openingComment,
                                           openingMsc) ||
            ownedDir != dir || openingMsc < cycleStartTimeMsc ||
            StringFind(openingComment, prefix) != 0)
            continue;
         if(!HistoryDealSelect(deal)) continue;
         cash += Recovery_DealCashPure(HistoryDealGetDouble(deal, DEAL_PROFIT),
                                       HistoryDealGetDouble(deal, DEAL_SWAP),
                                       HistoryDealGetDouble(deal, DEAL_COMMISSION),
                                       HistoryDealGetDouble(deal, DEAL_FEE));
         matched++;
      }
      if(matched <= 0)
      {
         why = "không tìm thấy Recovery close deal trong cycle T17.19";
         return false;
      }
      return true;
   }

   bool AllTerminalLayersClosedT1719(const eRecoveryCoreDirection dir) const
   {
      for(int i = 0; i < BD_ARCS_MAX_LAYERS; i++)
      {
         SArcsLayer layer;
         GetLayer(dir, i, layer);
         if(!layer.used) continue;
         if(layer.remainingUnits > 0) return false;
      }
      return true;
   }

   bool BeginProtectiveCollectionT1719(const SRecoveryT1719CloseProbe &probe,
                                       string &why)
   {
      why = "";
      int di = ReentryIdxT1719(probe.dir);
      if(MaxRecoveryReentryCycles_ <= 0 ||
         m_dir[di].generationCount < MaxHedgeGenerations_ ||
         !probe.protectiveCandidate)
         return true;

      SRecoveryReentryStateT1719 state = m_reentry[di];
      if(state.phase != RECOVERY_REENTRY_COLLECTING)
      {
         int completed = state.completedCycles;
         ulong campaignAnchor = state.campaignAnchorPosition;
         datetime campaignTime = state.campaignAnchorTime;
         long cycleStarted = state.cycleStartedTimeMsc;
         Recovery_T1719ResetState(state);
         state.completedCycles = completed;
         state.campaignAnchorPosition = campaignAnchor != 0
                                        ? campaignAnchor : m_dir[di].anchorPosition;
         state.campaignAnchorTime = campaignTime > 0
                                    ? campaignTime : m_dir[di].anchorTime;
         state.cycleStartedTimeMsc = cycleStarted > 0
                                     ? cycleStarted : FindCycleStartT1719(probe.dir);
         state.phase = RECOVERY_REENTRY_COLLECTING;
         state.candidateAllExact = true;
      }
      if(!probe.exactProtective)
         state.candidateAllExact = false;
      else if(state.sourceDeal != probe.deal)
      {
         state.anchorPrice = probe.targetPrice;
         state.anchorTicks = Recovery_PriceToTicksPure(probe.targetPrice, m_tickSize);
         state.lastFillPrice = probe.fillPrice;
         state.sourceDeal = probe.deal;
         state.sourceDealTimeMsc = probe.dealTimeMsc;
         state.sourceGeneration = probe.generation;
      }
      state.candidateObservedAt = TimeCurrent();
      m_reentry[di] = state;
      return SaveReentryT1719(why);
   }

   bool FinalizeProtectiveCollectionT1719(const eRecoveryCoreDirection dir,
                                          const EAContext &ctx,
                                          string &why)
   {
      why = "";
      int di = ReentryIdxT1719(dir);
      SRecoveryReentryStateT1719 state = m_reentry[di];
      if(state.phase != RECOVERY_REENTRY_COLLECTING) return false;
      long core = Recovery_ArcsCoreUnits(dir, m_volumeStep);
      long hedge = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      if(core <= 0 && hedge <= 0)
      {
         ClearReentryDirectionT1719(dir);
         if(!SaveReentryT1719(why)) FailReentryT1719(dir, why);
         return true;
      }
      if(hedge != 0 || !AllTerminalLayersClosedT1719(dir) ||
         ctx.now <= state.candidateObservedAt)
         return false;

      double netCash = 0.0;
      if(!AggregateChainCashT1719(dir, state.cycleStartedTimeMsc,
                                  netCash, why))
      {
         FailReentryT1719(dir, why);
         return true;
      }
      state.sourceNetCash = netCash;
      bool positive = state.anchorTicks > 0 &&
         Recovery_T1719TerminalEligiblePure(state.candidateAllExact,
                                             m_dir[di].generationCount,
                                             MaxHedgeGenerations_,
                                             core, hedge, netCash, 1e-8,
                                             state.completedCycles,
                                             MaxRecoveryReentryCycles_);
      if(state.completedCycles >= MaxRecoveryReentryCycles_)
         state.phase = RECOVERY_REENTRY_EXHAUSTED;
      else if(positive)
         state.phase = RECOVERY_REENTRY_WAIT_RESET;
      else
         state.phase = RECOVERY_REENTRY_NONE;

      // Prevent the legacy Global-SL transition from racing the new outer
      // two-stage latch. This is broker-neutral and is persisted before the
      // T17.19 phase becomes externally visible.
      m_dir[di].phase = ARCS_REVERSAL_HOLD;
      m_dir[di].activeLayer = -1;
      m_dir[di].globalSlArmed = false;
      m_dirty = true;
      if(!Save(why))
      {
         FailReentryT1719(dir, "không persist được terminal hold: " + why);
         return true;
      }

      m_reentry[di] = state;
      if(!SaveReentryT1719(why))
      {
         FailReentryT1719(dir, why);
         return true;
      }
      Log_Info("Recovery", "T17.19 terminal " + Recovery_DirectionName(dir) +
               " net=" + DoubleToString(netCash, 2) +
               " anchor=" + DoubleToString(state.anchorPrice, _Digits) +
               " exact=" + (state.candidateAllExact ? "yes" : "NO") +
               " -> " + Recovery_T1719PhaseName(state.phase));
      return true;
   }

   bool BaseReentryCycleStartedT1719(const eRecoveryCoreDirection dir) const
   {
      int di = ReentryIdxT1719(dir);
      if(m_dir[di].activeLayer < 0 || m_dir[di].generationCount < 1)
         return false;
      eArcsPhase phase = m_dir[di].phase;
      return phase == ARCS_BUILDING || phase == ARCS_ACTIVE ||
             phase == ARCS_TP_PENDING || phase == ARCS_CORE_FUNDING ||
             phase == ARCS_LOCK_PENDING ||
             phase == ARCS_PROTECTIVE_CLOSE_WAIT ||
             phase == ARCS_LOCKED || phase == ARCS_GLOBAL_PROTECT ||
             phase == ARCS_GLOBAL_ACTIVE || phase == ARCS_GLOBAL_CLOSING;
   }

   bool AdoptStartedReentryT1719(const eRecoveryCoreDirection dir,
                                 string &why)
   {
      int di = ReentryIdxT1719(dir);
      SRecoveryReentryStateT1719 state = m_reentry[di];
      if(state.phase != RECOVERY_REENTRY_TRIGGER_PENDING ||
         !BaseReentryCycleStartedT1719(dir))
         return false;
      state.completedCycles++;
      state.phase = RECOVERY_REENTRY_IN_CYCLE;
      m_reentry[di] = state;
      if(!SaveReentryT1719(why))
      {
         FailReentryT1719(dir, why);
         return true;
      }
      Log_Info("Recovery", "T17.19 " + Recovery_DirectionName(dir) +
               " re-entry G1 durable | cycle=" +
               (string)state.completedCycles + "/" +
               (string)MaxRecoveryReentryCycles_);
      return true;
   }

   bool StartPendingReentryT1719(const eRecoveryCoreDirection dir,
                                 const EAContext &ctx,
                                 string &why)
   {
      why = "";
      int di = ReentryIdxT1719(dir);
      SRecoveryReentryStateT1719 state = m_reentry[di];
      if(state.phase != RECOVERY_REENTRY_TRIGGER_PENDING) return false;
      if(AdoptStartedReentryT1719(dir, why)) return true;
      if(Recovery_ArcsCoreUnits(dir, m_volumeStep) <= 0)
      {
         ClearReentryDirectionT1719(dir);
         if(!SaveReentryT1719(why)) FailReentryT1719(dir, why);
         return true;
      }
      if(Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep) > 0)
      {
         FailReentryT1719(dir, "TRIGGER_PENDING có Hedge không thuộc G1 đã persist");
         why = "unexpected Hedge during re-entry trigger";
         return true;
      }

      // TRIGGER_PENDING is already durable before this point. Persist the ARCS
      // reset separately, then start G1. A crash at either boundary resumes
      // from the exact pair of durable states without duplicating an order.
      if(m_dir[di].generationCount != 0 || m_dir[di].phase != ARCS_LOCKED)
      {
         m_dir[di].transitionReferencePrice = state.anchorPrice;
         ResetForReentry(dir);
         m_dir[di].generationCount=0;
         m_dir[di].transitionReferencePrice = state.anchorPrice;
         if(!Save(why))
         {
            FailReentryT1719(dir, "không persist được ARCS reset trước G1: " + why);
            return true;
         }
      }
      if(!StartGeneration(dir, ctx.now, why))
      {
         if(m_dir[di].phase == ARCS_RECONCILE || !m_ready)
            FailReentryT1719(dir, "không khởi tạo được G1: " + why);
         return true;
      }
      if(!Save(why))
      {
         FailReentryT1719(dir, "không persist được G1: " + why);
         return true;
      }
      return AdoptStartedReentryT1719(dir, why);
   }

   bool ValidateLoadedStateT1719(const eRecoveryCoreDirection dir,
                                 string &why) const
   {
      why = "";
      const SRecoveryReentryStateT1719 state =
         m_reentry[ReentryIdxT1719(dir)];
      if(!Recovery_T1719PhaseValidPure((int)state.phase) ||
         state.completedCycles < 0 ||
         state.completedCycles > MaxRecoveryReentryCycles_)
      {
         why = "phase/cycle-count T17.19 không hợp lệ";
         return false;
      }
      long core = Recovery_ArcsCoreUnits(dir, m_volumeStep);
      long hedge = Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep);
      if(state.phase == RECOVERY_REENTRY_WAIT_RESET ||
         state.phase == RECOVERY_REENTRY_ARMED ||
         state.phase == RECOVERY_REENTRY_TRIGGER_PENDING)
      {
         if(state.anchorTicks <= 0 || state.anchorPrice <= 0.0 ||
            !state.candidateAllExact || core <= 0 || hedge != 0 ||
            state.completedCycles >= MaxRecoveryReentryCycles_)
         {
            why = "WAIT/ARMED/TRIGGER T17.19 không khớp broker/Core/cap";
            return false;
         }
      }
      if(state.phase == RECOVERY_REENTRY_IN_CYCLE &&
         (state.completedCycles <= 0 || core <= 0))
      {
         why = "IN_CYCLE T17.19 thiếu Core hoặc cycle identity";
         return false;
      }
      if(state.phase == RECOVERY_REENTRY_EXHAUSTED &&
         (state.completedCycles < MaxRecoveryReentryCycles_ ||
          core <= 0 || hedge != 0))
      {
         why = "EXHAUSTED T17.19 không khớp cap/broker";
         return false;
      }
      return true;
   }

   bool ReconstructMissingReentryT1719(string &why)
   {
      for(int d = 0; d < 2; d++)
      {
         eRecoveryCoreDirection dir = ReentryDirT1719(d);
         if(m_dir[d].generationCount < MaxHedgeGenerations_ ||
            Recovery_ArcsCoreUnits(dir, m_volumeStep) <= 0 ||
            Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep) != 0 ||
            m_dir[d].lastDealTicket == 0)
            continue;
         SRecoveryT1719CloseProbe probe;
         if(!ExpectedProtectiveCloseT1719(m_dir[d].lastDealTicket, probe) ||
            !probe.protectiveCandidate)
            continue;
         if(!BeginProtectiveCollectionT1719(probe, why)) return false;
      }
      m_reentryMissing = false;
      return true;
   }

   bool ReconcileDirectionT1719(const eRecoveryCoreDirection dir,
                                string &why)
   {
      int di = ReentryIdxT1719(dir);
      bool terminalNoHedge =
         (m_reentry[di].phase == RECOVERY_REENTRY_IN_CYCLE ||
          (m_reentry[di].phase == RECOVERY_REENTRY_NONE &&
           m_reentry[di].sourceDeal == 0)) &&
         m_dir[di].generationCount >= MaxHedgeGenerations_ &&
         Recovery_ArcsCoreUnits(dir, m_volumeStep) > 0 &&
         Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep) == 0 &&
         m_dir[di].lastDealTicket != 0;
      if(terminalNoHedge)
      {
         SRecoveryT1719CloseProbe probe;
         if(!ExpectedProtectiveCloseT1719(m_dir[di].lastDealTicket, probe) ||
            !probe.protectiveCandidate || !probe.exactProtective)
         {
            why = "terminal no-Hedge restart thiếu exact positive-SL identity";
            FailReentryT1719(dir, why);
            return false;
         }
         if(!BeginProtectiveCollectionT1719(probe, why)) return false;
      }
      if(m_reentry[di].phase == RECOVERY_REENTRY_TRIGGER_PENDING &&
         BaseReentryCycleStartedT1719(dir))
      {
         if(!AdoptStartedReentryT1719(dir, why)) return false;
      }
      if(ValidateLoadedStateT1719(dir, why)) return true;
      FailReentryT1719(dir, why);
      return false;
   }

public:
   CRecoveryArcsStackT1719(void) : CRecoveryArcsStackT178()
   {
      Recovery_T1719ResetState(m_reentry[0]);
      Recovery_T1719ResetState(m_reentry[1]);
      m_reentryReady = false;
      m_reentryBlocked = false;
      m_reentryMissing = false;
      m_reentrySaveSequence = 0;
   }

   bool Init()
   {
      if(!CRecoveryArcsStackT178::Init()) return false;
      m_reentryPersistence.Init(_Symbol, AccountInfoInteger(ACCOUNT_LOGIN),
                                (long)Magic, (long)RecoveryMagic_);
      Recovery_T1719ResetState(m_reentry[0]);
      Recovery_T1719ResetState(m_reentry[1]);
      m_reentryReady = RecoveryMode_ != recovery_ACTIVE;
      m_reentryBlocked = false;
      m_reentryMissing = false;
      m_reentrySaveSequence = 0;
      if(RecoveryMode_ != recovery_ACTIVE) return true;
      if(MaxRecoveryReentryCycles_ == 0)
      {
         m_reentryMissing = true;
         return true;
      }

      SRecoveryReentryIdentityT1719 identity;
      string why = "";
      eRecoveryReentryPersistStatusT1719 status =
         m_reentryPersistence.Load(identity, m_reentry[0], m_reentry[1], why);
      if(status == RECOVERY_REENTRY_PERSIST_OK)
         m_reentrySaveSequence = identity.saveSequence;
      else if(status == RECOVERY_REENTRY_PERSIST_NOT_FOUND)
         m_reentryMissing = true;
      else
      {
         m_reentryBlocked = true;
         Log_Error("Recovery", "T17.19 re-entry persistence blocked: " + why);
      }
      return true;
   }

   bool StartupReconcile(CExecutionLayer &exec, string &why)
   {
      why = "";
      if(!CRecoveryArcsStackT178::StartupReconcile(exec, why)) return false;
      if(RecoveryMode_ != recovery_ACTIVE)
      {
         m_reentryReady = true;
         return true;
      }
      if(m_reentryBlocked)
      {
         why = "T17.19 re-entry persistence corrupt/mismatch";
         return false;
      }
      if(MaxRecoveryReentryCycles_ == 0)
      {
         ClearReentryDirectionT1719(recovery_CORE_BUY);
         ClearReentryDirectionT1719(recovery_CORE_SELL);
         m_reentryReady = true;
         m_reentryMissing = false;
         return SaveReentryT1719(why);
      }

      if(m_reentryMissing)
      {
         // Safe upgrade path: reconstruct only the exact last terminal
         // protective deal retained by the ARCS v4 cursor. Otherwise start
         // clean; never infer a trigger from price alone.
         if(!ReconstructMissingReentryT1719(why)) return false;
      }

      for(int d = 0; d < 2; d++)
      {
         eRecoveryCoreDirection dir = ReentryDirT1719(d);
         if(!ReconcileDirectionT1719(dir, why)) return false;
      }
      m_reentryReady = true;
      if(!SaveReentryT1719(why)) return false;
      Log_Info("Recovery", "T17.19 terminal re-entry persistence reconciled");
      return true;
   }

   bool ActiveReady() const
   {
      return CRecoveryArcsStackT178::ActiveReady() &&
             (RecoveryMode_ != recovery_ACTIVE || m_reentryReady);
   }

   void OnTick(const EAContext &ctx)
   {
      CRecoveryArcsStackT178::OnTick(ctx);
      if(RecoveryMode_ != recovery_ACTIVE || !m_reentryReady) return;
      bool changed = false;
      bool changedDir[2] = {false, false};
      for(int d = 0; d < 2; d++)
      {
         eRecoveryCoreDirection dir = ReentryDirT1719(d);
         if(Recovery_ArcsCoreUnits(dir, m_volumeStep) <= 0 &&
            Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep) <= 0 &&
            (m_reentry[d].phase != RECOVERY_REENTRY_NONE ||
             m_reentry[d].completedCycles != 0))
         {
            ClearReentryDirectionT1719(dir);
            changed = true;
            changedDir[d] = true;
         }
      }
      if(changed)
      {
         string why = "";
         if(!SaveReentryT1719(why))
         {
            for(int d = 0; d < 2; d++)
               if(changedDir[d]) FailReentryT1719(ReentryDirT1719(d), why);
         }
      }
   }

   void OnTradeTransaction(const MqlTradeTransaction &trans)
   {
      SRecoveryT1719CloseProbe probe;
      bool probed = false;
      if(m_reentryReady && MaxRecoveryReentryCycles_ > 0 &&
         trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal != 0 &&
         trans.symbol == _Symbol)
      {
         probed = ExpectedProtectiveCloseT1719(trans.deal, probe) &&
                  probe.recoveryOwned && probe.protectiveCandidate;
         if(probed)
         {
            string why = "";
            if(!BeginProtectiveCollectionT1719(probe, why))
               FailReentryT1719(probe.dir, why);
         }
      }
      CRecoveryArcsStackT178::OnTradeTransaction(trans);
   }

   bool Drive(CExecutionLayer &exec, const EAContext &ctx, string &why)
   {
      why = "";
      if(RecoveryMode_ != recovery_ACTIVE || !m_reentryReady)
         return CRecoveryArcsStackT178::Drive(exec, ctx, why);

      for(int d = 0; d < 2; d++)
      {
         eRecoveryCoreDirection dir = ReentryDirT1719(d);
         SRecoveryReentryStateT1719 state = m_reentry[d];
         if(state.phase == RECOVERY_REENTRY_COLLECTING)
         {
            if(Recovery_ArcsTotalHedgeUnits(dir,m_volumeStep)==0)
            {
               if(FinalizeProtectiveCollectionT1719(dir, ctx, why))
               {
                  if(m_reentry[d].phase == RECOVERY_REENTRY_WAIT_RESET) continue;
                  return true;
               }
               return true;
            }
            return CRecoveryArcsStackT178::Drive(exec, ctx, why);
         }
         if(state.phase == RECOVERY_REENTRY_WAIT_RESET)
         {
            long bidTicks = Recovery_PriceToTicksPure(ctx.bid, m_tickSize);
            long askTicks = Recovery_PriceToTicksPure(ctx.ask, m_tickSize);
            if(Recovery_T1719ResetHitPure(dir, state.anchorTicks,
                                          bidTicks, askTicks,
                                          m_reentryBufferTicks))
            {
               state.phase = RECOVERY_REENTRY_ARMED;
               m_reentry[d] = state;
               if(!SaveReentryT1719(why))
               {
                  FailReentryT1719(dir, why);
                  return true;
               }
               Log_Info("Recovery", "T17.19 " + Recovery_DirectionName(dir) +
                        " re-entry ARMED sau reset buffer; Core DCA vẫn khóa, Core Pyramid ADD theo settings");
            }
            why = "";
            continue;
         }
         if(state.phase == RECOVERY_REENTRY_ARMED)
         {
            long bidTicks = Recovery_PriceToTicksPure(ctx.bid, m_tickSize);
            long askTicks = Recovery_PriceToTicksPure(ctx.ask, m_tickSize);
            if(!Recovery_T1719ReturnHitPure(dir, state.anchorTicks,
                                            bidTicks, askTicks))
               continue;
            state.phase = RECOVERY_REENTRY_TRIGGER_PENDING;
            state.cycleStartedTimeMsc = (long)ctx.now * 1000;
            if(state.sourceDealTimeMsc + 1 > state.cycleStartedTimeMsc)
               state.cycleStartedTimeMsc = state.sourceDealTimeMsc + 1;
            m_reentry[d] = state;
            if(!SaveReentryT1719(why))
            {
               FailReentryT1719(dir, why);
               return true;
            }
            return StartPendingReentryT1719(dir, ctx, why);
         }
         if(state.phase == RECOVERY_REENTRY_TRIGGER_PENDING)
            return StartPendingReentryT1719(dir, ctx, why);
      }
      return CRecoveryArcsStackT178::Drive(exec, ctx, why);
   }

   bool FlushPersistence()
   {
      bool baseOk = CRecoveryArcsStackT178::FlushPersistence();
      if(RecoveryMode_ != recovery_ACTIVE || !m_reentryReady) return baseOk;
      return baseOk;
   }

   bool FinalizeConfirmedGlobalFlatten(CExecutionLayer &exec,
                                       const datetime now,
                                       string &why)
   {
      if(!CRecoveryArcsStackT178::FinalizeConfirmedGlobalFlatten(exec, now, why))
         return false;
      ClearReentryDirectionT1719(recovery_CORE_BUY);
      ClearReentryDirectionT1719(recovery_CORE_SELL);
      return SaveReentryT1719(why);
   }

   bool FinalizeConfirmedSideMutation(CExecutionLayer &exec,
                                      const eRecoveryCoreDirection dir,
                                      const datetime now,
                                      string &why)
   {
      if(!CRecoveryArcsStackT178::FinalizeConfirmedSideMutation(exec, dir, now, why))
         return false;
      if(Recovery_ArcsCoreUnits(dir, m_volumeStep) <= 0 &&
         Recovery_ArcsTotalHedgeUnits(dir, m_volumeStep) <= 0)
      {
         ClearReentryDirectionT1719(dir);
         return SaveReentryT1719(why);
      }
      return true;
   }

   bool T1719BlocksCoreDca(const eRecoveryCoreDirection dir) const
   {
      if(RecoveryMode_ != recovery_ACTIVE) return false;
      if(!m_reentryReady) return true;
      return Recovery_T1719BlocksCoreDcaPure(m_reentry[ReentryIdxT1719(dir)].phase);
   }

   bool T1719BlocksCorePyramidAdd(const eRecoveryCoreDirection dir) const
   {
      if(RecoveryMode_ != recovery_ACTIVE) return false;
      if(!m_reentryReady) return true;
      return Recovery_T1719BlocksCorePyramidAddPure(
         m_reentry[ReentryIdxT1719(dir)].phase);
   }

   bool T1719AllowsCorePyramidAdd(const eRecoveryCoreDirection dir) const
   {
      if(RecoveryMode_ != recovery_ACTIVE || !m_reentryReady) return false;
      return Recovery_T1719AllowsCorePyramidAddPure(
         m_reentry[ReentryIdxT1719(dir)].phase);
   }

   bool T1719AllowsCorePyramidPeel(const eRecoveryCoreDirection dir) const
   {
      if(RecoveryMode_ != recovery_ACTIVE || !m_reentryReady) return false;
      return Recovery_T1719AllowsCorePyramidPeelPure(
         m_reentry[ReentryIdxT1719(dir)].phase);
   }

   eRecoveryReentryPhaseT1719 T1719ReentryPhase(
      const eRecoveryCoreDirection dir) const
   {
      return m_reentry[ReentryIdxT1719(dir)].phase;
   }
};

#endif // BD_RECOVERY_ARCS_STACK_T1719_REENTRY_MQH
