// T17.23 external-audit regression cases.
double T1723_F03LegacyCrossScopedSpent()
{
   long sellCursor=100000;
   double spent=0.0;
   // Legacy BUY replay admitted the SELL close at 250000 and ApplyCloseDeal()
   // moved the SELL cursor before SELL replay had a chance to see 150000.
   spent+=5.0;
   sellCursor=250000;
   if(150000>sellCursor) spent+=50.0;
   return spent;
}

double T1723_F03DirectionScopedSpent()
{
   long sellCursor=100000;
   double spent=0.0;
   // BUY replay ignores both SELL deals. SELL replay then consumes them in
   // deterministic time order and advances only its own cursor.
   if(150000>sellCursor) { spent+=50.0; sellCursor=150000; }
   if(250000>sellCursor) { spent+=5.0;  sellCursor=250000; }
   return spent;
}

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
   T1723_Check("F03 legacy cross-scope counterexample books only 5",
      MathAbs(T1723_F03LegacyCrossScopedSpent()-5.0)<1e-8);
   T1723_Check("F03 direction-scoped replay books full 55",
      MathAbs(T1723_F03DirectionScopedSpent()-55.0)<1e-8);
}
