#!/usr/bin/env node
/**
 * uniorg parser 精度验证脚本模板
 *
 * 用法：
 *   1. npm install unified uniorg-parse uniorg-rehype uniorg-extract-keywords \
 *        rehype-highlight rehype-slug rehype-autolink-headings rehype-stringify
 *   2. 准备一个覆盖你想测试的 Org 语法的 .org 文件
 *   3. node verify-uniorg-parser.mjs <your-test-file.org>
 *   4. 检查 output/ 目录下的 HTML 和终端的检查报告
 *
 * 这个脚本会：
 *   - 用 unified 管线（uniorg → rehype → stringify）把 .org 渲染成 HTML
 *   - 提取 AST 摘要（节点类型统计、链接类型、Keywords、Property Drawer）
 *   - 运行一组语义保留检查（加粗/斜体/链接/代码高亮/表格/脚注/等）
 *   - 输出结构化报告
 *
 * 如果某项检查失败，先用 Emacs ox-html 交叉验证——如果 Emacs 行为一致，
 * 说明是 Org 语法本身的边界规则（如 emphasis 的 pre/post 字符集），不是 parser bug。
 */

import { unified } from 'unified';
import parse from 'uniorg-parse';
import uniorg2rehype from 'uniorg-rehype';
import extractKeywords from 'uniorg-extract-keywords';
import rehypeHighlight from 'rehype-highlight';
import rehypeSlug from 'rehype-slug';
import rehypeAutolinkHeadings from 'rehype-autolink-headings';
import rehypeStringify from 'rehype-stringify';
import { readFileSync, writeFileSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const inputFile = process.argv[2] || join(__dirname, 'test-post.org');
const outputDir = join(__dirname, 'output');

mkdirSync(outputDir, { recursive: true });

// ── 管线 ──
const htmlProcessor = unified()
  .use(parse)
  .use(extractKeywords)
  .use(uniorg2rehype)
  .use(rehypeHighlight)
  .use(rehypeSlug)
  .use(rehypeAutolinkHeadings)
  .use(rehypeStringify);

const astProcessor = unified().use(parse);

// ── 运行 ──
const orgContent = readFileSync(inputFile, 'utf-8');

console.log('━━━ uniorg parser 精度验证 ━━━\n');
console.log(`输入: ${inputFile}`);
console.log(`大小: ${orgContent.length} bytes\n`);

// 1. 解析 AST
const ast = astProcessor.parse(orgContent);

// 2. 提取 AST 摘要
const summary = summarizeAST(ast);
console.log('▸ AST 摘要:');
for (const [key, value] of Object.entries(summary)) {
  if (key.includes('详情')) continue; // 详情在检查中展开
  console.log(`  ${key}: ${value}`);
}

// 3. 生成 HTML
const htmlResult = await htmlProcessor.process(orgContent);
const html = String(htmlResult);
const htmlPath = join(outputDir, 'output.html');
writeFileSync(htmlPath, html);
console.log(`\n✓ HTML: ${htmlPath} (${html.length} bytes)`);

// 4. 语义保留检查
console.log('\n━━━ 语义保留检查 ━━━\n');
const checks = runChecks(html, ast, summary);
let passed = 0, failed = 0;
for (const c of checks) {
  console.log(`  ${c.ok ? '✓' : '✗'} ${c.name}: ${c.detail}`);
  c.ok ? passed++ : failed++;
}
console.log(`\n━━━ ${passed} passed, ${failed} failed ━━━`);

// ── 辅助函数 ──

function summarizeAST(node) {
  const counts = {};
  const properties = [];
  const linkTypes = {};
  const keywords = {};

  function walk(n) {
    if (!n || typeof n !== 'object') return;
    if (n.type) counts[n.type] = (counts[n.type] || 0) + 1;
    if (n.type === 'link') {
      const lt = n.linkType || 'unknown';
      linkTypes[lt] = (linkTypes[lt] || 0) + 1;
    }
    if (n.type === 'keyword' && n.key) keywords[n.key] = n.value;
    if (n.type === 'node-property') properties.push({ key: n.key, value: n.value });
    for (const v of Object.values(n)) {
      if (Array.isArray(v)) v.forEach(walk);
      else if (v && typeof v === 'object') walk(v);
    }
  }
  walk(node);

  return {
    '节点类型统计': Object.entries(counts).map(([k, v]) => `${k}(${v})`).join(', '),
    '链接类型': Object.entries(linkTypes).map(([k, v]) => `${k}(${v})`).join(', ') || '无',
    'Keywords': Object.keys(keywords).join(', ') || '无',
    'Property 数量': properties.length,
    'Keywords 详情': keywords,
    'Property 详情': properties,
  };
}

function runChecks(html, ast, summary) {
  return [
    chk('加粗 <strong>', html.includes('<strong>'), count(html, '<strong>') + ' 个'),
    chk('斜体 <em>', html.includes('<em>'), count(html, '<em>') + ' 个'),
    chk('链接 [[url][desc]]', html.includes('href='), count(html, 'href=') + ' 个'),
    chk('代码高亮 hljs', html.includes('hljs'), count(html, 'hljs') + ' 处'),
    chk('表格 <table>', html.includes('<table'), count(html, '<table') + ' 个'),
    chk('无序列表 <ul>', html.includes('<ul'), count(html, '<ul') + ' 个'),
    chk('有序列表 <ol>', html.includes('<ol'), count(html, '<ol') + ' 个'),
    chk('引用块 <blockquote>', html.includes('<blockquote'), '存在'),
    chk('脚注', html.includes('footnote'), count(html, /footnote|fn\.|<sup/gi) + ' 处'),
    chk('分隔线 <hr>', html.includes('<hr'), '存在'),
    chk('COMMENT 块排除', !html.includes('不应该出现在导出结果中'), '正确排除'),
    chk('Property CUSTOM_ID', summary['Property 详情'].some(p => p.key === 'CUSTOM_ID'),
       summary['Property 详情'].find(p => p.key === 'CUSTOM_ID')?.value || '未找到'),
    chk('Property ID', summary['Property 详情'].some(p => p.key === 'ID'),
       summary['Property 详情'].find(p => p.key === 'ID')?.value || '未找到'),
    chk('TITLE keyword', !!summary['Keywords 详情'].TITLE, summary['Keywords 详情'].TITLE || '未找到'),
    chk('FILETAGS keyword', !!summary['Keywords 详情'].FILETAGS, summary['Keywords 详情'].FILETAGS || '未找到'),
  ];
}

function chk(name, ok, detail) { return { name, ok, detail }; }
function count(str, pattern) {
  return (str.match(new RegExp(pattern, 'gi')) || []).length;
}
