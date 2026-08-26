# CHANGELOG — EA Black Dragon (modular)

## T17.11 — Recovery runtime liveness and admission hardening

- Scheduler treats a stable ACTIVE/no-TP wait as side-local and read-only, so
  it cannot starve actionable Recovery work on the opposite direction.
- Terminal max-generation Core-without-Hedge topology is exposed as a derived,
  non-persisted status; DCA honors `ContinueDcaAfterHedge_` without requiring
  inapplicable live-Hedge coverage/corridor metrics.
- `OnInit()` now composes every existing Recovery validator through one
  authoritative fail-fast gate, including T5 and T6 families.
- Legacy Core/DCA submission returns a typed broker disposition. A per-intent,
  per-direction, per-bar strategy latch bounds repeated `NO_MONEY` attempts
  while leaving Recovery-owned execution and transient retry semantics intact.
- No user input, persisted enum, T17.10 unit behavior or trading-strategy
  semantic changed. Strategy Tester remains pending owner replay.

## T17.10 — versioned point/pip/tick unification

- Thêm `UnitSystemMode_`: mặc định `LEGACY_COMPAT` giữ nguyên `.set`; `PIP_UNIFIED` là opt-in và hiểu TP/SL/trailing/spread/slippage theo pip.
- DCA unified dùng pip-size của symbol, sửa lỗi bridge cố định 10 point trên FX 4-digit; Recovery/Pyramid `*Pips*` giữ nguyên semantic.
- Basket breakeven ghép `SYMBOL_TRADE_TICK_VALUE` với `SYMBOL_TRADE_TICK_SIZE`, không còn ghép nhầm `_Point`.
- Execution chỉ đổi slippage price sang broker points tại `MqlTradeRequest.deviation`; unit metadata lỗi làm OnInit fail-closed.
- Recovery fingerprint chỉ thêm unit-policy revision khi opt-in unified, nên default legacy vẫn byte-compatible.

## [14.7.2] — 2026-08-11 — Deep review BD-R1…R9 (TIP-501…509) — CHƯA COMPILE

> ⚠️ **Đọc dòng này trước mọi dòng khác.** Toàn bộ mục 14.7.2 là kết quả
> **review TĨNH**. Môi trường thực hiện không có MetaEditor, không có Strategy
> Tester và không có mạng ⇒ **F7 chưa chạy, `RunTests.mq5` chưa chạy, backtest
> đối chiếu golden baseline chưa chạy**. Mỗi dòng dưới đây mô tả code ĐÃ GHI
> vào nhánh `fix/bd-r2-r4-r5-r7-r8` (PR #2), **không** phải hành vi đã kiểm
> chứng. Đây là khác biệt lớn nhất giữa mục này và mọi mục phía dưới.

### P1 — 4 finding

- **BD-R1 / TIP-506 — async close khóa Money/Daily guard tới 30s.**
  `Strategy::OnTick` return ở `HasAnyPendingClose()` TRƯỚC `ApplyGuard`, nên
  một reply close thất lạc làm guard câm suốt hard-timeout. Thêm hằng
  `BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC = 10` + hàm thuần
  `Exec_HardTimeoutSec(action)` nối vào `Watchdog()`: CLOSE/MODIFY nhả sau
  10s, OPEN giữ 30s. Bất đối xứng CÓ CHỦ ĐÍCH — CLOSE/MODIFY idempotent,
  OPEN thì không (nhả sớm có thể sinh lệnh thật thứ hai).
- **BD-R2 / TIP-501 — `Slippage_` không nhân `PointScale`.** `req.deviation`
  nhận thẳng số point của input, nên trên Vàng 3-digit `Slippage_=3` chỉ là
  0.03 USD thay vì 0.30 — vi phạm rule 8. Thêm `Exec_Deviation(points, scale)`
  thuần, áp tại đúng một chỗ trong `OpenMarket`/`ClosePosition`.
- **BD-R3 / TIP-507 — trailing SL thật bị xóa mỗi lần DCA add.** Ngoài việc
  xóa stop, `SeedExtreme()` còn re-derive extreme từ "nến kể từ leg mới nhất"
  trên MỌI `Rebuild()`; cửa sổ đó vẫn chứa phần TRƯỚC khi add của nến hiện
  tại, nên một đỉnh cũ có thể arm trail ngay theo breakeven mới (Virt: đóng
  rổ tại chỗ; Real: đẩy stop sai phía giá). Trail extreme thành *session
  state* đơn điệu có leg anchor, chỉ re-anchor khi xuất hiện leg MỚI HƠN; leg
  bị tỉa KHÔNG re-derive. Mỗi lần xóa SL thật có log `trailclr`.
- **BD-R4 / TIP-502 — halt daily mất sau restart.** Đạt Daily target/limit →
  halt, nhưng `haltUntil` chỉ nằm trong RAM. Recompile hay restart giữa ngày
  là EA giao dịch lại ngay. Thêm `haltUntil` vào `SPersistedState` +
  `MG_HaltDeadline()` thuần. **Persistence bump BD15 → BD16.**

### P2 — 4 finding

- **BD-R5 / TIP-503 — retry storm khi không xóa được lệnh chờ.** Một pending
  mobile-control không xóa được làm `Persist_Save()` + panel redraw chạy 2
  lần/giây vĩnh viễn. Thêm `BD_MC_DELETE_RETRY_SEC = 5` + throttle log.
- **BD-R6 / TIP-508 — lệnh tay magic-0 chỉ tính floating, không tính
  realized.** Với `flag_Hand_Ord = true`, P/L nổi của lệnh tay đã vào lãi/lỗ
  ngày nhưng phần đã chốt thì không ⇒ ngày âm/dương nhảy bậc mỗi lần đóng
  lệnh tay. Hàm thuần `Basket_OwnsMagic()` thành định nghĩa DUY NHẤT của
  "lệnh của mình", dùng chung cho position scan, `SeedDayProfit()` và booking
  trong `OnTradeTransaction`.
- **BD-R7 / TIP-504 — ticket biến mất còn được đếm trọn một tick.**
  `RefreshFloating` bỏ qua ticket đã đóng nhưng không nén mảng, nên `count`/
  `totalLots` sai cho tới `Rebuild()` kế tiếp — bậc DCA và breakeven lệch
  trong cửa sổ đó. Nén ngay trong tick.
- **BD-R8 / TIP-505 — `DrawLevels` chạy mỗi tick**, trái rule C3 (panel theo
  timer 500ms + dirty check). Chuyển về cadence panel.

### P3 được Chủ nhà nâng vào scope

- **BD-R9 / TIP-509 — Hedge OFF + hai chiều cùng mở ⇒ CẢ HAI `TryGridAdd`
  kẹt vĩnh viễn.** Cổng cũ đặt trên cả hai nhánh:

  ```cpp
  if(Flag_Use_hedge || m_basket.sell.count == 0) TryGridAdd(... BD_DIR_BUY ...);
  if(Flag_Use_hedge || m_basket.buy.count  == 0) TryGridAdd(... BD_DIR_SELL ...);
  ```

  Hai điều kiện loại trừ lẫn nhau: hedge OFF + hai chiều cùng có lệnh ⇒ cả
  hai false, và không có gì trong vòng tick xóa được trạng thái đó. Rổ đóng
  băng ở giá trung bình xấu nhất trong khi exits vẫn chạy. Trạng thái hai
  chiều là ĐẾN ĐƯỢC dù hedge OFF: nút Open Buy/Open Sell trên panel bypass
  luật hedge theo thiết kế, và `flag_Hand_Ord = true` đếm lệnh tay magic-0
  vào cả hai chiều.

  Tách thành hai hàm thuần trong `EntryFilters.mqh`:
  `Hedge_AllowsNewSeries(useHedge, oppositeCount)` giữ NGUYÊN luật v13 cho
  series mới, `Hedge_AllowsGridAdd(ownCount)` chỉ hỏi "chiều này đã có lệnh
  chưa". `Flag_Use_hedge` **cố ý không phải tham số** của hàm thứ hai — đọc
  chữ ký là thấy ngay việc thiếu phép thử hedge là bàn ý, không phải xóa sót.

### Quyết định của Chủ nhà (11/08/2026 — sổ quyết định HANDOFF §3 mục 10–13)

1. **BD-R1:** giữ thứ tự `HasAnyPendingClose()` trước `ApplyGuard` (đảo thứ
   tự sẽ nhân đôi lệnh đóng), chỉ rút ngắn cửa sổ phơi nhiễm.
2. **BD-R3:** chấp nhận SL thật bị xóa khi DCA add, nhưng trail phải arm lại
   theo breakeven MỚI.
3. **BD-R6:** tính CẢ realized của lệnh tay vào lãi/lỗ ngày.
4. **BD-R9:** luật hedge gác SERIES MỚI, không gác DCA add.

### Deviation baseline DỰ BÁO

- Với **input mặc định, không đổi gì**: cả 9 patch là no-op trong tester.
  TIP-506 chỉ chạm error path; TIP-507 cần `iTS != 0` (mặc định 0); TIP-508
  cần `flag_Hand_Ord = true` (mặc định false); TIP-509 cần
  `Flag_Use_hedge = false` (mặc định true).
- **BD-R2 đổi hành vi có chủ đích trên sàn Vàng 3-digit:** deviation thực tế
  ×10 so với trước. Đây là sửa lỗi, không phải regression.
- **BD-R7 có thể dịch một fill sớm đúng một tick** sau khi một leg biến mất —
  patch duy nhất trong lượt này chạm được vào trade list của backtest.
- **BD15 → BD16:** lần khởi động đầu tiên sau merge, file state cũ bị từ chối
  sạch sẽ ⇒ mọi toggle panel về default của input. Chụp lại trạng thái panel
  trước khi merge nếu đang chạy live.

### Rủi ro còn lại của BD-R9 (có sẵn từ trước, nay gặp thường hơn)

Với `flag_Hand_Ord = true`, một chiều do EA sở hữu nay có thể DCA trong khi
chiều kia đang có lệnh tay, và `TryGridAdd` có thể chồng bậc martingale lên
cái thực chất là rổ lệnh tay. Đây là hành vi vốn có của `flag_Hand_Ord` —
nó đã đúng như vậy mỗi khi chỉ một chiều có lệnh tay — nhưng khóa deadlock
trước đây vô tình che nó đi. Ai bật `flag_Hand_Ord` nên đọc kịch bản 10
trong `docs/vibecode/VERIFY_REPORT-v14.7.2.md` trước.

### Test 14.7.2

- `RunTests.mq5` **+37 assert** cho BD-R1…R9 (7 BD-R2, 5 BD-R4, 1 BD-R5,
  8 BD-R1, 7 BD-R6, 9 BD-R9) — **ĐÃ VIẾT, CHƯA CHẠY**. Block BD-R9 có một
  assert dựng lại **cổng cũ** bằng biến chạy được (không dùng hằng, tránh
  constant folding) và chứng minh nó false ở cả hai chiều cùng lúc: giữ lỗi
  cũ dưới dạng code, vì văn xuôi không chặn được ai đặt lại nó.
- Offline suite C++ vẫn **277/277** của 14.7.1 — **chưa port** BD-R1…R9.
- BD-R3, BD-R7, BD-R8 không có bề mặt thuần để assert; checklist chạy tay
  10 kịch bản nằm trong `docs/vibecode/VERIFY_REPORT-v14.7.2.md`.

### Bài học ghi lại (đắt nhất của lượt này)

**TIP-506 từng landed một nửa mà mọi tài liệu đều báo đã xong.** Commit khai
báo `BD_ASYNC_CLOSE_HARD_TIMEOUT_SEC` trong `Config.mqh` và comment quyết
định trong `Strategy.mqh`, nhưng `ExecutionLayer.mqh` trở về **y hệt từng
byte**; `Watchdog()` vẫn so mọi intent với hằng 30s. Không có lệnh push nào
báo lỗi. Quy tắc rút ra, nay nằm trong HANDOFF §8 và ARCHITECTURE §6:
**một write thành công không phải là một write đã thay đổi thứ gì** — sau mỗi
commit phải đọc lại blob SHA và grep tên hằng/hàm mới; nếu nó chỉ xuất hiện
đúng một lần, ở chỗ khai báo, thì fix mới xong một nửa.

### Còn mở sau 14.7.2

- **4 finding P3** chưa vá: trailing SELL lệch bid/ask một spread;
  `positionVolumeBefore` là tên gọi sai (giữ target volume);
  journal async OPEN kẹt tới hard timeout khi `positionCountBefore` cũ;
  `WmfTF` < TF chart làm `Seed()` đọc lại 1000 nến mỗi nến chart. Ba mục đầu
  tiên và mục cuối đổi hành vi ⇒ Chủ nhà đã loại khỏi lượt này.
- **Zip trùng ở gốc repo đã xóa** (`BlackDragon_v14.7.1_BD001_BD002_FIXED.zip`,
  202 KB): git không diff được nó, không ai review nó, và nó lạc hậu ngay khi
  có commit kế tiếp.
- **Gate bắt buộc trước khi merge PR #2:** F7 0 error/0 warning → `RunTests.mq5`
  ALL GREEN → offline suite 277/277 → backtest đối chiếu golden baseline →
  kịch bản BD-R9 trên terminal (hedge OFF, mở tay 1 buy + 1 sell, xác nhận cả
  hai chiều DCA trở lại **và** series đối lập vẫn bị chặn) → demo async soak
  2–4 tuần.

## [14.7.1] — 2026-07-28 — BD-001/BD-002: close-terminal + async lifecycle idempotent

### BD-001 — close intent là terminal

- `Strategy::ApplyGuard`/`ApplyExit` trả kết quả close intent.
- Panel close, Money Guard và basket exit đều kết thúc tick trước
  `TryOpenSeries`, `TryGridAdd` và `ApplyRealLevels`.
- BUY/SELL exit vẫn được đánh giá cả hai để có thể gửi hai nhóm close trước khi
  return.
- Close đang pending từ tick trước chặn open/DCA/modify; panel-open bấm trong
  lúc close được tiêu thụ và log là ignored, không bị queue sang tick sau.

### BD-002 — lifecycle async theo resulting state

- Journal có phase `PENDING_SENT → PENDING_REQUEST_ACCEPTED`; REQUEST accepted
  không còn deactive entry/busy guard.
- Ghi server order/deal, target/observed volume và snapshot position trước
  request để hỗ trợ DEAL/REQUEST/POSITION đến khác thứ tự.
- Chỉ complete khi resulting state đã quan sát được: position open xuất hiện và
  không còn working order; close volume đã giảm đủ/position đã mất; SL/TP đã
  đúng giá yêu cầu. Reject là terminal ngay.
- Watchdog 5s chuyển thành soft-timeout reconcile/giữ khóa; hard-timeout 30s
  mới nhả sau lần đối soát cuối để tránh deadlock vô hạn.
- Không thêm `Sleep`, không đổi đường gửi request đầu tiên và không thay công
  thức chiến lược.

### Test và hiệu năng

- Offline suite: **277 passed, 0 failed**; UBSan: **277 passed, 0 failed**.
- Thêm permutation REQUEST→DEAL→STATE, DEAL→REQUEST→STATE, state-before-REQUEST,
  reject, partial close volume, soft/hard timeout và coordinator terminal
  trace.
- Sửa test giả “D-chain empty” trước đây dùng `x-x==0`; nay test mảng rỗng thật.
- Benchmark 5 lượt máy review: BD-002 ready-check 3,29–3,67ns/event; BD-001
  scan journal 0..8 entry 3,39–4,57ns/tick. Request đầu tiên không bị trì hoãn.
- Chưa chạy được MetaEditor/MT5 trong sandbox: F7, `RunTests.mq5`, golden
  baseline và async demo soak vẫn là release gate bắt buộc.

## [14.7.0] — 2026-07-26 — FE-407/408: chuỗi khoảng cách DCA theo pip + chuỗi hệ số nhân (Chủ nhà duyệt 4 quyết định)

### FE-407 — Chuỗi khoảng cách DCA thủ công (pip)
- `DistanceMode_`: **Classic** (mặc định — công thức v13 fix 200pt + dynamic ×1.2, giữ nguyên từng bit) / **Manual** dùng `DistanceSequence_` cú pháp xN như chuỗi lot: `10x3-15x2-20` → khoảng #1..3 = 10 pip (lệnh #2..#4), #4..5 = 15 pip, #6+ = 20 pip lặp mãi.
- Đơn vị PIP theo quy ước FE-201: 1 pip = 10 point chuẩn (`BD_POINTS_PER_PIP`) → 10 pip = 1.00 USD trên Vàng mọi sàn 2/3 digit (PointScale áp tại chỗ dùng, y hệt classic); trên FX 5-digit trùng pip tiêu chuẩn.
- Kiến trúc: `Grid_ChainDistancePoints` (thuần, test) + `CDistancePlan` (composition root sở hữu, Strategy nhận qua Init — nhánh classic gọi đúng hàm cũ). Logic trigger KHÔNG đổi: khoảng cách vẫn đo từ GIÁ MỞ LỆNH CUỐI, khớp theo tick chạm mức (không chờ đóng nến); gate 1 lệnh/nến/hướng, MinuteStop, filters giữ nguyên.

### FE-408 — Chuỗi hệ số nhân thủ công
- `eLotMode` thêm lựa chọn thứ ba **Multiplier chain** dùng `MartinSequence_`: `1.03x3-1.3x4-1.25-1.5` → 3 phép nhân đầu (lệnh #2..#4) hệ số 1.03, 4 kế 1.3, 1 kế 1.25, còn lại 1.5 lặp.
- **Công thức lot LÝ THUYẾT dạng đóng** (quyết định Chủ nhà): lot(#count+1) = lot lệnh đầu rổ (pos[0].lots — cùng base martingale v13) × TÍCH `count` hệ số đầu chuỗi. KHÔNG làm tròn trung gian → hệ số nhỏ (1.03) không bao giờ "kẹt" ở bước lot của sàn; làm tròn đúng MỘT lần lúc gửi (Grid_NormalizeVolume + log track FIX-5 rev). Deterministic theo count → Overlap tỉa xong tự tụt bậc (quy tắc đếm theo lệnh ĐANG MỞ, nhất quán 14.2.0). MaxLot vẫn cap.
- `Grid_ChainLot` (thuần, test) + `CChainSizer : ILotSizer` (extension point — không đụng 2 sizer cũ). Chuỗi sai cú pháp → INIT_PARAMETERS_INCORRECT.

### Test 14.7.0
- RunTests +17, offline +19 (đúng 2 ví dụ của Chủ nhà mapping từng bậc; sau tỉa 9→7 lệnh #8 → gap bậc 7 & tích 7 hệ số; anti-stuck 1.03^10; kiểm đơn vị 10 pip = 1 USD trên cả 2/3-digit; no-cap 1.03^200=3.6936 và cap tại 1.03^300) → **250/250 PASS**. Một assert kỳ vọng sai của chính suite (ngộ nhận 1.03^200 vượt cap) được phát hiện nhờ chạy thật và sửa — ghi lại làm bài học test-the-test.

### Re-audit hiệu suất & công thức sau 14.7.0 (cùng ngày — theo yêu cầu Chủ nhà)
- Benchmark lõi tính toán (g++ -O2): WMF_Step ≈ 4.3 ns/nến đóng; Grid_ChainLot(20 bậc) ≈ 17 ns/lệnh mở; toàn bộ arithmetic BE+TP/SL/trail cho rổ 20 lệnh ≈ 24 ns/tick — chi phí thật mỗi tick nằm ở ~≤20 lời gọi API position (mức µs), tổng dưới ~0.1 ms: KHÔNG có nguồn giật lag; không alloc/string/chart-write nào trên tick path ngoài 8 ObjectFind có dirty-check.
- Chứng minh bằng property-test (4 assert mới, tổng 254/254): martingale mặc định vs chuỗi 1 hệ số CÙNG công thức đóng từ lot lệnh đầu — trên sàn bước lot 0.01 trùng nhau TỪNG LỆNH (n=1..30 hệ số 1.5; n=1..40 hệ số 1.03); khác biệt duy nhất là martingale v13 làm tròn 2 chữ số trước (giữ để bảo toàn baseline) nên trên sàn bước 0.001 chain chính xác hơn (0.0225 → 0.023 thay vì 0.02).
- Không phát hiện bug/xung đột mới; ghi chú cosmetic: LotMode=Multiplier chain không log nhắc khi LotSequence_ bị bỏ qua (vô hại).

## [14.6.1] — 2026-07-26 — FE-406: mũi tên BUY/SELL WMF trên chart + deep audit (1 bug tìm thấy & vá)

### FE-406 — Hiển thị tín hiệu WMF trên chart (yêu cầu Chủ nhà)
- Input `ShowWmfSignals=true`: khi `SignalSource_=WMF`, EA vẽ mũi tên BUY (xanh, dưới low nến) / SELL (đỏ, trên high nến) tại các nến giao cắt — tương đương plotshape của indi. Vẽ cả ~100 tín hiệu LỊCH SỬ khi seed (nhìn chart giống TradingView ngay khi gắn EA); ring 200 mũi tên, cũ nhất tự xóa — chart không rác.
- Kiến trúc đúng quy tắc 3: `CWmfSignal` chỉ THU THẬP marks (`SWfMark`/`TakePendingMarks` — one-shot), composition root chuyển cho `Panel.MarkWmfSignal` — module duy nhất đụng chart objects. Idempotent theo tên object (reseed vẽ lại không nhân đôi, không đốt ring).

### AU-14-11 [TB — tìm thấy trong deep audit vòng này, đã vá]
- **Bug:** ở 14.6.0, cross event được đánh dấu bằng cờ cục bộ `steppedNew` chỉ đúng trong tick đã step nến WMF mới; nếu đúng tick đó CopyBuffer stochastic fail (buffer trễ 1 tick — hiếm nhưng có thật), lượt retry tick sau có `steppedNew=false` → **tín hiệu giao cắt bị NUỐT MẤT** ở chế độ Cross + Use_Stoh.
- **Fix:** thay bằng `m_pendingCross` (+1/−1/0) đặt tại thời điểm step, SỐNG QUA các lượt retry, chỉ bị tiêu thụ (về 0) sau khi đánh giá tín hiệu thành công — cross không bao giờ mất, vẫn bắn đúng một lần. Có test mô hình khóa hành vi.

### Audit 14.6.x
- Rà toàn văn WmfSignal bản chốt + wiring 4 file; 20/20 file cân bằng cú pháp; suite 232/232 PASS.
- Ghi chú hành vi (không phải bug): `WmfTF` nhỏ hơn TF chart → mỗi nến chart có thể re-seed toàn bộ (đúng nhưng tốn; khuyến nghị WmfTF ≥ TF chart — mặc định PERIOD_CURRENT là chuẩn); tín hiệu Cross khi gắn EA có thể bắn ngay nếu nến đóng gần nhất là nến giao cắt (đồng nhất với hành vi attach của signal BD).

## [14.6.0] — 2026-07-26 — FE-405: WMF Signal — port TradingView "WUYX Momentum Follower" (Pine v5)

### Tính năng (plan được Chủ nhà duyệt: cả 2 mode, default Cross, đủ input như indi gốc)
- Module mới `WmfSignal.mqh` — implementation thứ hai của `ISignal` (minh chứng extension point #5). Input `SignalSource_` chọn nguồn tín hiệu: **BD RSI (mặc định — baseline không đổi)** / **WMF**. Chỉ signal được chọn mới được Init (tạo handle); `CRsiStochSignal` KHÔNG bị sửa một dòng.
- Bản chất WMF: Volatility Stop (ATR ratchet, chỉ xiết một chiều đến khi giá xuyên → lật trend + reset extremes) × EMA. `WMF_Step` (hàm thuần, có test đối chiếu TÍNH TAY chuỗi 6 nến 2 lần lật) tái lập đúng thứ tự Pine: max/min ratchet → stop ratchet → so trend (>= 0) → reset khi lật → EMA đệ quy alpha=2/(len+1).
- Input đủ như indi gốc TradingView: `WmfTF`, `WmfLength=20` (ATR, minval 2), `WmfPrice` (Source: Close/Open/High/Low/Median/Typical/Weighted — như `src` Pine), `WmfFactor=1.0` (Multiplier), `WmfEmaLength=2`. Hai input màu (barcolor/bgcolor) là hiển thị thuần túy của TradingView, không ảnh hưởng tín hiệu → không port. Input sai (len<2, factor<=0) → INIT_FAILED kèm log.
- `WmfMode`: **Cross** (mặc định — đúng nhãn BUY/SELL của indi, `ta.crossover/crossunder` EMA vs vStop, chỉ bắn 1 lần trên nến WMF có giao cắt) / **Trend** (trạng thái màu nến: EMA trên/dưới vStop — nhịp vào lệnh liên tục như RSI hiện tại; bằng nhau → không tín hiệu, khớp màu đen của indi).
- ATR qua `iATR` (Wilder — trùng `ta.atr` Pine); warmup fallback `nz(..., ta.tr)` mô phỏng bằng range nến. **Seed**: chạy lại tối đa 1000 nến đóng (oldest→newest) để hội tụ hệ đệ quy — vài nến đầu warmup có thể lệch nhẹ so TradingView, hội tụ nhanh sau vài lần lật (ghi nhận). Gap nhiều nến (EA tắt lâu) → tự re-seed toàn bộ. Tín hiệu chỉ tính trên NẾN ĐÓNG (shift 1), gate 1 lần/nến chart như signal BD.
- **Bộ lọc Stochastic áp cho CẢ HAI signal** đúng yêu cầu Chủ nhà: CWmfSignal mang y nguyên luật xác nhận (SELL cần stoch ≥ Up_Level, BUY cần ≤ Down_Level khi Use_Stoh) — nhân bản có chủ đích ~15 dòng để không refactor class cũ ([STRATEGY-BEHAVIOR] bit-exact).

### Test 14.6.0
- RunTests.mq5 +15 assert; offline suite +15: applied price 5 case + chuỗi tham chiếu tính tay (stop 98→99→99→98→97→97; up T,T,T,F,F,T; SELL crossunder tại b4, BUY crossover tại b6; EMA khớp 1e-6) → **226/226 PASS**; 20/20 file cân bằng.

## [14.5.0] — 2026-07-26 — FE-404: Mobile Control qua lệnh chờ giá đặc biệt (CCBSN manual)

### Tính năng
- Module mới `MobileControl.mqh`: quét lệnh chờ trong OnTimer (500ms, live/demo only — tester skip), nhận diện 6 lệnh điều khiển theo đúng bảng CCBSN, thực thi rồi XÓA lệnh chờ. Chỉ xét lệnh chờ đúng symbol chart, bỏ qua volume và magic (đặt tay từ mobile → magic 0). Input `UseMobileControl=true` (tắt được).
- Mapping vào cờ runtime Black Dragon: Buy Stop **999999** → `Cfg.RemoteStop=true` (chặn MỌI lệnh mở tự động — chuỗi mới + DCA cả 2 chiều — qua CPauseFilter trên cả 2 chain; exits/quản lý rổ vẫn chạy); Buy Stop **666666** → khôi phục hoàn toàn (`RemoteStop/PauseBuy/PauseSell = false` — có xóa cả Stop Buy/Sell, KHÔNG đụng NewCycle); Buy Stop **888888** → `NewCycle=false`; Sell Limit **888888** → `NewCycle=true`; Buy Stop **555555** → `PauseBuy=true` (chặn mọi lệnh Buy kể cả DCA, như nút panel); Sell Limit **555555** → `PauseSell=true`.
- Hàm thuần có test: `MC_Command(type, price)` (tolerance 0.5 quanh giá đặc biệt — xa mọi giá thật), `MC_Apply(...)` (idempotent — xóa lệnh fail thì scan sau tự thực thi lại + xóa lại, không lệch trạng thái).
- `ExecutionLayer.DeleteOrder(ticket)` (TRADE_ACTION_REMOVE, luôn sync — chạy trên timer path, hiếm và do người dùng chủ động); panel `RedrawButtons()` + `Persist_Save()` sau mỗi lệnh điều khiển → trạng thái remote sống qua restart.
- **Persistence bump "BD14"→"BD15"** (+field remoteStop): file trạng thái cũ bị từ chối 1 lần → về defaults (chỉ mất toggle panel một lần sau khi nâng cấp — ghi nhận chấp nhận).

### Ghi chú hành vi
- RemoteStop không có nút panel riêng (nhận biết qua log + EA ngừng mở lệnh); nút Open Buy/Sell tay trên panel vẫn bypass (triết lý xuyên suốt — remote stop nhắm vào lệnh tự động).
- Không xung đột watchdog FIX-1: `HasLiveOrder` lọc magic của EA, lệnh chờ mobile magic 0 nằm ngoài.
- Cảnh báo từ manual giữ nguyên giá trị: chỉ dùng LỆNH CHỜ với giá đặc biệt; đừng đặt các giá này vào market order.

### Test 14.5.0
- RunTests.mq5 +19 assert; offline suite +22 (mapping 6 lệnh, sai loại lệnh → NONE, tolerance in/out, apply idempotent, resume xóa đúng cờ và không đụng NewCycle) → **211/211 PASS**; 19/19 file cân bằng cú pháp.

## [14.4.0] — 2026-07-26 — FE-403: Giới hạn thời gian theo giờ PC/Local (CCBSN manual)

### Tính năng
- Nhóm input mới (qw11): `UseTimeLimit` (master, default OFF), 4 khung giờ `UseTime1..4` + `TimeNStart/End` định dạng "HH:MM" (**giờ PC/Local — TimeLocal()**; trong Strategy Tester TimeLocal = giờ server mô phỏng, có log nhắc), `DcaOutsideTime` — true thì grid add DCA vẫn được phép ngoài khung giờ.
- `EntryFilters.mqh`: hàm thuần `TL_ParseHHMM` (chấp nhận "7:05", khoảng trắng; từ chối 24:00/12:60/thiếu số/chữ), `TL_InWindow` ([start, end) nửa mở, hỗ trợ khung QUA ĐÊM start>end, start==end = rỗng); `CTimeSchedule` (parse + validate 1 lần lúc Init, any-match 4 khung); `CTimeFilter(sched, forGrid)` — bản new-series chặn cứng, bản grid tôn trọng `DcaOutsideTime`.
- Đăng ký tại composition root CHỈ khi `UseTimeLimit=true` (tắt = 0 chi phí, baseline không đổi từng bit) — minh chứng extension point thứ 4 sau AdxFilter/CSequenceSizer/CHaltFilter.
- Fail-fast cấu hình (cùng lớp lỗi cú pháp LotSequence): HH:MM sai định dạng, start==end, hoặc bật master mà không bật khung nào → `INIT_PARAMETERS_INCORRECT` + log chỉ rõ khung lỗi.
- Ranh giới hành vi: time limit chỉ chặn MỞ lệnh tự động (chuỗi mới + grid add); mọi exit (TP/SL/trailing/Overlap/MoneyGuard/daily) và nút panel vẫn hoạt động ngoài khung giờ. Filter giờ v13 (`Start_Hour/End_Hour`, giờ server, chỉ lệnh đầu chuỗi) độc lập — cả hai cùng áp nếu cùng bật.

### Deep audit sau 14.3.0 + 14.4.0 (RRI-T, cùng ngày)
- Re-scan 18 file: cân bằng ngoặc/guard 18/18; version đồng bộ; wiring FE-401/402/403 đủ điểm chạm; **0 bug mới**.
- Soát tương tác chéo: HaltFilter × TimeFilter là AND độc lập trên chain; DcaOutsideTime chỉ tác động instance grid; exits không đi qua chain (đóng lệnh ngoài giờ vẫn chạy — đúng thiết kế); MoneyGuard closes không bị time limit chặn.
- Ghi chú cosmetic: thứ tự nhóm input trong dialog là qw9 (Money) → qw11 (Time) → qw10 (Daily) → qw8 (Lot & Pip) — nhãn nhóm rõ ràng nên giữ nguyên, dọn khi tiện.

### Test 14.4.0
- RunTests.mq5 +20 assert (parse 12 case, window 8 case); offline suite +30 (thêm e2e: 2 khung gồm 1 khung qua đêm, biên inclusive/exclusive, bypass DCA đúng từng chain) → **189/189 PASS**.

## [14.3.0] — 2026-07-26 — TIP-501: Money Close (FE-401) + Daily Target (FE-402) theo CCBSN manual

### Module mới: MoneyGuard.mqh (read-only consumer — không bao giờ tự gửi lệnh)
- Hàm thuần có test: `MG_MoneyTpHit/SlHit` (TP dương, SL âm, 0 = off), `MG_PctDiffHit` (công thức CCBSN: (chiều lời) + (chiều lỗ × (1+%)) ≥ 0 — ví dụ doc Buy +10/Sell −8/2% → +1.84 → đóng; chỉ xét khi có chiều đang lỗ), `MG_DailyTpHit/SlHit` ($ và % trên số dư đầu ngày).
- `CMoneyGuard.Check()` mỗi tick, ưu tiên scope rộng nhất: (1) Money TP/SL **toàn account** (ACCOUNT_PROFIT, mọi magic/symbol) → (2) **Daily target/limit** (scope Magic — quyết định Chủ nhà; đóng rổ + halt) → (3) Money TP All **hedged** (chỉ khi CẢ 2 rổ cùng mở — quyết định Chủ nhà) rồi Money TP/SL All thường (magicNet = buy+sell totalProfit) → (4) %-diff close-all → (5) Money TP/SL riêng Buy/Sell. Input sai dấu → warn + OFF (không chặn EA, tinh thần 14.2.2).
- FE-402: dayNet = DayProfit (realized hôm nay, C2) + floating 2 rổ; số dư đầu ngày chụp tại SeedDayProfit (= balance − realized hôm nay; nạp/rút giữa ngày sẽ làm lệch — giới hạn ghi nhận). Đạt target/limit → đóng 2 rổ + **halt đến 00:00 ngày mới + NewDayDelayMin phút**. Restart giữa halt: tự suy lại từ realized (self-healing); riêng cửa sổ delay đầu ngày mới mất nếu restart đúng lúc đó (chấp nhận, ít state).
- `CHaltFilter : IEntryFilter` đăng ký vào CẢ 2 chain (chuỗi mới + grid add) — halt chỉ chặn lệnh TỰ ĐỘNG; nút panel vẫn bypass (quyết định Chủ nhà). Panel hiện "DAILY HALT till..." trên title khi nghỉ.

### Hạ tầng
- `ExecutionLayer`: `ClosePositionEx(ticket)` đóng lệnh BẤT KỲ symbol/magic (tick + filling mode theo symbol của position, guard async tái dùng HasPendingClose) + `CloseAllAccount()`; `FillingFor(symbol)` tách từ DetectFilling; retry sync giờ refresh giá theo `req.symbol` (đúng cho close chéo symbol).
- `Strategy`: bước 1.5 `ApplyGuard` chạy TRƯỚC exits thường; `AddGridFilter()` — extension point mới cho grid chain; Init nhận thêm con trỏ guard.
- `BasketManager`: `m_dayStartBalance` + `DayStartBalance()`.
- Config: 15 input mới nhóm qw9/qw10, **default 0/off toàn bộ → không bật gì thì hành vi 14.2.2 giữ nguyên từng bit** (baseline an toàn).

### Test 14.3.0
- RunTests.mq5 +20 assert; offline suite +32 (ngưỡng, công thức doc + biên 8.17/8.15, ưu tiên scope, hedged cần cả 2 rổ, e2e chu kỳ: đạt target → đóng+halt → không re-fire → còn nghỉ 30' đầu ngày mới → resume; restart tự suy lại halt) → **159/159 PASS**.

## [14.2.2] — 2026-07-26 — FIX-5 rev: lot dưới min KHÔNG dừng EA (quyết định Chủ nhà)

- **Đảo hành vi FIX-5 của 14.2.1** theo chỉ đạo Chủ nhà: bậc lot nằm ngoài giới hạn khối lượng của sàn không còn chặn EA khởi động. Thay vào đó: `Grid_NormalizeVolume` áp min/step/max của symbol lúc gửi lệnh (dưới min → **dùng MIN LOT của sàn**, đúng clamp v13), và `OpenMarket` ghi **log KHÔNG throttle cho từng lệnh bị điều chỉnh** — `order #n lot adjusted: requested X -> using Y` — để Chủ nhà track đầy đủ trong journal.
- OnInit vẫn cảnh báo sớm (`Log_Warn`) nếu chuỗi có bậc ngoài giới hạn — biết trước, không bất ngờ. Lỗi CÚ PHÁP chuỗi (`0.01x`, `abc`…) vẫn fail-fast `INIT_PARAMETERS_INCORRECT` như cũ — chỉ nới phần giới hạn khối lượng.
- `Grid_ValidateVolumes` giữ nguyên (giờ đóng vai heads-up); AU-14-07 chốt theo hướng này. Test: offline suite +4 assert mô hình normalize (0.005→0.01, 0.004→0.01, 0.02 giữ nguyên, phát hiện điều chỉnh); tổng 127/127 PASS.

## [14.2.1] — 2026-07-26 — TIP-401: async mặc định + 6 fix nhỏ (Chủ nhà duyệt cả gói)

### Async là chế độ mặc định (FIX-2)
- `ExecMode` default đổi `exec_Sync` → **`exec_Async`** theo yêu cầu Chủ nhà (tăng tốc xử lý: OrderSendAsync không chờ sàn trả lời; đóng cả rổ bắn song song). Tester vẫn tự fallback sync — backtest/optimization không đổi. `.set` baseline cập nhật `ExecMode=1`.
- Cơ chế an toàn async (tóm tắt cho người tiếp nhận): journal request → xác nhận qua OnTradeTransaction; watchdog 5s; busy-flag mỗi hướng cho OPEN; HasPendingClose/HasPendingModify chống gửi trùng; lệnh lỗi/reject tự gửi lại tick sau với giá mới (điều kiện thoát ảo còn đúng thì không bao giờ bỏ quên lệnh); partial fill → đóng nốt tick sau; mất kết nối → retry mỗi tick + yêu cầu VPS vì TP/SL ảo.

### Fix
- **FIX-1 [async]** Watchdog: trước khi nhả busy-slot của lệnh MỞ quá 5s không hồi âm, quét `OrdersTotal` tìm order (magic+symbol) còn "sống" trên sàn — còn thì giữ slot, chờ tiếp. Bịt khe hở duplicate-open khi sàn lag >5s (race hiếm ghi nhận từ 14.0.1). CLOSE/MODIFY vẫn nhả như cũ (đã có guard chống trùng riêng).
- **FIX-3 [async]** Nút panel Open Buy/Sell tôn trọng busy-flag trong async (click khi lệnh mở đang bay → bỏ qua + log). Sync không đổi (flag luôn false).
- **FIX-4** ApplyRealLevels bỏ qua ticket có modify đang chờ xác nhận — hết log "modify SL/TP failed" gây hiểu nhầm (N-2 đóng).
- **FIX-5** `Grid_ValidateVolumes` (thuần, có test) + `CSequenceSizer.ValidateVolumes`: chuỗi lot được đối chiếu VOLUME_MIN/MAX/STEP của symbol ngay tại OnInit — bậc không khớp sàn → `INIT_PARAMETERS_INCORRECT` + chỉ rõ bậc và lý do. Đóng AU-14-07 cho mode chuỗi (martingale/autolot giữ clamp v13 trong Grid_NormalizeVolume).
- **FIX-6 [cosmetic]** `BD_MAX_LOT_STEPS` chuyển về khối constants của Config.mqh.

### Test 14.2.1
- Offline suite 123/123 PASS (+10: watchdog giữ/nhả slot theo trạng thái order sống, validate chuỗi đủ 4 nhánh + case làm tròn float 0.07/0.35). RunTests.mq5 +5 assert FIX-5.
- Baseline: sync-mode và tester không đổi hành vi; async default chỉ ảnh hưởng live/demo — README nhấn mạnh bước soak async 2-4 tuần trước tiền thật.

## [14.2.0] — 2026-07-26 — FE-301: LotMode input + chuỗi lot xN + quy tắc đếm thứ tự (Chủ nhà duyệt plan trước khi code)

### FE-301a — Input chọn chế độ lot DCA
- Enum mới `eLotMode { lot_Multiplier, lot_Sequence }` + input `LotMode_` (mặc định `lot_Multiplier` = martingale ×`Martin_` y hệt v13). Không còn tự suy theo chuỗi rỗng như 14.1.0 — Chủ nhà chọn tường minh.
- `LotMode_=lot_Sequence` + chuỗi rỗng/sai → `INIT_PARAMETERS_INCORRECT` + log hướng dẫn. `LotMode_=lot_Multiplier` + chuỗi có giá trị → log "sequence ignored".

### FE-301b — Cú pháp chuỗi lot mở rộng `lot x số-lần`
- `Grid_ParseLotSequence` hỗ trợ `0.01x5-0.02x3-0.05`: bung phẳng thành 9 bậc — 5 lệnh đầu 0.01, 3 lệnh kế 0.02, từ lệnh 9 vào 0.05 và lặp bậc cuối đến khi rổ đóng toàn bộ (new cycle tự về bậc 1 vì đếm theo số lệnh mở).
- Chấp nhận x/X, khoảng trắng tự do. Từ chối: `x0`, `x` cụt, `x5` không có lot, count lẻ (`x2.5`), lot dính ký tự lạ (`0.01a` — StringToDouble của MQL5 bỏ qua rác đuôi nên phải check ký tự tường minh), quá trần `BD_MAX_LOT_STEPS=200` bậc sau khi bung.

### FE-301c — Quy tắc đếm thứ tự lot khi Overlap tỉa lệnh (QUYẾT ĐỊNH CỦA CHỦ NHÀ 26/07/2026)
- **CẢ HAI chế độ đều đếm theo số lệnh THỰC TẾ ĐANG MỞ** (`side.count`): mở 9, Overlap tỉa 2 còn 7 → lệnh kế tiếp là **lệnh số 8** — chuỗi thủ công lấy bậc 8, martingale = hệ số^7 (đúng công thức v13, không đổi).
- Comment `|n` đánh cùng số đó (`|8`) — lot và comment luôn cùng một thứ tự. (Phương án "đếm tổng lệnh đã mở kể cả lệnh bị tỉa" đã được trình trong plan và Chủ nhà chọn KHÔNG dùng — ghi lại đây để AI sau không "sửa giùm".)
- Hệ quả code: không cần bộ đếm mới, không cần khôi phục sau restart — `side.count` rebuild từ pool là đủ.

### Test 14.2.0
- RunTests.mq5: +21 assert (bung xN đúng mapping bậc 1-5/6-8/9+, 7 case từ chối, kịch bản tỉa 9→7 → bậc 8 = 0.02, martingale ^7, vượt chuỗi lặp 0.05, new cycle về bậc 1). Offline suite: 101/101 PASS.
- Baseline: mode mặc định giữ nguyên 100% hành vi 14.1.0/v13.

### Re-audit toàn bộ sau 14.2.0 (26/07/2026 — RRI-T vòng 2, deep review + e2e)
- Re-scan 19 file trạng thái cuối: KHÔNG phát hiện bug mới mức cao/trung bình; 0 vi phạm 6 quy tắc kiến trúc; các fix AU-14-xx và FE-xxx đều còn nguyên vẹn, không dẫm chân nhau (PointScale không bị nhân đôi; sizer/comment/RefreshFloating/async guard độc lập đúng thiết kế).
- Offline suite bổ sung PART 8 — mô phỏng e2e NGUYÊN chu kỳ DCA xâu chuỗi hàm thật của các module (scale → grid distance → chuỗi lot → overlap tỉa → đánh số lại → BE/TP): sàn 2 digit và 3 digit cùng .set cho ra thang giá USD, chuỗi lot, số comment GIỐNG HỆT; tổng suite 113/113 PASS.
- Sửa tài liệu: ARCHITECTURE.md cập nhật bảng "Tính năng → File" (FE-201/202/203/301) + thêm quy tắc cứng 7-8-9 (cache tĩnh/RefreshFloating; PointScale cho input points mới; đếm thứ tự theo lệnh đang mở).
- Ghi chú mức THẤP giữ nguyên trạng thái theo dõi (không phải bug): nút panel mở tay trong async không check busy-flag → có thể trùng số comment (hành vi bypass v13, cosmetic); log warn "modify SL/TP failed" xuất hiện có throttle trong cửa sổ chờ async modify; AU-14-07 (lot dưới VOLUME_MIN bị kéo lên min — đáng cân nhắc hơn khi dùng chuỗi lot thủ công) và AU-14-10 vẫn deferred chờ Chủ nhà.

## [14.1.0] — 2026-07-26 — 3 tính năng mới theo yêu cầu Chủ nhà (FE-201/202/203)

### FE-201 — Chuẩn hóa pip cho Vàng trên mọi sàn (2 hoặc 3 số thập phân)
- **Quy ước:** 1 giá (1 USD) = 10 pips ⇒ 1 pip = 0.1 USD. Quote chuẩn tham chiếu = Vàng 2 digit (point 0.01).
- `GridEngine`: `Sym_PointScalePure(isGold, point)` (thuần, có test) trả về số broker-point tương đương 1 point chuẩn: sàn 2 digit → 1, sàn 3 digit → 10; symbol không phải Vàng → 1. `Sym_IsGold()` nhận diện qua SYMBOL_CURRENCY_BASE=="XAU" hoặc tên chứa XAU/GOLD. Input `AutoGoldPip=true` cho phép tắt (scale ép 1).
- Áp scale MỘT LẦN tại OnInit (`Config_ApplyPointScale`): Cfg.TP/SL/TrailStart/TrailDistance nhân scale; grid distance nhân tại Strategy.TryGridAdd; MaxSpred nhân tại CSpreadFilter. Spread thật (ctx.spreadPoints) giữ nguyên broker points — so sánh đồng đơn vị.
- **Kết quả:** cùng một .set, `Fix_Distance=200` = 2.00 USD = 20 pips trên MỌI sàn Vàng, bất kể 2 hay 3 digit. Log Init in rõ digits + PointScale để đối chiếu.
- *Baseline:* sàn 2 digit và mọi symbol không phải Vàng → scale=1, hành vi KHÔNG đổi. Sàn Vàng 3 digit → hành vi ĐỔI CÓ CHỦ ĐÍCH (trước đây khoảng cách/TP nhỏ hơn 10 lần so với thiết kế).

### FE-202 — Chuỗi lot thủ công cho DCA (bên cạnh martingale)
- Input mới `LotSequence_` (nhóm qw8), ví dụ `0.01-0.02-0.04`, phân cách `-`. Rỗng (mặc định) = giữ nguyên martingale v13.
- `GridEngine`: `Grid_ParseLotSequence()` (thuần, có test — từ chối token rỗng/không phải số/≤0) + `CSequenceSizer : ILotSizer` — lệnh DCA thứ n dùng lot thứ n; vượt quá độ dài chuỗi → lặp lot cuối; MaxLot vẫn cap; Autolot bị bỏ qua khi chuỗi active (chuỗi CHÍNH LÀ quyết định sizing).
- OnInit chọn sizer qua đúng extension point ILotSizer (P5). Chuỗi không hợp lệ → `INIT_PARAMETERS_INCORRECT` + log rõ — fail-safe, không bao giờ trade với lot sai.

### FE-203 — Comment kèm thứ tự lệnh DCA: "commentinput|n"
- `ExecutionLayer`: `Exec_BuildComment(base, n)` (thuần, có test) → `sOrdComm|n`, n = thứ tự 1-based trong chuỗi DCA. Ví dụ comment "EaBd": lệnh đầu `EaBd|1`, lệnh 2 `EaBd|2`.
- `OpenMarket(dir, volume, dcaIndex)` — 4 call site: mở chuỗi = 1, grid add = count+1, 2 nút panel = count+1 (lệnh tay gia nhập rổ nên đánh số tiếp).
- EA không parse comment ngược (C6 giữ nguyên) — chỉ phục vụ người đọc deal list/tool ngoài. Lưu ý: server/broker có thể cắt comment dài (>31 ký tự) hoặc ghi đè — không ảnh hưởng logic.

### Test 14.1.0
- RunTests.mq5: +26 assert mới (scale 2/3 digit, parse hợp lệ/không hợp lệ, sizer indexing + lặp lot cuối, comment format). Offline suite: 77/77 PASS.
- Nghiệm thu MT5-side: compile → RunTests ALL GREEN → với sàn Vàng 3 digit, kiểm tra log Init `PointScale=10` và khoảng cách lệnh thực tế ≈ 2 USD với set mặc định.

## [14.0.2] — 2026-07-26 — Audit ngoài theo Vibecode Kit v5 / RRI-T (5 Personas × 7 Dimensions)

### Bug fix (findings AU-14-xx, xem README §Fixlog để tra nhanh)
- **AU-14-01 [NGHIÊM TRỌNG — P0]** `BasketManager`: tối ưu C1 cache cả floating profit/totalProfit (chỉ ghi khi Rebuild) → giữa các trade event giá trị đóng băng ⇒ **Overlap gần như không bao giờ bắn** (snapshot luôn chụp ngay sau khi lệnh mới khớp, lastProfit ≤ 0) và panel hiển thị P/L cũ. Fix: thêm `RefreshFloating(side)` chạy mỗi tick trong `Update()` — đọc lại POSITION_PROFIT + POSITION_SWAP cho từng ticket đã cache, cập nhật `pos[].profit`, `totalProfit`, `swapSum` (field mới trong `BasketSide`). Thay thế `SwapSum()` cũ nên **không tăng** API call mỗi tick. Nguyên tắc rút ra: C1 chỉ được cache dữ liệu tĩnh theo sự kiện (ticket, lots, giá mở); dữ liệu biến thiên theo giá phải đọc tươi.
  - *Deviation baseline DỰ BÁO:* số lần Overlap bắn tăng trở lại ngang v13 (v14.0.0/14.0.1 hụt hẳn — đây là regression, không phải hành vi chuẩn). TP/SL/trailing không đổi.
- **AU-14-02 [TB — async]** `ExecutionLayer`: Real-mode + Async gửi lặp ModifySlTp mỗi tick trong cửa sổ chờ server xác nhận (AU-2 chỉ guard CLOSE). Fix: `HasPendingModify(ticket)` tra journal, chặn trong `ModifySlTp` (đối xứng `HasPendingClose`). Sync không đổi.
- **AU-14-03 [TB — tester]** `Persistence`: file trạng thái panel tồn tại qua các pass trong sandbox testing agent → pass sau nạp đè input pass trước, phá tính tái lập golden baseline/optimization. Fix: `Persist_Save/Load` return sớm khi `MQL_TESTER`. Hành vi live/demo giữ nguyên semantics v13 (trạng thái panel ưu tiên hơn input khi re-init — bẫy vận hành đã ghi ở README).
- **AU-14-04 [THẤP]** `SignalEngine`: handle Stochastic chỉ tạo và CopyBuffer chỉ gọi khi `Use_Stoh=true` — trước đây indicator tính mỗi tick vô ích khi tắt (mặc định), và lỗi CopyBuffer stoch kéo dài treo luôn tín hiệu RSI. Logic so sánh giữ nguyên từng bit ([STRATEGY-BEHAVIOR] không đổi: `d` ép 0 khi tắt, nhánh `|| !Use_Stoh` cho kết quả y hệt).
- **AU-14-05 [THẤP]** `SwapSum()` per-tick gộp vào `RefreshFloating` (1 vòng lặp thay 2 mục đích).
- **AU-14-06 [THẤP]** `Slippage_` thành input (Config §v14 Engine, default 3 = hardcode cũ → không đổi hành vi); `req.deviation` dùng input ở cả OpenMarket/ClosePosition.
- **AU-14-08 [THẤP]** `BuildContext`: guard `barTime==0` khi lịch sử chưa đồng bộ.
- **AU-14-09 [THẤP]** Dọn dead code: enum `eSignalBarTP`, define `BD_SIGNALBAR_CLOSED`, `BD_CLOSE_ON_REVERSE` (hành vi hardcode v13 đã ghi chú bằng comment tại Config/SignalEngine).

### Deferred có chủ đích (cần Chủ nhà quyết, KHÔNG tự làm)
- Dùng `SymbolInfoCommissions()` (MT5 build ≥ 6030) thay quét history trong `UseCommissionInBE` — đổi sang API mới, cần chốt build tối thiểu.
- Chính sách REASON_PARAMETERS: hiện input bị trạng thái panel đã lưu đè khi re-init (semantics v13). Muốn input mới thắng → sửa nhỏ trong OnInit.
- AU-14-07: `Grid_NormalizeVolume` kéo lot < VOLUME_MIN lên min lot (giữ nguyên v13; đổi = đổi hành vi chiến lược autolot).
- AU-14-10: cache news 1h (có thể hạ 15–30 phút nếu cần).

### Test v14.0.2
- Offline suite (sandbox, g++): port 33 assert RunTests + 11 test mới AU-14-01/02 + 2 test tương đương AU-14-04 → **48/48 PASS**.
- Còn lại trên terminal MT5 (bắt buộc trước khi chạy thật): compile F7 = 0 error → `Tests/RunTests.mq5` ALL GREEN → golden baseline theo README (khuyến nghị build ≥ 6030 — tester đã sửa swap/margin) → **đối chiếu thêm SỐ LẦN OVERLAP bắn** giữa v13 và v14.0.2 → soak async 2–4 tuần demo.

## [14.0.1] — 2026-07-24 — Deep audit sau big update (rà soát 17 file, đối chiếu v13)

### Bug fix (phát hiện qua audit)
- **AU-1 [CAO]** `Strategy.TryOpenSeries`: thiếu gate hedge — v13 GET_INFO chặn mở CHUỖI MỚI hướng ngược khi `Flag_Use_hedge=false` và hướng kia đang có rổ. Đã thêm `hedgeAllowsBuy/Sell` (đánh dấu [STRATEGY-BEHAVIOR]).
- **AU-2 [CAO, async]** `ExecutionLayer.ClosePosition`: điều kiện exit vẫn đúng cho tới khi lệnh đóng khớp → gửi lặp lệnh đóng cùng ticket mỗi tick. Đã thêm `HasPendingClose(ticket)` tra journal, chặn gửi trùng.
- **AU-3 [TB, real mode]** Spam ModifySlTp vô hạn: cache sl/tp chỉ refresh khi rebuild, nhưng modify không sinh DEAL_ADD → không bao giờ invalidate. Fix kép: (a) `ApplyRealLevels` invalidate sau khi modify thành công; (b) `OnTradeTransaction` invalidate thêm trên `TRADE_TRANSACTION_POSITION`.
- **AU-4 [THẤP]** `OnTradeTransaction`: lọc `trans.symbol == _Symbol` trước khi invalidate — tránh rebuild thừa khi EA khác/symbol khác phát sinh deal.
- **AU-5 [THẤP]** `CAdxFilter`: thêm destructor `IndicatorRelease(m_handle)`; sửa comment header bị lủng củng.

### Đã rà, kết luận ĐÚNG (không sửa)
- Filter giờ (kể cả ca qua đêm Start>End và quirk 0=tắt) khớp v13 dòng 620–630.
- Gate tín hiệu 1 lần/bar dùng bar chart hiện tại — khớp v13 `Time(0)` (dòng 2426–2436).
- Trailing extreme seed bằng CopyHigh/CopyLow từ lệnh cuối; guard DBL_MAX phía sell an toàn.
- Retcode `TRADE_RETCODE_PLACED` cho OrderSendAsync đúng theo docs; watchdog 5s giải phóng busy-flag kẹt.
- Journal chỉ chứa entry async → OnTransaction không ảnh hưởng chế độ sync.
- MinuteStop, spread, martingale lot, BE/TP/SL/overlap: đối chiếu công thức khớp v13.

### Ghi chú vận hành (không phải bug)
- Nút panel mở tay bỏ qua filter/MaxOrders — GIỮ NGUYÊN theo hành vi v13.
- Async: cửa sổ race hiếm giữa xác nhận REQUEST và rebuild — chấp nhận theo thiết kế, watchdog bọc lót.

## [14.0.0] — 2026-07-24 — Big update theo Plan v2 (P0→P5 code-side)

### P0/P2 — Kiến trúc (KHÔNG đổi hành vi)
- Tách 1 file .mq5 ~2.900 dòng thành 14 module trong `Include/BlackDragon/` + `BlackDragon.mq5` (~140 dòng, chỉ event handlers).
- Xóa ~60 biến global → `Cfg` (SConfig), `BasketSide buy/sell` (BasketManager sở hữu), state cục bộ từng module.
- Đặt tên tiếng Anh nhất quán; header contract mỗi file; marker `[STRATEGY-BEHAVIOR]` quanh mọi phép so sánh chiến lược.
- Thêm `Strategy.mqh` (composition root) — bổ sung so với danh sách file Plan v2 để giữ `BlackDragon.mq5` < 200 dòng.
- Giữ nguyên tên input + default v13 → dùng lại được .set cũ, so sánh baseline trực tiếp.

### P1 — Hàm thuần + unit test
- `Grid_DistancePoints`, `Grid_MartingaleLot`, `Grid_FirstLot`, `Basket_Breakeven`, `Exit_*` là hàm thuần.
- `Scripts/BlackDragon/Tests/RunTests.mq5`: 30+ assert cho grid/lot/BE/trail/overlap.

### P3 — Bug fix (Nhóm A) — deviation baseline DỰ BÁO ở edge case
- **#1** Mọi retcode của lệnh đóng được kiểm tra; thất bại → log + retry tick sau (không còn giả định đóng thành công).
- **#2** Trailing ảo: bỏ cửa sổ 100pt — giá gap xuyên mức vẫn đóng rổ.
- **#3** Breakeven: swap có DẤU (v13 MathAbs làm lệch mức khi swap dương); commission tùy chọn qua `UseCommissionInBE` (default false = sát baseline).
- **#4** Bỏ mảng cứng InfoBuyPos[600] → mảng động, không tràn.
- **#5** Sort vị thế tường minh theo (openTime, ticket) — không dựa vào thứ tự pool.
- **#6** Retry gửi lệnh refresh giá mỗi lần; busy-flag tách riêng từng hướng.
- **#7** Xóa toàn bộ Alert+Sleep(5000) → Logger throttle 60s, không block.
- **#8** Guard `tick_value<=0` và `lots<=0` trong breakeven.
- **#9** Trailing sell giữ nguyên quirk cộng spread của v13 (đánh dấu [STRATEGY-BEHAVIOR], đổi sau nếu muốn qua policy mới).
- **#10** Overlap chỉ kích hoạt khi lệnh đầu đang LỖ.
- **#11** News: bỏ scrape investing.com (WebRequest block 120s×3) → MQL5 Calendar API, cache 1h trong OnTimer, fail mode tường minh (`NewsFailMode`).
- **#12** Xóa CopyRates thừa, ~350 dòng dead code không port sang.

### P3 — Hiệu suất (Nhóm C)
- **C1** Rebuild cache vị thế theo sự kiện (OnTradeTransaction), không scan PositionsTotal mỗi tick.
- **C2** Daily profit: seed 1 lần + cộng dồn theo deal đóng, không HistorySelect mỗi tick.
- **C3** Panel redraw theo timer 500ms + dirty check (v13: ~20 ObjectSet mỗi tick).
- **C4** Trailing extreme: seed 1 lần khi rebuild + cập nhật O(1) mỗi tick (v13: CopyHigh/CopyLow alloc mỗi tick).
- **C5** Không còn REFRESH_RATES 2×/tick — 1 lần SymbolInfoTick trong BuildContext.
- **C6** Bỏ parse lot từ comment string mỗi tick.
- **C7** Indicator handle tạo 1 lần trong OnInit, release trong OnDeinit.

### P4 — Async (Nhóm B) + Calendar (Nhóm D)
- `ExecMode=exec_Async`: OrderSendAsync + journal PendingRequest, xác nhận qua OnTradeTransaction, watchdog 5s trong OnTimer, busy-flag chống lệnh trùng. Tester tự fallback Sync.
- Đóng rổ async: toàn bộ request rời đi song song (CloseBasket).
- NewsCalendar dùng CalendarValueHistory/CalendarEventById theo 2 đồng tiền của symbol.

### P5 — Mở rộng mẫu
- `Filters/AdxFilter.mqh` (default OFF): chứng minh 1 tính năng mới = 1 file + 1 dòng đăng ký + input.

### Khác biệt có chủ đích so với v13 (ngoài bug fix)
- Panel dựng lại bằng chart objects chuẩn (nút/label/line tương đương chức năng; bỏ Canvas/CEdit frame trang trí).
- Vẽ icon profit từng lệnh khi đóng (OUT_ZNACHKI/DrawOrderProfit) chưa port — thêm sau qua Panel nếu cần.
- `flag_Close_ot_Obr` (đóng rổ theo tín hiệu ngược) v13 hardcode false → không port code chết.

### Việc còn lại cần terminal MT5 của người dùng (không làm được ngoài MT5)
- Compile trong MetaEditor; chạy RunTests.mq5 → ALL GREEN.
- P0 golden baseline: backtest v13 real-tick 2–3 năm, xuất deal list; chạy v14 (UseCommissionInBE=false) cùng .set → diff.
- P4 soak test: demo 2–4 tuần, 2 chart Sync vs Async cùng settings.
