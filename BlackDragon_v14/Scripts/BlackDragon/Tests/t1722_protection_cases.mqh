// digits-tested: 3, 5
void T1722_RunCases()
{
   T1722_Check("BUY cash BE",MathAbs(PyProtect_LockPricePure(0,3000,.2,-2,0,100,.01)-3000.1)<1e-8);
   T1722_Check("SELL cash BE",MathAbs(PyProtect_LockPricePure(1,3000,.2,-2,0,100,.01)-2999.9)<1e-8);
   T1722_Check("BUY net lock after fee",MathAbs(PyProtect_LockPricePure(0,3000,.2,-2,3,100,.01)-3000.25)<1e-8);
   T1722_Check("SELL net lock after fee",MathAbs(PyProtect_LockPricePure(1,3000,.2,-2,3,100,.01)-2999.75)<1e-8);
   T1722_Check("BUY ticks round protective",MathAbs(PyProtect_LockPricePure(0,3000,.2,-2,3,100,.1)-3000.3)<1e-8);
   T1722_Check("SELL ticks round protective",MathAbs(PyProtect_LockPricePure(1,3000,.2,-2,3,100,.1)-2999.7)<1e-8);
   T1722_Check("positive booked cash reduces required excursion",MathAbs(PyProtect_LockPricePure(0,3000,.2,2,3,100,.01)-3000.05)<1e-8);
   T1722_Check("zero lot is unknown",PyProtect_LockPricePure(0,3000,0,-2,3,100,.01)==0);
   T1722_Check("missing tick is unknown",PyProtect_LockPricePure(0,3000,.2,-2,3,100,0)==0);
   T1722_Check("missing economics is unknown",PyProtect_LockPricePure(0,3000,.2,-2,3,0,.01)==0);
   T1722_Check("invalid direction",PyProtect_LockPricePure(2,3000,.2,-2,3,100,.01)==0);
   T1722_Check("BUY cannot loosen",PyProtect_StrongerPure(0,3005,3004)==3005);
   T1722_Check("SELL cannot loosen",PyProtect_StrongerPure(1,3005,3006)==3005);
   T1722_Check("BUY ratchet",PyProtect_StrongerPure(0,3005,3006)==3006);
   T1722_Check("SELL ratchet",PyProtect_StrongerPure(1,3005,3004)==3004);
   T1722_Check("zero candidate cannot erase",PyProtect_StrongerPure(0,3005,0)==3005);
   T1722_Check("BUY uses Bid",PyProtect_HitPure(0,3005,3005.2,3005));
   T1722_Check("SELL uses Ask",PyProtect_HitPure(1,3004.8,3005,3005));
   T1722_Check("BUY above stop",!PyProtect_HitPure(0,3005.01,3005.21,3005));
   T1722_Check("SELL below stop",!PyProtect_HitPure(1,3004.79,3004.99,3005));
   T1722_Check("missing quote cannot trigger",!PyProtect_HitPure(0,0,0,3005));
   T1722_Check("no stop cannot trigger",!PyProtect_HitPure(1,3000,3001,0));
   T1722_Check("group net after swap and fees once",MathAbs(PyProtect_NetAtPricePure(0,3000,.2,3001,100,-2,-1,1)-16)<1e-8);
   T1722_Check("SELL symmetry",MathAbs(PyProtect_NetAtPricePure(1,3000,.2,2999,100,-2,-1,1)-16)<1e-8);
   T1722_Check("partial survivor and realized",MathAbs(PyProtect_NetAtPricePure(0,3010,.1,3006,100,60,0,0)-20)<1e-8);
   T1722_Check("new episode excludes old realized",MathAbs(PyProtect_NetAtPricePure(0,3010,.1,3006,100,0,0,0)+40)<1e-8);
   T1722_Check("post PY cap 115 percent",PyProtect_CapUnitsPure(100,40,115)==69);
   T1722_Check("post partial same unreserved denominator",PyProtect_CapUnitsPure(80,20,115)==69);
   T1722_Check("no Core residual no Hedge",PyProtect_CapUnitsPure(40,40,115)==0);
   T1722_Check("fractional units round down",PyProtect_CapUnitsPure(13,4,115)==10);
   T1722_Check("100 percent cap",PyProtect_CapUnitsPure(100,40,100)==60);
   T1722_Check("BUY broker distance strict",!PyProtect_ArmablePure(0,3005,3005.2,3004,1));
   T1722_Check("BUY broker distance feasible",PyProtect_ArmablePure(0,3005.01,3005.21,3004,1));
   T1722_Check("SELL broker distance strict",!PyProtect_ArmablePure(1,3004.8,3005,3006,1));
   T1722_Check("SELL broker distance feasible",PyProtect_ArmablePure(1,3004.79,3004.99,3006,1));
   T1722_Check("ADD cannot spend locked floor",!PyProtect_AddFundedPure(0,3005,3006,.1,100,10,5,1));
   T1722_Check("funded ADD admitted",PyProtect_AddFundedPure(0,3005,3006,.1,100,20,5,1));
   T1722_Check("SELL funded ADD symmetry",PyProtect_AddFundedPure(1,3005,3004,.1,100,20,5,1));
   T1722_Check("unarmed ADD bypass",PyProtect_AddFundedPure(0,0,0,0,0,0,0,0));
   T1722_Check("ADD unknown volume waits",!PyProtect_AddFundedPure(0,3005,3006,0,100,20,5,1));
   T1722_Check("broker SL confirmed proof",PyProtect_ExpectedBrokerSlPure(true,7,7,3005,3005,0,.01));
   T1722_Check("broker SL same-event requested proof",PyProtect_ExpectedBrokerSlPure(true,7,7,3005,3004,3005,.01));
   T1722_Check("broker SL requested proof before first confirm",PyProtect_ExpectedBrokerSlPure(true,7,7,3005,0,3005,.01));
   T1722_Check("broker SL old episode rejected",!PyProtect_ExpectedBrokerSlPure(true,8,7,3005,3005,3005,.01));
   T1722_Check("virtual or mismatched SL rejected",!PyProtect_ExpectedBrokerSlPure(false,7,7,3005,3005,3005,.01) &&
                                               !PyProtect_ExpectedBrokerSlPure(true,7,7,3006,3005,3005,.01));
}
