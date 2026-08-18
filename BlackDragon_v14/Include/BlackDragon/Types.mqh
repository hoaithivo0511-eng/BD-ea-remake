//+------------------------------------------------------------------+
//| Types.mqh — BlackDragon v14.0.0                                  |
//| Purpose   : Shared structs + extension interfaces. No logic.     |
//| Invariants: Engines receive EAContext read-only; only            |
//|             BasketManager writes BasketState.                    |
//| Depends on: Config.mqh                                           |
//+------------------------------------------------------------------+
#ifndef BD_TYPES_MQH
#define BD_TYPES_MQH
#include "Config.mqh"

//--- One open position (replaces sInfoOrder; string comment dropped: C6)
struct PositionInfo
{
   ulong    ticket;
   int      type;        // POSITION_TYPE_BUY / _SELL
   double   openPrice;
   double   lots;
   double   profit;      // profit + swap (same as v13)
   double   tp;
   double   sl;
   datetime openTime;
};

//--- One direction of the hedge basket (owned by BasketManager)
struct BasketSide
{
   int          count;
   double       totalLots;
   double       totalProfit;   // sum(profit+swap)
   double       breakeven;     // NoLoss level (swap/commission adjusted)
   double       tpLevel;       // 0 = off
   double       slLevel;       // 0 = off
   double       trailLevel;
   bool         trailArmed;
   double       extremePrice;  // incremental max(buy)/min(sell) since last order (C4)
   double       swapSum;       // AU-14-01: refreshed per tick together with profit
   PositionInfo pos[];         // sorted oldest -> newest (fix #5)
};

//--- Per-tick context. Engines: READ ONLY.
struct EAContext
{
   double   ask;
   double   bid;
   double   point;
   int      digits;
   int      spreadPoints;
   datetime now;
   datetime barTime;       // iTime(_Symbol,0,0)
   bool     newsAllowsNew; // Flag_Mojno_New_Ord
   bool     signalBuy;     // Flag_Open_Buy
   bool     signalSell;    // Flag_Open_Sell
};

//--- What the strategy wants Execution to do
enum eIntent
{
   INTENT_NONE = 0,
   INTENT_OPEN_BUY,
   INTENT_OPEN_SELL,
   INTENT_CLOSE_TICKET,
   INTENT_MODIFY_SLTP
};
struct TradeIntent
{
   eIntent action;
   double  volume;
   ulong   ticket;   // for close/modify
   double  sl;
   double  tp;
};

//--- T2 execution ownership/reconciliation metadata ------------------------
// Legacy commands keep the historical bounded-release watchdog policy.
// Recovery commands can opt into fail-closed reconciliation without changing
// the timeout semantics of existing Core trading paths.
enum eExecCommandType
{
   EXEC_CMD_LEGACY = 0,
   EXEC_CMD_RECOVERY_OPEN,
   EXEC_CMD_RECOVERY_CLOSE,
   EXEC_CMD_RECOVERY_MODIFY
};

enum eExecReconcilePolicy
{
   EXEC_RECONCILE_LEGACY_RELEASE = 0,
   EXEC_RECONCILE_FAIL_CLOSED
};

struct SExecRequestMeta
{
   long                 ownerMagic;
   int                  cycleKey;       // 0 for legacy/non-cycle commands
   eExecCommandType     commandType;
   eExecReconcilePolicy reconcilePolicy;
};

//--- Async journal lifecycle (BD-002)
enum ePendingPhase
{
   PENDING_SENT = 0,
   PENDING_REQUEST_ACCEPTED
};
enum ePendingEvidence
{
   PENDING_EVIDENCE_NONE = 0,
   PENDING_EVIDENCE_REQUEST,
   PENDING_EVIDENCE_DEAL,
   PENDING_EVIDENCE_ORDER_DELETE,
   PENDING_EVIDENCE_RESULT_STATE
};

//--- Async journal entry (Nhom B + Recovery T2 metadata)
struct PendingRequest
{
   uint     requestId;
   ulong    ticket;      // position being closed/modified (0 for open)
   string   symbol;
   eIntent  action;
   ePendingPhase phase;
   double   volume;
   double   targetVolume;
   double   observedVolume;
   double   positionVolumeBefore;
   double   sl;
   double   tp;
   ulong    serverOrder;
   ulong    serverDeal;
   ulong    lastObservedDeal;
   uint     requestRetcode;
   int      positionCountBefore;
   datetime sentAt;
   int      retries;
   long     ownerMagic;
   int      cycleKey;
   eExecCommandType commandType;
   eExecReconcilePolicy reconcilePolicy;
   bool     reconcileRequired;
   bool     serverFinal;
   bool     orderDeleted;
   bool     active;
};

//--- Exit decision returned by IExitPolicy
enum eExitKind { EXIT_NONE=0, EXIT_TP, EXIT_SL, EXIT_TRAIL, EXIT_OVERLAP };
struct ExitDecision
{
   eExitKind kind;
   int       direction;      // 0 = buy basket, 1 = sell basket
   ulong     pairFirst;      // overlap only
   ulong     pairLast;       // overlap only
};

//--- Extension interfaces (P5 entry points) -------------------------
interface ISignal      { void Compute(EAContext &ctx); };
interface IEntryFilter { bool Allow(const EAContext &ctx, const int dir); };
interface ILotSizer    { double FirstLot(void); double NextLot(const BasketSide &side); };

#endif // BD_TYPES_MQH
