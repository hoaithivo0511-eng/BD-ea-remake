# PRD bàn giao Builder — BlackDragon EA PR #28

**Mã:** BD-PR28-REMEDIATION-001 · **Phiên bản:** 1.0 · **Ngày:** 05/09/2026

**Phương pháp:** Vibecode MQL5 Full · **Vai trò hiện tại:** CONTRACTOR / VERIFIER của tài liệu

**Trạng thái:** PLAN_READY_FOR_HANDOVER. Đây là kế hoạch triển khai và nghiệm thu, chưa phải kết quả sửa EA. Các trường build/release approval trong gói để trống; không tạo xác nhận owner giả định.

## 1. Mục tiêu sản phẩm và kết quả bàn giao

EA cần duy trì đúng nghĩa vụ bảo vệ PY–RH, kết thúc được request khi đã biết kết quả, ghi nhận đầy đủ cash theo đúng ownership và giảm công việc lặp trong đường xử lý tick. Builder phải tạo một candidate có thể audit lại từ source tới artifact và tình huống giao dịch, không chỉ có compile xanh.

Ba kết quả bắt buộc:

1. Khép F01, F02, F03 và F05 bằng regression có oracle độc lập, kiểm tra tích hợp native và đối chiếu đúng source candidate. F04 khép sau khi chính sách cash/ngày liên quan được chốt.
2. Đo baseline sau sửa lỗi, rồi giảm scan/history/sort/state I/O bằng thay đổi bảo toàn hành vi; chứng minh bằng call counters và benchmark hoàn tất.
3. Bàn giao PR/diff, source identity, spec/decision liên quan, TIP, Completion Report, test matrix và manifest có hash đủ để verifier chạy lại. Trạng thái chưa test hoặc test thất bại phải giữ nguyên.

Không có mục tiêu lợi nhuận, drawdown, tỷ lệ thắng hay tối ưu tham số giao dịch trong PRD này. Các chỉ tiêu tài chính đó cần một nghiên cứu chiến lược riêng với dữ liệu, chi phí và tiêu chuẩn out-of-sample.

## 2. Authority, baseline và quy tắc cập nhật HEAD

| Trường | Giá trị được chốt |
| --- | --- |
| Repository | `hoaithivo0511-eng/BD-ea-remake` |
| PR tham chiếu | [PR #28](https://github.com/hoaithivo0511-eng/BD-ea-remake/pull/28#issuecomment-5548875288) |
| Audit HEAD | `d3b5ce19cfdde52b9cb49fe14f1b50915fd0604d` |
| Audit tree | `e246b49b8fafcb081f21277ce39514f728168983` |
| PR base | `3265182639f9be1b448cd4356a891e461bc49db6` |
| Kiểm tra lại khi lập PRD | HEAD vẫn như trên; PR open/draft, chưa merge; xem `HEAD_CHECK.json` |
| Semantic authority kế thừa | `BlackDragon_v14/docs/vibecode/T17_22_py_protection/EA-SPEC.yaml` và `DECISIONS.yaml`; đối chiếu thêm quyết định cũ ở module bị tác động |
| Audit đầu vào | `inputs/BD-EA-PR28-Audit-Evidence.zip` và báo cáo HTML trong gói; hash trong `PROJECT_STATE.yaml` |
| Bằng chứng đã có | 54/54 nhóm local regression/source contract PASS; 6 phản ví dụ cho 5 phát hiện; CI metadata success đúng HEAD |
| Bằng chứng còn thiếu | Artifact CI chưa tải được để tự kiểm hash; chưa có native MT5/profile mới từ đợt audit |

**Bước đầu của builder:** đọc AGENTS.md và active project manifest trong checkout thực tế. Fetch/read HEAD hiện hành. Nếu đã khác audit HEAD, tạo `BASELINE_DELTA.md`: liệt kê commit, module liên quan, F01–F07 còn tồn tại hay đã được sửa, bằng chứng kiểm lại. Không ghi đè sửa mới của team bằng patch dành cho HEAD cũ. Base triển khai mới phải được ghi riêng cùng hash; mọi test/audit cuối dùng candidate HEAD/tree đó.

Giữ ba mốc riêng: **B0** = audit baseline; **B1** = bản đã sửa correctness; **C** = bản tối ưu từ B1. So B0→B1 bằng kỳ vọng bug fix; so B1→C bằng bảo toàn hành vi và benchmark. Dùng B0 làm chuẩn performance duy nhất có thể thưởng nhầm một bản nhanh hơn vì bỏ mất công việc.

Lệnh owner giao team triển khai phạm vi rõ ràng là authority cho phạm vi đó; không yêu cầu xác nhận lại từng task thường lệ. Việc tạo PRD ở đây không tự chứng minh owner đã duyệt các đề xuất đổi semantics mới. `OWNER_APPROVAL.template.json` chỉ được điền từ sự kiện phê duyệt có thật, gắn đúng hash tài liệu/build.

## 3. Phạm vi và những ý nghĩa phải giữ

**Pha A — correctness bắt buộc:** F01 pre-arm exposure; F02 async terminal result; F03 replay/cash cursor; F05 position identity và tính hợp lệ của cost; F04 daily cash sau quyết định D-201/D-202; kiểm kê và thiết kế an toàn cho F06.

**Pha B — performance bắt buộc sau baseline:** snapshot/aggregate dùng chung, history gia tăng có reconcile, streaming sum thay build-sort không cần thiết, bounded journal, retry có backoff đã chốt. Mỗi thay đổi có phép đo và differential trace.

**Pha C — tùy chọn có điều kiện:** đổi policy ADX theo D-204; profit oracle trên symbol cần portability theo D-205; tháo dần inheritance/macro sau khi trace ổn định. Không đưa ML, ONNX, Kalman hoặc adaptive entry vào scope mặc định.

Các invariant kế thừa:

- PY BUY/SELL được nhận diện theo hướng thực và cohort chính xác; không chiếm position Core/RH hoặc EA khác.
- BUY confirmed SL không hạ; SELL confirmed SL không nâng; cash floor không bị giảm bởi ADD hoặc partial close.
- Trước arm phải giữ được exposure envelope RH; PY tự tài trợ chi phí bảo vệ/phối hợp; khoản trim tính đúng một lần và không trở thành Core funding credit.
- Account emergency giữ ưu tiên đã duyệt. Một operation PY chờ chưa đủ dữ liệu không được vô tình loại bỏ exit độc lập mà contract cho phép.
- Nhóm chỉ reset khi đúng cohort đã flat và mọi nghĩa vụ settle; campaign ledger/serial không bị xóa tùy tiện.
- T17.20 one-bar gate, T17.21 comment schema, Core TP/LIFO và các exit hiện có giữ đúng nghĩa. Không đổi input name/type/order/default, magic, symbol/timeframe, sizing hoặc ngưỡng risk nếu không có change request tương ứng.
- Phân biệt phase Recovery với phase PY: Recovery `WAIT_RESET`/`ARMED` chặn Core DCA, còn Pyramid ADD theo settings; Recovery `EXHAUSTED` chặn DCA và Pyramid ADD nhưng giữ Peel/close giảm rủi ro. Không dùng một kết quả WAIT của PY để vô tình đổi các quy tắc này.
- Dữ liệu không xác định có trạng thái UNKNOWN/INVALID/STALE; không tự gán 0 chi phí, 0 exposure hoặc coi request thành công.

## 4. Quyết định và giả định RRI

Các đề xuất dưới đây đã đủ cụ thể để owner/team quyết định. Task không phụ thuộc quyết định còn mở có thể tiếp tục khi được giao triển khai. Builder chỉ ghi APPROVED khi có authority thật.

| ID | Quyết định | Đề xuất trong PRD | Phạm vi phụ thuộc |
| --- | --- | --- | --- |
| D-201 | Định nghĩa cash ngày và ownership phí | Theo ngày server khi cash được broker hạch toán. Cộng profit + swap + commission + fee của deal thuộc scope qua position identifier; entry fee vào đúng ngày booking; hỗ trợ OUT_BY; floating chỉ gồm live profit + live swap, không cộng entry cost lần nữa | F04, R-006; test Q15–Q19 |
| D-202 | Mẫu số phần trăm ngày và nạp/rút | Trong bản sửa này giữ định nghĩa mẫu số hiện có, ghi rõ đó là baseline tái dựng theo scope EA; không gọi nó là số dư account chính xác lúc 00:00. Sau D-201, cập nhật cash term nhất quán. Nếu owner muốn account balance thật đầu ngày/điều chỉnh dòng tiền ngoài EA, mở scope riêng | R-007; Q20; không chặn F01–F03/F05 |
| D-203 | Retry/backoff và thời điểm báo reconcile | Đề xuất no-effect reject retry sau 1 s, tăng gấp đôi tới trần 30 s, reset sau progress; 8 reject liên tiếp chuyển sang reconcile có lý do, vẫn giữ close obligation. Không dùng timeout để suy ra no-effect. Đây là giá trị đề xuất, chưa phải mặc định đã duyệt | R-012; Q29–Q30; async terminal result có thể sửa trước khi thay lịch retry |
| D-204 | ADX khi không có dữ liệu | Nếu owner chọn đổi: handle init lỗi → init fail; handle hợp lệ nhưng buffer chưa ready → WAIT cho entry mới, exit vẫn chạy. Nếu chưa duyệt: giữ policy hiện tại, test và ghi rõ fail-open | F07, R-015; Q36–Q37; tùy chọn |
| D-205 | Profit oracle và portability | Bổ sung oracle để kiểm chứng công thức hiện có trước. Chỉ đưa bisection theo tick vào runtime khi symbol/profile chứng minh cần và owner duyệt semantics tương ứng | R-016; Q38–Q40; tùy chọn |
| D-206 | Budget engineering sau baseline | Builder và verifier khóa budget từ B1 trước tối ưu; đề xuất ban đầu nằm ở R-013/R-014 và BENCHMARK_PLAN.json. Đây là mục tiêu kỹ thuật, không phải kết quả đã đo | R-013/R-014; Q33–Q35, Q46–Q47 |

D-201 không cho phép tính mọi khoản balance/commission cấp account cho EA một cách phỏng đoán. Phí không gắn được position phải được báo riêng là chưa phân bổ; muốn phân bổ cần rule đã duyệt. Việc close thủ công position của EA vẫn giữ ownership gốc; `flag_Hand_Ord` tiếp tục quyết định phạm vi position manual được nhận vào, không được dùng magic của close actor thay cho identity gốc.

Mẫu số D-202 đang là một giới hạn sản phẩm kế thừa. Đổi sang “account balance thật đầu ngày” cần đầy đủ account deal history, xử lý deposit/withdrawal/credit và quy tắc khởi động giữa ngày; không gộp âm thầm vào fix entry commission.

## 5. Đặc tả chức năng cho builder

### R-001 — Provenance và authority

Mỗi run ghi repo, branch, HEAD/tree, dirty diff hash nếu có, spec/contract hashes, toolchain, set/data hashes và UTC. Artifact dùng để kết luận candidate phải gắn candidate sạch, không lấy EX5 hoặc log từ build trước. Lệnh chạy, mã trả về, thời gian và artifact path/size/hash nằm trong manifest.

### R-002 — Pre-arm PY–RH không đi xuyên qua WAIT

Đầu vào quyết định phải dùng cùng một snapshot đã xác nhận: Core/PY retained exposure, RH units, reserve và trim dự kiến. Nếu hedge vượt cap và chi phí trim làm funded stop chưa hợp lệ, trả kết quả chờ riêng; không đi tiếp nhánh arm hoặc broker SL.

Tách ý nghĩa kết quả: `NO_ACTION`, `WAIT_PROTECTION`, `MUTATION_STARTED`, `FAULT_RECONCILE`. Tên enum là gợi ý triển khai; invariant và khả năng cho exit khác chạy là bắt buộc. `WAIT_PROTECTION` chưa gửi mutation không được giả làm thành công. Trước send, kiểm lại position ID, live volume, cap, stop/freeze và cash proof.

Sau partial trim, dùng actual filled units/cash và exposure mới; không dùng toàn bộ requested trim như đã fill. Fixture F01 phải đổi từ ARMED/0 trims sang chưa ARMED/không modify; sau funding hợp lệ phải tiến được. Không chữa lỗi bằng tắt protection.

### R-003 — Kết quả async có thể consume chính xác

Operation identity tối thiểu gồm account/symbol scope, owner, actual direction, group serial/campaign, position identifier, operation nonce và broker request ID khi đã có. Retry cùng nghĩa vụ phải có quan hệ với intent gốc; không dùng ticket hoặc timestamp một mình làm khóa idempotency.

| Trạng thái | Bằng chứng vào trạng thái | Hành động hợp lệ |
| --- | --- | --- |
| INTENT_DURABLE | Intent đã persist và kiểm checksum | Gửi một request qua executor |
| SENT_PENDING | Broker/transport đã nhận; chưa biết tác động cuối | Chờ/reconcile, không gửi trùng |
| APPLIED | Live state và/hoặc deal chứng minh tác động đúng ID | Commit hiệu lực, ACK consumer, settle |
| PARTIAL | Có fill thực tế nhỏ hơn nghĩa vụ | Book actual cash/units, giữ phần còn lại |
| REJECTED_NO_EFFECT | Kết quả reject dứt khoát được correlate, không có fill mâu thuẫn | Rollback requested SL về confirmed; giữ close obligation; lập lịch retry |
| UNKNOWN | Timeout, mất callback, kết quả mâu thuẫn hoặc thiếu proof | Reconcile; không coi là no-effect, không tự resubmit |
| SETTLED | Mọi hiệu lực và nghĩa vụ của operation đã được consume bền vững | Compact khi an toàn với replay/dedup |

Không xóa terminal result khỏi executor trước khi PY consume/ACK bền vững. Nếu broker result và live/deal khác nhau, UNKNOWN thắng; chưa được sửa bằng ghi success. Các callback REQUEST/DEAL/POSITION có thể tới khác thứ tự. Ngay iteration đủ bằng chứng terminal no-effect, operation phải rời chờ pending; lần retry tuân theo scheduler, không chặn account emergency.

### R-004 — Replay ledger đúng hướng, chịu late event

Mỗi deal được phân loại ownership/hướng/cohort trước khi lọc hoặc nâng cursor tương ứng. Chọn một trong hai cách và chứng minh: batch riêng đúng hướng, hoặc batch chung từ cursor tối thiểu rồi apply ledger đúng scope. Thứ tự `(time_msc,deal_id)` chỉ là thứ tự xử lý, không phải proof đã thấy toàn bộ deal cũ.

Dùng dedup exact deal ID và bounded overlap cho callback muộn; event cũ nằm ngoài cửa sổ phải kích hoạt reconcile phần ledger ảnh hưởng hoặc rebuild từ checkpoint an toàn. Không bỏ qua chỉ vì timestamp thấp hơn watermark. Với DEAL_UPDATE/DELETE, lưu fingerprint/version và áp dụng delta/rebuild; không được cộng lại toàn phần. Owner hoặc broker correction thiếu dữ liệu phải đánh dấu INVALID, không giữ ledger như đã đúng.

Atomicity: cash apply và marker consumed/cursor phải commit cùng một snapshot, hoặc qua journal có recovery chứng minh tương đương. Crash giữa hai bước không được làm double book hay mất cash. Test fixture lệch cursor phải ghi loss 55, và lặp replay vẫn là 55.

### R-005 — Identity và trạng thái commission

Tra history bằng `POSITION_IDENTIFIER`, giữ `POSITION_TICKET` cho hành động broker ở thời điểm hiện tại. API tính cost trả `{validity,value,source_revision}` hoặc cấu trúc tương đương. HistorySelect thất bại không trả một giá trị 0 có vẻ hợp lệ. Khi `UseCommissionInBE=false`, giữ nhánh không dùng commission; khi ON, tính đúng hoặc chờ proof theo policy đã có, đồng thời giữ emergency exits.

### R-006/R-007 — Cash ngày nhất quán sau D-201/D-202

`DailyCash(scope,day) = Σ booked deal cash thuộc scope/ngày đã duyệt`. Với policy D-201 đề xuất: `deal_cash = profit + swap + commission + fee`. `DayNet = DailyCash + Σ live profit + live swap` cho đúng scope. Chi phí đã ở DailyCash không được đưa vào floating lần nữa. Không dùng BE commission accumulator làm floating cash tổng hợp.

Seed và callback dùng cùng reducer. Test gross 10, entry commission −1, exit commission −1, entry/exit fee −0,2 phải cho 7,6 khi round trip cùng ngày. Test qua ngày phải theo quyết định đã chốt, không mặc định kết quả 7,6 cho mọi ngày. Core và Recovery không được cộng trùng realized; ngày server chuyển đúng một lần; history lỗi làm dayNetValid=false theo policy scope, giữ account emergency. Mẫu số phần trăm phải có test riêng với external cash flows và ghi giới hạn chính xác.

### R-008 — Shared PositionBook với freshness rõ ràng

Một thành phần sở hữu enumeration/aggregation; index theo position ID, role, actual direction và generation. Snapshot immutable đối với consumer trong một lượt quyết định. Chứa revision/topology revision, tick sequence, validity, scope, count, units/lots, weighted numerator và tập ID.

Topology được invalidate bởi deal/position/order event có liên quan, restart, external/manual mutation và reconcile định kỳ có căn cứ. Live P/L, swap, quote và conversion không được cache mù theo topology revision. Có thể refresh bằng danh sách ticket đã biết, nhưng phải kiểm identity/selection failure. Trước mutation luôn đọc lại đúng ticket/ID/volume và broker constraint cần thiết. Nếu stale ở ranh giới này: hủy quyết định cũ, rebuild/re-evaluate; không gửi theo cap cũ.

### R-009 — Incremental history cache

Ledger lịch sử cập nhật bằng sự kiện đã dedup; initial/full history chỉ ở bootstrap, rollover hoặc reconcile có reason code. `PyramidSLMode_=OFF` vẫn được hưởng cache khi CorePyramid hoạt động; không yêu cầu bật tính năng risk để tăng tốc. Không để `TimeCurrent()` sang giây mới tự buộc đọc lại toàn campaign trên quiet path.

Index có thể là sorted array/binary search khi quy mô vừa, hoặc hash table open addressing nếu benchmark chứng minh cần. Phải xử lý collision, capacity, tombstone và rehash có giới hạn. Lựa chọn cấu trúc không được làm mất ordering của các exit hiện có.

### R-010 — Streaming aggregate, đúng thứ tự khi cần

Caller cần count/sum không tạo danh sách rồi sort. Tính units và weighted numerator trong một lượt qua snapshot đúng scope. Caller LIFO/oldest/worst-loss dùng order index với tie-breaker đã chốt; chỉ rebuild khi key thay đổi. Không thay mọi array bằng cây/hash table khi tập position nhỏ và chưa có lợi ích đo được.

### R-011 — Journal bounded, migration và rollback

Xác định lifecycle riêng cho pending intent, terminal result chưa ACK, settled record và tombstone. Không compact ba loại đầu khi chưa chứng minh an toàn. Settled records được compact theo checkpoint/watermark sau khi ledger đã durable. Snapshot có schema version, counts, checksum và source semantics hash.

Writer phải không tạo file vượt giới hạn mà reader của cùng version từ chối. Trước capacity limit, compact an toàn hoặc trả lỗi có trạng thái rõ; không out-of-bounds, không ghi file không thể load. Nghiệm thu các biên 65.535/65.536/65.537 với fixture mô tả chính sách mới. Crash ở write-temp, flush, checksum và atomic replace phải load được bản cũ hoặc mới hoàn chỉnh, không chấp nhận payload nửa chừng.

Nếu đổi schema: cung cấp migration v1→v2, backup và rollback constraints. Khi có open position/pending mutation, không hạ binary về bản không hiểu schema mới. Rollback code chỉ khi state tương thích hoặc đã reconcile/settled theo quy trình; không xóa file state để ép chạy.

### R-012 — Retry scheduler

Thực hiện sau D-203 hoặc giữ nguyên lịch đã được duyệt nếu có. Key theo obligation + reject reason; dùng deadline có quy tắc restart, không ngủ chặn event thread. Không send trước nextEligibleTime. Progress thực sự mới reset backoff; spam callback không được reset. Cạn retry budget chuyển reconcile có observable reason và giữ nghĩa vụ, không đánh dấu done. Timer deadline không là bằng chứng request trước đã không fill.

### R-013/R-014 — Instrumentation và benchmark bảo toàn hành vi

Counter tách toàn EA với adapter PY; tách PositionsTotal enumeration, selected-position refresh, history selections, sort/alloc, bytes persisted, send/reject/reconcile. Timing riêng OnTick/OnTradeTransaction/OnTimer và từng subsystem; đo bằng clock độ phân giải phù hợp, tránh log mỗi tick. Local diagnostic default OFF; không network telemetry.

Benchmark cùng máy/build/broker profile/set/dataset/model, ghi warmup/cache state, hoàn tất end date. Lặp tối thiểu 5 paired runs nếu workload tái lập được; báo median và spread giữa runs cùng p50/p95/p99/max handler, memory peak và wall time. Không gộp compile time vào latency EA. Với noisy remote environment, ghi INCONCLUSIVE và chạy lại trên môi trường kiểm soát được thay vì tự cho PASS.

Tiêu chuẩn cấu trúc bắt buộc sau tối ưu: quiet tick không thêm protection-only whole-account enumeration hoặc full campaign history read; aggregate helper sum không sort; diagnostic saturation không tự xây lại Core book; mutation vẫn có final live validation. Chỉ tiêu thời gian được khóa trong `BENCHMARK_PLAN.json` ở B1 trước khi code tối ưu. Đề xuất để team chốt: giảm ít nhất 50% duplicate whole-account enumerations ở fixture đã xác định và không tăng p95/p99 handler quá 5% ngoài nhiễu đo. Đây là mục tiêu kế hoạch, chưa phải kết quả hay ngưỡng owner đã duyệt; emergency latency tuyệt đối không được đánh đổi để đạt trung bình đẹp.

### R-015/R-016/R-017 — Hạng mục mở rộng có điều kiện

ADX phải theo D-204, kèm init/buffer failure và exit-liveness test. Profit oracle theo D-205: kiểm `OrderCalcProfit` BUY/SELL theo account currency; tách fee/reserve; bracket hợp lệ và monotonicity trước bisection trên integer tick; failure không trả zero. Không đổi lot/SL rounding hoặc ngưỡng tiền ngoài scope.

Refactor kiến trúc ưu tiên composition: PositionBook, CashLedger, RecoveryState, ExecutionCoordinator và policy pure. Giữ wrapper tương thích tạm thời; chuyển từng caller, cùng behavior trace, rồi mới xóa layer thừa. Không gộp sửa correctness và tháo toàn bộ inheritance vào một diff khó audit.

### R-018 — Delivery và audit lại

Verifier phải đọc source diff thực tế, chạy lại critical tests, kiểm authority/hash, kiểm counterexample baseline bị giết và xác nhận case mới có thể đạt trong integration. Không tự kết luận từ chữ ALL GREEN hay từ báo cáo builder. Mỗi finding đóng bằng source + intended-result test + evidence đúng HEAD; unresolved finding giữ OPEN/BLOCKED/UNTESTABLE cùng điều kiện ảnh hưởng.

## 6. Blueprint và đường xử lý mong muốn

| Thành phần | Sở hữu | Không được làm |
| --- | --- | --- |
| PositionBook | Live identity/topology, scope aggregates và freshness | Tự gửi lệnh hoặc coi invalid là zero |
| CashLedger | Deal identity, attribution, dedup/correction/replay | Dùng close actor magic thay ownership gốc; double-book |
| Protection/Recovery policy | Candidate, cap, obligation và state transition | Bỏ qua proof để arm; tự xác nhận broker outcome |
| ExecutionCoordinator | Durable intent, send, callback result, ACK/reconcile | Xóa result trước consumer; retry UNKNOWN |
| Persistence | Atomic snapshot, migration, bounded retention | Ghi version/count không đọc lại được |
| Diagnostics | Counters và sampled timing riêng từng scope | Network telemetry mặc định; log/sort/scan nặng mỗi tick |

Thứ tự ưu tiên giữ theo code/spec đã duyệt: cập nhật dữ liệu cần thiết → account emergency → settle/reconcile nghĩa vụ → policy/guard/exit được phép → admission cho rủi ro mới. Builder phải lập event-order table từ candidate vì đây là quan hệ ưu tiên, không phải chỉ dẫn tự thay toàn bộ OnTick bằng một pipeline mới. OnTimer của EA dùng cùng hàng đợi sự kiện, không phải thread nền miễn phí.

MetaQuotes không bảo đảm thứ tự đến của trade transactions; queue có giới hạn 1.024 phần tử. [OnTradeTransaction](https://www.mql5.com/en/docs/event_handlers/ontradetransaction) Ticket có thể thay đổi qua server operation trong khi identifier ổn định. [Position properties](https://www.mql5.com/en/docs/constants/tradingconstants/positionproperties) `HistorySelectByPosition` nhận identifier. [HistorySelectByPosition](https://www.mql5.com/en/docs/trading/historyselectbyposition) Profit oracle phải kiểm return status và điều kiện account currency. [OrderCalcProfit](https://www.mql5.com/en/docs/trading/ordercalcprofit)

## 7. Task graph và nhịp bàn giao

Danh mục đầy đủ nằm trong `TASK_GRAPH.json` và `TASK_GRAPH.md`. Đây là dependency công việc cho team; không tự cấp quyền sửa cùng file đồng thời hoặc tự đăng nội dung lên GitHub.

| Wave | Công việc | Exit |
| --- | --- | --- |
| W0 | T00 chốt source/authority; T01 dựng regression baseline và oracle | Baseline report + approved scope mapping; critical tests thể hiện bug trên B0 |
| W1 | T02 pre-arm; T03 async; T04 replay; T05 identity; T06 cash theo D-201/D-202 | B1 correctness candidate; native/negative/restart evidence |
| W2 | T07 đo B1; T08 journal; T09 snapshot/aggregate; T10 incremental history/retry | Mỗi patch có differential trace và measured counters |
| W3 | T11 optional policy/portability; T12 integration, stress và benchmark | Candidate C có matrix đúng trạng thái và manifest |
| W4 | T13 verifier độc lập + handover | Finding disposition, completion, missing evidence và eligibility rõ |

Ước lượng lập kế hoạch: W0 khoảng 2 engineer-days; W1 6,5–11; W2 5–10; W3/W4 3–6, cộng thời gian chạy native/soak và chờ quyết định/dữ liệu. Tổng làm tròn khoảng 17–29 engineer-days, chưa tính các phần tùy chọn T11. Đây là ước lượng ban đầu, không phải cam kết lịch; team re-estimate sau W0, nhất là replay correction và migration. Các patch T02/T03/T08 cùng chạm PyramidProtection phải tích hợp theo thứ tự có người sở hữu; không cherry-pick mù các patch overlap.

Mỗi task hoàn thành một TIP nhỏ trước khi tích hợp: input HEAD, scope, decisions, allowed paths, change summary, tests/commands, artifact hashes, remaining risks. Nếu tạo PR, chỉ draft theo quyền owner/team đã có; mô tả “vấn đề → thay đổi → hành vi → bằng chứng”. Không merge hoặc mở forward/live từ PRD này.

## 8. Test matrix và cách chứng minh

`TEST_MATRIX.csv/json` chứa từng case với Given/When/Then, oracle, tier và evidence. Các case là kế hoạch, trạng thái ban đầu **NOT_RUN**. Số lượng case không thay assertion count; không lấy 54 nhóm baseline thay cho coverage mới.

Ba tầng xác minh:

1. **Model/host:** property và số học có seed, independent oracle; dùng để tìm phản ví dụ nhanh.
2. **Production integration native:** compile/call code thật qua seam mỏng, callback/persistence/failure injection kiểm được; không viết lại toàn thuật toán vào toy model rồi chỉ test toy model.
3. **MT5 scenario:** tester đúng data/model cùng forced coexistence/RH trim/restart. Tester ép sync nên async reject phải có native callback injection và, trước forward eligibility, bằng chứng async demo phù hợp phạm vi đã được cho phép.

Các script audit cũ exit 0 khi tái hiện **bug**. Builder phải chuyển chúng thành test kỳ vọng đúng; tiêu chí là bug hiện trên B0 và không còn trên candidate, không phải “script vẫn exit 0”. Mutation test đổi lại WAIT→NEXT, bỏ reject consume hoặc bỏ direction filter phải làm critical test thất bại.

Oracle số học dùng epsilon khai báo cố định, ví dụ 1e-8 trong fixture double. Native money tolerance gắn account currency precision và report precision; price theo integer tick, volume theo integer step. Không nới tolerance sau khi thấy regression để làm xanh. Seeds, generated input và shrink counterexample được lưu để chạy lại.

## 9. Verification gates

| Gate | Điều kiện PASS | Khi thiếu proof |
| --- | --- | --- |
| G0 Authority | Candidate/base/spec/decisions/allowed paths đối chiếu; approval không bị tự tạo | BLOCKED_SCOPE cho phần liên quan |
| G1 Regression | Bộ gốc + intended-result critical tests PASS; test bắt được mutation/baseline bug | FAIL hoặc UNTESTABLE |
| G2 Native compile | Windows MetaEditor đúng source; probe; Result 0 errors/0 warnings; EX5 mới tồn tại, hash/size | UNTESTABLE nếu không có backend; FAIL nếu source lỗi |
| G3 Integration | Native async, partial, late/duplicate, ownership, persistence và correction tests PASS | Không suy từ C++ thành PASS |
| G4 Scenario | OFF/VIRTUAL/BROKER, BUY/SELL, RH trim thực sự kích hoạt, real-tick case hoàn tất | Không có natural RH trim → forced deterministic scenario; vẫn thiếu thì UNTESTABLE |
| G5 Performance | Baseline B1 và candidate C tương đương trace, counters đạt budget đã chốt, timing có môi trường đủ tin cậy | INCONCLUSIVE/UNTESTABLE; không claim speedup |
| G6 Independent audit | F01–F06 disposition có source/test/evidence; F07 policy rõ; manifest/hash chain xác minh | Giữ finding mở |
| G7 Release decision | Áp dụng gates và owner authority riêng cho từng mức | Merge/forward/live vẫn false nếu chưa có quyết định riêng |

CI GitHub Windows được chấp nhận khi correlate repo/HEAD/tree/run ID/numeric job ID/runner và artifact hash, có toolchain probe, EX5 và compile summary đúng run. Nhãn `github_actions_metaeditor` hoặc workflow màu xanh không đủ. Không commit log/EX5 trở lại source chỉ để thay trạng thái CI.

Dùng runtime canonical sẵn có; chạy `vkmql-check --help`, `vkmql-check compile --help`, `mql5-compile --help` để chốt cú pháp đang cài trước khi ghi command thật. `mql5-retro-init` và `vkmql-check retro` theo skill/runtime được xác minh; không bịa CLI flag, không cài Wine/MT5/service mới khi chưa có yêu cầu. Lưu command thực thi và output, không đánh dấu template command là đã chạy.

## 10. Evidence contract và quy tắc trạng thái

Mỗi result gồm case/gate ID, status, reason, command, exit code, environment ID, recorded_at_utc, source HEAD/tree, input hashes và artifact records `{path,size,sha256}`. Test status cho phép PASS/FAIL/UNTESTABLE/SKIPPED/NOT_RUN; benchmark có thêm INCONCLUSIVE; approval là trường riêng.

`EVIDENCE_MANIFEST.template.json` trong gói là template của PRD, không phải canonical runtime release manifest. Builder phải xuất `evidence/manifest.json` schema 2.0 hoặc schema runtime đã hỗ trợ, rồi giữ liên kết từ template này. Không đặt `release_eligible=true` để vượt missing artifacts. Backtest report phải không rỗng và có metrics; EX5 không thể thay bằng file stub.

Bằng chứng bắt buộc: source identity; spec/contract hashes; native probe+compile log+EX5; baseline/candidate test logs; .set hash; dataset/tester configuration; report XML/HTML; broker capability profile; deal/intent/replay traces; crash/restart checkpoints; counter/latency samples; final audit disposition. Chỉ đưa dữ liệu đã được phép chia sẻ vào gói team; không kèm token/password hoặc tự truyền telemetry.

## 11. Definition of Done và audit độc lập

Một **correctness candidate B1** hoàn tất khi F01/F02/F03/F05 có intended-result + native integration proof; F04 được fix theo quyết định hoặc ghi rõ BLOCKED_POLICY và không được gọi là “đã khép toàn bộ”. Một **optimized candidate C** hoàn tất khi B1 gates còn PASS, F06 bounded/migration proof đạt, các tối ưu có counters/timing và differential trace. F07/portability chỉ được ghi implemented khi đúng quyết định tùy chọn.

Verifier chọn lại case từ input, không nhận expected values sinh từ output builder. Kiểm các interleaving chéo BUY/SELL/Core/PY/RH, callback trước/sau persistence, replay correction và lỗi history. Đối chiếu mọi bản sửa với approved semantics và phát hiện regression ở các module kế thừa. Recheck remote PR HEAD lần cuối để không audit nhầm commit.

Completion Report phải trả lời: đã đổi gì; finding nào đóng/mở; test nào chạy ở đâu; số liệu performance trước/sau và nhiễu; source/build/evidence hashes; decision còn thiếu; rollback state compatibility; eligibility từng mức. Local test xanh không được thay cho native, forward hoặc live.

## 12. Danh sách tài liệu và cách bàn giao

`START_HERE.md` là hướng dẫn nhận việc. `BUILDER_KICKOFF.md` là prompt bàn giao sẵn. `EA-SPEC.yaml`, `DECISIONS.yaml`, `AI-BUILD-CONTRACT.json`, `TASK_GRAPH.json`, `TEST_MATRIX.json/csv` là dữ liệu có ID để team theo dõi. `RRI.md`, `BLUEPRINT.md`, `BENCHMARK_PLAN.json`, `RETRO_GUARDS.yaml` và các template TIP/Completion/Approval/Evidence hoàn chỉnh phần quy trình.

Đây là package bàn giao độc lập. Khi tích hợp vào repo, giữ một active `BlackDragon_v14/docs/vibecode/PROJECT_STATE.yaml` trỏ đến các artifact đang dùng; đọc và cập nhật manifest hiện có, không tạo hai authority cạnh tranh. Trạng thái builder chưa chạy vẫn NOT_RUN. Trước khi chạy lại các script audit, kiểm package manifest; rerun sẽ đổi file generated nên không dùng hash trước rerun như thể đó là output mới.
