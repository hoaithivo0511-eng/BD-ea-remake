# BlackDragon v15.00 / T17.18 — handoff hiện hành

## Trạng thái khóa

| Trường | Giá trị |
|---|---|
| Repo | `hoaithivo0511-eng/BD-ea-remake` |
| Branch | `feat/t17-full-pyramid` |
| PR | `#28`, Draft, open, not merged |
| Runtime | `BlackDragon.mq5` v15.00, lineage T17.18 |
| T17.18 baseline | HEAD `525f2f8b1e084c03aa655d17c83e65428a59503d`, TREE `af95472247ae1d007429ada4411db29ed02fdfc4` |
| Strategy Tester | `PENDING_OWNER` |
| Release / forward / live | `false / false / false` |

Local ancestry từng lệch remote do GitHub connector tạo commit SHA khác trên
cùng tree. Vì vậy mọi cập nhật remote phải tạo Git tree/commit trên **exact
remote parent hiện tại** rồi update ref với `force=false`; không force-push
local ancestry.

## Runtime mới nhất

T17.18 xóa toàn bộ dashboard, P/L/level/halt labels, edit lot và chart
buttons. `Panel.mqh`, `CPanel` và `OnChartEvent` không còn trong composition;
Strategy cũng không còn đọc manual chart request trên mỗi tick. Mười một input
layout/font/color của dashboard đã bị loại khỏi optimizer. Theo xác nhận của
owner, `ShowWmfSignals` và mũi tên WMF vẫn được giữ trong module overlay riêng.

Timer 500 ms tiếp tục chạy News, execution watchdog, Recovery persistence,
exit coordination, Mobile Control, day rollover và halt persistence. Không có
entry/exit/lot/DCA/Pyramid/Recovery/Overlap/risk semantic nào được đổi.

T17.17 giữ quyền sở hữu exact broker protective-SL của ARCS trong side-cycle,
không biến nó thành external close chỉ vì Overlap đang hoạt động. Sau account
MoneyGuard đóng phẳng đã được xác minh, Recovery/Overlap lifecycle được reset
atomically; failure tiếp tục fail-closed. T17.16 phía dưới giữ stage-admission
replay sau Hedge rebase và embargo `NO_MONEY` dùng chung, bền qua restart.

T17.18 chỉ thay đổi public input surface bằng việc xóa 11 input dashboard đã
được owner phê duyệt. Các input/default giao dịch, công thức lot, khoảng cách,
target, hard cap, MoneyGuard và live-trading semantic giữ nguyên.

## Evidence baseline trước T17.18

- Workflow: `Verify T17.17 Broker SL Flat Liveness Final`
- Run: `33270273234`
- Model/source job: `99147403114`, PASS
- Native job: `99147403240`, PASS
- Artifact: `blackdragon-t1717-final-owner-qa`, ID `9719955627`
- Artifact ZIP SHA256: `25cfa95cdfe2891b613fccc7d0d76baef70002935724887599ac0196522a8fed`
- EX5: 668824 bytes, SHA256 `85db97f43450129f30a5247b78c88a625e11e0fe9f3b6933d1db411428746d55`

Repository-cleanup exact-head run `33657941993` đã PASS 37/37 models,
repository contract 9/9, MetaEditor 0/0 và native 27/27 = 915/0. T17.18 phải
chạy lại exact-head CI và tạo artifact mới vì source/EX5 đã thay đổi.

## Thứ tự đọc

1. `docs/vibecode/CURRENT_VERSION.md`
2. `docs/vibecode/REPOSITORY_CLEANUP_AUDIT.md`
3. `Include/BlackDragon/ARCHITECTURE.md`
4. `docs/vibecode/T17_18_EA-SPEC.yaml`
5. `docs/vibecode/T17_18_DECISIONS.yaml`
6. `docs/vibecode/T17_18_VERIFY_REPORT.md`
7. `docs/vibecode/T17_18_OWNER_QA_CHECKLIST.md`

Tài liệu trước T17.18 nằm trong `docs/vibecode/archive/`. Chỉ dùng
để truy nguyên quyết định; không lấy version/status/test claim trong đó làm
trạng thái hiện hành.
