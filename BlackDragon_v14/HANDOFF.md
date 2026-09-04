# BlackDragon v15.00 / T17.19 — handoff hiện hành

## Trạng thái khóa

| Trường | Giá trị |
|---|---|
| Repo | `hoaithivo0511-eng/BD-ea-remake` |
| Branch | `feat/t17-full-pyramid` |
| PR | `#28`, Draft, open, not merged |
| Runtime | `BlackDragon.mq5` v15.00, lineage T17.19 |
| T17.19 baseline | HEAD `b971f41fc92ac8b084ccfa6748a59ae166d5f939`, TREE `6da21b0dbaeda85ce66f12825064521be40e75c5` |
| Strategy Tester | `PENDING_OWNER` |
| TunnelVibemq5 | Workspace `BD`: compile/smoke/default validation PASS; BUY/SELL re-entry paths PASS |
| Release / forward / live / merge | `false / false / false / false` |

Local ancestry khác remote vì T17.18 đã được tạo bằng GitHub Git-data. Mọi cập
nhật tiếp theo phải tạo tree/commit trên exact remote parent rồi update ref với
`force=false`; không push local ancestry và không merge PR.

## Runtime mới nhất

T17.19 xử lý khoảng trống `MAXED_NO_HEDGE` thấy trong log owner. Khi terminal
RH đóng bằng exact protective BE/SL do Recovery sở hữu, engine tính net cash
toàn chuỗi. Nếu không âm, nó persist `WAIT_RESET`; sau khi giá pullback thuận
Core đủ `RecoveryReentryBufferPips_`, trạng thái thành `ARMED`. Chỉ khi giá quay
lại exact anchor theo chiều bất lợi Core, engine persist `TRIGGER_PENDING`,
reset ARCS book và bắt đầu G1 mới bằng fresh Core volume.

G1 và các bậc sau dùng nguyên Hedge Pyramid scheduler, coverage/gap/hard-cap,
timing, margin và execution gates hiện hữu. `MaxRecoveryReentryCycles_` mặc
định 2; zero tắt. Persistence re-entry là file v1 riêng nên payload ARCS v4
không đổi.

Owner đã khóa admission: trong `WAIT_RESET/ARMED`, chỉ Core DCA bị chặn. Core
Pyramid ADD vẫn được xét theo settings hiện tại. Khi outer cap `EXHAUSTED`, DCA
và Pyramid ADD bị chặn nhưng risk-reducing Peel/close vẫn chạy.

T17.18 dashboard-free và `ShowWmfSignals` arrows được bảo toàn.

## Evidence hiện hành

- Input log `20260904.log` SHA-256 `85af0f469ccde3be1dfe0681bf18277e9e2e78c1013e60e546966bf7e55e31ea`.
- Independent T17.19 C++ oracle: 33/33 PASS.
- T17.19 source contract: 17/17 PASS.
- Established + new C++ models: 38/38 PASS; source T17.11–T17.19 and repository contract PASS locally.
- Deep review v2: 111 files / 1,206 packets; critical=4, error=55 (không tăng so với T17.18), warn=353, info=29.
- Workspace VPS `BD`, MT5-2 build 6140: 83/83 file bytes đã đối chiếu; staged dependency closure compile 0 errors/0 warnings.
- Smoke job `BT-20260904-020421-32DA64`: PASS, không fatal/anomaly.
- Default validation job `BT-20260904-070949-5942DB`: hoàn tất nhưng Recovery mặc định OFF nên không cover T17.19; log cho thấy margin exhaustion/forced liquidation cùng retry `Market closed` và `NO_MONEY` heartbeat lặp lại — đây là risk/config và log-noise debt, không phải bằng chứng feature PASS. Số liệu account/trade chi tiết chỉ giữ trong evidence cục bộ.
- Targeted Core-Pyramid-ON job `BT-20260904-073840-4BA481`: PASS 0/0, không fatal/anomaly; active Recovery + Pyramid chạy cùng nhau nhưng chưa chạm terminal-positive.
- Focused trigger job `BT-20260904-075004-E4F818`: PASS 0/0 và journal chứng minh BUY `WAIT_RESET → ARMED → G1 durable cycle=1/1 → EXHAUSTED`, exact close, net dương, DCA bị khóa. SELL/restart/broker portability vẫn thuộc owner checklist.
- Core-Pyramid-ON trigger job `BT-20260904-075232-27C4F5`: PASS 0/0; BUY và SELL đều đi `WAIT_RESET → ARMED → G1 durable → EXHAUSTED`, exact net dương, không error/fatal/reconcile. Hai cửa sổ wait không phát sinh trigger ADD, nên case favorable-ADD vẫn để owner xác nhận; model/native contract khóa admission rule.
- Exact-head CI, native 28-suite matrix, artifact và owner acceptance vẫn pending.

Compile/native tests không được gọi là Strategy Tester PASS. Cơ chế mới giảm
uncovered terminal window nhưng không bảo đảm chống forced liquidation nếu lot/order/risk
caps và account loss stops bị tắt.

## Thứ tự đọc

1. `docs/vibecode/CURRENT_VERSION.md`
2. `docs/vibecode/T17_19_EA-SPEC.yaml`
3. `docs/vibecode/T17_19_DECISIONS.yaml`
4. `docs/vibecode/T17_19_VERIFY_REPORT.md`
5. `docs/vibecode/T17_19_OWNER_QA_CHECKLIST.md`
6. `Include/BlackDragon/ARCHITECTURE.md`

Tài liệu trước T17.19 nằm trong `docs/vibecode/archive/` và chỉ dùng để truy
nguyên; không dùng claim/version/status trong archive làm trạng thái hiện hành.
