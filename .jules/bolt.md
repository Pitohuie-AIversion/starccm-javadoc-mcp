## 2024-11-06 - [Avoid O(N log N) Array sorting for fuzzy search ordering]
**Learning:** Found a common performance anti-pattern where a large array (25,000+ items) was fully sorted using expensive string operations just to bubble up a few exact matches before filtering.
**Action:** Next time you need to prioritize exact matches over partial ones in a large dataset, use an O(N) partitioning loop (pushing into exact and partial arrays) instead of Array.prototype.sort().
