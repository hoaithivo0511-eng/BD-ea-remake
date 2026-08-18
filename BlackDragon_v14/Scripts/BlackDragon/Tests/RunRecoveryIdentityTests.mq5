//+------------------------------------------------------------------+
//| RunRecoveryIdentityTests.mq5 — T14 deterministic identity tests  |
//+------------------------------------------------------------------+
#property script_show_inputs
#include <BlackDragon/Recovery/RecoveryExecutionIdentity.mqh>

int g_pass = 0;
int g_fail = 0;

void Check(const string name, const bool cond)
{
   if(cond) { g_pass++; return; }
   g_fail++;
   Print("FAIL: ", name);
}

void OnStart()
{
   // 1 / 7: completion is identity-based and independent of aggregate count
   // or later position lifetime once the correlated broker deal is confirmed.
   Check("OPEN same-count replacement completes by correlated identity",
         Recovery_ExecOpenIdentityCompletePure(TRADE_RETCODE_DONE,
                                                true, true, true, true, false,
                                                0.08, 0.08, 0.01));
   Check("historical confirmed OPEN remains terminal after position later closed",
         Recovery_ExecOpenIdentityCompletePure(TRADE_RETCODE_DONE,
                                                true, true, true, true, false,
                                                0.08, 0.08, 0.01));

   // 2 / 3: identity mismatches must never terminalize.
   Check("OPEN owner mismatch not complete",
         !Recovery_ExecOpenIdentityCompletePure(TRADE_RETCODE_DONE,
                                                 true, false, true, true, false,
                                                 0.08, 0.08, 0.01));
   Check("OPEN request id mismatch not complete",
         !Recovery_ExecOpenIdentityCompletePure(TRADE_RETCODE_DONE,
                                                 false, true, true, true, false,
                                                 0.08, 0.08, 0.01));

   // 4: DONE_PARTIAL needs cumulative correlated volume to reach target.
   Check("DONE complete",
         Recovery_ExecOpenIdentityCompletePure(TRADE_RETCODE_DONE,
                                                true, true, true, true, false,
                                                0.08, 0.08, 0.01));
   Check("DONE_PARTIAL below target remains pending",
         !Recovery_ExecOpenIdentityCompletePure(TRADE_RETCODE_DONE_PARTIAL,
                                                 true, true, true, true, false,
                                                 0.03, 0.08, 0.01));
   Check("DONE_PARTIAL cumulative target complete",
         Recovery_ExecOpenIdentityCompletePure(TRADE_RETCODE_DONE_PARTIAL,
                                                true, true, true, true, false,
                                                0.08, 0.08, 0.01));

   // 5 / 6: ambiguous strict outcomes and PLACED remain fail-closed/pending.
   Check("strict TIMEOUT ambiguous fail closed",
         Recovery_ExecStrictAmbiguousMustBlockPure(TRADE_RETCODE_TIMEOUT,
                                                    EXEC_RECONCILE_FAIL_CLOSED));
   Check("strict CONNECTION ambiguous fail closed",
         Recovery_ExecStrictAmbiguousMustBlockPure(TRADE_RETCODE_CONNECTION,
                                                    EXEC_RECONCILE_FAIL_CLOSED));
   Check("async PLACED without execution remains pending",
         !Recovery_ExecOpenIdentityCompletePure(TRADE_RETCODE_PLACED,
                                                 true, true, false, true, true,
                                                 0.0, 0.08, 0.01));

   // 8 / 9: protective SL correlation is durable-identity based. Current FSM
   // state is deliberately absent, so HEDGE_LOCK_PENDING / HEDGE_LOCKED /
   // already-advanced states all classify the same when identity matches.
   Check("protective SL HEDGE_LOCK_PENDING identity",
         Recovery_ProtectiveSlIdentityPure(true, true, DEAL_REASON_SL,
                                           4480.386, 4480.386, 4480.479,
                                           0.02, 0.50, true));
   Check("protective SL HEDGE_LOCKED identity",
         Recovery_ProtectiveSlIdentityPure(true, true, DEAL_REASON_SL,
                                           4480.386, 4480.386, 4480.479,
                                           0.02, 0.50, true));
   Check("protective SL after FSM advanced still internal",
         Recovery_ProtectiveSlIdentityPure(true, true, DEAL_REASON_SL,
                                           4480.386, 4480.386, 4480.479,
                                           0.02, 0.50, true));
   Check("random/manual SL target mismatch remains external",
         !Recovery_ProtectiveSlIdentityPure(true, true, DEAL_REASON_SL,
                                            4470.000, 4480.386, 4470.010,
                                            0.02, 0.50, false));
   Check("SL wrong owner remains external",
         !Recovery_ProtectiveSlIdentityPure(false, true, DEAL_REASON_SL,
                                            4480.386, 4480.386, 4480.479,
                                            0.02, 0.50, true));

   // 10 / 11: flat account releases only terminal-proven journal work.
   Check("global flat plus terminal-proven stale journal can release",
         Recovery_GlobalJournalReleasePure(true, true, false));
   Check("global flat plus ambiguous Recovery OPEN remains blocked",
         !Recovery_GlobalJournalReleasePure(true, false, true));

   PrintFormat("Recovery T14 identity tests: %d passed, %d failed", g_pass, g_fail);
   if(g_fail == 0) Print("ALL GREEN — T14 execution identity policy passed.");
}
