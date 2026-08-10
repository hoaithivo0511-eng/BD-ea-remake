//+------------------------------------------------------------------+
//| Persistence.mqh — BlackDragon v14.0.0                            |
//| Purpose   : Save/restore panel-changeable runtime state across   |
//|             restarts (v13 .bin state file, fixed layout).        |
//| Invariants: Versioned header; unreadable file -> defaults, never |
//|             crash.                                               |
//| Depends on: Config.mqh, Logger.mqh                               |
//+------------------------------------------------------------------+
#ifndef BD_PERSISTENCE_MQH
#define BD_PERSISTENCE_MQH
#include "Config.mqh"
#include "Logger.mqh"

#define BD_STATE_MAGIC 0x42443136  // "BD16" (v14.7.2 BD-R4: +haltUntil; old BD15 files -> defaults once)

struct SPersistedState
{
   uint     magic;
   bool     pauseBuy;
   bool     pauseSell;
   bool     tradeBuy;
   bool     tradeSell;
   bool     newCycle;
   double   editLot;
   bool     remoteStop;   // FE-404 (v14.5)
   datetime haltUntil;    // BD-R4 (v14.7.2): daily SL/TP halt deadline
};

string Persist_FileName()
{
   return _Symbol + "_" + (string)Magic + BD_STATE_FILE_SUFFIX;
}

void Persist_Save()
{
   // AU-14-03: tester agent Files/ survives across passes -> a saved state
   // from pass N would override the inputs of pass N+1 and break golden-
   // baseline reproducibility. Live/demo behavior is unchanged.
   if(MQLInfoInteger(MQL_TESTER)) return;
   SPersistedState st;
   st.magic     = BD_STATE_MAGIC;
   st.pauseBuy  = Cfg.PauseBuy;
   st.pauseSell = Cfg.PauseSell;
   st.tradeBuy  = Cfg.TradeBuy;
   st.tradeSell = Cfg.TradeSell;
   st.newCycle  = Cfg.NewCycle;
   st.editLot   = Cfg.EditLot;
   st.remoteStop = Cfg.RemoteStop;   // FE-404
   st.haltUntil  = Cfg.HaltUntil;    // BD-R4: daily halt must survive restart
   int h = FileOpen(Persist_FileName(), FILE_WRITE | FILE_BIN);
   if(h == INVALID_HANDLE) { Log_Warn("Persist", "save", "cannot open state file"); return; }
   FileWriteStruct(h, st);
   FileClose(h);
}

void Persist_Load()
{
   if(MQLInfoInteger(MQL_TESTER)) return;   // AU-14-03: see Persist_Save
   if(!FileIsExist(Persist_FileName())) return;
   int h = FileOpen(Persist_FileName(), FILE_READ | FILE_BIN);
   if(h == INVALID_HANDLE) return;
   SPersistedState st;
   ZeroMemory(st);                          // BD-R4: short/legacy file must not leave stack garbage
   uint read = FileReadStruct(h, st);
   FileClose(h);
   if(read == 0 || st.magic != BD_STATE_MAGIC)
   {
      Log_Warn("Persist", "load", "state file invalid/old version — using defaults");
      return;
   }
   Cfg.PauseBuy  = st.pauseBuy;
   Cfg.PauseSell = st.pauseSell;
   Cfg.TradeBuy  = st.tradeBuy;
   Cfg.TradeSell = st.tradeSell;
   Cfg.NewCycle  = st.newCycle;
   Cfg.EditLot   = st.editLot;
   Cfg.RemoteStop = st.remoteStop;   // FE-404: mobile STOP ALL survives restart
   Cfg.HaltUntil  = st.haltUntil;    // BD-R4: daily halt survives restart
}
#endif // BD_PERSISTENCE_MQH
