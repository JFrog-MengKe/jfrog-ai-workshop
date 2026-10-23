
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

if [ -z "${JFROG_ACCESS_TOKEN:-}" ]; then
  printf '%s\n' '找不到 JFROG_ACCESS_TOKEN；請確認 Codespaces Secret 已授權此 Repository，然後重建 Codespace。'
else
  printf '%s' "$JFROG_ACCESS_TOKEN" | jf config add workshop \
    --url https://alexwangtrial.jfrog.io \
    --access-token-stdin --interactive=false --overwrite &&
    jf config use workshop &&
    jf rt ping --server-id workshop
fi
