# Baseline delta — T17.24 builder

Audit: d3b5ce19. Implementation base: 40c424cfa71b6742414b012e9d67d3294003f38e.

Upstream T17.23 added typed pre-arm wait, async reject consumer, replay direction filter, identifier-based commission, partial daily cash fix, ADX fail-closed and bounded PY state. These changes are retained.

Remaining issues inspected: owner resolution resets selected history during replay enumeration; Core daily cache lacks validity/recovery and late-day filtering; Recovery cash still excludes entry costs; invalid BE commission never retries without another topology event; callback rejection treats timeout/connection as no-effect; reject match omits operation nonce/position ID; repeated Recovery observation scans and campaign-second invalidation remain.

Full native verification and artifact compilation require a Windows MetaEditor backend. No such backend/connected GitHub credentials are exposed in this workspace at scan time. No stale EX5 will be supplied as an updated build.
