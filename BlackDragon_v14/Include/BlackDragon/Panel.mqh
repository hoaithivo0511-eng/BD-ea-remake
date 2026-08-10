//+------------------------------------------------------------------+
//| Panel.mqh — BlackDragon v14.0.0                                  |
//| Purpose   : ALL chart UI. Buttons, labels, level lines.          |
//| Invariants: The ONLY module touching chart objects. Contains NO  |
//|             trade logic — it toggles Cfg flags and raises        |
//|             requests the coordinator consumes.                   |
//| Fixes     : C3 — redraw on timer (500ms) + only when a value     |
//|             changed, instead of ~20 ObjectSet per tick.          |
//| Depends on: Config.mqh, Types.mqh, Persistence.mqh               |
//+------------------------------------------------------------------+
#ifndef BD_PANEL_MQH
#define BD_PANEL_MQH
#include "Types.mqh"
#include "Persistence.mqh"

class CPanel
{
private:
   bool   m_enabled;
   string m_p;                 // object prefix
   double m_lastBuyProfit, m_lastSellProfit, m_lastDayProfit;
   datetime m_lastHalt;        // FE-402: last halt-until shown in the title
   string   m_wmfMarks[BD_WMF_MARKS_MAX];   // FE-406: ring of WMF arrow names
   int      m_wmfMarkIdx;
   double m_lines[8];          // cached line prices (dirty check)
   bool   m_reqCloseBuy, m_reqCloseSell, m_reqOpenBuy, m_reqOpenSell;

   void Button(const string name, const int x, const int y, const int w, const int h,
               const string text, const color bg)
   {
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
         ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
         ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
         ObjectSetString(0, name, OBJPROP_FONT, FontNameButt);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FontSizeButt);
         ObjectSetInteger(0, name, OBJPROP_COLOR, ColorButt);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      }
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(0, name, OBJPROP_STATE, false);
   }

   void Label(const string name, const int x, const int y, const string text)
   {
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
         ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
         ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
         ObjectSetString(0, name, OBJPROP_FONT, FontNameMark);
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, FontSizeMark);
         ObjectSetInteger(0, name, OBJPROP_COLOR, ColorText);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      }
      ObjectSetString(0, name, OBJPROP_TEXT, text);
   }

   void HLine(const int slot, const string name, const double price, const color clr,
              const int width, const string text)
   {
      if(price == m_lines[slot] && ObjectFind(0, name) >= 0) return;   // C3: dirty check
      m_lines[slot] = price;
      if(price == 0) { ObjectDelete(0, name); ObjectDelete(0, name + "Txt"); return; }
      if(ObjectFind(0, name) < 0)
      {
         ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
         ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      }
      ObjectMove(0, name, 0, 0, price);
      if(ObjectFind(0, name + "Txt") < 0)
      {
         ObjectCreate(0, name + "Txt", OBJ_TEXT, 0, TimeCurrent(), price);
         ObjectSetInteger(0, name + "Txt", OBJPROP_COLOR, clr);
         ObjectSetInteger(0, name + "Txt", OBJPROP_SELECTABLE, false);
      }
      ObjectMove(0, name + "Txt", 0, TimeCurrent(), price);
      ObjectSetString(0, name + "Txt", OBJPROP_TEXT, text);
   }

public:
   void Init()
   {
      m_enabled = fDraw && (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE));
      m_p = BD_OBJ_PREFIX;
      ArrayInitialize(m_lines, -1);
      m_lastBuyProfit = m_lastSellProfit = m_lastDayProfit = DBL_MAX;
      m_lastHalt = (datetime)-1;   // force first ShowHalt draw
      m_wmfMarkIdx = 0;
      for(int i = 0; i < BD_WMF_MARKS_MAX; i++) m_wmfMarks[i] = "";
      m_reqCloseBuy = m_reqCloseSell = m_reqOpenBuy = m_reqOpenSell = false;
      if(!m_enabled) return;

      int x = Cfg.X1, y = Cfg.Y1;
      if(ObjectFind(0, m_p + "Fon") < 0)
      {
         ObjectCreate(0, m_p + "Fon", OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(0, m_p + "Fon", OBJPROP_XDISTANCE, x - 5);
         ObjectSetInteger(0, m_p + "Fon", OBJPROP_YDISTANCE, y - 5);
         ObjectSetInteger(0, m_p + "Fon", OBJPROP_XSIZE, 620);
         ObjectSetInteger(0, m_p + "Fon", OBJPROP_YSIZE, 110);
         ObjectSetInteger(0, m_p + "Fon", OBJPROP_BGCOLOR, cCIP);
         ObjectSetInteger(0, m_p + "Fon", OBJPROP_SELECTABLE, false);
      }
      Label(m_p + "Title", x + 5, y, "EA Black Dragon v" + BD_VERSION);
      Refresh(0, 0, 0, true);
      RedrawButtons();
   }

   void RedrawButtons()
   {
      if(!m_enabled) return;
      int x = Cfg.X1, y = Cfg.Y1;
      Button(m_p + "bTradeBuy",  x + 5,   y + 70, 95, 25, Cfg.TradeBuy  ? "Buy: ON"  : "Buy: OFF",  Cfg.TradeBuy  ? clrGreen : clrGray);
      Button(m_p + "bTradeSell", x + 105, y + 70, 95, 25, Cfg.TradeSell ? "Sell: ON" : "Sell: OFF", Cfg.TradeSell ? clrGreen : clrGray);
      Button(m_p + "bPauseBuy",  x + 205, y + 70, 95, 25, Cfg.PauseBuy  ? "B-Pause!" : "Pause B",   Cfg.PauseBuy  ? clrOrangeRed : ColorFonRec);
      Button(m_p + "bPauseSell", x + 305, y + 70, 95, 25, Cfg.PauseSell ? "S-Pause!" : "Pause S",   Cfg.PauseSell ? clrOrangeRed : ColorFonRec);
      Button(m_p + "bCloseBuy",  x + 405, y + 70, 95, 25, "Close Buy",  clrFireBrick);
      Button(m_p + "bCloseSell", x + 505, y + 70, 95, 25, "Close Sell", clrFireBrick);
      Button(m_p + "bNewCycle",  x + 405, y + 12, 95, 25, Cfg.NewCycle ? "Series: ON" : "Series: OFF", Cfg.NewCycle ? clrGreen : clrGray);
      Button(m_p + "bOpenBuy",   x + 5,   y + 12, 95, 25, "Open Buy",  clrSeaGreen);
      Button(m_p + "bOpenSell",  x + 105, y + 12, 95, 25, "Open Sell", clrSeaGreen);
      if(ObjectFind(0, m_p + "eLot") < 0)
      {
         ObjectCreate(0, m_p + "eLot", OBJ_EDIT, 0, 0, 0);
         ObjectSetInteger(0, m_p + "eLot", OBJPROP_XDISTANCE, Cfg.X1 + 205);
         ObjectSetInteger(0, m_p + "eLot", OBJPROP_YDISTANCE, Cfg.Y1 + 12);
         ObjectSetInteger(0, m_p + "eLot", OBJPROP_XSIZE, 95);
         ObjectSetInteger(0, m_p + "eLot", OBJPROP_YSIZE, 25);
         ObjectSetString(0, m_p + "eLot", OBJPROP_TEXT, DoubleToString(Cfg.EditLot, 2));
      }
   }

   //--- C3: call from OnTimer (500ms), not per tick --------------------
   void Refresh(const double buyProfit, const double sellProfit, const double dayProfit,
                const bool force = false)
   {
      if(!m_enabled) return;
      int x = Cfg.X1, y = Cfg.Y1;
      if(force || buyProfit != m_lastBuyProfit)
      { m_lastBuyProfit = buyProfit;  Label(m_p + "lBuyP",  x + 5,   y + 45, "Buy profit: "   + DoubleToString(buyProfit, 2)); }
      if(force || sellProfit != m_lastSellProfit)
      { m_lastSellProfit = sellProfit; Label(m_p + "lSellP", x + 205, y + 45, "Sell profit: "  + DoubleToString(sellProfit, 2)); }
      if(force || dayProfit != m_lastDayProfit)
      { m_lastDayProfit = dayProfit;  Label(m_p + "lDayP",  x + 405, y + 45, "Daily profit: " + DoubleToString(dayProfit, 2)); }
   }

   //--- FE-406 (14.6.1): WMF BUY/SELL arrow on the chart (the indi's
   //    plotshape labels). Buy: green up-arrow anchored below the bar low;
   //    Sell: red down-arrow above the bar high. Idempotent per bar; a ring
   //    of BD_WMF_MARKS_MAX keeps the chart tidy (oldest arrow removed).
   void MarkWmfSignal(const bool isBuy, const datetime t, const double price)
   {
      if(!m_enabled) return;
      string name = m_p + (isBuy ? "wmfB" : "wmfS") + (string)(long)t;
      if(ObjectFind(0, name) >= 0) return;   // already drawn (reseed replays)
      if(m_wmfMarks[m_wmfMarkIdx] != "") ObjectDelete(0, m_wmfMarks[m_wmfMarkIdx]);
      m_wmfMarks[m_wmfMarkIdx] = name;
      m_wmfMarkIdx = (m_wmfMarkIdx + 1) % BD_WMF_MARKS_MAX;
      ObjectCreate(0, name, OBJ_ARROW, 0, t, price);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isBuy ? 233 : 234);   // wingdings up/down
      ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? clrLime : clrRed);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, isBuy ? "WMF BUY" : "WMF SELL");
   }

   //--- FE-402 (v14.3): show/clear the daily-halt notice in the title.
   //    Call from OnTimer with MoneyGuard.HaltUntil() (0 = not halted).
   void ShowHalt(const datetime until)
   {
      if(!m_enabled) return;
      if(until == m_lastHalt) return;   // dirty check
      m_lastHalt = until;
      string t = "EA Black Dragon v" + BD_VERSION;
      if(until != 0) t += "  |  DAILY HALT till " + TimeToString(until, TIME_DATE | TIME_MINUTES);
      Label(m_p + "Title", Cfg.X1 + 5, Cfg.Y1, t);
   }

   void DrawLevels(const BasketSide &b, const BasketSide &s)
   {
      if(!m_enabled) return;
      HLine(0, m_p + "BEb", b.breakeven,  clrOrange, 1, "Breakeven Buy");
      HLine(1, m_p + "BEs", s.breakeven,  clrOrange, 1, "Breakeven Sell");
      HLine(2, m_p + "TPb", b.tpLevel,    clrGreen,  2, "TP Buy");
      HLine(3, m_p + "TPs", s.tpLevel,    clrGreen,  2, "TP Sell");
      HLine(4, m_p + "SLb", b.slLevel,    clrRed,    2, "SL Buy");
      HLine(5, m_p + "SLs", s.slLevel,    clrRed,    2, "SL Sell");
      HLine(6, m_p + "TSb", b.trailLevel, clrSalmon, 1, b.trailArmed ? "Trailing stop buy"  : "Trailing stop buy start");
      HLine(7, m_p + "TSs", s.trailLevel, clrSalmon, 1, s.trailArmed ? "Trailing stop sell" : "Trailing stop sell start");
   }

   //--- OnChartEvent ----------------------------------------------------
   void OnEvent(const int id, const long lparam, const double dparam, const string sparam)
   {
      if(!m_enabled) return;
      if(id == CHARTEVENT_OBJECT_ENDEDIT && sparam == m_p + "eLot")
      {
         double v = StringToDouble(ObjectGetString(0, m_p + "eLot", OBJPROP_TEXT));
         if(v > 0) Cfg.EditLot = v;
         ObjectSetString(0, m_p + "eLot", OBJPROP_TEXT, DoubleToString(Cfg.EditLot, 2));
         Persist_Save();
         return;
      }
      if(id != CHARTEVENT_OBJECT_CLICK) return;
      if(sparam == m_p + "bTradeBuy")   Cfg.TradeBuy  = !Cfg.TradeBuy;
      else if(sparam == m_p + "bTradeSell")  Cfg.TradeSell = !Cfg.TradeSell;
      else if(sparam == m_p + "bPauseBuy")   Cfg.PauseBuy  = !Cfg.PauseBuy;
      else if(sparam == m_p + "bPauseSell")  Cfg.PauseSell = !Cfg.PauseSell;
      else if(sparam == m_p + "bNewCycle")   Cfg.NewCycle  = !Cfg.NewCycle;
      else if(sparam == m_p + "bCloseBuy")   m_reqCloseBuy  = true;
      else if(sparam == m_p + "bCloseSell")  m_reqCloseSell = true;
      else if(sparam == m_p + "bOpenBuy")    m_reqOpenBuy   = true;
      else if(sparam == m_p + "bOpenSell")   m_reqOpenSell  = true;
      else return;
      Persist_Save();
      RedrawButtons();
      ChartRedraw();
   }

   //--- Coordinator consumes one-shot requests ---------------------------
   bool TakeCloseBuy()  { bool r = m_reqCloseBuy;  m_reqCloseBuy  = false; return r; }
   bool TakeCloseSell() { bool r = m_reqCloseSell; m_reqCloseSell = false; return r; }
   bool TakeOpenBuy()   { bool r = m_reqOpenBuy;   m_reqOpenBuy   = false; return r; }
   bool TakeOpenSell()  { bool r = m_reqOpenSell;  m_reqOpenSell  = false; return r; }

   void Deinit(const int reason)
   {
      if(!m_enabled) return;
      // keep objects on param change (v13 behavior), clean otherwise
      if(reason == REASON_PARAMETERS || reason == REASON_CHARTCHANGE) return;
      ObjectsDeleteAll(0, m_p);
   }
};
#endif // BD_PANEL_MQH
