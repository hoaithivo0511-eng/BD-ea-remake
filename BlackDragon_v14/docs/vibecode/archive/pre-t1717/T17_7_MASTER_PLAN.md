# T17.7 MASTER PLAN — OWNER APPROVED

Baseline: `904dad4d92e31ebed56c75a54d8bd0537b0012a1` / tree `3cf49aed71288e5dfd0b1651c712763e7e55fbef`.

## Mục tiêu

T17.7 hợp nhất hai nhánh brainstorm đã được owner duyệt: (1) Core Pyramid anchor + scheduler Recovery/Pyramid; (2) Overlap Stage C + gộp/lược input + migration/fingerprint. T17.6 Stage A/B là baseline bắt buộc phải giữ regression-pass.

## C1 — Scheduler Recovery/Pyramid

- Thay `bool` kiểu WAIT cũng chiếm tick bằng disposition: `NO_EFFECT`, `WAIT`, `MUTATED`, `PENDING`, `RECONCILE`.
- `WAIT/NO_EFFECT`: không chiếm mutation slot, module khác được evaluate.
- `MUTATED/PENDING`: dừng mutation chain trong tick.
- `RECONCILE`: fail-closed.
- Recovery cùng side đã sở hữu topology: block Core Pyramid cùng side.
- Recovery opposite-side chỉ WAIT: không được block Pyramid side còn lại.
- Giữ invariant tối đa một trade mutation chain mỗi tick.

## C2 — Core Pyramid anchor

Thêm `CorePyramidAnchorMode_` độc lập với `CorePyramidMode_`.

### DYNAMIC
Giữ behavior hiện tại: DCA mới -> basket BE; sau Peel -> giá Peel; có Pyramid live -> giá Pyramid mới nhất; còn lại -> basket BE.

### FIRST_CORE_CUMULATIVE
- Anchor = giá Core exact-Magic đầu tiên của campaign.
- DCA/Peel không dịch anchor.
- Distance sequence cộng dồn theo serial: `25-35-38` => L1 +25, L2 +60, L3 +98, L4 +136...
- SELL đối xứng theo chiều giảm giá.
- `CHU_KY_SACH` và `TAI_KICH_HOAT` giữ vai trò riêng: quyết định có ADD lại sau Peel hay không.

## C3 — Overlap Stage C

Lifecycle durable: `PAIR_ARMED -> LEG1_SUBMITTED -> LEG1_CONFIRMED -> LEG2_RECHECK -> LEG2_WAIT_SAFE/LEG2_SUBMITTED -> COMPLETE`, hoặc `RECONCILE` khi outcome mơ hồ.

- Persist pair obligation trước leg 1.
- Sau leg 1 broker-confirmed: refresh floating, spread/deviation/cost và re-evaluate leg 2.
- Nếu leg 2 không còn an toàn: giữ durable WAIT, không ép đóng âm.
- Không blind retry.

## C4 — Hedge ladder + target semantics

- Một public final target: `HedgeTargetCoveragePercent_` = total live Recovery Hedge / current exact-Magic Core.
- Coverage sequence là các bậc trung gian.
- Hard cap riêng: `HedgeAbsoluteMaxCoveragePercent_`.
- Normalize raw coverage sang broker units; loại stage có cùng executable lot; remap gap theo effective ladder.
- Log rõ requested/effective/skipped stages.

## C5 — Input consolidation + persistence migration

- Overlap: một enum `OFF / CORE_ONLY / ALLOW_DURING_RECOVERY`.
- Global SL: `GlobalSLAfterGenerations_=0` nghĩa OFF; không cần boolean Enable riêng.
- `ReHedgeGapPips_`: LEGACY/DEPRECATED, không còn active ARCS semantics.
- Conditional fingerprint: input inactive không làm đổi persistence identity.
- Không xóa input cũ đột ngột; migration/versioning bắt buộc để `.set` cũ có đường chuyển.

## C6 — Log/journal tiếng Việt

Yêu cầu owner bắt buộc:

- Ngắn, dễ hiểu, hạn chế thuật ngữ.
- Nhìn một dòng phải biết: trạng thái hiện tại, đang làm gì/chờ gì, bị chặn/lỗi vì sao.
- Log WAIT phải cho biết điều kiện còn thiếu; có số đo thì ghi số còn thiếu.
- Log lỗi phải nêu module + BUY/SELL + trạng thái + hành động fail-closed.
- Không spam mỗi tick; state transition log một lần, WAIT dùng heartbeat có throttle.
- Giữ ticket/lot/price/serial/generation khi cần điều tra.

Format khuyến nghị:

`[BD:<MODULE>] <MỨC> <SIDE> | <TRẠNG THÁI> | <LÝ DO/VIỆC ĐANG LÀM> | <SỐ LIỆU>`

Ví dụ:

- `[BD:Pyramid] CHỜ SELL | Chưa đủ khoảng giá | mốc=4410.50 hiện=4402.10 còn=14.0 pip`
- `[BD:Recovery] CHỜ BUY | Hedge chờ bậc tiếp | đang=81% mục tiêu=85% còn=4%`
- `[BD:Overlap] CHỜ BUY | Lệnh 1 đã đóng, lệnh 2 chưa an toàn | dự kiến=-0.42 USD`
- `[BD:Recovery] LỖI BUY | Không xác định kết quả khớp lệnh | chuyển sang đối soát`

## C7 — Verify

Sau mỗi stage có rủi ro: pure/model -> source invariant -> MetaEditor 0/0 -> native MT5 -> T1-T17 regression.

Bản cuối phải có owner Strategy Tester cho 4 tổ hợp cycle/anchor, Seed-only, Seed+DCA, Peel/re-arm, restart, Recovery WAIT opposite-side, same-side ownership block, `MaxHedgeGenerations>=2`, `flag_Hand_Ord=true`, coverage `80-81-82-85`, Overlap 150ms adverse post-leg1, MoneyTPAllAccount=300 và end-date completion.

## Release gate

PR #28 tiếp tục Draft. Không mark Ready, không merge, không forward/live cho tới khi exact-head CI + owner Strategy Tester PASS và owner duyệt release/merge riêng.
