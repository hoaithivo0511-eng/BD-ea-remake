//+------------------------------------------------------------------+
//| RunRecoveryMutationTests.mq5 — T13 deterministic policy tests    |
//+------------------------------------------------------------------+
+#property script_show_inputs
+#include <BlackDragon/Config.mqh>
+#include <BlackDragon/Recovery/RecoveryTypes.mqh>
+#include <BlackDragon/Recovery/RecoveryStateMachine.mqh>
+#include <BlackDragon/Recovery/RecoveryMutationPolicy.mqh>
+
+int g_pass = 0;
+int g_fail = 0;
+
+void Check(const string name, const bool cond)
+{
+   if(cond) { g_pass++; return; }
+   g_fail++;
+   Print("FAIL: ", name);
+}
+
+void OnStart()
+{
+   Check("CORE_ONLY overlap bypass", Recovery_OverlapPolicyPure(recovery_CORE_ONLY) == recovery_OVERLAP_BYPASS);
+   Check("COMPLETED overlap bypass", Recovery_OverlapPolicyPure(recovery_COMPLETED) == recovery_OVERLAP_BYPASS);
+   Check("ARMED overlap coordinated", Recovery_OverlapPolicyPure(recovery_ARMED) == recovery_OVERLAP_COORDINATE);
+   Check("HEDGE_ACTIVE overlap coordinated", Recovery_OverlapPolicyPure(recovery_HEDGE_ACTIVE) == recovery_OVERLAP_COORDINATE);
+   Check("HEDGE_LOCKED overlap coordinated", Recovery_OverlapPolicyPure(recovery_HEDGE_LOCKED) == recovery_OVERLAP_COORDINATE);
+
+   Check("HEDGE_BUILDING overlap deferred", Recovery_OverlapPolicyPure(recovery_HEDGE_BUILDING) == recovery_OVERLAP_DEFER);
+   Check("HEDGE_TP_PENDING overlap deferred", Recovery_OverlapPolicyPure(recovery_HEDGE_TP_PENDING) == recovery_OVERLAP_DEFER);
+   Check("CORE_CLOSE_PENDING overlap deferred", Recovery_OverlapPolicyPure(recovery_CORE_CLOSE_PENDING) == recovery_OVERLAP_DEFER);
+   Check("HEDGE_LOCK_PENDING overlap deferred", Recovery_OverlapPolicyPure(recovery_HEDGE_LOCK_PENDING) == recovery_OVERLAP_DEFER);
+   Check("REHEDGE_PENDING overlap deferred", Recovery_OverlapPolicyPure(recovery_REHEDGE_PENDING) == recovery_OVERLAP_DEFER);
+   Check("PAUSE_SOFT overlap deferred", Recovery_OverlapPolicyPure(recovery_PAUSE_SOFT) == recovery_OVERLAP_DEFER);
+   Check("PAUSE_HARD overlap deferred", Recovery_OverlapPolicyPure(recovery_PAUSE_HARD) == recovery_OVERLAP_DEFER);
+   Check("RECONCILE overlap deferred", Recovery_OverlapPolicyPure(recovery_RECONCILE_REQUIRED) == recovery_OVERLAP_DEFER);
+   Check("GLOBAL_STOP overlap deferred", Recovery_OverlapPolicyPure(recovery_GLOBAL_STOP) == recovery_OVERLAP_DEFER);
+
+   Check("CORE_ONLY stable side mutation", Recovery_SideMutationStableStatePure(recovery_CORE_ONLY));
+   Check("ARMED stable side mutation", Recovery_SideMutationStableStatePure(recovery_ARMED));
+   Check("HEDGE_ACTIVE stable side mutation", Recovery_SideMutationStableStatePure(recovery_HEDGE_ACTIVE));
+   Check("HEDGE_LOCKED stable side mutation", Recovery_SideMutationStableStatePure(recovery_HEDGE_LOCKED));
+   Check("COMPLETED stable side mutation", Recovery_SideMutationStableStatePure(recovery_COMPLETED));
+   Check("HEDGE_BUILDING not stable", !Recovery_SideMutationStableStatePure(recovery_HEDGE_BUILDING));
+   Check("HEDGE_TP_PENDING not stable", !Recovery_SideMutationStableStatePure(recovery_HEDGE_TP_PENDING));
+   Check("CORE_CLOSE_PENDING not stable", !Recovery_SideMutationStableStatePure(recovery_CORE_CLOSE_PENDING));
+   Check("HEDGE_LOCK_PENDING not stable", !Recovery_SideMutationStableStatePure(recovery_HEDGE_LOCK_PENDING));
+   Check("REHEDGE_PENDING not stable", !Recovery_SideMutationStableStatePure(recovery_REHEDGE_PENDING));
+
+   Check("T13 ARMED may disarm to CORE_ONLY after confirmed trim",
+         Recovery_StateTransitionAllowed(recovery_ARMED, recovery_CORE_ONLY));
+   Check("T13 ARMED still may build hedge",
+         Recovery_StateTransitionAllowed(recovery_ARMED, recovery_HEDGE_BUILDING));
+
+   PrintFormat("Recovery T13 mutation policy tests: %d passed, %d failed", g_pass, g_fail);
+   if(g_fail == 0) Print("ALL GREEN — T13 side-mutation/Overlap deterministic policy passed.");
+}
+