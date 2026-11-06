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

console.time("two-arrays (filter then combine)");
for (let j = 0; j < 10; j++) {
  const exactTypes = [];
  const partialTypes = [];

  for (const t of types) {
    const full = t.pkg ? `${t.pkg}.${t.name}` : t.name;
    const fullLower = full.toLowerCase();

    if (fullLower.includes(q)) {
      if (t.name.toLowerCase() === q || fullLower === q) {
        exactTypes.push(`[type]   ${full}  ->  ${t.url}`);
      } else {
        partialTypes.push(`[type]   ${full}  ->  ${t.url}`);
      }
    }
  }
  const outTypes = exactTypes.concat(partialTypes);
}
console.timeEnd("two-arrays (filter then combine)");

console.time("two-arrays member search");
const members = Array.from({length: 200000}, (_, i) => ({name: "method" + i, cls: "Class" + (i%25000), pkg: "star.common", url: "url"}));
for (let j = 0; j < 10; j++) {
  const outMembers = [];
  for (const m of members) {
    const full = m.pkg ? `${m.pkg}.${m.cls}.${m.name}` : `${m.cls}.${m.name}`;
    if (full.toLowerCase().includes(q)) {
      outMembers.push(`[member] ${full}  ->  ${m.url}`);
    }
  }
}
console.timeEnd("two-arrays member search");
