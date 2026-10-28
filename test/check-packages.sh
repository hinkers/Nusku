#!/usr/bin/env bash
# Check that every package in packages/apps.list (plus the Task 3 GPU lib32 names) exists:
# repo names in core/extra/multilib, aur: names via the AUR RPC, flatpak: ids on Flathub.
# Usage: test/check-packages.sh   (needs Docker and network)
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

docker run --rm -v "$mount_dir:/nusku" -w /nusku nusku-test bash -c '
set -uo pipefail
export NUSKU_ROOT=/nusku
source lib/log.sh
source lib/answers.sh
source lib/apps.sh

# The throwaway container may enable multilib and sync (the installer itself never uses -Sy).
if grep -q "^#\[multilib\]" /etc/pacman.conf; then
    sudo sed -i "/^#\[multilib\]/,/^#Include/ s/^#//" /etc/pacman.conf
elif ! grep -q "^\[multilib\]" /etc/pacman.conf; then
    printf "\\n[multilib]\\nInclude = /etc/pacman.d/mirrorlist\\n" | sudo tee -a /etc/pacman.conf >/dev/null
fi
sudo pacman -Sy --noconfirm >/dev/null

repo=() aur=() flat=()
add() {
    case "$1" in
        aur:*) aur+=("${1#aur:}") ;;
        flatpak:*) flat+=("${1#flatpak:}") ;;
        *) repo+=("$1") ;;
    esac
}
ids="$(awk -F"|" "\$1==\"app\"{print \$3} \$1==\"lang\"{print \$2}" "$NUSKU_APPS_LIST")"
for id in $ids; do
    for t in $(apps_packages "$id"); do add "$t"; done
done
# GPU 32-bit drivers (Stage 2 Task 3).
repo+=(lib32-mesa lib32-vulkan-radeon lib32-vulkan-intel lib32-vulkan-swrast lib32-nvidia-utils)
aur+=(lib32-nvidia-580xx-utils)

fail=0

echo "=== repo: ${#repo[@]} names ==="
available="$(pacman -Sl core extra multilib | awk "{print \$2}")"
# Also accept provides (virtual names).
for p in $(printf "%s\n" "${repo[@]}" | sort -u); do
    if ! grep -qxF "$p" <<<"$available" && ! pacman -Sp "$p" >/dev/null 2>&1; then
        echo "MISSING repo package: $p"
        fail=1
    fi
done

echo "=== aur: ${#aur[@]} names ==="
if [ "${#aur[@]}" -gt 0 ]; then
    q=""
    for p in "${aur[@]}"; do q+="&arg[]=$p"; done
    json="$(curl -fsS "https://aur.archlinux.org/rpc/v5/info?${q#&}")" || { echo "AUR RPC failed"; exit 1; }
    found="$(jq -r ".results[].Name" <<<"$json")"
    for p in $(printf "%s\n" "${aur[@]}" | sort -u); do
        if ! grep -qxF "$p" <<<"$found"; then
            echo "MISSING AUR package: $p"
            fail=1
        fi
    done
    jq -r ".results[] | select(.OutOfDate != null) | \"WARN: AUR \(.Name) is flagged out of date\"" <<<"$json"
fi

echo "=== flatpak: ${#flat[@]} ids ==="
for f in "${flat[@]}"; do
    code="$(curl -s -o /dev/null -w "%{http_code}" "https://flathub.org/api/v2/appstream/$f")"
    if [ "$code" != 200 ]; then
        echo "MISSING Flathub app: $f (HTTP $code)"
        fail=1
    fi
done

if [ "$fail" -eq 0 ]; then
    echo "ALL PACKAGES FOUND"
else
    echo "SOME PACKAGES MISSING"
fi
exit "$fail"
'
