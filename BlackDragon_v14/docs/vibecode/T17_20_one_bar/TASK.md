# T17.20 — optional one RH opening order per bar

[CONTRACTOR] Full applies because this changes Recovery order admission. The owner request authorizes the additive input; no earlier audit fix is included.

SCAN: T17.19 exact source tree is clean. Five production-reachable RH open primitives exist across legacy ARCS, hardened ARCS and staged Hedge implementations. Core Pyramid has separate owner-aware calls and must remain unchanged. Existing Hedge timing can reset at generation boundaries and permits multiple children within an admitted stage.

RRI: default OFF preserves behavior. ON counts filled RH opens, including already-closed positions, per chart candle and Recovery direction. First RH retains its trigger because Core orders do not consume a RH slot. A prior RH from the same candle still counts after a generation/campaign reset. New data dependencies cause WAIT only. No new persistence or changing SL classification.

Blueprint: input → shared read-only broker/history gate → existing save-before-mutation → existing async/sync executor. All exit paths and existing pending journal remain intact.

Task graph: source/contract → gate at five open sites → actual-runtime adapter regression and native pure policy cases → source/full model regression → native compile/scripts and targeted tester → exact-parent publication and evidence.

Acceptance: OFF has no extra data reads; ON prevents a second opening order in the candle even after BE/SL/restart; opposite direction is independent; Core opening orders do not consume RH slots; wait occurs before durable order intent; protected audit logic hashes match baseline. Native compile remains 0 errors/0 warnings. No compile/model result substitutes for Strategy Tester evidence.

RETRO: a generation-local/live-position-only timestamp cannot enforce a candle rule after a close or generation reset. Use current-bar broker history, with no retained-cache assumption. Performance scope is bounded current-bar history at an otherwise eligible RH open, not a tick-wide history replay.
