# T17.18 Retro Guardrails

- A3/A13: Never classify signal overlays as dashboard controls without owner
  confirmation; preserve `ShowWmfSignals` independently from future panel work.
- A1/A5/A14: Before removing a timer named after UI, enumerate every actual
  responsibility. Rename it only after safety/liveness duties are locked.
- A12: UI classes that emit trade requests are architectural dependencies, not
  display-only files; remove composition root and both Strategy layers together.
- A1/A5: Retire persisted fields by reserved slots when later fields must keep
  binary offsets. Make enum values explicit before deleting a historical source.
- A11: Static call/object reduction is valid evidence of removed work, not a
  measured tester speedup. Native comparative timing requires a separate gate.
- A13: The accurate claim is dashboard-free with optional WMF arrows, not a
  chart with no visual objects.

Strategy Tester remains `PENDING_OWNER` and release/forward/live remain false.

