#!/usr/bin/env bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) echo 'Native Windows: double-click start-workshop.cmd'; exit 1;; esac
bash "$TASK_ROOT/scripts/bootstrap-node.sh"
export PATH="${WORKSHOP_HOME:-$HOME/.jfrog-workshop}/bin:$PATH"
exec node "$TASK_ROOT/scripts/workshop-server.cjs" "$@"
