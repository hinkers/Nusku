setup() {
    export XDG_STATE_HOME="$BATS_TEST_TMPDIR" XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/cfg"
    unset NUSKU_LOG NUSKU_STEP NUSKU_NONINTERACTIVE
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS"
    CALLS="$BATS_TEST_TMPDIR/calls"
    : >"$CALLS"
    printf '#!/bin/sh\necho "sudo $*" >>"$CALLS"\nexec "$@"\n' >"$STUBS/sudo"
    chmod +x "$STUBS/sudo"
    for c in pacman mkinitcpio grub-mkconfig; do
        printf '#!/bin/sh\necho "%s $*" >>"$CALLS"\n' "$c" >"$STUBS/$c"
        chmod +x "$STUBS/$c"
    done
    printf '#!/bin/sh\necho none\n' >"$STUBS/systemd-detect-virt"
    chmod +x "$STUBS/systemd-detect-virt"
}

in_sub() {
    PATH="$STUBS:$PATH" CALLS="$CALLS" bash -c 'source lib/log.sh; source lib/answers.sh; source lib/packages.sh; source lib/grub.sh; source lib/backup.sh; source lib/gpu.sh; '"$1"
}

@test "gpu_package_lists hybrid-intel open = intel + nvidia-open + prime" {
    run in_sub "gpu_package_lists hybrid-intel open none | xargs -n1 basename | tr '\n' ' '"
    [ "$output" = "gpu-intel.pacman gpu-nvidia-open.pacman gpu-hybrid.pacman " ]
}

@test "gpu_package_lists hybrid-amd proprietary" {
    run in_sub "gpu_package_lists hybrid-amd proprietary none | xargs -n1 basename | tr '\n' ' '"
    [ "$output" = "gpu-amd.pacman gpu-nvidia.pacman gpu-nvidia.aur gpu-hybrid.pacman " ]
}

@test "gpu_package_lists vm microsoft = vm-hyperv" {
    run in_sub "gpu_package_lists vm proprietary microsoft | xargs -n1 basename"
    [ "$output" = "gpu-vm-hyperv.pacman" ]
}

@test "gpu_package_lists vm: vmware, kvm, qemu, none" {
    run in_sub "gpu_package_lists vm proprietary vmware | xargs -n1 basename"
    [ "$output" = "gpu-vm-vmware.pacman" ]
    run in_sub "gpu_package_lists vm proprietary kvm | xargs -n1 basename"
    [ "$output" = "gpu-vm-qemu.pacman" ]
    run in_sub "gpu_package_lists vm proprietary qemu | xargs -n1 basename"
    [ "$output" = "gpu-vm-qemu.pacman" ]
    run in_sub "gpu_package_lists vm proprietary none | xargs -n1 basename"
    [ "$output" = "gpu-vm-generic.pacman" ]
}

@test "gpu_package_lists nvidia proprietary includes the AUR legacy list, no repo nvidia-utils, no prime" {
    run in_sub 'pkg_read_list $(gpu_package_lists nvidia proprietary none)'
    [ -z "$(grep -x nvidia-utils <<<"$output")" ]
    [[ "$output" == *nvidia-580xx-dkms* ]]
    [[ "$output" != *nvidia-open-dkms* ]]
    [[ "$output" != *nvidia-prime* ]]
}

@test "gpu_hypr_conf vm microsoft" {
    run in_sub "gpu_hypr_conf vm microsoft"
    [[ "$output" == *no_hardware_cursors* ]]
    [[ "$output" == *LIBGL_ALWAYS_SOFTWARE* ]]
    [[ "$output" == *WLR_RENDERER_ALLOW_SOFTWARE* ]]
}

@test "gpu_hypr_conf vm kvm has cursor fix but no software GL" {
    run in_sub "gpu_hypr_conf vm kvm"
    [[ "$output" == *no_hardware_cursors* ]]
    [[ "$output" != *LIBGL_ALWAYS_SOFTWARE* ]]
}

@test "gpu_hypr_conf hybrid-amd does not force NVIDIA" {
    run in_sub "gpu_hypr_conf hybrid-amd none"
    [[ "$output" != *__GLX_VENDOR_LIBRARY_NAME* ]]
    [[ "$output" != *LIBVA_DRIVER_NAME* ]]
}

@test "gpu_hypr_conf nvidia sets NVIDIA env" {
    run in_sub "gpu_hypr_conf nvidia none"
    [[ "$output" == *"env = LIBVA_DRIVER_NAME,nvidia"* ]]
    [[ "$output" == *"env = __GLX_VENDOR_LIBRARY_NAME,nvidia"* ]]
    [[ "$output" == *"env = NVD_BACKEND,direct"* ]]
}

@test "gpu_hypr_conf amd is comments only" {
    run in_sub "gpu_hypr_conf amd none"
    [[ "$output" == "#"* ]]
    [ -z "$(printf '%s\n' "$output" | grep -v '^#')" ]
}

@test "gpu_vm_services" {
    run in_sub "gpu_vm_services microsoft"
    [ "$output" = "hv_kvp_daemon hv_vss_daemon" ]
    run in_sub "gpu_vm_services vmware"
    [ "$output" = "vmtoolsd" ]
    run in_sub "gpu_vm_services kvm"
    [ "$output" = "qemu-guest-agent" ]
    run in_sub "gpu_vm_services none"
    [ -z "$output" ]
}

@test "gpu_suggest never dies without lspci" {
    run in_sub "gpu_suggest"
    [ "$status" -eq 0 ]
}

@test "gpu_configure nvidia edits files, rebuilds once, writes gpu.conf" {
    printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' >"$BATS_TEST_TMPDIR/grub"
    printf 'MODULES=()\n' >"$BATS_TEST_TMPDIR/mk"
    export NUSKU_GRUB_DEFAULT="$BATS_TEST_TMPDIR/grub" NUSKU_MKINITCPIO_CONF="$BATS_TEST_TMPDIR/mk"
    run in_sub "answers_set GPU nvidia; answers_set NVIDIA_MODULE open; gpu_configure"
    [ "$status" -eq 0 ]
    grep -q 'nvidia_drm.modeset=1 nvidia_drm.fbdev=1' "$BATS_TEST_TMPDIR/grub"
    grep -qx 'MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)' "$BATS_TEST_TMPDIR/mk"
    grep -q 'pacman -S --needed --noconfirm nvidia-open-dkms' "$CALLS"
    [ "$(grep -c '^mkinitcpio -P' "$CALLS")" -eq 1 ]
    [ "$(grep -c '^grub-mkconfig -o /boot/grub/grub.cfg' "$CALLS")" -eq 1 ]
    [ -n "$(find "$BATS_TEST_TMPDIR"/nusku/backup-* -name grub -type f)" ]
    [ -n "$(find "$BATS_TEST_TMPDIR"/nusku/backup-* -name mk -type f)" ]
    grep -q NVD_BACKEND "$BATS_TEST_TMPDIR/cfg/nusku/gpu.conf"
    : >"$CALLS"
    run in_sub "answers_set GPU nvidia; answers_set NVIDIA_MODULE open; gpu_configure"
    [ "$status" -eq 0 ]
    [ "$(grep -c '^mkinitcpio' "$CALLS")" -eq 0 ]
    [ "$(grep -c '^grub-mkconfig' "$CALLS")" -eq 0 ]
}

@test "gpu_configure nvidia with missing grub file warns, does not die" {
    printf 'MODULES=()\n' >"$BATS_TEST_TMPDIR/mk"
    export NUSKU_GRUB_DEFAULT="$BATS_TEST_TMPDIR/nogrub" NUSKU_MKINITCPIO_CONF="$BATS_TEST_TMPDIR/mk"
    run in_sub "answers_set GPU nvidia; answers_set NVIDIA_MODULE open; gpu_configure"
    [ "$status" -eq 0 ]
    [[ "$output" == *nvidia_drm.modeset=1* ]]
    [ "$(grep -c '^grub-mkconfig' "$CALLS")" -eq 0 ]
}

@test "gpu_configure amd does no boot edits" {
    run in_sub "answers_set GPU amd; gpu_configure"
    [ "$status" -eq 0 ]
    [ "$(grep -c '^mkinitcpio' "$CALLS")" -eq 0 ]
    [ -f "$BATS_TEST_TMPDIR/cfg/nusku/gpu.conf" ]
}

@test "gpu_package_lists nvidia proprietary includes gpu-nvidia.aur, open does not" {
    run in_sub "gpu_package_lists nvidia proprietary none"
    [[ "$output" == *gpu-nvidia.aur* ]]
    run in_sub "gpu_package_lists nvidia open none"
    [[ "$output" != *.aur* ]]
}

@test "gpu_configure proprietary installs repo bits then AUR driver" {
    printf '#!/bin/sh\necho "paru $*" >>"$CALLS"\n' >"$STUBS/paru"
    chmod +x "$STUBS/paru"
    export NUSKU_GRUB_DEFAULT="$BATS_TEST_TMPDIR/nogrub" NUSKU_MKINITCPIO_CONF="$BATS_TEST_TMPDIR/nomk"
    run in_sub "answers_set GPU nvidia; answers_set NVIDIA_MODULE proprietary; answers_set AUR_HELPER paru; gpu_configure"
    [ "$status" -eq 0 ]
    grep -q '^pacman -S --needed --noconfirm egl-wayland' "$CALLS"
    [ "$(grep -cw 'nvidia-utils' "$CALLS")" -eq 0 ]
    grep -q '^paru -S --needed --noconfirm nvidia-580xx-dkms nvidia-580xx-utils' "$CALLS"
    [ "$(grep -n '^pacman' "$CALLS" | head -1 | cut -d: -f1)" -lt "$(grep -n '^paru' "$CALLS" | head -1 | cut -d: -f1)" ]
}

# pacman stub that also answers -Qq for the kernels listed in STUB_KERNELS.
_kernel_pacman() {
    cat >"$STUBS/pacman" <<'STUB'
#!/usr/bin/env bash
echo "pacman $*" >>"$CALLS"
if [ "$1" = "-Qq" ]; then
    shift
    rc=0
    for p in "$@"; do
        case " $STUB_KERNELS " in
            *" $p "*) echo "$p" ;;
            *) echo "error: package '$p' was not found" >&2; rc=1 ;;
        esac
    done
    exit "$rc"
fi
STUB
    chmod +x "$STUBS/pacman"
}

@test "nvidia package lists no longer hard-code linux-headers" {
    run in_sub 'pkg_read_list packages/gpu-nvidia-open.pacman packages/gpu-nvidia.pacman'
    [ "$status" -eq 0 ]
    [ -z "$(grep -x linux-headers <<<"$output")" ]
}

@test "gpu_kernel_headers: headers for each installed kernel, only for NVIDIA" {
    _kernel_pacman
    export STUB_KERNELS="linux-zen linux-lts"
    run in_sub "gpu_kernel_headers nvidia | tr '\n' ' '"
    [ "$status" -eq 0 ]
    [ "$output" = "linux-lts-headers linux-zen-headers " ]
    run in_sub "gpu_kernel_headers hybrid-amd | tr '\n' ' '"
    [ "$output" = "linux-lts-headers linux-zen-headers " ]
    run in_sub "gpu_kernel_headers amd"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "gpu_configure nvidia installs headers for the installed kernels" {
    _kernel_pacman
    export STUB_KERNELS="linux linux-hardened"
    export NUSKU_GRUB_DEFAULT="$BATS_TEST_TMPDIR/nogrub" NUSKU_MKINITCPIO_CONF="$BATS_TEST_TMPDIR/nomk"
    run in_sub "answers_set GPU nvidia; answers_set NVIDIA_MODULE open; gpu_configure"
    [ "$status" -eq 0 ]
    line="$(grep '^pacman -S ' "$CALLS")"
    [[ " $line " == *" linux-headers "* ]]
    [[ " $line " == *" linux-hardened-headers "* ]]
    [[ " $line " != *" linux-lts-headers "* ]]
}
