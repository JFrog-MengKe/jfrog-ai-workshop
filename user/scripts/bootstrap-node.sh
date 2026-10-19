#!/usr/bin/env bash
# Bootstrap Node for the local UI. Prefer tools; download the official archive if absent.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_BASE="${WORKSHOP_HOME:-$HOME/.jfrog-workshop}"
TASK_BIN="$TASK_BASE/bin"
export PATH="$TASK_BIN:$PATH"
if [[ "${1:-}" != '--force' ]] && command -v node >/dev/null 2>&1 && node -e 'process.exit(+process.versions.node.split(".")[0]>=18?0:1)' >/dev/null 2>&1; then
  printf 'Node runtime available: %s\n' "$(node --version)"
  exit 0
fi
case "$(uname -s)" in Darwin) TASK_OS=darwin;; Linux) TASK_OS=linux;; *) echo 'Use start-workshop.cmd on native Windows.' >&2; exit 1;; esac
case "$(uname -m)" in arm64|aarch64) TASK_ARCH=arm64;; x86_64|amd64) TASK_ARCH=x64;; *) echo 'Unsupported CPU architecture' >&2; exit 1;; esac
TASK_ARCHIVE="$TASK_ROOT/tools/$TASK_OS-$TASK_ARCH/node.tar.gz"
mkdir -p "$(dirname "$TASK_ARCHIVE")"
# No Node dependency: use a downloader already supplied by the OS.
task_download() {
  local task_url="$1" task_dest="$2" task_partial="$2.partial.$$"
  if command -v curl >/dev/null 2>&1; then
    if ! curl --fail --location --silent --show-error --proto '=https' --retry 2 --connect-timeout 15 --max-time 900 "$task_url" -o "$task_partial"; then rm -f "$task_partial"; return 1; fi
  elif command -v wget >/dev/null 2>&1; then
    if ! wget --https-only --timeout=60 --tries=3 -q "$task_url" -O "$task_partial"; then rm -f "$task_partial"; return 1; fi
  elif command -v python3 >/dev/null 2>&1; then
    if ! python3 - "$task_url" "$task_partial" <<'PYDOWNLOAD'
import sys,urllib.request,shutil
with urllib.request.urlopen(sys.argv[1],timeout=60) as response, open(sys.argv[2],'wb') as output:
    shutil.copyfileobj(response,output)
PYDOWNLOAD
    then rm -f "$task_partial"; return 1; fi
  else
    echo 'Node is unavailable and no curl/wget/Python HTTPS downloader was found. Ask the instructor for the Node archive in tools.' >&2
    return 1
  fi
  mv "$task_partial" "$task_dest"
}
task_sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}';
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}';
  else echo 'Need shasum or sha256sum (normally provided by OS).' >&2; return 1; fi
}
TASK_NODE_VERSION='24.22.0'
TASK_SOURCE_FILE="node-v$TASK_NODE_VERSION-$TASK_OS-$TASK_ARCH.tar.gz"
TASK_SOURCE_BASE="https://nodejs.org/download/release/v$TASK_NODE_VERSION"
if [[ -f "$TASK_ARCHIVE" ]]; then
  echo "LOCAL tools/$TASK_OS-$TASK_ARCH/node.tar.gz"
  if [[ -f "$TASK_ARCHIVE.sha256" ]]; then
    TASK_EXPECTED="$(cat "$TASK_ARCHIVE.sha256")"
  elif [[ -f "$TASK_ROOT/tools/checksums.json" ]]; then
    TASK_EXPECTED="$(sed -n 's/.*"'"$TASK_OS-$TASK_ARCH"'\/node.tar.gz"[[:space:]]*:[[:space:]]*"\([a-fA-F0-9]\{64\}\)".*/\1/p' "$TASK_ROOT/tools/checksums.json" | head -1)"
    if [[ -z "$TASK_EXPECTED" ]]; then TASK_EXPECTED="$(task_sha256 "$TASK_ARCHIVE")"; echo 'LOCAL HASH recorded for manually supplied Node archive'; fi
  else
    TASK_EXPECTED="$(task_sha256 "$TASK_ARCHIVE")"
    echo 'LOCAL HASH recorded for manually supplied Node archive'
  fi
else
  echo "DOWNLOAD Node $TASK_NODE_VERSION → tools/$TASK_OS-$TASK_ARCH/node.tar.gz"
  TASK_SUMS="$TASK_ARCHIVE.checksums.$$"
  task_download "$TASK_SOURCE_BASE/SHASUMS256.txt" "$TASK_SUMS"
  TASK_EXPECTED="$(awk -v task_file="$TASK_SOURCE_FILE" '$2==task_file {print $1}' "$TASK_SUMS")"
  rm -f "$TASK_SUMS"
  [[ "$TASK_EXPECTED" =~ ^[a-fA-F0-9]{64}$ ]] || { echo 'Official Node SHA256 was not found' >&2; exit 1; }
  task_download "$TASK_SOURCE_BASE/$TASK_SOURCE_FILE" "$TASK_ARCHIVE.download"
  TASK_ACTUAL="$(task_sha256 "$TASK_ARCHIVE.download")"
  if [[ "$TASK_ACTUAL" != "$TASK_EXPECTED" ]]; then rm -f "$TASK_ARCHIVE.download"; echo 'Downloaded Node SHA256 mismatch' >&2; exit 1; fi
  mv "$TASK_ARCHIVE.download" "$TASK_ARCHIVE"
  echo 'CACHED Node archive (official SHA256 verified)'
fi
TASK_ACTUAL="$(task_sha256 "$TASK_ARCHIVE")"
[[ "$TASK_ACTUAL" == "$TASK_EXPECTED" ]] || { echo 'Local Node SHA256 mismatch; replace the damaged archive before retrying' >&2; exit 1; }
printf '%s\n' "$TASK_EXPECTED" > "$TASK_ARCHIVE.sha256"
mkdir -p "$TASK_BASE" "$TASK_BIN"
TASK_STAGE="$(mktemp -d "$TASK_BASE/node-stage.XXXXXX")"
trap 'rm -rf "$TASK_STAGE"' EXIT
# Instructor-provided official archive; reject absolute/traversing paths.
tar -tzf "$TASK_ARCHIVE" > "$TASK_STAGE/entries"
if awk '/^\// || /(^|\/)\.\.(\/|$)/ {bad=1} END {exit !bad}' "$TASK_STAGE/entries"; then echo 'Unsafe archive path' >&2; exit 1; fi
mkdir "$TASK_STAGE/node"
tar -xzf "$TASK_ARCHIVE" -C "$TASK_STAGE/node" --strip-components=1
"$TASK_STAGE/node/bin/node" -e 'process.exit(+process.versions.node.split(".")[0]>=18?0:1)'
# Keep Node distribution intact: npx/npm need lib/node_modules and their symlinks.
TASK_TARGET="$TASK_BASE/node-$(date +%s)-$$"
mv "$TASK_STAGE/node" "$TASK_TARGET"
for TASK_TOOL in node npm npx; do ln -sfn "$TASK_TARGET/bin/$TASK_TOOL" "$TASK_BIN/$TASK_TOOL"; done
"$TASK_BIN/node" --version
"$TASK_BIN/npx" --version
"$TASK_BIN/node" "$TASK_ROOT/scripts/package-cache.cjs" node
echo 'Node / npx prepared; installation archive retained in tools.'
