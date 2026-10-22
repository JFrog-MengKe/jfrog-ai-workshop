#!/usr/bin/env bash
# Run as your normal macOS user: bash uninstall-local-tools.sh
# Removes OpenCode / JFrog CLI / jfcm and their dedicated local configuration.
set -euo pipefail

TASK_MANAGER="$(cd "$(dirname "$0")" && pwd)"
TASK_PROJECT="$(dirname "$TASK_MANAGER")"

if [[ "${1:-}" == '--help' || "${1:-}" == '-h' ]]; then
  echo 'Usage: bash uninstall-local-tools.sh'
  echo 'Close OpenCode and the workshop launcher first. Removes tools, credentials, caches and sessions.'
  echo 'Deletes all of ~/.jfrog-workshop, including environment settings and lab files.'
  echo 'Keeps workshop documents, account Excel files and provisioning records.'
  exit 0
fi
if [[ $# -ne 0 ]]; then
  echo 'Unknown argument. Use --help.' >&2
  exit 1
fi
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This script targets the inspected macOS installations.' >&2
  exit 1
fi
if [[ "$EUID" -eq 0 ]]; then
  echo 'Run as your normal user, without sudo before bash. The script requests sudo only for system binaries.' >&2
  exit 1
fi
command -v python3 >/dev/null 2>&1 || { echo 'Python 3 is required.' >&2; exit 1; }

# Obtain OS permission before making changes if root-owned binaries remain.
TASK_SYSTEM_FILES=()
for TASK_FILE in /usr/local/bin/jf /usr/local/bin/jfrog /usr/local/bin/jfcm /usr/local/bin/opencode; do
  if [[ -e "$TASK_FILE" || -L "$TASK_FILE" ]]; then
    TASK_SYSTEM_FILES+=("$TASK_FILE")
  fi
done
if [[ ${#TASK_SYSTEM_FILES[@]} -gt 0 ]]; then
  echo 'Removing system binaries requires your macOS administrator password.'
  sudo -v
fi

if command -v brew >/dev/null 2>&1; then
  for TASK_FORMULA in opencode jfrog-cli; do
    if HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 \
      brew list --formula --versions "$TASK_FORMULA" >/dev/null 2>&1; then
      HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_AUTOREMOVE=1 \
        brew uninstall --formula "$TASK_FORMULA"
    fi
  done
fi
if [[ ${#TASK_SYSTEM_FILES[@]} -gt 0 ]]; then
  sudo /bin/rm -f "${TASK_SYSTEM_FILES[@]}"
fi

python3 - "$TASK_PROJECT" <<'PY'
from pathlib import Path
import re
import shutil
import sys

home = Path.home()
project = Path(sys.argv[1])
# Reset the complete workshop runtime, including tools, identity and lab data.
paths = [home / '.jfrog-workshop']
paths += [home / '.local/bin' / name
          for name in ('opencode', 'jf', 'jfrog', 'jfcm')]
paths += [
    home / '.jfrog', home / '.jfcm', home / '.opencode',
    home / '.config/opencode', home / '.cache/opencode',
    home / '.local/share/opencode', home / '.local/state/opencode',
    home / 'Library/Logs/Homebrew/opencode',
    project / 'user/.opencode', project / 'user/opencode.json',
    project / 'user/opencode.jsonc',
]
cache = home / 'Library/Caches/Homebrew'
paths.extend(cache.glob('opencode--*'))
paths.extend((cache / 'downloads').glob('*--opencode-*'))

for path in paths:
    if path.is_symlink() or path.is_file():
        path.unlink()
        print('Removed:', path)
    elif path.is_dir():
        shutil.rmtree(path)
        print('Removed:', path)

setting = re.compile(
    r'^\s*#?\s*(?:export\s+)?'
    r'(?:JFROG_\w+|JF_PROJECT|WORKSHOP_\w+|OPENCODE_\w+|jfcm_\w+)\s*='
)
alias = re.compile(r'^\s*alias\s+(?:opencode|jf|jfrog|jfcm)=')
for name in ['.zshrc', '.zprofile', '.bashrc', '.bash_profile', '.profile']:
    path = home / name
    if not path.exists():
        continue
    original = path.read_text()
    lines = original.splitlines(keepends=True)
    cleaned = ''.join(
        line for line in lines
        if not setting.match(line) and not alias.match(line) and 'jfcm' not in line
        and '.jfrog-workshop' not in line
        and line.strip() != '# JFrog workshop tools'
    )
    if cleaned != original:
        path.write_text(cleaned)
        print('Cleaned shell settings:', path)
PY

hash -r 2>/dev/null || true
printf '\nRemoved the complete ~/.jfrog-workshop runtime, environment settings and lab files.\n'
printf '\nCleanup completed. Close the old terminal and open a new one.\n'
printf 'Workshop documents, account Excel files and provisioning records are retained.\n'
printf '\nExecutable paths still present, if any:\n'
TASK_REMAINING=0
for TASK_TOOL in opencode jf jfrog jfcm; do
  if TASK_FOUND="$(command -v "$TASK_TOOL")"; then
    printf 'STILL PRESENT: %s\n' "$TASK_FOUND"
    TASK_REMAINING=1
  fi
done
if [[ "$TASK_REMAINING" -ne 0 ]]; then
  echo 'Uninstall incomplete: another installation remains at the path above.' >&2
  exit 1
fi
echo 'Verified: opencode, jf, jfrog and jfcm are no longer on this script PATH.'
