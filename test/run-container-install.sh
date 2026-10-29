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
run2_log="$(ls -t "$state"/install-*.log | head -n1)"

echo "=== update run (saved answers) ==="
# Simulate an older install: all of ~/.config/btop linked into the repo.
rm -rf "$HOME/.config/btop" && ln -s /nusku/config/btop "$HOME/.config/btop"
# Simulate a moved repo: the saved wallpaper path no longer exists.
printf "*=/nonexistent/old-repo/wallpapers/space.png\n" >"$state/wallpapers"
# Simulate a Stage 1 (hyprlang) install: generated .conf files and a local.conf with overrides.
cfg="$HOME/.config/nusku"
printf "env = OLD,1\n" >"$cfg/gpu.conf"
printf "\$accent = rgb(000000)\n" >"$cfg/theme/hypr-colors.conf"
printf "env = XCURSOR_THEME,old\n" >"$cfg/theme/hypr-cursor.conf"
printf "# mine\nmonitor = DP-1, 2560x1440@144, 0x0, 1\n" >"$cfg/local.conf"
./install.sh --update --no-reboot 2>&1 | tee /tmp/update.log
if [ "${PIPESTATUS[0]}" -eq 0 ]; then
    pass "install.sh --update exited 0"
else
    bad "install.sh --update exited non-zero"
fi
if [ ! -e "$cfg/gpu.conf" ] && [ ! -e "$cfg/theme/hypr-colors.conf" ] && [ ! -e "$cfg/theme/hypr-cursor.conf" ]; then
    pass "--update removed the old generated hyprlang files"
else
    bad "old generated hyprlang files left: $(ls "$cfg" "$cfg/theme")"
fi
if grep -q "DP-1" "$cfg/local.conf" && [ "$(grep -c "local.conf is no longer read" /tmp/update.log)" -eq 1 ]; then
    pass "--update kept local.conf and warned once to move it to local.lua"
else
    bad "local.conf migration: $(grep -c "local.conf is no longer read" /tmp/update.log) warnings, file: $(cat "$cfg/local.conf" 2>&1)"
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

if [ -d "$HOME/.config/btop" ] && [ ! -L "$HOME/.config/btop" ] &&
    [ "$(readlink "$HOME/.config/btop/themes")" = /nusku/config/btop/themes ] &&
    [ -f "$HOME/.config/btop/btop.conf" ] && [ ! -L "$HOME/.config/btop/btop.conf" ]; then
    pass "btop: real dir, themes linked, btop.conf copied"
else
    bad "btop layout wrong: $(ls -la "$HOME/.config/btop" 2>&1)"
fi
if [ -f /nusku/config/btop/themes/catppuccin_mocha.theme ] && [ -f /nusku/config/btop/btop.conf ]; then
    pass "repo btop files intact after migrating the old link"
else
    bad "repo btop files damaged"
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

for f in "$HOME/.config/nusku/local.lua" "$HOME/.config/nusku/gpu.lua" "$HOME/.config/nusku/theme/hypr-colors.lua" "$HOME/.config/nusku/theme/hypr-cursor.lua"     "$HOME/.config/nusku/answers" "$state/wallpapers" /var/lib/nusku/sddm-background/background; do
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
if [ ! -e "$HOME/.config/hypr/hyprland.conf" ] && [ -f "$HOME/.config/hypr/hyprland.lua" ]; then
    pass "~/.config/hypr has hyprland.lua and no hyprland.conf"
else
    bad "~/.config/hypr: $(ls "$HOME/.config/hypr")"
fi
# No -c: Hyprland picks the config itself, so this also proves it chooses the Lua one.
out="$(Hyprland --verify-config 2>&1)"
rc=$?
printf "%s\n" "$out" | grep -v DEBUG
# Older Hyprland prints "Using lua config found at <path>"; Hyprland 0.57 prints "Regular config
# at <path>" instead. Either way the path must still be hyprland.lua, never hyprland.conf.
if [ "$rc" -eq 0 ] && printf "%s\n" "$out" | grep -q "^config ok" &&
    printf "%s\n" "$out" | grep -Eq "(Using lua config found|Regular config) at $HOME/.config/hypr/hyprland.lua"; then
    pass "Hyprland --verify-config: Lua config ok"
else
    printf "%s\n" "$out" | tail -n 30
    bad "Hyprland --verify-config (exit $rc)"
fi
if printf "%s\n" "$out" | grep -Eqi "legacy config|deprecat|will be removed|0\.57"; then
    bad "Hyprland reports the legacy/deprecated config format"
else
    pass "no legacy-config or deprecation message"
fi

if pacman -Q neovim github-cli lazygit yazi zathura docker go lua; then
    pass "app and language packages installed"
else
    bad "pacman -Q of the picked apps failed"
fi
case "$(readlink "$HOME/.config/nvim")" in
    /nusku/*) pass "~/.config/nvim links into /nusku" ;;
    *) bad "~/.config/nvim links to $(readlink "$HOME/.config/nvim" 2>&1)" ;;
esac
if [ "$(grep -v "^--" "$HOME/.config/nusku/nvim-languages.lua")" = "return { \"go\", \"lua\" }" ]; then
    pass "nvim-languages.lua lists go and lua"
else
    bad "nvim-languages.lua: $(cat "$HOME/.config/nusku/nvim-languages.lua" 2>&1)"
fi
for f in "$HOME/.local/share/nvim/site/parser/go.so" "$HOME/.local/share/nvim/mason/bin/gopls"; do
    if [ -e "$f" ]; then pass "$f exists"; else bad "$f missing"; fi
done
if [ "$(systemctl is-enabled docker.service 2>&1)" = enabled ]; then
    pass "docker.service enabled"
else
    bad "docker.service: $(systemctl is-enabled docker.service 2>&1)"
fi
# getent, not id -nG: this shell predates the usermod.
if getent group docker | cut -d: -f4 | tr "," "
" | grep -qx "$(id -un)"; then
    pass "user is in the docker group"
else
    bad "docker group: $(getent group docker)"
fi
if pacman -Q ai.storyteller.artcraft-launcher ai.storyteller.photocraft; then
    pass "ArtCraft launcher and PhotoCraft release packages installed"
else
    bad "pacman -Q of the ArtCraft release packages failed"
fi
if grep -qx "Exec=/usr/bin/artcraft-launcher --hidden" "$HOME/.config/autostart/ai.storyteller.artcraft-launcher.desktop" 2>/dev/null; then
    pass "ArtCraft Launcher autostart entry written"
else
    bad "ArtCraft Launcher autostart entry missing or wrong"
fi
if grep -q "releases/latest/download" "$run2_log"; then
    bad "second run downloaded ArtCraft again: $(grep "releases/latest/download" "$run2_log")"
elif grep -q "PhotoCraft is already installed" "$run2_log"; then
    pass "second run skipped the installed ArtCraft packages"
else
    bad "second run log has neither an ArtCraft download nor a skip: $run2_log"
fi
if [ -x "$HOME/.local/bin/nusku-menu-keybinds" ]; then
    pass "~/.local/bin/nusku-menu-keybinds exists"
else
    bad "~/.local/bin/nusku-menu-keybinds missing"
fi
# --verify-config above loaded keybinds.lua, which writes the keybind menu manifest.
if grep -q "	Screenshot a region	" "$XDG_RUNTIME_DIR/nusku/keybinds.tsv" 2>/dev/null; then
    pass "keybind manifest lists Screenshot a region"
else
    bad "keybind manifest: $(head -n3 "$XDG_RUNTIME_DIR/nusku/keybinds.tsv" 2>&1)"
fi

if grep -q "Not installed" /tmp/update.log "$state"/install-*.log; then
    bad "an optional app failed: $(grep -h -A8 "Not installed" /tmp/update.log | head -n 12)"
else
    pass "no optional app failures"
fi

if [ "$fail" -eq 0 ]; then
    echo "ALL CONTAINER INSTALL ASSERTIONS PASSED"
else
    echo "CONTAINER INSTALL ASSERTIONS FAILED"
fi
exit "$fail"
'
