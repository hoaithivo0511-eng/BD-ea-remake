//+------------------------------------------------------------------+
//| EntryFilters.mqh — BlackDragon v14.8.0                           |
//| Purpose   : IEntryFilter chain: spread, pause, news, local-time. |
//|             Adding a filter = new class + register in OnInit.    |
//| Invariants: Filters only READ ctx; never place orders.           |
//| Depends on: Types.mqh, NewsCalendar.mqh                          |
//| [STRATEGY-BEHAVIOR] Spread semantics remain v13; v14.8 removes   |
//|                     the legacy server-hour filter entirely.      |
//+------------------------------------------------------------------+
#ifndef BD_ENTRYFILTERS_MQH
#define BD_ENTRYFILTERS_MQH
#include "Types.mqh"
#include "NewsCalendar.mqh"

// BD_DIR_BUY / BD_DIR_SELL are shared cross-module identifiers declared in
// Types.mqh. EntryFilters consumes them but no longer owns their definition.

//--- v13: MaxSpred, 0 disables ---------------------------------------
class CSpreadFilter : public IEntryFilter
{
public:
   bool Allow(const EAContext &ctx, const int dir)
   {
      if(MaxSpred == 0) return true;
      return MathMax(ctx.ask - ctx.bid, 0.0) <= Cfg.MaxSpreadPrice + 1e-12;
   }
};

//--- FE-404 Mobile Control directional pause + STOP ALL --------------
//    RemoteStop (Buy Stop 999999 from mobile) blocks every automated
//    open on both chains; management/exits keep running.
class CPauseFilter : public IEntryFilter
{
public:
   bool Allow(const EAContext &ctx, const int dir)
   {
      if(Cfg.RemoteStop) return false;                 // FE-404 (v14.5)
      if(dir == BD_DIR_BUY  && Cfg.PauseBuy)  return false;
      if(dir == BD_DIR_SELL && Cfg.PauseSell) return false;
      return true;
   }
};

//--- News pause (Nhom D) ---------------------------------------------
class CNewsFilter : public IEntryFilter
{
public:
   bool Allow(const EAContext &ctx, const int dir)
   {
      return ctx.newsAllowsNew;
   }
};

//--- BD-R9 (v14.7.2): hedge gating is a NEW-SERIES rule, not a DCA rule
//    v13 GET_INFO semantics: with hedge OFF the EA must not START a
//    series on one side while the opposite side is open. Applying the
//    SAME test to grid adds deadlocks BOTH sides as soon as two-sided
//    exposure exists: buy DCA waits for sell.count == 0 while sell DCA
//    waits for buy.count == 0, and neither side can shrink on its own.
//    Exits keep running, so the basket is frozen at its worst average
//    with no way to average down.
//    Two-sided exposure IS reachable with Flag_Use_hedge = false:
//      - flag_Hand_Ord = true counts manual magic-0 orders into both
//        sides (see Basket_OwnsMagic).
//    A grid add cannot CREATE opposite exposure — its own side is
//    already open and the opposite side exists either way — so it is
//    not what the no-hedge rule protects. Splitting the rule in two
//    also restores the invariant documented in the Strategy.mqh
//    header: "grid adds are gated by pause/news/one-per-bar/MinuteStop
//    only".

//--- PURE: may a NEW series be started on this side?
bool Hedge_AllowsNewSeries(const bool useHedge, const int oppositeCount)
{
   return useHedge || oppositeCount <= 0;
}

//--- PURE: may an ALREADY OPEN side add a grid (DCA) leg?
//    Flag_Use_hedge is deliberately NOT a parameter: the absence of the
//    hedge test here is the fix itself, not an accidental omission.
bool Hedge_AllowsGridAdd(const int ownCount)
{
   return ownCount > 0;
}

//--- FE-403 (v14.4): trading schedule by PC/LOCAL time (CCBSN manual) --
//    4 on/off windows in "HH:MM"; overnight windows (start > end) are
//    supported; [start, end) half-open. NOTE: in the Strategy Tester
//    TimeLocal() equals the modelled server time. Since v14.8 this is the
//    ONLY time-window system; Start_Hour/End_Hour were removed.

//--- PURE: "HH:MM" -> minutes since midnight. Tolerant to spaces and a
//    1-digit hour; minute must be exactly 2 digits; both numeric.
bool TL_ParseHHMM(const string s, int &minutes)
{
   minutes = -1;
   string p = s;
   StringReplace(p, " ", "");
   string parts[];
   if(StringSplit(p, ':', parts) != 2) return false;
   if(StringLen(parts[0]) < 1 || StringLen(parts[0]) > 2 || StringLen(parts[1]) != 2) return false;
   for(int i = 0; i < 2; i++)
      for(int c = 0; c < StringLen(parts[i]); c++)
      {
         ushort ch = StringGetCharacter(parts[i], c);
         if(ch < '0' || ch > '9') return false;
      }
   int h = (int)StringToInteger(parts[0]);
   int m = (int)StringToInteger(parts[1]);
   if(h > 23 || m > 59) return false;
   minutes = h * 60 + m;
   return true;
}

//--- PURE: window membership. start == end -> empty window (never in).
bool TL_InWindow(const int nowMin, const int startMin, const int endMin)
{
   if(startMin == endMin) return false;
   if(startMin < endMin)  return nowMin >= startMin && nowMin < endMin;
   return nowMin >= startMin || nowMin < endMin;    // overnight span
}

//--- Parsed schedule, owned by the composition root (like g_news) ------
class CTimeSchedule
{
private:
   bool m_on[4];
   int  m_start[4];
   int  m_end[4];
   int  m_enabled;

   bool ParseOne(const int i, const bool on, const string s, const string e, string &err)
   {
      m_on[i] = on;
      m_start[i] = 0; m_end[i] = 0;
      if(!on) return true;
      if(!TL_ParseHHMM(s, m_start[i])) { err = "window " + (string)(i + 1) + " start '" + s + "' is not HH:MM"; return false; }
      if(!TL_ParseHHMM(e, m_end[i]))   { err = "window " + (string)(i + 1) + " end '"   + e + "' is not HH:MM"; return false; }
      if(m_start[i] == m_end[i])       { err = "window " + (string)(i + 1) + " start == end (empty window)"; return false; }
      m_enabled++;
      return true;
   }
public:
   CTimeSchedule() : m_enabled(0) {}

   //--- config-time validation: bad HH:MM / no enabled window -> refuse
   //    (config-syntax error class, same as LotSequence_ format errors)
   bool Init(string &err)
   {
      m_enabled = 0;
      if(!ParseOne(0, UseTime1, Time1Start, Time1End, err)) return false;
      if(!ParseOne(1, UseTime2, Time2Start, Time2End, err)) return false;
      if(!ParseOne(2, UseTime3, Time3Start, Time3End, err)) return false;
      if(!ParseOne(3, UseTime4, Time4Start, Time4End, err)) return false;
      if(m_enabled == 0) { err = "UseTimeLimit=true but no window is enabled"; return false; }
      return true;
   }

   //--- PURE membership over the enabled windows (any-match)
   bool AllowedAt(const int nowMin) const
   {
      for(int i = 0; i < 4; i++)
         if(m_on[i] && TL_InWindow(nowMin, m_start[i], m_end[i])) return true;
      return false;
   }

   bool AllowedNow() const
   {
      MqlDateTime t;
      TimeToStruct(TimeLocal(), t);    // PC/local time per the manual
      return AllowedAt(t.hour * 60 + t.min);
   }

   string Describe() const
   {
      string s = "";
      for(int i = 0; i < 4; i++)
         if(m_on[i])
            s += (s == "" ? "" : ", ") + "W" + (string)(i + 1) + " " +
                 StringFormat("%02d:%02d-%02d:%02d", m_start[i] / 60, m_start[i] % 60, m_end[i] / 60, m_end[i] % 60);
      return s;
   }
};

//--- FE-403: entry filter. New-series chain: hard schedule. Grid chain:
//    DcaOutsideTime=true lets DCA adds through outside the windows.
//    Registered from OnInit ONLY when UseTimeLimit=true (zero cost off).
class CTimeFilter : public IEntryFilter
{
private:
   CTimeSchedule *m_sched;
   bool           m_forGrid;
public:
   CTimeFilter(CTimeSchedule *sched, const bool forGrid) : m_sched(sched), m_forGrid(forGrid) {}
   bool Allow(const EAContext &ctx, const int dir)
   {
      if(m_forGrid && DcaOutsideTime) return true;   // "DCA ngoai thoi gian?"
      return m_sched.AllowedNow();
   }
};

//--- Chain -----------------------------------------------------------
class CFilterChain
{
private:
   IEntryFilter *m_filters[];
public:
   void Add(IEntryFilter *f)
   {
      int n = ArraySize(m_filters);
      ArrayResize(m_filters, n + 1);
      m_filters[n] = f;
   }
   bool Allow(const EAContext &ctx, const int dir)
   {
      for(int i = 0; i < ArraySize(m_filters); i++)
         if(!m_filters[i].Allow(ctx, dir)) return false;
      return true;
   }
   void Clear()
   {
      for(int i = 0; i < ArraySize(m_filters); i++)
         if(CheckPointer(m_filters[i]) == POINTER_DYNAMIC) delete m_filters[i];
      ArrayResize(m_filters, 0);
   }
};
#endif // BD_ENTRYFILTERS_MQH
