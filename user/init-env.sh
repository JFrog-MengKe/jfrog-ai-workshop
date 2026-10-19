#!/usr/bin/env bash
# Learner-side local-cache-first install/check. macOS, Linux and WSL; native Windows dispatch.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) exec powershell.exe -NoProfile -File "$(cygpath -w "$TASK_ROOT/scripts/init-env.ps1")" "$@";; esac
bash "$TASK_ROOT/scripts/bootstrap-node.sh"
export PATH="${WORKSHOP_HOME:-$HOME/.jfrog-workshop}/bin:$PATH"
exec node "$TASK_ROOT/scripts/environment.cjs" "$@"
