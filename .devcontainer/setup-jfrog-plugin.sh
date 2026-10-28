
#!/usr/bin/env bash
set -euo pipefail

echo "[JFrog] Checking prerequisites..."

if ! command -v node >/dev/null 2>&1; then
  echo "ERROR: Node.js is missing."
  exit 1
fi

NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])')"
if [ "$NODE_MAJOR" -lt 22 ]; then
  echo "ERROR: Node.js 22+ is required."
  exit 1
fi

# Install GitHub Copilot CLI if missing
if ! command -v copilot >/dev/null 2>&1; then
  npm install -g @github/copilot
fi

echo "[JFrog] Checking plugin marketplace..."

MARKETPLACES="$(copilot plugin marketplace list 2>/dev/null || true)"

if ! printf '%s\n' "$MARKETPLACES" |
  grep -F 'jfrog-agent-plugins' >/dev/null; then
  copilot plugin marketplace add jfrog/vscode-plugin
fi

# Check whether the official JFrog plugin is installed
plugin_installed() {
  copilot plugin list --json |
    node -e '
      let data = "";
      process.stdin.on("data", c => data += c);
      process.stdin.on("end", () => {
        try {
          const plugins = JSON.parse(data);
          const found = plugins.some(p =>
            p.name === "jfrog" &&
            p.marketplace === "jfrog-agent-plugins"
          );
          process.exit(found ? 0 : 1);
        } catch {
          process.exit(1);
        }
      });
    '
}

plugin_enabled() {
  copilot plugin list --json |
    node -e '
      let data = "";
      process.stdin.on("data", c => data += c);
      process.stdin.on("end", () => {
        try {
          const plugins = JSON.parse(data);
          const found = plugins.some(p =>
            p.name === "jfrog" &&
            p.marketplace === "jfrog-agent-plugins" &&
            p.enabled === true
          );
          process.exit(found ? 0 : 1);
        } catch {
          process.exit(1);
        }
      });
    '
}

if ! plugin_installed; then
  echo "[JFrog] Installing official plugin..."
  copilot plugin install jfrog@jfrog-agent-plugins
fi

if ! plugin_enabled; then
  echo "[JFrog] Enabling plugin..."
  copilot plugin enable jfrog
fi

# The marketplace plugin currently ships its MCP template with a host-only
# variable and prepends https://. Codespaces provides the complete platform
# URL as JFROG_URL, so rewrite the installed JFrog-owned MCP files to use it
# directly. This also covers Copilot's runtime copy of the plugin when it is
# already present.
rewrite_plugin_mcp_configs() {
  node <<'NODE'
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const roots = [
  path.join(os.homedir(), '.copilot', 'installed-plugins'),
  path.join(os.homedir(), '.vscode', 'agent-plugins'),
  path.join(os.homedir(), 'Library', 'Application Support', 'Code', 'agentPlugins'),
  path.join(os.homedir(), '.config', 'Code', 'agentPlugins')
];
const mcpFile = /(?:^|[.])mcp[.]json$/i;
const jfrogUrl = new RegExp('https://' + '\\$' + '\\{env:[^}]*jfrog[^}]*\\}/mcp', 'gi');
let changed = 0;

function visit(directory) {
  if (!fs.existsSync(directory)) return;
  let entries;
  try { entries = fs.readdirSync(directory, {withFileTypes: true}); } catch { return; }
  for (const entry of entries) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      visit(file);
      continue;
    }
    if (!mcpFile.test(entry.name)) continue;
    let content;
    try { content = fs.readFileSync(file, 'utf8'); } catch { continue; }
    const updated = content.replace(jfrogUrl, '${env:JFROG_URL}/mcp');
    if (updated === content) continue;
    fs.writeFileSync(file, updated);
    changed += 1;
    console.log(`[JFrog] 已将 MCP 地址切换为 JFROG_URL：${file}`);
  }
}

for (const root of roots) visit(root);
if (changed === 0) {
  console.log('[JFrog] 未发现需要改写的插件 MCP 模板；插件可能尚未复制到运行时目录。');
}
NODE
}

rewrite_plugin_mcp_configs

echo "[JFrog] Final plugin status:"
copilot plugin list

if [ -z "${JFROG_ACCESS_TOKEN:-}" ]; then
  echo "WARNING: JFROG_ACCESS_TOKEN is not available in this process."
else
  echo "[JFrog] Access token environment variable is present."
fi

echo "[JFrog] Setup completed."

if ! command -v jf >/dev/null 2>&1; then
  curl -fL https://install-cli.jfrog.io | sh
fi
jf --version

if [ -n "${JF_PROJECT:-}" ]; then
  WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  node - "$JF_PROJECT" "$WORKSPACE_ROOT" <<'NODE'
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const project = process.argv[2];
const workspaceRoot = process.argv[3];
if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(project)) {
  console.error('[JFrog] JF_PROJECT 格式无效，跳过 agents-conf.json 配置。');
  process.exit(0);
}

const directory = path.join(os.homedir(), '.jfrog');
const file = path.join(directory, 'agents-conf.json');
let config = {};
try {
  if (fs.existsSync(file)) config = JSON.parse(fs.readFileSync(file, 'utf8'));
} catch (error) {
  console.error(`[JFrog] 无法读取 ${file}，跳过自动配置：${error.message}`);
  process.exit(0);
}

config.packageResolution = {
  ...(config.packageResolution || {}),
  enabled: true,
  defaultGlobalRepos: {
    ...(config.packageResolution?.defaultGlobalRepos || {}),
    npm: `${project}-npm-virtual`,
    pypi: `${project}-pypi-virtual`
  }
};
fs.mkdirSync(directory, {recursive: true, mode: 0o700});
fs.writeFileSync(file, JSON.stringify(config, null, 2) + '\n', {mode: 0o600});
fs.chmodSync(file, 0o600);
console.log(`[JFrog] 已根据 JF_PROJECT=${project} 配置 ${file}`);

const bindingDirectory = path.join(workspaceRoot, '.jfrog', 'local');
const bindingFile = path.join(bindingDirectory, 'package-resolution.json');
let binding = {};
try {
  if (fs.existsSync(bindingFile)) binding = JSON.parse(fs.readFileSync(bindingFile, 'utf8'));
} catch (error) {
  console.error(`[JFrog] 无法读取 ${bindingFile}，跳过工程级绑定：${error.message}`);
  process.exit(0);
}

binding.repositories = {
  ...(binding.repositories || {}),
  npm: `${project}-npm-virtual`,
  pypi: `${project}-pypi-virtual`
};
fs.mkdirSync(bindingDirectory, {recursive: true, mode: 0o700});
fs.writeFileSync(bindingFile, JSON.stringify(binding, null, 2) + '\n', {mode: 0o600});
fs.chmodSync(bindingFile, 0o600);
console.log(`[JFrog] 已配置工程级绑定 ${bindingFile}`);
NODE
else
  echo "[JFrog] JF_PROJECT 未设置，跳过 agents-conf.json 配置。"
fi

if [ -z "${JFROG_ACCESS_TOKEN:-}" ]; then
  printf '%s\n' '找不到 JFROG_ACCESS_TOKEN；請確認 Codespaces Secret 已授權此 Repository，然後重建 Codespace。'
else
  if [ -z "${JFROG_URL:-}" ]; then
    printf '%s\n' '找不到 JFROG_URL；請確認 Codespaces Secret 已授權此 Repository，然後重建 Codespace。'
    exit 1
  fi
  printf '%s' "$JFROG_ACCESS_TOKEN" | jf config add workshop \
    --url "$JFROG_URL" \
    --access-token-stdin --interactive=false --overwrite &&
    jf config use workshop &&
    jf rt ping --server-id workshop
fi
