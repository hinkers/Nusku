#!/usr/bin/env bash
# Full install in a fresh nusku-test container (twice), then assertions.
# Usage: test/run-container-install.sh   (needs Docker and network; downloads several hundred MB)
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

# --rm: every run starts from the unmodified image.
docker run --rm -v "$mount_dir:/nusku" -w /nusku \
    -e NUSKU_NONINTERACTIVE=1 \
    --shm-size=512m \
    nusku-test bash -c '
set -uo pipefail
fail=0
pass() { printf "PASS: %s\n" "$*"; }
bad() { printf "FAIL: %s\n" "$*"; fail=1; }
state="$HOME/.local/state/nusku"
backups() { find "$state" -maxdepth 1 -type d -name "backup-*" 2>/dev/null | sort; }

echo "=== install run 1 ==="
if ./install.sh --answers test/answers/container.answers --no-reboot; then
    pass "first install exited 0"
else
    bad "first install exited non-zero"
    exit 1
fi
before="$(backups)"
sleep 1   # make sure a second run would get a different backup timestamp

echo "=== install run 2 ==="
if ./install.sh --answers test/answers/container.answers --no-reboot; then
    pass "second install exited 0"
else
    bad "second install exited non-zero"
fi
after="$(backups)"

echo "=== update run (saved answers) ==="
# Simulate a moved repo: the saved wallpaper path no longer exists.
printf "*=/nonexistent/old-repo/wallpapers/space.png\n" >"$state/wallpapers"
if ./install.sh --update --no-reboot; then
    pass "install.sh --update exited 0"
else
    bad "install.sh --update exited non-zero"
fi
[ "$(backups)" = "$before" ] || bad "--update run created a backup dir"
if grep -qx "\*=/nusku/wallpapers/space.png" "$state/wallpapers" && [ -f "$(readlink "$state/current-wallpaper")" ]; then
    pass "--update replaced a dangling saved wallpaper with the default"
else
    bad "--update kept a dangling wallpaper: $(cat "$state/wallpapers")"
fi

echo "=== assertions ==="
if [ -L "$HOME/.config/hypr" ]; then
    case "$(readlink "$HOME/.config/hypr")" in
        /nusku/*) pass "~/.config/hypr links into /nusku" ;;
        *) bad "~/.config/hypr links to $(readlink "$HOME/.config/hypr")" ;;
    esac
else
    bad "~/.config/hypr is not a symlink"
fi

if grep -q 89b4fa "$HOME/.config/nusku/theme/colors.css" 2>/dev/null; then
    pass "colors.css contains 89b4fa"
else
    bad "colors.css missing or lacks 89b4fa"
fi

if [ "$before" = "$after" ]; then
    pass "second run created no backup dir"
else
    bad "second run created a backup dir: $(comm -13 <(printf "%s\n" "$before") <(printf "%s\n" "$after"))"
fi

if pacman -Q hyprland waybar sddm; then
    pass "hyprland waybar sddm installed"
else
    bad "pacman -Q hyprland waybar sddm failed"
fi

for f in "$HOME/.config/nusku/local.conf" "$HOME/.config/nusku/gpu.conf"     "$HOME/.config/nusku/answers" "$state/wallpapers" /var/lib/nusku/sddm-background/background; do
    if [ -e "$f" ]; then pass "$f exists"; else bad "$f missing"; fi
done

if [ "$(getent passwd "$(id -un)" | cut -d: -f7)" = /usr/bin/zsh ]; then
    pass "login shell is zsh"
else
    bad "login shell is not zsh"
fi

# Hyprland refuses to start (even for --help) without XDG_RUNTIME_DIR.
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-runtime-$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
if Hyprland --help 2>&1 | grep -q -- --verify-config; then
    out="$(Hyprland --verify-config -c "$HOME/.config/hypr/hyprland.conf" 2>&1)"
    if printf "%s\n" "$out" | grep -qi "config ok"; then
        pass "Hyprland --verify-config"
    else
        printf "%s\n" "$out" | tail -n 30
        bad "Hyprland --verify-config"
    fi
else
    echo "SKIP: Hyprland --verify-config not supported"
fi

if [ "$fail" -eq 0 ]; then
    echo "ALL CONTAINER INSTALL ASSERTIONS PASSED"
else
    echo "CONTAINER INSTALL ASSERTIONS FAILED"
fi
exit "$fail"
'
