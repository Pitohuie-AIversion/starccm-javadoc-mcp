const types = [];
const members = [];
for (let i=0; i<25000; i++) {
  types.push({ name: `Class${i}`, pkg: `star.pkg${i%10}` });
}
for (let i=0; i<150000; i++) {
  members.push({ name: `method${i}`, cls: `Class${i%100}`, pkg: `star.pkg${i%10}` });
}
const q = 'class123';

console.time('current_search_api_total');
const outOrig = [];
for (let i=0; i<100; i++) {
  outOrig.length = 0;
  const rankedTypes = [...types].sort((a, b) => Number(b.name.toLowerCase() === q || `${b.pkg}.${b.name}`.toLowerCase() === q) - Number(a.name.toLowerCase() === q || `${a.pkg}.${a.name}`.toLowerCase() === q));
  for (const t of rankedTypes) {
    if (`${t.pkg}.${t.name}`.toLowerCase().includes(q)) {
      outOrig.push(`[type]`);
    }
  }
  for (const m of members) {
    if (`${m.pkg}.${m.cls}.${m.name}`.toLowerCase().includes(q)) {
      outOrig.push(`[member]`);
    }
  }
}
console.timeEnd('current_search_api_total');

// What if we don't pre-compute on buildIndex, just don't allocate [...types] and strings dynamically?
console.time('no_precompute_optimized');
const outOpt = [];
for (let i=0; i<100; i++) {
  outOpt.length = 0;
  const matchedTypes = [];
  for (const t of types) {
    const full = t.pkg ? `${t.pkg}.${t.name}` : t.name;
    const fullLower = full.toLowerCase();
    if (fullLower.includes(q)) {
      matchedTypes.push({ t, fullLower, nameLower: t.name.toLowerCase() });
    }
  }
  matchedTypes.sort((a, b) => Number(b.nameLower === q || b.fullLower === q) - Number(a.nameLower === q || a.fullLower === q));
  for (const {t} of matchedTypes) {
    outOpt.push(`[type]`);
  }

  for (const m of members) {
    const fullLower = (m.pkg ? `${m.pkg}.${m.cls}.${m.name}` : `${m.cls}.${m.name}`).toLowerCase();
    if (fullLower.includes(q)) {
      outOpt.push(`[member]`);
    }
  }
}
console.timeEnd('no_precompute_optimized');
