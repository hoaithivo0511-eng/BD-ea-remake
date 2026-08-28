# T17.15 Retro guards

- A1/A4: exact unit examples lock Core 80, Hedge 68, cap 72, target 22 and remaining add four.
- A2: uncertain readiness, journal state, cap or refresh fails closed; over-cap does not auto-reduce Hedge.
- A3: the owner explicitly approved the three semantics in chat on 2026-08-28.
- A5: Core/Hedge denominator is reread from broker-observed positions after trim; stale latch-time values are not authority.
- A6/A8: durable Recovery command, execution journal and coordinator obligation must all be quiet; retry does not duplicate a mutation.
- A9: all comparisons use integer broker volume-step units and one percent-to-units floor.
- A10: Linux model/source is not native authority; Windows MetaEditor/native and owner Strategy Tester remain separate.
- A12: source contract checks exact runtime call sites after the multi-file edit.

Promotion decision: keep this domain-specific to Recovery/Overlap coordination; do not promote it to a universal guard.
