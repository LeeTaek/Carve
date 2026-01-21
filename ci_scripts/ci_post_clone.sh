#!/bin/sh
set -eu

# Always run from repository root (script is located under ci_scripts/ in Xcode Cloud)
script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$script_dir/.."

echo "[post-clone] start: $(date '+%Y-%m-%d %H:%M:%S')"
echo "[post-clone] cwd: $(pwd)"

# Keep-alive to prevent Xcode Cloud 'No activity detected in 15 minutes' timeout
(
  while true; do
    echo "[post-clone] keepalive: $(date '+%Y-%m-%d %H:%M:%S')"
    sleep 60
  done
) &
keepalive_pid=$!
trap 'kill "$keepalive_pid" 2>/dev/null || true' EXIT

echo "❗️Install mise"
# Network hiccups (DNS/TLS) can happen on CI; retry and fail fast
curl -fsSL --retry 3 --retry-delay 5 --connect-timeout 20 --max-time 300 https://mise.run | sh

export PATH="$HOME/.local/bin:$PATH"
echo "❗️Current PATH: $PATH"

echo "❗️mise version"
mise --version

echo "❗️mise install (.mise.toml)"
export MISE_VERBOSE=1
mise install

# Make mise shims available without relying on the current shell (Xcode Cloud may run scripts with zsh if not executable)
export PATH="$HOME/.local/share/mise/shims:$PATH"
echo "❗️PATH with mise shims: $PATH"

echo "❗️mise doctor"
mise doctor

echo "❗️tuist install"
tuist install

echo "❗️tuist generate"
# tuist generate can be quiet for a long time; keepalive above prevents CI timeout
tuist generate

echo "[post-clone] done: $(date '+%Y-%m-%d %H:%M:%S')"
