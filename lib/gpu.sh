#!/usr/bin/env bash
# GPU driver selection and configuration. Sourced, not executed.
# Needs lib/log.sh, lib/answers.sh, lib/packages.sh and lib/grub.sh.

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
    local dir="$NUSKU_ROOT/packages" nv
    if [ "$mod" = "open" ]; then nv="gpu-nvidia-open"; else nv="gpu-nvidia"; fi
    case "$gpu" in
        amd) echo "$dir/gpu-amd.pacman" ;;
        intel) echo "$dir/gpu-intel.pacman" ;;
        nvidia) echo "$dir/$nv.pacman" ;;
        hybrid-intel) printf '%s\n' "$dir/gpu-intel.pacman" "$dir/$nv.pacman" "$dir/gpu-hybrid.pacman" ;;
        hybrid-amd) printf '%s\n' "$dir/gpu-amd.pacman" "$dir/$nv.pacman" "$dir/gpu-hybrid.pacman" ;;
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

# _gpu_edit_etc FILE FUNC ARGS...: apply a pure edit function to a temp copy, then sudo-install it.
# Returns 0 if changed, 1 if unchanged, 2 if FILE is missing.
_gpu_edit_etc() {
    local file="$1" func="$2" tmp rc=0
    shift 2
    [ -r "$file" ] || return 2
    tmp="$(mktemp)"
    cp "$file" "$tmp"
    "$func" "$tmp" "$@" || rc=$?
    if [ "$rc" -eq 0 ]; then
        run sudo install -m 644 "$tmp" "$file"
    fi
    rm -f "$tmp"
    return "$rc"
}

# gpu_configure: install drivers, edit boot config, write gpu.conf, using the answers.
gpu_configure() {
    local gpu mod virt lists=() names=() n rc
    gpu="$(answers_get GPU)"
    mod="$(answers_get NVIDIA_MODULE)"
    virt="$(gpu_virt)"
    [ -n "$gpu" ] || die "GPU is not set"

    while IFS= read -r n; do lists+=("$n"); done < <(gpu_package_lists "$gpu" "${mod:-proprietary}" "$virt")
    [ "${#lists[@]}" -gt 0 ] || die "No package lists for GPU '$gpu'"
    while IFS= read -r n; do names+=("$n"); done < <(pkg_read_list "${lists[@]}")
    pkg_install_repo "${names[@]}"

    case "$gpu" in
        nvidia | hybrid-*)
            rc=0
            _gpu_edit_etc "${NUSKU_GRUB_DEFAULT:-/etc/default/grub}" grub_add_params "${NUSKU_NVIDIA_PARAMS[@]}" || rc=$?
            case "$rc" in
                0) run sudo grub-mkconfig -o /boot/grub/grub.cfg ;;
                2) log_warn "No GRUB config found; add these kernel parameters manually: ${NUSKU_NVIDIA_PARAMS[*]}" ;;
            esac
            rc=0
            _gpu_edit_etc "${NUSKU_MKINITCPIO_CONF:-/etc/mkinitcpio.conf}" mkinit_add_modules "${NUSKU_NVIDIA_MODULES[@]}" || rc=$?
            case "$rc" in
                0) run sudo mkinitcpio -P ;;
                2) log_warn "No mkinitcpio.conf found; add these modules manually: ${NUSKU_NVIDIA_MODULES[*]}" ;;
            esac
            ;;
    esac

    local conf="${XDG_CONFIG_HOME:-$HOME/.config}/nusku/gpu.conf"
    mkdir -p "$(dirname "$conf")"
    gpu_hypr_conf "$gpu" "$virt" >"$conf"
    log_info "GPU configured ($gpu); wrote $conf"
}
