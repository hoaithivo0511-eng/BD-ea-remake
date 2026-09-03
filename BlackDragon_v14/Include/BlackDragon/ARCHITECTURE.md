# EA BlackDragon v15.00 / T17.18 — ARCHITECTURE.md

> **Đọc file này trước khi sửa bất kỳ dòng code nào.** Các tên T16/T17.x
> trong file/class là lớp compatibility đang được composition hiện hành dùng,
> không phải nhiều bản EA có thể xóa độc lập.

## 1. Tổng quan

- **Composition hiện hành:** signal → Core/DCA/Pyramid → Recovery ARCS/Hedge
  Pyramid → Overlap/MoneyGuard → ExecutionLayer, với persistence và journal
  fail-closed.
- **T17.18:** dashboard/button cũ đã được gỡ; WMF signal arrows được tách vào
  overlay riêng. T17.17 exact ARCS broker-SL ownership và verified account-flat reset
  không được làm coordinator starvation; T17.16 giữ shared NO_MONEY embargo
  và stage-gate replay sau Hedge rebase.
- Input/default và behavior cũ chỉ được đổi qua spec/decision/contract mới.

## 2. Luồng dữ liệu một chiều (bất khả xâm phạm)

```
Tick → BuildContext() → EAContext (read-only cho engines)
     → SignalEngine.Compute()  → ctx.signalBuy/signalSell
     → BasketManager.Update()  → BasketState (chỉ BasketManager được ghi)
     → Strategy.OnTick()       → quyết định (dùng EntryFilters, GridEngine, ExitEngine)
     → ExecutionLayer          → nơi DUY NHẤT gọi OrderSend/OrderSendAsync
     → OnTradeTransaction      → BasketManager.Invalidate() → rebuild cache
```

Quy tắc cứng:
1. Engine **không được ghi** vào `EAContext`.
2. Chỉ `BasketManager` được ghi `BasketSide`.
3. Chỉ `WmfSignalOverlay.mqh` được đụng chart objects, và chỉ được vẽ mũi tên WMF.
4. Chỉ `ExecutionLayer` được gọi trade API. Không module nào khác gọi `OrderSend*`.
5. Không thêm biến global mới — thêm field vào struct/class sở hữu tương ứng.
6. Vùng đánh dấu `[STRATEGY-BEHAVIOR]` là hành vi chiến lược: KHÔNG sửa khi refactor. Muốn hành vi khác → viết implementation mới qua interface.
7. Cache (C1) chỉ được giữ dữ liệu TĨNH theo sự kiện (ticket, lots, giá mở, thời gian mở). Mọi giá trị biến thiên theo giá — profit, swap — phải đọc tươi mỗi tick qua `RefreshFloating()` (bài học AU-14-01: cache profit làm Overlap tê liệt).
8. Mọi distance input phải chuyển đúng một lần sang price qua `UnitSystem.mqh`; không nhân `Cfg.PointScale` tại consumer. Broker deviation/stops đổi sang broker points ở execution boundary; cash dùng tick size + tick value.
9. Thứ tự lệnh DCA (lot bậc mấy, comment `|n`) đếm theo số lệnh ĐANG MỞ (`side.count`) — Overlap tỉa xong thì thứ tự lùi tương ứng. Đây là quyết định của Chủ nhà 26/07/2026, đã có test chốt — không "sửa giùm" sang đếm tổng.
10. Mọi close intent (Money Guard, TP/SL/trail/Overlap) là **terminal cho tick hiện tại**. Có thể gửi close cho cả BUY và SELL trước khi return, nhưng tuyệt đối không mở/DCA/modify phía sau.
11. Async REQUEST accepted **không phải completion**. Pending journal chỉ nhả khi kết quả position/SLTP đã quan sát được, request bị reject, hoặc hard-timeout đã đối soát; transaction có thể đến khác thứ tự. Hard-timeout là **theo intent** (BD-R1, v14.7.2): CLOSE/MODIFY idempotent nên nhả sau 10s, OPEN giữ 30s vì nhả sớm có thể nhân đôi lệnh thật.

## 3. Tính năng → File

| Tính năng | File | Ghi chú |
|---|---|---|
| Inputs, hằng số | `Config.mqh` | Input giao dịch giữ nguyên; 11 input dashboard được retire ở T17.18 |
| Struct chung + interfaces | `Types.mqh` | `ISignal`, `IEntryFilter`, `ILotSizer` |
| Tín hiệu RSI/Stoch | `SignalEngine.mqh` | 1 lần/nến đóng |
| Khoảng cách grid, lot martingale | `GridEngine.mqh` | Hàm thuần, có unit test |
| Cache vị thế, breakeven, mức TP/SL/trail | `BasketManager.mqh` | Event-driven rebuild; trail extreme là session state (BD-R3) |
| Quyết định thoát (TP/SL/trail ảo, Overlap) | `ExitEngine.mqh` | Hàm thuần, có unit test |
| Filter giờ/spread/pause/news | `EntryFilters.mqh` | Chain đăng ký trong `Strategy.Init()` |
| Gửi/đóng lệnh, retry, async journal | `ExecutionLayer.mqh` | Async mặc định live/demo; tester tự fallback sync; lifecycle SENT→ACCEPTED→state observed; hard-timeout theo intent (`Exec_HardTimeoutSec`) |
| Lịch tin (MQL5 Calendar) | `NewsCalendar.mqh` | Refresh trong OnTimer, không block tick |
| WMF signal arrows | `WmfSignalOverlay.mqh` | Overlay tùy chọn qua `ShowWmfSignals`; không dashboard/button/event |
| Lưu/khôi phục trạng thái runtime | `Persistence.mqh` | Mobile pause/NewCycle/RemoteStop + halt; giữ reserved slot byte-compatible |
| Khóa tài khoản | `License.mqh` | Giữ nguyên semantics v13 (mặc định mở) |
| Điều phối tổng | `Strategy.mqh` | Composition root; nơi đăng ký mọi behavior |
| Filter mở rộng mẫu (ADX) | `Filters/AdxFilter.mqh` | P5 demo, mặc định OFF |
| Chế độ lot DCA: martingale / chuỗi xN (FE-301) | `GridEngine.mqh` | `CMartingaleSizer` / `CSequenceSizer` qua `ILotSizer`; chọn theo `LotMode_` trong OnInit; parser `Grid_ParseLotSequence` |
| Unit migration point/pip/tick T17.10 | `UnitSystem.mqh` + `Config.mqh` | `LEGACY_COMPAT` giữ `.set` cũ; `PIP_UNIFIED` opt-in; mọi consumer dùng canonical price |
| Comment `\|n` theo thứ tự DCA (FE-203) | `ExecutionLayer.mqh` | `Exec_BuildComment`; index = số lệnh ĐANG MỞ + 1 (quyết định Chủ nhà 26/07/2026) |
| Money TP/SL đa scope + %-diff close (FE-401) | `MoneyGuard.mqh` | Hàm thuần MG_* + `CMoneyGuard.Check()` — CHỈ trả quyết định, Strategy thực thi; đóng toàn account qua `ExecutionLayer.CloseAllAccount` |
| Daily target + halt + delay ngày mới (FE-402) | `MoneyGuard.mqh` + `BasketManager.mqh` | dayNet = DayProfit + floating; `DayStartBalance()`; `CHaltFilter` đăng ký cả 2 chain qua `AddNewSeriesFilter`/`AddGridFilter`; deadline thuần `MG_HaltDeadline` + persist qua `Cfg.HaltUntil` (BD-R4) |
| Giới hạn thời gian giờ PC/Local, 4 khung (FE-403) | `EntryFilters.mqh` | `TL_ParseHHMM`/`TL_InWindow` (thuần) + `CTimeSchedule` + `CTimeFilter`; đăng ký 2 chain khi `UseTimeLimit=true`; grid chain tôn trọng `DcaOutsideTime`; chỉ chặn MỞ lệnh — exits không đi qua chain |
| Mobile Control qua lệnh chờ giá đặc biệt (FE-404) | `MobileControl.mqh` | `MC_Command`/`MC_Apply` (thuần) + `CMobileControl.Scan` trong OnTimer; ghi cờ runtime RemoteStop/Pause/NewCycle; xóa lệnh chờ qua `ExecutionLayer.DeleteOrder` có backoff `BD_MC_DELETE_RETRY_SEC`; persist BD16 |
| WMF Signal — port TradingView (FE-405) | `WmfSignal.mqh` | `WMF_Step`/`WMF_Price` (thuần, test đối chiếu tính tay) + `CWmfSignal : ISignal`; chọn qua `SignalSource_` trong OnInit (con trỏ ISignal); stoch confirm nhân bản y luật BD; seed 1000 nến, re-seed khi gap |
| Chuỗi khoảng cách DCA theo pip (FE-407/T17.10) | `GridEngine.mqh` | `Grid_ChainDistancePrice` + `CDistancePlan`; legacy giữ bridge 10 reference-point, unified dùng symbol pip-size |
| Chuỗi hệ số nhân — lot lý thuyết (FE-408) | `GridEngine.mqh` | `Grid_ChainLot` (thuần, công thức đóng, không làm tròn trung gian) + `CChainSizer : ILotSizer`; base = pos[0].lots như martingale v13; đếm bậc theo lệnh ĐANG MỞ |
| Quyền sở hữu lệnh (magic bot vs lệnh tay) | `BasketManager.mqh` | `Basket_OwnsMagic` (thuần) — định nghĩa DUY NHẤT, dùng chung cho position scan, `SeedDayProfit()` và booking realized trong `OnTradeTransaction` (BD-R6) |
| Unit tests | `Scripts/BlackDragon/Tests/RunTests.mq5` | Chạy như Script; **số assert do chính script in ra ở dòng cuối** — đừng cứng hóa con số trong tài liệu (v14.7.2 thêm 28 assert cho BD-R1…R8). Bản port C++ chạy ngoài MT5: `Tests/offline_suite.cpp` |

## 4. Điểm mở rộng (P5)

- **Thêm filter vào lệnh:** class mới implement `IEntryFilter` trong `Include/BlackDragon/Filters/` + 1 dòng `g_strategy.AddNewSeriesFilter(new CMyFilter())` trong `BlackDragon.mq5` OnInit + input bật/tắt trong `Config.mqh`. Xem `AdxFilter.mqh` làm mẫu.
- **Đổi cách tính lot:** class mới implement `ILotSizer`, truyền vào `g_strategy.Init(...)`. `CMartingaleSizer` giữ nguyên làm default.
- **Đổi tín hiệu:** class mới implement `ISignal` thay `CRsiStochSignal` trong `BlackDragon.mq5`.

## 5. Gating chi tiết (đối chiếu v13 — đọc kỹ trước khi "sửa bug" nhầm)

- Filter giờ + spread chỉ áp cho **lệnh đầu chuỗi** (v13 OPEN_ORDERS). Grid add chỉ bị chặn bởi: pause, news, 1 lệnh/nến/hướng, MinuteStop, MaxOrders, busy-slot async.
- `Start_Hour==0 || End_Hour==0` → filter giờ tắt (quirk v13, giữ nguyên).
- Stochastic mặc định OFF (`Use_Stoh=false`) → chỉ RSI quyết định.
- SL mặc định 0 (OFF), trailing mặc định 0 (OFF) — TP ảo + Overlap là cơ chế thoát chính.

## 6. Quy trình sửa code (cho AI và người)

1. Đọc file này → xác định file đích từ bảng mục 3.
2. Đọc header contract của file đích (Purpose/Invariants/KHONG DUOC DOI).
3. Sửa nhỏ nhất có thể, không đụng vùng `[STRATEGY-BEHAVIOR]`.
4. Chạy `Tests/RunTests.mq5` → phải ALL GREEN.
5. Backtest đối chiếu golden baseline (xem README mục Baseline).
6. Ghi CHANGELOG.md: thay đổi gì, file nào, test kết quả ra sao. Commit nhỏ.
7. Sau khi commit: **grep tên hằng/hàm vừa thêm**. Nếu nó chỉ xuất hiện ở đúng chỗ khai báo thì fix mới landed một nửa (bài học TIP-506, 11/08/2026).
