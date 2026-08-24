# T17.7 — Owner Strategy Tester QA Checklist

## Binary contract
- Chỉ test `BlackDragon.ex5` lấy từ artifact `blackdragon-t177-final-owner-qa` của exact PR HEAD.
- Ghi lại HEAD, TREE và `BLACKDRAGON_EX5_SHA256` trong `PROVENANCE.txt` trước khi chạy.
- Không dùng EX5 từ run/commit cũ.

## Baseline tester
- MT5 Strategy Tester, tài khoản hedging.
- XAUUSD/XAUUSDm M1 theo broker đang dùng.
- Model: Every tick based on real ticks khi có dữ liệu.
- Execution delay stress: 150 ms cho các case async/Overlap.
- Chạy tới đúng ngày kết thúc yêu cầu; terminal không được tự shutdown/TesterStop vì invariant lỗi.
- Lưu `.set`, tester log, report và EX5 hash cho từng case fail.

## Matrix bắt buộc
1. Core Pyramid OFF / DYNAMIC / FIRST_CORE_CUMULATIVE; Seed-only và Seed+DCA.
2. Core Pyramid Peel + re-arm: không mở lại sai anchor; FIRST_CORE dùng cumulative distance từ Core đầu campaign.
3. Recovery WAIT một phía không khóa Pyramid/exit hợp lệ phía đối diện.
4. Same-side Recovery ownership chặn risk-add cùng phía nhưng không chặn risk-reducing action.
5. Hedge Pyramid `MaxHedgeGenerations_ >= 2`; coverage sequence `80-81-82-85`; kiểm tra broker-volume de-dup và gap cộng dồn sau bậc bị skip.
6. Target/hard-cap: broker minimum không được đẩy Hedge vượt final target/hard cap; nếu phần thiếu < broker-min phải WAIT, zero mutation.
7. Smoking gun T17.6: Core 1.08 lot, retained Hedge 0.30, generation live 0.18, cap 90%; retained Hedge đóng bởi expected broker SL thì generation target được rebase lên khoảng 0.97 tổng target tương ứng, không fatal drift latch/TesterStop.
8. `flag_Hand_Ord=true`: manual magic-0 không làm tăng Core Recovery denominator/campaign trigger; exact Core Magic vẫn là ownership source.
9. Overlap 150 ms adverse move: leg1 winner đóng trước; sau broker-confirmed fill phải recheck economics; nếu leg2 chưa an toàn thì durable `LEG2_WAIT_SAFE`, không đóng lỗ gộp; restart phải resume/fail-closed đúng identity.
10. Overlap policy: OFF / CORE_ONLY / ALLOW_DURING_RECOVERY và LEGACY_AUTO migration từ `.set` cũ.
11. Persistence migration: state legacy sạch (IDLE/ARMED/REVERSAL_HOLD, no pending) được nhận; BUILDING/ACTIVE/PENDING legacy mismatch phải fail-closed, không reinterpret.
12. Global SL: `GlobalSLAfterGenerations_=0` = OFF; N>0 kích hoạt đúng generation; các knob inactive không đổi semantic fingerprint.
13. `ReHedgeGapPips_`: thay giá trị không được đổi fingerprint T17.7 active ARCS vì input chỉ còn compatibility/deprecated.
14. MoneyGuard: `MoneyTPAllAccount=300` và side/magic/daily guards phải preempt risk-add, đóng tới flat, không reopen cùng tick.
15. DCA after Hedge + corridor/coverage: exact Core Magic denominator, min coverage >100 được chấp nhận về mặt config khi reachable; unreachable staged target phải bị cross-validator chặn.
16. Restart/resume giữa pending open/close, protective SL, Overlap leg1/leg2 và Hedge generation; không duplicate mutation.
17. End-date completion: tester đi hết khoảng thời gian, không còn `RECONCILE_REQUIRED` không giải thích, không còn lệnh âm bị đóng trái contract.

## PASS gate của owner
- Không fatal invariant / unexpected `TesterStop`.
- Không duplicate trade do async timeout/retry.
- Không vượt Hedge hard cap.
- Overlap pair economics không gross-negative sau leg1 revalidation.
- MoneyGuard đạt close-to-flat đúng scope.
- Log tiếng Việt cho WAIT/LỖI nêu side + trạng thái + lý do; không spam mỗi tick.
- Tester kết thúc đúng end date và report/log được lưu làm runtime evidence.

Sau khi owner PASS toàn bộ matrix mới đủ điều kiện xem xét forward/live và Ready-for-Review/merge.
