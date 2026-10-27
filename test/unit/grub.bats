in_sub() { bash -c 'source lib/log.sh; source lib/answers.sh; source lib/packages.sh; source lib/grub.sh; '"$1"; }

@test "grub_add_params adds to empty default" {
    f="$BATS_TEST_TMPDIR/grub"
    printf 'GRUB_TIMEOUT=5\nGRUB_CMDLINE_LINUX_DEFAULT=""\n' >"$f"
    run in_sub "grub_add_params '$f' a=1 b=2"
    [ "$status" -eq 0 ]
    grep -qx 'GRUB_CMDLINE_LINUX_DEFAULT="a=1 b=2"' "$f"
    grep -qx 'GRUB_TIMEOUT=5' "$f"
}

@test "grub_add_params appends keeping existing params" {
    f="$BATS_TEST_TMPDIR/grub"
    printf 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"\n' >"$f"
    run in_sub "grub_add_params '$f' a=1"
    grep -qx 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet a=1"' "$f"
}

@test "grub_add_params is idempotent (status 1 = nothing changed)" {
    f="$BATS_TEST_TMPDIR/grub"
    printf 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"\n' >"$f"
    run in_sub "grub_add_params '$f' a=1 b=2"
    [ "$status" -eq 0 ]
    run in_sub "grub_add_params '$f' a=1 b=2"
    [ "$status" -eq 1 ]
    [ "$(grep -o 'a=1' "$f" | wc -l)" -eq 1 ]
}

@test "grub_add_params handles single quotes" {
    f="$BATS_TEST_TMPDIR/grub"
    printf "GRUB_CMDLINE_LINUX_DEFAULT='quiet'\n" >"$f"
    run in_sub "grub_add_params '$f' a=1"
    grep -q 'quiet a=1' "$f"
}

@test "grub_add_params appends line when absent" {
    f="$BATS_TEST_TMPDIR/grub"
    printf 'GRUB_TIMEOUT=5\n' >"$f"
    run in_sub "grub_add_params '$f' a=1"
    grep -qx 'GRUB_CMDLINE_LINUX_DEFAULT="a=1"' "$f"
}

@test "mkinit_add_modules on empty and populated MODULES" {
    f="$BATS_TEST_TMPDIR/mk"
    printf 'MODULES=()\nHOOKS=(base)\n' >"$f"
    run in_sub "mkinit_add_modules '$f' nvidia nvidia_drm"
    [ "$status" -eq 0 ]
    grep -qx 'MODULES=(nvidia nvidia_drm)' "$f"
    printf 'MODULES=(btrfs)\n' >"$f"
    run in_sub "mkinit_add_modules '$f' nvidia"
    grep -qx 'MODULES=(btrfs nvidia)' "$f"
}

@test "mkinit_add_modules is idempotent" {
    f="$BATS_TEST_TMPDIR/mk"
    printf 'MODULES=(btrfs)\n' >"$f"
    run in_sub "mkinit_add_modules '$f' nvidia"
    run in_sub "mkinit_add_modules '$f' nvidia"
    [ "$status" -eq 1 ]
    grep -qx 'MODULES=(btrfs nvidia)' "$f"
}

@test "mkinit_remove_hook removes kms and keeps the rest" {
    f="$BATS_TEST_TMPDIR/mk"
    printf 'MODULES=()\nHOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block filesystems fsck)\n' >"$f"
    run in_sub "mkinit_remove_hook '$f' kms"
    [ "$status" -eq 0 ]
    grep -qx 'HOOKS=(base systemd autodetect microcode modconf keyboard sd-vconsole block filesystems fsck)' "$f"
    grep -qx 'MODULES=()' "$f"
}

@test "mkinit_remove_hook is idempotent (status 1) and 2 for a missing file" {
    f="$BATS_TEST_TMPDIR/mk"
    printf 'HOOKS=(base kms udev)\n' >"$f"
    run in_sub "mkinit_remove_hook '$f' kms"
    [ "$status" -eq 0 ]
    run in_sub "mkinit_remove_hook '$f' kms"
    [ "$status" -eq 1 ]
    grep -qx 'HOOKS=(base udev)' "$f"
    printf 'MODULES=()\n' >"$f"
    run in_sub "mkinit_remove_hook '$f' kms"
    [ "$status" -eq 1 ]
    run in_sub "mkinit_remove_hook '$BATS_TEST_TMPDIR/none' kms"
    [ "$status" -eq 2 ]
}

@test "mkinit_remove_hook does not touch similarly named hooks" {
    f="$BATS_TEST_TMPDIR/mk"
    printf 'HOOKS=(base kmsx xkms)\n' >"$f"
    run in_sub "mkinit_remove_hook '$f' kms"
    [ "$status" -eq 1 ]
    grep -qx 'HOOKS=(base kmsx xkms)' "$f"
}
