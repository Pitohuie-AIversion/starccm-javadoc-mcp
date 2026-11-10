const types = [];
const members = [];
for (let i=0; i<25000; i++) {
  types.push({ name: `Class${i}`, pkg: `star.pkg${i%10}`, url: 'abc' });
}
for (let i=0; i<150000; i++) {
  members.push({ name: `method${i}`, cls: `Class${i%100}`, pkg: `star.pkg${i%10}`, url: 'abc' });
}
const q = 'class123';

console.time('current_buildIndex');
const docs = { types, members };
for (let i=0; i<10; i++) {
  const t = [];
  const m = [];
  for (const docT of docs.types) {
    const pkg = docT.pkg || "";
    const url = docT.url || (pkg ? pkg.replaceAll(".", "/") + "/" + docT.name + ".html" : docT.name + ".html");
    t.push({ name: docT.name, pkg, url });
  }
  for (const docM of docs.members) {
    const pkg = docM.pkg || "";
    const classUrl = (pkg ? pkg.replaceAll(".", "/") + "/" : "") + (docM.cls || "") + ".html";
    const anchor = docM.name.replace(/^#/, "");
    m.push({ name: docM.name, cls: docM.cls || "", pkg, url: classUrl + "#" + anchor });
  }
}
console.timeEnd('current_buildIndex');

console.time('precomputed_buildIndex2');
for (let i=0; i<10; i++) {
  const t = [];
  const m = [];
  for (const docT of docs.types) {
    const pkg = docT.pkg || "";
    const url = docT.url || (pkg ? pkg.replaceAll(".", "/") + "/" + docT.name + ".html" : docT.name + ".html");
    const nameLower = docT.name.toLowerCase();
    const fullLower = (pkg ? pkg + "." + docT.name : docT.name).toLowerCase();
    t.push({ name: docT.name, pkg, url, nameLower, fullLower });
  }
  for (const docM of docs.members) {
    const pkg = docM.pkg || "";
    const classUrl = (pkg ? pkg.replaceAll(".", "/") + "/" : "") + (docM.cls || "") + ".html";
    const anchor = docM.name.replace(/^#/, "");
    const cls = docM.cls || "";
    const fullLower = (pkg ? pkg + "." + cls + "." + docM.name : cls + "." + docM.name).toLowerCase();
    m.push({ name: docM.name, cls, pkg, url: classUrl + "#" + anchor, fullLower });
  }
}
console.timeEnd('precomputed_buildIndex2');

console.time('precomputed_search_api2');
const out = [];
for (let i=0; i<100; i++) {
  out.length = 0;
  const matchedTypes = [];
  for (const t of types) {
    // mock use precomputed fullLower
    const fullLower = (t.pkg ? t.pkg + "." + t.name : t.name).toLowerCase();
    if (fullLower.includes(q)) {
      matchedTypes.push({ t, fullLower, nameLower: t.name.toLowerCase() });
    }
  }
  matchedTypes.sort((a, b) => Number(b.nameLower === q || b.fullLower === q) - Number(a.nameLower === q || a.fullLower === q));
  for (const {t} of matchedTypes) {
    out.push(`[type]   ${t.pkg ? t.pkg + "." : ""}${t.name}  ->  ${t.url}`);
  }

  for (const m of members) {
    const fullLower = (m.pkg ? m.pkg + "." + m.cls + "." + m.name : m.cls + "." + m.name).toLowerCase();
    if (fullLower.includes(q)) {
      out.push(`[member] ${m.pkg ? m.pkg + "." : ""}${m.cls}.${m.name}  ->  ${m.url}`);
    }
  }
}
console.timeEnd('precomputed_search_api2');
