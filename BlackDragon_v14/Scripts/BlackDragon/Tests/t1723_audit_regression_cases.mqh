// T17.23 external-audit regression cases.
void T1723_RunCases()
{
   T1723_Check("F01 no excess continues",
      PyProtect_PrepareDecisionPure(0,false,false)==PY_PREPARE_CONTINUE);
   T1723_Check("F01 missing trim proof blocks",
      PyProtect_PrepareDecisionPure(40,false,false)==PY_PREPARE_BLOCK_UNKNOWN);
   T1723_Check("F01 unfunded trim waits",
      PyProtect_PrepareDecisionPure(40,true,false)==PY_PREPARE_WAIT_UNFUNDED);
   T1723_Check("F01 funded trim may execute",
      PyProtect_PrepareDecisionPure(40,true,true)==PY_PREPARE_TRIM_READY);
   bool oldCandidateArmable=PyProtect_ArmablePure(0,3005.0,3005.2,3000.4,1.0);
   bool fundedAfterArmable=PyProtect_ArmablePure(0,3005.0,3005.2,3006.4,1.0);
   T1723_Check("F01 counterexample old candidate differs from funded stop",
      oldCandidateArmable && !fundedAfterArmable &&
      PyProtect_PrepareDecisionPure(40,true,fundedAfterArmable)==PY_PREPARE_WAIT_UNFUNDED);
   T1723_Check("F02 exact definitive reject matches",
      PyProtect_RejectMatchesOperationPure(172200,7,1001,0,7,1001,false));
   T1723_Check("F02 wrong side cycle rejected",
      !PyProtect_RejectMatchesOperationPure(172201,7,1001,0,7,1001,false));
   T1723_Check("F02 wrong command rejected",
      !PyProtect_RejectMatchesOperationPure(172200,8,1001,0,7,1001,false));
   T1723_Check("F02 completed op cannot consume duplicate reject",
      !PyProtect_RejectMatchesOperationPure(172200,7,1001,0,7,1001,true));
}
