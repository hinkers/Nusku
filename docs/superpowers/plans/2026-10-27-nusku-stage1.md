# Nusku Stage 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `install.sh` turns a fresh Arch base install into a complete, Catppuccin Mocha–themed Hyprland desktop (base desktop only, no optional groups), re-runnable as an update, with a Hyper-V test loop.

**Architecture:** A Bash entry point (`install.sh`) sources small single-purpose libraries in `lib/`, each exposing a few functions. Package names live in plain list files under `packages/`. Configs live in `config/` and are symlinked into `$HOME` from a manifest; anything colour-related is rendered from one palette file into `~/.config/nusku/theme/`, which the configs `source`/`@import`. Pure logic is unit-tested with bats in an Arch Linux Docker container on the Windows host; the full install is tested in the container and then in a Hyper-V VM.

**Tech Stack:** Bash 5, gum (menus), bats-core + shellcheck (tests), Docker `archlinux:latest` (test runner), PowerShell 5.1 Hyper-V cmdlets (VM loop), Hyprland ecosystem, Catppuccin ports.

**Spec:** `docs/superpowers/specs/2026-10-27-nusku-design.md`

## Global Constraints

- Target Arch Linux x86_64; run as a normal user with sudo, never as root.
- Bootloader is GRUB only; other bootloaders get the params printed for manual addition.
- Idempotent: re-running converges; never removes packages.
- Never overwrite a user file without backing it up to a timestamped backup directory first.
- Log everything to `~/.local/state/nusku/install-<timestamp>.log`.
- On failure: stop, print the failed step, the failed command and the log path.
- One palette file; accent default `blue` (`#89b4fa`); accent is one of the 14 Catppuccin accents: rosewater flamingo pink mauve red maroon peach yellow green teal sky sapphire blue lavender.
- Use official Catppuccin ports where they exist; pin versions; vendored files keep their upstream licence header and a `# source: <url>@<commit>` line.
- Nothing copied from Omarchy, including its keybinds.
- SDDM autologin only in VM test mode.
- All files LF line endings except `*.ps1` (CRLF), enforced by `.gitattributes` (already committed).
- All shell scripts pass `shellcheck -x` with no warnings.
- Repo is public: no secrets, no machine-specific paths.

## Review Focus

1. **Re-run on an already-installed machine** (update mode): every step must skip cleanly; symlinks already pointing at the repo must not be backed up again. → test in Task 7 (`link_file` on an existing correct link is a no-op) and Task 14 (second container run succeeds and creates no new backup dir).
2. **Repo moved or cloned to a different path** after install: symlinks would dangle. → `install.sh` must resolve its own absolute path and re-linking from the new path must replace links pointing at the old path without backing them up (they're our own links). Test in Task 7.
3. **Network drop or a failing package mid-install**: must stop with a readable error naming the package step, not continue into dotfiles. → test in Task 2 (`run` failure exits non-zero and prints step + command + log path).
4. **Answers file with a bad or missing value** (typo'd accent, unknown GPU): must fail at load time, not halfway through. → test in Task 3 (`answers_validate`).
5. **Machine with no battery / single monitor / multiple monitors of different resolutions**: Waybar shouldn't show a broken battery module; wallpapers fill each monitor. → battery module uses Waybar's own hide-when-absent behaviour; checked visually in Task 16 (VM has no battery) and the wallpaper script test in Task 10 covers per-monitor state.

---

## File Structure

```
install.sh                    entry point: flags, step order, update mode
lib/log.sh                    logging, run(), step(), die()
lib/answers.sh                answers file load/validate/save/get/set
lib/ui.sh                     gum wrappers; read answers in non-interactive mode
lib/preflight.sh              arch/user/sudo/network checks, gum bootstrap, -Syu
lib/packages.sh               list parsing, pacman/AUR install, AUR helper bootstrap
lib/gpu.sh                    gpu detection hint, per-GPU packages + config
lib/grub.sh                   idempotent GRUB_CMDLINE_LINUX_DEFAULT edits
lib/theme.sh                  palette loading, template rendering
lib/dotfiles.sh               manifest-driven symlinking with backup
lib/system.sh                 services, SDDM config, shell change
packages/base.pacman          always-installed repo packages
packages/base.aur             always-installed AUR packages
packages/gpu-{amd,intel,nvidia,nvidia-open,vm-hyperv,vm-vmware,vm-qemu}.pacman
theme/palette.conf            Catppuccin Mocha: name=hex, one per line
theme/templates/*.tmpl        per-app colour files rendered to ~/.config/nusku/theme/
config/links.txt              symlink manifest: "<repo-relative src> <$HOME-relative dest>"
config/hypr/ ...              hyprland, hypridle, hyprlock, hyprpaper configs
config/waybar/ config/swaync/ config/rofi/ config/kitty/ config/zsh/
config/starship.toml config/btop/ config/fastfetch/ config/gtk-3.0/ config/gtk-4.0/
config/Kvantum/ config/qt6ct/
sddm/                         sddm.conf.d snippets + theme overrides
scripts/nusku-wallpaper       set/restore/list wallpapers
scripts/nusku-menu-power      rofi power menu
scripts/nusku-menu-clipboard  rofi clipboard history
scripts/nusku-menu-wallpaper  rofi wallpaper picker
scripts/nusku-theme           re-render theme with a new accent
scripts/nusku-update          git pull + install.sh --update
wallpapers/                   the 14 starter images (moved from repo root)
test/Dockerfile               arch + bats + shellcheck + gum + sudo user "tester"
test/run-unit.sh              build image, run shellcheck + bats
test/run-container-install.sh full install.sh run inside the container
test/unit/*.bats              unit tests
test/answers/container.answers, test/answers/vm.answers
test/hyperv/New-NuskuVM.ps1, test/hyperv/Invoke-NuskuTest.ps1, test/hyperv/README.md
README.md
```

---

### Task 1: Test harness and repo skeleton

**Files:**
- Create: `test/Dockerfile`, `test/run-unit.sh`, `test/unit/smoke.bats`, `.gitignore`, `README.md`
- Move: the 14 images in the repo root → `wallpapers/` (`git mv` after `git add`)

**Interfaces:**
- Produces: `test/run-unit.sh [bats-filter]` — builds image `nusku-test`, runs `shellcheck -x` on `install.sh lib/*.sh scripts/*` (skipping missing paths), then `bats test/unit`. Exits non-zero on any failure. Works from Git Bash on Windows (use `MSYS_NO_PATHCONV=1` and `pwd -W` for the volume mount) and from Linux.
- Produces: image has a non-root user `tester` with passwordless sudo, repo mounted at `/nusku`, tests run as `tester`.

- [ ] **Step 1:** Write `test/unit/smoke.bats` with one test: `@test "bats runs" { run true; [ "$status" -eq 0 ]; }`.
- [ ] **Step 2:** Write `test/Dockerfile` (`FROM archlinux:latest`; `pacman -Syu --noconfirm bats shellcheck gum jq sudo git base-devel`; create `tester` with `NOPASSWD:ALL`; `USER tester`; `WORKDIR /nusku`) and `test/run-unit.sh`.
- [ ] **Step 3:** Run `bash test/run-unit.sh`. Expected: `1 test, 0 failures`, exit 0.
- [ ] **Step 4:** `.gitignore`: `test/screenshots/`, `*.log`, `.claude/`. Move wallpapers into `wallpapers/`. `README.md`: one paragraph on what Nusku is, the install command (`git clone … && cd nusku && ./install.sh`), and how to run tests.
- [ ] **Step 5:** Commit: `git add -A && git commit -m "chore: test harness, skeleton, starter wallpapers"`.

---

### Task 2: Logging and failure handling — `lib/log.sh`

**Files:** Create `lib/log.sh`, `test/unit/log.bats`

**Interfaces:**
- Produces:
  - `log_init` — sets `NUSKU_LOG` to `${XDG_STATE_HOME:-$HOME/.local/state}/nusku/install-$(date +%Y%m%d-%H%M%S).log` unless `NUSKU_LOG` already set; creates the dir.
  - `log_info MSG`, `log_warn MSG`, `log_error MSG` — timestamped line to the log; coloured line to stderr.
  - `step NAME` — sets `NUSKU_STEP=NAME` and logs `==> NAME`.
  - `run CMD ARGS...` — runs the command with stdout+stderr appended to the log (and shown on the terminal); on non-zero exit calls `die "command failed: CMD ARGS"`.
  - `die MSG` — prints `Nusku install failed during step: $NUSKU_STEP`, the message and `Full log: $NUSKU_LOG` to stderr, exits 1.

- [ ] **Step 1: Write failing tests** in `test/unit/log.bats`:
  - `log_init creates the log file under XDG_STATE_HOME` — `XDG_STATE_HOME=$BATS_TEST_TMPDIR`; after `log_init; log_info hi`, file matches `$BATS_TEST_TMPDIR/nusku/install-*.log` and contains `hi`.
  - `run passes through success` — `run_in_sub 'run true'` status 0.
  - `run failure names step, command and log` — `step "Install packages"; run false` → status 1, output contains `step: Install packages`, `command failed: false`, `Full log:`.
  - `run captures command output in log` — `run echo marker123` → log contains `marker123`.
  (bats' own `run` clashes with ours: in tests call ours via `bash -c 'source lib/log.sh; …'`.)
- [ ] **Step 2:** `bash test/run-unit.sh log` → FAIL (file missing).
- [ ] **Step 3:** Implement `lib/log.sh`. Use `set -o pipefail` and `tee -a` with `PIPESTATUS` to keep the exit code.
- [ ] **Step 4:** `bash test/run-unit.sh log` → all pass; shellcheck clean.
- [ ] **Step 5:** Commit `feat(lib): logging and fail-loud run()`.

---

### Task 3: Answers file and UI — `lib/answers.sh`, `lib/ui.sh`

**Files:** Create `lib/answers.sh`, `lib/ui.sh`, `test/unit/answers.bats`, `test/answers/container.answers`, `test/answers/vm.answers`

**Answers file format** (never `source`d; parsed line by line; `#` comments; `KEY=value`):
```
GPU=amd|intel|nvidia|hybrid-intel|hybrid-amd|vm
NVIDIA_MODULE=proprietary|open        # only when GPU is nvidia or hybrid-*
AUR_HELPER=paru|yay
ACCENT=blue                            # one of the 14 accents
APPS=                                  # space-separated app ids; empty in Stage 1
TEST_AUTOLOGIN=0|1                     # only honoured when GPU=vm
```
Saved to `${XDG_CONFIG_HOME:-$HOME/.config}/nusku/answers`.

**Interfaces:**
- Produces (`lib/answers.sh`): `answers_load FILE`, `answers_get KEY` (prints value, empty if unset), `answers_set KEY VALUE`, `answers_save FILE`, `answers_validate` (calls `die` naming the bad key and allowed values). Values held in associative array `NUSKU_ANSWERS`.
- Produces (`lib/ui.sh`): `ui_choose KEY PROMPT DEFAULT OPTION...`, `ui_confirm PROMPT` (0/1), `ui_checklist KEY PROMPT PRESELECTED_CSV OPTION...`. When `NUSKU_NONINTERACTIVE=1` or the key is already set in `NUSKU_ANSWERS`, they return the stored value without prompting (non-interactive with a missing key → `die "answers file missing KEY"`). Otherwise they call `gum choose` / `gum confirm` and store the result via `answers_set`.
- Consumes: `die` from Task 2.

- [ ] **Step 1: Write failing tests:**
  - `load/get round-trip` — file `GPU=vm\nACCENT=mauve` → `answers_get ACCENT` prints `mauve`.
  - `comments and blank lines ignored`.
  - `save then load reproduces values`.
  - `validate rejects unknown accent` — `ACCENT=purple` → status 1, output contains `ACCENT` and `rosewater`.
  - `validate rejects unknown GPU`.
  - `validate requires NVIDIA_MODULE for nvidia and hybrid-*`.
  - `value with = sign preserved` — `APPS=a=b` → `a=b`.
  - `file is not executed` — line `GPU=$(touch $BATS_TEST_TMPDIR/pwned)` → pwned file absent.
  - `ui_choose returns stored answer without gum` — `PATH` without gum, `NUSKU_NONINTERACTIVE=1`.
  - `ui_choose non-interactive missing key dies`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement both files. Write `container.answers` (`GPU=vm`, `AUR_HELPER=paru`, `ACCENT=blue`, `TEST_AUTOLOGIN=0`) and `vm.answers` (same with `TEST_AUTOLOGIN=1`).
- [ ] **Step 4:** Run → pass.
- [ ] **Step 5:** Commit `feat(lib): answers file and gum UI wrappers`.

---

### Task 4: Preflight — `lib/preflight.sh`

**Files:** Create `lib/preflight.sh`, `test/unit/preflight.bats`

**Interfaces:**
- Produces: `preflight_checks` (dies with a specific message for each: not Arch — no `/etc/arch-release` (path overridable via `NUSKU_ARCH_RELEASE` for tests); running as root (`EUID` 0); `sudo -v` fails; `curl -fsS --max-time 10 https://archlinux.org` fails → "no network"). `preflight_bootstrap` — `sudo pacman -Syu --needed --noconfirm gum jq git base-devel curl` (one `run` call, which does the full upgrade).
- Consumes: `die`, `run`, `step`.

- [ ] **Step 1: Failing tests** with stub `sudo`/`curl` scripts prepended to `PATH`: `fails when not Arch`, `fails as root` (run with `EUID` override via `NUSKU_EUID` test hook), `fails when sudo -v fails`, `fails with no network`, `passes when all ok`. Each asserts the specific message.
- [ ] **Step 2:** Run → FAIL.  **Step 3:** Implement.  **Step 4:** Run → pass.
- [ ] **Step 5:** Commit `feat(lib): preflight checks`.

---

### Task 5: Packages and AUR helper — `lib/packages.sh`, `packages/base.*`

**Files:** Create `lib/packages.sh`, `packages/base.pacman`, `packages/base.aur`, `test/unit/packages.bats`

**List format:** one package per line, `#` comments, inline comments allowed (`foo  # why`).

**`packages/base.pacman`** (repo packages; verify each name with `pacman -Si` in the container during Step 4):
hyprland hyprlock hypridle hyprpaper hyprpolkitagent xdg-desktop-portal-hyprland xdg-desktop-portal-gtk qt5-wayland qt6-wayland sddm waybar kitty rofi swaync cliphist wl-clipboard grim slurp hyprshot(→AUR if not in extra) pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol networkmanager network-manager-applet bluez bluez-utils blueman power-profiles-daemon thunar thunar-volman gvfs tumbler zsh starship fzf ripgrep fd bat eza zoxide btop fastfetch ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji adw-gtk-theme papirus-icon-theme kvantum qt6ct qt5ct brightnessctl playerctl imagemagick jq libnotify xdg-user-dirs

**`packages/base.aur`:** catppuccin-cursors-mocha, plus any of the above that turn out to be AUR-only.

**Interfaces:**
- Produces: `pkg_read_list FILE...` (prints package names, one per line, comments/blank stripped, deduped), `pkg_install_repo NAME...` (`run sudo pacman -S --needed --noconfirm`), `pkg_install_aur NAME...` (`run "$AUR_HELPER" -S --needed --noconfirm`), `aur_bootstrap HELPER` (skip if `command -v HELPER`; else clone `https://aur.archlinux.org/HELPER-bin.git` into a temp dir and `makepkg -si --noconfirm`).
- Consumes: `run`, `die`, `answers_get AUR_HELPER`.

- [ ] **Step 1: Failing tests:** `pkg_read_list strips comments and blanks`, `pkg_read_list merges and dedupes two files`, `pkg_install_repo calls pacman with --needed` (stub `sudo` records argv), `aur_bootstrap skips when helper present` (stub `paru` on PATH; `git` stub must not be called).
- [ ] **Step 2:** Run → FAIL.  **Step 3:** Implement + write lists.
- [ ] **Step 4:** Run → pass. Then in the container: `pkg_read_list packages/base.pacman | xargs pacman -Si >/dev/null` → exit 0 (move any failures to `base.aur` after confirming they exist on the AUR).
- [ ] **Step 5:** Commit `feat(lib): package lists and installers`.

---

### Task 6: GPU and GRUB — `lib/gpu.sh`, `lib/grub.sh`

**Files:** Create `lib/gpu.sh`, `lib/grub.sh`, `packages/gpu-*.pacman`, `test/unit/grub.bats`, `test/unit/gpu.bats`

**Decisions:**
- `gpu-amd`: mesa vulkan-radeon libva-mesa-driver. `gpu-intel`: mesa vulkan-intel intel-media-driver. `gpu-nvidia`: nvidia-dkms nvidia-utils egl-wayland libva-nvidia-driver linux-headers. `gpu-nvidia-open`: same with nvidia-open-dkms. Hybrid = integrated list + nvidia list + `nvidia-prime`.
- VM: `systemd-detect-virt` → `microsoft` → `gpu-vm-hyperv` (`hyperv`, enable `hv_kvp_daemon hv_vss_daemon`), `vmware` → `open-vm-tools` (enable `vmtoolsd`), `kvm|qemu` → `qemu-guest-agent`; all VMs also get `mesa`.
- NVIDIA/hybrid config: GRUB params `nvidia_drm.modeset=1 nvidia_drm.fbdev=1`; add `nvidia nvidia_modeset nvidia_uvm nvidia_drm` to `MODULES=()` in `/etc/mkinitcpio.conf`; `mkinitcpio -P`; `grub-mkconfig -o /boot/grub/grub.cfg`. If `/etc/default/grub` is missing, `log_warn` the params to add manually (don't die).
- Writes `~/.config/nusku/gpu.conf` (sourced by Hyprland): NVIDIA → `env = LIBVA_DRIVER_NAME,nvidia`, `env = __GLX_VENDOR_LIBRARY_NAME,nvidia`, `env = NVD_BACKEND,direct`; hybrid → nothing forcing NVIDIA (Hyprland on the iGPU; `prime-run` for apps); VM → `cursor { no_hardware_cursors = true }` and, for Hyper-V, `env = LIBGL_ALWAYS_SOFTWARE,1` and `env = WLR_RENDERER_ALLOW_SOFTWARE,1`; AMD/Intel → empty file with a comment.

**Interfaces:**
- Produces: `grub_add_params FILE PARAM...` (idempotent; edits `GRUB_CMDLINE_LINUX_DEFAULT` keeping existing params and quoting), `mkinit_add_modules FILE MOD...` (idempotent edit of `MODULES=(...)`), `gpu_suggest` (prints a suggested GPU answer from `lspci`/`systemd-detect-virt`, used as the gum default only), `gpu_package_lists GPU NVIDIA_MODULE VIRT` (prints list file paths), `gpu_hypr_conf GPU VIRT` (prints gpu.conf contents), `gpu_configure` (does it all using answers).
- Consumes: `answers_get`, `run`, `pkg_read_list`, `pkg_install_repo`.

- [ ] **Step 1: Failing tests:** `grub_add_params adds to empty default`, `… appends keeping existing "loglevel=3 quiet"`, `… is idempotent (twice → once)`, `mkinit_add_modules on MODULES=() and MODULES=(btrfs)`, `… idempotent`, `gpu_package_lists hybrid-intel open → intel + nvidia-open + prime`, `gpu_package_lists vm microsoft → vm-hyperv`, `gpu_hypr_conf vm microsoft contains no_hardware_cursors and LIBGL_ALWAYS_SOFTWARE`, `gpu_hypr_conf hybrid-amd does not set __GLX_VENDOR_LIBRARY_NAME`.
- [ ] **Step 2:** Run → FAIL.  **Step 3:** Implement.  **Step 4:** Run → pass; all `gpu-*.pacman` names pass `pacman -Si` in the container.
- [ ] **Step 5:** Commit `feat(lib): gpu drivers, grub and initramfs config`.

---

### Task 7: Dotfile linking — `lib/dotfiles.sh`, `config/links.txt`

**Files:** Create `lib/dotfiles.sh`, `config/links.txt`, `test/unit/dotfiles.bats`

**Manifest** (`config/links.txt`, `src dest`, `#` comments). Stage 1 entries: `config/hypr .config/hypr`, `config/waybar .config/waybar`, `config/swaync .config/swaync`, `config/rofi .config/rofi`, `config/kitty .config/kitty`, `config/btop .config/btop`, `config/fastfetch .config/fastfetch`, `config/starship.toml .config/starship.toml`, `config/zsh/zshrc .zshrc`, `config/gtk-3.0/gtk.css .config/gtk-3.0/gtk.css`, `config/gtk-4.0/gtk.css .config/gtk-4.0/gtk.css`, `config/Kvantum .config/Kvantum`, `config/qt6ct .config/qt6ct`, `config/qt5ct .config/qt5ct`, and each `scripts/nusku-*` → `.local/bin/nusku-*`.

**Interfaces:**
- Produces: `link_file SRC_ABS DEST_ABS BACKUP_DIR` — if DEST is a symlink to SRC: no-op. If DEST is a symlink whose `readlink` target ends with `/<repo-relative SRC>` (our own link from a moved or re-cloned repo): replace without backup. Otherwise if DEST exists: move to `BACKUP_DIR/<dest relative to HOME>`. Then `mkdir -p` parent and `ln -s`. `deploy_dotfiles REPO_ROOT` — reads the manifest, backup dir `~/.local/state/nusku/backup-<timestamp>` created only if something is backed up.
- Consumes: `log_info`, `die`.

- [ ] **Step 1: Failing tests** (HOME=`$BATS_TEST_TMPDIR/home`): `links a new file`, `backs up an existing regular file`, `backs up an existing directory`, `existing correct link is a no-op and creates no backup dir`, `link from an old repo path is replaced without backup`, `foreign symlink is backed up`, `creates missing parent dirs`, `manifest comments ignored`.
- [ ] **Step 2:** Run → FAIL.  **Step 3:** Implement.  **Step 4:** Run → pass.
- [ ] **Step 5:** Commit `feat(lib): manifest-driven dotfile linking with backups`.

---

### Task 8: Palette and theme rendering — `theme/`, `lib/theme.sh`, `scripts/nusku-theme`

**Files:** Create `theme/palette.conf`, `lib/theme.sh`, `theme/templates/{hypr-colors.conf,colors.css,colors.rasi,hyprlock-colors.conf,gtk.css,kitty-accent.conf}.tmpl`, `scripts/nusku-theme`, `test/unit/theme.bats`

**Palette:** Mocha `name=hex` (no `#`) for all 26 colours, copied from catppuccin/palette `palette.json` (record the commit in a header comment). Values to spot-check: `blue=89b4fa`, `base=1e1e2e`, `mantle=181825`, `crust=11111b`, `text=cdd6f4`, `surface0=313244`, `mauve=cba6f7`.

**Template syntax:** `{{name}}` → hex without `#`; `{{accent}}` → the chosen accent's hex; `{{name_rgb}}` → `r, g, b` decimal (for CSS `rgba()`), also `{{accent_rgb}}`. Unknown placeholder → `die`.

**Interfaces:**
- Produces: `theme_load PALETTE_FILE ACCENT` (fills assoc array `NUSKU_COLORS`, adds `accent`), `theme_render TEMPLATE OUT`, `theme_render_all REPO_ROOT` (renders every `theme/templates/*.tmpl` to `${XDG_CONFIG_HOME:-$HOME/.config}/nusku/theme/<name without .tmpl>`, accent from answers). `scripts/nusku-theme ACCENT` — validates accent, updates the saved answers, re-renders, runs `hyprctl reload`, restarts waybar and swaync (`pkill -SIGUSR2 waybar`; `swaync-client -rs`).
- Consumes: `answers_get ACCENT`, `answers_set`, `answers_save`, `die`.

- [ ] **Step 1: Failing tests:** `palette has 26 colours`, `blue is 89b4fa`, `render replaces {{base}} and {{accent}}` (accent mauve → `cba6f7`), `render {{accent_rgb}} → 137, 180, 250 for blue`, `unknown placeholder dies naming it`, `render_all writes every template output` (count matches).
- [ ] **Step 2:** Run → FAIL.  **Step 3:** Implement palette, lib, templates (templates hold only colour definitions in each app's syntax: Hyprland `$accent = rgb(...)` vars, CSS `@define-color`, rasi `* { accent: #...; }`, etc.), and `nusku-theme`.
- [ ] **Step 4:** Run → pass.
- [ ] **Step 5:** Commit `feat(theme): single palette and templated colour files`.

---

### Task 9: Hyprland configs

**Files:** Create `config/hypr/hyprland.conf` and split files `config/hypr/{env,monitors,input,looks,animations,keybinds,rules,autostart}.conf`, `config/hypr/hypridle.conf`, `config/hypr/hyprlock.conf`, `config/hypr/hyprpaper.conf`

**Before writing:** check the installed Hyprland and hyprpaper versions in the container (`pacman -Si hyprland hyprpaper`) and read the current wiki syntax for those versions (config syntax for window rules and hyprpaper changed in 2025; follow what the installed versions accept).

**Decisions:**
- `hyprland.conf` only `source`s the split files plus `~/.config/nusku/theme/hypr-colors.conf`, `~/.config/nusku/gpu.conf`, and `~/.config/nusku/local.conf` (per-machine overrides; installer creates it empty with a comment if missing).
- `monitors.conf`: `monitor = , preferred, auto, auto`.
- Borders: active = `$accent`, inactive = `$surface0`; gaps 5/10; rounding 10; blur on; animations short (≤ 300 ms feel).
- Autostart: waybar, swaync, hyprpaper, hypridle, hyprpolkitagent (`systemctl --user start hyprpolkitagent`), `wl-paste --type text --watch cliphist store`, `wl-paste --type image --watch cliphist store`, `nusku-wallpaper restore`, nm-applet, blueman-applet.
- Hypridle: dim at 5 min, lock at 10 min, screen off at 11 min, suspend never (laptop users can add it in local.conf). Hyprlock: wallpaper from `~/.local/state/nusku/current-wallpaper` (blurred), clock, input field coloured from the palette (source `hyprlock-colors.conf`).
- Window rules: float pavucontrol, blueman-manager, nm-connection-editor, file-chooser portal dialogs; idle-inhibit on fullscreen.

**Keybinds (new set; `$mod = SUPER`):**

| Keys | Action |
|---|---|
| mod+Return | kitty |
| mod+Space | rofi app launcher |
| mod+Q | close window |
| mod+E | Thunar |
| mod+V | clipboard menu |
| mod+W | wallpaper picker |
| mod+Escape | power menu |
| mod+L | lock (hyprlock) |
| mod+N | toggle SwayNC panel |
| mod+F | fullscreen |
| mod+T | toggle floating |
| mod+P | pseudo-tile |
| mod+J | toggle split |
| mod+arrows | move focus |
| mod+Shift+arrows | move window |
| mod+Ctrl+arrows | resize |
| mod+1…0 | workspace 1–10 |
| mod+Shift+1…0 | move window to workspace 1–10 |
| mod+mouse drag L/R | move / resize |
| mod+scroll | cycle workspaces |
| Print | hyprshot region → clipboard + ~/Pictures/Screenshots |
| Shift+Print | hyprshot window |
| Ctrl+Print | hyprshot output |
| XF86 audio/brightness/media | wpctl / brightnessctl / playerctl |

- [ ] **Step 1:** Write the configs.
- [ ] **Step 2: Verify** in the container after Task 14's install (or by installing hyprland there now): `Hyprland --verify-config -c ~/.config/hypr/hyprland.conf` → `config ok`. (If the installed version lacks `--verify-config`, record that and rely on the VM run in Task 16.)
- [ ] **Step 3:** Commit `feat(config): hyprland, hypridle, hyprlock, hyprpaper`.

---

### Task 10: Wallpaper script and Rofi menus

**Files:** Create `scripts/nusku-wallpaper`, `scripts/nusku-menu-power`, `scripts/nusku-menu-clipboard`, `scripts/nusku-menu-wallpaper`, `config/rofi/config.rasi`, `config/rofi/nusku.rasi`, `test/unit/wallpaper.bats`

**Decisions:**
- Wallpaper state: `~/.local/state/nusku/wallpapers` with lines `MONITOR=/abs/path` and `*=/abs/path` (all monitors). `~/.local/state/nusku/current-wallpaper` symlink → the `*` image (or the first monitor's), used by Hyprlock.
- SDDM background: `/var/lib/nusku/sddm-background` — directory created by the installer owned by the user, mode 755; the script copies the `*` image there as `background.<ext>` and updates a `background` symlink so SDDM's theme.conf can point at a fixed path.
- Default wallpaper when no state exists: `wallpapers/space.png` (builder's pick; change freely).
- Display mode: fill/cover via hyprpaper (current hyprpaper's fit mode `cover`), preloading only images in use.
- Rofi theme: Catppuccin's official rofi port for Mocha (vendored with source line), with the accent colour imported from `~/.config/nusku/theme/colors.rasi`.
- Power menu entries: Lock, Logout, Suspend, Reboot, Shutdown (confirm on Reboot/Shutdown).
- Wallpaper picker: rofi with image thumbnails from `wallpapers/` (repo path resolved via the script's own symlink target), then a second rofi asking "All monitors" or a monitor name from `hyprctl monitors -j`.

**Interfaces:**
- Produces: `nusku-wallpaper set FILE [MONITOR|all]`, `nusku-wallpaper restore`, `nusku-wallpaper list`. Hyprpaper calls go through one function `_apply MONITOR FILE` so tests can stub `hyprctl`.

- [ ] **Step 1: Failing tests** (stub `hyprctl` logs argv; `HOME` tmp; `NUSKU_SDDM_BG_DIR` override): `set all writes *= line and current-wallpaper link`, `set one monitor keeps the * line`, `restore applies each saved line`, `restore with no state uses the default`, `set with missing file fails with message`, `set all copies to sddm background dir`.
- [ ] **Step 2:** Run → FAIL.  **Step 3:** Implement scripts and rofi config.
- [ ] **Step 4:** Run → pass; shellcheck clean.
- [ ] **Step 5:** Commit `feat(scripts): wallpaper state and rofi menus`.

---

### Task 11: Waybar and SwayNC

**Files:** Create `config/waybar/config.jsonc`, `config/waybar/style.css`, `config/swaync/config.json`, `config/swaync/style.css`

**Decisions:**
- Waybar top bar. Left: workspaces, window title. Centre: clock (click → calendar tooltip). Right: tray, pulseaudio (click → pavucontrol), network (click → nm-connection-editor), bluetooth (click → blueman-manager), battery (hidden automatically when no battery), notifications (custom module using `swaync-client -swb`, click → `swaync-client -t -sw`).
- CSS starts with the official Catppuccin Waybar Mocha colours via `@import "../nusku/theme/colors.css";` (path relative to `~/.config/waybar/`), accent for active workspace and module highlights.
- SwayNC style from the official Catppuccin swaync Mocha theme (vendored, source line), accent from `colors.css`.

- [ ] **Step 1:** Write configs.
- [ ] **Step 2: Verify:** strip comments and `jq . config.jsonc` → valid; `jq . config/swaync/config.json` → valid. Visual check in Task 16.
- [ ] **Step 3:** Commit `feat(config): waybar and swaync`.

---

### Task 12: Terminal, shell, toolkits, cursors

**Files:** Create `config/kitty/kitty.conf` (+ vendored `config/kitty/mocha.conf`), `config/zsh/zshrc`, `config/starship.toml`, `config/btop/btop.conf` (+ vendored `config/btop/themes/catppuccin_mocha.theme`), `config/fastfetch/config.jsonc`, `config/gtk-3.0/gtk.css`, `config/gtk-4.0/gtk.css`, `config/Kvantum/kvantum.kvconfig` (+ vendored Catppuccin Mocha Kvantum theme for the chosen accent), `config/qt5ct/qt5ct.conf`, `config/qt6ct/qt6ct.conf`

**Decisions:**
- Kitty: JetBrains Mono Nerd Font 11, Catppuccin Mocha from the official port, `include ~/.config/nusku/theme/kitty-accent.conf` for cursor/selection/active-tab accent.
- zshrc: history settings, completion, `fzf` key bindings, `zoxide init zsh`, `starship init zsh`, aliases `ls=eza`, `cat=bat --paging=never`; sources `~/.config/nusku/local.zsh` if present. No plugin manager.
- Starship: the official Catppuccin Mocha preset (`starship preset catppuccin-powerline` output, palette set to `catppuccin_mocha`).
- GTK: base `adw-gtk3-dark` set with `gsettings set org.gnome.desktop.interface gtk-theme adw-gtk3-dark`, `color-scheme prefer-dark`, `icon-theme Papirus-Dark`, `cursor-theme catppuccin-mocha-<accent>-cursors` (falls back to `-dark-` if the accent variant isn't packaged), `font-name 'Noto Sans 11'`. `gtk.css` files `@import` the rendered `~/.config/nusku/theme/gtk.css`.
- Qt: `QT_QPA_PLATFORMTHEME=qt6ct` in `env.conf`; qt5ct/qt6ct style `kvantum`; Kvantum theme `catppuccin-mocha-<accent>`.
- Cursor: `env = XCURSOR_THEME,…`, `env = XCURSOR_SIZE,24`, `env = HYPRCURSOR_SIZE,24` in `env.conf` — theme name written into `~/.config/nusku/theme/` by a template so it follows the accent.

- [ ] **Step 1:** Write configs; add vendored files with source lines.
- [ ] **Step 2: Verify:** `zsh -n config/zsh/zshrc` → no output; `starship config` loads without error (`STARSHIP_CONFIG=config/starship.toml starship prompt` exit 0) in the container.
- [ ] **Step 3:** Commit `feat(config): kitty, zsh, starship, btop, gtk, qt`.

---

### Task 13: SDDM and system setup — `lib/system.sh`, `sddm/`

**Files:** Create `lib/system.sh`, `sddm/10-nusku.conf`, `sddm/20-autologin.conf.tmpl`, `sddm/theme.conf.user.tmpl`, `test/unit/system.bats`

**Decisions:**
- Theme: official catppuccin/sddm release zip `catppuccin-mocha-<accent>-sddm.zip`, version pinned in `lib/system.sh` (`SDDM_THEME_VERSION`), extracted to `/usr/share/sddm/themes/catppuccin-mocha-<accent>`. Requires `qt6-svg qt6-declarative` (add to `base.pacman`).
- `theme.conf.user` (rendered): `CustomBackground=true`, `Background=/var/lib/nusku/sddm-background/background`, font JetBrains Mono. Confirm the theme's QML uses `fillMode: Image.PreserveAspectCrop`; if not, patch the extracted `Main.qml` with a single `sed` and log it.
- `/etc/sddm.conf.d/10-nusku.conf`: `[Theme] Current=catppuccin-mocha-<accent>`, `[General] DisplayServer=wayland` only if the installed SDDM version supports a Wayland greeter cleanly; otherwise leave X11 greeter (builder verifies; X11 greeter is the safe default).
- `20-autologin.conf` written only when `GPU=vm` and `TEST_AUTOLOGIN=1`: `[Autologin] User=<user> Session=hyprland`. Removed if present and conditions are not met.
- Services: system — `sddm NetworkManager bluetooth power-profiles-daemon` (+ VM daemons from Task 6); user — `pipewire pipewire-pulse wireplumber` via `sudo systemctl --global enable` (works without a running session or user bus; these are usually enabled by Arch presets already, so this is a safety net).
- Login shell: `chsh -s /usr/bin/zsh` via `sudo chsh -s /usr/bin/zsh "$USER"` if not already zsh.
- `xdg-user-dirs-update`; create `~/Pictures/Screenshots`.

**Interfaces:**
- Produces: `sddm_install_theme ACCENT`, `sddm_write_config ACCENT GPU TEST_AUTOLOGIN` (writes to `${NUSKU_ETC:-/etc}` so tests can redirect), `services_enable`, `shell_set_zsh`, `system_configure` (calls all; uses answers).
- Consumes: `run`, `answers_get`, `theme_render`.

- [ ] **Step 1: Failing tests** (`NUSKU_ETC` tmp, `sudo` stub that runs the command without sudo): `writes theme conf with accent`, `autologin written only for vm + TEST_AUTOLOGIN=1`, `autologin removed when GPU is not vm`, `shell_set_zsh skips when already zsh` (stub `getent`).
- [ ] **Step 2:** Run → FAIL.  **Step 3:** Implement.  **Step 4:** Run → pass.
- [ ] **Step 5:** Commit `feat(lib): sddm theme, autologin, services, shell`.

---

### Task 14: `install.sh` orchestration, update mode, container install test

**Files:** Create `install.sh`, `scripts/nusku-update`, `test/run-container-install.sh`

**Flags:** `--answers FILE` (load and run non-interactively), `--update` (reuse saved answers; skip questions; still runs every step idempotently), `--reconfigure` (ask questions again even if saved), `--no-reboot`, `-h/--help`.

**Step order** (each wrapped in `step`): Preflight → Questions (GPU with `gpu_suggest` default; NVIDIA module if needed; AUR helper default paru; accent default blue; validate; save) → AUR helper → Packages (base + GPU lists, repo then AUR) → GPU config → Theme render → Dotfiles → Local files (create `~/.config/nusku/local.conf`, `/var/lib/nusku/sddm-background` owned by user, initial `nusku-wallpaper set <default> all` without hyprctl if Hyprland isn't running) → System (SDDM, services, shell) → Summary (GPU, accent, log path, backup dir if any) → Reboot prompt (skipped with `--no-reboot` or in non-interactive mode).

`nusku-update`: `git -C <repo> pull --ff-only` then `<repo>/install.sh --update`.

**Container install test** (`test/run-container-install.sh`): runs the `nusku-test` image as `tester` with `NUSKU_NONINTERACTIVE=1`, `./install.sh --answers test/answers/container.answers --no-reboot`, then runs it a second time, then asserts: exit 0 both times; `~/.config/hypr` is a symlink into `/nusku`; `~/.config/nusku/theme/colors.css` contains `89b4fa`; no `backup-*` dir created by the second run; `pacman -Q hyprland waybar sddm` succeeds; `Hyprland --verify-config` passes if supported. Systemd isn't running in the container: `services_enable` must use `systemctl enable` (works offline) and tolerate `systemctl --user` absence with a warning.

- [ ] **Step 1:** Write `test/run-container-install.sh` with the assertions above.
- [ ] **Step 2:** Run it → FAIL (no install.sh).
- [ ] **Step 3:** Implement `install.sh` and `nusku-update`. `install.sh` resolves `REPO_ROOT` from `${BASH_SOURCE[0]}` with `realpath`, sets `set -Eeuo pipefail`, an `ERR` trap that calls `die`, and sources `lib/*.sh`.
- [ ] **Step 4:** Run `bash test/run-container-install.sh` → all assertions pass. Fix package names, missing deps and config errors it surfaces.
- [ ] **Step 5:** `bash test/run-unit.sh` → all pass.
- [ ] **Step 6:** Commit `feat: install.sh orchestration, update mode, container install test`.

---

### Task 15: Hyper-V test VM

**Files:** Create `test/hyperv/New-NuskuVM.ps1`, `test/hyperv/README.md`

**Decisions:**
- Requires an elevated PowerShell or membership in "Hyper-V Administrators" (the current user isn't a member yet — README says how to add: `Add-LocalGroupMember -Group "Hyper-V Administrators" -Member $env:USERNAME`, then sign out/in).
- `New-NuskuVM.ps1 -IsoPath <arch.iso> [-Name nusku-test] [-MemoryGB 8] [-Cpus 4] [-DiskGB 60]`: Gen 2, Secure Boot off, Default Switch, dynamic VHDX under the Hyper-V default path, DVD attached and first in boot order, checkpoint type Standard.
- README walks the owner through the manual base install in the VM: `archinstall` with GRUB, ext4, user `tester` with sudo, packages `openssh git`, NetworkManager, then `systemctl enable sshd`, copy the host's SSH public key into `~/.ssh/authorized_keys`, shut down, and `Checkpoint-VM -Name nusku-test -SnapshotName clean-arch`.

- [ ] **Step 1:** Write script and README.
- [ ] **Step 2: Verify:** run `New-NuskuVM.ps1` with the owner's ISO (owner downloads the ISO; ask for its path) → `Get-VM nusku-test` shows Gen 2, Secure Boot off. Owner completes the base install and checkpoint per README.
- [ ] **Step 3:** Commit `test: hyper-v vm creation and base install guide`.

---

### Task 16: Hyper-V test loop and first full run

**Files:** Create `test/hyperv/Invoke-NuskuTest.ps1`

**Behaviour:** `Invoke-NuskuTest.ps1 [-Name nusku-test] [-User tester] [-KeepRunning]`:
1. `Stop-VM -TurnOff` if running; `Restore-VMCheckpoint -Name clean-arch -Confirm:$false`; `Start-VM`.
2. Wait (timeout 180 s) for an IPv4 from `(Get-VMNetworkAdapter -VMName $Name).IPAddresses`, then for port 22.
3. Package the working tree including uncommitted changes (`git ls-files -co --exclude-standard` → `tar`), `scp` to `~/nusku`, extract.
4. `ssh` run `cd ~/nusku && NUSKU_NONINTERACTIVE=1 ./install.sh --answers test/answers/vm.answers --no-reboot`; capture exit code; copy the install log to `test/screenshots/<timestamp>/install.log`.
5. `ssh sudo reboot`; wait for SSH again; wait for autologin (poll `pgrep -x Hyprland`, timeout 120 s).
6. Check: `systemctl is-active sddm NetworkManager bluetooth power-profiles-daemon`, `pgrep -x waybar`, `pgrep -x swaync`, `pgrep -x hyprpaper`; print a pass/fail table.
7. Screenshot: `ssh` run `export XDG_RUNTIME_DIR=/run/user/$(id -u); export WAYLAND_DISPLAY=$(basename $(ls $XDG_RUNTIME_DIR/wayland-* | grep -v lock | head -1)); grim /tmp/shot.png`, `scp` back to `test/screenshots/<timestamp>/desktop.png`. Also open the rofi launcher via `hyprctl dispatch exec rofi -show drun`, wait 2 s, screenshot `rofi.png`.
8. Exit non-zero if install or any check failed.

- [ ] **Step 1:** Write the script.
- [ ] **Step 2: Run** `powershell -File test/hyperv/Invoke-NuskuTest.ps1`. Expected: install exit 0, all checks pass, screenshots present. Inspect the screenshots against the spec (accent borders, Waybar modules, wallpaper fills screen, rofi themed).
- [ ] **Step 3:** If Hyprland can't render on Hyper-V: record what failed, keep steps 1–6 as the loop, and tell the owner (per spec, ask before installing any other hypervisor).
- [ ] **Step 4:** Fix what the run shows; re-run until clean. Each fix gets its own commit.
- [ ] **Step 5:** Commit `test: hyper-v test loop`.
