#!/usr/bin/env bash
# GPU driver selection and configuration. Sourced, not executed.
# Needs lib/log.sh, lib/answers.sh, lib/packages.sh, lib/grub.sh and lib/backup.sh.

NUSKU_ROOT="${NUSKU_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

NUSKU_NVIDIA_PARAMS=(nvidia_drm.modeset=1 nvidia_drm.fbdev=1)
NUSKU_NVIDIA_MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)

# gpu_virt: hypervisor name from systemd-detect-virt --vm ("none" on bare metal or if unavailable).
gpu_virt() {
    local v
    v="$(systemd-detect-virt --vm 2>/dev/null || true)"
    printf '%s\n' "${v:-none}"
}

# gpu_suggest: a default for the menu only; falls back to "amd" and never fails.
gpu_suggest() {
    local pci nv=0 amd=0 intel=0
    if [ "$(gpu_virt)" != "none" ]; then
        echo vm
        return 0
    fi
    pci="$(lspci 2>/dev/null | grep -Ei 'vga|3d|display' || true)"
    case "$pci" in *[Nn][Vv][Ii][Dd][Ii][Aa]*) nv=1 ;; esac
    case "$pci" in *AMD* | *ATI* | *Radeon*) amd=1 ;; esac
    case "$pci" in *[Ii]ntel*) intel=1 ;; esac
    if [ "$nv" -eq 1 ] && [ "$intel" -eq 1 ]; then
        echo hybrid-intel
    elif [ "$nv" -eq 1 ] && [ "$amd" -eq 1 ]; then
        echo hybrid-amd
    elif [ "$nv" -eq 1 ]; then
        echo nvidia
    elif [ "$intel" -eq 1 ]; then
        echo intel
    else
        echo amd
    fi
    return 0
}

# gpu_vm_services VIRT: guest services to enable (enabled later by the services task).
gpu_vm_services() {
    case "${1:-}" in
        microsoft) echo "hv_kvp_daemon hv_vss_daemon" ;;
        vmware) echo "vmtoolsd" ;;
        kvm | qemu) echo "qemu-guest-agent" ;;
    esac
    return 0
}

# gpu_package_lists GPU NVIDIA_MODULE VIRT: list file paths, one per line.
gpu_package_lists() {
    local gpu="${1:-}" mod="${2:-proprietary}" virt="${3:-none}"
    local dir="$NUSKU_ROOT/packages" nvl=()
    if [ "$mod" = "open" ]; then
        nvl=("$dir/gpu-nvidia-open.pacman")
    else
        nvl=("$dir/gpu-nvidia.pacman" "$dir/gpu-nvidia.aur")
    fi
    case "$gpu" in
        amd) echo "$dir/gpu-amd.pacman" ;;
        intel) echo "$dir/gpu-intel.pacman" ;;
        nvidia) printf '%s\n' "${nvl[@]}" ;;
        hybrid-intel) printf '%s\n' "$dir/gpu-intel.pacman" "${nvl[@]}" "$dir/gpu-hybrid.pacman" ;;
        hybrid-amd) printf '%s\n' "$dir/gpu-amd.pacman" "${nvl[@]}" "$dir/gpu-hybrid.pacman" ;;
        vm)
            case "$virt" in
                microsoft) echo "$dir/gpu-vm-hyperv.pacman" ;;
                vmware) echo "$dir/gpu-vm-vmware.pacman" ;;
                kvm | qemu) echo "$dir/gpu-vm-qemu.pacman" ;;
                *) echo "$dir/gpu-vm-generic.pacman" ;;
            esac
            ;;
        *) die "Unknown GPU choice: '$gpu'" ;;
    esac
}

# gpu_kernel_headers GPU: <kernel>-headers for each installed kernel (DKMS needs them),
# only for NVIDIA choices; prints nothing otherwise.
gpu_kernel_headers() {
    local k
    case "${1:-}" in
        nvidia | hybrid-*) ;;
        *) return 0 ;;
    esac
    for k in linux linux-lts linux-zen linux-hardened; do
        if pacman -Qq "$k" >/dev/null 2>&1; then
            printf '%s-headers
' "$k"
        fi
    done
    return 0
}

# gpu_hypr_conf GPU VIRT: contents of ~/.config/nusku/gpu.conf.
gpu_hypr_conf() {
    local gpu="${1:-}" virt="${2:-none}"
    echo "# Nusku GPU settings (generated; sourced by Hyprland)"
    case "$gpu" in
        nvidia)
            echo "env = LIBVA_DRIVER_NAME,nvidia"
            echo "env = __GLX_VENDOR_LIBRARY_NAME,nvidia"
            echo "env = NVD_BACKEND,direct"
            ;;
        hybrid-*)
            echo "# Hybrid: Hyprland runs on the integrated GPU; use prime-run for apps."
            ;;
        vm)
            echo "cursor {"
            echo "    no_hardware_cursors = true"
            echo "}"
            if [ "$virt" = "microsoft" ]; then
                echo "env = LIBGL_ALWAYS_SOFTWARE,1"
                echo "env = WLR_RENDERER_ALLOW_SOFTWARE,1"
            fi
            ;;
        *)
            echo "# Nothing to override for this GPU."
            ;;
    esac
}

# _gpu_edit_etc FILE KEY_RE FUNC ARGS...: apply a pure edit function to a temp copy, check the
# result is non-empty and still has a line matching KEY_RE, then sudo-install it.
# Returns 0 if changed, 1 if unchanged, 2 if FILE is missing; dies on a broken edit.
_gpu_edit_etc() {
    local file="$1" key="$2" func="$3" tmp rc=0
    shift 3
    [ -r "$file" ] || return 2
    tmp="$(mktemp)"
    cp "$file" "$tmp"
    "$func" "$tmp" "$@" || rc=$?
    if [ "$rc" -eq 0 ]; then
        if [ ! -s "$tmp" ] || ! grep -q "$key" "$tmp"; then
            rm -f "$tmp"
            die "Editing $file went wrong (result empty or missing $key); left it unchanged"
        fi
        backup_file "$file"
        # Subshell: run's die exits, and the temp file must still be removed.
        if ! (run sudo install -m 644 "$tmp" "$file"); then
            rm -f "$tmp"
            exit 1
        fi
    fi
    rm -f "$tmp"
    return "$rc"
}

# _gpu_mkinit_edit FILE: add the NVIDIA modules and drop the kms hook (keeps nouveau out
# of the initramfs). 0 if either changed, 1 if nothing did, 2 if FILE is unreadable.
_gpu_mkinit_edit() {
    local rc_mod=0 rc_hook=0
    mkinit_add_modules "$1" "${NUSKU_NVIDIA_MODULES[@]}" || rc_mod=$?
    [ "$rc_mod" -ne 2 ] || return 2
    mkinit_remove_hook "$1" kms || rc_hook=$?
    [ "$rc_hook" -ne 2 ] || return 2
    if [ "$rc_mod" -eq 0 ] || [ "$rc_hook" -eq 0 ]; then
        return 0
    fi
    return 1
}

# gpu_configure: install drivers, edit boot config, write gpu.conf, using the answers.
gpu_configure() {
    local gpu mod virt lists=() n rc
    gpu="$(answers_get GPU)"
    mod="$(answers_get NVIDIA_MODULE)"
    virt="$(gpu_virt)"
    [ -n "$gpu" ] || die "GPU is not set"

    while IFS= read -r n; do lists+=("$n"); done < <(gpu_package_lists "$gpu" "${mod:-proprietary}" "$virt")
    [ "${#lists[@]}" -gt 0 ] || die "No package lists for GPU '$gpu'"
    local repo_lists=() aur_lists=() repo_names=() aur_names=()
    for n in "${lists[@]}"; do
        case "$n" in
            *.aur) aur_lists+=("$n") ;;
            *) repo_lists+=("$n") ;;
        esac
    done
    if [ "${#repo_lists[@]}" -gt 0 ]; then
        while IFS= read -r n; do repo_names+=("$n"); done < <(pkg_read_list "${repo_lists[@]}")
    fi
    while IFS= read -r n; do repo_names+=("$n"); done < <(gpu_kernel_headers "$gpu")
    if [ "${#aur_lists[@]}" -gt 0 ]; then
        while IFS= read -r n; do aur_names+=("$n"); done < <(pkg_read_list "${aur_lists[@]}")
    fi
    pkg_install_repo "${repo_names[@]}"
    pkg_install_aur "${aur_names[@]}"

    case "$gpu" in
        nvidia | hybrid-*)
            rc=0
            _gpu_edit_etc "${NUSKU_GRUB_DEFAULT:-/etc/default/grub}" '^GRUB_CMDLINE_LINUX_DEFAULT=' grub_add_params "${NUSKU_NVIDIA_PARAMS[@]}" || rc=$?
            case "$rc" in
                0) run sudo grub-mkconfig -o /boot/grub/grub.cfg ;;
                2) log_warn "No GRUB config found; add these kernel parameters manually: ${NUSKU_NVIDIA_PARAMS[*]}" ;;
            esac
            rc=0
            _gpu_edit_etc "${NUSKU_MKINITCPIO_CONF:-/etc/mkinitcpio.conf}" '^MODULES=(' _gpu_mkinit_edit || rc=$?
            case "$rc" in
                0) run sudo mkinitcpio -P ;;
                2) log_warn "No mkinitcpio.conf found; add these modules manually: ${NUSKU_NVIDIA_MODULES[*]} (and remove the kms hook)" ;;
            esac
            ;;
    esac

    local conf="${XDG_CONFIG_HOME:-$HOME/.config}/nusku/gpu.conf"
    mkdir -p "$(dirname "$conf")"
    gpu_hypr_conf "$gpu" "$virt" >"$conf"
    log_info "GPU configured ($gpu); wrote $conf"
}
