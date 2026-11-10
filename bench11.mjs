const members = [];
for (let i=0; i<150000; i++) {
  members.push({ name: `method${i}`, cls: `Class${i%100}`, pkg: `star.pkg${i%10}`, url: 'abc' });
}
const q = 'method1234';

console.time('original');
for (let i=0; i<100; i++) {
  let c = 0;
  for (const m of members) {
    if (`${m.pkg}.${m.cls}.${m.name}`.toLowerCase().includes(q)) {
      c++;
    }
  }
}
console.timeEnd('original');

console.time('optimized_string_concat');
for (let i=0; i<100; i++) {
  let c = 0;
  for (const m of members) {
    const full = m.pkg ? m.pkg + "." + m.cls + "." + m.name : m.cls + "." + m.name;
    if (full.toLowerCase().includes(q)) {
      c++;
    }
  }
}
console.timeEnd('optimized_string_concat');
