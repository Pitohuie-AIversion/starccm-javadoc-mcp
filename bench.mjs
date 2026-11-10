const types = [];
for (let i=0; i<25000; i++) {
  types.push({ name: `Class${i}`, pkg: `star.pkg${i%10}` });
}
const q = 'class123';

console.time('current');
for (let i=0; i<100; i++) {
  const rankedTypes = [...types].sort((a, b) => Number(b.name.toLowerCase() === q || `${b.pkg}.${b.name}`.toLowerCase() === q) - Number(a.name.toLowerCase() === q || `${a.pkg}.${a.name}`.toLowerCase() === q));
  const out = [];
  for (const t of rankedTypes) {
    if (`${t.pkg}.${t.name}`.toLowerCase().includes(q)) {
      out.push(t);
    }
  }
}
console.timeEnd('current');

console.time('optimized');
for (let i=0; i<100; i++) {
  const matched = [];
  for (const t of types) {
    if (`${t.pkg}.${t.name}`.toLowerCase().includes(q)) {
      matched.push(t);
    }
  }
  matched.sort((a, b) => Number(b.name.toLowerCase() === q || `${b.pkg}.${b.name}`.toLowerCase() === q) - Number(a.name.toLowerCase() === q || `${a.pkg}.${a.name}`.toLowerCase() === q));
  const out = [];
  for (const t of matched) {
    out.push(t);
  }
}
console.timeEnd('optimized');
