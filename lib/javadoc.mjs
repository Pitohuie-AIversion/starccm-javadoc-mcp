import { promises as fs } from 'node:fs';
import path from 'node:path';

export async function exists(file) {
  try { return (await fs.stat(file)).isFile(); } catch { return false; }
}

export async function readSearchIndex(file) {
  const raw = await fs.readFile(file, 'utf8');
  const start = raw.indexOf('['), end = raw.lastIndexOf(']');
  let rows;
  try { rows = JSON.parse(raw.slice(start, end + 1)); } catch {
    throw new Error(`Invalid Javadoc search index: ${file}. Restore the original documentation.`);
  }
  if (!Array.isArray(rows) || rows.length === 0 || rows.some(r => !r || typeof r.l !== 'string' || !r.l || ['p', 'c', 'u', 'm'].some(k => r[k] !== undefined && typeof r[k] !== 'string'))) {
    throw new Error(`Empty or malformed Javadoc search index: ${file}`);
  }
  return rows;
}

export async function inspectJavadoc(root) {
  const simulation = path.join(root, 'star/common/Simulation.html');
  if (!await exists(simulation)) throw new Error(`Missing STAR-CCM+ Simulation documentation under: ${root}`);
  const html = await fs.readFile(simulation, 'utf8');
  if (!/<(?:html|body)\b/i.test(html) || !/\bSimulation\b/.test(html)) throw new Error(`Invalid Simulation HTML page: ${simulation}`);
  const typeFile = path.join(root, 'type-search-index.js');
  const memberFile = path.join(root, 'member-search-index.js');
  const types = await exists(typeFile) ? await readSearchIndex(typeFile) : null;
  const members = await exists(memberFile) ? await readSearchIndex(memberFile) : null;
  if (types && members) return { format: 'indexed', types, members };
  const hasEntry = (await Promise.all(['index.html', 'overview-summary.html'].map(n => exists(path.join(root, n))))).some(Boolean);
  if (!hasEntry || !await exists(path.join(root, 'star/common/Region.html'))) {
    throw new Error('Incomplete Javadoc: require both search indexes, or legacy index.html/overview-summary.html plus star/common/Region.html.');
  }
  return { format: 'html-fallback', types, members };
}
