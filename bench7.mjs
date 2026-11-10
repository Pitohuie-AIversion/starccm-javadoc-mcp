const types = [];
const members = [];
for (let i=0; i<25000; i++) {
  types.push({ name: `Class${i}`, pkg: `star.pkg${i%10}` });
}
for (let i=0; i<150000; i++) {
  members.push({ name: `method${i}`, cls: `Class${i%100}`, pkg: `star.pkg${i%10}` });
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

console.time('precomputed_buildIndex');
for (let i=0; i<10; i++) {
  const t = [];
  const m = [];
  for (const docT of docs.types) {
    const pkg = docT.pkg || "";
    const url = docT.url || (pkg ? pkg.replaceAll(".", "/") + "/" + docT.name + ".html" : docT.name + ".html");
    const nameLower = docT.name.toLowerCase();
    const fullLower = pkg ? `${pkg}.${docT.name}`.toLowerCase() : nameLower;
    t.push({ name: docT.name, pkg, url, nameLower, fullLower });
  }
  for (const docM of docs.members) {
    const pkg = docM.pkg || "";
    const classUrl = (pkg ? pkg.replaceAll(".", "/") + "/" : "") + (docM.cls || "") + ".html";
    const anchor = docM.name.replace(/^#/, "");
    const cls = docM.cls || "";
    const fullLower = (pkg ? `${pkg}.${cls}.${docM.name}` : `${cls}.${docM.name}`).toLowerCase();
    m.push({ name: docM.name, cls, pkg, url: classUrl + "#" + anchor, fullLower });
  }
}
console.timeEnd('precomputed_buildIndex');
