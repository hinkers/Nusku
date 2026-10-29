<#
.SYNOPSIS
    Restores a clean Arch VM, runs the Nusku installer, reboots, checks the
    desktop and takes screenshots.

.DESCRIPTION
    1. Restore checkpoint 'clean-arch' and start the VM.
    2. Wait for an IPv4 address (via Hyper-V KVP) and for SSH.
    3. Package the working tree (tracked + untracked, honouring .gitignore,
       including uncommitted changes), copy it to ~/nusku and extract it.
    4. Run install.sh non-interactively with the answers file (default test/answers/vm.answers).
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

.PARAMETER Answers
    Answers file, relative to the repo root (default test/answers/vm.answers).
    When it has an APPS line, the app checks and an extra Neovim screenshot run too.
    test/answers/vm-full.answers installs every app and language.

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
    [string]$Answers = 'test/answers/vm.answers',
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

if (-not (Test-Path (Join-Path $RepoRoot $Answers))) { Stop-WithError "Answers file '$Answers' not found under the repo root." }
$Answers = $Answers -replace '\\', '/'
$HasApps = [bool](Select-String -Path (Join-Path $RepoRoot $Answers) -Pattern '^APPS=' -Quiet)
$HasPokemon = [bool](Select-String -Path (Join-Path $RepoRoot $Answers) -Pattern '^APPS=.*\bpokemon\b' -Quiet)
$HasArtCraft = [bool](Select-String -Path (Join-Path $RepoRoot $Answers) -Pattern '^APPS=.*\bphotocraft\b' -Quiet)
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
    "cd ~/nusku && set -o pipefail && NUSKU_NONINTERACTIVE=1 ./install.sh --answers $Answers --no-reboot 2>&1 | tee ~/install.out"
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

# Shared preamble: find the Wayland socket and Hyprland instance signature so
# grim and hyprctl work from an SSH session.
$envPreamble = @'
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR"/wayland-* 2>/dev/null | grep -v '\.lock$' | head -1 | xargs -r basename)
sig=$(ls -t "$XDG_RUNTIME_DIR/hypr/" 2>/dev/null | head -1)
export HYPRLAND_INSTANCE_SIGNATURE="$sig"
'@

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

# The config is Lua (hyprctl eval only works with a Lua config), loads without
# errors, registers every Nusku bind, and Hyprland shows no notice (e.g. the
# 0.56 ".conf format will be removed" one) over the desktop.
$cfgType = ((Invoke-Remote ($envPreamble + "`nhyprctl eval 'return 1'")) -join ' ').Trim()
if ($cfgType -eq 'ok') { Add-Result 'hyprland config is lua' 'PASS' 'hyprctl eval ok' }
else { Add-Result 'hyprland config is lua' 'FAIL' "hyprctl eval: $cfgType" }
$cfgErrors = ((Invoke-Remote ($envPreamble + "`nhyprctl configerrors")) | Where-Object { $_.Trim() -ne '' }) -join ' / '
if ($script:RemoteExit -eq 0 -and -not $cfgErrors) { Add-Result 'hyprland config errors' 'PASS' 'none' }
else { Add-Result 'hyprland config errors' 'FAIL' "$cfgErrors" }
$bindCount = ((Invoke-Remote ($envPreamble + "`nhyprctl binds -j | jq length")) | Select-Object -First 1)
if ([int]("0$bindCount".Trim()) -ge 62) { Add-Result 'hyprland binds' 'PASS' "$bindCount binds" }
else { Add-Result 'hyprland binds' 'FAIL' "$bindCount binds (expected >= 62)" }
$notifyLua = 'local t = {} for _, n in ipairs(hl.notification.get()) do t[#t + 1] = n:get_text() end return #t .. ": " .. table.concat(t, " / ")'
# Prefix the count: an empty repl reply comes back from hyprctl as "unknown request".
$notices = ((Invoke-Remote ($envPreamble + "`nhyprctl repl '$notifyLua'")) | Where-Object { $_.Trim() -ne '' }) -join ' / '
if ($notices.Trim() -eq '0:') { Add-Result 'hyprland notifications' 'PASS' 'none' }
elseif ($notices -match '\.conf|0\.57') { Add-Result 'hyprland notifications' 'FAIL' "$notices" }
else { Add-Result 'hyprland notifications' 'WARN' "$notices" }

# Keybind menu: script linked, SUPER + slash registered (with its description), the
# manifest written by keybinds.lua in this session, the menu lists it (Rofi stubbed),
# and a manifest expr runs through `hyprctl` dispatching like a menu pick would.
$null = Invoke-Remote 'test -x ~/.local/bin/nusku-menu-keybinds'
if ($script:RemoteExit -eq 0) { Add-Result 'keybind menu script' 'PASS' '~/.local/bin/nusku-menu-keybinds' }
else { Add-Result 'keybind menu script' 'FAIL' 'missing' }
$slash = ((Invoke-Remote ($envPreamble + "`nhyprctl binds -j | jq -c '.[] | select(.key == `"slash`") | {modmask, key, description}'")) -join ' ').Trim()
if ($slash -match 'Search keybinds') { Add-Result 'bind SUPER + slash' 'PASS' $slash }
elseif ($slash) { Add-Result 'bind SUPER + slash' 'WARN' "registered, no description: $slash" }
else { Add-Result 'bind SUPER + slash' 'FAIL' 'not in hyprctl binds' }
$shotLine = ((Invoke-Remote ($envPreamble + "`ngrep -P '\tScreenshot a region\t' `"`$XDG_RUNTIME_DIR/nusku/keybinds.tsv`"")) -join ' ').Trim()
if ($script:RemoteExit -eq 0) { Add-Result 'keybind manifest' 'PASS' ($shotLine -replace "`t", ' | ') }
else { Add-Result 'keybind manifest' 'FAIL' 'no "Screenshot a region" record' }
$menuOut = Invoke-Remote ($envPreamble + @'

stub=$(mktemp -d)
printf '#!/bin/sh\ncat > %s/listed\nexit 1\n' "$stub" > "$stub/rofi"
chmod +x "$stub/rofi"
PATH="$stub:$PATH" ~/.local/bin/nusku-menu-keybinds
rc=$?
grep -E 'Screenshot a region +Print|Search keybinds|Go to workspace' "$stub/listed"
n=$(wc -l < "$stub/listed")
rm -rf "$stub"
echo "lines=$n"
exit $rc
'@)
$menuText = ($menuOut -join ' / ')
if ($script:RemoteExit -eq 0 -and $menuText -match 'Screenshot a region +Print' -and $menuText -match 'Go to workspace') {
    Add-Result 'keybind menu lists binds' 'PASS' $menuText
} else { Add-Result 'keybind menu lists binds' 'FAIL' "exit $($script:RemoteExit): $menuText" }
$wsOut = Invoke-Remote ($envPreamble + @'

expr=$(awk -F'\t' '$1 == "bind" && $2 == "ws-go" && $4 == "2" { print $6; exit }' "$XDG_RUNTIME_DIR/nusku/keybinds.tsv")
echo "expr: $expr"
[ -n "$expr" ] || exit 3
hyprctl dispatch "$expr"
rc=$?
sleep 1
echo "active: $(hyprctl activeworkspace -j | jq .id)"
hyprctl dispatch 'hl.dsp.focus({ workspace = 1 })' >/dev/null
exit $rc
'@)
$wsText = ($wsOut -join ' / ')
if ($script:RemoteExit -eq 0 -and $wsText -match 'active: 2') { Add-Result 'dispatch manifest expr' 'PASS' $wsText }
else { Add-Result 'dispatch manifest expr' 'FAIL' "exit $($script:RemoteExit): $wsText" }

if ($HasPokemon) {
    $kr = (Invoke-Remote 'pacman -Q krabby-bin') -join ' / '
    if ($script:RemoteExit -eq 0) { Add-Result 'krabby package' 'PASS' $kr }
    else { Add-Result 'krabby package' 'FAIL' "$kr" }
    # krabby draws sprites with half-block characters (U+2580 / U+2584) and truecolor escapes;
    # the Arch logo uses neither. Byte-wise grep so the guest locale does not matter.
    $fetch = (Invoke-Remote 'out=$(~/.local/bin/nusku-fetch 2>&1); echo "$out" | LC_ALL=C grep -cP "\xe2\x96[\x80\x84]"') -join ' '
    if ($script:RemoteExit -eq 0 -and [int]$fetch -gt 0) { Add-Result 'nusku-fetch pokemon sprite' 'PASS' "$fetch sprite lines" }
    else { Add-Result 'nusku-fetch pokemon sprite' 'FAIL' "exit $($script:RemoteExit): $fetch" }
}

if ($HasArtCraft) {
    $pk = (Invoke-Remote 'pacman -Q ai.storyteller.artcraft-launcher ai.storyteller.photocraft') -join ' / '
    if ($script:RemoteExit -eq 0) { Add-Result 'artcraft packages' 'PASS' $pk }
    else { Add-Result 'artcraft packages' 'FAIL' "$pk" }
    $entry = (Invoke-Remote 'grep -x "Exec=/usr/bin/artcraft-launcher --hidden" ~/.config/autostart/ai.storyteller.artcraft-launcher.desktop') -join ' '
    if ($script:RemoteExit -eq 0) { Add-Result 'artcraft autostart entry' 'PASS' $entry }
    else { Add-Result 'artcraft autostart entry' 'FAIL' 'missing or no --hidden Exec' }
    $launcher = ''
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        $launcher = (Invoke-Remote 'pgrep -a -f "[a]rtcraft-launcher"') -join ' / '
        if ($script:RemoteExit -eq 0) { break }
        Start-Sleep -Seconds 3
    }
    if ($script:RemoteExit -eq 0) { Add-Result 'artcraft launcher running' 'PASS' $launcher }
    else { Add-Result 'artcraft launcher running' 'FAIL' 'no artcraft-launcher process after login' }
}

if ($HasApps) {
    $cmds = 'nvim gh claude lazygit docker code firefox discord obsidian libreoffice thunderbird zathura localsend spotify-launcher vlc obs audacity gimp krita inkscape kdenlive blender steam lutris heroic gamemoded mangohud protonup-qt wine yazi flatpak gparted ufw'
    foreach ($c in $cmds.Split(' ')) {
        $null = Invoke-Remote "command -v $c"
        if ($script:RemoteExit -eq 0) { Add-Result "command $c" 'PASS' 'found' }
        else { Add-Result "command $c" 'FAIL' 'not found' }
    }
    $null = Invoke-Remote 'flatpak info com.bitwarden.desktop >/dev/null'
    if ($script:RemoteExit -eq 0) { Add-Result 'flatpak bitwarden' 'PASS' 'installed' }
    else { Add-Result 'flatpak bitwarden' 'FAIL' 'not installed' }
    foreach ($svc in 'docker', 'ufw') {
        $st = ((Invoke-Remote "systemctl is-enabled $svc") | Select-Object -First 1)
        if ($st -eq 'enabled') { Add-Result "enabled $svc" 'PASS' $st } else { Add-Result "enabled $svc" 'FAIL' "$st" }
    }
    $null = Invoke-Remote 'sudo ufw status | grep -q 53317'
    if ($script:RemoteExit -eq 0) { Add-Result 'ufw allows 53317' 'PASS' 'LocalSend port open' }
    else { Add-Result 'ufw allows 53317' 'FAIL' 'port 53317 not in ufw status' }
    $null = Invoke-Remote 'sudo ufw status | grep -qE "^22/tcp"'
    if ($script:RemoteExit -eq 0) { Add-Result 'ufw allows 22' 'PASS' 'SSH port open' }
    else { Add-Result 'ufw allows 22' 'FAIL' '22/tcp not in ufw status' }
    $null = Invoke-Remote 'grep -q multilib /etc/pacman.conf'
    if ($script:RemoteExit -eq 0) { Add-Result 'multilib enabled' 'PASS' 'pacman.conf' }
    else { Add-Result 'multilib enabled' 'FAIL' 'not in pacman.conf' }
    $null = Invoke-Remote 'grep -q "Skipping Snapper" ~/.local/state/nusku/install-*.log'
    if ($script:RemoteExit -eq 0) { Add-Result 'snapper skipped (ext4)' 'PASS' 'logged' }
    else { Add-Result 'snapper skipped (ext4)' 'FAIL' 'no "Skipping Snapper" in the log' }
    $null = Invoke-Remote 'grep -q "Not installed" ~/install.out'
    if ($script:RemoteExit -ne 0) { Add-Result 'no optional app failures' 'PASS' 'summary clean' }
    else {
        $fl = (Invoke-Remote 'grep -A12 "Not installed" ~/install.out') -join ' / '
        Add-Result 'no optional app failures' 'FAIL' "$fl"
    }
}

# Re-run the installer once: ArtCraft packages already installed are not downloaded again.
if ($HasArtCraft) {
    Write-Step 'Re-running install.sh (ArtCraft must not download again)'
    $null = Invoke-Remote "cd ~/nusku && NUSKU_NONINTERACTIVE=1 ./install.sh --answers $Answers --no-reboot > ~/install2.out 2>&1"
    $rerunExit = $script:RemoteExit
    $rerun = (Invoke-Remote @'
log=$(ls -t ~/.local/state/nusku/install-*.log | head -1)
echo "log: $log"
grep -E 'releases/latest/download|is already installed' "$log"
'@) -join ' / '
    if ($rerunExit -ne 0) { Add-Result 'installer re-run' 'FAIL' "exit $rerunExit (see ~/install2.out)" }
    elseif ($rerun -match 'releases/latest/download') { Add-Result 'installer re-run' 'FAIL' "downloaded again: $rerun" }
    elseif ($rerun -match 'PhotoCraft is already installed') { Add-Result 'installer re-run' 'PASS' "no ArtCraft download: $rerun" }
    else { Add-Result 'installer re-run' 'FAIL' "no ArtCraft skip in the log: $rerun" }
}

$results | Format-Table -AutoSize | Out-String | Write-Host
$checksFailed = @($results | Where-Object { $_.Result -eq 'FAIL' }).Count -gt 0

# ------------------------------------------------------------ 7. screenshots
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
# Hyprland's config is Lua, so 'hyprctl dispatch' takes hl.dsp expressions.
# Park the cursor off the bar (no tooltips).
$moveCursor = "`nhyprctl dispatch 'hl.dsp.cursor.move({ x = 512, y = 400 })' >/dev/null"
$null = Invoke-Remote ($envPreamble + $moveCursor)
Start-Sleep -Seconds 1
Save-Screenshot 'desktop.png'
# A terminal shows the active window border (accent) and the Waybar window title.
$null = Invoke-Remote ($envPreamble + "`nhyprctl dispatch 'hl.dsp.exec_cmd(`"kitty`")' >/dev/null")
Start-Sleep -Seconds 5
$null = Invoke-Remote ($envPreamble + $moveCursor)
Save-Screenshot 'window.png'   # the fresh kitty shows the nusku-fetch greeting
$null = Invoke-Remote ($envPreamble + "`nhyprctl dispatch 'hl.dsp.exec_cmd(`"rofi -show drun`")' >/dev/null")
Start-Sleep -Seconds 4   # software rendering: give rofi time to map and animate in
Save-Screenshot 'rofi.png'
$null = Invoke-Remote 'pkill -x -u "$(id -u)" rofi || true'
# The keybind menu (SUPER + /), started the way its bind starts it.
$null = Invoke-Remote ($envPreamble + "`nhyprctl dispatch 'hl.dsp.exec_cmd(`"~/.local/bin/nusku-menu-keybinds`")' >/dev/null")
Start-Sleep -Seconds 4
Save-Screenshot 'keybinds.png'
$null = Invoke-Remote 'pkill -x -u "$(id -u)" rofi || true'
if ($HasApps) {
    $null = Invoke-Remote @'
printf 'import os


class Greeter:
    def __init__(self, name: str) -> None:
        self.name = name

    def greet(self) -> str:
        return f"Hello, {self.name}!"


if __name__ == "__main__":
    print(Greeter(os.getenv("USER", "world")).greet())
' > /tmp/demo.py
'@
    $null = Invoke-Remote ($envPreamble + "`nhyprctl dispatch 'hl.dsp.exec_cmd(`"kitty -e nvim /tmp/demo.py`")' >/dev/null")
    Start-Sleep -Seconds 5
    $null = Invoke-Remote ($envPreamble + $moveCursor)
    Save-Screenshot 'neovim.png'
}

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
