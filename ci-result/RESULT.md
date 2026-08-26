# MQL5 compile result

- source commit: `125de44dbe19bbf95b468613e4d1e62337d41113`
- run: https://github.com/hoaithivo0511-eng/BD-ea-remake/actions/runs/32990612484
- finished (UTC): 2026-08-26 16:51:35
- runner: Windows

| target | .ex5 produced | bytes | errors | warnings |
|---|---|---|---|---|
| RunTests | yes | 69700 | 0 | 0 |
| BlackDragon | yes | 653170 | 0 | 0 |

## Verdict

Both targets built. 0 errors, 0 warnings.

This proves the code compiles. It does NOT prove the 37 asserts pass -
running RunTests needs a terminal with a chart, which this job does not do.

### MetaEditor log - RunTests

```text


C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: compiling C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Config.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Config.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\UnitSystem.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Types.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\GridEngine.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\ExitEngine.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\BasketManager.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\BasketManager.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Logger.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Logger.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\JournalT177.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\ExecutionLayer.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\ExecutionLayer.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\License.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\ExecutionLayer.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryExecutionIdentity.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\MoneyGuard.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\EntryFilters.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\EntryFilters.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\NewsCalendar.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\MobileControl.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\WmfSignal.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryStateMachine.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryStateMachine.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryTypes.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryTypes.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryMath.mqh
C:\Program Files\MetaTrader 5\MQL5\Scripts\BlackDragon\Tests\RunTests.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryGlobalFlatten.mqh
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
Result: 0 errors, 0 warnings, 952 ms elapsed, cpu='X64 Regular'
```

### MetaEditor log - BlackDragon

```text


C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: compiling C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Config.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Config.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\UnitSystem.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryTypes.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryTypes.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryMath.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Pyramid\PyramidAnchorT177.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Pyramid\PyramidAnchorT177.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Pyramid\PyramidConfig.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Pyramid\PyramidConfig.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\GridEngine.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\GridEngine.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Types.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryEngine.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryEngine.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\ExecutionLayer.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\ExecutionLayer.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Logger.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Logger.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\JournalT177.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\ExecutionLayer.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\License.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\ExecutionLayer.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryExecutionIdentity.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryEngine.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryPersistence.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryPersistence.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryRegistry.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryRegistry.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryBundle.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryBundle.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryStateMachine.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryRegistry.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryGlobalFlatten.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryPersistence.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryExit.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryEngine.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT16Config.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT16Config.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT16ConfigT177C5Impl.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT16ConfigT177C5Impl.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT16ConfigT177C4Base.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT16ConfigT177C4Base.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT164Reachability.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryEngine.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT165GuardScope.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT165GuardScope.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT165Policy.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryEngine.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryEngineT13Base.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryEngineT13Base.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryMutationPolicy.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryEngineT13Base.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryLock.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryEngine.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackT177Scheduler.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackT177Scheduler.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT177Scheduler.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackT177Scheduler.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackT17Pyramid.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackT17Pyramid.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackPostDeal.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackPostDeal.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT163Policy.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackPostDeal.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackPostDealT162Base.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackPostDealT162Base.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackHardened.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackHardened.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStack.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStack.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsBook.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsBook.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsPersistence.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsPersistence.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsPersistenceT177C5Impl.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsPersistenceT177C5Impl.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsPersistenceT177C4Base.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsPersistenceT177C4Base.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsTypes.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryEngine.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackT177HedgeLadder.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackT177HedgeLadder.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackT177HedgeLadderC4Base.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackT177HedgeLadderC4Base.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT177HedgeLadder.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryArcsStackT177HedgeLadder.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT178RuntimePolicy.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Pyramid\CorePyramidT177Anchor.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Pyramid\CorePyramidT177Anchor.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\EntryFilters.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\EntryFilters.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\NewsCalendar.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Pyramid\CorePyramidT177Anchor.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\BasketManager.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Pyramid\CorePyramidT177Anchor.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Pyramid\CorePyramid.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryDca.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryExitCoordinator.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryExitCoordinator.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryExitCoordinatorT177Base.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryExitCoordinatorT177Base.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryExitCoordinatorT13Base.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryExitCoordinator.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT179RealTpPolicy.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\SignalEngine.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\WmfSignal.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\ExitEngine.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\MoneyGuard.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\MobileControl.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Panel.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Panel.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Persistence.mqh
C:\Program Files\MetaTrader 5\MQL5\Experts\BlackDragon\BlackDragon.mq5 : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Strategy.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Strategy.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\StrategyT176Base.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\StrategyT176Base.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT165MarginReserve.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\StrategyT176Base.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\StrategyT1711Admission.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Strategy.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Overlap\OverlapT177Coordinator.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Overlap\OverlapT177Coordinator.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT177MigrationPolicy.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Overlap\OverlapT177Coordinator.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Overlap\OverlapT177CoordinatorT177C3Base.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Overlap\OverlapT177CoordinatorT177C3Base.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Overlap\OverlapT177Policy.mqh
C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Strategy.mqh : information: including C:\Program Files\MetaTrader 5\MQL5\Include\BlackDragon\Recovery\RecoveryT1712EconomicPolicy.mqh
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
Result: 0 errors, 0 warnings, 14955 ms elapsed, cpu='X64 Regular'
```

