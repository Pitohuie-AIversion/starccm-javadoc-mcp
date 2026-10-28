import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';
import { inspectJavadoc } from '../lib/javadoc.mjs';

export async function verify(root) {
  const profile = await inspectJavadoc(root);
  console.log(`Documentation format: ${profile.format}`);
  if (!profile.members) console.log('NOTICE: no member index; class search and document reading only.');
  const client = new Client({ name: 'starccm-codex-verifier', version: '1.0.0' });
  const transport = new StdioClientTransport({
    command: process.execPath,
    args: [fileURLToPath(new URL('../server.mjs', import.meta.url)), root],
    stderr: 'pipe',
  });
  try {
    await client.connect(transport);
    const listed = await client.listTools();
    assert.deepEqual(listed.tools.map(t => t.name).sort(), ['get_doc', 'search_api']);
    const searched = await client.callTool({ name: 'search_api', arguments: { query: 'star.common.Simulation', kind: 'type', limit: 1 } });
    assert(!searched.isError);
    assert(searched.content.some(c => c.text?.includes('star.common.Simulation')));
    const returnedPath = searched.content.map(c => c.text || '').join('\n').match(/->\s+(\S+)/)?.[1];
    assert.equal(returnedPath?.split('#')[0], 'star/common/Simulation.html');
    const doc = await client.callTool({ name: 'get_doc', arguments: { docPath: returnedPath } });
    assert(!doc.isError);
    assert(doc.content.some(c => c.text?.includes('Simulation')));
    if (profile.members) {
      const sample = profile.members.find(m => m.p === 'star.common' && m.c === 'Simulation');
      assert(sample, 'No Simulation members in the member index. Check the documentation version/content.');
      const found = await client.callTool({ name: 'search_api', arguments: { query: `star.common.Simulation.${sample.l}`, kind: 'member' } });
      assert(!found.isError);
      const memberPath = found.content.map(c => c.text || '').join('\n').match(/->\s+(\S+)/)?.[1];
      assert(memberPath?.startsWith('star/common/Simulation.html#'));
      const memberDoc = await client.callTool({ name: 'get_doc', arguments: { docPath: memberPath } });
      assert(!memberDoc.isError, 'Member search returned an unreadable page.');
    }
    for (const docPath of ['../outside.html', 'type-search-index.js']) {
      const denied = await client.callTool({ name: 'get_doc', arguments: { docPath } });
      assert.equal(denied.isError, true);
    }
    console.log('PASS: MCP initialize, tools/list, search_api, get_doc, path restrictions.');
  } finally { await client.close(); }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (!process.argv[2]) throw new Error('Usage: node scripts/smoke-test.mjs <Javadoc root>');
    await verify(path.resolve(process.argv[2]));
  } catch (error) {
    console.error(`MCP verification failed: ${error.message}`);
    process.exitCode = 1;
  }
}
