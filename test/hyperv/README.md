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
if (-not (Test-Path $HOME\.ssh\nusku_test)) { ssh-keygen -t ed25519 -f $HOME\.ssh\nusku_test -N '""' }
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

Install, then reboot (do not chroot). After first boot, log in as `tester`:

```bash
sudo systemctl enable --now sshd hv_kvp_daemon hv_vss_daemon
# Test VM only: passwordless sudo for the automated loop
echo 'tester ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/10-tester
mkdir -p ~/.ssh && chmod 700 ~/.ssh
```

Put the host's public key in `~/.ssh/authorized_keys` — paste it
(`Get-Content $HOME\.ssh\nusku_test.pub` on the host), or from the host once the
VM has an IP (`(Get-VMNetworkAdapter -VMName nusku-test).IPAddresses`):

```powershell
scp -i $HOME\.ssh\nusku_test $HOME\.ssh\nusku_test.pub tester@<ip>:/tmp/k.pub
# in the VM: cat /tmp/k.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys
```

Check from the host: `ssh -i $HOME\.ssh\nusku_test tester@<ip> true`.

## 4. Checkpoint

Shut the VM down (`sudo poweroff`), then on the host:

```powershell
Set-VMDvdDrive -VMName nusku-test -Path $null
Set-VMFirmware -VMName nusku-test -FirstBootDevice (Get-VMHardDiskDrive -VMName nusku-test)
Checkpoint-VM -Name nusku-test -SnapshotName clean-arch
```

Restore later with `Restore-VMSnapshot -VMName nusku-test -Name clean-arch -Confirm:$false`.
