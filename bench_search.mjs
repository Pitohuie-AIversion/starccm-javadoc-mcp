import { inspectJavadoc } from "./lib/javadoc.mjs";

const types = Array.from({length: 25000}, (_, i) => ({name: "Class" + i, pkg: "star.common", url: "url"}));
const members = Array.from({length: 200000}, (_, i) => ({name: "method" + i, cls: "Class" + (i%25000), pkg: "star.common", url: "url"}));

console.time("search types");
const q = "class1234".toLowerCase();
const rankedTypes = [...types].sort((a, b) => Number(b.name.toLowerCase() === q || `${b.pkg}.${b.name}`.toLowerCase() === q) - Number(a.name.toLowerCase() === q || `${a.pkg}.${a.name}`.toLowerCase() === q));
const outTypes = [];
for (const t of rankedTypes) {
  if (`${t.pkg}.${t.name}`.toLowerCase().includes(q)) {
    outTypes.push(`[type]   ${t.pkg ? t.pkg + "." : ""}${t.name}  ->  ${t.url}`);
  }
}
console.timeEnd("search types");

console.time("search members");
const outMembers = [];
for (const m of members) {
  if (`${m.pkg}.${m.cls}.${m.name}`.toLowerCase().includes(q)) {
    outMembers.push(`[member] ${m.pkg ? m.pkg + "." : ""}${m.cls}.${m.name}  ->  ${m.url}`);
  }
}
console.timeEnd("search members");
