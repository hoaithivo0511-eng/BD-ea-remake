//+------------------------------------------------------------------+
//| Config.mqh — BlackDragon v14.0.0                                 |
//| Purpose   : ALL inputs + named constants. No logic.              |
//| Invariants: Input names/defaults identical to v13 for .set        |
//|             compatibility and baseline comparison.               |
//| Depends on: (nothing)                                            |
//| KHONG DUOC DOI: default values of strategy inputs.               |
//+------------------------------------------------------------------+
#ifndef BD_CONFIG_MQH
#define BD_CONFIG_MQH

enum eModeStops { mode_Real, mode_Virt };
enum eExecMode { exec_Sync, exec_Async };            // NEW v14 (Plan cu - Nhom B)
enum eLotMode { lot_Multiplier, lot_Sequence, lot_MultiplierChain };  // FE-301 + FE-408 (v14.7: chuoi he so nhan)
enum eDistanceMode { dist_Classic, dist_Manual };    // v14.7 FE-407: khoang cach DCA
enum eSignalSource { sig_BD, sig_WMF };              // v14.6 FE-405: entry signal source
enum eWmfMode { wmf_Cross, wmf_Trend };              // v14.6 FE-405: BUY/SELL labels vs barcolor state
enum eNewsFailMode { news_fail_TradeOn, news_fail_PauseNew }; // NEW v14 (Nhom D)

input string qw0 = "//--- Basic parameters ---//";
input bool   NewCycle_        = true;   // Open new series
input bool   Flag_Trade_Buy_  = true;   // Trade Buy
input bool   Flag_Trade_Sell_ = true;   // Trade Sell
input bool   flag_Hand_Ord    = false;  // Manage manual orders
input bool   Flag_Use_hedge   = true;   // Use hedge
input string sOrdComm         = "EA Black Dragon"; // Order Comment
input int    MaxSpred         = 0;      // Max spread (0 - not use)
input int    Start_Hour       = 0;      // Start Hour
input int    End_Hour         = 0;      // End Hour
input int    Magic            = 1111;

input string qw1 = "//--- Black Dragon parametrs ---//";
input ENUM_TIMEFRAMES TF_DB   = PERIOD_CURRENT; // TF Black Dragon

input string qw2 = "//--- Modified_stochastic---//";
input bool   Use_Stoh    = false; // Use stochastic
input ENUM_TIMEFRAMES TF_Stoh = PERIOD_CURRENT; // TF
input int    Up_Level    = 90;   // Up level
input int    Down_Level  = 10;   // Down level
input int    KPeriod     = 7;
input int    DPeriod     = 1;
input int    Slowing     = 2;

input string qw3 = "//--- Strategy Settings ---//";
input int    MaxOrdersBuy   = 10;    // Max buy orders
input int    MaxOrdersSell  = 10;    // Max sell orders
input double Lot_Init_      = 0.01;  // Initial lot
input bool   Autolot_       = false; // Autolot
input int    Autolotsize_   = 1000;  // Autolot size. Free margin for each 0.01 Lots
input double Martin_        = 1.5;   // Lot Multiplier
input double MaxLot_        = 5;     // Max Lot
input eModeStops TP_Mode    = mode_Virt; // TP Mode
input int    TP_            = 200;   // TP (0 - not use)
input eModeStops SL_Mode    = mode_Virt; // SL Mode
input int    SL_            = 0;     // SL (0 - not use)
input eModeStops Trail_Mode = mode_Virt; // Trail Mode
input int    iTS            = 0;     // Trail Start, points (0 - not use)
input int    iTD            = 100;   // Trail Distance, points
input bool   Overlap             = true; // Overlap Last order
input int    OverlapOrderNumber  = 8;    // Overlap last order number
input int    OverlapPercent      = 3;    // Overlap percent
input int    MinuteStop          = 0;    // Pause between orders (min. 0 - not use)

input string qw4 = "//--- Distance settings ---//";
input int    Fix_Distance           = 200; // Fix distance
input int    Order_dinamic_distance = 6;   // Order dinamic distance
input int    Dynamic_distance_start = 200; // Dynamic distance start
input double Distance_multiplier    = 1.2; // Distance multiplier

input string qw5 = "//--- News Setting ---//";
input bool Flag_Use_News = false; // Use News (built-in MQL5 Calendar)
input bool Imp3High      = false; // High impact
input bool Imp2Med       = false; // Medium impact
input bool Imp1Low       = false; // Low impact
input int  b3_ = 60; // Pause before a high importance news
input int  a3_ = 60; // Pause after a high importance news
input int  b2_ = 15; // Pause before a medium importance news
input int  a2_ = 15; // Pause after a medium importance news
input int  b1_ = 5;  // Pause befor a low importance news
input int  a1_ = 5;  // Pause after a low importance news
input eNewsFailMode NewsFailMode = news_fail_TradeOn; // NEW v14: behavior when calendar has no data

input string qw6 = "//--- Panel Parametrs ---//";
input int    X1_ = 10;
input int    Y1_ = 25;
input bool   fDraw        = true; // Draw on-off
input int    FontSizeMark = 13;
input string FontNameMark = "Verdana";
input color  ColorText    = clrWhite;
input color  ColorFonRec  = clrDarkViolet;
input int    FontSizeButt = 11;
input string FontNameButt = "Verdana";
input color  ColorButt    = clrWhite;
input color  cCIP         = clrGray; // Info panel background color

input string qw7 = "//--- v14 Engine ---//";
input eExecMode ExecMode          = exec_Async; // FIX-2 (14.2.1): default Async (live/demo; tester auto-falls back to sync)
input int    Slippage_            = 3;         // Slippage, points (AU-14-06; v13 hardcoded 3)
input bool   UseCommissionInBE    = false;     // Include commission in breakeven (bug#3 full fix)
input bool   UseAdxFilter         = false;     // Sample extension filter (P5)
input int    AdxPeriod            = 14;
input double MinAdx               = 20.0;

input string qw9 = "//--- v14.3 Money Close (FE-401, theo CCBSN manual) ---//";
input double PctDiffClose        = 0;   // % lai/lo giua Buy va Sell de Close All (0 = off)
input double MoneyTPAllAccount   = 0;   // Money TP toan account, $ (0 = off)
input double MoneySLAllAccount   = 0;   // Money SL toan account, -$ (0 = off)
input double MoneyTPAll          = 0;   // Money TP cung Magic, $
input double MoneySLAll          = 0;   // Money SL cung Magic, -$
input double MoneyTPBuy          = 0;   // Money TP rieng Buy, $
input double MoneySLBuy          = 0;   // Money SL rieng Buy, -$
input double MoneyTPSell         = 0;   // Money TP rieng Sell, $
input double MoneySLSell         = 0;   // Money SL rieng Sell, -$
input double MoneyTPAllHedged    = 0;   // Money TP All khi CA Buy va Sell cung mo, $

input string qw14 = "//--- v14.7 DCA Distance & Multiplier chains (FE-407/408) ---//";
input eDistanceMode DistanceMode_ = dist_Classic; // FE-407: Classic (fix+dynamic v13) / Manual chain theo pip
input string DistanceSequence_    = "";           // FE-407: chuoi pip "10x3-15x2-20" (1 pip = 10 point chuan FE-201)
input string MartinSequence_      = "";           // FE-408: chuoi he so "1.03x3-1.3x4-1.25-1.5" (LotMode = Multiplier chain)

input string qw13 = "//--- v14.6 Signal Source & WMF (FE-405) ---//";
input eSignalSource SignalSource_ = sig_BD;      // FE-405: signal mo lenh (BD RSI / WMF)
input eWmfMode WmfMode            = wmf_Cross;   // WMF: Cross (nhan BUY/SELL) / Trend (mau nen xanh/do)
input ENUM_TIMEFRAMES WmfTF       = PERIOD_CURRENT; // WMF TF
input int    WmfLength            = 20;          // WMF Length (ATR, minval 2 nhu Pine)
input ENUM_APPLIED_PRICE WmfPrice = PRICE_CLOSE; // WMF Source (Pine src)
input double WmfFactor            = 1.0;         // WMF Multiplier (ATR factor)
input int    WmfEmaLength         = 2;           // WMF EMA Length
input bool   ShowWmfSignals       = true;        // FE-406: ve mui ten BUY/SELL cua WMF len chart

input string qw12 = "//--- v14.5 Mobile Control (FE-404) ---//";
input bool   UseMobileControl = true;   // FE-404: dieu khien tu xa qua lenh cho gia dac biet (999999/666666/888888/555555)

input string qw11 = "//--- v14.4 Time Limit (FE-403, gio PC/Local) ---//";
input bool   UseTimeLimit    = false;   // FE-403: bat lich giao dich theo khung gio (gio PC/Local)
input bool   UseTime1        = true;    // khung 1 on/off
input string Time1Start      = "07:00"; // "HH:MM"
input string Time1End        = "11:00";
input bool   UseTime2        = false;   // khung 2 on/off
input string Time2Start      = "13:00";
input string Time2End        = "17:00";
input bool   UseTime3        = false;   // khung 3 on/off
input string Time3Start      = "19:00";
input string Time3End        = "23:00";
input bool   UseTime4        = false;   // khung 4 on/off
input string Time4Start      = "00:00";
input string Time4End        = "06:00";
input bool   DcaOutsideTime  = false;   // FE-403: van cho phep DCA grid add ngoai khung gio

input string qw10 = "//--- v14.3 Daily Target (FE-402) ---//";
input double DailyTPMoney        = 0;   // Muc tieu loi nhuan ngay, $ (0 = off)
input double DailySLMoney        = 0;   // Gioi han thua lo ngay, -$ (0 = off)
input double DailyTPPercent      = 0;   // Muc tieu loi nhuan ngay, % so du dau ngay
input double DailySLPercent      = 0;   // Gioi han thua lo ngay, -% so du dau ngay
input int    NewDayDelayMin      = 0;   // So phut nghi dau ngay moi sau khi dat target

input string qw8 = "//--- v14.1 Lot & Pip ---//";
input eLotMode LotMode_           = lot_Multiplier; // FE-301: DCA lot mode (xLot multiplier / manual sequence)
input string LotSequence_         = "";        // FE-202/301: "0.01-0.02-0.04" or "0.01x5-0.02x3-0.05"
input bool   AutoGoldPip          = true;      // FE-201: gold 1 USD = 10 pips; auto scale point-inputs on 3-digit quotes

//--- Named constants (was: magic numbers) --------------------------
#define BD_VERSION            "14.7.1"
#define BD_STATE_FILE_SUFFIX  "_BD_v14.bin"
#define BD_OBJ_PREFIX         "ke_EA_BD_"
#define BD_OBJ_PREFIX_REZ     "ke_Rez_EA_BD_"
#define BD_MAX_SEND_RETRIES   3      // was: hardcoded 3 in Trade()
#define BD_ASYNC_TIMEOUT_SEC  5      // watchdog: reconcile if no server reply
#define BD_ASYNC_HARD_TIMEOUT_SEC 30 // BD-002: conservative final unlock after reconciliation
#define BD_NEWS_REFRESH_SEC   3600   // refresh calendar cache hourly
#define BD_PANEL_TIMER_MS     500    // UI refresh cadence (C3)
#define BD_LOT_DIGITS         2      // was: NormalizeDouble(lot,2)
#define BD_MAX_LOT_STEPS      200    // FE-301: lot-chain cap after xN expansion (FIX-6: moved from GridEngine)
#define BD_WMF_MARKS_MAX      200    // FE-406: max BUY/SELL arrows kept on the chart (ring)
#define BD_POINTS_PER_PIP     10     // FE-407: 1 pip = 10 reference points (FE-201 convention)

//--- Signal behavior kept hardcoded exactly like v13 ----------------
// (v13 hardcodes: SignalBar=Closed — evaluated on closed bar only, see
//  SignalEngine; flag_Close_ot_Obr=false — no close-on-reverse-signal.
//  AU-14-09: unused enum/defines documenting this removed as dead code.)
#define BD_RSI_PERIOD   50
#define BD_RSI_OVER     50

//--- Mutable runtime copies (panel can change these at runtime) -----
struct SConfig
{
   bool   NewCycle;
   bool   TradeBuy;
   bool   TradeSell;
   bool   PauseBuy;
   bool   PauseSell;
   double LotInit;
   bool   Autolot;
   int    Autolotsize;
   double Martin;
   double MaxLot;
   int    TP;
   int    SL;
   int    TrailStart;
   int    TrailDistance;
   int    X1;
   int    Y1;
   double EditLot;   // manual-order lot from panel
   int    PointScale; // FE-201: broker points per reference point (gold 3-digit: 10, else 1)
   bool   RemoteStop; // FE-404: mobile STOP ALL (999999) — blocks every automated open
};
SConfig Cfg;

void Config_Init()
{
   Cfg.NewCycle      = NewCycle_;
   Cfg.TradeBuy      = Flag_Trade_Buy_;
   Cfg.TradeSell     = Flag_Trade_Sell_;
   Cfg.PauseBuy      = false;
   Cfg.PauseSell     = false;
   Cfg.LotInit       = Lot_Init_;
   Cfg.Autolot       = Autolot_;
   Cfg.Autolotsize   = Autolotsize_;
   Cfg.Martin        = Martin_;
   Cfg.MaxLot        = MaxLot_;
   Cfg.TP            = TP_;
   Cfg.SL            = SL_;
   Cfg.TrailStart    = iTS;
   Cfg.TrailDistance = iTD;
   Cfg.X1            = X1_;
   Cfg.Y1            = Y1_;
   Cfg.EditLot       = Lot_Init_;
   Cfg.PointScale    = 1;
   Cfg.RemoteStop    = false;
}

//--- FE-201: multiply every point-based runtime value ONCE at init.
//    Grid distances (inputs, immutable) and MaxSpred are scaled at their
//    usage sites via Cfg.PointScale instead. Call right after Config_Init.
void Config_ApplyPointScale(const int scale)
{
   Cfg.PointScale = scale < 1 ? 1 : scale;
   if(Cfg.PointScale == 1) return;
   Cfg.TP            *= Cfg.PointScale;
   Cfg.SL            *= Cfg.PointScale;
   Cfg.TrailStart    *= Cfg.PointScale;
   Cfg.TrailDistance *= Cfg.PointScale;
}
#endif // BD_CONFIG_MQH
