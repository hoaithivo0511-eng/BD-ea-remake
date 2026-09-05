//+------------------------------------------------------------------+
//| WmfSignalOverlay.mqh — optional WMF arrow rendering only          |
//| No dashboard, labels, levels, buttons, chart events or trading.  |
//+------------------------------------------------------------------+
#ifndef BD_WMF_SIGNAL_OVERLAY_MQH
#define BD_WMF_SIGNAL_OVERLAY_MQH
#include "WmfSignal.mqh"

class CWmfSignalOverlay
{
private:
   string m_names[BD_WMF_MARKS_MAX];
   int    m_next;
   bool   m_enabled;

public:
   void Init()
   {
      m_next = 0;
      m_enabled = ShowWmfSignals &&
                  (!MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_VISUAL_MODE));
      for(int i = 0; i < BD_WMF_MARKS_MAX; i++) m_names[i] = "";
      if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
      ObjectsDeleteAll(0, BD_WMF_OBJ_PREFIX);
   }

   bool Enabled() const { return m_enabled; }

   void Mark(const bool isBuy, const datetime when, const double price)
   {
      if(!m_enabled) return;
      string name = BD_WMF_OBJ_PREFIX + (isBuy ? "B" : "S") + (string)(long)when;
      if(ObjectFind(0, name) >= 0) return;
      if(m_names[m_next] != "") ObjectDelete(0, m_names[m_next]);
      m_names[m_next] = name;
      m_next = (m_next + 1) % BD_WMF_MARKS_MAX;
      ObjectCreate(0, name, OBJ_ARROW, 0, when, price);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, isBuy ? 233 : 234);
      ObjectSetInteger(0, name, OBJPROP_COLOR, isBuy ? clrLime : clrRed);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,
                       isBuy ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, isBuy ? "WMF BUY" : "WMF SELL");
   }

   void Deinit(const int reason)
   {
      if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE)) return;
      if(reason == REASON_PARAMETERS || reason == REASON_CHARTCHANGE) return;
      ObjectsDeleteAll(0, BD_WMF_OBJ_PREFIX);
   }
};
#endif // BD_WMF_SIGNAL_OVERLAY_MQH
