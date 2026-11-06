import { inspectJavadoc } from "./lib/javadoc.mjs";

const types = Array.from({length: 25000}, (_, i) => ({name: "Class" + i, pkg: "star.common", url: "url"}));
const q = "class1234".toLowerCase();

console.time("original sort-filter");
for (let j = 0; j < 10; j++) {
  const rankedTypes = [...types].sort((a, b) => Number(b.name.toLowerCase() === q || `${b.pkg}.${b.name}`.toLowerCase() === q) - Number(a.name.toLowerCase() === q || `${a.pkg}.${a.name}`.toLowerCase() === q));
  const outTypes = [];
  for (const t of rankedTypes) {
    if (`${t.pkg}.${t.name}`.toLowerCase().includes(q)) {
      outTypes.push(`[type]   ${t.pkg ? t.pkg + "." : ""}${t.name}  ->  ${t.url}`);
    }
  }
}
console.timeEnd("original sort-filter");

console.time("filter-sort");
for (let j = 0; j < 10; j++) {
  const matched = [];
  for (const t of types) {
    const full = t.pkg ? `${t.pkg}.${t.name}` : t.name;
    const fullLower = full.toLowerCase();
    if (fullLower.includes(q)) {
      const exact = t.name.toLowerCase() === q || fullLower === q;
      matched.push({ t, exact });
    }
  }
  matched.sort((a, b) => Number(b.exact) - Number(a.exact));
  const outTypes = [];
  for (const { t } of matched) {
    outTypes.push(`[type]   ${t.pkg ? t.pkg + "." : ""}${t.name}  ->  ${t.url}`);
  }
}
console.timeEnd("filter-sort");
