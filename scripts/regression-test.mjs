import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, symlink, unlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { verify } from './smoke-test.mjs';
import { inspectJavadoc } from '../lib/javadoc.mjs';
const base = await mkdtemp(path.join(tmpdir(), 'starccm-regression-'));
const root = path.join(base, 'docs');
await mkdir(path.join(root, 'star/common'), { recursive: true });
await writeFile(path.join(root, 'type-search-index.js'), 'typeSearchIndex = [{"p":"star.common","l":"Simulation"}];');
await writeFile(path.join(root, 'member-search-index.js'), 'memberSearchIndex = [{"p":"star.common","c":"Simulation","l":"getRegionManager()","u":"getRegionManager()"},{"p":"star.common","c":"Simulation","l":"fallback()"}];');
await writeFile(path.join(root, 'star/common/Simulation.html'), '<html>Simulation getRegionManager() fallback()</html>');
await verify(root);
const client = new Client({ name: 'regression', version: '1.0.0' });
try {
  await client.connect(new StdioClientTransport({ command: process.execPath, args: [fileURLToPath(new URL('../server.mjs', import.meta.url)), root] }));
  for (const query of ['getRegionManager', 'fallback']) {
    const result = await client.callTool({ name: 'search_api', arguments: { query, kind: 'member' } });
    const docPath = result.content[0].text.match(/->\s+(\S+)/)[1];
    assert.equal(docPath, `star/common/Simulation.html#${query}()`);
    const doc = await client.callTool({ name: 'get_doc', arguments: { docPath } });
    assert(!doc.isError, JSON.stringify(doc));
    assert(doc.content[0].text.includes(query));
  }
  console.log('PASS: member result links can be passed directly to get_doc, including missing u.');
  const outside = path.join(base, 'private');
  await mkdir(outside);
  await writeFile(path.join(outside, 'secret.html'), 'PRIVATE');
  await symlink(outside, path.join(root, 'linked'), process.platform === 'win32' ? 'junction' : 'dir');
  const denied = await client.callTool({ name: 'get_doc', arguments: { docPath: 'linked/secret.html' } });
  assert.equal(denied.isError, true);
  assert(!denied.content[0].text.includes('PRIVATE'));
  console.log('PASS: symbolic link / Windows junction cannot escape Javadoc root.');
} finally { await client.close(); }

// An index failure must be reported, never silently treated as "no matches".
await writeFile(path.join(root, 'type-search-index.js'), 'broken index');
await assert.rejects(inspectJavadoc(root), /Invalid Javadoc search index/);
await unlink(path.join(root, 'type-search-index.js'));
await unlink(path.join(root, 'member-search-index.js'));
await assert.rejects(inspectJavadoc(root), /Incomplete Javadoc/);
await writeFile(path.join(root, 'index.html'), '<html>STAR API</html>');
await writeFile(path.join(root, 'star/common/Region.html'), '<html>Region</html>');
for (const name of ['IndexCounter', 'SearchableClass', 'OverviewManager']) {
  await writeFile(path.join(root, `star/common/${name}.html`), `<html>${name}</html>`);
}
await verify(root);
const legacy = new Client({ name: 'legacy-regression', version: '1.0.0' });
try {
  await legacy.connect(new StdioClientTransport({ command: process.execPath, args: [fileURLToPath(new URL('../server.mjs', import.meta.url)), root] }));
  const result = await legacy.callTool({ name: 'search_api', arguments: { query: 'getRegionManager', kind: 'member' } });
  assert(result.content[0].text.includes('Member search index is unavailable'));
  const types = await legacy.callTool({ name: 'search_api', arguments: { query: 'star.common.Simulation', kind: 'type' } });
  assert(types.content[0].text.includes('star/common/Simulation.html'));
  for (const name of ['IndexCounter', 'SearchableClass', 'OverviewManager']) {
    const found = await legacy.callTool({ name: 'search_api', arguments: { query: name, kind: 'type' } });
    assert(found.content[0].text.includes(`star/common/${name}.html`), `${name} was incorrectly filtered as an auxiliary page`);
  }
} finally { await legacy.close(); }
console.log('PASS: corrupt/incomplete docs rejected; legacy class search works with explicit member limitation.');
console.log('PASS: legacy classes beginning with Index/Search/Overview are searchable.');
