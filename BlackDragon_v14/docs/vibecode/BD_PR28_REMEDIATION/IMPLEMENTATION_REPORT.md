# BlackDragon v15.01 — T17.24 build checkpoint

**Trạng thái: source candidate đã cập nhật, Full plan chưa hoàn tất. Chưa có EX5 mới.**

Bản này tiếp tục PRD `BD-PR28-REMEDIATION-001` theo yêu cầu triển khai của owner, trên PR #28 mới nhất được clone tại HEAD `40c424cfa71b6742414b012e9d67d3294003f38e`. Nhánh local: `codex/pr28-full-update`. PR gốc chưa được merge; checkpoint này chưa push lên GitHub.

## Kết quả có bằng chứng

| Lớp kiểm tra | Kết quả | Giới hạn |
| --- | --- | --- |
| Model C++ hiện có | 42/42 nhóm PASS | Không phải terminal MT5 |
| Source/repository contracts | 15/15 nhóm PASS | Kiểm wiring, scope, inputs; không thay thế runtime |
| Cash ledger production fixture | 30 assertion PASS | API history được mô phỏng; class production thật |
| Replay production fixture | 2 assertion PASS | Phần Core loss ledger; không bao trùm mọi Recovery generation |
| Protection production fixture | 15 assertion PASS | Thân hàm production thật; executor/Save/platform seam dùng fixture |
| Observation production fixture | 13 assertion PASS | Aggregate class thật; broker position và comment role dùng fixture |
| Input declarations | 150 giữ nguyên | Tên/type/thứ tự/default trong 89 file runtime baseline |
| Native MetaEditor / EX5 | UNTESTABLE | Phiên này không có compiler/backend được cấu hình |
| 33 native suites đã đưa vào CI | NOT_RUN | Enrolled không có nghĩa đã chạy |
| Strategy Tester / restart / benchmark | UNTESTABLE | Không có MT5, broker profile, dataset và runtime connection |

Hai lớp kiểm tra có đơn vị khác nhau: **57 nhóm hồi quy** = 42 models + 15 source contracts; **60 assertion fixture** = 30 cash + 2 replay + 15 protection + 13 observation. Không được diễn giải thành 56 case PRD đều PASS. `TEST_EXECUTION.json` giữ trạng thái riêng từng case kế hoạch.

## Thay đổi chính

### Cash ngày và commission

`CashLedger.mqh` là reducer chung cho Core và Recovery. Mỗi trade deal đóng góp `profit + swap + commission + fee` theo ngày booking của server. Ownership được truy bằng immutable position identifier và opening deal; magic của người thực hiện close không tự thay chủ sở hữu ban đầu. Manual position chỉ được đưa vào Core khi input hiện có cho phép; account-level fee không đủ attribution không được đoán.

Seed chụp toàn bộ deal ID trước khi đọc history theo position. Dedup dùng ID chính xác; deal cash thay đổi được cập nhật bằng delta. Khi history thiếu, ledger INVALID và thử lại theo deadline; không biến thiếu dữ liệu thành số 0 hợp lệ. Đã sửa thêm trường hợp seed đầu ngày thất bại làm reset deadline trên từng tick.

Core và Recovery dùng cùng reducer; correction event invalidate cả hai. Khi exit coordinator suppress strategy replay, Recovery cash vẫn được observe riêng. Core BE commission giữ lookup bằng POSITION_IDENTIFIER của upstream, bổ sung retry khi history phục hồi mà chưa có topology event. Refresh basket cập nhật volume/ID/giá/SL/TP cả khi Pyramid protection OFF; thay đổi volume/ID kích hoạt lượt rebuild thứ hai có giới hạn ngay trong tick, để commission/levels không chờ tick sau.

Mẫu số daily percent giữ cách tái dựng theo scope đã chọn trong D-202. Đây **không phải** cam kết số dư tài khoản chính xác lúc nửa đêm nếu có dòng tiền hay giao dịch ngoài scope. Q20 về external flows và tương tác Recovery còn phải chạy.

### Replay và giới hạn callback muộn

Upstream T17.23 đã lọc direction nhưng còn gọi hàm thay đổi selected history ngay khi đang duyệt danh sách đó. Fixture dùng đúng thân hàm upstream ghi nhận **50 thay vì 55** ở lượt replay đầu. Candidate chụp ID trước, lọc đúng direction, lưu timestamp để sort và ghi đủ **55** ngay lượt đầu; replay lại giữ 55.

DEAL_UPDATE/DELETE hiện đưa ARCS funding vào reconciliation để không tiếp tục dùng ledger có thể sai. Đây là biện pháp giữ chặn, **chưa phải** automatic rebuild. Exact receipt dedup và overlap cho DEAL_ADD có timestamp thấp hơn cursor chưa hoàn tất; R-004 vẫn PARTIAL.

Theo tài liệu chính thức, HistoryDealSelect thay danh sách deal được chọn bằng một deal; việc snapshot trước nested lookup xử lý đúng đặc tính này. Thứ tự nhận trade transaction cũng không bảo đảm tương ứng thứ tự nghiệp vụ. Nguồn: [HistoryDealSelect](https://www.mql5.com/en/docs/trading/historydealselect), [OnTradeTransaction](https://www.mql5.com/en/docs/event_handlers/ontradetransaction).

### Async reject, nghĩa vụ và retry

Execution journal lấy ID/nonce của intent đã persist. Consumer chỉ chấp nhận reject đúng cycle, command, ticket, position ID và nonce. Timeout/connection/retcode 0 giữ trạng thái cần đối soát. Nếu đã có volume/deal effect, hoặc live SL đã ở target mới, reject không được coi là no-effect.

No-effect đúng identity rollback requested SL về confirmed SL, giữ group obligation, ghi retry outcome rồi Save trước khi ACK cho executor. Save thất bại giữ fault và không ACK. Backoff theo D-203: 1, 2, 4, 8, 16, 30 giây; tối đa 8 reject liên tiếp rồi reconcile. Không sleep trong event thread.

Retry payload được thêm vào disk version 2; reader chấp nhận v1 và khởi tạo retry trống. Native file round-trip, crash giữa Save/ACK và restart có pending operation vẫn chưa có bằng chứng. Không hạ binary v2 về bản chỉ đọc v1 khi state đang hoạt động.

### Tối ưu đã viết và giới hạn

Recovery OnTick có một lượt tổng hợp Core/hedge units và trigger count, không cấp phát danh sách position không dùng. Snapshot chỉ tồn tại trong lượt quan sát; tắt trước Strategy/executor. Sum-only layer query không tạo array rồi sort; saturation log dùng count trực tiếp. Các caller cần ordering tiếp tục dùng ordering hiện có.

Campaign statistics ở OFF và ON dùng deal revision thay vì giây đồng hồ để quyết định freshness. Quiet path không tự đọc lại history vì sang giây mới. Tuy vậy, khi revision thay đổi vẫn rebuild campaign; chưa phải incremental cache đầy đủ của R-009.

Có local observation counters scans/visits/hits, không network telemetry. Chưa có histogram latency toàn EA hoặc benchmark B1 → candidate. **Không có kết luận nhanh hơn bao nhiêu phần trăm**, và chưa áp dụng mục tiêu 50% / 5% thành kết quả đạt.

## Sửa đổi kiểm thử

Các fingerprint lịch sử T17.20/T17.21 được supersede chỉ ở những file đã được scope mới cho phép; các gate one-bar và comment semantics vẫn được giữ. T17.23 cash contract trỏ sang reducer chung; replay contract trỏ sang comparator dùng metadata đã chụp. T17.24 thêm baseline source/input manifest và fixture thực thi thân hàm production để kiểm tra hành vi đã chuyển.

Một lỗi phân loại ở runner tổng hợp đã được sửa: script T17.12 in `SOURCE CONTRACT GREEN` thay vì `ALL GREEN`. Script gốc trả exit 0 ở cả hai lượt; không sửa assertion hay expected value của script đó. Log lần phân loại đầu vẫn được giữ trong evidence.

## Phạm vi chưa đóng

1. R-003/R-011: hoàn thiện và kiểm chứng durable outcome, Save/ACK crash, v1/v2 round-trip, corrupt/truncated file, restart và retention của RH records.
2. R-004: exact dedup receipt, bounded overlap và reconciliation/rebuild an toàn cho deal cũ hoặc correction; không chỉ dựa vào cursor.
3. R-008/R-009: full indexed PositionBook và incremental campaign ledger; candidate hiện mới có aggregate observation và event invalidation.
4. R-013/R-014: instrumentation toàn EA, B1 baseline và 5 paired native runs; kiểm p95/p99, memory và trade trace parity.
5. R-016: OrderCalcProfit oracle trên broker profile thật; chưa thay thuật toán giá/lot bằng bisection.
6. Native compile 0/0, 33 native suites, Strategy Tester đủ end date và independent review trước EX5 release.

Không waive các gate này. `release_eligible=false`, `forward_eligible=false`, `live_eligible=false`.

## Tiếp tục từ checkpoint

Đọc `REMAINING_WORK.md`, `REQUIREMENT_STATUS.json` và `TEST_EXECUTION.json` trước khi nhận task. `NATIVE_BUILD_RUNBOOK.md` chỉ ra lệnh compile với MetaEditor đã có. Mọi bằng chứng mới phải gắn source manifest và artifact SHA256; EX5 từ HEAD cũ không phải sản phẩm của candidate này.
