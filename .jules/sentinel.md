## 2024-05-19 - Input Validation Length Constraints
**Vulnerability:** Missing maximum length constraints in Zod schemas for user-controlled inputs in `server.mjs` (`query`, `limit`, `docPath`, `maxChars`).
**Learning:** This codebase uses Zod for input validation on MCP endpoints, but omitted length limits, creating a risk of Denial of Service (DoS) via resource exhaustion (e.g. event loop blocking or memory exhaustion) on exceptionally large inputs.
**Prevention:** Always add sensible `.max()` bounds to string and number fields in Zod schemas handling user input, even for internal/local MCP servers, to ensure robust defense in depth.
