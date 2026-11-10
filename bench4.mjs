const members = [];
for (let i=0; i<150000; i++) {
  members.push({ name: `method${i}`, cls: `Class${i%100}`, pkg: `star.pkg${i%10}` });
}
const q = 'method1234';

console.time('current_member');
for (let i=0; i<100; i++) {
  let matched = 0;
  for (const m of members) {
    if (`${m.pkg}.${m.cls}.${m.name}`.toLowerCase().includes(q)) {
      matched++;
    }
  }
}
console.timeEnd('current_member');

console.time('optimized_member');
for (let i=0; i<100; i++) {
  let matched = 0;
  for (const m of members) {
    // avoid creating intermediate strings if possible, or build a pre-computed full string
    const full = `${m.pkg}.${m.cls}.${m.name}`.toLowerCase();
    if (full.includes(q)) {
      matched++;
    }
  }
}
console.timeEnd('optimized_member');

console.time('precomputed_member');
const preMembers = members.map(m => ({...m, full: `${m.pkg}.${m.cls}.${m.name}`.toLowerCase() }));
for (let i=0; i<100; i++) {
  let matched = 0;
  for (const m of preMembers) {
    if (m.full.includes(q)) {
      matched++;
    }
  }
}
console.timeEnd('precomputed_member');
