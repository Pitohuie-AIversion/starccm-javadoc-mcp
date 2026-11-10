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

console.time('optimized_isExact');
for (let i=0; i<100; i++) {
  const out = [];
  const matched = [];
  for (const t of types) {
    const full = `${t.pkg}.${t.name}`.toLowerCase();
    if (full.includes(q)) {
      const isExact = t.name.toLowerCase() === q || full === q;
      matched.push({ t, isExact });
    }
  }
  matched.sort((a, b) => Number(b.isExact) - Number(a.isExact));
  for (const { t } of matched) {
    out.push(`[type]   ${t.pkg ? t.pkg + "." : ""}${t.name}  ->  ${t.url}`);
  }
}
console.timeEnd('optimized_isExact');

console.time('optimized_no_alloc');
for (let i=0; i<100; i++) {
  const out = [];
  const matched = [];
  for (const t of types) {
    if (`${t.pkg}.${t.name}`.toLowerCase().includes(q)) {
      matched.push(t);
    }
  }
  matched.sort((a, b) => Number(b.name.toLowerCase() === q || `${b.pkg}.${b.name}`.toLowerCase() === q) - Number(a.name.toLowerCase() === q || `${a.pkg}.${a.name}`.toLowerCase() === q));
  for (const t of matched) {
    out.push(`[type]   ${t.pkg ? t.pkg + "." : ""}${t.name}  ->  ${t.url}`);
  }
}
console.timeEnd('optimized_no_alloc');
