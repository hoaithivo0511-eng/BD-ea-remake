# T17.21 — readable order comments

Implement the authorized comment formats in EA-SPEC.yaml. Comments participate in
ownership and recovery history, so use Full verification despite no intended
strategy change. Preserve all T17.20 trading calculations and gate behavior.

The exact replacement manifest reverses each existing-source edit back to the
T17.20 baseline hash. Historical T17.20 hashes remain frozen; its contract applies
this explicit normalization before checking them. New headers are exercised by
literal codec cases and an adapter compiling the actual runtime helper.
