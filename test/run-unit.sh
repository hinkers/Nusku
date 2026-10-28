#!/usr/bin/env bash
# Build the test image, run shellcheck, then bats. Usage: test/run-unit.sh [filter]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

case "$(uname -s)" in
    MINGW* | MSYS* | CYGWIN*)
        export MSYS_NO_PATHCONV=1
        mount_dir="$(pwd -W)"
        ;;
    *) mount_dir="$root" ;;
esac

docker build -q -t nusku-test -f test/Dockerfile test >/dev/null

if [ $# -gt 0 ]; then
    target="test/unit/$1.bats"
else
    target="test/unit"
fi

docker run --rm -v "$mount_dir:/nusku" -w /nusku nusku-test bash -c '
set -euo pipefail
files=()
for f in install.sh lib/*.sh scripts/*; do
    [ -f "$f" ] && files+=("$f")
done
if [ "${#files[@]}" -gt 0 ]; then
    shellcheck -x "${files[@]}"
fi
bats "$1"
' _ "$target"
