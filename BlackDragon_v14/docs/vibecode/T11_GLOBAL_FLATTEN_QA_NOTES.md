# T11 — Global Flatten / New-Cycle Recovery Reset

Status: IMPLEMENTED IN SOURCE; NATIVE/STRATEGY TESTER RE-VERIFY REQUIRED.

## Runtime evidence that triggered T11

Owner Strategy Tester showed `Money TP All account` correctly firing and `CloseAllAccount` successfully sending all close requests, but the EA did not start a later Core series despite a valid signal. No explicit Journal error followed the flatten.

## Root cause

T10 account-wide MoneyGuard preempted the T8 exit coordinator and flattened broker positions, but T8 only reset its own transient coordinator cycles. The T3/T9 Recovery registry could retain the pre-flatten ACTIVE state (`HEDGE_ACTIVE`, `HEDGE_TP_PENDING`, `CORE_CLOSE_PENDING`, `HEDGE_LOCK_PENDING`, `HEDGE_LOCKED`, etc.). That stale logical cycle could block or later fail-close new-series execution.

## T11 contract

Account-wide flatten is now a two-phase lifecycle boundary:

1. T8 keeps `m_accountWidePending` latched while any account position exists and continues `CloseAllAccount()` as required.
2. Even when `PositionsTotal()==0`, T8 does **not** release while `ExecutionLayer::HasPending()` is true. This prevents a delayed async OPEN/MODIFY result from escaping the global-close boundary.
3. Only after `positions==0 && execution journal quiet` may stale durable Recovery commands be cleared.
4. T8 raises a global-finalization latch. On the next Recovery `OnTick`, BUY and SELL logical cycles transition to `COMPLETED`.
5. The cycle serial is pre-rolled at this terminal boundary so T5/T6 mechanics reset in that same observation before persistence/release.
6. T8 verifies both cycles are `COMPLETED`, flushes Recovery persistence, confirms `ActiveReady()`, then releases the account-wide latch.
7. A later confirmed Core entry reuses the clean completed slot and normal new-series logic resumes.

## Expected Journal sequence

After an account money TP/SL fires during Recovery ACTIVE, a healthy T11 sequence should include:

- `Money TP All account: ...`
- `CloseAllAccount: ... close request(s) sent ...`
- `GLOBAL FLATTEN broker state confirmed — waiting for BUY/SELL Recovery cycles to reach COMPLETED`
- `GLOBAL FLATTEN complete — Recovery cycles COMPLETED and persisted; new Core series enabled`

If a future signal is blocked because Recovery is genuinely not ready, T11 now logs:

- `new Core series blocked: Recovery ACTIVE is not reconciled/ready`

instead of silently rejecting the new series.

## Safety / evidence limits

- No global reset occurs while positions remain live.
- No global reset occurs while any execution request is unresolved.
- Persistence failure remains fail-closed and keeps global-close blocking active.
- `MoneyTPAllAccount` is still whole-account floating P/L; this T11 change does not alter MoneyGuard threshold semantics.
- Exact MetaEditor compile and native RunTests must pass before owner retest.
- Owner Strategy Tester must reproduce: Recovery ACTIVE -> MoneyTPAllAccount flatten -> later valid signal -> new Core order opens.
- Async late-fill, restart/reconnect and broker-forward parity remain separate runtime evidence gates.
