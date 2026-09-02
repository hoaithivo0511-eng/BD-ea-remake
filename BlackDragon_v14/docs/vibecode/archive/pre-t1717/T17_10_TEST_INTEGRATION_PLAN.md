# T17.10 Test / Integration Plan

The independent model and native script exercise XAU 2/3-digit and EURUSD 4/5-digit profiles.

- Prove `LEGACY_COMPAT` matches the historical formulas for TP/SL/trailing/spread/slippage/DCA.
- Prove `PIP_UNIFIED` yields identical price for equal pip inputs across quote digits.
- Prove Recovery/Pyramid true-pip conversion is unchanged.
- Prove price-to-broker-point conversion rounds outward and never narrows requested deviation.
- Prove cost-to-price conversion uses tick size, including `tickSize != point`.
- Prove invalid point/tick/pip metadata fails closed.
- Compile focused script and full EA with 0 errors / 0 warnings, then replay every established model/native suite from exact final HEAD.

Native compile does not establish Strategy Tester behavior.
