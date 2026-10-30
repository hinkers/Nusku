#!/usr/bin/env bash
# Nusku installer: turns a fresh Arch base install into a Catppuccin Mocha Hyprland desktop.
# Run as your normal user (not root). See usage() or ./install.sh --help.
set -Eeuo pipefail

REPO_ROOT="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
NUSKU_ROOT="$REPO_ROOT"
export NUSKU_ROOT

# shellcheck source=lib/log.sh
source "$REPO_ROOT/lib/log.sh"
# shellcheck source=lib/answers.sh
source "$REPO_ROOT/lib/answers.sh"
# shellcheck source=lib/apps.sh
source "$REPO_ROOT/lib/apps.sh"
# shellcheck source=lib/artcraft.sh
source "$REPO_ROOT/lib/artcraft.sh"
# shellcheck source=lib/ui.sh
source "$REPO_ROOT/lib/ui.sh"
# shellcheck source=lib/backup.sh
source "$REPO_ROOT/lib/backup.sh"
# shellcheck source=lib/preflight.sh
source "$REPO_ROOT/lib/preflight.sh"
# shellcheck source=lib/packages.sh
source "$REPO_ROOT/lib/packages.sh"
# shellcheck source=lib/grub.sh
source "$REPO_ROOT/lib/grub.sh"
# shellcheck source=lib/gpu.sh
source "$REPO_ROOT/lib/gpu.sh"
# shellcheck source=lib/swaync.sh
source "$REPO_ROOT/lib/swaync.sh"
# shellcheck source=lib/tui.sh
source "$REPO_ROOT/lib/tui.sh"
# shellcheck source=lib/questions.sh
source "$REPO_ROOT/lib/questions.sh"
# shellcheck source=lib/launcher.sh
source "$REPO_ROOT/lib/launcher.sh"
# shellcheck source=lib/theme.sh
source "$REPO_ROOT/lib/theme.sh"
# shellcheck source=lib/dotfiles.sh
source "$REPO_ROOT/lib/dotfiles.sh"
# shellcheck source=lib/system.sh
source "$REPO_ROOT/lib/system.sh"
# shellcheck source=lib/hypr.sh
source "$REPO_ROOT/lib/hypr.sh"

SAVED_ANSWERS="${XDG_CONFIG_HOME:-$HOME/.config}/nusku/answers"
NUSKU_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nusku"
NUSKU_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/nusku"

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

Turns a fresh Arch Linux base install into the Nusku Hyprland desktop.
Run it as your normal user; it asks for sudo when needed. Safe to re-run.

Options:
  --answers FILE   Read the answers from FILE and run without questions.
  --update         Reuse your saved answers, skip the questions and re-apply
                   every step (what nusku-update runs after pulling).
  --apps           Change which optional apps and languages are installed, then re-apply.
  --reconfigure    Open the settings menu again (starts from your saved answers).
  --no-reboot      Do not offer to reboot at the end.
  -h, --help       Show this help.
EOF
}

opt_answers=""
opt_update=0
opt_apps=0
opt_reconfigure=0
opt_no_reboot=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --answers)
            [ "$#" -ge 2 ] && [ -n "$2" ] || {
                printf 'install.sh: --answers needs a file\n' >&2
                exit 2
            }
            opt_answers="$2"
            shift 2
            ;;
        --answers=*)
            opt_answers="${1#--answers=}"
            shift
            ;;
        --update) opt_update=1 && shift ;;
        --apps) opt_apps=1 && shift ;;
        --reconfigure) opt_reconfigure=1 && shift ;;
        --no-reboot) opt_no_reboot=1 && shift ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            printf 'install.sh: unknown option: %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [ "$opt_reconfigure" -eq 1 ] && { [ "$opt_update" -eq 1 ] || [ -n "$opt_answers" ]; }; then
    printf 'install.sh: --reconfigure cannot be combined with --update or --answers\n' >&2
    exit 2
fi
if [ "$opt_apps" -eq 1 ] && { [ "$opt_update" -eq 1 ] || [ -n "$opt_answers" ] || [ "$opt_reconfigure" -eq 1 ]; }; then
    printf 'install.sh: --apps cannot be combined with --update, --answers or --reconfigure\n' >&2
    exit 2
fi
if [ -n "$opt_answers" ]; then
    opt_answers="$(realpath "$opt_answers")"
    NUSKU_NONINTERACTIVE=1
fi
if [ "$opt_update" -eq 1 ]; then
    NUSKU_NONINTERACTIVE=1
fi
export NUSKU_NONINTERACTIVE="${NUSKU_NONINTERACTIVE:-0}"

# One log and one backup dir for the whole run, shared by every step and subshell.
log_init
NUSKU_RUN_ID="${NUSKU_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
export NUSKU_RUN_ID

trap 'die "command failed (exit $?): $BASH_COMMAND"' ERR

# Keep the sudo timestamp fresh during long builds; stops when the installer exits.
SUDO_KEEPALIVE_PID=""
sudo_keepalive() {
    (
        trap - ERR
        while kill -0 "$$" 2>/dev/null; do
            sudo -n true 2>/dev/null || true
            sleep 50
        done
    ) </dev/null >/dev/null 2>&1 &
    SUDO_KEEPALIVE_PID=$!
}
# shellcheck disable=SC2329,SC2317  # invoked by the EXIT trap
cleanup() {
    if [ -n "$SUDO_KEEPALIVE_PID" ]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# ask_menu KEY PROMPT DEFAULT_VALUE VALUE LABEL [VALUE LABEL]...: menu of plain-words labels;
# stores the VALUE belonging to the chosen label (a stored answer is kept as is).
ask_menu() {
    local key="$1" prompt="$2" def="$3" deflabel="" chosen i
    local -a values=() labels=()
    shift 3
    while [ "$#" -ge 2 ]; do
        values+=("$1")
        labels+=("$2")
        [ "$1" = "$def" ] && deflabel="$2"
        shift 2
    done
    ui_choose "$key" "$prompt" "$deflabel" "${labels[@]}" >/dev/null
    chosen="$(answers_get "$key")"
    for i in "${!labels[@]}"; do
        if [ "${labels[$i]}" = "$chosen" ]; then
            answers_set "$key" "${values[$i]}"
            return 0
        fi
    done
}

step_questions() {
    step "Questions"
    if [ -n "$opt_answers" ]; then
        answers_load "$opt_answers"
    elif [ -r "$SAVED_ANSWERS" ]; then
        answers_load "$SAVED_ANSWERS"
    fi

    local suggested
    suggested="$(gpu_suggest)"
    # Interactive: one menu with every setting (prefilled from saved answers on --reconfigure).
    # --apps goes straight to the app list below. The ask_menu calls then only check answers.
    if [ "$NUSKU_NONINTERACTIVE" != "1" ] && [ "$opt_apps" -eq 0 ] &&
        { [ "$opt_reconfigure" -eq 1 ] || questions_needed; }; then
        questions_menu "$suggested"
    fi
    ask_menu GPU "Which graphics do you have?" "$suggested" "${Q_GPU[@]}"
    if q_needs_nvidia; then
        ask_menu NVIDIA_MODULE "Which NVIDIA driver?" open "${Q_NVIDIA[@]}"
    fi
    ask_menu AUR_HELPER "Which AUR helper?" paru "${Q_AUR[@]}"
    local -a accent_menu=()
    local a
    for a in "${NUSKU_ACCENTS[@]}"; do
        accent_menu+=("$a" "$a")
    done
    ask_menu ACCENT "Accent colour (Catppuccin Mocha)?" blue "${accent_menu[@]}"

    if [ "$NUSKU_NONINTERACTIVE" = "1" ]; then
        apps_default_missing
    elif [ "$opt_apps" -eq 1 ] || [ -z "${NUSKU_ANSWERS[APPS]+x}" ]; then
        apps_ask
    fi

    answers_validate
    answers_save "$SAVED_ANSWERS"
    log_info "Answers: GPU=$(answers_get GPU) NVIDIA_MODULE=$(answers_get NVIDIA_MODULE) AUR_HELPER=$(answers_get AUR_HELPER) ACCENT=$(answers_get ACCENT)"
    log_info "Saved answers to $SAVED_ANSWERS"
}

# check_answers_early: with --answers or --update, load and validate the answers before
# anything touches the system, so a typo fails fast instead of after a full upgrade.
check_answers_early() {
    if [ -n "$opt_answers" ]; then
        step "Checking answers"
        answers_load "$opt_answers"
        answers_validate
    elif [ "$opt_update" -eq 1 ]; then
        step "Checking answers"
        [ -r "$SAVED_ANSWERS" ] || die "--update needs saved answers ($SAVED_ANSWERS); run ./install.sh first"
        answers_load "$SAVED_ANSWERS"
        answers_validate
    elif [ "$opt_apps" -eq 1 ]; then
        step "Checking answers"
        [ -r "$SAVED_ANSWERS" ] || die "--apps needs saved answers ($SAVED_ANSWERS); run ./install.sh first"
        answers_load "$SAVED_ANSWERS"
        answers_validate
    fi
}

step_aur_helper() {
    step "AUR helper"
    aur_bootstrap "$(answers_get AUR_HELPER)"
}

# _read_lists FILE...: package names from the lists (dies on an unreadable list).
_read_lists() {
    [ "$#" -gt 0 ] || return 0
    pkg_read_list "$@"
}

step_packages() {
    step "Packages"
    local lists l text
    local -a repo_lists=("$REPO_ROOT/packages/base.pacman") aur_lists=("$REPO_ROOT/packages/base.aur")
    local -a repo_names=() aur_names=()
    lists="$(gpu_package_lists "$(answers_get GPU)" "$(answers_get NVIDIA_MODULE)" "$(gpu_virt)")"
    while IFS= read -r l; do
        case "$l" in
            '') ;;
            *.aur) aur_lists+=("$l") ;;
            *) repo_lists+=("$l") ;;
        esac
    done <<<"$lists"
    text="$(_read_lists "${repo_lists[@]}")"
    [ -z "$text" ] || mapfile -t repo_names <<<"$text"
    text="$(gpu_kernel_headers "$(answers_get GPU)")"
    [ -z "$text" ] || mapfile -t -O "${#repo_names[@]}" repo_names <<<"$text"
    text="$(_read_lists "${aur_lists[@]}")"
    [ -z "$text" ] || mapfile -t aur_names <<<"$text"
    local gpu mod batches
    gpu="$(answers_get GPU)"
    mod="$(answers_get NVIDIA_MODULE)"
    batches="$(apps_batches "$gpu" "$mod")"
    text="$(awk '$1 == "repo" && !seen[$2]++ { print $2 }' <<<"$batches")"
    [ -z "$text" ] || mapfile -t -O "${#repo_names[@]}" repo_names <<<"$text"
    if apps_needs_multilib; then
        pkg_enable_multilib
    fi
    pkg_install_repo_swap_rust "${repo_names[@]}"
    pkg_install_aur "${aur_names[@]}"
    apps_install_aur_soft "$batches"
    apps_install_flatpak_soft "$batches"
    artcraft_install_soft "$batches"
}

step_gpu() {
    step "GPU configuration"
    gpu_configure
}

step_theme() {
    step "Theme"
    theme_render_all "$REPO_ROOT"
}

step_dotfiles() {
    step "Dotfiles"
    # Older installs linked all of ~/.config/btop (btop then rewrote btop.conf inside the repo)
    # and all of ~/.config/swaync (its config.json is now written per machine). Drop those
    # directory links so only the files listed in links.txt are linked.
    # Any checkout counts (the repo may have moved): linking files through it would edit that checkout.
    local name dir
    for name in btop swaync; do
        dir="$HOME/.config/$name"
        if [ -L "$dir" ]; then
            case "$(readlink "$dir")" in
                */config/"$name")
                    rm -f "$dir"
                    log_info "Removed old Nusku link $dir"
                    ;;
            esac
        fi
    done
    deploy_dotfiles "$REPO_ROOT"
}

step_local_files() {
    step "Local files"
    mkdir -p "$NUSKU_CONFIG_DIR"
    hypr_write_local_lua "$NUSKU_CONFIG_DIR/local.lua"
    hypr_migrate_legacy "$NUSKU_CONFIG_DIR"
    # btop rewrites its config on exit, so it is a copy (made once), not a link.
    local btop_conf="$HOME/.config/btop/btop.conf"
    if [ ! -e "$btop_conf" ] && [ ! -L "$btop_conf" ]; then
        mkdir -p "$(dirname "$btop_conf")"
        cp "$REPO_ROOT/config/btop/btop.conf" "$btop_conf"
        log_info "Created $btop_conf"
    fi
    # Rewritten every run (like gpu.lua): the brightness slider and power modes depend on the machine.
    swaync_write_config "$REPO_ROOT/config/swaync/config.template.json" "$HOME/.config/swaync/config.json" &&
        { ! pgrep -x swaync >/dev/null 2>&1 || swaync-client -R >/dev/null 2>&1 || true; }
    if [ ! -e "$NUSKU_CONFIG_DIR/gpu.lua" ]; then
        gpu_hypr_lua "$(answers_get GPU)" "$(gpu_virt)" >"$NUSKU_CONFIG_DIR/gpu.lua"
    fi
    sddm_prepare_background_dir
    local wp_state="$NUSKU_STATE_DIR/wallpapers" saved=""
    if [ -s "$wp_state" ]; then
        saved="$(sed -n 's/^\*=//p' "$wp_state" | head -n1)"
    fi
    if [ ! -s "$wp_state" ]; then
        run "$HOME/.local/bin/nusku-wallpaper" set "$REPO_ROOT/wallpapers/space.png" all
    elif [ -n "$saved" ] && [ ! -f "$saved" ]; then
        # Saved paths are absolute: moving the repo leaves them dangling.
        log_warn "Saved wallpaper $saved no longer exists; using the default"
        run "$HOME/.local/bin/nusku-wallpaper" set "$REPO_ROOT/wallpapers/space.png" all
    else
        log_info "Wallpaper already chosen; keeping it"
    fi
}

step_system() {
    system_configure
}

step_apps_setup() {
    step "Apps setup"
    apps_run_hooks
    launcher_apply "$REPO_ROOT/config/applications/overrides.list"
}

step_summary() {
    step "Summary"
    local gpu mod bdir
    gpu="$(answers_get GPU)"
    mod="$(answers_get NVIDIA_MODULE)"
    case "$gpu" in nvidia | hybrid-*) gpu="$gpu ($mod driver)" ;; esac
    bdir="$NUSKU_STATE_DIR/backup-$NUSKU_RUN_ID"
    {
        printf '\nNusku is installed.\n'
        printf '  GPU:     %s\n' "$gpu"
        printf '  Accent:  %s\n' "$(answers_get ACCENT)"
        printf '  Apps:    %s apps, %s languages\n' "$(wc -w <<<"$(answers_get APPS)")" "$(wc -w <<<"$(answers_get LANGS)")"
        printf '  Log:     %s\n' "$NUSKU_LOG"
        if [ -d "$bdir" ]; then
            printf '  Backups: %s\n' "$bdir"
        fi
        apps_summary_failures
        apps_summary_notes
        printf '\nNext step: Reboot to log in.\n'
    } | tee -a "$NUSKU_LOG" >&2
}

step_reboot() {
    if [ "$opt_no_reboot" -eq 1 ] || [ "$NUSKU_NONINTERACTIVE" = "1" ]; then
        return 0
    fi
    if ui_confirm "Reboot now?"; then
        run sudo systemctl reboot
    fi
}

main() {
    check_answers_early
    preflight_checks
    preflight_bootstrap
    sudo_keepalive
    step_questions
    step_aur_helper
    step_packages
    step_gpu
    step_theme
    step_dotfiles
    step_local_files
    step_system
    step_apps_setup
    step_summary
    step_reboot
}

main
