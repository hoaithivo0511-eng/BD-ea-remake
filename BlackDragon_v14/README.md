# EA Black Dragon v14.7.1 — Modular Rebuild (Plan v2)

> **Người dùng EA:** mở `GUIDE_SoTayVanHanh.html` (gốc repo) bằng trình duyệt — flowchart luồng chạy, giải thích từng input, minh họa, set mẫu, checklist setup.
>
> **AI/dev mới tiếp nhận project:** đọc `HANDOFF.md` (gốc repo) trước tiên — trạng thái bàn giao, sổ quyết định Chủ nhà, thứ tự đọc tài liệu, cạm bẫy đã biết.

Bản big update theo Plan v2: module hóa toàn bộ EA Black Dragon v13, giữ nguyên logic chiến lược, áp 12 bug fix + tối ưu hiệu suất + async trade mode + calendar API. Bản 14.0.2 vá 8 finding từ audit ngoài Vibecode Kit v5/RRI-T; bản 14.1.0 thêm 3 tính năng theo yêu cầu Chủ nhà (xem §Tính năng v14.1 và §Fixlog).

## Tính năng v14.1 (FE-201/202/203)

**FE-201 — Pip Vàng chuẩn hóa mọi sàn.** Quy ước 1 giá (1 USD) = 10 pips. EA tự nhận sàn Vàng hiển thị 2 hay 3 số thập phân và scale toàn bộ input dạng points (Fix_Distance, Dynamic_distance_start, TP_, SL_, iTS, iTD, MaxSpred) để cùng một .set chạy giống hệt nhau: `Fix_Distance=200` luôn = 2.00 USD = 20 pips. Input `AutoGoldPip=true` (tắt được). Log Init in digits + PointScale để kiểm tra nhanh. Symbol không phải Vàng: không đổi gì.

**FE-202 + FE-301 — Chế độ lot DCA (v14.2).** Input `LotMode_` chọn tường minh: `xLot hệ số nhân` (martingale ×`Martin_`, mặc định — y hệt v13) hoặc `Lot thủ công (chuỗi)` dùng `LotSequence_`. Chuỗi hỗ trợ hai cú pháp: liệt kê từng bậc `0.01-0.02-0.04`, hoặc rút gọn nhân bậc `0.01x5-0.02x3-0.05` (5 lệnh đầu 0.01, 3 lệnh kế 0.02, từ lệnh 9 vào 0.05). Vượt chuỗi → lặp lot bậc cuối đến khi rổ đóng hết; MaxLot vẫn cap; Autolot bị bỏ qua khi chuỗi active; trần 200 bậc sau khi bung. Chuỗi sai định dạng → EA từ chối khởi động (INIT_PARAMETERS_INCORRECT) kèm log — không bao giờ trade với lot sai.

**FE-407/408 — Chuỗi khoảng cách & chuỗi hệ số nhân (v14.7).** `DistanceMode_=Manual` + `DistanceSequence_` (pip, cú pháp xN: `10x3-15x2-20`; 1 pip = 10 point chuẩn FE-201 → 10 pip = 1 USD trên Vàng mọi sàn) thay bảng khoảng cách classic; `LotMode_=Multiplier chain` + `MartinSequence_` (`1.03x3-1.3x4-1.25-1.5`) thay hệ số nhân đơn — lot tính công thức đóng lý thuyết từ lệnh đầu rổ, làm tròn một lần lúc gửi kèm log track. Cả hai chuỗi lặp bậc cuối đến hết rổ và đếm bậc theo số lệnh đang mở. Trigger DCA không đổi: đo từ giá mở lệnh cuối, khớp theo tick, 1 lệnh/nến/hướng.

**Quy tắc đếm thứ tự (Chủ nhà chốt 26/07/2026):** cả hai chế độ đều đếm theo số lệnh **thực tế đang mở** — mở 9, Overlap tỉa 2 còn 7 → lệnh kế tiếp là lệnh số 8 (chuỗi lấy bậc 8; martingale = hệ số^7 như v13). Comment `|n` mang đúng số đó. Rổ đóng toàn bộ → chu kỳ mới tự về bậc 1.

**FE-401 — Money Close (v14.3, theo CCBSN manual).** Nhóm input "Money Close": TP điền số DƯƠNG (500), SL điền số ÂM (−500), 0 = tắt. Các scope: toàn account (mọi magic/symbol — dùng ACCOUNT_PROFIT), cùng Magic, riêng Buy, riêng Sell, TP tổng đặc biệt khi CẢ 2 rổ cùng mở, và %-chênh-lệch Close All theo công thức (chiều lời) + (chiều lỗ × (1+%)) ≥ 0. Ưu tiên đóng theo scope rộng nhất trước. Sai dấu input → warn + coi như tắt.

**FE-402 — Daily Target (v14.3).** Mục tiêu/giới hạn lãi lỗ NGÀY theo $ hoặc % số dư đầu ngày, scope Magic của bot; dayNet = realized hôm nay + floating 2 rổ. Chạm ngưỡng → đóng 2 rổ + nghỉ giao dịch đến 00:00 ngày mới + `NewDayDelayMin` phút (title panel hiện "DAILY HALT till…"). Halt chỉ chặn lệnh tự động — nút panel vẫn hoạt động. Restart giữa chừng: halt tự suy lại từ lãi đã chốt trong ngày.

**FE-403 — Giới hạn thời gian theo giờ PC/Local (v14.4).** `UseTimeLimit` + 4 khung giờ bật/tắt riêng, định dạng "HH:MM" theo **giờ máy tính** (trong tester = giờ server mô phỏng), hỗ trợ khung qua đêm (vd 22:00–02:00). Ngoài khung giờ: chặn mở chuỗi mới và grid add; `DcaOutsideTime=true` thì riêng grid add DCA vẫn được phép. Mọi exit (TP/SL/trailing/Overlap/Money/Daily) và nút panel vẫn hoạt động ngoài giờ. HH:MM sai định dạng hoặc bật master mà không bật khung nào → EA từ chối chạy kèm log chỉ rõ khung lỗi.

**FE-404 — Mobile Control (v14.5).** Điều khiển EA từ MT5 mobile bằng lệnh chờ giá đặc biệt trên đúng chart symbol (volume tùy ý, EA tự xóa lệnh chờ sau khi thực thi): Buy Stop 999999 = dừng mọi lệnh mở tự động; Buy Stop 666666 = khôi phục hoàn toàn (xóa cả Stop Buy/Sell); Buy Stop 888888 = tắt New Cycle, Sell Limit 888888 = bật; Buy Stop 555555 = Stop Buy, Sell Limit 555555 = Stop Sell. Trạng thái sống qua restart. Lưu ý: chỉ dùng LỆNH CHỜ với các giá này — đừng nhập vào market order; exits và nút panel vẫn hoạt động khi đang Stop All. Tắt tính năng bằng `UseMobileControl=false`.

**FE-405 — WMF Signal (v14.6).** Nguồn tín hiệu thứ hai port từ TradingView "WUYX Momentum Follower" (Volatility Stop ATR × EMA). Chọn qua `SignalSource_` (BD RSI mặc định / WMF); `WmfMode` = Cross (đúng nhãn BUY/SELL của indi) hay Trend (theo màu nến — nhịp liên tục như RSI). Đủ input như indi gốc: TF, Length 20, Source (Close/Open/…/Weighted), Multiplier 1.0, EMA Length 2. Bộ lọc Stochastic (`Use_Stoh`) áp y hệt cho cả hai signal. EA tự seed 1000 nến đóng khi khởi động để khớp TradingView; tín hiệu tính trên nến đóng. Từ 14.6.1: `ShowWmfSignals=true` vẽ mũi tên BUY/SELL (kể cả ~100 tín hiệu lịch sử khi gắn EA) lên chart như plotshape của indi — ring 200 mũi tên tự dọn.

**FE-203 — Comment đánh số DCA.** Comment lệnh = `commentinput|n` (n = thứ tự lệnh trong chuỗi, 1-based): với `sOrdComm=EaBd` → `EaBd|1`, `EaBd|2`… Lệnh mở tay từ panel gia nhập rổ nên được đánh số tiếp theo. EA không parse comment ngược — chỉ phục vụ đọc deal list.

## Bản đồ tiếp nhận project (đọc theo thứ tự — dành cho AI coding & dev mới)

1. `Include/BlackDragon/ARCHITECTURE.md` — bản đồ module, luồng dữ liệu một chiều, 6 quy tắc bất khả xâm phạm, bảng "Tính năng → File". **Đọc trước khi sửa bất kỳ dòng nào.**
2. `Include/BlackDragon/CHANGELOG.md` — lịch sử đầy đủ: 12 bug fix + C1–C7 (14.0.0), 5 fix audit nội bộ AU-1…AU-5 (14.0.1), 8 fix audit ngoài AU-14-xx (14.0.2) kèm deviation baseline dự báo cho từng fix.
3. `Scripts/BlackDragon/Tests/RunTests.mq5` — 30+ assert hàm thuần; mọi thay đổi công thức phải giữ ALL GREEN.
4. Quy ước sống còn: vùng `[STRATEGY-BEHAVIOR]` là hành vi chiến lược v13 — KHÔNG sửa khi refactor; chỉ `ExecutionLayer` được gọi trade API; chỉ `BasketManager` ghi `BasketSide`; chỉ `Panel` đụng chart objects; input names/defaults giữ nguyên v13 để tương thích .set.
5. Bài học đắt giá nhất của project (AU-14-01): **cache chỉ được giữ dữ liệu tĩnh theo sự kiện** (ticket, lots, giá mở); mọi giá trị biến thiên theo giá (profit, swap) phải đọc tươi mỗi tick qua `RefreshFloating()`. Đừng "tối ưu" lại điều này.

## Fixlog v14.0.2 — audit ngoài Vibecode Kit v5 / RRI-T (26/07/2026)

| ID | Mức | File | Tóm tắt | Trạng thái |
|---|---|---|---|---|
| AU-14-01 | **P0** | Types.mqh, BasketManager.mqh | Floating profit đóng băng giữa các trade event (hệ quả C1) → Overlap tê liệt, panel P/L sai. Thêm `RefreshFloating()` mỗi tick, field `BasketSide.swapSum`, bỏ `SwapSum()` | ✅ Fixed |
| AU-14-02 | TB | ExecutionLayer.mqh | Async+Real gửi lặp modify SL/TP trong cửa sổ chờ xác nhận. Thêm `HasPendingModify()` guard | ✅ Fixed |
| AU-14-03 | TB | Persistence.mqh | File trạng thái panel nhiễm chéo giữa các pass tester. Guard `MQL_TESTER` trong Save/Load | ✅ Fixed |
| AU-14-04 | Thấp | SignalEngine.mqh | Stochastic tính mỗi tick dù `Use_Stoh=false`; lỗi copy stoch treo cả tín hiệu RSI. Handle + CopyBuffer có điều kiện | ✅ Fixed |
| AU-14-05 | Thấp | BasketManager.mqh | SwapSum quét riêng mỗi tick — gộp vào RefreshFloating, không tăng API call | ✅ Fixed |
| AU-14-06 | Thấp | Config.mqh, ExecutionLayer.mqh | Slippage hardcode 3 → input `Slippage_` (default 3, hành vi không đổi) | ✅ Fixed |
| AU-14-07 | Thấp | GridEngine.mqh, ExecutionLayer.mqh | Lot < VOLUME_MIN → dùng MIN LOT của sàn (clamp v13), EA không dừng; từng lệnh bị điều chỉnh được log không-throttle để track; OnInit cảnh báo sớm | ✅ Chốt 14.2.2 (quyết định Chủ nhà) |
| AU-14-08 | Thấp | BlackDragon.mq5 | Guard `barTime==0` khi history chưa đồng bộ | ✅ Fixed |
| AU-14-09 | Thấp | Config.mqh | Dọn dead code: enum `eSignalBarTP`, 2 define không dùng | ✅ Fixed |
| AU-14-10 | Thấp | NewsCalendar.mqh | Cache tin 1h — sự kiện đổi giờ trong vòng 1h có thể lọt | ⏸ Deferred — chấp nhận được, hạ chu kỳ nếu cần |
| — | Ghi chú | — | Semantics v13 giữ nguyên: trạng thái panel đè input khi re-init (REASON_PARAMETERS); nút panel bỏ qua filter/MaxOrders; nâng cấp `SymbolInfoCommissions()` (build ≥ 6030) chờ Chủ nhà duyệt | 📋 Cần quyết định |

Tương thích nền tảng: đã audit đối chiếu MT5 build 6060 (23/07/2026) — không dùng API deprecated; hai thay đổi compiler lớn (build 5200 strict enum, build 5260 method hiding) không ảnh hưởng codebase. Test offline 77/77 PASS (port RunTests + mô phỏng AU-14-01/02 + FE-201/202/203); nghiệm thu MT5-side theo mục dưới đây.

Ghi chú cho AI/dev khi mở rộng tiếp: FE-202 là ví dụ sống thứ hai (sau AdxFilter) của extension point — một tính năng lot mới = 1 class ILotSizer + chọn trong OnInit + input; đừng sửa CMartingaleSizer. FE-201 gói toàn bộ scale trong `Sym_PointScale*` + `Config_ApplyPointScale` — mọi input points mới thêm sau này phải tự hỏi "có cần nhân Cfg.PointScale không".

## Cài đặt

Copy đúng cấu trúc vào thư mục dữ liệu MT5 (`File > Open Data Folder`):

```
MQL5/Experts/BlackDragon/BlackDragon.mq5
MQL5/Include/BlackDragon/*.mqh  (+ Filters/, ARCHITECTURE.md, CHANGELOG.md)
MQL5/Scripts/BlackDragon/Tests/RunTests.mq5
```

Mở `BlackDragon.mq5` trong MetaEditor → Compile (F7). Yêu cầu 0 error.

## Quy trình nghiệm thu (bắt buộc, theo Plan v2 §4–§5)

1. **Unit tests**: compile + chạy Script `Tests/RunTests` trên chart bất kỳ → log phải in `ALL GREEN`.
2. **Golden baseline (P0)**: backtest **v13 gốc** real-tick 2–3 năm với `Sets/BlackDragon_baseline.set`, xuất báo cáo deal list. Chạy 2 lần — phải giống hệt nhau.
3. **So sánh v14**: cùng .set, cùng dữ liệu → đối chiếu deal list với baseline. Lệch chỉ được phép ở các edge case đã dự báo trong CHANGELOG (trailing gap #2, swap dương #3, overlap #10…). Với setting mặc định (SL=0, iTS=0), khác biệt kỳ vọng ≈ 0 trừ khi Overlap từng bắn sai ở v13. **Từ 14.0.2:** đối chiếu thêm SỐ LẦN Overlap bắn — v14.0.2 phải ngang v13 (v14.0.0/14.0.1 hụt hẳn do AU-14-01, đó là bug chứ không phải baseline). Khuyến nghị chạy trên MT5 build ≥ 6030 (tester đã sửa swap/margin).
4. **Stress test**: backtest 2020 (COVID) + 2022 (trend USD mạnh), symbol tick value nhỏ.
5. **Async soak (P4)**: demo 2–4 tuần, 2 chart cùng settings — 1 `exec_Sync`, 1 `exec_Async` → so deal log, không được có lệnh trùng/sót. Async chỉ dùng live/demo (tester tự fallback sync).

## Lưu ý vận hành

- **Từ 14.2.1, ExecMode mặc định là Async** (OrderSendAsync — không chờ sàn trả lời, đóng cả rổ song song). **14.7.1 hardening:** callback REQUEST accepted chỉ chuyển journal sang trạng thái chờ, không còn nhả guard; EA đợi kết quả position/SLTP thực sự quan sát được, đối soát mỗi 500ms, giữ khóa qua soft-timeout 5s và chỉ nhả ở hard-timeout 30s nếu không còn bằng chứng broker đang xử lý. Mọi close intent kết thúc tick nên không thể mở/DCA/modify phía sau snapshot đang đóng. Tester luôn tự chạy sync. **Bước soak async 2–4 tuần demo vẫn bắt buộc trước tiền thật.**
- TP/SL/Trailing mặc định là **ảo** → cần terminal/VPS chạy liên tục.
- Rủi ro chiến lược grid-martingale không đổi: tổng khối lượng rổ đầy ≈ 113× lot đầu, SL mặc định tắt.
- News filter dùng calendar tích hợp MT5: cần bật "Allow news" trong terminal; trong tester không có dữ liệu → `NewsFailMode` quyết định (mặc định: vẫn giao dịch, giống v13).
- Đọc `Include/BlackDragon/ARCHITECTURE.md` trước khi sửa code. Ghi `CHANGELOG.md` sau mỗi thay đổi.

## Git (khuyến nghị P0)

```
git init && git add -A && git commit -m "v14.0.0 modular rebuild (Plan v2)"
```
Mỗi thay đổi sau đó: branch riêng, commit nhỏ, diện tích diff nhỏ.
