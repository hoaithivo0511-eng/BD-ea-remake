//+------------------------------------------------------------------+
//| SignalEngine.mqh — BlackDragon v14.0.0                           |
//| Purpose   : Basket direction signal. RSI(50) vs 50 on closed bar |
//|             1, optional Stochastic(7,1,2) confirmation.          |
//| Inputs    : indicator handles (created once in Init).            |
//| Outputs   : ctx.signalBuy / ctx.signalSell (once per new bar).   |
//| Invariants: pure w.r.t. trading state; never sends orders.       |
//| Depends on: Config.mqh, Types.mqh, Logger.mqh                    |
//| [STRATEGY-BEHAVIOR] Comparison rules below are v13 behavior.     |
//|                     Do not change during refactors.              |
//+------------------------------------------------------------------+
#ifndef BD_SIGNALENGINE_MQH
#define BD_SIGNALENGINE_MQH
#include "Types.mqh"
#include "Logger.mqh"

class CRsiStochSignal : public ISignal
{
private:
   int      m_hRsi;
   int      m_hStoch;
   datetime m_barFlags;    // v13: tBars  — reset flags each new bar
   datetime m_barSignal;   // v13: tBars2 — evaluate once per closed bar
   bool     m_sigBuy;
   bool     m_sigSell;
public:
   CRsiStochSignal() : m_hRsi(INVALID_HANDLE), m_hStoch(INVALID_HANDLE),
                       m_barFlags(0), m_barSignal(0), m_sigBuy(false), m_sigSell(false) {}

   bool Init()
   {
      // v13: RSI_Period=50, applied to close, TF_DB; Stoch(7,1,2) LWMA/CloseClose, TF_Stoh
      m_hRsi = iRSI(_Symbol, TF_DB, BD_RSI_PERIOD, PRICE_CLOSE);
      // AU-14-04: create the Stochastic handle only when it is actually used.
      // With Use_Stoh=false (default) the indicator was computed every tick
      // for nothing, and a persistent CopyBuffer failure on it stalled the
      // RSI-only signal too.
      if(Use_Stoh)
         m_hStoch = iStochastic(_Symbol, TF_Stoh, KPeriod, DPeriod, Slowing, MODE_LWMA, STO_CLOSECLOSE);
      if(m_hRsi == INVALID_HANDLE || (Use_Stoh && m_hStoch == INVALID_HANDLE))
      {
         Log_Error("Signal", "indicator handle creation failed");
         return false;
      }
      return true;
   }

   void Deinit()
   {
      if(m_hRsi   != INVALID_HANDLE) IndicatorRelease(m_hRsi);
      if(m_hStoch != INVALID_HANDLE) IndicatorRelease(m_hStoch);
   }

   // Fills ctx.signalBuy / ctx.signalSell
   void Compute(EAContext &ctx)
   {
      if(m_barFlags != ctx.barTime)
      {
         m_barFlags = ctx.barTime;
         m_sigBuy   = false;
         m_sigSell  = false;
      }
      if(m_barSignal != ctx.barTime)
      {
         double rsiBuf[1], stochBuf[1];
         // [STRATEGY-BEHAVIOR] closed bar (shift 1) values only
         if(CopyBuffer(m_hRsi, 0, 1, 1, rsiBuf) != 1) { Publish(ctx); return; }   // retry next tick (v13 behavior)
         double d = 0;   // AU-14-04: unused when Use_Stoh=false ("|| !Use_Stoh" below)
         if(Use_Stoh)
         {
            if(CopyBuffer(m_hStoch, 0, 1, 1, stochBuf) != 1) { Publish(ctx); return; }
            d = stochBuf[0];
         }
         m_barSignal = ctx.barTime;   // v13: SignalBar==Closed -> mark evaluated

         int flagBD = 0;
         if(rsiBuf[0] > BD_RSI_OVER)      flagBD = 1;
         else if(rsiBuf[0] < BD_RSI_OVER) flagBD = -1;

         // [STRATEGY-BEHAVIOR] v13 rules:
         // SELL: rsi < 50 and (stoch >= Up_Level or stochastic off)
         // BUY : rsi > 50 and (stoch <= Down_Level or stochastic off)
         if((d >= Up_Level   || !Use_Stoh) && flagBD == -1) m_sigSell = true;
         if((d <= Down_Level || !Use_Stoh) && flagBD ==  1) m_sigBuy  = true;
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
#endif // BD_SIGNALENGINE_MQH
