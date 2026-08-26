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

// Shared side identifiers are a cross-module primitive. They live here rather
// than in EntryFilters so ExecutionLayer/Strategy/tests can depend on them
// without importing filter/news modules. Values intentionally remain 0/1.
#define BD_DIR_BUY  0
#define BD_DIR_SELL 1

struct PositionInfo
{
   ulong    ticket;
   int      type;
   double   openPrice;
   double   lots;
   double   profit;
   double   tp;
   double   sl;
   datetime openTime;
};

struct BasketSide
{
   int          count;
   double       totalLots;
   double       totalProfit;
   double       breakeven;
   double       tpLevel;
   double       slLevel;
   double       trailLevel;
   bool         trailArmed;
   double       extremePrice;
   double       swapSum;
   PositionInfo pos[];
};

struct EAContext
{
   double   ask;
   double   bid;
   double   point;
   int      digits;
   int      spreadPoints;
   datetime now;
   datetime barTime;
   bool     newsAllowsNew;
   bool     signalBuy;
   bool     signalSell;
};

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
   ulong   ticket;
   double  sl;
   double  tp;
};

// T17: Pyramid dùng owner-aware execution journal riêng để timeout/connection
// không tạo duplicate add. Legacy Core/DCA và Recovery giữ nguyên semantic.
enum eExecCommandType
{
   EXEC_CMD_LEGACY = 0,
   EXEC_CMD_RECOVERY_OPEN,
   EXEC_CMD_RECOVERY_CLOSE,
   EXEC_CMD_RECOVERY_MODIFY,
   EXEC_CMD_CORE_PYRAMID_OPEN,
   EXEC_CMD_CORE_PYRAMID_CLOSE
};

enum eExecReconcilePolicy
{
   EXEC_RECONCILE_LEGACY_RELEASE = 0,
   EXEC_RECONCILE_FAIL_CLOSED
};

struct SExecRequestMeta
{
   long                 ownerMagic;
   int                  cycleKey;
   eExecCommandType     commandType;
   eExecReconcilePolicy reconcilePolicy;
};

// T17.11: non-persisted submission outcome used only by Core/DCA admission.
// This is deliberately separate from the persisted Recovery state enums.
enum eExecSubmitDisposition
{
   EXEC_SUBMIT_REJECTED = 0,
   EXEC_SUBMIT_ACCEPTED,
   EXEC_SUBMIT_TRANSIENT,
   EXEC_SUBMIT_CAPACITY_BLOCKED
};

struct SExecSubmitOutcome
{
   eExecSubmitDisposition disposition;
   uint                   retcode;
   double                 normalizedVolume;
   double                 requiredMargin;
   double                 freeMargin;
};

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

struct PendingRequest
{
   uint     requestId;
   ulong    ticket;
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

enum eExitKind { EXIT_NONE=0, EXIT_TP, EXIT_SL, EXIT_TRAIL, EXIT_OVERLAP };
struct ExitDecision
{
   eExitKind kind;
   int       direction;
   ulong     pairFirst;
   ulong     pairLast;
};

interface ISignal      { void Compute(EAContext &ctx); };
interface IEntryFilter { bool Allow(const EAContext &ctx, const int dir); };
interface ILotSizer    { double FirstLot(void); double NextLot(const BasketSide &side); };

#endif // BD_TYPES_MQH