#!/usr/bin/env bash
set -euo pipefail

node <<'NODE'
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

let platformUrl = String(process.env.JFROG_URL || '');
while (platformUrl.endsWith('/')) platformUrl = platformUrl.slice(0, -1);
let parsedUrl;
try { parsedUrl = new URL(platformUrl); } catch { parsedUrl = null; }
if (!parsedUrl || parsedUrl.protocol !== 'https:' || parsedUrl.username || parsedUrl.password || parsedUrl.pathname !== '/' || parsedUrl.search || parsedUrl.hash) {
  console.error('[JFrog] JFROG_URL 无效，无法生成工作区 MCP 配置。');
  process.exit(1);
}

const roots = [
  path.join(os.homedir(), '.copilot', 'installed-plugins'),
  path.join(os.homedir(), '.vscode', 'agent-plugins'),
  path.join(os.homedir(), '.config', 'Code', 'agentPlugins'),
  path.join(os.homedir(), 'Library', 'Application Support', 'Code', 'agentPlugins')
];
const mcpFile = /(?:^|[.])mcp[.]json$/i;
let removed = 0;

function visit(directory) {
  if (!fs.existsSync(directory)) return;
  let entries;
  try { entries = fs.readdirSync(directory, {withFileTypes: true}); } catch { return; }
  for (const entry of entries) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) { visit(file); continue; }
    if (!mcpFile.test(entry.name)) continue;
    let content;
    try { content = fs.readFileSync(file, 'utf8'); } catch { continue; }
    if (!content.includes('"jfrog"')) continue;
    fs.unlinkSync(file);
    removed += 1;
  }
}

for (const root of roots) visit(root);
const workspaceMcp = path.join(process.cwd(), '.vscode', 'mcp.json');
fs.mkdirSync(path.dirname(workspaceMcp), {recursive: true});
fs.writeFileSync(workspaceMcp, JSON.stringify({
  inputs: [],
  servers: {jfrog: {type: 'http', url: `${platformUrl}/mcp`}}
}, null, 2) + '\n');
console.log(`[JFrog] 工作区 MCP 已就绪；清理插件副本 ${removed} 个。`);
NODE
