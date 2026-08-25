//+------------------------------------------------------------------+
//| Config.mqh — BlackDragon v14.9.0                                 |
//| Purpose   : ALL user inputs + named constants. No trade logic.   |
//| Invariants: retained input identifiers/default meanings stay     |
//|             stable unless explicitly migrated by release notes.  |
//| v14.9.0  : DCA lot uses manual lot or multiplier chains only;    |
//|             distance uses one pip chain and repeats its last gap.|
//+------------------------------------------------------------------+
#ifndef BD_CONFIG_MQH
#define BD_CONFIG_MQH
#include "UnitSystem.mqh"

enum eModeStops
{
   mode_Real, // Thật — đặt mức SL/TP tại broker
   mode_Virt  // Ảo — EA tự theo dõi và đóng rổ
};
enum eExecMode
{
   exec_Sync, // Đồng bộ
   exec_Async // Bất đồng bộ
};
enum eLotMode
{
   lot_Sequence        = 1, // Chuỗi Lot thủ công
   lot_MultiplierChain = 2  // Chuỗi hệ số nhân
};
enum eSignalSource
{
   sig_BD, // Black Dragon RSI
   sig_WMF // WUYX Momentum Follower
};
enum eWmfMode
{
   wmf_Cross, // Cross — chỉ khi có giao cắt
   wmf_Trend  // Trend — theo trạng thái xu hướng
};
enum eNewsFailMode
{
   news_fail_TradeOn, // Không có dữ liệu → tiếp tục giao dịch
   news_fail_PauseNew // Không có dữ liệu → dừng mở lệnh tự động
};

input group "01 — Vận hành chung & định danh EA"
input bool   NewCycle_        = true;   // Mặc định cho phép EA mở chuỗi mới
input bool   Flag_Trade_Buy_  = true;   // Mặc định cho phép mở chuỗi Buy mới
input bool   Flag_Trade_Sell_ = true;   // Mặc định cho phép mở chuỗi Sell mới
input bool   flag_Hand_Ord    = false;  // Gộp lệnh tay Magic 0 vào rổ EA
input bool   Flag_Use_hedge   = true;   // Cho phép mở chuỗi mới khi có rổ đối diện
input string sOrdComm         = "EA Black Dragon"; // Nội dung comment của lệnh
input int    Magic            = 1111;   // Magic Number của EA

input group "02 — Nguồn tín hiệu & Black Dragon"
input eSignalSource   SignalSource_ = sig_BD;         // Nguồn tín hiệu mở chuỗi
input ENUM_TIMEFRAMES TF_DB         = PERIOD_CURRENT; // Khung thời gian tín hiệu Black Dragon

input group "03 — Xác nhận Stochastic"
input bool            Use_Stoh    = false;          // Dùng Stochastic xác nhận tín hiệu
input ENUM_TIMEFRAMES TF_Stoh     = PERIOD_CURRENT; // Khung thời gian Stochastic
input int             Up_Level    = 90;             // Ngưỡng Stochastic xác nhận Sell
input int             Down_Level  = 10;             // Ngưỡng Stochastic xác nhận Buy
input int             KPeriod     = 7;              // Chu kỳ %K của Stochastic
input int             DPeriod     = 1;               // Chu kỳ %D của Stochastic
input int             Slowing     = 2;              // Hệ số Slowing của Stochastic

input group "04 — Tín hiệu WMF"
input eWmfMode           WmfMode        = wmf_Cross;      // Chế độ phát tín hiệu WMF
input ENUM_TIMEFRAMES    WmfTF          = PERIOD_CURRENT; // Khung thời gian WMF
input int                WmfLength      = 20;             // Chu kỳ ATR của WMF
input ENUM_APPLIED_PRICE WmfPrice       = PRICE_CLOSE;    // Nguồn giá tính WMF
input double             WmfFactor      = 1.0;            // Hệ số ATR của WMF
input int                WmfEmaLength   = 2;              // Chu kỳ EMA của WMF
input bool               ShowWmfSignals = true;           // Vẽ mũi tên tín hiệu WMF trên chart

input group "05 — Quản lý Lot & giới hạn rổ"
input int      MaxOrdersBuy    = 10;                  // Số lệnh Buy tối đa trong rổ
input int      MaxOrdersSell   = 10;                  // Số lệnh Sell tối đa trong rổ
input eLotMode LotMode_        = lot_MultiplierChain; // Chế độ tính Lot DCA
input double   Lot_Init_       = 0.01;                // Lot cơ sở / Lot mặc định nút Open
input bool     Autolot_        = false;               // Tự tính Lot đầu theo Free Margin
input int      Autolotsize_    = 1000;                // Free Margin tương ứng mỗi 0.01 Lot
input string   LotSequence_    = "";                  // Chuỗi Lot thủ công; hết chuỗi lặp Lot cuối
input string   MartinSequence_ = "1.5";               // Chuỗi hệ số nhân; hết chuỗi lặp hệ số cuối
input double   MaxLot_         = 5;                   // Lot tối đa cho mỗi lệnh

input group "06 — Khoảng cách DCA"
input int    MinuteStop        = 0;                         // Delay tối thiểu giữa các ADD DCA/Pyramid Core/bậc Hedge Pyramid (phút); 0 = tắt
input string DistanceSequence_ = "20x5-24-28.8-34.6-41.5"; // DCA: pip thật ở PIP_UNIFIED; bridge cũ ở LEGACY_COMPAT

input group "07 — TP / SL / Trailing / Overlap"
input eModeStops TP_Mode       = mode_Virt; // Chế độ Take Profit của rổ
input double     TP_           = 200.0;     // Legacy: point chuẩn; PIP_UNIFIED: pip
input eModeStops SL_Mode       = mode_Virt; // Chế độ Stop Loss của rổ
input double     SL_           = 0.0;       // Legacy: point chuẩn; PIP_UNIFIED: pip
input eModeStops Trail_Mode    = mode_Virt; // Chế độ Trailing Stop của rổ
input double     iTS           = 0.0;       // Legacy: point chuẩn; PIP_UNIFIED: pip
input double     iTD           = 100.0;     // Legacy: point chuẩn; PIP_UNIFIED: pip
input bool       Overlap       = true;      // Bật chốt cặp lệnh đầu-cuối (Overlap)
input int        OverlapOrderNumber = 8;    // Bắt đầu Overlap từ số lệnh
input double     OverlapPercent     = 3.0;  // Biên lợi nhuận thêm khi Overlap (%)
input bool       UseCommissionInBE  = false;// Tính commission vào giá hòa vốn

input group "08 — Chốt lời/lỗ theo tiền"
input double PctDiffClose      = 0.0; // Đóng hai rổ theo tỷ lệ bù lời/lỗ (%)
input double MoneyTPAllAccount = 0.0; // TP floating toàn tài khoản ($)
input double MoneySLAllAccount = 0.0; // SL floating toàn tài khoản ($, nhập âm)
input double MoneyTPAll        = 0.0; // TP floating tổng rổ của Magic ($)
input double MoneySLAll        = 0.0; // SL floating tổng rổ của Magic ($, nhập âm)
input double MoneyTPBuy        = 0.0; // TP floating riêng rổ Buy ($)
input double MoneySLBuy        = 0.0; // SL floating riêng rổ Buy ($, nhập âm)
input double MoneyTPSell       = 0.0; // TP floating riêng rổ Sell ($)
input double MoneySLSell       = 0.0; // SL floating riêng rổ Sell ($, nhập âm)
input double MoneyTPAllHedged  = 0.0; // TP floating khi đồng thời có Buy + Sell ($)

input group "09 — Mục tiêu & giới hạn theo ngày"
input double DailyTPMoney   = 0.0; // Mục tiêu lãi ngày theo tiền ($)
input double DailySLMoney   = 0.0; // Giới hạn lỗ ngày theo tiền ($, nhập âm)
input double DailyTPPercent = 0.0; // Mục tiêu lãi ngày theo số dư đầu ngày (%)
input double DailySLPercent = 0.0; // Giới hạn lỗ ngày theo số dư đầu ngày (%, nhập âm)
input int    NewDayDelayMin = 0;   // Phút chờ sau 00:00 ngày mới trước khi chạy lại

input group "10 — Bộ lọc mở chuỗi mới"
input int    MaxSpred     = 0;     // Legacy: point chuẩn; PIP_UNIFIED: pip; 0 = tắt
input bool   UseAdxFilter = false; // Dùng ADX lọc mở chuỗi mới
input int    AdxPeriod    = 14;    // Chu kỳ ADX trên timeframe chart
input double MinAdx       = 20.0;  // ADX tối thiểu để mở chuỗi mới

input group "11 — Lịch giao dịch theo giờ máy tính"
input bool   UseTimeLimit   = false;   // Bật lịch giao dịch theo giờ máy tính
input bool   UseTime1       = true;    // Bật khung giờ 1
input string Time1Start     = "07:00"; // Khung 1 — giờ bắt đầu (HH:MM)
input string Time1End       = "11:00"; // Khung 1 — giờ kết thúc (HH:MM)
input bool   UseTime2       = false;   // Bật khung giờ 2
input string Time2Start     = "13:00"; // Khung 2 — giờ bắt đầu (HH:MM)
input string Time2End       = "17:00"; // Khung 2 — giờ kết thúc (HH:MM)
input bool   UseTime3       = false;   // Bật khung giờ 3
input string Time3Start     = "19:00"; // Khung 3 — giờ bắt đầu (HH:MM)
input string Time3End       = "23:00"; // Khung 3 — giờ kết thúc (HH:MM)
input bool   UseTime4       = false;   // Bật khung giờ 4
input string Time4Start     = "00:00"; // Khung 4 — giờ bắt đầu (HH:MM)
input string Time4End       = "06:00"; // Khung 4 — giờ kết thúc (HH:MM)
input bool   DcaOutsideTime = false;   // Cho phép DCA ngoài các khung giờ trên

input group "12 — Bộ lọc tin tức"
input bool Flag_Use_News = false; // Bật dừng mở lệnh tự động theo tin tức
input bool Imp3High      = false; // Lọc tin mức Cao
input bool Imp2Med       = false; // Lọc tin mức Trung bình
input bool Imp1Low       = false; // Lọc tin mức Thấp
input int  b3_           = 60;    // Dừng trước tin Cao (phút)
input int  a3_           = 60;    // Dừng sau tin Cao (phút)
input int  b2_           = 15;    // Dừng trước tin Trung bình (phút)
input int  a2_           = 15;    // Dừng sau tin Trung bình (phút)
input int  b1_           = 5;     // Dừng trước tin Thấp (phút)
input int  a1_           = 5;     // Dừng sau tin Thấp (phút)
input eNewsFailMode NewsFailMode = news_fail_TradeOn; // Xử lý khi lịch tin không có dữ liệu

input group "13 — Khớp lệnh & chuẩn hóa broker"
input eExecMode ExecMode    = exec_Async; // Chế độ gửi lệnh Sync / Async
input eUnitSystemMode UnitSystemMode_ = unit_LEGACY_COMPAT; // Legacy .set hoặc chuẩn hóa toàn bộ theo pip
input int       Slippage_   = 3;          // Legacy: point chuẩn; PIP_UNIFIED: pip
input bool      AutoGoldPip = true;       // Chỉ áp dụng trong LEGACY_COMPAT

input group "14 — Điều khiển từ MT5 Mobile"
input bool UseMobileControl = true; // Bật điều khiển EA từ MT5 Mobile

input group "15 — Panel & hiển thị chart"
input int    X1_          = 10;            // Vị trí Panel theo trục X
input int    Y1_          = 25;            // Vị trí Panel theo trục Y
input bool   fDraw        = true;          // Hiển thị Panel và đối tượng trên chart
input int    FontSizeMark = 13;            // Cỡ chữ thông tin
input string FontNameMark = "Verdana";     // Font chữ thông tin
input color  ColorText    = clrWhite;      // Màu chữ thông tin
input color  ColorFonRec  = clrDarkViolet; // Màu nền nút Pause khi bình thường
input int    FontSizeButt = 11;            // Cỡ chữ nút điều khiển
input string FontNameButt = "Verdana";     // Font chữ nút điều khiển
input color  ColorButt    = clrWhite;      // Màu chữ nút điều khiển
input color  cCIP         = clrGray;       // Màu nền Panel

#define BD_VERSION            "14.9.0"
#define BD_STATE_FILE_SUFFIX  "_BD_v14.bin"
#define BD_OBJ_PREFIX         "ke_EA_BD_"
#define BD_OBJ_PREFIX_REZ     "ke_Rez_EA_BD_"
#define BD_MAX_SEND_RETRIES   3
#define BD_ASYNC_TIMEOUT_SEC  5
#define BD_ASYNC_HARD_TIMEOUT_SEC 30
#define BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC 10
#define BD_NEWS_REFRESH_SEC   3600
#define BD_PANEL_TIMER_MS     500
#define BD_MAX_LOT_STEPS      200
#define BD_WMF_MARKS_MAX      200
#define BD_MC_DELETE_RETRY_SEC 5
#define BD_RSI_PERIOD         50
#define BD_RSI_OVER           50
#define BD_UNIT_POLICY_REV     1

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
   double MaxLot;
   double TP;
   double SL;
   double TrailStart;
   double TrailDistance;
   eUnitSystemMode UnitMode;
   double Point;
   double TickSize;
   double PipSize;
   double LegacyPointSize;
   double TPPrice;
   double SLPrice;
   double TrailStartPrice;
   double TrailDistancePrice;
   double MaxSpreadPrice;
   double SlippagePrice;
   double DcaInputUnitPrice;
   int    X1;
   int    Y1;
   double EditLot;
   int    PointScale;
   bool   RemoteStop;
   datetime HaltUntil;
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
   Cfg.MaxLot        = MaxLot_;
   Cfg.TP            = TP_;
   Cfg.SL            = SL_;
   Cfg.TrailStart    = iTS;
   Cfg.TrailDistance = iTD;
   Cfg.UnitMode       = UnitSystemMode_;
   Cfg.Point          = 0.0;
   Cfg.TickSize       = 0.0;
   Cfg.PipSize        = 0.0;
   Cfg.LegacyPointSize = 0.0;
   Cfg.TPPrice        = 0.0;
   Cfg.SLPrice        = 0.0;
   Cfg.TrailStartPrice = 0.0;
   Cfg.TrailDistancePrice = 0.0;
   Cfg.MaxSpreadPrice = 0.0;
   Cfg.SlippagePrice = 0.0;
   Cfg.DcaInputUnitPrice = 0.0;
   Cfg.X1            = X1_;
   Cfg.Y1            = Y1_;
   Cfg.EditLot       = Lot_Init_;
   Cfg.PointScale    = 1;
   Cfg.RemoteStop    = false;
   Cfg.HaltUntil     = 0;
}

void Config_ApplyPointScale(const int scale)
{
   Cfg.PointScale = scale < 1 ? 1 : scale;
   if(Cfg.PointScale == 1) return;
   Cfg.TP            *= Cfg.PointScale;
   Cfg.SL            *= Cfg.PointScale;
   Cfg.TrailStart    *= Cfg.PointScale;
   Cfg.TrailDistance *= Cfg.PointScale;
}

bool Config_BindUnitProfile(const bool isGold, const double point, const int digits,
                            const double tickSize, string &why)
{
   SUnitProfile p;
   if(!Unit_BuildProfilePure(isGold, point, digits, tickSize, AutoGoldPip, p, why))
      return false;
   Config_ApplyPointScale(Unit_LegacyPointScalePure(isGold, point, AutoGoldPip));
   Cfg.UnitMode        = UnitSystemMode_;
   Cfg.Point           = p.point;
   Cfg.TickSize        = p.tickSize;
   Cfg.PipSize         = p.pipSize;
   Cfg.LegacyPointSize = p.legacyPointSize;
   Cfg.TPPrice         = Unit_ConfigDistancePricePure(TP_, UnitSystemMode_, p.legacyPointSize, p.pipSize);
   Cfg.SLPrice         = Unit_ConfigDistancePricePure(SL_, UnitSystemMode_, p.legacyPointSize, p.pipSize);
   Cfg.TrailStartPrice = Unit_ConfigDistancePricePure(iTS, UnitSystemMode_, p.legacyPointSize, p.pipSize);
   Cfg.TrailDistancePrice = Unit_ConfigDistancePricePure(iTD, UnitSystemMode_, p.legacyPointSize, p.pipSize);
   Cfg.MaxSpreadPrice  = Unit_ConfigDistancePricePure((double)MaxSpred, UnitSystemMode_, p.legacyPointSize, p.pipSize);
   Cfg.SlippagePrice   = Unit_ConfigDistancePricePure((double)Slippage_, UnitSystemMode_, p.legacyPointSize, p.pipSize);
   Cfg.DcaInputUnitPrice = Unit_DcaDistancePricePure(1.0, UnitSystemMode_, p.legacyPointSize, p.pipSize);
   return true;
}
#endif // BD_CONFIG_MQH
