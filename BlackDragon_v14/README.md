# EA BlackDragon v15.00 — runtime lineage T17.21

Đây là **một EA hiện hành**, không phải nhiều bản EA song song.

- Composition root: `Experts/BlackDragon/BlackDragon.mq5`
- Version hiển thị và binary: `15.00`
- Runtime lineage mới nhất: `T17.21`
- `RecoveryOneOrderPerBar_ = false`: bật để giới hạn mỗi hướng RH một lệnh mở/nến chart, kể cả mở lại sau BE/SL; Core DCA không chiếm lượt RH.
- Comment RH: `RH-S|G1|P1|N1`; sau BE/SL: `RHSL1-S|G1|P1|N1`; Pyramid: `PYR-B#3`. B/S là hướng lệnh. DCA giữ nguyên.
- Terminal Recovery Hedge positive-BE/SL re-entry: tối đa 2 chu kỳ mặc định
- Dashboard, nhãn thông tin và button chart cũ: đã xóa
- Mũi tên WMF: giữ nguyên qua input `ShowWmfSignals`
- Nhánh làm việc: `feat/t17-full-pyramid`
- Pull request: `#28`, luôn giữ **Draft**
- Trạng thái phát hành: owner Strategy Tester còn `PENDING`; forward/live không đủ điều kiện

## Bản đồ repo

| Khu vực | Vai trò |
|---|---|
| `Experts/BlackDragon/` | Entry point duy nhất của EA |
| `Include/BlackDragon/` | Module runtime; dashboard cũ không còn, WMF overlay tách riêng |
| `Scripts/BlackDragon/Tests/` | 30 native MQL suites, 40 C++ model suites, source/repository contracts |
| `Sets/` | Baseline setting được version-control |
| `docs/vibecode/` | Baseline T17.19, bổ sung T17.21 và trạng thái dự án |
| `docs/vibecode/archive/` | Governance/evidence lịch sử, frozen; không phải hướng dẫn hiện hành |
| `.github/workflows/verify-current.yml` | Workflow CI duy nhất |

Các tên như `T176Base`, `T177C4Base`, `T1713` là lớp tương thích trong
composition hiện hành. Chúng **không phải các EA cũ độc lập** và không được
xóa chỉ vì tên task nhỏ hơn T17.19.

## Điểm đọc cho review/update

1. `docs/vibecode/CURRENT_VERSION.md`
2. `HANDOFF.md`
3. `Include/BlackDragon/ARCHITECTURE.md`
4. `Include/BlackDragon/Config.mqh`
5. `Experts/BlackDragon/BlackDragon.mq5`
6. `docs/vibecode/T17_21_comments/EA-SPEC.yaml`
7. `docs/vibecode/T17_21_comments/DECISIONS.yaml`

## Gate build hiện hành

Workflow canonical bắt buộc:

- exact HEAD/TREE provenance;
- 40/40 C++ model suites;
- source contracts T17.11–T17.21;
- repository layout/include/version contract;
- ProbeEA, full EA và toàn bộ 30 native scripts: 0 error / 0 warning;
- chạy toàn bộ 30 native scripts và yêu cầu `ALL GREEN` (1030/0);
- artifact owner-QA có `BlackDragon.ex5`, toolchain và `PROVENANCE.txt`.

CI/native compile không thay thế Strategy Tester. Không merge PR, không bật
forward/live và không dùng EX5 cũ để chứng minh cho exact HEAD mới.

## Cài source

Copy đúng ba cây `Experts`, `Include`, `Scripts` vào `MQL5/`, sau đó
compile `Experts/BlackDragon/BlackDragon.mq5`. Input/default authoritative
nằm trong `Include/BlackDragon/Config.mqh`,
`Include/BlackDragon/Pyramid/PyramidConfig.mqh` và
`Include/BlackDragon/Recovery/RecoveryT16Config.mqh`.
