#!/usr/bin/env bash
# Try the installer's settings menu and app list without installing or saving anything.
#   test/tui-demo.sh          the settings menu (as on a fresh install)
#   test/tui-demo.sh apps     just the app list (as ./install.sh --apps)
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export NUSKU_ROOT="$root" XDG_STATE_HOME
XDG_STATE_HOME="$(mktemp -d)"
trap 'rm -rf "$XDG_STATE_HOME"' EXIT
for f in log answers gpu apps tui questions; do
    # shellcheck source=/dev/null
    source "$root/lib/$f.sh"
done
NUSKU_LOG="$XDG_STATE_HOME/demo.log"
if [ "${1:-}" = apps ]; then
    apps_ask >/dev/null 2>&1
else
    questions_menu "$(gpu_suggest)"
fi
echo "You picked (nothing was installed or saved):"
for k in GPU NVIDIA_MODULE AUR_HELPER ACCENT APPS LANGS; do
    [ -n "${NUSKU_ANSWERS[$k]+x}" ] && printf '  %-14s %s\n' "$k" "${NUSKU_ANSWERS[$k]}"
done
