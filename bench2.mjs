const types = [];
for (let i=0; i<25000; i++) {
  types.push({ name: `Class${i}`, pkg: `star.pkg${i%10}` });
}
const q = 'class123';

console.time('original');
for (let i=0; i<100; i++) {
  const out = [];
  const rankedTypes = [...types].sort((a, b) => Number(b.name.toLowerCase() === q || `${b.pkg}.${b.name}`.toLowerCase() === q) - Number(a.name.toLowerCase() === q || `${a.pkg}.${a.name}`.toLowerCase() === q));
  for (const t of rankedTypes) {
    if (`${t.pkg}.${t.name}`.toLowerCase().includes(q)) {
      out.push(`[type]   ${t.pkg ? t.pkg + "." : ""}${t.name}  ->  ${t.url}`);
    }
  }
}
console.timeEnd('original');

console.time('optimized_filter_first');
for (let i=0; i<100; i++) {
  const out = [];
  const matched = [];
  for (const t of types) {
    const full = t.pkg ? `${t.pkg}.${t.name}` : t.name;
    if (full.toLowerCase().includes(q)) {
      matched.push({ t, full });
    }
  }
  matched.sort((a, b) => {
    const aExact = a.t.name.toLowerCase() === q || a.full.toLowerCase() === q;
    const bExact = b.t.name.toLowerCase() === q || b.full.toLowerCase() === q;
    return Number(bExact) - Number(aExact);
  });
  for (const { t } of matched) {
    out.push(`[type]   ${t.pkg ? t.pkg + "." : ""}${t.name}  ->  ${t.url}`);
  }
}
console.timeEnd('optimized_filter_first');
