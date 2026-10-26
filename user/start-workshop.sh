#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) echo 'Native Windows: double-click start-workshop.cmd'; exit 1;; esac
bash "$TASK_ROOT/scripts/bootstrap-node.sh"
export PATH="${WORKSHOP_HOME:-$HOME/.jfrog-workshop}/bin:$PATH"
if [ "${CODESPACES:-}" = "true" ] && [ -n "${JF_PROJECT:-}" ]; then
  node - "$JF_PROJECT" <<'NODE'
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const project = process.argv[2];
if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(project)) {
  console.error('JF_PROJECT 格式无效，跳过 agents-conf.json 配置。');
  process.exit(0);
}

const directory = path.join(os.homedir(), '.jfrog');
const file = path.join(directory, 'agents-conf.json');
let config = {};
try {
  if (fs.existsSync(file)) config = JSON.parse(fs.readFileSync(file, 'utf8'));
} catch (error) {
  console.error(`无法读取 ${file}，跳过自动配置：${error.message}`);
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
console.log(`已根据 JF_PROJECT=${project} 配置 ${file}`);
NODE
fi
exec node "$TASK_ROOT/scripts/workshop-server.cjs" "$@"
