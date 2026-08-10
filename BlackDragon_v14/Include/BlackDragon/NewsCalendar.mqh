//+------------------------------------------------------------------+
//| NewsCalendar.mqh — BlackDragon v14.0.0                           |
//| Purpose   : News pause windows from the BUILT-IN MQL5 economic   |
//|             calendar (Nhom D). Replaces v13 investing.com        |
//|             scraping (blocking WebRequest 120s, bug #11).        |
//| Outputs   : News_AllowsNewOrders(now)                            |
//| Invariants: Never blocks OnTick. Cache refresh only in OnTimer.  |
//| Depends on: Config.mqh, Logger.mqh                               |
//| NOTE: Strategy tester has no calendar data -> NewsFailMode       |
//|       decides (default: trade on, same as v13 fail-open).        |
//+------------------------------------------------------------------+
#ifndef BD_NEWSCALENDAR_MQH
#define BD_NEWSCALENDAR_MQH
#include "Config.mqh"
#include "Logger.mqh"

struct SNewsWindow { datetime from; datetime to; };

class CNewsCalendar
{
private:
   SNewsWindow m_windows[];
   datetime    m_lastRefresh;
   bool        m_hasData;
   string      m_currencies[2];

   void AddWindow(const datetime eventTime, const int beforeMin, const int afterMin)
   {
      int n = ArraySize(m_windows);
      ArrayResize(m_windows, n + 1);
      m_windows[n].from = eventTime - beforeMin * 60;
      m_windows[n].to   = eventTime + afterMin * 60;
   }
public:
   CNewsCalendar() : m_lastRefresh(0), m_hasData(false) {}

   void Init()
   {
      // v13 filtered by the two symbol currencies
      m_currencies[0] = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_BASE);
      m_currencies[1] = SymbolInfoString(_Symbol, SYMBOL_CURRENCY_PROFIT);
   }

   // Call from OnTimer only — never from OnTick
   void Refresh()
   {
      if(!Flag_Use_News) return;
      if(TimeCurrent() - m_lastRefresh < BD_NEWS_REFRESH_SEC && m_lastRefresh != 0) return;
      m_lastRefresh = TimeCurrent();
      ArrayResize(m_windows, 0);
      m_hasData = false;

      MqlCalendarValue values[];
      datetime from = TimeCurrent() - 2 * 3600;
      datetime to   = TimeCurrent() + 48 * 3600;
      for(int c = 0; c < 2; c++)
      {
         if(c == 1 && m_currencies[1] == m_currencies[0]) break;
         int total = CalendarValueHistory(values, from, to, NULL, m_currencies[c]);
         if(total <= 0) continue;
         m_hasData = true;
         for(int i = 0; i < total; i++)
         {
            MqlCalendarEvent ev;
            if(!CalendarEventById(values[i].event_id, ev)) continue;
            if(ev.importance == CALENDAR_IMPORTANCE_HIGH     && Imp3High) AddWindow(values[i].time, b3_, a3_);
            if(ev.importance == CALENDAR_IMPORTANCE_MODERATE && Imp2Med)  AddWindow(values[i].time, b2_, a2_);
            if(ev.importance == CALENDAR_IMPORTANCE_LOW      && Imp1Low)  AddWindow(values[i].time, b1_, a1_);
         }
      }
      Log_Info("News", "calendar cache refreshed: " + (string)ArraySize(m_windows) + " pause windows");
   }

   // Was: Flag_Mojno_New_Ord. O(windows) lookup, no allocation.
   bool AllowsNewOrders(const datetime now)
   {
      if(!Flag_Use_News) return true;
      if(!m_hasData) return (NewsFailMode == news_fail_TradeOn);  // fail mode is explicit now (bug #11)
      for(int i = ArraySize(m_windows) - 1; i >= 0; i--)
         if(now >= m_windows[i].from && now <= m_windows[i].to) return false;
      return true;
   }
};
#endif // BD_NEWSCALENDAR_MQH
