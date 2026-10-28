
#!/usr/bin/env bash
set -euo pipefail

echo "[JFrog] Checking prerequisites..."

# JFROG_URL is the only platform Secret. Keep the legacy host-only value
# available to tools that still expect JFROG_PLATFORM_URL, without requiring a
# second Secret.
if [ -n "${JFROG_URL:-}" ]; then
  JFROG_PLATFORM_URL="${JFROG_URL#https://}"
  export JFROG_PLATFORM_URL
fi

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
