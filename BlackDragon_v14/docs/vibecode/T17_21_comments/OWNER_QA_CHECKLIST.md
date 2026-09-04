# T17.21 owner QA — readable comments

- [ ] Install the exact verified EX5 on a tester with the owner set.
- [ ] Check RH-S|G1|P1|N1 and BUY equivalents; B/S is order direction.
- [ ] After full protective BE/SL reset, check RHSL1 then RHSL2 and later rounds.
- [ ] Check G/P/N against generation, stage and opening history; RHSL is a display count, not the outer reentry limit.
- [ ] Check PYR-B#n/PYR-S#n; Core DCA retains its input comment and ordinal.
- [ ] Restart with mixed old BDR/BDP and new positions and pending journal; ownership, SL management and reconcile must remain correct.
- [ ] Migrated history can show RHSL?; no invented historical round and no new admission block.
- [ ] Confirm the broker preserves at least the side/G/B identity. Extreme identifiers may omit optional P/N to fit 31 characters.
- [ ] Confirm T17.20 one-bar OFF/ON and all previous lot, price, coverage and NewCycle behavior.

Existing positions cannot be renamed by this EA change. Native scripts and small
regression tester runs do not replace owner XAUUSDm, restart or broker acceptance.
Release, forward, live and merge remain false; PR stays Draft.
