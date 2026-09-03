//+------------------------------------------------------------------+
//| WmfSignal.mqh — BlackDragon v14.6.0                              |
//| Purpose   : FE-405 — port TradingView "WUYX Momentum Follower"   |
//|             (WMF, Pine v5) lam nguon tin hieu thay the qua       |
//|             ISignal. Ban chat: Volatility Stop (ATR ratchet) x   |
//|             EMA — vStop bam gia mot chieu den khi bi xuyen thi   |
//|             lat trend va reset extremes.                         |
//| Modes     : wmf_Cross = dung nhan BUY/SELL cua indi (EMA giao    |
//|             cat vStop, bao dung 1 lan tren nen WMF co cross);    |
//|             wmf_Trend = trang thai mau nen (EMA tren/duoi vStop).|
//| Fidelity  : WMF_Step tai lap DUNG thu tu Pine tung nen dong:     |
//|             (1) max/min ratchet (2) stop ratchet (3) so trend    |
//|             (4) reset khi lat (5) EMA de quy alpha=2/(len+1).    |
//|             ATR qua iATR (Wilder — trung ta.atr). Seed bang cach |
//|             chay lai toi da BD_WMF_WARMUP nen dong (he hoi tu    |
//|             nhanh sau vai lan lat; vai nen warmup dau co the     |
//|             lech nhe so TradingView — chap nhan, ghi chu).       |
//|             Gap nhieu nen (EA tat lau) -> tu re-seed toan bo.    |
//| Stoch     : ap dung Y HET luat xac nhan cua CRsiStochSignal      |
//|             ([STRATEGY-BEHAVIOR] — nhan ban co chu dich de khong |
//|             dung den class tin hieu cu).                         |
//| Invariants: pure w.r.t. trading state; never sends orders.       |
//| Depends on: Config.mqh, Types.mqh, Logger.mqh                    |
//+------------------------------------------------------------------+
#ifndef BD_WMFSIGNAL_MQH
#define BD_WMFSIGNAL_MQH
#include "Types.mqh"
#include "Logger.mqh"

#define BD_WMF_WARMUP 1000    // closed bars walked to converge the recursion

//--- PURE: Pine input `src` — applied price from OHLC ----------------
double WMF_Price(const ENUM_APPLIED_PRICE ap, const double o, const double h,
                 const double l, const double c)
{
   switch(ap)
   {
      case PRICE_OPEN:     return o;
      case PRICE_HIGH:     return h;
      case PRICE_LOW:      return l;
      case PRICE_MEDIAN:   return (h + l) / 2.0;
      case PRICE_TYPICAL:  return (h + l + c) / 3.0;
      case PRICE_WEIGHTED: return (h + l + 2.0 * c) / 4.0;
   }
   return c;   // PRICE_CLOSE (default)
}

//--- PURE: recursive WMF state (unit-tested in RunTests + offline) ---
struct SWmfState
{
   bool   seeded;
   double maxVal;
   double minVal;
   bool   uptrend;
   double stop;
   double ema;
};

void WMF_Reset(SWmfState &st)
{
   st.seeded = false; st.maxVal = 0; st.minVal = 0;
   st.uptrend = true; st.stop = 0; st.ema = 0;
}

//--- One CLOSED-bar step, faithful to the Pine execution order.
void WMF_Step(SWmfState &st, const double src, const double atrM, const double emaAlpha)
{
   if(!st.seeded)
   {
      st.maxVal = src; st.minVal = src;          // Pine: var maxVal/minVal = src
      st.uptrend = true; st.stop = 0.0;          // Pine: var uptrend=true, stop=0.0
      st.ema = src;                              // EMA seeds on first value
      st.seeded = true;
   }
   else
      st.ema = st.ema + emaAlpha * (src - st.ema);

   st.maxVal = MathMax(st.maxVal, src);
   st.minVal = MathMin(st.minVal, src);
   st.stop = st.uptrend ? MathMax(st.stop, st.maxVal - atrM)
                        : MathMin(st.stop, st.minVal + atrM);
   bool prevUp = st.uptrend;                     // uptrend[1]
   st.uptrend = (src - st.stop) >= 0.0;
   if(st.uptrend != prevUp)                      // reversal -> reset extremes
   {
      st.maxVal = src;
      st.minVal = src;
      st.stop = st.uptrend ? st.maxVal - atrM : st.minVal + atrM;
   }
}

//--- Optional WMF BUY/SELL chart signal payload ----------------------
struct SWmfMark
{
   datetime time;
   bool     isBuy;
   double   price;
};
#define BD_WMF_SEED_MARKS 100

class CWmfSignal : public ISignal
{
private:
   int       m_hAtr;
   int       m_hStoch;
   SWmfState m_st;
   double    m_prevEma;     // state values BEFORE the newest step (for crossover)
   double    m_prevStop;
   bool      m_havePrev;
   int       m_pendingCross; // AU-14-11: +1 buy / -1 sell cross awaiting evaluation
                             // (persists across copy-fail retries so a cross is
                             // never lost when the stoch buffer lags one tick)
   SWmfMark  m_marks[];
   datetime  m_lastClosed;  // open time of the last processed closed WmfTF bar
   datetime  m_barFlags;    // reset signal flags each new chart bar (v13 pattern)
   datetime  m_barSignal;   // evaluated once per chart bar; retry on copy fail
   bool      m_sigBuy;
   bool      m_sigSell;

   double Alpha() const { return 2.0 / (WmfEmaLength + 1.0); }

   void AddMark(const bool isBuy, const datetime t, const double lo, const double hi)
   {
      if(!ShowWmfSignals ||
         (MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))) return;
      int n = ArraySize(m_marks);
      ArrayResize(m_marks, n + 1);
      m_marks[n].time  = t;
      m_marks[n].isBuy = isBuy;
      m_marks[n].price = isBuy ? lo : hi;
   }

   //--- AU-14-11: after a step, detect the cross once
   void NoteCross(const datetime t, const double lo, const double hi)
   {
      if(!m_havePrev) { m_pendingCross = 0; return; }
      bool buy  = (m_st.ema > m_st.stop) && (m_prevEma <= m_prevStop);
      bool sell = (m_st.ema < m_st.stop) && (m_prevEma >= m_prevStop);
      m_pendingCross = buy ? 1 : (sell ? -1 : 0);
      if(buy)  AddMark(true, t, lo, hi);
      if(sell) AddMark(false, t, lo, hi);
   }

   double AtrOf(const double atrRaw, const double high, const double low) const
   {
      // Pine: nz(ta.atr(len)*factor, ta.tr) — warmup fallback ~ bar range
      if(atrRaw != EMPTY_VALUE && atrRaw > 0) return atrRaw * WmfFactor;
      return MathMax(high - low, 0);
   }

   //--- (re)build the recursion from history, oldest -> newest closed bar
   bool Seed()
   {
      WMF_Reset(m_st);
      m_havePrev = false; m_lastClosed = 0;
      MqlRates rates[];
      int got = CopyRates(_Symbol, WmfTF, 1, BD_WMF_WARMUP, rates);   // closed bars only
      if(got < WmfLength + 2) return false;
      double atr[];
      if(CopyBuffer(m_hAtr, 0, 1, got, atr) != got) return false;
      // CopyRates/CopyBuffer (non-series arrays): index 0 = OLDEST element
      ArrayResize(m_marks, 0);
      for(int i = 0; i < got; i++)
      {
         if(m_st.seeded) { m_prevEma = m_st.ema; m_prevStop = m_st.stop; m_havePrev = true; }
         WMF_Step(m_st,
                  WMF_Price(WmfPrice, rates[i].open, rates[i].high, rates[i].low, rates[i].close),
                  AtrOf(atr[i], rates[i].high, rates[i].low), Alpha());
         NoteCross(rates[i].time, rates[i].low, rates[i].high);
      }
      int nm = ArraySize(m_marks);
      if(nm > BD_WMF_SEED_MARKS)
      {
         for(int i = 0; i < BD_WMF_SEED_MARKS; i++)
            m_marks[i] = m_marks[nm - BD_WMF_SEED_MARKS + i];
         ArrayResize(m_marks, BD_WMF_SEED_MARKS);
      }
      m_lastClosed = rates[got - 1].time;
      return true;
   }

public:
   CWmfSignal() : m_hAtr(INVALID_HANDLE), m_hStoch(INVALID_HANDLE),
                  m_prevEma(0), m_prevStop(0), m_havePrev(false), m_pendingCross(0),
                  m_lastClosed(0), m_barFlags(0), m_barSignal(0),
                  m_sigBuy(false), m_sigSell(false)
   { WMF_Reset(m_st); }

   int TakePendingMarks(SWmfMark &out[])
   {
      int n = ArraySize(m_marks);
      ArrayResize(out, n);
      for(int i = 0; i < n; i++) out[i] = m_marks[i];
      ArrayResize(m_marks, 0);
      return n;
   }

   bool Init()
   {
      if(WmfLength < 2 || WmfEmaLength < 1 || WmfFactor <= 0)
      {
         Log_Error("WMF", "invalid inputs — required: WmfLength>=2 (Pine minval), WmfEmaLength>=1, WmfFactor>0");
         return false;
      }
      m_hAtr = iATR(_Symbol, WmfTF, WmfLength);
      if(Use_Stoh)   // FE-405: identical stochastic confirmation as the BD signal
         m_hStoch = iStochastic(_Symbol, TF_Stoh, KPeriod, DPeriod, Slowing, MODE_LWMA, STO_CLOSECLOSE);
      if(m_hAtr == INVALID_HANDLE || (Use_Stoh && m_hStoch == INVALID_HANDLE))
      {
         Log_Error("WMF", "indicator handle creation failed");
         return false;
      }
      if(!Seed()) Log_Warn("WMF", "seed", "not enough history yet — will retry on ticks");
      else Log_Info("WMF", "seeded " + (string)BD_WMF_WARMUP + " bars: trend=" + (m_st.uptrend ? "UP" : "DOWN") +
                    " vStop=" + DoubleToString(m_st.stop, _Digits));
      return true;
   }

   void Deinit()
   {
      if(m_hAtr   != INVALID_HANDLE) IndicatorRelease(m_hAtr);
      if(m_hStoch != INVALID_HANDLE) IndicatorRelease(m_hStoch);
   }

   void Compute(EAContext &ctx)
   {
      if(m_barFlags != ctx.barTime)
      {
         m_barFlags = ctx.barTime;
         m_sigBuy = false; m_sigSell = false;
      }
      if(m_barSignal != ctx.barTime)
      {
         if(!m_st.seeded && !Seed()) { Publish(ctx); return; }   // retry next tick

         datetime newest = iTime(_Symbol, WmfTF, 1);             // newest CLOSED WmfTF bar
         if(newest == 0) { Publish(ctx); return; }

         if(newest != m_lastClosed)
         {
            int sh = (m_lastClosed == 0) ? -1 : iBarShift(_Symbol, WmfTF, m_lastClosed, true);
            if(sh != 2)
            {
               // gap (EA was off / history reload / WmfTF < chart TF) -> replay warmup
               if(!Seed()) { Publish(ctx); return; }
               // NoteCross already ran on the newest seeded bar
            }
            else
            {
               MqlRates r[];
               if(CopyRates(_Symbol, WmfTF, 1, 1, r) != 1) { Publish(ctx); return; }
               double atr[1];
               if(CopyBuffer(m_hAtr, 0, 1, 1, atr) != 1) { Publish(ctx); return; }
               m_prevEma = m_st.ema; m_prevStop = m_st.stop; m_havePrev = true;
               WMF_Step(m_st,
                        WMF_Price(WmfPrice, r[0].open, r[0].high, r[0].low, r[0].close),
                        AtrOf(atr[0], r[0].high, r[0].low), Alpha());
               NoteCross(r[0].time, r[0].low, r[0].high);
               m_lastClosed = newest;
            }
         }

         double d = 0;   // stoch confirm — same rule/branching as CRsiStochSignal
         if(Use_Stoh)
         {
            double stochBuf[1];
            if(CopyBuffer(m_hStoch, 0, 1, 1, stochBuf) != 1) { Publish(ctx); return; }
            d = stochBuf[0];
         }
         m_barSignal = ctx.barTime;

         bool rawBuy, rawSell;
         if(WmfMode == wmf_Cross)
         {
            // ta.crossover/crossunder — the pending cross (AU-14-11) fires
            // exactly once and SURVIVES copy-fail retries within the bar
            rawBuy  = (m_pendingCross == 1);
            rawSell = (m_pendingCross == -1);
         }
         else   // wmf_Trend — barcolor state (green/red; equality -> neither)
         {
            rawBuy  = m_st.ema > m_st.stop;
            rawSell = m_st.ema < m_st.stop;
         }
         m_pendingCross = 0;   // consumed (either mode)

         // [STRATEGY-BEHAVIOR] identical stoch gate as the BD signal:
         if((d <= Down_Level || !Use_Stoh) && rawBuy)  m_sigBuy  = true;
         if((d >= Up_Level   || !Use_Stoh) && rawSell) m_sigSell = true;
      }
      Publish(ctx);
   }

private:
   void Publish(EAContext &ctx)
   {
      ctx.signalBuy  = m_sigBuy;
      ctx.signalSell = m_sigSell;
   }
};
#endif // BD_WMFSIGNAL_MQH
