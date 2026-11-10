# Sentinel Journal
## 2024-11-10 - Zod Input Exhaustion via Missing Bounds
**Vulnerability:** Input schemas using Zod for MCP server tools lacked maximum length bounds (`.max()`) on strings and numbers. Given a known CVE where Zod can exhaust memory on oversized constrained collections, unbounded string evaluation opens the system to a Denial of Service via massive inputs (e.g. 1GB query string).
**Learning:** Even internal tool endpoints (like local MCP servers) require input validation boundaries, especially when regex or heavy processing like `.toLowerCase()` loops are applied over the payload.
**Prevention:** Always append `.max()` limits to `z.string()` and `z.number()` declarations, particularly for unbounded parameters parsed from unknown clients.
