## 2025-02-28 - Optimize search API query matching
**Learning:** `O(N log N)` sorting combined with expensive string interpolation inside the hot path of an API search scales poorly with 100k+ API members (as seen when loading all classes/members from a large API like STAR-CCM+).
**Action:** Replace `O(N log N)` full-array sorting and filtering logic with a single `O(N)` pass that groups matches into `exact` and `partial` arrays and concatenates them, avoiding repetitive `.toLowerCase()` and template literals for strings that won't match anyway.
