# Nusku Stage 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The installer offers the optional app groups (Dev, Everyday, Media, Creative, Gaming, System tools) and a language picker inside Dev, installs what was picked (with per-app setup such as Docker, UFW, Snapper), and ships a LazyVim-based Neovim config whose language extras follow the picked languages.

**Architecture:** One catalogue file (`packages/apps.list`) describes groups, apps and languages and their package sources (`name` = repo, `aur:name`, `flatpak:id`). `lib/apps.sh` parses it, runs the picker (gum), turns the saved `APPS`/`LANGS` answers into package batches and runs per-app setup hooks. Repo packages join the existing single pacman call (fatal on failure); optional AUR and Flatpak installs run per app and are soft — failures are collected and shown in the summary. Neovim is the LazyVim starter (lazy.nvim, committed `lazy-lock.json`); the installer writes `~/.config/nusku/nvim-languages.lua`, which turns on one LazyVim language extra per picked language, and runs Neovim headless once so plugins, Mason tools and treesitter parsers are installed before first launch.

**Tech Stack:** Bash 5, gum, bats + shellcheck in the `nusku-test` container, Neovim 0.12, LazyVim (lazy.nvim, Mason, language extras), catppuccin/nvim, Yazi flavors, Hyper-V loop.

**Spec:** `docs/superpowers/specs/2026-10-27-nusku-design.md` (§4 Stage 2, §5, §8 except ArtCraft, §9). Stage 1 plan for conventions: `docs/superpowers/plans/2026-10-27-nusku-stage1.md`.

## Global Constraints

- Everything in the Stage 1 plan's Global Constraints still holds (shellcheck clean, LF endings, backups before overwriting, idempotent, log everything, nothing from Omarchy).
- Package source preference: official repos > AUR > Flatpak (> vendor installer; none needed in Stage 2).
- Re-runs only add packages; never remove. **Exception:** selecting Rust replaces an installed `rust` package with `rustup` (they conflict); log it.
- ★ (pre-checked) apps, verbatim from spec §8: Neovim, GitHub CLI, Claude Code, Firefox, Discord, Obsidian, Spotify, VLC. Nothing else is pre-checked; no language is pre-checked.
- Gaming enables multilib. Snapper is offered only when `/` is btrfs; otherwise hidden in the picker and skipped with a log note if an answers file names it.
- Docker and UFW services enabled only if selected (spec §5 step 8).
- Claude desktop app is **not** offered: Anthropic's Linux build is Debian/Ubuntu-only beta and their docs point Arch users to the CLI (spec: "only if an official Linux build exists").
- A failed **base** install still stops the run (`run`). A failed **optional** AUR/Flatpak app or hook does not: `run_soft`, collected in `NUSKU_APP_FAILURES`, printed in red in the summary; exit status stays 0.
- Neovim is **LazyVim** (owner's choice), started from the upstream `LazyVim/starter` (Apache-2.0; keep its licence, add a `-- source: https://github.com/LazyVim/starter@<commit>` line). Not Omarchy's LazyVim setup. Versions pinned by the committed `config/nvim/lazy-lock.json`.
- Language tooling (LSP servers, formatters, linters) comes from LazyVim's Mason, as LazyVim intends; pacman installs only each language's runtime and package manager.

## Review Focus

1. **Update from a Stage 1 install** (saved answers have no `APPS`/`LANGS`, run with `--update`): must not die with "answers file missing APPS"; installs no optional apps and says how to add some (`./install.sh --apps`). → Task 2 test.
2. **One optional AUR build breaks** (e.g. `heroic-games-launcher-bin` fails): the rest of the apps, the dotfiles and the system step still run; summary lists the failed app; exit 0. → Task 3 test.
3. **Legacy NVIDIA + Steam**: must install `lib32-nvidia-580xx-utils` and `steam` in the same AUR-helper transaction and never pull `lib32-nvidia-utils` (it conflicts with the 580xx utils). → Task 3 test.
4. **Rust selected on a machine that already has `rust`** (the AUR-helper source build leaves `rust`/`cargo` installed): `pacman -S --noconfirm rustup` would refuse the conflict. Must swap via `--ask=4` and log it. → Task 3 test.
5. **Re-running with the same picks**: every hook (docker group, UFW rules, flathub remote, snapper config, Neovim sync) is a no-op or harmless the second time, no duplicate rules, no new backup dir. → Task 4 tests + Task 7 container second run.

---

## File Structure

```
packages/apps.list            catalogue: groups, apps (★, packages, flags), languages
lib/apps.sh                   catalogue parsing, validation, picker, package batches, hooks
lib/answers.sh                + LANGS key; APPS/LANGS validated via lib/apps.sh
lib/packages.sh               + pkg_enable_multilib, pkg_install_flatpak
install.sh                    + --apps flag, app picker in Questions, optional installs, hooks, summary
config/nvim/                  LazyVim starter: init.lua, lua/config/*.lua, lua/plugins/*.lua, lazy-lock.json
config/yazi/                  yazi.toml, flavors/catppuccin-mocha.yazi/ (vendored)
config/hypr/keybinds.lua      + SUPER+SHIFT+E → Yazi when installed
config/links.txt              + nvim, yazi
theme/templates/nvim-accent.lua.tmpl
theme/templates/home/.config/yazi/theme.toml.tmpl
test/unit/apps.bats           catalogue, validation, picker, batches, hooks
test/check-packages.sh        every catalogue package exists (repo/AUR RPC/Flathub), network
test/answers/container.answers, test/answers/vm-full.answers
test/run-container-install.sh + optional-apps assertions
test/hyperv/Invoke-NuskuTest.ps1  + -Answers param, optional-app checks, Neovim screenshot
README.md                     groups, --apps, languages
```

---

### Task 1: Catalogue, parsing and validation

**Files:**
- Create: `packages/apps.list`, `lib/apps.sh`, `test/unit/apps.bats`, `test/check-packages.sh`
- Modify: `lib/answers.sh` (add `LANGS` to `_NUSKU_ANSWER_KEYS`; `answers_validate` calls `apps_validate_answers` when it is defined), `install.sh` (source `lib/apps.sh` before `answers_validate` can run)

**Interfaces:**
- Produces (`lib/apps.sh`; `NUSKU_APPS_LIST` defaults to `$NUSKU_ROOT/packages/apps.list`):
  - `apps_groups` → group ids in file order, one per line.
  - `apps_group_label GROUP` → label.
  - `apps_in_group GROUP` → app ids in file order (excludes `btrfs`-flagged apps unless `apps_root_is_btrfs`).
  - `apps_label ID` → label (apps and languages).
  - `apps_starred` → space-separated ★ app ids.
  - `apps_langs` → language ids in file order.
  - `apps_packages ID` → that app's/language's package tokens, one per line.
  - `apps_has_flag ID FLAG` → status 0/1.
  - `apps_root_is_btrfs` → status 0 if `${NUSKU_ROOT_FSTYPE:-$(findmnt -no FSTYPE /)}` is `btrfs`.
  - `apps_validate_answers` → dies on any unknown id in `APPS` or `LANGS` (`answers: unknown app 'x' in APPS; see packages/apps.list`).

**Catalogue format** (`|`-separated, `#` comments):

```
group|<id>|<label>
app|<group>|<id>|<* or ->|<label>|<tokens space-separated>|<flags comma-separated or empty>
lang|<id>|<label>|<tokens>|<flags>
```

Tokens: `name` (repo), `aur:name`, `flatpak:app.id`. Flags: `multilib`, `gpu32` (add the GPU's 32-bit Vulkan driver), `btrfs`. Labels contain no `,` or `|` (gum `--selected` is comma-separated).

Contents (ids and packages decided by the research on 2026-10-28):

| group | id | ★ | label | tokens | flags |
|---|---|---|---|---|---|
| dev (Dev) | neovim | * | Neovim (LazyVim) | `neovim tree-sitter-cli wl-clipboard unzip lazygit fd ripgrep` | |
| | gh | * | GitHub CLI | `github-cli` | |
| | claude-code | * | Claude Code | `aur:claude-code` | |
| | lazygit | - | lazygit | `lazygit` | |
| | docker | - | Docker + Compose | `docker docker-compose docker-buildx` | |
| | vscode | - | VS Code | `aur:visual-studio-code-bin` | |
| everyday (Everyday) | firefox | * | Firefox | `firefox` | |
| | discord | * | Discord | `discord` | |
| | obsidian | * | Obsidian | `obsidian` | |
| | libreoffice | - | LibreOffice | `libreoffice-fresh` | |
| | thunderbird | - | Thunderbird | `thunderbird` | |
| | bitwarden | - | Bitwarden | `flatpak:com.bitwarden.desktop` | |
| | zathura | - | Zathura | `zathura zathura-pdf-mupdf` | |
| | localsend | - | LocalSend | `aur:localsend-bin` | |
| media (Media) | spotify | * | Spotify | `spotify-launcher` | |
| | vlc | * | VLC | `vlc vlc-plugins-all` | |
| | obs | - | OBS Studio | `obs-studio` | |
| | audacity | - | Audacity | `audacity` | |
| creative (Creative) | gimp, krita, inkscape, kdenlive, blender | - | (names) | same as id | |
| gaming (Gaming) | steam | - | Steam | `steam` | multilib,gpu32 |
| | lutris | - | Lutris | `lutris wine winetricks` | |
| | heroic | - | Heroic Games Launcher | `aur:heroic-games-launcher-bin` | |
| | gamemode | - | GameMode | `gamemode lib32-gamemode` | multilib |
| | mangohud | - | MangoHud | `mangohud lib32-mangohud` | multilib |
| | protonup | - | ProtonUp-Qt | `aur:protonup-qt` | |
| | wine | - | Wine | `wine winetricks` | |
| system (System tools) | yazi | - | Yazi | `yazi ffmpeg 7zip poppler resvg chafa` | |
| | flatpak | - | Flatpak | `flatpak` | |
| | snapper | - | Snapper | `snapper snap-pac grub-btrfs inotify-tools` | btrfs |
| | gparted | - | GParted | `gparted` | |
| | ufw | - | UFW firewall | `ufw` | |

Languages (runtime + package manager only; LSP/formatter/parser come from LazyVim, Task 5): `python` Python `python uv` · `php` PHP `php composer` · `gdscript` GDScript (Godot) `godot` · `js` JavaScript/TypeScript `nodejs npm` · `rust` Rust `rustup` · `go` Go `go` · `cpp` C/C++ `clang cmake` · `csharp` C# `dotnet-sdk` · `java` Java `jdk25-openjdk maven gradle` · `lua` Lua `lua luarocks`.

The `neovim` app's tokens are `neovim tree-sitter-cli wl-clipboard unzip lazygit fd ripgrep` (LazyVim and Mason need `unzip`, `curl`, `git`, a C compiler and `tree-sitter-cli`; `curl git base-devel` are already bootstrapped).

- [ ] **Step 1: Write failing tests** in `test/unit/apps.bats` (use a small fixture catalogue via `NUSKU_APPS_LIST` for logic tests, the real file for content tests):
  - `apps_groups lists groups in file order` — real file → `dev everyday media creative gaming system`.
  - `apps_starred is exactly the spec's favourites` — `[ "$(apps_starred)" = "neovim gh claude-code firefox discord obsidian spotify vlc" ]`.
  - `apps_packages splits tokens` — `steam` → `steam`; `bitwarden` → `flatpak:com.bitwarden.desktop`.
  - `snapper hidden on ext4, shown on btrfs` — `NUSKU_ROOT_FSTYPE=ext4 apps_in_group system` lacks `snapper`; `=btrfs` has it.
  - `apps_validate_answers rejects an unknown app` — `APPS='firefox nope'` → status 1, output contains `unknown app 'nope'`.
  - `apps_validate_answers rejects an unknown language` — `LANGS='python cobol'` → `unknown language 'cobol'`.
  - `empty APPS and LANGS are valid`.
  - `every app and language has a label and at least one package`.
  - `no label contains a comma or pipe`.
  - `catalogue ids are unique across apps and languages`.
- [ ] **Step 2:** `bash test/run-unit.sh apps` → FAIL (lib missing).
- [ ] **Step 3:** Write `packages/apps.list` and `lib/apps.sh` (parse with `awk -F'|'`; never `source` the catalogue). Add `LANGS` to answers; wire `apps_validate_answers` into `answers_validate`.
- [ ] **Step 4:** `bash test/run-unit.sh apps` and `bash test/run-unit.sh answers` → pass; shellcheck clean.
- [ ] **Step 5:** Write `test/check-packages.sh` (runs in the `nusku-test` container with network, like `run-container-install.sh`): repo tokens checked in one `pacman -Sl core extra multilib`-backed lookup after enabling multilib in the throwaway container (`pkg_enable_multilib` is Task 3, so here use the sed one-liner directly); `aur:` tokens via one AUR RPC v5 `info` call (`arg[]=` per name), failing on missing names and printing `OutOfDate` ones as warnings; `flatpak:` ids via `https://flathub.org/api/v2/appstream/<id>` (HTTP 200). Also covers the GPU lib32 names from Task 3 (`lib32-mesa lib32-vulkan-radeon lib32-vulkan-intel lib32-vulkan-swrast lib32-nvidia-utils`, AUR `lib32-nvidia-580xx-utils`). Run it: `bash test/check-packages.sh` → `ALL PACKAGES FOUND`. Fix any name it rejects in the catalogue (and note it in the commit message).
- [ ] **Step 6:** Commit `feat(apps): app and language catalogue with validation`.

---

### Task 2: Picker, `--apps`, and answers without apps

**Files:**
- Modify: `lib/apps.sh`, `install.sh`, `test/unit/apps.bats`, `test/unit/install.bats`

**Interfaces:**
- Consumes: Task 1 functions; `ui_checklist`-style gum use from `lib/ui.sh`.
- Produces:
  - `apps_ask` — interactive picker; sets `APPS` and `LANGS` in `NUSKU_ANSWERS`. Starting selection: the stored `APPS`/`LANGS` if the key exists, else `apps_starred` / empty.
  - `install.sh --apps` — loads saved answers (required; dies like `--update` without them), re-runs only `apps_ask`, then the normal full run. Rejected together with `--update`, `--answers` or `--reconfigure` (exit 2).
  - Non-interactive with no `APPS`/`LANGS` keys → both treated as empty; one `log_info` line: `No optional apps selected (add some with ./install.sh --apps)`.

**Picker flow** (gum):
1. `gum choose --header "Optional apps — pick a group to change, then Done"` over lines `Dev (3/6)`, `Everyday (3/8)`, …, `Done`.
2. Choosing a group: `gum choose --no-limit --header "<Group> — space toggles, ctrl+a selects all, enter confirms" --selected "<current labels csv>"` over that group's labels, ★ apps shown as `★ Label`. Map labels back to ids; replace that group's ids in the working selection. Esc/empty = no change for that group (not "deselect all").
3. After the Dev checklist, the language checklist (`Languages — runtimes, tools and Neovim support`) the same way.
4. `Done` stores `APPS` (catalogue order) and `LANGS`.
In interactive mode `step_questions` calls `apps_ask` when `APPS` is not stored (fresh install, Stage 1 machine, `--reconfigure`) or when `--apps` was given.

- [ ] **Step 1: Write failing tests.** Fake `gum` in `$BATS_TEST_TMPDIR/bin` that pops its reply from a script file (one reply per call; record each call's args to a file):
  - `fresh picker defaults to the starred apps` — replies: `Done` → `APPS` = the 8 ★ ids, `LANGS` empty.
  - `opening Media and unticking Spotify` — replies: `Media (2/4)`, `★ VLC`, `Done` → `APPS` has `vlc`, not `spotify`; others unchanged.
  - `Dev opens the language picker` — replies: `Dev (3/6)`, `★ Neovim`, `Python\nRust`, `Done` → `LANGS='python rust'`, `APPS` contains `neovim` but not `gh`.
  - `Esc in a group keeps its selection` — fake gum exits 130 for the group checklist → group's apps unchanged.
  - `re-asking starts from saved picks` — stored `APPS='gimp'`; first group-menu call shows `Creative (1/5)` and `Dev (0/6)`.
  - `snapper not offered on ext4` — `NUSKU_ROOT_FSTYPE=ext4`, open System → the recorded checklist args do not contain `Snapper`.
  - `install.sh --apps with --update exits 2` and `--apps without saved answers dies before preflight` (reuse the stub pattern from `invalid --answers dies before preflight`).
  - `non-interactive without APPS installs no optional apps` — `apps_selected_or_empty` returns empty and logs the `--apps` hint, no die.
- [ ] **Step 2:** `bash test/run-unit.sh apps` → new tests FAIL.
- [ ] **Step 3:** Implement `apps_ask`, the `--apps` flag (usage text: `--apps  Change which optional apps and languages are installed, then re-apply.`), and the non-interactive default. Log the final selection: `Apps: …` / `Languages: …`.
- [ ] **Step 4:** `bash test/run-unit.sh apps && bash test/run-unit.sh install` → pass.
- [ ] **Step 5:** Commit `feat(apps): group picker, language picker and --apps`.

---

### Task 3: Installing the picks

**Files:**
- Modify: `lib/apps.sh`, `lib/packages.sh`, `install.sh` (`step_packages`, `step_summary`), `test/unit/apps.bats`, `test/unit/packages.bats`

**Interfaces:**
- Consumes: Task 1/2; `gpu_*` from `lib/gpu.sh`; `backup_file`; `run`, `run_soft`.
- Produces:
  - `apps_gpu32 GPU NVIDIA_MODULE` → tokens: amd `lib32-mesa lib32-vulkan-radeon`; intel `lib32-mesa lib32-vulkan-intel`; nvidia+open `lib32-nvidia-utils`; nvidia+proprietary `aur:lib32-nvidia-580xx-utils`; hybrid-intel / hybrid-amd = the iGPU set + the NVIDIA set; vm `lib32-mesa lib32-vulkan-swrast`.
  - `apps_batches GPU NVIDIA_MODULE` → reads `APPS`/`LANGS`, skips `btrfs` apps on non-btrfs roots (`log_info "Skipping Snapper: / is not btrfs"`), prints lines `repo NAME`, `aur APP_ID NAME`, `flatpak APP_ID ID`. If any `gpu32` app is selected, appends `apps_gpu32`; if that includes an `aur:` token, the `gpu32` app's own repo packages move to its `aur` lines (one helper transaction, Review Focus 3). Adds `repo flatpak` when any flatpak token is present.
  - `apps_needs_multilib` → status 0 if any selected app has `multilib` or `gpu32`.
  - `pkg_enable_multilib` — if `/etc/pacman.conf` (`NUSKU_ETC` test hook) has no `^\[multilib\]`: `backup_file`, uncomment `#[multilib]` and its `Include` line (anchor `^#\[multilib\]$`, leaves `#[multilib-testing]` alone), append the block if absent, then `run sudo pacman -Syu --noconfirm` (no bare `-Sy`). No-op otherwise.
  - `pkg_flathub_remote` — `run_soft sudo flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo`.
  - `pkg_install_flatpak ID` — `run_soft sudo flatpak install --system -y --noninteractive flathub ID`.
  - `NUSKU_APP_FAILURES` — array of `"<label>: <what failed>"`; appended by optional installs and hooks.
- `step_packages` order: (multilib if needed) → one `pkg_install_repo` with base + GPU + optional repo names (fatal) → base AUR (fatal) → optional AUR, one `run_soft` helper call per app with all its AUR names (soft) → `pkg_flathub_remote` if any flatpak token → flatpaks per app (soft).
- Rust swap (Review Focus 4): when `rustup` is in the repo batch and `pacman -Qq rust` succeeds, install `rustup` first on its own with `run sudo pacman -S --needed --noconfirm --ask=4 rustup` and `log_warn "Replacing the rust package with rustup (needed for the Rust language option)"`; drop it from the main batch.
- Summary: after the existing lines, `Apps:` count and, if `NUSKU_APP_FAILURES` is non-empty, a red block `Not installed (see the log): …` and `Fix the cause and run ./install.sh --update to retry.`

- [ ] **Step 1: Write failing tests** (stub `sudo`, `pacman`, `paru`, `flatpak`, `findmnt` as in `packages.bats`):
  - `apps_gpu32` table above, one test per GPU value incl. hybrid-intel+proprietary → `lib32-mesa lib32-vulkan-intel aur:lib32-nvidia-580xx-utils`.
  - `steam on legacy nvidia goes through the AUR helper together with the driver` — `APPS=steam`, `GPU=nvidia NVIDIA_MODULE=proprietary` → batches contain `aur steam lib32-nvidia-580xx-utils` and `aur steam steam`; no `repo steam`; nothing named `lib32-nvidia-utils`.
  - `steam on amd stays in the repo batch` — `repo steam`, `repo lib32-vulkan-radeon`.
  - `bitwarden adds flatpak to the repo batch`.
  - `languages contribute packages` — `LANGS=python` → `repo python`, `repo uv`.
  - `pkg_enable_multilib uncomments only multilib` — fixture pacman.conf with `#[multilib-testing]` and `#[multilib]` blocks → only `[multilib]` + its Include uncommented; `pacman -Syu` called once; second call makes no change and no pacman call.
  - `pkg_enable_multilib appends the block when missing`.
  - `a failing optional AUR app is recorded and the run continues` — paru stub fails for `heroic-games-launcher-bin` → status 0, `NUSKU_APP_FAILURES` mentions `Heroic Games Launcher`, the next app's paru call still happens.
  - `rust is swapped for rustup with --ask=4` — pacman `-Qq rust` stub succeeds → calls contain `pacman -S --needed --noconfirm --ask=4 rustup`, and the main batch has no `rustup`.
  - `summary lists failed apps` — `step_summary` with one failure prints `Not installed` and the label (call via `install.sh` functions sourced in a subshell, or factor `summary_failures` into `lib/apps.sh` and test that).
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `bash test/run-unit.sh` (whole suite) → pass.
- [ ] **Step 5:** Commit `feat(apps): install selected apps; multilib, 32-bit drivers, soft optional installs`.

---

### Task 4: Per-app setup hooks

**Files:**
- Modify: `lib/apps.sh`, `install.sh` (new step `Apps setup` after `step_system`, before the summary), `test/unit/apps.bats`

**Interfaces:**
- Produces: `apps_run_hooks` — for each selected id (apps then languages) with a function `apps_hook_<id with - → _>` defined, call it; a hook failure (non-zero) appends to `NUSKU_APP_FAILURES` and continues. Hooks use `run_soft` and must be idempotent:
  - `apps_hook_docker`: `systemctl enable docker.service`; `usermod -aG docker "$USER"` only if not already in the group; summary note `You are in the docker group: that is root-equivalent. Log out and back in to use docker without sudo.`
  - `apps_hook_ufw`: `ufw default deny incoming`, `ufw default allow outgoing`, if `localsend` selected `ufw allow 53317/tcp` and `ufw allow 53317/udp` (comment `LocalSend`), `ufw --force enable`, `systemctl enable ufw.service`.
  - `apps_hook_flatpak`: calls `pkg_flathub_remote` (Task 3) so picking Flatpak alone still sets up Flathub.
  - `apps_hook_gamemode`: `usermod -aG gamemode` unless already a member.
  - `apps_hook_snapper` (btrfs only; skip if `/etc/snapper/configs/root` exists): if `/.snapshots` is a mountpoint (`findmnt -n /.snapshots`) do the archinstall-layout dance — `umount /.snapshots`, `rmdir /.snapshots`, `snapper -c root create-config /`, `btrfs subvolume delete /.snapshots`, `mkdir /.snapshots`, `mount -a` — else just `snapper -c root create-config /`; then `systemctl enable snapper-timeline.timer snapper-cleanup.timer grub-btrfsd.service` and, if `/boot/grub/grub.cfg` exists, `grub-mkconfig -o /boot/grub/grub.cfg`.
  - `apps_hook_zathura`: `xdg-mime default org.pwmt.zathura.desktop application/pdf` (as the user).
  - `apps_hook_rust`: `rustup default stable` if `rustup default` reports none; `rustup component add rust-analyzer rustfmt` (as the user).
  - `apps_hook_neovim`: defined in Task 5.

- [ ] **Step 1: Write failing tests** (stubs record calls to `$CALLS`):
  - `hooks run only for selected apps` — `APPS='docker'` → docker calls present, no ufw calls.
  - `docker hook skips usermod when already in the group` — `id -nG` stub prints `wheel docker`.
  - `ufw hook opens LocalSend's port only when LocalSend is selected` (two tests).
  - `ufw hook uses --force enable` (non-interactive).
  - `snapper hook skips when the root config exists`.
  - `snapper hook does the umount dance when /.snapshots is mounted` — order of calls asserted: `umount`, `rmdir`, `create-config`, `subvolume delete`, `mkdir`, `mount -a`.
  - `snapper hook does nothing on ext4`.
  - `a failing hook is recorded and later hooks still run`.
  - `rust hook sets stable only when no default toolchain`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** `bash test/run-unit.sh` → pass.
- [ ] **Step 5:** Commit `feat(apps): setup for docker, ufw, flatpak, snapper, gamemode, zathura, rust`.

---

### Task 5: LazyVim config with per-language extras

**Files:**
- Create: `config/nvim/` from `LazyVim/starter` at a pinned commit (`init.lua`, `lua/config/{lazy,options,keymaps,autocmds}.lua`, `lua/plugins/`, `stylua.toml`, `LICENSE`), plus `config/nvim/lua/plugins/nusku-theme.lua`, `config/nvim/lua/plugins/nusku-gdscript.lua`, `config/nvim/lua/nusku/{languages,sync}.lua`, `config/nvim/lazy-lock.json` (generated), `theme/templates/nvim-accent.lua.tmpl`
- Modify: `config/links.txt` (`config/nvim .config/nvim`), `.gitignore` (`config/nvim/lazyvim.json`), `lib/apps.sh` (`apps_hook_neovim`, `apps_write_nvim_languages`), `test/Dockerfile` (+ `neovim`), `test/unit/apps.bats`, `test/unit/theme.bats`

**Interfaces:**
- Consumes: `LANGS`; rendered theme dir `~/.config/nusku/theme/`.
- Produces:
  - `apps_write_nvim_languages FILE` — writes `return { "python", "rust" }` (selected `LANGS` in catalogue order; `return {}` when none), every run, with a "generated" header.
  - `~/.config/nusku/theme/nvim-accent.lua` — `return { name = "{{accent_name}}", hex = "#{{accent}}" }`.
  - `nusku.languages` (Lua): `extras` map from catalogue id to LazyVim extra modules — python `lang.python`; php `lang.php`; js `lang.typescript`, `lang.json`; rust `lang.rust`; go `lang.go`; cpp `lang.clangd`, `lang.cmake`; csharp `lang.omnisharp`; java `lang.java`; lua `false` (LazyVim core covers Lua); gdscript `false` (own spec, below). `enabled()` reads `~/.config/nusku/nvim-languages.lua` with `dofile` inside `pcall` (missing → `{}`); `imports()` returns `{ import = "lazyvim.plugins.extras.<x>" }` specs for the enabled ones. Check every extra name against the pinned LazyVim's `lua/lazyvim/plugins/extras/lang/` and fix the map if one was renamed.
  - `lua/config/lazy.lua` (starter file, edited): spec = `{ "LazyVim/LazyVim", import = "lazyvim.plugins" }`, then `require("nusku.languages").imports()`, then `{ import = "plugins" }`. Language extras are **not** written to `lazyvim.json`; that file is for `:LazyExtras` picks the owner makes by hand, so it is gitignored.
  - `lua/plugins/nusku-theme.lua`: LazyVim `opts.colorscheme = "catppuccin-mocha"`; catppuccin `flavour = "mocha"` with `custom_highlights` setting `CursorLineNr`, `FloatBorder`, `WinSeparator`, `Title` to the accent hex from `nvim-accent.lua` (fallback `#89b4fa` if the file is missing).
  - `lua/plugins/nusku-gdscript.lua`: active only when `gdscript` is enabled — lspconfig `servers.gdscript = { mason = false }` (Godot's own server on 127.0.0.1:6005, only while the Godot editor is open) and treesitter `ensure_installed` gets `gdscript godot_resource gdshader`.
  - `nusku.sync` — `run()` for the headless install: `require("lazy").restore({ wait = true })` (install exactly the `lazy-lock.json` revisions), load all plugins, then wait for Mason to finish every `ensure_installed` tool (poll `mason-registry` until nothing is installing; timeout 15 min) and for the treesitter parsers (`require("nvim-treesitter").install(<ensure_installed>):wait(600000)`). On any failure print it and `vim.cmd.cquit(1)`; otherwise `qa`. Read `ensure_installed` from the resolved plugin opts (`require("lazy.core.plugin").values(plugin, "opts")`) of the pinned LazyVim's mason and treesitter specs, not from a hard-coded list.
  - `apps_hook_neovim` — `apps_write_nvim_languages "$NUSKU_CONFIG_DIR/nvim-languages.lua"`, then `run_soft nvim --headless "+lua require('nusku.sync').run()"`.
- Keymaps and options are the starter's/LazyVim's own; nothing from Omarchy.

- [ ] **Step 1: Write failing tests**:
  - `apps_write_nvim_languages writes selected languages in catalogue order` — `LANGS='rust python'` → `return { "python", "rust" }` (+ header).
  - `apps_write_nvim_languages writes an empty table with no languages`.
  - `every catalogue language is mapped in nusku.languages` — each `apps_langs` id is a key in the `extras` table of `config/nvim/lua/nusku/languages.lua`, and there are no extra keys.
  - `nvim-accent template renders` (`theme.bats`) — blue → `hex = "#89b4fa"`.
  - `nusku.languages builds imports without plugins installed` (`neovim` added to `test/Dockerfile`) — `XDG_CONFIG_HOME=$BATS_TEST_TMPDIR/cfg` with `cfg/nusku/nvim-languages.lua` = `return { "python", "go" }`; `nvim --headless --clean "+set rtp^=$PWD/config/nvim" "+lua io.write(vim.inspect(require('nusku.languages').imports()))" +qa` → output contains `extras.lang.python` and `extras.lang.go`, not `extras.lang.rust`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Import the starter and add the Nusku files. Generate `lazy-lock.json` in the container: an `XDG_CONFIG_HOME` whose `nvim` links to the repo's `config/nvim` and whose `nusku/nvim-languages.lua` lists **every** language (so the lock covers every extra's plugins); run `nvim --headless "+Lazy! sync" +qa`; commit the lockfile.
- [ ] **Step 4:** In the container with a fresh `XDG_DATA_HOME` and `LANGS=python lua`: `nvim --headless "+lua require('nusku.sync').run()"` exits 0. Afterwards:
  - `~/.local/share/nvim/mason/bin/` has `ruff` and the Python LSP the pinned extra uses.
  - `~/.local/share/nvim/site/parser/python.so` exists.
  - `nvim --headless "+lua io.write(vim.g.colors_name)" +qa` prints `catppuccin-mocha`.
  - A second `sync` run exits 0 and installs nothing new.
  - The full suite passes.
- [ ] **Step 5:** Commit `feat(nvim): LazyVim config; language extras follow the picked languages`.

---

### Task 6: Yazi theme and keybind

**Files:**
- Create: `config/yazi/yazi.toml`, `config/yazi/flavors/catppuccin-mocha.yazi/{flavor.toml,tmtheme.xml,LICENSE,LICENSE-tmtheme}` (vendored from `yazi-rs/flavors`, pinned commit, `# source:` line in `flavor.toml`), `theme/templates/home/.config/yazi/theme.toml.tmpl`
- Modify: `config/links.txt` (`config/yazi/yazi.toml .config/yazi/yazi.toml`, `config/yazi/flavors .config/yazi/flavors`), `config/hypr/keybinds.lua`, `test/unit/hypr.bats`, `test/unit/theme.bats`

**Interfaces:**
- `theme.toml` (rendered, not linked, so the accent applies): `[flavor] dark = "catppuccin-mocha"` plus accent overrides for the hovered row, the normal-mode badge and the tab/cwd colour, using `#{{accent}}`. Check the vendored `flavor.toml` for the exact section/key names the pinned Yazi (26.9) uses and override only keys that exist there.
- Keybind: `SUPER+SHIFT+E` → `kitty -e yazi`, registered only when `/usr/bin/yazi` exists (`io.open` check at config load), so a machine without Yazi has no dead bind.

- [ ] **Step 1: Failing tests:** `hypr.bats` — keybinds.lua binds `SHIFT`+`E` to `yazi` inside a yazi-exists guard (grep both); `theme.bats` — rendered yazi theme for `mauve` contains `#cba6f7` and `catppuccin-mocha`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement, vendor, render. **Step 4:** Container: `Hyprland --verify-config` still `config ok` (run via `bash test/run-container-install.sh` in Task 7, or the existing hypr.bats verify test if present). Suite passes.
- [ ] **Step 5:** Commit `feat(yazi): Catppuccin flavor with accent and SUPER+SHIFT+E`.

---

### Task 7: Container and VM runs, docs

**Files:**
- Modify: `test/answers/container.answers`, `test/run-container-install.sh`, `test/hyperv/Invoke-NuskuTest.ps1`, `test/hyperv/README.md`, `README.md`
- Create: `test/answers/vm-full.answers`

**Interfaces:**
- `container.answers` adds `APPS=neovim gh lazygit yazi zathura docker` and `LANGS=lua go` (small, no services that need a kernel: no ufw/flatpak).
- `vm-full.answers`: `vm.answers` + every app id (incl. `snapper`, to exercise the ext4 skip) and every language.
- `Invoke-NuskuTest.ps1 -Answers <repo-relative path>` (default `test/answers/vm.answers`).

- [ ] **Step 1:** Container assertions (append): `pacman -Q neovim github-cli lazygit yazi zathura docker go lua`; `~/.config/nvim` links into `/nusku`; `~/.config/nusku/nvim-languages.lua` is `return { "go", "lua" }` (+ header); `~/.local/share/nvim/site/parser/go.so` and `~/.local/share/nvim/mason/bin/gopls` exist; `docker.service` enabled (`systemctl is-enabled`); `getent group docker` lists the user (not `id -nG`: the test shell predates the usermod); second install run and `--update` still create no backup dir; `NUSKU_APP_FAILURES` block absent from the log (`! grep -q "Not installed" log`).
- [ ] **Step 2:** `bash test/run-container-install.sh` → `ALL CONTAINER INSTALL ASSERTIONS PASSED`.
- [ ] **Step 3:** VM loop: add `-Answers`; when the answers file has `APPS`, add checks: `command -v` for `nvim gh claude lazygit docker code firefox discord obsidian libreoffice thunderbird zathura localsend spotify-launcher vlc obs audacity gimp krita inkscape kdenlive blender steam lutris heroic gamemoded mangohud protonup-qt wine yazi flatpak gparted ufw` (PASS/FAIL per name); `flatpak info com.bitwarden.desktop`; `systemctl is-enabled docker ufw`; `sudo ufw status` shows `53317`; `grep -q multilib /etc/pacman.conf`; the log contains `Skipping Snapper`; summary has no `Not installed`. Add one screenshot: `kitty -e nvim /tmp/demo.py` launched via `hyprctl dispatch 'hl.dsp.exec_cmd("…")'`, wait 5 s, grim.
- [ ] **Step 4:** Run `powershell -NoProfile -ExecutionPolicy Bypass -File test\hyperv\Invoke-NuskuTest.ps1 -Answers test/answers/vm-full.answers` → all checks PASS (WARN allowed for the existing bluetooth/hyprpaper notes); inspect screenshots (desktop unchanged from Stage 1; Neovim shows LazyVim in Mocha with the blue accent, Python highlighting and no install popups (Lazy and Mason already done)). Then the plain `vm.answers` run still passes (a Stage-1-style install with no apps).
- [ ] **Step 5:** README: the groups and ★ defaults, `./install.sh --apps`, the language list, the Neovim notes (LazyVim; `:Lazy update` changes `config/nvim/lazy-lock.json` in the repo, so commit it; extras added by hand with `:LazyExtras` stay local; GDScript needs the Godot editor open), Docker group warning, UFW + LocalSend port. `test/hyperv/README.md`: the `-Answers` switch and that a full run needs ~25 GB of the VM's 60 GB.
- [ ] **Step 6:** Commit `test, docs: Stage 2 container and VM runs, README`.
