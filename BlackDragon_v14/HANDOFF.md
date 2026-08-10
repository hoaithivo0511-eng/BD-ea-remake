# HANDOFF.md — Tài liệu bàn giao EA Black Dragon v14.7.1

> **Dành cho AI/dev tiếp nhận project để mở rộng & chỉnh sửa.** Đọc file này ĐẦU TIÊN, sau đó theo "Thứ tự đọc khi onboard" bên dưới. Cập nhật ngày 28/07/2026.

## 0. Trạng thái bàn giao

- **Version hiện tại:** 14.7.1 (`Config.mqh` BD_VERSION / `#property version "14.71"`). BD-001/BD-002 đã sửa; trạng thái **NEEDS MT5 VERIFY** vì các finding P1 khác của deep review chưa nằm trong scope này.
- **Test:** offline suite C++ **277/277 PASS**, UBSan PASS; RunTests.mq5 có thêm lifecycle tests nhưng chờ Chủ nhà compile/chạy trong MT5 xác nhận ALL GREEN.
- **Tương thích MT5:** đã kiểm tới build 6060 (23/07/2026); build tối thiểu khuyến nghị ≥ 6030.
- **Nghiệm thu phía Chủ nhà còn treo (không phải việc của code):** compile F7, RunTests ALL GREEN, backtest đối chiếu golden baseline (mode mặc định phải khớp v13 từng lệnh), demo async soak 2–4 tuần trước khi live.

## 0b. Gói này chứa gì (bàn giao trọn vẹn trong 1 file zip)

| File / thư mục | Dành cho ai | Nội dung |
|---|---|---|
| `GUIDE_SoTayVanHanh.html` | **Người dùng cuối / trader** | Mở bằng trình duyệt: flowchart luồng xử lý, giải thích 106 input, minh họa DCA/trailing/pip Vàng, set mẫu, checklist setup, FAQ |
| `HANDOFF.md` (file này) | **AI/dev tiếp nhận** | Trạng thái, sổ quyết định, thứ tự đọc, cạm bẫy, backlog |
| `Include/BlackDragon/ARCHITECTURE.md` | AI/dev | Bản đồ module + 9 quy tắc bất khả xâm phạm |
| `Include/BlackDragon/CHANGELOG.md` | AI/dev | Lịch sử từng version, mã FE/TIP/FIX/AU |
| `README.md` | Cả hai | Mô tả tính năng + fixlog |
| `vibecode-kit-v5.1.skill` | AI | Bộ quy trình build/audit (zip skill) — cài trước khi sửa code |
| `Experts/` `Include/` `Scripts/` `Sets/` | MT5 | Code EA, tests, .set baseline |

## 1. Thứ tự đọc khi onboard (bắt buộc, đúng thứ tự)

0. `GUIDE_SoTayVanHanh.html` — xem 15 phút để nắm hành vi EA từ góc nhìn người dùng trước khi đọc code.
1. `Include/BlackDragon/ARCHITECTURE.md` — bản đồ module, luồng dữ liệu một chiều, **9 quy tắc bất khả xâm phạm**, bảng Tính năng → File. Đây là luật.
2. Header contract của file định sửa (mỗi `.mqh` có Purpose/Invariants/KHONG DUOC DOI).
3. `Include/BlackDragon/CHANGELOG.md` — lịch sử đầy đủ từng version, mã FE/TIP/FIX/AU, deviation dự báo so với v13.
4. `README.md` — mô tả tính năng cho người dùng + Fixlog tổng hợp.
5. `Scripts/BlackDragon/Tests/` — RunTests.mq5 + offline_suite.cpp: đọc test là cách nhanh nhất hiểu hành vi đã chốt.

## 2. Lịch sử version (tóm tắt — chi tiết trong CHANGELOG.md)

| Version | Mã | Nội dung chính |
|---|---|---|
| 14.0.0–14.0.2 | Plan v2, AU-14-01…08 | Module hóa toàn bộ v13 (17 file), 12 bug fix, audit ngoài RRI-T vá 8 finding — nặng nhất **AU-14-01**: cache floating profit làm Overlap tê liệt → `RefreshFloating()` mỗi tick (thành rule 7) |
| 14.1.0 | FE-201/202/203 | Pip Vàng 1 USD = 10 pip tự nhận 2/3-digit (`PointScale`), chuỗi lot thủ công, comment `\|n` theo thứ tự DCA |
| 14.2.0 | FE-301 | Input `LotMode_`, cú pháp xN (`0.01x5-0.02x3`), **quy tắc đếm theo lệnh ĐANG MỞ** (quyết định Chủ nhà — rule 9) |
| 14.2.1 | TIP-401 | **Async là mặc định** + journal + watchdog + 6 fix nhỏ (HasPendingModify, MQL_TESTER guard…) |
| 14.2.2 | FIX-5 rev | Lot dưới min sàn → **dùng min sàn + log tracking, KHÔNG dừng EA** (Chủ nhà đảo chính sách fail-fast) |
| 14.3.0 | FE-401/402 | Money Close đa scope + %-diff + Daily Target/halt (CCBSN manual) — `MoneyGuard.mqh` |
| 14.4.0 | FE-403 | Time Limit 4 khung giờ PC/Local, qua đêm, `DcaOutsideTime` — `EntryFilters.mqh` |
| 14.5.0 | FE-404 | Mobile Control qua lệnh chờ giá đặc biệt 999999/666666/888888/555555 — `MobileControl.mqh` |
| 14.6.0–14.6.1 | FE-405/406, AU-14-11 | Port TradingView WMF (Pine v5) làm `ISignal` thứ hai + mũi tên chart; vá mất tín hiệu khi CopyBuffer fail (`m_pendingCross`) |
| 14.7.0 | FE-407/408 | Chuỗi khoảng cách DCA theo pip + chuỗi hệ số nhân (công thức đóng, không làm tròn trung gian) — `CDistancePlan`/`CChainSizer` |
| 14.7.1 | BD-001/002 | Close-terminal tick + async journal đợi resulting state; soft/hard watchdog 5s/30s |

## 3. Sổ quyết định của Chủ nhà (KHÔNG được "sửa giùm")

Các quyết định dưới đây đã được Chủ nhà chốt tường minh và có test chốt hành vi. Muốn đổi → hỏi lại Chủ nhà, không tự quyết:

1. **Đếm bậc DCA theo lệnh ĐANG MỞ** (`side.count`): mở 9, Overlap tỉa 2 còn 7 → lệnh kế là số 8. Áp cho CẢ lot (mọi LotMode) lẫn distance chain lẫn comment `|n`. (26/07/2026, rule 9 ARCHITECTURE.)
2. **Lot dưới min sàn:** dùng min sàn + log track (không throttle), EA chạy tiếp. Riêng **chuỗi sai cú pháp** vẫn fail-fast `INIT_PARAMETERS_INCORRECT` tại OnInit.
3. **Async là chế độ mặc định** (`exec_Async`); mọi lệnh mở/đóng — kể cả Money/Daily close — đi cùng một đường `ExecutionLayer.Send` + journal + watchdog.
4. **Pip Vàng:** 1 giá (1 USD) = 10 pip; reference point 0.01; `PointScale = round(0.01/_Point)` cho Vàng, sàn khác = 1. Input points mới PHẢI tự trả lời "có nhân PointScale không" (rule 8) và chỉ nhân ĐÚNG MỘT LẦN tại chỗ dùng.
5. **WMF giữ đủ input gốc TradingView** (kể cả Source/ENUM_APPLIED_PRICE); bộ lọc Stoch của BD áp chung cho cả 2 signal khi bật.
6. **Classic mode = baseline v13:** `Grid_DistancePoints` và `Grid_MartingaleLot` (kể cả `NormalizeDouble(,2)` trung gian) giữ nguyên để khớp golden baseline — KHÔNG "tối ưu" chúng.
7. **Cú pháp chuỗi thống nhất:** phần tử cách nhau `-`, lặp bậc `xN`, vượt chuỗi lặp bậc cuối, trần `BD_MAX_LOT_STEPS=200` — parser chung `Grid_ParseLotSequence` dùng cho lot/hệ số/khoảng cách.
8. **Close intent kết thúc tick:** nếu close và DCA cùng đúng, chỉ close; nếu BUY và SELL cùng exit thì gửi close cả hai rồi return.
9. **Async accepted chưa hoàn tất:** journal chỉ nhả khi resulting position/SLTP đã quan sát được; event REQUEST/DEAL/POSITION có thể đến khác thứ tự.

## 4. Kiến trúc & điểm mở rộng (tóm tắt — chi tiết ARCHITECTURE.md)

- Luồng một chiều: Tick → Context → Signal → BasketManager → Strategy → **ExecutionLayer (nơi DUY NHẤT gọi trade API)** → OnTradeTransaction → rebuild cache.
- Interface có sẵn: `ISignal` (CRsiStochSignal, CWmfSignal), `IEntryFilter` (Hour/Spread/Pause/News/Halt/Time/Adx), `ILotSizer` (CMartingaleSizer, CSequenceSizer, CChainSizer), `CDistancePlan`.
- **Thêm filter:** class mới trong `Filters/` + 1 dòng `AddNewSeriesFilter`/`AddGridFilter` trong `BlackDragon.mq5` OnInit + input trong `Config.mqh`. Mẫu: `AdxFilter.mqh`.
- **Thêm signal:** implement `ISignal`, thêm giá trị vào `eSignalSource`, gắn con trỏ trong OnInit. Mẫu: `WmfSignal.mqh` (chú ý seed/re-seed khi gap, pending event qua retry).
- **Đổi cách tính lot/khoảng cách:** implement `ILotSizer` / mở rộng `CDistancePlan`. Hàm tính giữ THUẦN trong `GridEngine.mqh` để test được cả 2 suite.
- Vùng `[STRATEGY-BEHAVIOR]` không sửa khi refactor; hành vi khác → implementation mới qua interface.

## 5. Hạ tầng test & cách chạy

- **Trong MT5:** `Scripts/BlackDragon/Tests/RunTests.mq5` chạy như Script → kỳ vọng ALL GREEN (~180 assert hiện tại).
- **Ngoài MT5:** `Scripts/BlackDragon/Tests/offline_suite.cpp` là bản port hàm thuần + lifecycle model sang C++ — 14.7.1 hiện **277/277 PASS**.
- **Benchmark hiệu suất:** `Scripts/BlackDragon/Tests/bench.cpp` có sink. 5 lượt máy review 14.7.1: BD-002 ready-check **3,29–3,67ns/event**; BD-001 journal guard 0..8 entry **3,39–4,57ns/tick**. Các benchmark core cũ nằm trong dao động cùng máy.
- **Kỷ luật "test the test":** expected value phải tính tay/bằng python ĐỘC LẬP trước khi viết assert (bài học: đoán 1.03^200 > 5.0, thực tế 3.69).
- Kiểm tra nhanh brace balance các .mqh bằng python trước khi giao (không có compiler MQL5 trong sandbox).

## 6. Quy trình sửa/mở rộng (VibecodeKit v5.1)

> Bộ quy trình đầy đủ nằm ngay gốc repo: **`vibecode-kit-v5.1.skill`** (zip — giải nén ra `SKILL.md` + `references/`, trong đó `retro-rubrics.md` là checklist PRE-BUILD/BUILD/VERIFY/PERF/HANDOFF chưng cất từ chính project này). Phiên làm việc mới: cài/đọc skill này TRƯỚC khi sửa code.

1. Đọc §1 → xác định file đích từ bảng ARCHITECTURE §3.
2. Tính năng mới: **plan trước — Chủ nhà duyệt — mới code** (TIP). Hỏi rõ chính sách lỗi: dừng EA (fail-fast) hay chạy tiếp + log (graceful)? — đã từng đoán sai cả hai hướng.
3. Sửa nhỏ nhất có thể; input mới → cân nhắc rule 8 (PointScale) + thêm vào `Sets/BlackDragon_baseline.set` với default TẮT (backward-compatible).
4. Chạy cả 2 suite + cập nhật CHANGELOG.md (mã FE/TIP/FIX/AU, deviation dự báo) + README nếu người dùng cần biết.
5. Persistence đổi struct → tăng magic version (hiện BD15 `0x42443135`), file cũ từ chối sạch sẽ → dùng default.

## 7. Backlog / cơ hội để sau

- Log nhắc khi `LotSequence_` bị bỏ qua ở `LotMode=MultiplierChain` (cosmetic, vô hại).
- `SymbolInfoCommissions()` (MT5 ≥ 6030) — panel P/L net chính xác hơn.
- Soak test async 2–4 tuần demo (phía Chủ nhà, trước live).

## 8. Cạm bẫy đã trả giá (đọc trước khi tự tin)

- **Cache dữ liệu biến thiên theo giá = tê liệt exit** (AU-14-01). C1 chỉ giữ dữ liệu tĩnh theo sự kiện; profit/swap đọc tươi mỗi tick.
- **Async không có guard = spam lệnh** (AU-14-02): mọi thao tác async lặp lại được phải có `HasPending*` guard idempotent.
- **Tester chạy nhiều pass dùng chung file state** (AU-14-03): mọi persistence phải có `MQL_TESTER` guard.
- **Cờ local mất event khi retry** (AU-14-11): tín hiệu/sự kiện phát hiện được phải persist thành member (`m_pendingCross`) đến khi TIÊU THỤ, không sống trong biến local một tick.
- **CopyRates/CopyBuffer non-series: index 0 = nến CŨ nhất**; iTime/iBarShift = series. Trộn 2 hướng là bug im lặng.
- **TimeLocal() trong tester = giờ server mô phỏng** — FE-403 đã ghi rõ trong README; đừng "fix" thành TimeCurrent.
- **PointScale nhân đúng MỘT lần** — nhân ở cả Config lẫn chỗ dùng là sai ×10/×100 khoảng cách.
