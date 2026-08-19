//+------------------------------------------------------------------+
//| RecoveryArcsTypes.mqh — T16 ARCS layer/cycle state model         |
//| One direction may own N LOCKED layers + at most one ACTIVE layer.|
//+------------------------------------------------------------------+
#ifndef BD_RECOVERY_ARCS_TYPES_MQH
#define BD_RECOVERY_ARCS_TYPES_MQH

#include "RecoveryT16Config.mqh"

#define BD_ARCS_MAX_LAYERS 16

enum eArcsLayerState
{
   ARCS_LAYER_EMPTY = 0,
   ARCS_LAYER_BUILDING,
   ARCS_LAYER_ACTIVE,
   ARCS_LAYER_TP_PENDING,
   ARCS_LAYER_LOCK_PENDING,
   ARCS_LAYER_LOCKED,
   ARCS_LAYER_GLOBAL_PROTECTED,
   ARCS_LAYER_CLOSED
};

enum eArcsPhase
{
   ARCS_IDLE = 0,
   ARCS_ARMED,
   ARCS_BUILDING,
   ARCS_ACTIVE,
   ARCS_TP_PENDING,
   ARCS_CORE_FUNDING,
   ARCS_LOCK_PENDING,
   ARCS_LOCKED,
   ARCS_GLOBAL_PROTECT,
   ARCS_GLOBAL_ACTIVE,
   ARCS_GLOBAL_CLOSING,
   ARCS_TRANSITION,
   ARCS_REVERSAL_HOLD,
   ARCS_RECONCILE
};

struct SArcsLayer
{
   bool            used;
   int             generation;
   int             bundleId;
   eArcsLayerState state;
   long            targetUnits;
   long            openedUnits;
   long            remainingUnits;
   long            tpBaselineUnits;
   long            tpTargetCloseUnits;
   long            tpObservedCloseUnits;
   long            fundingClosedUnits;
   double          weightedEntry;
   double          netBE;
   double          tpTriggerPrice;
   double          lockTargetPrice;
   bool            virtualSlArmed;
   double          virtualSlPrice;
   double          realizedFundingCash;
   double          realizedOtherCash;
};

struct SArcsDirection
{
   eArcsPhase phase;
   bool       armed;
   ulong      anchorPosition;
   double     anchorPrice;
   long       anchorTicks;
   datetime   anchorTime;
   int        generationCount;
   int        activeLayer;
   double     hedgeFundingCash;
   double     coreLossSpent;
   double     availableCredit;
   bool       globalSlArmed;
   double     globalSlPrice;
   double     transitionReferencePrice;
   long       lastObservedCoreUnits;
   long       lastObservedHedgeUnits;
   ulong      lastDealTicket;
   long       lastDealTimeMsc;
   bool       reconcileRequired;
};

struct SArcsExternalPending
{
   bool             active;
   eExecCommandType commandType;
   long             ownerMagic;
   ulong            ticket;
   long             targetUnits;
   long             observedUnitsBefore;
   double           targetPrice;
   datetime         startedAt;
};

void Recovery_ArcsLayerReset(SArcsLayer &l)
{
   ZeroMemory(l);
   l.state = ARCS_LAYER_EMPTY;
}

void Recovery_ArcsDirectionReset(SArcsDirection &d)
{
   ZeroMemory(d);
   d.phase = ARCS_IDLE;
   d.activeLayer = -1;
}

void Recovery_ArcsPendingReset(SArcsExternalPending &p)
{
   ZeroMemory(p);
   p.commandType = EXEC_CMD_LEGACY;
}

void Recovery_ArcsRecomputeCredit(SArcsDirection &d)
{
   double positiveFunding = d.hedgeFundingCash > 0.0 ? d.hedgeFundingCash : 0.0;
   double raw = positiveFunding - d.coreLossSpent;
   d.availableCredit = raw > 0.0 ? raw : 0.0;
}

string Recovery_ArcsPhaseName(const eArcsPhase p)
{
   switch(p)
   {
      case ARCS_IDLE:             return "IDLE";
      case ARCS_ARMED:            return "ARMED";
      case ARCS_BUILDING:         return "BUILDING";
      case ARCS_ACTIVE:           return "ACTIVE";
      case ARCS_TP_PENDING:       return "TP_PENDING";
      case ARCS_CORE_FUNDING:     return "CORE_FUNDING";
      case ARCS_LOCK_PENDING:     return "LOCK_PENDING";
      case ARCS_LOCKED:           return "LOCKED";
      case ARCS_GLOBAL_PROTECT:   return "GLOBAL_PROTECT";
      case ARCS_GLOBAL_ACTIVE:    return "GLOBAL_ACTIVE";
      case ARCS_GLOBAL_CLOSING:   return "GLOBAL_CLOSING";
      case ARCS_TRANSITION:       return "TRANSITION";
      case ARCS_REVERSAL_HOLD:    return "REVERSAL_HOLD";
      case ARCS_RECONCILE:        return "RECONCILE";
   }
   return "UNKNOWN";
}

eRecoveryState Recovery_ArcsPublicState(const eArcsPhase p)
{
   switch(p)
   {
      case ARCS_IDLE:           return recovery_CORE_ONLY;
      case ARCS_ARMED:          return recovery_ARMED;
      case ARCS_BUILDING:       return recovery_HEDGE_BUILDING;
      case ARCS_ACTIVE:         return recovery_HEDGE_ACTIVE;
      case ARCS_TP_PENDING:     return recovery_HEDGE_TP_PENDING;
      case ARCS_CORE_FUNDING:   return recovery_CORE_CLOSE_PENDING;
      case ARCS_LOCK_PENDING:   return recovery_HEDGE_LOCK_PENDING;
      case ARCS_LOCKED:         return recovery_HEDGE_LOCKED;
      case ARCS_GLOBAL_PROTECT:
      case ARCS_GLOBAL_ACTIVE:  return recovery_HEDGE_LOCKED;
      case ARCS_GLOBAL_CLOSING: return recovery_GLOBAL_STOP;
      case ARCS_TRANSITION:     return recovery_PAUSE_SOFT;
      case ARCS_REVERSAL_HOLD:  return recovery_PAUSE_SOFT;
      case ARCS_RECONCILE:      return recovery_RECONCILE_REQUIRED;
   }
   return recovery_RECONCILE_REQUIRED;
}

int Recovery_ArcsCommentFieldInt(const string comment, const string key)
{
   int p = StringFind(comment, key);
   if(p < 0) return -1;
   int start = p + StringLen(key);
   int stop = StringFind(comment, "|", start);
   string token = stop < 0 ? StringSubstr(comment, start)
                           : StringSubstr(comment, start, stop - start);
   if(token == "") return -1;
   return (int)StringToInteger(token);
}

int Recovery_ArcsGenerationFromComment(const string comment)
{
   if(StringFind(comment, "BDR|C=") != 0) return -1;
   return Recovery_ArcsCommentFieldInt(comment, "|G=");
}

int Recovery_ArcsCycleFromComment(const string comment)
{
   if(StringFind(comment, "BDR|C=") != 0) return -1;
   return Recovery_ArcsCommentFieldInt(comment, "BDR|C=");
}

bool Recovery_ArcsLayerStateHasExposure(const eArcsLayerState s)
{
   return s == ARCS_LAYER_BUILDING || s == ARCS_LAYER_ACTIVE ||
          s == ARCS_LAYER_TP_PENDING || s == ARCS_LAYER_LOCK_PENDING ||
          s == ARCS_LAYER_LOCKED || s == ARCS_LAYER_GLOBAL_PROTECTED;
}

bool Recovery_ArcsPhaseMutating(const eArcsPhase p)
{
   return p == ARCS_BUILDING || p == ARCS_TP_PENDING ||
          p == ARCS_CORE_FUNDING || p == ARCS_LOCK_PENDING ||
          p == ARCS_GLOBAL_PROTECT || p == ARCS_GLOBAL_CLOSING;
}

#endif // BD_RECOVERY_ARCS_TYPES_MQH
