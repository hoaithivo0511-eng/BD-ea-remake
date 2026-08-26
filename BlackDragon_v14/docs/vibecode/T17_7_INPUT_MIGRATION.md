# T17.7 INPUT MIGRATION MAP

## Nguyên tắc

Không xóa/đổi tên input cũ ngay lập tức nếu việc đó làm `.set` cũ mất nghĩa. T17.7 ưu tiên một lớp compatibility/migration rõ ràng, sau đó mới cân nhắc remove ở release sau.

## Mapping đề xuất

| Input hiện tại | T17.7 public semantic | Migration |
|---|---|---|
| `Overlap` / legacy Overlap enable | `OverlapPolicy_=OVERLAP_CORE_ONLY` | migrate enable=true -> CORE_ONLY |
| `OverlapAfterHedge_` | `OverlapPolicy_=OVERLAP_ALLOW_DURING_RECOVERY` | nếu true ưu tiên ALLOW_DURING_RECOVERY |
| cả hai false | `OverlapPolicy_=OVERLAP_OFF` | direct |
| `EnableGlobalHedgeSL_` + `GlobalSLAfterGenerations_` | `GlobalSLAfterGenerations_` | Enable=false -> 0; Enable=true -> giữ N >= 1 |
| `ReHedgeGapPips_` | LEGACY/DEPRECATED | đọc để tương thích; không dùng trong active ARCS; không hash khi inactive |
| `HedgeVolumePercent_` | `HedgeTargetCoveragePercent_` | migrate giá trị hiện tại làm final target |
| `HedgePyramidMaxCoveragePercent_` | `HedgeAbsoluteMaxCoveragePercent_` | hard cap riêng; nếu <=0 dùng policy default/disabled theo contract |
| `HedgePyramidCoverageSequence_` | intermediate coverage ladder | giữ string; normalize theo broker units |
| `HedgePyramidGapSequence_` | effective-stage gap ladder | giữ string; remap sau broker-unit dedup |
| `CorePyramidMode_` | giữ nguyên | không thay nghĩa |
| mới: `CorePyramidAnchorMode_` | DYNAMIC / FIRST_CORE_CUMULATIVE | default DYNAMIC để giữ parity `.set` cũ |

## Xung đột migration

- Nếu legacy Overlap=true và `OverlapAfterHedge_=true`: chọn `ALLOW_DURING_RECOVERY` vì đó là policy rộng hơn, đồng thời log một cảnh báo migration một lần.
- Nếu GlobalSL legacy Enable=false nhưng N>0: migrate thành OFF (`0`), vì boolean cũ là master switch.
- Nếu Hedge final target > hard cap: effective target = hard cap và log rõ requested/effective.
- Nếu nhiều coverage raw map về cùng broker volume: giữ stage đầu tiên đạt volume đó, bỏ stage trùng và log danh sách stage bị bỏ.

## Persistence fingerprint

T17.7 phải tăng persistence/config policy revision và có migration test. Fingerprint mới chỉ chứa input đang có executable effect:

- Core Pyramid OFF: bỏ Core Pyramid anchor/distance/lot/risk knobs khỏi active fingerprint.
- Hedge Pyramid OFF: bỏ intermediate ladder/gap/lock-before-add knobs.
- Global SL OFF (`GlobalSLAfterGenerations_=0`): bỏ Global profit/reentry fields chỉ thuộc Global SL nếu không được dùng ở mode khác.
- Overlap OFF: bỏ Overlap execution-policy fields.
- `ReHedgeGapPips_` legacy inactive: không được làm persistence mismatch.

Không được reinterpret persisted BUILDING/ACTIVE state âm thầm. Nếu không thể migration an toàn từ revision cũ, fail-closed với thông báo tiếng Việt nói rõ cần khởi tạo state sạch.

## Logging migration

Ví dụ log một lần khi init:

- `[BD:Cấu hình] THÔNG TIN | Đã chuyển cài đặt Overlap cũ | chế độ=Mở rộng khi Recovery hoạt động`
- `[BD:Cấu hình] CẢNH BÁO | ReHedgeGap cũ không còn dùng trong ARCS | giữ chỉ để tương thích file set`
- `[BD:Cấu hình] THÔNG TIN | Ladder Hedge đã chuẩn hóa | 82% bị bỏ vì cùng lot với 81%`
