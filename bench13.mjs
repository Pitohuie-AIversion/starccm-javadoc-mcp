const types = [];
const members = [];
for (let i=0; i<25000; i++) {
  types.push({ name: `Class${i}`, pkg: `star.pkg${i%10}`, url: 'abc' });
}
for (let i=0; i<150000; i++) {
  members.push({ name: `method${i}`, cls: `Class${i%100}`, pkg: `star.pkg${i%10}`, url: 'abc' });
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

console.time('optimized_types');
for (let i=0; i<100; i++) {
  const out = [];
  const matchedTypes = [];
  for (const t of types) {
    const fullLower = (t.pkg ? t.pkg + "." + t.name : t.name).toLowerCase();
    if (fullLower.includes(q)) {
      matchedTypes.push({ t, fullLower, nameLower: t.name.toLowerCase() });
    }
  }
  matchedTypes.sort((a, b) => Number(b.nameLower === q || b.fullLower === q) - Number(a.nameLower === q || a.fullLower === q));
  for (const {t} of matchedTypes) {
    out.push(`[type]   ${t.pkg ? t.pkg + "." : ""}${t.name}  ->  ${t.url}`);
  }
}
console.timeEnd('optimized_types');
