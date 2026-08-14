# MQL5 compile result

- source commit: `7866367869b4f99fcc03e5f6e99e850be98c867d`
- run: https://github.com/hoaithivo0511-eng/BD-ea-remake/actions/runs/31851801533
- finished (UTC): 2026-08-14 23:53:46
- runner: Windows

| target | .ex5 produced | bytes | errors | warnings |
|---|---|---|---|---|
| RunTests | yes | 64946 | 0 | 0 |
| BlackDragon | yes | 157942 | 0 | 0 |

## Verdict

Both targets built. 0 errors, 0 warnings.

This proves the code compiles. It does NOT prove the 37 asserts pass -
running RunTests needs a terminal with a chart, which this job does not do.

### MetaEditor log - RunTests

```text


C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: compiling C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Config.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Types.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\GridEngine.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\ExitEngine.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\BasketManager.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\BasketManager.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Logger.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\ExecutionLayer.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\ExecutionLayer.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\License.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\MoneyGuard.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\EntryFilters.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\EntryFilters.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\NewsCalendar.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\MobileControl.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\WmfSignal.mqh
 : information: generating code
 : information: generating code 3%
 : information: generating code 6%
 : information: generating code 9%
 : information: generating code 12%
 : information: generating code 15%
 : information: generating code 18%
 : information: generating code 21%
 : information: generating code 24%
 : information: generating code 27%
 : information: generating code 30%
 : information: generating code 33%
 : information: generating code 36%
 : information: generating code 39%
 : information: generating code 42%
 : information: generating code 45%
 : information: generating code 48%
 : information: generating code 51%
 : information: generating code 54%
 : information: generating code 57%
 : information: generating code 60%
 : information: generating code 63%
 : information: generating code 66%
 : information: generating code 69%
 : information: generating code 72%
 : information: generating code 75%
 : information: generating code 78%
 : information: generating code 81%
 : information: generating code 84%
 : information: generating code 87%
 : information: generating code 90%
 : information: generating code 93%
 : information: generating code 95%
 : information: generating code 100%
 : information: code generated
Result: 0 errors, 0 warnings, 891 ms elapsed, cpu='X64 Regular'
```

### MetaEditor log - BlackDragon

```text


C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: compiling C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Config.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Types.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Logger.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\License.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\SignalEngine.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\WmfSignal.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\GridEngine.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\EntryFilters.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\EntryFilters.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\NewsCalendar.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\BasketManager.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\ExitEngine.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\ExecutionLayer.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\MoneyGuard.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\MobileControl.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Panel.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Panel.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Persistence.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Strategy.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Filters\AdxFilter.mqh
 : information: generating code
 : information: generating code 3%
 : information: generating code 6%
 : information: generating code 9%
 : information: generating code 12%
 : information: generating code 15%
 : information: generating code 18%
 : information: generating code 21%
 : information: generating code 24%
 : information: generating code 27%
 : information: generating code 30%
 : information: generating code 33%
 : information: generating code 36%
 : information: generating code 39%
 : information: generating code 42%
 : information: generating code 45%
 : information: generating code 48%
 : information: generating code 51%
 : information: generating code 54%
 : information: generating code 57%
 : information: generating code 60%
 : information: generating code 63%
 : information: generating code 66%
 : information: generating code 69%
 : information: generating code 72%
 : information: generating code 75%
 : information: generating code 78%
 : information: generating code 81%
 : information: generating code 84%
 : information: generating code 87%
 : information: generating code 90%
 : information: generating code 93%
 : information: generating code 95%
 : information: generating code 100%
 : information: code generated
Result: 0 errors, 0 warnings, 3439 ms elapsed, cpu='X64 Regular'
```

