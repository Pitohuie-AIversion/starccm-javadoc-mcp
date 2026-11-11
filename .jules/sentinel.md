## 2024-11-11 - Missing Zod Input Length Limits
**Vulnerability:** The MCP server endpoints (`server.mjs`) lacked `.max()` limits on Zod schema strings and numbers, which could lead to Denial of Service via memory exhaustion from overly large inputs.
**Learning:** Due to restrictions on updating dependency versions directly in package.json, Zod must be used defensively with explicit length limits to avoid relying on automatic or future library-level mitigations for large payloads.
**Prevention:** Always include `.max()` constraints on all Zod `z.string()` and `z.number()` declarations to ensure inputs are bounded to reasonable sizes before processing.
