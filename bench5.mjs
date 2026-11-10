const types = [];
const members = [];
for (let i=0; i<25000; i++) {
  types.push({ name: `Class${i}`, pkg: `star.pkg${i%10}` });
}
for (let i=0; i<150000; i++) {
  members.push({ name: `method${i}`, cls: `Class${i%100}`, pkg: `star.pkg${i%10}` });
}
const q = 'class123';

console.time('current_search_api');
for (let i=0; i<10; i++) {
  const out = [];
  const rankedTypes = [...types].sort((a, b) => Number(b.name.toLowerCase() === q || `${b.pkg}.${b.name}`.toLowerCase() === q) - Number(a.name.toLowerCase() === q || `${a.pkg}.${a.name}`.toLowerCase() === q));
  for (const t of rankedTypes) {
    if (`${t.pkg}.${t.name}`.toLowerCase().includes(q)) {
      out.push(`[type]   ${t.pkg ? t.pkg + "." : ""}${t.name}  ->  ${t.url}`);
    }
  }
  for (const m of members) {
    if (`${m.pkg}.${m.cls}.${m.name}`.toLowerCase().includes(q)) {
      out.push(`[member] ${m.pkg ? m.pkg + "." : ""}${m.cls}.${m.name}  ->  ${m.url}`);
    }
  }
}
console.timeEnd('current_search_api');


// Build optimized index
console.time('buildIndex_precomputed');
const optTypes = [];
const optMembers = [];
for (let i=0; i<25000; i++) {
  const name = `Class${i}`;
  const pkg = `star.pkg${i%10}`;
  const full = pkg ? `${pkg}.${name}` : name;
  optTypes.push({ name, pkg, fullLower: full.toLowerCase(), nameLower: name.toLowerCase() });
}
for (let i=0; i<150000; i++) {
  const name = `method${i}`;
  const cls = `Class${i%100}`;
  const pkg = `star.pkg${i%10}`;
  const full = pkg ? `${pkg}.${cls}.${name}` : `${cls}.${name}`;
  optMembers.push({ name, cls, pkg, fullLower: full.toLowerCase() });
}
console.timeEnd('buildIndex_precomputed');

console.time('optimized_search_api');
for (let i=0; i<10; i++) {
  const out = [];
  const matchedTypes = [];
  for (const t of optTypes) {
    if (t.fullLower.includes(q)) {
      matchedTypes.push(t);
    }
  }
  matchedTypes.sort((a, b) => Number(b.nameLower === q || b.fullLower === q) - Number(a.nameLower === q || a.fullLower === q));
  for (const t of matchedTypes) {
    out.push(`[type]   ${t.pkg ? t.pkg + "." : ""}${t.name}  ->  ${t.url}`);
  }

  for (const m of optMembers) {
    if (m.fullLower.includes(q)) {
      out.push(`[member] ${m.pkg ? m.pkg + "." : ""}${m.cls}.${m.name}  ->  ${m.url}`);
    }
  }
}
console.timeEnd('optimized_search_api');
