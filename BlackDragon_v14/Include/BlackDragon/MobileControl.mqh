//+------------------------------------------------------------------+
//| MobileControl.mqh — BlackDragon v14.5.0                          |
//| Purpose   : FE-404 (CCBSN manual): remote control via pending    |
//|             orders at special prices, placed from MT5 mobile.    |
//|             Detect -> execute command -> DELETE the pending.     |
//| Mapping (Chu nha's build order 26/07/2026):                      |
//|   Buy Stop  999999 -> STOP ALL  (Cfg.RemoteStop = true: blocks   |
//|                       every AUTOMATED open — new series + DCA;   |
//|                       exits/management keep running)             |
//|   Buy Stop  666666 -> RESUME    (clears RemoteStop AND both      |
//|                       Pause flags — full "hoat dong binh thuong")|
//|   Buy Stop  888888 -> New Cycle OFF   (Cfg.NewCycle = false)     |
//|   Sell Limit 888888 -> New Cycle ON   (Cfg.NewCycle = true)      |
//|   Buy Stop  555555 -> STOP BUY  (Cfg.PauseBuy = true — chan moi  |
//|                       lenh Buy ke ca DCA)                        |
//|   Sell Limit 555555 -> STOP SELL (Cfg.PauseSell = true)          |
//| Invariants: Scan chi DOC order pool; lenh xoa di qua             |
//|             ExecutionLayer.DeleteOrder (quy tac 4). Volume cua   |
//|             lenh cho bi bo qua (dung nhu manual). Chi xet lenh   |
//|             cho DUNG SYMBOL chart nay; khong quan tam magic      |
//|             (nguoi dung dat tay tu mobile -> magic 0).           |
//| Notes     : Commands are idempotent — a failed delete self-heals |
//|             (re-detected + re-applied next timer scan). Flags    |
//|             persist across restart (Persistence, live only).     |
//| BD-R5     : Scan() reports only real flag TRANSITIONS. Before    |
//|             v14.7.2 it returned true on every scan while an      |
//|             undeletable pending sat in the pool, so OnTimer      |
//|             rewrote the state file twice a second and spammed    |
//|             the journal.                                        |
//| Depends on: Config.mqh, Types.mqh, Logger.mqh, ExecutionLayer    |
//+------------------------------------------------------------------+
#ifndef BD_MOBILECONTROL_MQH
#define BD_MOBILECONTROL_MQH
#include "Types.mqh"
#include "Logger.mqh"
#include "ExecutionLayer.mqh"

enum eMcCommand
{
   MC_NONE = 0,
   MC_STOP_ALL,     // Buy Stop  999999
   MC_RESUME,       // Buy Stop  666666
   MC_CYCLE_OFF,    // Buy Stop  888888
   MC_CYCLE_ON,     // Sell Limit 888888
   MC_STOP_BUY,     // Buy Stop  555555
   MC_STOP_SELL     // Sell Limit 555555
};

//--- PURE: (order type, price) -> command. Tolerance 0.5 — the special
//    prices are integers far outside any real quote, and mobile-entered
//    prices are normalized to symbol digits.
eMcCommand MC_Command(const int orderType, const double price)
{
   bool bs = (orderType == ORDER_TYPE_BUY_STOP);
   bool sl = (orderType == ORDER_TYPE_SELL_LIMIT);
   if(!bs && !sl) return MC_NONE;
   if(MathAbs(price - 999999.0) < 0.5) return bs ? MC_STOP_ALL  : MC_NONE;
   if(MathAbs(price - 666666.0) < 0.5) return bs ? MC_RESUME    : MC_NONE;
   if(MathAbs(price - 888888.0) < 0.5) return bs ? MC_CYCLE_OFF : MC_CYCLE_ON;
   if(MathAbs(price - 555555.0) < 0.5) return bs ? MC_STOP_BUY  : MC_STOP_SELL;
   return MC_NONE;
}

//--- PURE: apply a command to the runtime flags. Returns true when any
//    flag actually changed (caller persists the transition).
bool MC_Apply(const eMcCommand cmd, bool &remoteStop, bool &pauseBuy, bool &pauseSell, bool &newCycle)
{
   bool r = remoteStop, pb = pauseBuy, ps = pauseSell, nc = newCycle;
   switch(cmd)
   {
      case MC_STOP_ALL:  remoteStop = true;  break;
      case MC_RESUME:    remoteStop = false; pauseBuy = false; pauseSell = false; break;
      case MC_CYCLE_OFF: newCycle = false; break;
      case MC_CYCLE_ON:  newCycle = true;  break;
      case MC_STOP_BUY:  pauseBuy = true;  break;
      case MC_STOP_SELL: pauseSell = true; break;
      default: return false;
   }
   return r != remoteStop || pb != pauseBuy || ps != pauseSell || nc != newCycle;
}

string MC_Name(const eMcCommand cmd)
{
   switch(cmd)
   {
      case MC_STOP_ALL:  return "STOP ALL (999999)";
      case MC_RESUME:    return "RESUME (666666)";
      case MC_CYCLE_OFF: return "New Cycle OFF (888888)";
      case MC_CYCLE_ON:  return "New Cycle ON (888888)";
      case MC_STOP_BUY:  return "STOP BUY (555555)";
      case MC_STOP_SELL: return "STOP SELL (555555)";
   }
   return "?";
}

class CMobileControl
{
private:
   datetime m_nextDeleteTry;   // BD-R5: backoff after a failed pending delete

public:
   CMobileControl() : m_nextDeleteTry(0) {}

   //--- Call from OnTimer (500ms). Returns true ONLY when a runtime flag
   //    actually changed, so the caller persists only on transitions instead
   //    of twice per second (BD-R5). The command itself
   //    is still re-applied every scan — MC_Apply is idempotent — so an
   //    undeletable pending keeps enforcing its state without side effects.
   bool Scan(CExecutionLayer *exec)
   {
      bool changedAny = false;
      datetime now = TimeCurrent();
      for(int i = OrdersTotal() - 1; i >= 0; i--)
      {
         ulong tic = OrderGetTicket(i);
         if(tic == 0) continue;
         if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
         eMcCommand cmd = MC_Command((int)OrderGetInteger(ORDER_TYPE),
                                     OrderGetDouble(ORDER_PRICE_OPEN));
         if(cmd == MC_NONE) continue;
         if(MC_Apply(cmd, Cfg.RemoteStop, Cfg.PauseBuy, Cfg.PauseSell, Cfg.NewCycle))
         {
            Log_Info("Mobile", MC_Name(cmd) + " executed (pending #" + (string)tic + ")");
            changedAny = true;
         }
         if(now < m_nextDeleteTry) continue;   // still backing off from a failed delete
         if(!exec.DeleteOrder(tic))
         {
            m_nextDeleteTry = now + BD_MC_DELETE_RETRY_SEC;
            Log_Warn("Mobile", "mcdel", "cannot delete pending #" + (string)tic +
                     " — retrying in " + (string)BD_MC_DELETE_RETRY_SEC +
                     "s (command already applied)");
         }
      }
      return changedAny;
   }
};
#endif // BD_MOBILECONTROL_MQH
