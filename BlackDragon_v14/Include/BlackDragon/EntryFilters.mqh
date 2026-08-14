//+------------------------------------------------------------------+
//| EntryFilters.mqh — BlackDragon v14.8.0                           |
//| Purpose   : IEntryFilter chain: spread, pause, news, local-time. |
//|             Adding a filter = new class + register in OnInit.    |
//| Invariants: Filters only READ ctx; never place orders.           |
//| Depends on: Types.mqh, NewsCalendar.mqh                          |
//| v14.8.0  : legacy Start_Hour/End_Hour + CHourFilter removed.     |
//|             The detailed PC/local HH:MM schedule is the single   |
//|             time-window implementation.                          |
//+------------------------------------------------------------------+
#ifndef BD_ENTRYFILTERS_MQH
#define BD_ENTRYFILTERS_MQH
#include "Types.mqh"
#include "NewsCalendar.mqh"

#define BD_DIR_BUY  0
#define BD_DIR_SELL 1

class CSpreadFilter : public IEntryFilter
{
public:
   bool Allow(const EAContext &ctx, const int dir)
   {
      if(MaxSpred == 0) return true;
      return ctx.spreadPoints <= MaxSpred * Cfg.PointScale;
   }
};

class CPauseFilter : public IEntryFilter
{
public:
   bool Allow(const EAContext &ctx, const int dir)
   {
      if(Cfg.RemoteStop) return false;
      if(dir == BD_DIR_BUY  && Cfg.PauseBuy)  return false;
      if(dir == BD_DIR_SELL && Cfg.PauseSell) return false;
      return true;
   }
};

class CNewsFilter : public IEntryFilter
{
public:
   bool Allow(const EAContext &ctx, const int dir)
   {
      return ctx.newsAllowsNew;
   }
};

bool Hedge_AllowsNewSeries(const bool useHedge, const int oppositeCount)
{
   return useHedge || oppositeCount <= 0;
}

bool Hedge_AllowsGridAdd(const int ownCount)
{
   return ownCount > 0;
}

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

bool TL_InWindow(const int nowMin, const int startMin, const int endMin)
{
   if(startMin == endMin) return false;
   if(startMin < endMin)  return nowMin >= startMin && nowMin < endMin;
   return nowMin >= startMin || nowMin < endMin;
}

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
      m_start[i] = 0;
      m_end[i] = 0;
      if(!on) return true;
      if(!TL_ParseHHMM(s, m_start[i]))
      {
         err = "window " + (string)(i + 1) + " start '" + s + "' is not HH:MM";
         return false;
      }
      if(!TL_ParseHHMM(e, m_end[i]))
      {
         err = "window " + (string)(i + 1) + " end '" + e + "' is not HH:MM";
         return false;
      }
      if(m_start[i] == m_end[i])
      {
         err = "window " + (string)(i + 1) + " start == end (empty window)";
         return false;
      }
      m_enabled++;
      return true;
   }

public:
   CTimeSchedule() : m_enabled(0) {}

   bool Init(string &err)
   {
      m_enabled = 0;
      if(!ParseOne(0, UseTime1, Time1Start, Time1End, err)) return false;
      if(!ParseOne(1, UseTime2, Time2Start, Time2End, err)) return false;
      if(!ParseOne(2, UseTime3, Time3Start, Time3End, err)) return false;
      if(!ParseOne(3, UseTime4, Time4Start, Time4End, err)) return false;
      if(m_enabled == 0)
      {
         err = "UseTimeLimit=true but no window is enabled";
         return false;
      }
      return true;
   }

   bool AllowedAt(const int nowMin) const
   {
      for(int i = 0; i < 4; i++)
         if(m_on[i] && TL_InWindow(nowMin, m_start[i], m_end[i])) return true;
      return false;
   }

   bool AllowedNow() const
   {
      MqlDateTime t;
      TimeToStruct(TimeLocal(), t);
      return AllowedAt(t.hour * 60 + t.min);
   }

   string Describe() const
   {
      string s = "";
      for(int i = 0; i < 4; i++)
         if(m_on[i])
            s += (s == "" ? "" : ", ") + "W" + (string)(i + 1) + " " +
                 StringFormat("%02d:%02d-%02d:%02d", m_start[i] / 60, m_start[i] % 60,
                              m_end[i] / 60, m_end[i] % 60);
      return s;
   }
};

class CTimeFilter : public IEntryFilter
{
private:
   CTimeSchedule *m_sched;
   bool           m_forGrid;
public:
   CTimeFilter(CTimeSchedule *sched, const bool forGrid) : m_sched(sched), m_forGrid(forGrid) {}
   bool Allow(const EAContext &ctx, const int dir)
   {
      if(m_forGrid && DcaOutsideTime) return true;
      return m_sched.AllowedNow();
   }
};

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
