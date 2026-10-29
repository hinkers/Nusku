# Hyper-V test VM

A throwaway Arch VM for testing the installer. You build it once, take a
checkpoint (`clean-arch`), and the test loop restores that checkpoint before
every run.

## 1. One-time host setup

In an **elevated** PowerShell:

```powershell
Add-LocalGroupMember -Group "Hyper-V Administrators" -Member $env:USERNAME
```

Sign out and back in. The OpenSSH client is built into Windows. Create a key
if you do not have one:

```powershell
New-Item -ItemType Directory -Force "$HOME\.ssh" | Out-Null
if (-not (Test-Path "$HOME\.ssh\nusku_test")) { ssh-keygen -t ed25519 -f "$HOME\.ssh\nusku_test" -N '""' }
```

## 2. Create the VM

Download the Arch ISO, then:

```powershell
.\test\hyperv\New-NuskuVM.ps1 -IsoPath E:\archlinux-2026.10.01-x86_64.iso
Start-VM -Name nusku-test
vmconnect.exe localhost nusku-test
```

Options: `-Name nusku-test -MemoryGB 8 -Cpus 4 -DiskGB 60 -Force`.
Gen 2, Secure Boot off, Default Switch.

## 3. Base install (manual, inside the VM)

Boot the ISO, then run `archinstall`. Menus change slightly between releases;
the intent is:

- Disk configuration: best-effort default layout, use the entire disk, ext4
- Bootloader: GRUB (UEFI)
- User account: `tester`, administrator (sudo), a password of your choice
- Profile: Minimal
- Additional packages: `openssh git sudo hyperv`
- Network configuration: NetworkManager

When archinstall finishes, **power off** (do not reboot, or the live ISO boots
again). On the host, eject the ISO and boot from the disk:

```powershell
Set-VMDvdDrive -VMName nusku-test -Path $null
Set-VMFirmware -VMName nusku-test -FirstBootDevice (Get-VMHardDiskDrive -VMName nusku-test)
Start-VM -Name nusku-test
```

Log in as `tester` and run:

```bash
sudo systemctl enable --now sshd hv_kvp_daemon hv_vss_daemon
# Test VM only: passwordless sudo for the automated loop
sudo install -m 440 /dev/stdin /etc/sudoers.d/10-tester <<<'tester ALL=(ALL) NOPASSWD: ALL'
sudo visudo -c
mkdir -p ~/.ssh && chmod 700 ~/.ssh
```

Put the host's public key in `~/.ssh/authorized_keys`: paste it
(`Get-Content "$HOME\.ssh\nusku_test.pub"` on the host), or copy it from the
host once the VM has an IP. `IPAddresses` also lists IPv6; use the IPv4 one:

```powershell
(Get-VMNetworkAdapter -VMName nusku-test).IPAddresses
scp "$HOME\.ssh\nusku_test.pub" tester@<ip>:/tmp/k.pub
# in the VM: cat /tmp/k.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
```

Check from the host: `ssh -i "$HOME\.ssh\nusku_test" tester@<ip> true`.

## 4. Checkpoint

Shut the VM down (`sudo poweroff`), then on the host:

```powershell
Checkpoint-VM -Name nusku-test -SnapshotName clean-arch
```

Restore later with `Restore-VMSnapshot -VMName nusku-test -Name clean-arch -Confirm:$false`.

## 5. Running the test loop

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File test/hyperv/Invoke-NuskuTest.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File test/hyperv/Invoke-NuskuTest.ps1 -Answers test/answers/vm-full.answers
```

`-Answers` takes a repo-relative path (default `test/answers/vm.answers`, a Stage 1 style install with no apps). With an answers file that has an `APPS` line, the run also checks that every app's command exists, the Flatpak, Docker and UFW services, the SSH and LocalSend ports, multilib and that Snapper was skipped on ext4, and adds a Neovim screenshot. Every run checks the keybind menu (SUPER + slash bound, the manifest written, the menu listing binds with Rofi stubbed, a manifest entry run through `hyprctl dispatch`) and screenshots it. When `APPS` includes `photocraft` (as `vm-full.answers` does), the run also checks the ArtCraft Launcher and PhotoCraft packages, the launcher's autostart entry and running process, then re-runs the installer and checks nothing was downloaded again. `vm-full.answers` picks every app and language; a full run needs about 25 GB of the VM's 60 GB disk and takes from about 15 minutes to an hour, depending on your connection.
