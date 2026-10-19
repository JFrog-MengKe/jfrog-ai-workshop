#!/usr/bin/env bash
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
bash "$TASK_ROOT/start-workshop.sh"
TASK_STATUS=$?
if [ "$TASK_STATUS" -ne 0 ]; then echo '启动失败。请保留错误信息并联系讲师。'; read -r -p '按 Enter 关闭' _; fi
exit "$TASK_STATUS"
