# ArtCraft installer, with stub curl, pacman and sudo on PATH.

setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR"
    unset NUSKU_LOG NUSKU_STEP NUSKU_NONINTERACTIVE
    export NUSKU_ROOT="$PWD"
    export BIN="$BATS_TEST_TMPDIR/bin" SRV="$BATS_TEST_TMPDIR/srv"
    export CALLS="$BATS_TEST_TMPDIR/calls" INSTALLED="$BATS_TEST_TMPDIR/installed"
    mkdir -p "$BIN" "$SRV"
    : >"$CALLS"
    : >"$INSTALLED"
    export NUSKU_ARTCRAFT_BASE="http://stub"
    # curl -fsSL --retry 2 -o OUT URL: copy $SRV/<url path>; fail when it is absent.
    cat >"$BIN/curl" <<'STUB'
#!/usr/bin/env bash
out="" url=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift ;;
        --retry) shift ;;
        -*) ;;
        *) url="$1" ;;
    esac
    shift
done
echo "curl $url" >>"$CALLS"
src="$SRV/${url#http://stub/}"
[ -f "$src" ] || { echo "curl: (22) The requested URL returned error: 404" >&2; exit 22; }
cp "$src" "$out"
STUB
    # pacman -Q / -Qq NAME: installed when listed in $INSTALLED; -U is recorded.
    cat >"$BIN/pacman" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    -Q | -Qq) grep -qxF "$2" "$INSTALLED" ;;
    *) echo "pacman $*" >>"$CALLS" ;;
esac
STUB
    cat >"$BIN/sudo" <<'STUB'
#!/usr/bin/env bash
exec "$@"
STUB
    chmod +x "$BIN"/*
    export PATH="$BIN:$PATH"
}

# release REPO [GOODSUM]: a fixture release with aarch64, x86_64 Arch and AppImage files.
release() {
    local repo="$1" d="$SRV/$1/releases/latest/download" f="$1-0.17.0-linux-x86_64.pkg.tar.zst" sum
    mkdir -p "$d"
    echo "payload $repo" >"$d/$f"
    echo "other" >"$d/$repo-0.17.0-linux-aarch64.pkg.tar.zst"
    sum="${2:-$(sha256sum "$d/$f" | cut -d' ' -f1)}"
    {
        echo "1111111111111111111111111111111111111111111111111111111111111111  $repo-0.17.0-linux-aarch64.pkg.tar.zst"
        echo "$sum  $f"
        echo "2222222222222222222222222222222222222222222222222222222222222222  $repo-0.17.0-linux-x86_64.AppImage"
    } >"$d/SHA256SUMS.txt"
}

in_art() {
    bash -c 'source lib/log.sh; source lib/answers.sh; source lib/apps.sh; source lib/artcraft.sh; '"$1"
}

@test "fetch picks the x86_64 Arch package from SHA256SUMS and verifies it" {
    release photocraft
    run in_art 'artcraft_fetch photocraft "$BATS_TEST_TMPDIR"'
    [ "$status" -eq 0 ]
    [[ "$output" == *photocraft-0.17.0-linux-x86_64.pkg.tar.zst ]]
    [ -f "$output" ]
}

@test "fetch fails on a checksum mismatch" {
    release photocraft 0000000000000000000000000000000000000000000000000000000000000000
    run in_art 'artcraft_fetch photocraft "$BATS_TEST_TMPDIR" 2>&1'
    [ "$status" -ne 0 ]
    [[ "$output" == *"checksum mismatch"* ]]
    ! grep -q 'pacman -U' "$CALLS" || false
}

@test "fetch fails when the release has no x86_64 Arch package" {
    release photocraft
    echo "1111111111111111111111111111111111111111111111111111111111111111  photocraft-0.17.0-linux-aarch64.pkg.tar.zst" \
        >"$SRV/photocraft/releases/latest/download/SHA256SUMS.txt"
    run in_art 'artcraft_fetch photocraft "$BATS_TEST_TMPDIR" 2>&1'
    [ "$status" -ne 0 ]
    [[ "$output" == *"no x86_64 Arch package in the latest release"* ]]
}

@test "install_soft records a failure and continues" {
    release craft-launcher
    release pdfcraft
    run in_art 'artcraft_install_soft "artcraft launcher craft-launcher
artcraft photocraft photocraft
artcraft pdfcraft pdfcraft"
printf "%s\n" "${NUSKU_APP_FAILURES[@]}"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PhotoCraft: download failed"* ]]
    grep -q 'pacman -U --noconfirm --needed .*pdfcraft-0.17.0-linux-x86_64.pkg.tar.zst' "$CALLS"
    ! grep -q 'photocraft.*pkg.tar.zst' <(grep 'pacman -U' "$CALLS") || false
}

@test "install_soft skips an installed release package" {
    echo ai.storyteller.photocraft >"$INSTALLED"
    run in_art 'artcraft_install_soft "artcraft photocraft photocraft"'
    [ "$status" -eq 0 ]
    ! grep -q 'curl .*photocraft' "$CALLS" || false
}

@test "install_soft skips an AUR copy with a note" {
    echo photocraft-bin >"$INSTALLED"
    run in_art 'artcraft_install_soft "artcraft photocraft photocraft"; printf "%s\n" "${NUSKU_APP_NOTES[@]}"'
    [ "$status" -eq 0 ]
    ! grep -q curl "$CALLS" || false
    [[ "$output" == *"PhotoCraft is installed from the AUR (photocraft-bin); the ArtCraft Launcher won't update it."* ]]
}

@test "launcher failure adds a note and still installs apps" {
    release pdfcraft
    run in_art 'artcraft_install_soft "artcraft launcher craft-launcher
artcraft pdfcraft pdfcraft"
printf "%s\n" "${NUSKU_APP_NOTES[@]}" "${NUSKU_APP_FAILURES[@]}"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"The ArtCraft Launcher was not installed, so ArtCraft apps won't update until it is."* ]]
    [[ "$output" == *"ArtCraft Launcher: download failed"* ]]
    grep -q 'pacman -U .*pdfcraft' "$CALLS"
}

@test "a fresh launcher install is flagged" {
    release craft-launcher
    run in_art 'artcraft_install_soft "artcraft launcher craft-launcher"; echo "new=$NUSKU_ARTCRAFT_LAUNCHER_NEW"'
    [[ "$output" == *"new=1"* ]]
}

@test "a failed download records exactly 'download failed', not curl's message" {
    run in_art 'artcraft_install_soft "artcraft photocraft photocraft"; printf "%s\n" "${NUSKU_APP_FAILURES[@]}"'
    [ "$status" -eq 0 ]
    [ "$output" = "PhotoCraft: download failed" ]
}

@test "fetch reports download failed when the package itself 404s" {
    release photocraft
    rm "$SRV/photocraft/releases/latest/download/photocraft-0.17.0-linux-x86_64.pkg.tar.zst"
    run in_art 'artcraft_fetch photocraft "$BATS_TEST_TMPDIR" 2>&1'
    [ "$status" -ne 0 ]
    [ "$output" = "download failed" ]
}

@test "fetch rejects a SHA256SUMS filename containing a slash" {
    release photocraft
    echo "1111111111111111111111111111111111111111111111111111111111111111  ../evil-linux-x86_64.pkg.tar.zst" \
        >"$SRV/photocraft/releases/latest/download/SHA256SUMS.txt"
    run in_art 'artcraft_fetch photocraft "$BATS_TEST_TMPDIR" 2>&1'
    [ "$status" -ne 0 ]
    [[ "$output" == *"no x86_64 Arch package"* ]]
    ! grep -q 'evil' "$CALLS" || false
}

ENTRY_REL=autostart/ai.storyteller.artcraft-launcher.desktop

@test "writes the autostart entry on first launcher install" {
    release craft-launcher
    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/cfg"
    run in_art 'artcraft_install_soft "artcraft launcher craft-launcher"'
    [ "$status" -eq 0 ]
    [ "$(cat "$XDG_CONFIG_HOME/$ENTRY_REL")" = "[Desktop Entry]
Type=Application
Name=ArtCraft Launcher
Comment=Install and update the Craft App Suite
Exec=/usr/bin/artcraft-launcher --hidden
Icon=ai.storyteller.artcraft-launcher
Terminal=false
X-GNOME-Autostart-enabled=true" ]
}

@test "does not recreate a deleted entry when the launcher was already installed" {
    echo ai.storyteller.artcraft-launcher >"$INSTALLED"
    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/cfg"
    run in_art 'artcraft_install_soft "artcraft launcher craft-launcher"'
    [ "$status" -eq 0 ]
    [ ! -e "$XDG_CONFIG_HOME/$ENTRY_REL" ]
}

@test "does not overwrite an existing autostart entry" {
    release craft-launcher
    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/cfg"
    mkdir -p "$XDG_CONFIG_HOME/autostart"
    echo "mine" >"$XDG_CONFIG_HOME/$ENTRY_REL"
    run in_art 'artcraft_install_soft "artcraft launcher craft-launcher"'
    [ "$status" -eq 0 ]
    [ "$(cat "$XDG_CONFIG_HOME/$ENTRY_REL")" = "mine" ]
}

@test "autostart.lua runs the launcher's Exec line when the entry exists" {
    mkdir -p "$BATS_TEST_TMPDIR/home/.config/autostart"
    printf '[Desktop Entry]\nName=x\nExec=/usr/bin/artcraft-launcher --hidden\nIcon=y\n' \
        >"$BATS_TEST_TMPDIR/home/.config/$ENTRY_REL"
    HOME="$BATS_TEST_TMPDIR/home" run nvim --headless -l test/fixtures/hypr-stub.lua config/hypr/autostart.lua
    [ "$status" -eq 0 ]
    [ "$(grep -c artcraft <<<"$output")" -eq 1 ]
    grep -qxF '/usr/bin/artcraft-launcher --hidden' <<<"$output"
}

@test "autostart.lua starts nothing extra without the entry" {
    mkdir -p "$BATS_TEST_TMPDIR/home"
    HOME="$BATS_TEST_TMPDIR/home" run nvim --headless -l test/fixtures/hypr-stub.lua config/hypr/autostart.lua
    [ "$status" -eq 0 ]
    ! grep -q artcraft <<<"$output" || false
    grep -qxF 'waybar' <<<"$output"
}
