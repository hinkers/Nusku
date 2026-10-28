<#
.SYNOPSIS
    Restores a clean Arch VM, runs the Nusku installer, reboots, checks the
    desktop and takes screenshots.

.DESCRIPTION
    1. Restore checkpoint 'clean-arch' and start the VM.
    2. Wait for an IPv4 address (via Hyper-V KVP) and for SSH.
    3. Package the working tree (tracked + untracked, honouring .gitignore,
       including uncommitted changes), copy it to ~/nusku and extract it.
    4. Run install.sh non-interactively with test/answers/vm.answers.
    5. Reboot, wait for SDDM autologin to start Hyprland and Waybar.
    6. Check services and processes, print a PASS/WARN/FAIL table.
    7. Screenshot the desktop, a kitty window and the rofi launcher with grim.
    On error the VM is left running for debugging.
    Results go to test/screenshots/<timestamp>/ (gitignored).
    Exit code is 1 if the install or any check failed, else 0.

.PARAMETER Name
    VM name (default nusku-test).

.PARAMETER User
    Guest user (default tester). Needs NOPASSWD sudo and the nusku_test key.

.PARAMETER KeepRunning
    Leave the VM running at the end. By default it is shut down (Stop-VM).

.EXAMPLE
    powershell -File test\hyperv\Invoke-NuskuTest.ps1 -KeepRunning
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Name = 'nusku-test',
    [string]$User = 'tester',
    [switch]$KeepRunning
)

$ErrorActionPreference = 'Stop'

$Checkpoint = 'clean-arch'
$KeyPath    = Join-Path $HOME '.ssh\nusku_test'
$RepoRoot   = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$OutDir     = Join-Path $RepoRoot "test\screenshots\$Stamp"
$script:Ip  = $null

$SshOpts = @(
    '-i', $KeyPath,
    '-o', 'StrictHostKeyChecking=no',
    '-o', 'UserKnownHostsFile=NUL',
    '-o', 'ConnectTimeout=5',
    '-o', 'ServerAliveInterval=5',
    '-o', 'ServerAliveCountMax=3',
    '-o', 'BatchMode=yes',
    '-o', 'LogLevel=ERROR'
)

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

# Note: on error the VM is deliberately left as-is (usually running) so you can debug it.
function Stop-WithError([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 2
}

# Builds the ssh command string for a script: base64 has no quoting hazards
# and avoids the CRLF that PowerShell 5.1 appends when piping to a native exe.
function ConvertTo-RemoteCommand([string]$Script) {
    $body = ($Script -replace "`r", '') + "`n"
    $b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($body))
    return "echo $b64 | base64 -d | bash"
}

# Runs a bash script on the guest. Returns stdout lines; the remote exit code
# is left in $script:RemoteExit.
function Invoke-Remote([string]$Script) {
    $out = & ssh.exe -n @SshOpts "$User@$($script:Ip)" (ConvertTo-RemoteCommand $Script)
    $script:RemoteExit = $LASTEXITCODE
    return $out
}

function Copy-FromGuest([string]$Remote, [string]$Local) {
    & scp.exe @SshOpts "$User@$($script:Ip):$Remote" $Local
    return ($LASTEXITCODE -eq 0)
}

function Get-GuestIPv4 {
    $adapter = Get-VMNetworkAdapter -VMName $Name
    $addr = @($adapter.IPAddresses) |
        Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' -and $_ -notlike '169.254.*' } |
        Select-Object -First 1
    return $addr
}

# Waits for an IPv4 and an open port 22. With -NotBootId, additionally waits
# until the guest reports a boot_id different from that value (i.e. it has
# really rebooted, not just still shutting down).
function Wait-ForSsh([int]$TimeoutSec = 180, [string]$NotBootId = '') {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $script:Ip = $null
    $sawIp = $false
    $sawPort = $false
    while ((Get-Date) -lt $deadline) {
        if (-not $script:Ip) { $script:Ip = Get-GuestIPv4 }
        if ($script:Ip) {
            $sawIp = $true
            $client = New-Object System.Net.Sockets.TcpClient
            $open = $false
            try {
                $task = $client.ConnectAsync($script:Ip, 22)
                $open = ($task.Wait(2000) -and $client.Connected)
            } catch { } finally { $client.Close() }
            if ($open) {
                $sawPort = $true
                if (-not $NotBootId) { return }
                $id = (Invoke-Remote 'cat /proc/sys/kernel/random/boot_id') | Select-Object -First 1
                if ($script:RemoteExit -eq 0 -and $id -and $id -ne $NotBootId) { return }
            } else {
                # The address may have changed after a reboot; re-read it next loop.
                $script:Ip = $null
            }
        }
        Start-Sleep -Seconds 3
    }
    if (-not $sawIp) {
        Stop-WithError ("No IPv4 address for VM '$Name' after ${TimeoutSec}s. " +
            "Is hv_kvp_daemon running in the guest (systemctl enable --now hv_kvp_daemon, package 'hyperv')?")
    }
    if (-not $sawPort) {
        Stop-WithError ("VM '$Name' has an IP but port 22 never opened within ${TimeoutSec}s. " +
            "Is sshd running and enabled in the guest (systemctl enable --now sshd), and not firewalled?")
    }
    Stop-WithError "VM '$Name' did not come back from the reboot (boot_id unchanged) within ${TimeoutSec}s."
}

function Assert-SshAuth {
    $null = & ssh.exe -n @SshOpts "$User@$($script:Ip)" 'true'
    if ($LASTEXITCODE -ne 0) {
        Stop-WithError ("SSH login as '$User' failed. Is the public key '$KeyPath.pub' in " +
            "~$User/.ssh/authorized_keys in the guest (and was the checkpoint taken after adding it)?")
    }
}

# ---------------------------------------------------------------- preflight
foreach ($tool in 'ssh.exe', 'scp.exe', 'tar.exe', 'git.exe') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Stop-WithError "$tool not found on PATH (OpenSSH client and tar ship with Windows; install Git for Windows for git)."
    }
}
if (-not (Test-Path $KeyPath)) {
    Stop-WithError "SSH key $KeyPath not found. See test\hyperv\README.md section 1."
}

try { $vm = Get-VM -Name $Name -ErrorAction Stop }
catch { Stop-WithError "VM '$Name' not found (or no permission: join 'Hyper-V Administrators' and sign in again). Create it with test\hyperv\New-NuskuVM.ps1." }

$snap = Get-VMSnapshot -VMName $Name -Name $Checkpoint -ErrorAction SilentlyContinue
if (-not $snap) {
    Stop-WithError "Checkpoint '$Checkpoint' not found on VM '$Name'. Take it after the base install: Checkpoint-VM -Name $Name -SnapshotName $Checkpoint"
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$installFailed = $false

# ------------------------------------------------------------ 1. restore VM
Write-Step "Restoring checkpoint '$Checkpoint' on '$Name'"
if ((Get-VM -Name $Name).State -in 'Running', 'Paused') { Stop-VM -Name $Name -TurnOff -Force }
Restore-VMCheckpoint -VMName $Name -Name $Checkpoint -Confirm:$false
Start-VM -Name $Name

# --------------------------------------------------------------- 2. wait IP
Write-Step 'Waiting for IP address and SSH'
Wait-ForSsh 180
Write-Host "    $User@$($script:Ip)"
Assert-SshAuth

# ------------------------------------------------------------- 3. package
Write-Step 'Packaging working tree'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "nusku-$Stamp"
New-Item -ItemType Directory -Force $tmp | Out-Null
$rawList  = Join-Path $tmp 'files.raw'
$list     = Join-Path $tmp 'files.lst'
$tarball  = Join-Path $tmp 'nusku.tar'

Push-Location $RepoRoot
try {
    # Capture raw bytes (NUL separators) without any shell or pipeline in between.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git.exe'
    $psi.Arguments = 'ls-files -co --exclude-standard -z'
    $psi.WorkingDirectory = $RepoRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $fs = [System.IO.File]::Create($rawList)
    try { $proc.StandardOutput.BaseStream.CopyTo($fs) } finally { $fs.Close() }
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) { Stop-WithError 'git ls-files failed.' }

    $text  = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($rawList))
    # .NET Framework has no Split(char, options) overload, so pass a char[]
    # explicitly; also drop empty entries (the trailing NUL) defensively.
    $files = $text.Split([char[]]@([char]0), [System.StringSplitOptions]::RemoveEmptyEntries) |
        Where-Object { $_ -and $_ -notlike 'test/screenshots/*' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }   # drop files deleted but not yet committed
    $bytes = [System.Text.Encoding]::UTF8.GetBytes((($files -join [char]0) + [char]0))
    [System.IO.File]::WriteAllBytes($list, $bytes)

    & tar.exe --null -T $list -cf $tarball
    if ($LASTEXITCODE -ne 0) { Stop-WithError 'tar failed.' }
} finally { Pop-Location }
Write-Host ("    {0} files, {1:N0} KiB" -f @($files).Count, ((Get-Item $tarball).Length / 1KB))

Write-Step 'Copying to guest'
& scp.exe @SshOpts $tarball "$User@$($script:Ip):/tmp/nusku.tar"
if ($LASTEXITCODE -ne 0) { Stop-WithError 'scp of the tarball failed.' }
# Windows tar does not carry exec bits, so restore them.
$null = Invoke-Remote @'
set -e
rm -rf ~/nusku && mkdir -p ~/nusku
tar -xf /tmp/nusku.tar -C ~/nusku
rm -f /tmp/nusku.tar
cd ~/nusku
chmod +x install.sh
chmod +x scripts/* 2>/dev/null || true
chmod +x test/*.sh 2>/dev/null || true
'@
if ($script:RemoteExit -ne 0) { Stop-WithError 'Extracting the tarball in the guest failed.' }
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

# --------------------------------------------------------------- 4. install
Write-Step 'Running install.sh (this takes a while)'
& ssh.exe -n @SshOpts "$User@$($script:Ip)" `
    'cd ~/nusku && NUSKU_NONINTERACTIVE=1 ./install.sh --answers test/answers/vm.answers --no-reboot'
$installExit = $LASTEXITCODE
if ($installExit -ne 0) { $installFailed = $true }
Write-Host "    install.sh exit code: $installExit"

$remoteLog = (Invoke-Remote 'ls -t ~/.local/state/nusku/install-*.log 2>/dev/null | head -1') | Select-Object -First 1
if ($remoteLog) {
    if (Copy-FromGuest $remoteLog (Join-Path $OutDir 'install.log')) {
        Write-Host "    log: $(Join-Path $OutDir 'install.log')"
    }
} else {
    Write-Host '    (no install log found in the guest)' -ForegroundColor Yellow
}

# --------------------------------------------------------------- 5. reboot
Write-Step 'Rebooting and waiting for autologin'
$bootId = (Invoke-Remote 'cat /proc/sys/kernel/random/boot_id') | Select-Object -First 1
if (-not $bootId) { Stop-WithError 'Could not read boot_id from the guest before rebooting.' }
$null = Invoke-Remote 'sudo systemctl reboot'   # ssh may drop with 255; ignore
Start-Sleep -Seconds 5
Wait-ForSsh 180 $bootId

# Hyprland may show up as "Hyprland" or a wrapper name; match both.
$hyprUp = $false
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
    $null = Invoke-Remote "pgrep -x Hyprland >/dev/null || pgrep -f -x '.*[Hh]yprland' >/dev/null"
    if ($script:RemoteExit -eq 0) { $hyprUp = $true; break }
    Start-Sleep -Seconds 3
}
if (-not $hyprUp) { Write-Host '    Hyprland did not start within 120 s' -ForegroundColor Yellow }

# Give waybar up to 30 s more.
$waybarUp = $false
$deadline = (Get-Date).AddSeconds(30)
while ($hyprUp -and (Get-Date) -lt $deadline) {
    $null = Invoke-Remote 'pgrep -x waybar >/dev/null'
    if ($script:RemoteExit -eq 0) { $waybarUp = $true; break }
    Start-Sleep -Seconds 2
}
if ($hyprUp -and -not $waybarUp) { Write-Host '    waybar did not start within 30 s after Hyprland' -ForegroundColor Yellow }
# Let the wallpaper come up: hyprpaper, or swaybg after nusku-wallpaper's ~5 s
# wait for hyprpaper where it cannot run (Hyper-V).
$deadline = (Get-Date).AddSeconds(20)
while ($hyprUp -and (Get-Date) -lt $deadline) {
    $null = Invoke-Remote 'pgrep -x hyprpaper >/dev/null || pgrep -x swaybg >/dev/null'
    if ($script:RemoteExit -eq 0) { break }
    Start-Sleep -Seconds 2
}
Start-Sleep -Seconds 3   # let it draw

# --------------------------------------------------------------- 6. checks
Write-Step 'Checking services and processes'
$results = New-Object System.Collections.Generic.List[object]

function Add-Result([string]$Check, [string]$Status, [string]$Detail) {
    $results.Add([pscustomobject]@{ Check = $Check; Result = $Status; Detail = $Detail })
}

foreach ($svc in 'sddm', 'NetworkManager', 'bluetooth', 'power-profiles-daemon') {
    $state = ((Invoke-Remote "systemctl is-active $svc") | Select-Object -First 1)
    if ($state -eq 'active') {
        Add-Result "service $svc" 'PASS' $state
    } elseif ($svc -eq 'bluetooth' -and $state -eq 'inactive') {
        # A Hyper-V VM has no Bluetooth adapter, so bluetooth.service is
        # condition-skipped (inactive). That is expected, not a failure.
        Add-Result "service $svc" 'WARN' "$state (no adapter in a VM)"
    } else {
        Add-Result "service $svc" 'FAIL' "$state"
    }
}
$null = Invoke-Remote "pgrep -x Hyprland >/dev/null || pgrep -f -x '.*[Hh]yprland' >/dev/null"
if ($script:RemoteExit -eq 0) { Add-Result 'process Hyprland' 'PASS' 'running' }
else { Add-Result 'process Hyprland' 'FAIL' 'not running' }
foreach ($proc in 'waybar', 'swaync') {
    $null = Invoke-Remote "pgrep -x $proc >/dev/null"
    if ($script:RemoteExit -eq 0) { Add-Result "process $proc" 'PASS' 'running' }
    else { Add-Result "process $proc" 'FAIL' 'not running' }
}
# hyprpaper 0.8 needs linux-dmabuf, which Hyprland only offers with a DRM render
# node; Hyper-V has none, so nusku-wallpaper falls back to swaybg there.
$null = Invoke-Remote 'pgrep -x hyprpaper >/dev/null'
if ($script:RemoteExit -eq 0) {
    Add-Result 'process hyprpaper' 'PASS' 'running'
} else {
    $null = Invoke-Remote 'pgrep -x swaybg >/dev/null'
    if ($script:RemoteExit -eq 0) {
        Add-Result 'process hyprpaper' 'WARN' 'not running (no render node); swaybg fallback running'
    } else {
        Add-Result 'process hyprpaper' 'FAIL' 'not running, and no swaybg fallback'
    }
}

$results | Format-Table -AutoSize | Out-String | Write-Host
$checksFailed = @($results | Where-Object { $_.Result -eq 'FAIL' }).Count -gt 0

# ------------------------------------------------------------ 7. screenshots
# Shared preamble: find the Wayland socket and Hyprland instance signature so
# grim and hyprctl work from an SSH session.
$envPreamble = @'
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -1 | xargs -r basename)
sig=$(ls -t "$XDG_RUNTIME_DIR/hypr/" 2>/dev/null | head -1)
export HYPRLAND_INSTANCE_SIGNATURE="$sig"
'@

function Save-Screenshot([string]$File) {
    $null = Invoke-Remote ($envPreamble + "`ngrim /tmp/shot.png")
    if ($script:RemoteExit -ne 0) {
        Write-Host "    grim failed for $File (is Hyprland rendering?)" -ForegroundColor Yellow
        $script:shotFailed = $true
        return
    }
    if (Copy-FromGuest '/tmp/shot.png' (Join-Path $OutDir $File)) {
        Write-Host "    saved $(Join-Path $OutDir $File)"
    } else {
        $script:shotFailed = $true
    }
}
$script:shotFailed = $false

Write-Step 'Taking screenshots'
# Hyprland 0.56 shows a timed ".conf format is deprecated" notice at login; clear
# it so it does not cover the bar, and park the cursor off the bar (no tooltips).
$null = Invoke-Remote ($envPreamble + "`nhyprctl dismissnotify >/dev/null; hyprctl dispatch movecursor 512 400 >/dev/null")
Start-Sleep -Seconds 1
Save-Screenshot 'desktop.png'
# A terminal shows the active window border (accent) and the Waybar window title.
$null = Invoke-Remote ($envPreamble + "`nhyprctl dispatch exec kitty >/dev/null")
Start-Sleep -Seconds 5
$null = Invoke-Remote ($envPreamble + "`nhyprctl dispatch movecursor 512 400 >/dev/null")
Save-Screenshot 'window.png'
$null = Invoke-Remote ($envPreamble + "`nhyprctl dispatch exec 'rofi -show drun'")
Start-Sleep -Seconds 4   # software rendering: give rofi time to map and animate in
Save-Screenshot 'rofi.png'
$null = Invoke-Remote 'pkill -x -u "$(id -u)" rofi || true'

# ---------------------------------------------------------------- finish
if (-not $KeepRunning) {
    Write-Step 'Shutting the VM down'
    Stop-VM -Name $Name -TurnOff -Force
}

Write-Host ''
if ($installFailed) { Write-Host "Install FAILED (exit $installExit). See $(Join-Path $OutDir 'install.log')" -ForegroundColor Red }
if ($shotFailed)    { Write-Host 'A screenshot is missing.' -ForegroundColor Red }
if ($checksFailed)  { Write-Host 'One or more checks FAILED.' -ForegroundColor Red }
Write-Host "Results: $OutDir"
if ($installFailed -or $checksFailed -or $shotFailed) { exit 1 }
Write-Host 'All good.' -ForegroundColor Green
exit 0
