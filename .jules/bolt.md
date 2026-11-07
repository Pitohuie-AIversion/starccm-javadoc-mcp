## 2024-05-18 - Avoid O(N log N) Sorting for Matches Classification
**Learning:** In scenarios where exact matches need to be placed before partial matches, an O(N log N) `Array.sort()` combined with redundant string formatting and lowercasing inside the comparator creates an unnecessary performance bottleneck on large arrays (e.g., thousands of types/members).
**Action:** Instead of sorting, use a single O(N) pass to identify and separate exact matches from partial matches into two separate arrays, doing the string manipulations only once per element.
