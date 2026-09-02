# BlackDragon v15.00 / T17.17 — handoff hiện hành

## Trạng thái khóa

| Trường | Giá trị |
|---|---|
| Repo | `hoaithivo0511-eng/BD-ea-remake` |
| Branch | `feat/t17-full-pyramid` |
| PR | `#28`, Draft, open, not merged |
| Runtime | `BlackDragon.mq5` v15.00, lineage T17.17 |
| Baseline trước cleanup | HEAD `b87bd3cf3d3a1c23d748ed0b4addb95a8ea376b4`, TREE `2c1940de27fd6547eee17eb6c34683292c0d189e` |
| Strategy Tester | `PENDING_OWNER` |
| Release / forward / live | `false / false / false` |

Local ancestry từng lệch remote do GitHub connector tạo commit SHA khác trên
cùng tree. Vì vậy mọi cập nhật remote phải tạo Git tree/commit trên **exact
remote parent hiện tại** rồi update ref với `force=false`; không force-push
local ancestry.

## Runtime mới nhất

T17.17 giữ quyền sở hữu exact broker protective-SL của ARCS trong side-cycle,
không biến nó thành external close chỉ vì Overlap đang hoạt động. Sau account
MoneyGuard đóng phẳng đã được xác minh, Recovery/Overlap lifecycle được reset
atomically; failure tiếp tục fail-closed. T17.16 phía dưới giữ stage-admission
replay sau Hedge rebase và embargo `NO_MONEY` dùng chung, bền qua restart.

Không có input/default, công thức lot, khoảng cách, target, hard cap,
MoneyGuard threshold hoặc live-trading semantic nào được thay đổi bởi cleanup
repo. `BD_VERSION` được đồng bộ từ 14.9.0 thành 15.00 chỉ để Panel khớp
`#property version "15.00"`; nó không được dùng trong persistence hay logic
giao dịch.

## Evidence T17.17 trước cleanup

- Workflow: `Verify T17.17 Broker SL Flat Liveness Final`
- Run: `33270273234`
- Model/source job: `99147403114`, PASS
- Native job: `99147403240`, PASS
- Artifact: `blackdragon-t1717-final-owner-qa`, ID `9719955627`
- Artifact ZIP SHA256: `25cfa95cdfe2891b613fccc7d0d76baef70002935724887599ac0196522a8fed`
- EX5: 668824 bytes, SHA256 `85db97f43450129f30a5247b78c88a625e11e0fe9f3b6933d1db411428746d55`

Đây là evidence cho exact baseline trước cleanup. Exact-head cleanup CI và
artifact mới phải được ghi vào verify report trước khi handoff owner.

## Thứ tự đọc

1. `docs/vibecode/CURRENT_VERSION.md`
2. `docs/vibecode/REPOSITORY_CLEANUP_AUDIT.md`
3. `Include/BlackDragon/ARCHITECTURE.md`
4. `docs/vibecode/T17_17_EA-SPEC.yaml`
5. `docs/vibecode/T17_17_DECISIONS.yaml`
6. `docs/vibecode/T17_17_VERIFY_REPORT.md`
7. `docs/vibecode/T17_17_OWNER_QA_CHECKLIST.md`

Tài liệu trước T17.17 nằm trong `docs/vibecode/archive/pre-t1717/`. Chỉ dùng
để truy nguyên quyết định; không lấy version/status/test claim trong đó làm
trạng thái hiện hành.
