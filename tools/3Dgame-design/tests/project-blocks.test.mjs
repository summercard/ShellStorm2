import test from 'node:test';
import assert from 'node:assert/strict';
import { parseProjectBlocks, readProjectBlocks, blockDesignRelativePath } from '../project-blocks.mjs';

test('parses project block rows from the design contract', () => {
  const blocks = parseProjectBlocks(`## 3. 四区块分布\n\n| block_id | 节点 | 中文显示 | 当前楼层 | 内容边界 |\n|---|---|---|---|---|\n| \`demo\` | \`Blocks/Demo\` | 演示区 | 1F | 测试 |\n\n## 4. next`);
  assert.deepEqual(blocks, [{ id: 'demo', nodePath: 'Blocks/Demo', name: '演示区', floorRange: '1F', description: '测试' }]);
});

test('loads the live project block catalog', async () => {
  const catalog = await readProjectBlocks();
  assert.equal(catalog.source, blockDesignRelativePath);
  assert.deepEqual(catalog.blocks.map(block => block.id), ['rooftop', 'base', 'battle', 'stairs']);
  assert.equal(catalog.blocks.find(block => block.id === 'battle').name, '局内关卡01-顶部数据库');
});
