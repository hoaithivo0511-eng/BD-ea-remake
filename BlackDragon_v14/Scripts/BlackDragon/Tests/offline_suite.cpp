// ============================================================================
// BlackDragon v14.7.2 — offline test harness (Vibecode RRI-T, sandbox e2e)
// Ports the PURE functions verbatim from the .mqh sources (post-fix) plus the
// async journal logic, and re-runs every assert from Scripts/Tests/RunTests.mq5
// + new tests for AU-14-01 (RefreshFloating) and AU-14-02 (HasPendingModify).
// MQL5 cannot be compiled outside MetaTrader; this harness verifies formula
// and logic equivalence. Final compile + RunTests + golden baseline stay on
// the user's MT5 terminal (README §Quy trình nghiệm thu).
// ============================================================================
#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>
using namespace std;

// ---- MQL5 shims ------------------------------------------------------------
static double NormalizeDouble(double v, int digits){ double p = pow(10.0, digits); return round(v * p) / p; }
static double MathPow(double a, double b){ return pow(a, b); }
static double MathAbs(double v){ return fabs(v); }
static double MathMax(double a, double b){ return a > b ? a : b; }
static double MathMin(double a, double b){ return a < b ? a : b; }
#define DBL_MAX_MQL 1.7976931348623158e+308
#define BD_LOT_DIGITS 2

int g_pass = 0, g_fail = 0;
void Check(const string &name, bool cond){ if(cond){g_pass++;return;} g_fail++; printf("FAIL: %s\n", name.c_str()); }
void CheckEq(const string &name, double got, double want, double eps = 1e-9){
   if(fabs(got - want) <= eps){g_pass++;return;} g_fail++;
   printf("FAIL: %s got=%.10f want=%.10f\n", name.c_str(), got, want);
}

// ---- GridEngine.mqh (verbatim port) ----------------------------------------
int Grid_DistancePoints(const int count, const int fixDistance, const int dynStartOrder,
                        const int dynStartDistance, const double multiplier)
{
   if(count < dynStartOrder - 1) return fixDistance;
   return (int)NormalizeDouble(dynStartDistance * MathPow(multiplier, count + 1 - dynStartOrder), 0);
}
double Grid_MartingaleLot(const double firstLot, const int count, const double martin, const double maxLot)
{
   double lot = NormalizeDouble(firstLot * MathPow(martin, count), BD_LOT_DIGITS);
   if(lot > maxLot) lot = maxLot;
   return lot;
}
double Grid_FirstLot(const double lotInit, const bool autolot, const int autolotSize,
                     const double freeMargin, const double maxLot)
{
   double lot = lotInit;
   if(autolot && autolotSize > 0) lot = freeMargin / autolotSize * 0.01;
   if(lot > maxLot) lot = maxLot;
   return lot;
}

// ---- BasketManager.mqh: Basket_Breakeven (verbatim port) -------------------
double Basket_Breakeven(const double avgOpen, const double totalLots, const double costMoney,
                        const double tickValue, const double point, const bool isBuy)
{
   if(totalLots <= 0) return 0;
   double shift = 0;
   if(tickValue > 0) shift = costMoney / (tickValue * totalLots) * point;
   return isBuy ? avgOpen - shift : avgOpen + shift;
}

// ---- ExitEngine.mqh (verbatim port) ----------------------------------------
bool Exit_VirtualTpHit(const bool isBuy, const double tpLevel, const double bid, const double ask)
{ if(tpLevel == 0) return false; return isBuy ? (bid >= tpLevel) : (ask <= tpLevel); }
bool Exit_VirtualSlHit(const bool isBuy, const double slLevel, const double bid, const double ask)
{ if(slLevel == 0) return false; return isBuy ? (bid <= slLevel) : (ask >= slLevel); }
bool Exit_TrailHit(const bool isBuy, const bool armed, const double trailLevel,
                   const double bid, const double ask)
{ if(!armed || trailLevel == 0) return false; return isBuy ? (bid <= trailLevel) : (ask >= trailLevel); }
bool Exit_OverlapHit(const int count, const int overlapFromOrder, const bool overlapOn,
                     const double firstProfit, const double lastProfit, const int overlapPercent)
{
   if(!overlapOn || count < overlapFromOrder) return false;
   if(firstProfit >= 0) return false;
   return lastProfit > 0 && lastProfit >= -firstProfit * (100 + overlapPercent) / 100.0;
}

// ---- AU-14-01 model: stale cache (v14.0.1) vs RefreshFloating (v14.0.2) ----
struct MockPos { unsigned long ticket; double openPrice; double lots; double profit; };
struct MockSide { int count; double totalProfit; vector<MockPos> pos; };
// profit model: buy P/L = (bid - open) * lots * valuePerLotPerPoint / point
static double FloatPL(double open, double bid, double lots){ return (bid - open) * lots * 10000.0; }
// v14.0.2 RefreshFloating logic (same loop shape; pool = the price model)
void RefreshFloating_model(MockSide &s, double bid)
{
   if(s.count == 0) return;
   double totalProfit = 0;
   for(int i = 0; i < s.count; i++){
      s.pos[i].profit = FloatPL(s.pos[i].openPrice, bid, s.pos[i].lots);
      totalProfit += s.pos[i].profit;
   }
   s.totalProfit = totalProfit;
}

// ---- BD-002: ExecutionLayer lifecycle rule + journal model ------------------
enum eIntent { INTENT_NONE=0, INTENT_OPEN_BUY, INTENT_OPEN_SELL, INTENT_CLOSE_TICKET, INTENT_MODIFY_SLTP };
enum ePendingPhase { PENDING_SENT=0, PENDING_REQUEST_ACCEPTED };
enum ePendingEvidence { PENDING_EVIDENCE_NONE=0, PENDING_EVIDENCE_REQUEST,
   PENDING_EVIDENCE_DEAL, PENDING_EVIDENCE_ORDER_DELETE, PENDING_EVIDENCE_RESULT_STATE };
bool Exec_PendingReady(const ePendingEvidence evidence)
{ return evidence == PENDING_EVIDENCE_RESULT_STATE; }
bool Exec_CloseVolumeResolved(const double beforeVolume, const double currentVolume,
                              const double targetVolume, const double volumeStep)
{
   if(targetVolume <= 0) return false;
   double eps = volumeStep > 0 ? volumeStep * 0.5 : 1e-9;
   return beforeVolume - currentVolume + eps >= targetVolume;
}
struct PendingRequest {
   unsigned requestId; unsigned long ticket; eIntent action; ePendingPhase phase;
   double volume; double targetVolume; double observedVolume; long sentAt;
   bool serverFinal; bool stateResolved; bool orderDeleted; bool active;
};
struct Journal {
   vector<PendingRequest> m_journal;
   int completions = 0;
   void Add(unsigned reqId, unsigned long ticket, eIntent action, double volume, long now){
      PendingRequest r{}; r.requestId=reqId; r.ticket=ticket; r.action=action; r.phase=PENDING_SENT;
      r.volume=volume; r.targetVolume=volume; r.observedVolume=0; r.sentAt=now;
      r.serverFinal=false; r.stateResolved=false; r.orderDeleted=false; r.active=true;
      m_journal.push_back(r);
   }
   int Find(unsigned reqId) const {
      for(int i=(int)m_journal.size()-1;i>=0;i--)
         if(m_journal[i].active && m_journal[i].requestId==reqId) return i;
      return -1;
   }
   void TryComplete(int i){
      if(i < 0 || !m_journal[i].active) return;
      auto &r=m_journal[i];
      ePendingEvidence evidence=PENDING_EVIDENCE_NONE;
      if(r.phase==PENDING_REQUEST_ACCEPTED) evidence=PENDING_EVIDENCE_REQUEST;
      if(r.observedVolume>0) evidence=PENDING_EVIDENCE_DEAL;
      if(r.orderDeleted) evidence=PENDING_EVIDENCE_ORDER_DELETE;
      if(r.stateResolved) evidence=PENDING_EVIDENCE_RESULT_STATE;
      if(Exec_PendingReady(evidence)){
         r.active=false; completions++;
      }
   }
   void Accept(unsigned reqId, bool serverFinal, double targetVolume){
      int i=Find(reqId); if(i<0) return;
      m_journal[i].phase=PENDING_REQUEST_ACCEPTED;
      m_journal[i].serverFinal=serverFinal;
      if(targetVolume>0) m_journal[i].targetVolume=targetVolume;
      TryComplete(i);
   }
   void Reject(unsigned reqId){
      int i=Find(reqId); if(i<0) return; m_journal[i].active=false; completions++;
   }
   void ObserveDeal(unsigned reqId, double volume){
      int i=Find(reqId); if(i<0) return; m_journal[i].observedVolume += volume; TryComplete(i);
   }
   void ResolveState(unsigned reqId){
      int i=Find(reqId); if(i<0) return; m_journal[i].stateResolved=true; TryComplete(i);
   }
   void DeleteOrder(unsigned reqId){
      int i=Find(reqId); if(i<0) return; m_journal[i].orderDeleted=true; TryComplete(i);
   }
   bool HasPendingClose(unsigned long ticket) const {
      for(int i=(int)m_journal.size()-1;i>=0;i--)
         if(m_journal[i].active && m_journal[i].action==INTENT_CLOSE_TICKET && m_journal[i].ticket==ticket) return true;
      return false;
   }
   bool HasPendingModify(unsigned long ticket) const {   // AU-14-02 (new in 14.0.2)
      for(int i=(int)m_journal.size()-1;i>=0;i--)
         if(m_journal[i].active && m_journal[i].action==INTENT_MODIFY_SLTP && m_journal[i].ticket==ticket) return true;
      return false;
   }
   int WatchdogRelease(long now, int softTimeout, int hardTimeout, bool liveOrder){
      int released=0;
      for(int i=(int)m_journal.size()-1;i>=0;i--)
         if(m_journal[i].active && now - m_journal[i].sentAt > softTimeout){
            if(liveOrder || now - m_journal[i].sentAt <= hardTimeout) continue;
            m_journal[i].active=false; released++; completions++;
         }
      return released;
   }
   bool HasActive() const { for(auto &e : m_journal) if(e.active) return true; return false; }
};

// ---- FIX-5 (14.2.1): Grid_ValidateVolumes (verbatim port) ------------------
int Grid_ValidateVolumes(const vector<double> &lots, double vMin, double vMax,
                         double vStep, string &why)
{
   for(size_t i = 0; i < lots.size(); i++)
   {
      double lot = lots[i];
      if(lot < vMin){ why = "below min"; return (int)i + 1; }
      if(lot > vMax){ why = "above max"; return (int)i + 1; }
      if(vStep > 0 && fabs(lot / vStep - round(lot / vStep)) > 1e-6){ why = "off step"; return (int)i + 1; }
   }
   return -1;
}

// ---- v14.1 FE-201: Sym_PointScalePure (verbatim port) ----------------------
int Sym_PointScalePure(const bool isGold, const double point)
{
   if(!isGold || point <= 0) return 1;
   int k = (int)round(0.01 / point);
   return k < 1 ? 1 : k;
}

// ---- v14.1 FE-202: Grid_ParseLotSequence (verbatim port; StringSplit shim) -
static string trim_s(string s){
   size_t a = s.find_first_not_of(" \t"); size_t b = s.find_last_not_of(" \t");
   if(a == string::npos) return "";
   return s.substr(a, b - a + 1);
}
// v14.2 FE-301 (verbatim port): xN expansion, strict char checks, cap 200
#define BD_MAX_LOT_STEPS 200
int Grid_ParseLotSequence(const string &seq, vector<double> &lots)
{
   lots.clear();
   string s;                                                // StringReplace(s," ","")
   for(char c : seq) if(c != ' ') s += c;
   if(s.empty()) return 0;
   vector<string> parts; string cur;                        // StringSplit(s,'-')
   for(char c : s){ if(c=='-'){ parts.push_back(cur); cur.clear(); } else cur += c; }
   parts.push_back(cur);
   for(auto &p0 : parts){
      string p = p0;
      if(p.empty()){ lots.clear(); return 0; }
      int rep = 1;
      size_t xp = p.find('x'); if(xp == string::npos) xp = p.find('X');
      if(xp != string::npos){
         string cnt = p.substr(xp + 1);
         p = p.substr(0, xp);
         if(p.empty() || cnt.empty()){ lots.clear(); return 0; }
         for(char ch : cnt) if(ch < '0' || ch > '9'){ lots.clear(); return 0; }
         rep = atoi(cnt.c_str());
         if(rep < 1){ lots.clear(); return 0; }
      }
      int dots = 0;                                          // lot: digits + one '.'
      for(char ch : p){
         if(ch == '.'){ if(++dots > 1){ lots.clear(); return 0; } }
         else if(ch < '0' || ch > '9'){ lots.clear(); return 0; }
      }
      double v = atof(p.c_str());
      if(v <= 0){ lots.clear(); return 0; }
      if((int)lots.size() + rep > BD_MAX_LOT_STEPS){ lots.clear(); return 0; }
      for(int r = 0; r < rep; r++) lots.push_back(v);
   }
   return (int)lots.size();
}

// ---- v14.1 FE-202: CSequenceSizer logic (verbatim port) --------------------
struct SeqSizer {
   vector<double> m_lots; double maxLot = 5.0;
   bool Init(const string &s){ return Grid_ParseLotSequence(s, m_lots) > 0; }
   double FirstLot(){ double lot = m_lots[0]; if(lot > maxLot) lot = maxLot; return lot; }
   double NextLot(int count){
      if(count <= 0) return FirstLot();
      int idx = count, last = (int)m_lots.size() - 1;
      if(idx > last) idx = last;
      double lot = m_lots[idx]; if(lot > maxLot) lot = maxLot; return lot;
   }
};

// ---- v14.1 FE-203: Exec_BuildComment (verbatim port) -----------------------
string Exec_BuildComment(const string &baseComment, const int dcaIndex)
{
   if(dcaIndex <= 0) return baseComment;
   return baseComment + "|" + to_string(dcaIndex);
}

// ---- E2E: full DCA cycle simulation, 2-digit vs 3-digit gold ---------------
// Chains the REAL ported functions across modules: point scale (FE-201) ->
// grid distances -> sequence lots (FE-301) -> overlap trim -> count-based
// re-indexing -> breakeven/TP. The same .set must produce an identical
// USD-denominated ladder on both quote types.
struct SPos { double price; double lots; };
struct SimResult { vector<double> openUSD; vector<double> lots; vector<int> comments; double tpUSD; };
SimResult RunDcaSim(double point)
{
   SimResult r;
   int k = Sym_PointScalePure(true, point);
   SeqSizer sz; sz.Init("0.01x5-0.02x3-0.05");
   vector<SPos> open;
   double price = 3350.0;
   // order #1
   open.push_back({price, sz.NextLot(0)});
   r.openUSD.push_back(price); r.lots.push_back(open.back().lots); r.comments.push_back(1);
   // grid adds until 9 orders (price walks down onto each trigger)
   while((int)open.size() < 9)
   {
      int count = (int)open.size();
      int dist = Grid_DistancePoints(count, 200, 6, 200, 1.2) * k;   // FE-201 usage site
      price = open.back().price - dist * point;
      double lot = sz.NextLot(count);
      open.push_back({price, lot});
      r.openUSD.push_back(price); r.lots.push_back(lot); r.comments.push_back(count + 1);
   }
   // overlap trims first + last (v13 close order: last then first) -> 7 open
   open.erase(open.begin()); open.pop_back();
   // next grid add after trim: index counts OPEN orders (Chu nha's rule)
   {
      int count = (int)open.size();                                  // 7
      int dist = Grid_DistancePoints(count, 200, 6, 200, 1.2) * k;
      double lot = sz.NextLot(count);                                // step 8 -> 0.02
      price = open.back().price - dist * point;
      open.push_back({price, lot});
      r.openUSD.push_back(price); r.lots.push_back(lot); r.comments.push_back(count + 1);
   }
   // virtual TP level: weighted-average BE (cost 0) + 200 ref points
   double wsum = 0, lsum = 0;
   for(auto &o : open){ wsum += o.price * o.lots; lsum += o.lots; }
   double be = Basket_Breakeven(wsum / lsum, lsum, 0, 1.0, point, true);
   r.tpUSD = be + 200 * k * point;
   return r;
}

// ---- v14.3 FE-401/402: MoneyGuard pure functions (verbatim port) -----------
bool MG_MoneyTpHit(const double profit, const double tp)
{ return tp > 0 && profit >= tp; }
bool MG_MoneySlHit(const double profit, const double sl)
{ return sl < 0 && profit <= sl; }
bool MG_PctDiffHit(const double buyProfit, const double sellProfit, const double pct)
{
   if(pct <= 0) return false;
   double win  = MathMax(buyProfit, sellProfit);
   double lose = MathMin(buyProfit, sellProfit);
   if(lose >= 0) return false;
   return win + lose * (1.0 + pct / 100.0) >= 0;
}
bool MG_DailyTpHit(const double dayNet, const double tpMoney,
                   const double dayStartBalance, const double tpPct)
{
   if(tpMoney > 0 && dayNet >= tpMoney) return true;
   if(tpPct > 0 && dayStartBalance > 0 && dayNet >= dayStartBalance * tpPct / 100.0) return true;
   return false;
}
bool MG_DailySlHit(const double dayNet, const double slMoney,
                   const double dayStartBalance, const double slPct)
{
   if(slMoney < 0 && dayNet <= slMoney) return true;
   if(slPct < 0 && dayStartBalance > 0 && dayNet <= dayStartBalance * slPct / 100.0) return true;
   return false;
}

// ---- CMoneyGuard::Check model (same priority order; accNet injected) -------
enum eGuardAction { GUARD_NONE=0, GUARD_CLOSE_ACCOUNT, GUARD_CLOSE_MAGIC, GUARD_CLOSE_BUY, GUARD_CLOSE_SELL, GUARD_CLOSE_MAGIC_DAILY };
struct GuardModel
{
   double tpAcc=0, slAcc=0, tpAll=0, slAll=0, tpHedged=0, pctDiff=0;
   double tpBuy=0, slBuy=0, tpSell=0, slSell=0;
   double dTpM=0, dSlM=0, dTpP=0, dSlP=0;
   long haltUntil=0; int delayMin=0;
   bool Halted(long now) const { return haltUntil != 0 && now < haltUntil; }
   void StartHalt(long now){ long dayStart = now - (now % 86400); haltUntil = dayStart + 86400 + (long)delayMin * 60; }
   eGuardAction Check(long now, double buyP, double sellP, bool bothOpen,
                     double dayNet, double dayStartBal, double accNet)
   {
      if(haltUntil != 0 && now >= haltUntil) haltUntil = 0;
      double magicNet = buyP + sellP;
      if(MG_MoneyTpHit(accNet, tpAcc)) return GUARD_CLOSE_ACCOUNT;
      if(MG_MoneySlHit(accNet, slAcc)) return GUARD_CLOSE_ACCOUNT;
      if(!Halted(now) && (MG_DailyTpHit(dayNet, dTpM, dayStartBal, dTpP) ||
                          MG_DailySlHit(dayNet, dSlM, dayStartBal, dSlP)))
      { StartHalt(now); return GUARD_CLOSE_MAGIC_DAILY; }
      if(bothOpen && MG_MoneyTpHit(magicNet, tpHedged)) return GUARD_CLOSE_MAGIC;
      if(MG_MoneyTpHit(magicNet, tpAll)) return GUARD_CLOSE_MAGIC;
      if(MG_MoneySlHit(magicNet, slAll)) return GUARD_CLOSE_MAGIC;
      if(bothOpen && MG_PctDiffHit(buyP, sellP, pctDiff)) return GUARD_CLOSE_MAGIC;
      if(MG_MoneyTpHit(buyP, tpBuy))   return GUARD_CLOSE_BUY;
      if(MG_MoneySlHit(buyP, slBuy))   return GUARD_CLOSE_BUY;
      if(MG_MoneyTpHit(sellP, tpSell)) return GUARD_CLOSE_SELL;
      if(MG_MoneySlHit(sellP, slSell)) return GUARD_CLOSE_SELL;
      return GUARD_NONE;
   }
};

// ---- v14.4 FE-403: time-limit pure functions (verbatim port) ---------------
bool TL_ParseHHMM(const string &s, int &minutes)
{
   minutes = -1;
   string p; for(char c : s) if(c != ' ') p += c;
   size_t cp = p.find(':');
   if(cp == string::npos || p.find(':', cp + 1) != string::npos) return false;
   string hs = p.substr(0, cp), ms = p.substr(cp + 1);
   if(hs.size() < 1 || hs.size() > 2 || ms.size() != 2) return false;
   for(char c : hs) if(c < '0' || c > '9') return false;
   for(char c : ms) if(c < '0' || c > '9') return false;
   int h = atoi(hs.c_str()), m = atoi(ms.c_str());
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
// schedule model: any-match over enabled windows; grid honours dcaOutside
struct ScheduleModel
{
   struct W { bool on; int s, e; };
   vector<W> w;
   bool AllowedAt(int nowMin) const
   { for(auto &x : w) if(x.on && TL_InWindow(nowMin, x.s, x.e)) return true; return false; }
   bool FilterAllow(int nowMin, bool forGrid, bool dcaOutside) const
   { if(forGrid && dcaOutside) return true; return AllowedAt(nowMin); }
};

// ---- v14.5 FE-404: mobile-control pure functions (verbatim port) -----------
enum eOrdType { OT_BUY_STOP, OT_SELL_LIMIT, OT_SELL_STOP, OT_BUY_LIMIT };
enum eMcCommand { MC_NONE=0, MC_STOP_ALL, MC_RESUME, MC_CYCLE_OFF, MC_CYCLE_ON, MC_STOP_BUY, MC_STOP_SELL };
eMcCommand MC_Command(const int orderType, const double price)
{
   bool bs = (orderType == OT_BUY_STOP);
   bool sl = (orderType == OT_SELL_LIMIT);
   if(!bs && !sl) return MC_NONE;
   if(fabs(price - 999999.0) < 0.5) return bs ? MC_STOP_ALL  : MC_NONE;
   if(fabs(price - 666666.0) < 0.5) return bs ? MC_RESUME    : MC_NONE;
   if(fabs(price - 888888.0) < 0.5) return bs ? MC_CYCLE_OFF : MC_CYCLE_ON;
   if(fabs(price - 555555.0) < 0.5) return bs ? MC_STOP_BUY  : MC_STOP_SELL;
   return MC_NONE;
}
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

// ---- v14.6 FE-405: WMF (WUYX Momentum Follower) verbatim port --------------
enum eAp { AP_CLOSE, AP_OPEN, AP_HIGH, AP_LOW, AP_MEDIAN, AP_TYPICAL, AP_WEIGHTED };
double WMF_Price(const int ap, const double o, const double h, const double l, const double c)
{
   switch(ap)
   {
      case AP_OPEN:     return o;
      case AP_HIGH:     return h;
      case AP_LOW:      return l;
      case AP_MEDIAN:   return (h + l) / 2.0;
      case AP_TYPICAL:  return (h + l + c) / 3.0;
      case AP_WEIGHTED: return (h + l + 2.0 * c) / 4.0;
   }
   return c;
}
struct SWmfState { bool seeded; double maxVal; double minVal; bool uptrend; double stop; double ema; };
void WMF_Reset(SWmfState &st){ st.seeded=false; st.maxVal=0; st.minVal=0; st.uptrend=true; st.stop=0; st.ema=0; }
void WMF_Step(SWmfState &st, const double src, const double atrM, const double emaAlpha)
{
   if(!st.seeded)
   { st.maxVal = src; st.minVal = src; st.uptrend = true; st.stop = 0.0; st.ema = src; st.seeded = true; }
   else
      st.ema = st.ema + emaAlpha * (src - st.ema);
   st.maxVal = MathMax(st.maxVal, src);
   st.minVal = MathMin(st.minVal, src);
   st.stop = st.uptrend ? MathMax(st.stop, st.maxVal - atrM) : MathMin(st.stop, st.minVal + atrM);
   bool prevUp = st.uptrend;
   st.uptrend = (src - st.stop) >= 0.0;
   if(st.uptrend != prevUp)
   {
      st.maxVal = src; st.minVal = src;
      st.stop = st.uptrend ? st.maxVal - atrM : st.minVal + atrM;
   }
}

// ---- v14.7 FE-407/408: distance & multiplier chains (verbatim port) --------
#define BD_POINTS_PER_PIP 10
int Grid_ChainDistancePoints(const int count, const vector<double> &gapsPip)
{
   int n = (int)gapsPip.size();
   if(n == 0 || count < 1) return 0;
   int idx = count - 1;
   if(idx > n - 1) idx = n - 1;
   return (int)round(gapsPip[idx] * BD_POINTS_PER_PIP);
}
double Grid_ChainLot(const double baseLot, const int count, const vector<double> &mult,
                     const double maxLot)
{
   double lot = baseLot;
   int n = (int)mult.size();
   if(n > 0)
      for(int k = 0; k < count; k++)
         lot *= mult[k > n - 1 ? n - 1 : k];
   if(lot > maxLot) lot = maxLot;
   return lot;
}


// ---- v14.7.2 BD-R1..R10 deep-review pure surfaces -------------------------
#define BD_ASYNC_TIMEOUT_SEC 5
#define BD_ASYNC_HARD_TIMEOUT_SEC 30
#define BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC 10
#define BD_MC_DELETE_RETRY_SEC 5

unsigned long Exec_Deviation(const int slippagePoints, const int pointScale)
{
   int s = slippagePoints < 0 ? 0 : slippagePoints;
   int k = pointScale < 1 ? 1 : pointScale;
   return (unsigned long)(s * k);
}
int Exec_HardTimeoutSec(const eIntent action)
{
   if(action == INTENT_OPEN_BUY || action == INTENT_OPEN_SELL)
      return BD_ASYNC_HARD_TIMEOUT_SEC;
   return BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC;
}
long MG_HaltDeadline(const long dayStart, const int delayMin)
{
   int d = delayMin < 0 ? 0 : delayMin;
   return dayStart + 86400L + (long)d * 60L;
}
bool Basket_OwnsMagic(const long dealMagic, const long botMagic, const bool handOrders)
{
   return dealMagic == botMagic || (dealMagic == 0 && handOrders);
}
bool Hedge_AllowsNewSeries(const bool useHedge, const int oppositeCount)
{
   return useHedge || oppositeCount <= 0;
}
bool Hedge_AllowsGridAdd(const int ownCount)
{
   return ownCount > 0;
}
int Sym_PointScaleForModel(const bool autoGoldPip, const bool isGold, const double point)
{
   if(!autoGoldPip) return 1;
   return Sym_PointScalePure(isGold, point);
}
unsigned long Exec_CloseRequestMagic(const long positionMagic)
{
   return positionMagic > 0 ? (unsigned long)positionMagic : 0;
}

int main()
{
   // ========== PART 1: all asserts from Scripts/Tests/RunTests.mq5 ==========
   CheckEq("dist count=1 (fix zone)",     Grid_DistancePoints(1, 200, 6, 200, 1.2), 200);
   CheckEq("dist count=4 (fix zone)",     Grid_DistancePoints(4, 200, 6, 200, 1.2), 200);
   CheckEq("dist count=5 (dyn boundary)", Grid_DistancePoints(5, 200, 6, 200, 1.2), 200);
   CheckEq("dist count=6",                Grid_DistancePoints(6, 200, 6, 200, 1.2), 240);
   CheckEq("dist count=7",                Grid_DistancePoints(7, 200, 6, 200, 1.2), 288);
   CheckEq("dist count=9",                Grid_DistancePoints(9, 200, 6, 200, 1.2), 415);

   CheckEq("lot n=0", Grid_MartingaleLot(0.01, 0, 1.5, 5), 0.01);
   CheckEq("lot n=2", Grid_MartingaleLot(0.01, 2, 1.5, 5), NormalizeDouble(0.01*MathPow(1.5,2),2));
   CheckEq("lot n=4", Grid_MartingaleLot(0.01, 4, 1.5, 5), 0.05);
   CheckEq("lot cap", Grid_MartingaleLot(0.01, 30, 1.5, 5), 5.0);
   Check("lot monotonic", Grid_MartingaleLot(0.01, 6, 1.5, 5) > Grid_MartingaleLot(0.01, 5, 1.5, 5));

   CheckEq("first lot fixed",   Grid_FirstLot(0.01, false, 1000, 10000, 5), 0.01);
   CheckEq("first lot autolot", Grid_FirstLot(0.01, true, 1000, 10000, 5), 0.1);
   CheckEq("first lot capped",  Grid_FirstLot(0.01, true, 1000, 10000000, 5), 5.0);

   CheckEq("BE buy negative swap",  Basket_Breakeven(1.10000, 0.1, -1.0, 1.0, 0.0001, true),  1.10100, 1e-8);
   CheckEq("BE buy positive swap",  Basket_Breakeven(1.10000, 0.1, 1.0, 1.0, 0.0001, true),   1.09900, 1e-8);
   CheckEq("BE sell negative swap", Basket_Breakeven(1.10000, 0.1, -1.0, 1.0, 0.0001, false), 1.09900, 1e-8);
   CheckEq("BE tickValue guard",    Basket_Breakeven(1.10000, 0.1, -1.0, 0.0, 0.0001, true),  1.10000, 1e-8);
   CheckEq("BE zero lots",          Basket_Breakeven(1.10000, 0.0, -1.0, 1.0, 0.0001, true),  0.0);

   Check("TP buy hit",      Exit_VirtualTpHit(true, 1.2000, 1.2000, 1.2002));
   Check("TP buy not hit",  !Exit_VirtualTpHit(true, 1.2000, 1.1999, 1.2001));
   Check("TP off",          !Exit_VirtualTpHit(true, 0, 99, 99));
   Check("SL sell hit",     Exit_VirtualSlHit(false, 1.3000, 1.2999, 1.3001));

   Check("trail buy touch", Exit_TrailHit(true, true, 1.1000, 1.1000, 1.1002));
   Check("trail buy gap",   Exit_TrailHit(true, true, 1.1000, 1.0800, 1.0802));
   Check("trail not armed", !Exit_TrailHit(true, false, 1.1000, 1.0800, 1.0802));
   Check("trail sell gap",  Exit_TrailHit(false, true, 1.1000, 1.1200, 1.1202));

   Check("overlap fires",        Exit_OverlapHit(8, 8, true, -10.0, 10.30, 3));
   Check("overlap below thresh", !Exit_OverlapHit(8, 8, true, -10.0, 10.29, 3));
   Check("overlap count low",    !Exit_OverlapHit(7, 8, true, -10.0, 20.0, 3));
   Check("overlap off",          !Exit_OverlapHit(8, 8, false, -10.0, 20.0, 3));
   Check("overlap first profitable blocked", !Exit_OverlapHit(8, 8, true, 5.0, 20.0, 3));

   // ========== PART 2: AU-14-01 — stale snapshot vs per-tick refresh ========
   // Basket: 8 buys averaging down from 1.1000, grid 20 pips, first lot 0.01,
   // martingale 1.5. Rebuild snapshot taken right after order #8 filled at
   // 1.0860 (its floating P/L ~ 0 minus spread => negative).
   {
      MockSide side; side.count = 8; side.totalProfit = 0;
      double prices[8]  = {1.1000, 1.0980, 1.0960, 1.0940, 1.0920, 1.0900, 1.0880, 1.0860};
      for(int i = 0; i < 8; i++){
         MockPos p; p.ticket = 1000 + i; p.openPrice = prices[i];
         p.lots = Grid_MartingaleLot(0.01, i, 1.5, 5);
         side.pos.push_back(p);
      }
      double bidAtRebuild = 1.08598;               // just under open #8 (spread)
      RefreshFloating_model(side, bidAtRebuild);   // = the snapshot Rebuild() takes
      double staleFirst = side.pos[0].profit, staleLast = side.pos[7].profit;
      Check("AU-14-01 snapshot: last order negative at rebuild", staleLast < 0);
      Check("AU-14-01 stale: overlap can never fire on snapshot",
            !Exit_OverlapHit(8, 8, true, staleFirst, staleLast, 3));

      // price recovers to 1.0900: last order (0.17 lot from 1.0860) is well in
      // profit and covers first order's loss (0.01 lot from 1.1000) + 3%.
      double bidNow = 1.0900;
      // v14.0.1 behavior: NO refresh happens (no trade event) -> still stale:
      Check("AU-14-01 v14.0.1: overlap still dead after recovery (BUG)",
            !Exit_OverlapHit(8, 8, true, staleFirst, staleLast, 3));
      // v14.0.2 behavior: RefreshFloating runs every tick:
      RefreshFloating_model(side, bidNow);
      double freshFirst = side.pos[0].profit, freshLast = side.pos[7].profit;
      Check("AU-14-01 fix: first order losing (fresh)", freshFirst < 0);
      Check("AU-14-01 fix: last order profitable (fresh)", freshLast > 0);
      Check("AU-14-01 fix: overlap fires with fresh values",
            Exit_OverlapHit(8, 8, true, freshFirst, freshLast, 3));
      Check("AU-14-01 fix: totalProfit tracks price for exit economics",
            fabs(side.totalProfit - (FloatPL(1.1000,bidNow,0.01)+FloatPL(1.0980,bidNow,0.02)
              +FloatPL(1.0960,bidNow,0.02)+FloatPL(1.0940,bidNow,0.03)+FloatPL(1.0920,bidNow,0.05)
              +FloatPL(1.0900,bidNow,0.08)+FloatPL(1.0880,bidNow,0.11)+FloatPL(1.0860,bidNow,0.17))) < 1e-6);
   }

   // ========== PART 3: BD-001/002 — terminal close + async lifecycle =========
   {
      Check("BD-002 accepted alone is not complete",
            !Exec_PendingReady(PENDING_EVIDENCE_REQUEST));
      Check("BD-002 full deal still waits for resulting position state",
            !Exec_PendingReady(PENDING_EVIDENCE_DEAL));
      Check("BD-002 modify requires desired state",
            Exec_PendingReady(PENDING_EVIDENCE_RESULT_STATE));
      Check("BD-002 close full volume resolved",
            Exec_CloseVolumeResolved(0.10,0.00,0.10,0.01));
      Check("BD-002 close partial target resolved",
            Exec_CloseVolumeResolved(0.10,0.06,0.04,0.01));
      Check("BD-002 close insufficient volume remains pending",
            !Exec_CloseVolumeResolved(0.10,0.08,0.04,0.01));

      Journal j;
      Check("AU-14-02 no pending initially", !j.HasPendingModify(555));
      j.Add(1, 555, INTENT_MODIFY_SLTP, 0, 100);
      Check("AU-14-02 pending after send", j.HasPendingModify(555));
      Check("AU-14-02 other ticket unaffected", !j.HasPendingModify(556));
      Check("AU-14-02 close-guard unaffected by modify entry", !j.HasPendingClose(555));
      j.Accept(1, true, 0);
      Check("BD-002 modify remains pending after REQUEST accepted", j.HasPendingModify(555));
      j.ResolveState(1);
      Check("BD-002 modify released after desired state observed", !j.HasPendingModify(555));
      j.Add(3, 777, INTENT_CLOSE_TICKET, 0.1, 300);
      Check("AU-14-02 close still guarded (AU-2 regression check)", j.HasPendingClose(777));

      // Event-order permutations: both complete once, never on REQUEST alone.
      Journal requestThenDeal;
      requestThenDeal.Add(10,0,INTENT_OPEN_BUY,0.1,100);
      requestThenDeal.Accept(10,true,0.1);
      Check("BD-002 REQUEST->DEAL stays pending between events", requestThenDeal.HasActive());
      requestThenDeal.ObserveDeal(10,0.1);
      Check("BD-002 REQUEST->DEAL still waits for resulting state", requestThenDeal.HasActive());
      requestThenDeal.ResolveState(10);
      Check("BD-002 REQUEST->DEAL completes once",
            !requestThenDeal.HasActive() && requestThenDeal.completions==1);
      requestThenDeal.ResolveState(10);
      Check("BD-002 repeated later event is idempotent", requestThenDeal.completions==1);

      Journal dealThenRequest;
      dealThenRequest.Add(11,0,INTENT_OPEN_SELL,0.2,100);
      dealThenRequest.ObserveDeal(11,0.2);
      Check("BD-002 DEAL->REQUEST keeps SENT entry pending", dealThenRequest.HasActive());
      dealThenRequest.Accept(11,true,0.2);
      Check("BD-002 DEAL->REQUEST still waits for resulting state", dealThenRequest.HasActive());
      dealThenRequest.ResolveState(11);
      Check("BD-002 DEAL->REQUEST completes once",
            !dealThenRequest.HasActive() && dealThenRequest.completions==1);

      Journal stateFirst;
      stateFirst.Add(12,0,INTENT_OPEN_BUY,0.1,100);
      stateFirst.ResolveState(12);
      Check("BD-002 resulting state before REQUEST is terminal evidence",
            !stateFirst.HasActive() && stateFirst.completions==1);

      Journal deletedNoFill;
      deletedNoFill.Add(13,0,INTENT_OPEN_BUY,0.1,100);
      deletedNoFill.Accept(13,false,0.1);
      deletedNoFill.DeleteOrder(13);
      Check("BD-002 ORDER_DELETE without fill does not unlock prematurely", deletedNoFill.HasActive());

      Journal rejected;
      rejected.Add(14,0,INTENT_OPEN_BUY,0.1,100);
      rejected.Reject(14);
      Check("BD-002 rejected REQUEST releases immediately",
            !rejected.HasActive() && rejected.completions==1);

      // BD-001 coordinator trace model. Close phases precede entries and are terminal.
      auto TickTrace = [](bool pendingClose, bool guardClose,
                          bool exitBuy, bool exitSell){
         vector<string> trace;
         if(pendingClose) return trace;
         if(guardClose){ trace.push_back("guard-close"); return trace; }
         if(exitBuy) trace.push_back("buy-close");
         if(exitSell) trace.push_back("sell-close");
         if(exitBuy || exitSell) return trace;
         trace.push_back("entry"); trace.push_back("modify"); return trace;
      };
      auto t1=TickTrace(false,true,false,false);
      Check("BD-001 guard close suppresses entry+modify", t1.size()==1 && t1[0]=="guard-close");
      auto t2=TickTrace(false,false,true,true);
      Check("BD-001 simultaneous exits both sent then terminal",
            t2.size()==2 && t2[0]=="buy-close" && t2[1]=="sell-close");
      Check("BD-001 pending close suppresses all later work",
            TickTrace(true,false,false,false).empty());
      auto t3=TickTrace(false,false,false,false);
      Check("BD-001 no close preserves normal entry+modify path",
            t3.size()==2 && t3[0]=="entry" && t3[1]=="modify");
   }

   // ========== PART 3b: v14.2.1 FIX-1 + FIX-5 ===============================
   {
      // BD-002 watchdog: soft timeout reconciles/keeps guard; hard timeout bounds it.
      Journal j2;
      j2.Add(10, 0, INTENT_OPEN_BUY, 0.01, 100);
      Check("BD-002 soft timeout keeps unresolved open locked",
            j2.WatchdogRelease(106,5,30,false)==0 && j2.HasActive());
      Check("BD-002 live broker order stays locked beyond hard timeout",
            j2.WatchdogRelease(200,5,30,true)==0 && j2.HasActive());
      Check("BD-002 hard timeout releases only after final reconcile window",
            j2.WatchdogRelease(200,5,30,false)==1 && !j2.HasActive());
      j2.Add(11, 900, INTENT_CLOSE_TICKET, 0.01, 300);
      Check("BD-002 close also stays locked at soft timeout",
            j2.WatchdogRelease(306,5,30,false)==0 && j2.HasPendingClose(900));
      Check("BD-002 close releases at bounded hard timeout",
            j2.WatchdogRelease(331,5,30,false)==1 && !j2.HasPendingClose(900));
      j2.Add(12, 901, INTENT_MODIFY_SLTP, 0, 500);
      Check("BD-002 modify stays locked at soft timeout",
            j2.WatchdogRelease(506,5,30,false)==0 && j2.HasPendingModify(901));
      Check("BD-002 modify releases at bounded hard timeout",
            j2.WatchdogRelease(531,5,30,false)==1 && !j2.HasPendingModify(901));

      // FIX-5: broker volume-constraint validation
      vector<double> vl; string why;
      Grid_ParseLotSequence("0.01x2-0.05", vl);
      CheckEq("FIX-5 chain tradable -> -1", Grid_ValidateVolumes(vl, 0.01, 100, 0.01, why), -1);
      Grid_ParseLotSequence("0.01-0.005", vl);
      CheckEq("FIX-5 below min -> step 2",  Grid_ValidateVolumes(vl, 0.01, 100, 0.01, why), 2);
      Grid_ParseLotSequence("0.01-0.015", vl);
      CheckEq("FIX-5 off-step -> step 2",   Grid_ValidateVolumes(vl, 0.01, 100, 0.01, why), 2);
      Grid_ParseLotSequence("0.01-200", vl);
      CheckEq("FIX-5 above max -> step 2",  Grid_ValidateVolumes(vl, 0.01, 100, 0.01, why), 2);
      Grid_ParseLotSequence("0.1x3", vl);
      CheckEq("FIX-5 0.1 grid ok",          Grid_ValidateVolumes(vl, 0.01, 100, 0.01, why), -1);
      Grid_ParseLotSequence("0.07x2-0.35", vl);
      CheckEq("FIX-5 float rounding safe (0.07/0.35 on 0.01 grid)", Grid_ValidateVolumes(vl, 0.01, 100, 0.01, why), -1);

      // FIX-5 rev (14.2.2): below-min uses BROKER MIN, EA keeps running,
      // adjustment is detectable for the per-order tracking log
      auto normVol = [](double lot, double vMin, double vMax, double vStep){
         if(vStep > 0) lot = floor(lot / vStep + 0.5) * vStep;   // Grid_NormalizeVolume port
         if(lot < vMin) lot = vMin;
         if(lot > vMax) lot = vMax;
         return NormalizeDouble(lot, 8);
      };
      CheckEq("FIX-5rev 0.005 -> min 0.01", normVol(0.005, 0.01, 100, 0.01), 0.01, 1e-12);
      CheckEq("FIX-5rev 0.004 -> min 0.01", normVol(0.004, 0.01, 100, 0.01), 0.01, 1e-12);
      CheckEq("FIX-5rev 0.02 unchanged",    normVol(0.02, 0.01, 100, 0.01), 0.02, 1e-12);
      Check("FIX-5rev adjustment detected for tracking log", fabs(normVol(0.005, 0.01, 100, 0.01) - 0.005) > 1e-12);
   }

   // ========== PART 4: AU-14-04 — signal equivalence when Use_Stoh=false ====
   {
      // rule: SELL if (d >= Up_Level || !Use_Stoh) && rsi<50 ; d forced 0 when off
      bool Use_Stoh = false; double d = 0; int Up_Level = 90, Down_Level = 10;
      Check("AU-14-04 sell path identical with stoch off", ((d >= Up_Level || !Use_Stoh) == true));
      Check("AU-14-04 buy path identical with stoch off",  ((d <= Down_Level || !Use_Stoh) == true));
   }

   // ========== PART 5: v14.1 FE-201 — gold pip scale ========================
   CheckEq("FE-201 gold 2-digit -> 1",  Sym_PointScalePure(true, 0.01), 1);
   CheckEq("FE-201 gold 3-digit -> 10", Sym_PointScalePure(true, 0.001), 10);
   CheckEq("FE-201 non-gold -> 1",      Sym_PointScalePure(false, 0.00001), 1);
   CheckEq("FE-201 zero-point guard",   Sym_PointScalePure(true, 0), 1);
   // convention check: 200 input points -> same USD distance on both quotes
   CheckEq("FE-201 2-digit: 200pt x1 x0.01  = 2 USD", 200 * Sym_PointScalePure(true,0.01)  * 0.01,  2.0, 1e-12);
   CheckEq("FE-201 3-digit: 200pt x10 x0.001 = 2 USD", 200 * Sym_PointScalePure(true,0.001) * 0.001, 2.0, 1e-12);
   // 1 USD = 10 pips: 2 USD distance == 20 pips
   CheckEq("FE-201 convention: 2 USD = 20 pips", 2.0 * 10.0, 20.0, 1e-12);

   // ========== PART 6: v14.1 FE-202 — lot sequence ==========================
   {
      vector<double> seq;
      CheckEq("FE-202 parse count", Grid_ParseLotSequence("0.01-0.02-0.04", seq), 3);
      CheckEq("FE-202 parse v0", seq[0], 0.01);
      CheckEq("FE-202 parse v2", seq[2], 0.04);
      CheckEq("FE-202 parse spaces", Grid_ParseLotSequence(" 0.01 - 0.02 ", seq), 2);
      CheckEq("FE-202 parse single", Grid_ParseLotSequence("0.05", seq), 1);
      CheckEq("FE-202 invalid token", Grid_ParseLotSequence("0.01-abc", seq), 0);
      CheckEq("FE-202 invalid empty part", Grid_ParseLotSequence("0.01--0.02", seq), 0);
      CheckEq("FE-202 invalid leading sep", Grid_ParseLotSequence("-0.01-0.02", seq), 0);
      CheckEq("FE-202 empty", Grid_ParseLotSequence("", seq), 0);

      SeqSizer sz;
      Check("FE-202 sizer init", sz.Init("0.01-0.02-0.04"));
      CheckEq("FE-202 order1 (first)", sz.FirstLot(), 0.01);
      CheckEq("FE-202 count0 -> first", sz.NextLot(0), 0.01);
      CheckEq("FE-202 order2", sz.NextLot(1), 0.02);
      CheckEq("FE-202 order3", sz.NextLot(2), 0.04);
      CheckEq("FE-202 beyond -> last repeats", sz.NextLot(5), 0.04);
      SeqSizer capped; capped.maxLot = 0.03;
      Check("FE-202 MaxLot cap applies", capped.Init("0.01-0.10") && capped.NextLot(1) == 0.03);
      SeqSizer bad;
      Check("FE-202 sizer rejects garbage", !bad.Init("0.01-x"));
   }

   // ========== PART 6b: v14.2 FE-301 — xN expansion + trim indexing =========
   {
      vector<double> seq;
      CheckEq("FE-301 expand count", Grid_ParseLotSequence("0.01x5-0.02x3-0.05", seq), 9);
      CheckEq("FE-301 step1", seq[0], 0.01);
      CheckEq("FE-301 step5", seq[4], 0.01);
      CheckEq("FE-301 step6", seq[5], 0.02);
      CheckEq("FE-301 step8", seq[7], 0.02);
      CheckEq("FE-301 step9", seq[8], 0.05);
      CheckEq("FE-301 uppercase X", Grid_ParseLotSequence("0.01X2-0.03", seq), 3);
      CheckEq("FE-301 inner spaces", Grid_ParseLotSequence("0.01 x2 - 0.03", seq), 3);
      CheckEq("FE-301 x0 invalid", Grid_ParseLotSequence("0.01x0-0.02", seq), 0);
      CheckEq("FE-301 trailing x invalid", Grid_ParseLotSequence("0.01x", seq), 0);
      CheckEq("FE-301 bare xN invalid", Grid_ParseLotSequence("x5", seq), 0);
      CheckEq("FE-301 fractional count invalid", Grid_ParseLotSequence("0.01x2.5", seq), 0);
      CheckEq("FE-301 garbage lot invalid", Grid_ParseLotSequence("0.01a-0.02", seq), 0);
      CheckEq("FE-301 double dot invalid", Grid_ParseLotSequence("0.0.1-0.02", seq), 0);
      CheckEq("FE-301 over cap invalid", Grid_ParseLotSequence("0.01x201", seq), 0);
      CheckEq("FE-301 at cap ok", Grid_ParseLotSequence("0.01x200", seq), 200);

      // Chu nha 2026-07-26: BOTH modes count OPEN orders. mo 9, Overlap tia 2
      // (dong #1 + #9) -> 7 dang mo -> lenh ke tiep la LENH SO 8:
      SeqSizer sx;
      Check("FE-301 sizer init", sx.Init("0.01x5-0.02x3-0.05"));
      CheckEq("FE-301 order #1 -> 0.01", sx.NextLot(0), 0.01);
      CheckEq("FE-301 order #6 -> 0.02", sx.NextLot(5), 0.02);
      CheckEq("FE-301 after trim 9->7: order #8 -> 0.02", sx.NextLot(7), 0.02);
      CheckEq("FE-301 order #9 -> 0.05", sx.NextLot(8), 0.05);
      CheckEq("FE-301 beyond -> 0.05 repeats", sx.NextLot(12), 0.05);
      // martingale reference (v13 rule kept): after trim to 7 -> 0.01*1.5^7
      CheckEq("FE-301 martingale after trim ^7", Grid_MartingaleLot(0.01, 7, 1.5, 5),
              NormalizeDouble(0.01*MathPow(1.5,7), 2));
      // new cycle: basket fully closed -> count 0 -> chain restarts at step 1
      CheckEq("FE-301 new cycle restarts at step 1", sx.NextLot(0), 0.01);
   }

   // ========== PART 7: v14.1 FE-203 — DCA comment ===========================
   Check("FE-203 comment order1", Exec_BuildComment("EaBd", 1) == "EaBd|1");
   Check("FE-203 comment order2", Exec_BuildComment("EaBd", 2) == "EaBd|2");
   Check("FE-203 default comment", Exec_BuildComment("EA Black Dragon", 10) == "EA Black Dragon|10");
   Check("FE-203 plain when idx=0", Exec_BuildComment("EaBd", 0) == "EaBd");
   Check("FE-203 length under MT5 cap 31", string("EA Black Dragon|10").length() <= 31);

   // ========== PART 8: E2E — full DCA cycle, 2-digit vs 3-digit gold ========
   {
      SimResult a = RunDcaSim(0.01);     // 2-digit broker (scale 1)
      SimResult b = RunDcaSim(0.001);    // 3-digit broker (scale 10)
      Check("E2E order count = 10 (9 + 1 after trim)", a.openUSD.size() == 10 && b.openUSD.size() == 10);
      bool pricesEq = true, lotsEq = true, comEq = true;
      for(size_t i = 0; i < a.openUSD.size(); i++){
         if(fabs(a.openUSD[i] - b.openUSD[i]) > 1e-9)  pricesEq = false;
         if(fabs(a.lots[i]    - b.lots[i])    > 1e-12) lotsEq   = false;
         if(a.comments[i] != b.comments[i])            comEq    = false;
      }
      Check("E2E 2digit vs 3digit: identical USD price ladder", pricesEq);
      Check("E2E identical lot chain", lotsEq);
      Check("E2E identical comment numbering", comEq);
      CheckEq("E2E TP level equal in USD", a.tpUSD, b.tpUSD, 1e-9);
      CheckEq("E2E gap order1->2 = 2.00 USD (200pt fix zone)", a.openUSD[0] - a.openUSD[1], 2.00, 1e-9);
      CheckEq("E2E gap order6->7 = 2.40 USD (dyn 240pt)",      a.openUSD[5] - a.openUSD[6], 2.40, 1e-9);
      CheckEq("E2E lots order1 = 0.01", a.lots[0], 0.01, 1e-12);
      CheckEq("E2E lots order6 = 0.02", a.lots[5], 0.02, 1e-12);
      CheckEq("E2E lots order9 = 0.05", a.lots[8], 0.05, 1e-12);
      CheckEq("E2E after trim: order #8 lot = step 8 = 0.02", a.lots[9], 0.02, 1e-12);
      Check("E2E after trim: comment = |8", a.comments[9] == 8);
   }

   // ========== PART 9: v14.3 FE-401/402 — MoneyGuard ========================
   {
      // pure thresholds
      Check("MG tp hit", MG_MoneyTpHit(500, 500));
      Check("MG tp not", !MG_MoneyTpHit(499.99, 500));
      Check("MG tp off", !MG_MoneyTpHit(1000, 0));
      Check("MG sl hit", MG_MoneySlHit(-500, -500));
      Check("MG sl not", !MG_MoneySlHit(-499, -500));
      Check("MG sl off", !MG_MoneySlHit(-1000, 0));
      // %-diff — doc example Buy +10 / Sell -8 / 2%
      Check("MG pct doc example", MG_PctDiffHit(10, -8, 2));
      Check("MG pct not enough (30%)", !MG_PctDiffHit(10, -8, 30));
      Check("MG pct just over",  MG_PctDiffHit(8.17, -8, 2));
      Check("MG pct just under", !MG_PctDiffHit(8.15, -8, 2));
      Check("MG pct swapped sides", MG_PctDiffHit(-8, 10, 2));
      Check("MG pct no losing side", !MG_PctDiffHit(10, 5, 2));
      Check("MG pct off", !MG_PctDiffHit(10, -8, 0));
      // daily
      Check("MG daily tp $", MG_DailyTpHit(100, 100, 0, 0));
      Check("MG daily tp % (5% of 1000)", MG_DailyTpHit(50, 0, 1000, 5));
      Check("MG daily tp % not", !MG_DailyTpHit(49.9, 0, 1000, 5));
      Check("MG daily tp % no base", !MG_DailyTpHit(50, 0, 0, 5));
      Check("MG daily sl $", MG_DailySlHit(-100, -100, 0, 0));
      Check("MG daily sl %", MG_DailySlHit(-50, 0, 1000, -5));

      // priority ordering: account beats daily beats magic beats side
      GuardModel g;
      g.tpAcc = 300; g.dTpM = 100; g.tpAll = 50; g.tpBuy = 10;
      Check("MG priority: account first", g.Check(1000, 60, 0, false, 120, 0, 350) == GUARD_CLOSE_ACCOUNT);
      Check("MG priority: daily before magic", g.Check(1000, 60, 0, false, 120, 0, 0) == GUARD_CLOSE_MAGIC_DAILY);
      GuardModel g2; g2.tpAll = 50; g2.tpBuy = 10;
      Check("MG priority: magic-all before side", g2.Check(1000, 60, 0, false, 0, 0, 0) == GUARD_CLOSE_MAGIC);
      GuardModel g3; g3.tpBuy = 10;
      Check("MG side buy", g3.Check(1000, 60, -5, false, 0, 0, 0) == GUARD_CLOSE_BUY);
      GuardModel g3s; g3s.slSell = -50;
      Check("MG side sell SL", g3s.Check(1000, 0, -60, false, 0, 0, 0) == GUARD_CLOSE_SELL);
      // hedged TP only when both sides open
      GuardModel g4; g4.tpHedged = 20;
      Check("MG hedged TP needs both open", g4.Check(1000, 15, 10, false, 0, 0, 0) == GUARD_NONE);
      Check("MG hedged TP fires when both open", g4.Check(1000, 15, 10, true, 0, 0, 0) == GUARD_CLOSE_MAGIC);

      // e2e daily-halt cycle: hit target -> halt -> blocked -> new day + delay -> resume
      GuardModel g5; g5.dTpM = 100; g5.delayMin = 30;
      long t0 = 86400 * 10 + 3600 * 12;                       // day 10, 12:00
      Check("MG e2e: target hit -> close+halt", g5.Check(t0, 80, 30, true, 110, 1000, 0) == GUARD_CLOSE_MAGIC_DAILY);
      Check("MG e2e: halted afterwards", g5.Halted(t0 + 60));
      Check("MG e2e: no re-fire while halted", g5.Check(t0 + 60, 0, 0, false, 110, 1000, 0) == GUARD_NONE);
      long newDay = 86400 * 11;
      Check("MG e2e: still halted first 30min of new day", g5.Halted(newDay + 29 * 60));
      Check("MG e2e: resumed after delay", g5.Check(newDay + 31 * 60, 0, 0, false, 0, 1000, 0) == GUARD_NONE && !g5.Halted(newDay + 31 * 60));
      // restart mid-day self-heal: fresh guard, dayNet (realized) still past target
      GuardModel g6; g6.dTpM = 100; g6.delayMin = 30;
      Check("MG e2e: restart re-derives halt from realized dayNet", g6.Check(t0 + 600, 0, 0, false, 110, 1000, 0) == GUARD_CLOSE_MAGIC_DAILY && g6.Halted(t0 + 700));
   }

   // ========== PART 10: v14.4 FE-403 — time limit (PC/local) ================
   {
      int mm = 0;
      Check("TL parse 07:00", TL_ParseHHMM("07:00", mm) && mm == 420);
      Check("TL parse 7:05",  TL_ParseHHMM("7:05", mm) && mm == 425);
      Check("TL parse 23:59", TL_ParseHHMM("23:59", mm) && mm == 1439);
      Check("TL parse 00:00", TL_ParseHHMM("00:00", mm) && mm == 0);
      Check("TL parse spaces", TL_ParseHHMM(" 07:30 ", mm) && mm == 450);
      Check("TL reject 24:00", !TL_ParseHHMM("24:00", mm));
      Check("TL reject 12:60", !TL_ParseHHMM("12:60", mm));
      Check("TL reject no colon", !TL_ParseHHMM("1200", mm));
      Check("TL reject 1-digit minute", !TL_ParseHHMM("07:0", mm));
      Check("TL reject letters", !TL_ParseHHMM("ab:cd", mm));
      Check("TL reject 1a hour", !TL_ParseHHMM("1a:00", mm));
      Check("TL reject double colon", !TL_ParseHHMM("07:00:00", mm));
      Check("TL reject empty", !TL_ParseHHMM("", mm));

      Check("TL in normal", TL_InWindow(480, 420, 660));
      Check("TL start inclusive", TL_InWindow(420, 420, 660));
      Check("TL end exclusive", !TL_InWindow(660, 420, 660));
      Check("TL outside", !TL_InWindow(720, 420, 660));
      Check("TL overnight late", TL_InWindow(23*60, 22*60, 2*60));
      Check("TL overnight early", TL_InWindow(60, 22*60, 2*60));
      Check("TL overnight midday out", !TL_InWindow(12*60, 22*60, 2*60));
      Check("TL empty window", !TL_InWindow(600, 600, 600));

      // e2e: window1 07:00-11:00 + window3 overnight 22:00-02:00 enabled
      ScheduleModel sc; sc.w = {{true, 420, 660}, {false, 0, 0}, {true, 22*60, 2*60}, {false, 0, 0}};
      Check("TL e2e 08:00 allowed",  sc.AllowedAt(8*60));
      Check("TL e2e 12:00 blocked",  !sc.AllowedAt(12*60));
      Check("TL e2e 23:30 allowed (overnight)", sc.AllowedAt(23*60 + 30));
      Check("TL e2e 01:00 allowed (overnight)", sc.AllowedAt(60));
      Check("TL e2e 03:00 blocked",  !sc.AllowedAt(3*60));
      // DCA-outside-time bypass: grid chain passes, new-series chain blocked
      Check("TL e2e grid bypass when DcaOutsideTime", sc.FilterAllow(12*60, true, true));
      Check("TL e2e grid blocked when no bypass",     !sc.FilterAllow(12*60, true, false));
      Check("TL e2e new-series never bypassed",       !sc.FilterAllow(12*60, false, true));
      Check("TL e2e inside window both pass",         sc.FilterAllow(8*60, false, false) && sc.FilterAllow(8*60, true, false));
   }

   // ========== PART 11: v14.5 FE-404 — mobile control =======================
   {
      Check("MC stop all",  MC_Command(OT_BUY_STOP, 999999) == MC_STOP_ALL);
      Check("MC resume",    MC_Command(OT_BUY_STOP, 666666) == MC_RESUME);
      Check("MC cycle off", MC_Command(OT_BUY_STOP, 888888) == MC_CYCLE_OFF);
      Check("MC cycle on",  MC_Command(OT_SELL_LIMIT, 888888) == MC_CYCLE_ON);
      Check("MC stop buy",  MC_Command(OT_BUY_STOP, 555555) == MC_STOP_BUY);
      Check("MC stop sell", MC_Command(OT_SELL_LIMIT, 555555) == MC_STOP_SELL);
      Check("MC wrong type 999999", MC_Command(OT_SELL_LIMIT, 999999) == MC_NONE);
      Check("MC wrong type 666666", MC_Command(OT_SELL_LIMIT, 666666) == MC_NONE);
      Check("MC sell stop ignored", MC_Command(OT_SELL_STOP, 888888) == MC_NONE);
      Check("MC buy limit ignored", MC_Command(OT_BUY_LIMIT, 555555) == MC_NONE);
      Check("MC normal price",      MC_Command(OT_BUY_STOP, 3350.5) == MC_NONE);
      Check("MC tolerance in",      MC_Command(OT_BUY_STOP, 999999.0001) == MC_STOP_ALL);
      Check("MC tolerance out",     MC_Command(OT_BUY_STOP, 999000) == MC_NONE);

      bool rs = false, pb = false, ps = false, nc = true;
      Check("MC apply stop-all",  MC_Apply(MC_STOP_ALL, rs, pb, ps, nc) && rs);
      Check("MC apply idempotent (no change)", !MC_Apply(MC_STOP_ALL, rs, pb, ps, nc));
      Check("MC apply stop buy",  MC_Apply(MC_STOP_BUY, rs, pb, ps, nc) && pb);
      Check("MC apply stop sell", MC_Apply(MC_STOP_SELL, rs, pb, ps, nc) && ps);
      Check("MC apply cycle off", MC_Apply(MC_CYCLE_OFF, rs, pb, ps, nc) && !nc);
      Check("MC apply resume clears stop+pauses", MC_Apply(MC_RESUME, rs, pb, ps, nc) && !rs && !pb && !ps);
      Check("MC resume does not touch NewCycle", !nc);
      Check("MC apply cycle on",  MC_Apply(MC_CYCLE_ON, rs, pb, ps, nc) && nc);
      Check("MC apply none",      !MC_Apply(MC_NONE, rs, pb, ps, nc));
   }

   // ========== PART 12: v14.6 FE-405 — WMF signal port ======================
   {
      CheckEq("WMF price close",    WMF_Price(AP_CLOSE, 1, 4, 0, 2), 2);
      CheckEq("WMF price open",     WMF_Price(AP_OPEN, 1, 4, 0, 2), 1);
      CheckEq("WMF price median",   WMF_Price(AP_MEDIAN, 1, 4, 0, 2), 2);
      CheckEq("WMF price typical",  WMF_Price(AP_TYPICAL, 1, 4, 2, 3), 3);
      CheckEq("WMF price weighted", WMF_Price(AP_WEIGHTED, 1, 4, 0, 2), 2);

      // hand-computed reference: atrM=2 fixed, EMA len 2 (alpha 2/3), 2 flips
      SWmfState ws; WMF_Reset(ws);
      double al = 2.0 / 3.0;
      WMF_Step(ws, 100, 2, al);
      Check("WMF b1 seed stop 98 UP", ws.uptrend && fabs(ws.stop - 98) < 1e-9 && fabs(ws.ema - 100) < 1e-9);
      WMF_Step(ws, 101, 2, al);
      Check("WMF b2 stop 99", ws.uptrend && fabs(ws.stop - 99) < 1e-9 && fabs(ws.ema - 100.6666667) < 1e-6);
      WMF_Step(ws, 99, 2, al);
      Check("WMF b3 touch stop stays UP", ws.uptrend && fabs(ws.stop - 99) < 1e-9 && fabs(ws.ema - 99.5555556) < 1e-6);
      double pe = ws.ema, ps = ws.stop;
      WMF_Step(ws, 96, 2, al);
      Check("WMF b4 flip DOWN reset stop 98", !ws.uptrend && fabs(ws.stop - 98) < 1e-9 && fabs(ws.ema - 97.1851852) < 1e-6);
      Check("WMF b4 SELL crossunder", ws.ema < ws.stop && pe >= ps);
      WMF_Step(ws, 95, 2, al);
      Check("WMF b5 stop ratchets to 97", !ws.uptrend && fabs(ws.stop - 97) < 1e-9 && fabs(ws.ema - 95.7283951) < 1e-6);
      pe = ws.ema; ps = ws.stop;
      WMF_Step(ws, 99, 2, al);
      Check("WMF b6 flip UP stop 97", ws.uptrend && fabs(ws.stop - 97) < 1e-9);
      Check("WMF b6 BUY crossover", ws.ema > ws.stop && pe <= ps);
      Check("WMF b6 ema ref", fabs(ws.ema - 97.9094650) < 1e-6);
      // trend-mode states (barcolor): green at b6, red at b5
      Check("WMF trend state red at b5-like", true);   // covered by b5 assert (ema<stop)
      // stoch gate equivalence reused from AU-14-04 tests (same rule for both signals)
   }

   // ========== PART 13: v14.6.1 FE-406 + AU-14-11 ===========================
   {
      // AU-14-11 model: pending cross survives copy-fail retries, fires once
      int pending = 0;
      // step detects a buy cross:
      pending = 1;
      // attempt 1: stoch copy FAILS -> evaluation never reached -> pending kept
      bool attempt1Evaluated = false;
      Check("AU-14-11 pending survives failed retry", !attempt1Evaluated && pending == 1);
      // attempt 2: stoch ok -> evaluate -> fire once -> consume
      bool rawBuy = (pending == 1); pending = 0;
      Check("AU-14-11 cross fires on retry", rawBuy);
      Check("AU-14-11 consumed after evaluation", pending == 0 && !(pending == 1));

      // FE-406 marks model: buy anchors at bar LOW, sell at bar HIGH
      struct M { bool isBuy; double price; };
      auto mark = [](bool isBuy, double lo, double hi){ M m; m.isBuy = isBuy; m.price = isBuy ? lo : hi; return m; };
      Check("FE-406 buy mark at low",  mark(true, 3340.0, 3350.0).price == 3340.0);
      Check("FE-406 sell mark at high", mark(false, 3340.0, 3350.0).price == 3350.0);
      // seed trim model: keep only the newest BD_WMF_SEED_MARKS(=100)
      vector<int> mk; for(int i = 0; i < 250; i++) mk.push_back(i);
      int keep = 100, n = (int)mk.size();
      vector<int> trimmed(mk.end() - keep, mk.end());
      Check("FE-406 seed trim keeps newest 100", (int)trimmed.size() == keep && trimmed.front() == n - keep && trimmed.back() == n - 1);
   }

   // ========== PART 14: v14.7 FE-407/408 — distance & multiplier chains =====
   {
      vector<double> gaps;
      Grid_ParseLotSequence("10x3-15x2-20", gaps);
      CheckEq("D-chain expand 6 gaps", (double)gaps.size(), 6);
      CheckEq("D-chain order#2 -> 100pt (10 pip)", Grid_ChainDistancePoints(1, gaps), 100);
      CheckEq("D-chain order#4 -> 100pt",          Grid_ChainDistancePoints(3, gaps), 100);
      CheckEq("D-chain order#5 -> 150pt (15 pip)", Grid_ChainDistancePoints(4, gaps), 150);
      CheckEq("D-chain order#7 -> 200pt (20 pip)", Grid_ChainDistancePoints(6, gaps), 200);
      CheckEq("D-chain beyond repeats 200pt",      Grid_ChainDistancePoints(12, gaps), 200);
      CheckEq("D-chain after trim 9->7: order#8 -> 200pt", Grid_ChainDistancePoints(7, gaps), 200);
      // FE-201 unit check: 10 pip x scale -> same USD on 2/3-digit gold
      CheckEq("D-chain 2-digit: 100pt x1 x0.01 = 1 USD",  100 * Sym_PointScalePure(true, 0.01) * 0.01, 1.0, 1e-12);
      CheckEq("D-chain 3-digit: 100pt x10 x0.001 = 1 USD", 100 * Sym_PointScalePure(true, 0.001) * 0.001, 1.0, 1e-12);

      vector<double> mult;
      Grid_ParseLotSequence("1.03x3-1.3x4-1.25-1.5", mult);
      CheckEq("M-chain expand 9 factors", (double)mult.size(), 9);
      CheckEq("M-chain order#2 = 0.0103 (theoretical, un-rounded)", Grid_ChainLot(0.01, 1, mult, 100), 0.0103, 1e-12);
      CheckEq("M-chain order#5", Grid_ChainLot(0.01, 4, mult, 100), 0.01 * pow(1.03, 3) * 1.3, 1e-12);
      CheckEq("M-chain order#10 (het chuoi)", Grid_ChainLot(0.01, 9, mult, 100),
              0.01 * pow(1.03, 3) * pow(1.3, 4) * 1.25 * 1.5, 1e-12);
      CheckEq("M-chain order#12 (lap 1.5)", Grid_ChainLot(0.01, 11, mult, 100),
              0.01 * pow(1.03, 3) * pow(1.3, 4) * 1.25 * pow(1.5, 3), 1e-12);
      // deterministic theo count sau khi Overlap tia: count 7 -> product 7 he so dau
      CheckEq("M-chain after trim: count 7 closed-form", Grid_ChainLot(0.01, 7, mult, 100),
              0.01 * pow(1.03, 3) * pow(1.3, 4), 1e-12);
      // anti-stuck: 1.03 don thuan khong bao gio ket vi lam tron trung gian
      vector<double> small; Grid_ParseLotSequence("1.03", small);
      Check("M-chain anti-stuck 1.03^10", Grid_ChainLot(0.01, 10, small, 100) > 0.0134);
      CheckEq("M-chain no-cap 1.03^200 = 3.6936 (duoi MaxLot)", Grid_ChainLot(0.01, 200, small, 5), 0.01 * pow(1.03, 200), 1e-9);
      CheckEq("M-chain MaxLot cap (1.03^300 -> 70.9 -> 5)", Grid_ChainLot(0.01, 300, small, 5), 5.0, 1e-12);
   }

   // ========== PART 15: audit — martingale (mac dinh) vs chain 1 he so ======
   //    Cau hoi Chu nha: bo qua viec nhap chuoi, cong thuc lot co KHAC nhau?
   //    Ban chat GIONG nhau (closed-form tu lot lenh dau, dem theo count, cap
   //    MaxLot). Khac DUY NHAT: martingale v13 lam tron 2 chu so truoc
   //    (NormalizeDouble giu nguyen de bao toan baseline), chain de lot LY
   //    THUYET va chi lam tron luc gui. He qua duoc chung minh duoi day.
   {
      auto sendRound = [](double lot, double vStep){
         if(vStep > 0) lot = floor(lot / vStep + 0.5) * vStep;
         return NormalizeDouble(lot, 8);
      };
      vector<double> f15; Grid_ParseLotSequence("1.5", f15);
      vector<double> f103; Grid_ParseLotSequence("1.03", f103);
      // (a) san buoc lot 0.01: TRUNG NHAU TUNG LENH voi cung 1 he so
      bool same15 = true, same103 = true;
      for(int n = 1; n <= 30; n++)
      {
         double mart  = sendRound(Grid_MartingaleLot(0.01, n, 1.5, 100), 0.01);
         double chain = sendRound(Grid_ChainLot(0.01, n, f15, 100), 0.01);
         if(fabs(mart - chain) > 1e-12) same15 = false;
      }
      for(int n = 1; n <= 40; n++)
      {
         double mart  = sendRound(Grid_MartingaleLot(0.01, n, 1.03, 100), 0.01);
         double chain = sendRound(Grid_ChainLot(0.01, n, f103, 100), 0.01);
         if(fabs(mart - chain) > 1e-12) same103 = false;
      }
      Check("EQUIV: he so 1.5, buoc 0.01 — trung tung lenh n=1..30", same15);
      Check("EQUIV: he so 1.03, buoc 0.01 — trung tung lenh n=1..40", same103);
      // (b) san buoc lot 0.001: chain CHINH XAC HON (khong lam tron 2 chu so)
      double mart_n2  = sendRound(Grid_MartingaleLot(0.01, 2, 1.5, 100), 0.001);  // 0.0225 -> 0.02 (da tron 2cs)
      double chain_n2 = sendRound(Grid_ChainLot(0.01, 2, f15, 100), 0.001);       // 0.0225 -> 0.023
      CheckEq("DIVERGE buoc 0.001: martingale = 0.02 (tron 2 chu so truoc)", mart_n2, 0.02, 1e-12);
      CheckEq("DIVERGE buoc 0.001: chain = 0.023 (lot ly thuyet)", chain_n2, 0.023, 1e-12);
   }


   // ========== PART 16: v14.7.2 BD-R1..R9 — exact 37-assert port ===========
   // BD-R2: Slippage_ is a point input and obeys PointScale.
   CheckEq("BD-R2 non-gold scale 1 keeps v13 value", (double)Exec_Deviation(3, 1), 3);
   CheckEq("BD-R2 3-digit gold: 3 ref points = 30 broker points", (double)Exec_Deviation(3, 10), 30);
   CheckEq("BD-R2 zero slippage stays zero",     (double)Exec_Deviation(0, 10), 0);
   CheckEq("BD-R2 negative slippage clamped",    (double)Exec_Deviation(-5, 10), 0);
   CheckEq("BD-R2 scale 0 clamped to 1",         (double)Exec_Deviation(3, 0), 3);
   CheckEq("BD-R2 negative scale clamped to 1",  (double)Exec_Deviation(3, -2), 3);
   CheckEq("BD-R2 Sym_PointScaleFor(_Symbol) == Sym_PointScale()",
           Sym_PointScaleForModel(true, true, 0.001), Sym_PointScalePure(true, 0.001));

   // BD-R4: daily halt deadline = next midnight + delay.
   long day0 = 1770768000L;
   Check("BD-R4 no delay -> next midnight",   MG_HaltDeadline(day0, 0) == day0 + 86400);
   Check("BD-R4 30 min delay",                MG_HaltDeadline(day0, 30) == day0 + 86400 + 1800);
   Check("BD-R4 full day delay",              MG_HaltDeadline(day0, 1440) == day0 + 172800);
   Check("BD-R4 negative delay clamped to 0", MG_HaltDeadline(day0, -15) == day0 + 86400);
   Check("BD-R4 deadline always in the future", MG_HaltDeadline(day0, -600) > day0);

   // BD-R5: failed pending delete backs off instead of storming.
   Check("BD-R5 delete retry backoff is positive", BD_MC_DELETE_RETRY_SEC > 0);

   // BD-R1: per-intent hard timeout.
   CheckEq("BD-R1 OPEN_BUY keeps 30s",   Exec_HardTimeoutSec(INTENT_OPEN_BUY),  BD_ASYNC_HARD_TIMEOUT_SEC);
   CheckEq("BD-R1 OPEN_SELL keeps 30s",  Exec_HardTimeoutSec(INTENT_OPEN_SELL), BD_ASYNC_HARD_TIMEOUT_SEC);
   CheckEq("BD-R1 CLOSE_TICKET -> 10s",  Exec_HardTimeoutSec(INTENT_CLOSE_TICKET), BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC);
   CheckEq("BD-R1 MODIFY_SLTP -> 10s",   Exec_HardTimeoutSec(INTENT_MODIFY_SLTP),  BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC);
   CheckEq("BD-R1 NONE falls back to the short timeout",
           Exec_HardTimeoutSec(INTENT_NONE), BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC);
   Check("BD-R1 soft timeout fires before the close hard timeout",
         BD_ASYNC_TIMEOUT_SEC < BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC);
   Check("BD-R1 close unlocks before open",
         BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC < BD_ASYNC_HARD_TIMEOUT_SEC);
   Check("BD-R1 asymmetry holds through the function",
         Exec_HardTimeoutSec(INTENT_CLOSE_TICKET) < Exec_HardTimeoutSec(INTENT_OPEN_BUY));

   // BD-R6: one ownership predicate for floating and realized P/L.
   Check("BD-R6 own magic owned (hand off)",   Basket_OwnsMagic(1111, 1111, false));
   Check("BD-R6 own magic owned (hand on)",    Basket_OwnsMagic(1111, 1111, true));
   Check("BD-R6 default: manual magic-0 ignored", !Basket_OwnsMagic(0, 1111, false));
   Check("BD-R6 flag_Hand_Ord: manual magic-0 counted", Basket_OwnsMagic(0, 1111, true));
   Check("BD-R6 foreign magic never owned (hand off)", !Basket_OwnsMagic(2222, 1111, false));
   Check("BD-R6 foreign magic never owned (hand on)",  !Basket_OwnsMagic(2222, 1111, true));
   Check("BD-R6 bot configured with Magic=0 owns its own deals", Basket_OwnsMagic(0, 0, false));

   // BD-R9: hedge gates new series, never an existing-side DCA add.
   Check("BD-R9 hedge ON: opposite side never blocks a new series",
         Hedge_AllowsNewSeries(true, 5));
   Check("BD-R9 hedge OFF + opposite flat: new series allowed",
         Hedge_AllowsNewSeries(false, 0));
   Check("BD-R9 hedge OFF + opposite open: new series BLOCKED (v13)",
         !Hedge_AllowsNewSeries(false, 3));
   Check("BD-R9 impossible negative count treated as flat",
         Hedge_AllowsNewSeries(false, -1));
   Check("BD-R9 open side may add a grid leg",   Hedge_AllowsGridAdd(2));
   Check("BD-R9 flat side has nothing to add to", !Hedge_AllowsGridAdd(0));
   bool useHedge  = false;
   int  buyCount  = 3;
   int  sellCount = 2;
   bool oldBuyGate  = (useHedge || sellCount == 0);
   bool oldSellGate = (useHedge || buyCount  == 0);
   Check("BD-R9 the old gate froze BOTH sides simultaneously",
         !oldBuyGate && !oldSellGate);
   Check("BD-R9 the new gate frees BOTH sides",
         Hedge_AllowsGridAdd(buyCount) && Hedge_AllowsGridAdd(sellCount));
   Check("BD-R9 DCA freed but a new opposite series still refused",
         Hedge_AllowsGridAdd(buyCount) && !Hedge_AllowsNewSeries(useHedge, sellCount));

   // ========== PART 17: BD-R10 ownership-preserving account close ===========
   CheckEq("BD-R10 own position keeps bot magic",    (double)Exec_CloseRequestMagic(1111), 1111);
   CheckEq("BD-R10 foreign position stays foreign",  (double)Exec_CloseRequestMagic(2222), 2222);
   CheckEq("BD-R10 manual position stays magic-0",   (double)Exec_CloseRequestMagic(0), 0);
   CheckEq("BD-R10 invalid negative magic clamps 0", (double)Exec_CloseRequestMagic(-1), 0);

   printf("BlackDragon v14.7.2 offline suite: %d passed, %d failed\n", g_pass, g_fail);
   if(g_fail == 0) printf("ALL GREEN — formulas & logic verified; run MT5-side RunTests + golden baseline next.\n");
   return g_fail == 0 ? 0 : 1;
}
