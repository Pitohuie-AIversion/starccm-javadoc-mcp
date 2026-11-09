## 2024-03-01 - Prevent DoS with Input Length Limits
**Vulnerability:** MCP Server tools (`search_api` and `get_doc`) lacked maximum bounds on input parameters (`query`, `limit`, `docPath`, `maxChars`). This allowed potential unbounded input strings/numbers that could lead to Denial of Service (DoS) due to high memory allocation or excessive string/array manipulation within processing functions.
**Learning:** MCP server integrations using schemas (like Zod) must explicitly bound both minimum and maximum inputs because upstream constraints from typical HTTP handlers or proxies aren't guaranteed to exist.
**Prevention:** Always add `.max()` constraints to string and numeric types in Zod schemas for all exposed MCP tool inputs.
