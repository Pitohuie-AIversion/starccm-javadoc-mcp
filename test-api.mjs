import assert from 'node:assert/strict';

const types = [
    { name: 'Class1', pkg: 'pkg1' },
    { name: 'Class123', pkg: 'pkg2' },
    { name: 'Class3', pkg: 'pkg1' }
];

const q = 'class123';

const out1 = [];
const rankedTypes = [...types].sort((a, b) => Number(b.name.toLowerCase() === q || `${b.pkg}.${b.name}`.toLowerCase() === q) - Number(a.name.toLowerCase() === q || `${a.pkg}.${a.name}`.toLowerCase() === q));
for (const t of rankedTypes) {
    if (`${t.pkg}.${t.name}`.toLowerCase().includes(q)) {
        out1.push(t.name);
    }
}

const out2 = [];
const matchedTypes = [];
for (const t of types) {
    const full = t.pkg ? `${t.pkg}.${t.name}` : t.name;
    const fullLower = full.toLowerCase();
    if (fullLower.includes(q)) {
        matchedTypes.push({ t, fullLower, nameLower: t.name.toLowerCase() });
    }
}
matchedTypes.sort((a, b) => Number(b.nameLower === q || b.fullLower === q) - Number(a.nameLower === q || a.fullLower === q));
for (const { t } of matchedTypes) {
    out2.push(t.name);
}

assert.deepEqual(out1, out2);
console.log('Passed');
