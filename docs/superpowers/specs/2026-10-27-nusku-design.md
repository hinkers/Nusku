# Nusku — Arch + Hyprland Desktop Bootstrap: Design

Date: 2026-10-27
Status: draft for owner review

## 1. Intent

Nusku is the owner's own Arch + Hyprland desktop, kept as a git repo of
dotfiles plus an interactive installer. On a **fresh Arch base install** you
clone the repo, run `install.sh`, answer a few questions, reboot, and land in
a finished, Catppuccin Mocha–themed desktop.

**Why:** the owner currently uses Omarchy on their laptop and wants their own
version instead. It is written from scratch, with no code or config copied from
Omarchy. It is their personal setup first; it should be clean enough to share,
but serving strangers is not a goal.

**Scope of use:** runs on a **fresh Arch base install**, and afterwards as an
**update** on a machine it already set up (pull the repo, re-apply configs,
install anything newly selected or newly added to the package lists). Running
it over someone else's setup (e.g. the current Omarchy laptop) is not supported.

**Repo is public** on GitHub.

**Success:** wipe a machine, run the installer, reboot, and feel at home with no
manual fixing afterwards.

## 2. Goals, non-goals, anti-goals

**Goals**
- One command after an Arch base install produces a complete desktop.
- Single palette file drives the whole look; changing the accent means changing one value.
- Pick optional app bundles from a checklist, with favourites (★) pre-checked.
- Idempotent: re-running is safe and converges to the same result.
- Every config lives in the repo and is symlinked into place, so editing the repo edits the live desktop.

**Non-goals**
- Installing Arch itself (partitioning, bootloader, base system).
- Supporting distros other than Arch.
- A GUI installer.
- Installing over an existing non-Nusku desktop (Omarchy etc.).
- Uninstalling apps the user un-checks on a re-run. Re-runs only add.
- Theme switching beyond the Catppuccin accent (no light theme, no other flavours).

**Anti-goals (a failure even if it "works")**
- Code or config copied from Omarchy, including its keybind scheme. Keybinds
  are a new set designed for Nusku.
- Leaving the user with a half-configured desktop and no clear error.
- Silently overwriting existing user config (it must be backed up first).
- Several palette copies drifting apart.

## 3. Constraints

- Bootloader: **GRUB** only (kernel params go in `/etc/default/grub` then
  `grub-mkconfig`). Other bootloaders: print the params to add by hand.
- Target: Arch Linux, x86_64, run as a normal user with sudo (not root).
- Network required.
- Testing host is Windows 11 with **Hyper-V** (VMware is not installed). Hyper-V
  has no 3D acceleration, so GPU-related behaviour is tested on real hardware.
- Everything in git from the first commit.

## 4. Build stages

Each stage is installable and testable on its own. Build in this order.

### Stage 1 — Installer skeleton, base desktop, theming
- Install flow (§5) end to end, with the app-selection step present but
  offering only what Stage 1 needs (it can show groups as "coming later" or
  omit them; builder's call).
- Everything in §7 "Always installed".
- Palette system and all theming (§6).
- Hyprland keybinds, window rules, animations, multi-monitor handling.
- Waybar with all modules in §10.
- Rofi menus: app launcher, power menu, clipboard history, wallpaper picker.
- Curated wallpapers in the repo (no generator yet).
- Hyper-V test VM and test loop (§11).

### Stage 2 — Optional groups and language picker
- All groups in §8 except ArtCraft.
- Language picker (§9).

### Stage 3 — Extras
- Generated wallpapers (ImageMagick from the palette).
- Optional larger wallpaper pack download.
- ArtCraft group.
- Oh My Posh as an alternative prompt.
- Rofi keybind cheatsheet.

## 5. Install flow

1. **Preflight**: confirm Arch, non-root user with sudo, network. Run a full
   system upgrade (`pacman -Syu`) before installing anything. Enable multilib
   if Gaming is selected (Stage 2).
2. **GPU choice**: AMD / Intel / NVIDIA / Hybrid (Intel or AMD + NVIDIA) /
   Virtual machine. The user picks; the installer may pre-select from
   `lspci` but never decides alone. Hybrid installs both driver sets and the
   NVIDIA offload setup (`prime-run`), with Hyprland running on the
   integrated GPU by default.
   - **AMD / Intel**: mesa + vulkan drivers.
   - **NVIDIA**: choose proprietary or open kernel module; set kernel params
     (`nvidia_drm.modeset=1`, and `fbdev=1` where relevant) and Hyprland
     NVIDIA env vars. Kernel params via GRUB; also add the nvidia modules to
     `mkinitcpio.conf` and rebuild the initramfs (works with or without LUKS).
   - **Virtual machine**: skip GPU drivers. Detect the hypervisor
     (`systemd-detect-virt`) and install the matching guest tools: Hyper-V
     (`hyperv` package / KVP daemons) and VMware (`open-vm-tools`); QEMU/KVM
     (`qemu-guest-agent`) is nice to have. Apply VM-only tweaks: software
     cursor, and software rendering where there's no 3D (Hyper-V). In VM mode
     with the test answers file, SDDM autologin is enabled so the test loop
     can screenshot a live session. Never on real hardware.
3. **AUR helper**: paru or yay, built from source. Skip if already present.
4. **Accent colour**: default **Blue**; any of the 14 Catppuccin accents.
5. **App selection**: checklist. Select a whole group, or open it and toggle
   individual apps. ★ apps are pre-checked.
6. **Install packages**: pacman, then AUR, then any non-repo installers.
7. **Deploy dotfiles**: symlink configs into place; back up any existing
   non-symlink file first (to a timestamped backup directory).
8. **Enable services**: sddm, NetworkManager, bluetooth, pipewire (user units),
   power-profiles-daemon; docker and ufw if selected.
9. **Summary + reboot prompt** into SDDM.

**Behaviour requirements**
- Idempotent: already-installed packages, existing symlinks and enabled
  services are skipped or confirmed, not redone destructively.
- All output logged to a file (e.g. `~/.local/state/nusku/install-<timestamp>.log`).
- Fails loudly: on error, stop, print which step failed, what command failed
  and where the log is.
- **Update mode:** `install.sh` (or a `nusku-update` command) on an
  already-set-up machine pulls the repo, re-deploys symlinks, re-renders
  theme files, installs newly selected or newly listed packages, and reuses
  saved answers unless the user asks to change them. It never removes packages.
- Answers can be saved so a re-run can reuse them (builder's call on format);
  a non-interactive mode driven by a config/answers file is required for the
  automated test loop.

## 6. Theme

- **Catppuccin Mocha**, accent **Blue `#89b4fa`** by default (any of the 14
  accents at install time).
- Palette source: https://github.com/catppuccin/palette (Mocha block of `palette.json`).
- **One palette file** in the repo (`theme/palette.*`) plus the chosen accent.
  All hand-written configs read from it: Hyprland borders, Waybar CSS, Rofi,
  SwayNC, Hyprlock, SDDM. The mechanism (template rendering at deploy time,
  `source`/`@import` of generated per-app colour files, etc.) is the builder's
  call, but changing the accent must be one value plus a re-run (or a small
  `nusku-theme` command).
- Use **official Catppuccin ports** where they exist: Hyprland, Hyprlock,
  Waybar, Kitty, Rofi, SDDM, cursors, btop, Starship, Yazi, Neovim, Kvantum.
  Ports may be vendored or fetched; pin versions either way.
- **GTK**: the official catppuccin/gtk port was archived in June 2024. Use a
  maintained base GTK theme (e.g. adw-gtk3) with a Mocha CSS override
  (`gtk.css` for GTK 3 and 4). Builder picks the exact base.
- **Qt**: Kvantum with Catppuccin Mocha (plus qt5ct/qt6ct to apply it).
- **Fonts**: JetBrains Mono Nerd Font + an emoji font (Noto Color Emoji).
- **Icons**: a Papirus-style icon theme with Catppuccin folder colours fits;
  builder's call.

## 7. Always installed (base desktop)

- **Desktop:** Hyprland, SDDM (Catppuccin theme), Waybar, Kitty, Rofi (Wayland
  build), Hyprlock, Hypridle, Hyprpaper, Hyprshot, SwayNC, cliphist, a polkit
  agent (e.g. hyprpolkitagent), xdg-desktop-portal-hyprland (+ gtk portal for
  file pickers).
- **System:** PipeWire + wireplumber + pavucontrol, NetworkManager, Bluetooth
  (bluez + a GUI such as blueman), power-profiles-daemon, Thunar, fonts.
- **Shell:** zsh as the login shell + Starship (Catppuccin Mocha preset).
- **Terminal tools:** fzf, ripgrep, fd, bat, eza, zoxide, btop, fastfetch.

## 8. Optional groups (★ = pre-checked)

**Dev** — ★ Neovim, ★ GitHub CLI, ★ Claude Code (CLI; add the desktop app only
if an official Linux build exists at implementation time), lazygit,
Docker + Compose, VS Code.

**Everyday** — ★ Firefox, ★ Discord, ★ Obsidian, LibreOffice, Thunderbird,
Bitwarden, Zathura, LocalSend.

**Media** — ★ Spotify, ★ VLC, OBS Studio, Audacity.

**Creative** — GIMP, Krita, Inkscape, Kdenlive, Blender.

**ArtCraft** (Stage 3, https://getartcraft.com/apps) — PhotoCraft, VectorCraft,
FilmCraft, LightCraft, PdfCraft, EffectCraft, DesignCraft, FigCraft, WordCraft,
SoundCraft, DeckCraft, CADCraft, GridCraft.
- Whole set → ArtCraft Launcher (keeps apps updated).
- Individual picks → each app's own Linux installer.
- Check the real Linux package format when implementing; add `.desktop`
  entries so they show in Rofi.
- Apps are early-stage; the Creative group stays as the fallback.

**Gaming** — Steam, Lutris, Heroic, Gamemode, MangoHud, ProtonUp-Qt, Wine
(enables multilib).

**System tools** — Yazi (Catppuccin theme, own keybind alongside Thunar),
Flatpak, Snapper, GParted, UFW. Snapper only on btrfs root (with snap-pac
and grub-btrfs); on other filesystems it is hidden or skipped with a note.

Package source per app (repo / AUR / Flatpak / vendor installer) is the
builder's call; prefer official repos, then AUR, then Flatpak.

## 9. Language picker (Stage 2, inside Dev)

Each selected language installs runtime + package manager + Neovim support
(LSP, formatter, treesitter parser):
- **Python:** python, uv, ruff, basedpyright
- **PHP:** php, Composer, Intelephense or Phpactor, php-cs-fixer
- **GDScript:** Godot; Neovim connects to Godot's built-in language server
- Also: JavaScript/TypeScript, Rust, Go, C/C++, C#, Java, Lua

The Neovim config is the repo's own (builder decides whether it sits on a
starter like lazy.nvim alone or a distro); language support is added per
selected language, not all at once.

## 10. Desktop extras

- **Rofi menus:** app launcher, power menu, clipboard history, wallpaper picker;
  keybind cheatsheet in Stage 3.
- **Wallpaper picker:** apply to all monitors or one; the choice persists
  across reboots.
- **Wallpapers:** high-res (≥4K) images with centred subjects, shown in
  fill/cover mode on every monitor. Same image and crop on desktop, Hyprlock
  and SDDM (`PreserveAspectCrop` in SDDM QML). Small curated set in the repo.
- **Starter set exists:** the owner has added 14 images (currently in the repo
  root) to move into `wallpapers/`. Several are under 4K (lowest 1920×1080);
  they stay, and ≥4K is the target for new additions. Total ~37 MB, committed
  as plain files (no LFS). The default wallpaper is the builder's pick.
- **Hyprland:** sensible keybinds, window rules, animations, multi-monitor
  handling (auto-detect with sane defaults; per-machine overrides in a
  file not tracked by the repo or a hostname-keyed file).
- **Waybar modules:** workspaces, window title, clock, audio, network,
  bluetooth, battery (laptops only), tray, notifications toggle (SwayNC).

## 11. Testing

- **Hyper-V Gen 2 VM** (Secure Boot off), minimal Arch install, `sshd` enabled,
  key-based SSH from the Windows host, checkpoint named **`clean-arch`**.
  Creating this VM is part of the project; the Arch base install inside it is
  manual, with written steps for the owner.
- **Loop** (driven from Claude Code via PowerShell Hyper-V cmdlets):
  restore `clean-arch` → start VM → SSH in → copy/clone repo → run installer
  non-interactively → check log and service states → screenshot with `grim`
  inside the session → copy back → inspect → fix → repeat.
- Hyper-V has no GPU acceleration: Hyprland runs on software rendering and will
  be slow. That's acceptable for checking installs and appearance.
- GPU paths (AMD/Intel/NVIDIA) and look-and-feel polish are verified on real
  hardware once the install path is solid.
- A lint step (shellcheck on all scripts) runs as part of the loop.

## 12. Repo layout (proposed)

```
install.sh            # entry point
lib/                  # helpers: ui, packages, gpu, logging, symlinks
packages/             # package lists per group / language (pacman, aur, other)
config/               # dotfiles: hypr, waybar, kitty, rofi, swaync, starship, yazi, nvim, ...
theme/palette.*       # single Catppuccin Mocha palette + accent
sddm/                 # SDDM theme config
wallpapers/           # curated set (+ generator script in Stage 3)
scripts/              # rofi menus, wallpaper picker, helpers
test/                 # Hyper-V test loop scripts (PowerShell) and VM setup notes
docs/                 # design + plans
```

## 13. Decided by the owner

- Their own setup, written from scratch; nothing copied from Omarchy.
- Everything in the original plan (flow, theme, groups, ★ defaults, extras).
- Test on Hyper-V for now; real hardware for GPU-related checks.
- Build in three stages in the order in §4.
- GPU is chosen by the user in the installer; GRUB is the bootloader.
- Fresh installs plus an update path; not for installing over Omarchy.
- New keybind set, not Omarchy's.
- Starter wallpapers supplied by the owner; repo is public.

## 14. Builder's calls (made by Claude, open to change)

- **Language:** Bash for the installer; PowerShell for the Windows-side test loop.
- **Installer UI:** `gum` (in the Arch repos) for menus/checklists, installed in
  preflight.
- **Accent stored** in the palette/config, re-applied by re-running the deploy step.
- Hyper-V guest tools, software rendering and software cursor in VM mode
  (replaces "open-vm-tools only" from the original plan).
- Non-interactive answers file, needed for automated testing.
- `pacman -Syu` in preflight.
- **Hybrid GPU** offered as its own option.
- **Re-runs only add** packages, never remove.
- **SDDM autologin** in VM test mode only.
- **Snapper** gated on btrfs; LUKS needs no special handling beyond the
  initramfs rebuild.
- **Hyper-V fallback:** if Hyprland can't render on Hyper-V, the loop drops to
  install/log/service checks plus screenshots on real hardware, and the owner
  is asked before installing any other hypervisor.
- Starter wallpapers kept even where below 4K.
- Exact GTK base theme, icon theme, polkit agent, Bluetooth GUI, Neovim setup
  approach, palette templating mechanism, and per-app package sources.
