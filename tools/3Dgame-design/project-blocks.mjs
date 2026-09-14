import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const toolRoot = path.dirname(fileURLToPath(import.meta.url));
export const projectRoot = path.resolve(toolRoot, '../..');
export const blockDesignRelativePath = 'docs/v0.1/05.1_关卡区块设计.md';
export const blockDesignPath = path.join(projectRoot, blockDesignRelativePath);

export function parseProjectBlocks(markdown) {
  const section = markdown.match(/## 3\. 四区块分布([\s\S]*?)(?=\n## )/)?.[1] || '';
  return section.split('\n').flatMap(line => {
    const cells = line.split('|').slice(1, -1).map(cell => cell.trim().replace(/^`|`$/g, ''));
    if (cells.length < 5 || !/^[a-z][a-z0-9_-]*$/.test(cells[0]) || !cells[1].startsWith('Blocks/')) return [];
    return [{ id: cells[0], nodePath: cells[1], name: cells[2], floorRange: cells[3], description: cells[4] }];
  });
}

export async function readProjectBlocks() {
  const markdown = await fs.readFile(blockDesignPath, 'utf8');
  const blocks = parseProjectBlocks(markdown);
  if (!blocks.length) throw new Error(`未能从 ${blockDesignRelativePath} 读取区块表`);
  return { source: blockDesignRelativePath, blocks };
}

export async function requireProjectBlock(blockId) {
  const catalog = await readProjectBlocks();
  const block = catalog.blocks.find(item => item.id === blockId);
  if (!block) throw new Error(`未知区块：${blockId}`);
  return block;
}
