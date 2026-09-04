# T17.18 Owner QA — Dashboard-Free Baseline

Use only `BlackDragon.ex5` whose SHA256/size match the exact-head
`PROVENANCE.txt` in `blackdragon-current-owner-qa`.

- Confirm the EA displays no dashboard background, title, profit labels,
  level lines, buttons or edit-lot field.
- Confirm no chart click can Open/Close/Pause/toggle the EA.
- With `SignalSource_=sig_WMF` and `ShowWmfSignals=true`, confirm BUY/SELL WMF
  arrows still appear.
- With `ShowWmfSignals=false`, confirm WMF arrows are absent while WMF entry
  calculations continue unchanged.
- Confirm the 11 removed dashboard inputs are absent and
  `ShowWmfSignals` remains present.
- Replay the accepted owner `.set` and compare trades, timing, lots, exits,
  Recovery/Pyramid/Overlap and terminal balance against the exact baseline.
- Attach tester settings, report, complete journal/log and hashes to PR #28.

MetaEditor/native unit PASS is not Strategy Tester PASS. Do not merge or enable
forward/live trading from this checklist alone.

