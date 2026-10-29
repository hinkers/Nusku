# Nusku Stage 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ArtCraft as a picker group (installed from the official Arch packages, kept updated by an auto-started ArtCraft Launcher) and a searchable Rofi keybind menu that can run the bind you pick.

**Architecture:** ArtCraft apps are catalogue entries with a new `artcraft:<repo>` token; `apps_batches` emits `artcraft` lines that a new `lib/artcraft.sh` downloads, checksum-verifies and installs with `pacman -U`, softly. Keybinds are registered through one Lua helper that both calls `hl.bind` (with a description) and appends the bind to a runtime manifest; the menu script reads that manifest and runs a pick with `hyprctl dispatch '<lua expr>'`.

**Tech Stack:** Bash, gum, bats + shellcheck (Docker `nusku-test`), curl, pacman, Hyprland 0.57 Lua config, Rofi.

**Spec:** `docs/superpowers/specs/2026-10-29-nusku-stage3-design.md`

## Global Constraints

- Written from scratch; nothing copied from Omarchy. No ArtCraft code vendored.
- ArtCraft source: `https://github.com/storytold/<repo>`; launcher repo `craft-launcher`, file stem `artcraft-launcher`; app stem = repo name. Assets per release: `SHA256SUMS.txt` and `<stem>-<ver>-linux-x86_64.pkg.tar.zst`.
- Release package name is `ai.storyteller.<stem>` (verified: launcher `.PKGINFO` → `pkgname = ai.storyteller.artcraft-launcher`, `conflict = artcraft-launcher artcraft-launcher-bin artcraft-launcher-git`, binary `/usr/bin/artcraft-launcher`).
- Always latest release; nothing pinned. Every download verified against that release's `SHA256SUMS.txt` before install.
- ArtCraft failures are soft: recorded in `NUSKU_APP_FAILURES`, install continues.
- An AUR copy (`<stem>`, `<stem>-bin`, `<stem>-git`) installed → skip with a note; Nusku never removes packages it didn't install.
- Launcher autostart entry: `~/.config/autostart/ai.storyteller.artcraft-launcher.desktop`, launcher's own format (Exec `<path> --hidden`); Hyprland runs it only while that file exists.
- Keybind menu opens on `SUPER + /`; uses `-theme nusku` like the other menus; script `scripts/nusku-menu-keybinds` (linked by the existing `scripts/nusku-* .local/bin` manifest line).
- Tests: `bash test/run-unit.sh [name]` (bats + shellcheck), `bash test/run-container-install.sh`, Hyper-V `powershell -NoProfile -ExecutionPolicy Bypass -File test\hyperv\Invoke-NuskuTest.ps1 [-Answers test/answers/vm-full.answers]` (run from PowerShell).

## Review Focus

- A new ArtCraft release lands between fetching `SHA256SUMS.txt` and the package → checksum/asset mismatch must be a soft failure with a clear reason, never a crash or an unverified install.
- No network / GitHub down → every ArtCraft app (and the launcher) ends up in "Not installed" and the rest of the install finishes.
- Re-running the installer with ArtCraft already installed → no downloads, no reinstall, no duplicate autostart entry, and an autostart entry the owner deleted (unticked) is not recreated.
- Hyprland config reload (`hyprctl reload`) → the keybind manifest is rewritten, not appended to twice.
- A description containing a tab, `|` or quote, or an action with quotes (e.g. hyprshot paths) → menu shows and runs it correctly.

---

## File map

| File | Change |
|---|---|
| `packages/apps.list` | + `group|artcraft|ArtCraft` and 13 `app|artcraft|…|-|<Label>|artcraft:<repo>|` lines |
| `lib/apps.sh` | `apps_batches` emits `artcraft ID REPO` lines (+ one `artcraft launcher craft-launcher` when any) |
| `lib/artcraft.sh` (new) | download, verify, install, autostart entry |
| `install.sh` | source `lib/artcraft.sh`; `step_packages` calls `artcraft_install_soft "$batches"` |
| `config/hypr/autostart.lua` | conditional launcher start |
| `config/hypr/bindlib.lua` (new) | `nusku_bind` helper + manifest |
| `config/hypr/keybinds.lua` | every bind through the helper, with a description; `SUPER + /` |
| `scripts/nusku-menu-keybinds` (new) | the Rofi menu |
| `test/unit/artcraft.bats`, `test/unit/keybinds.bats` (new), `test/unit/apps.bats`, `test/unit/menus.bats` | tests |
| `test/answers/vm-full.answers`, `test/hyperv/Invoke-NuskuTest.ps1`, `test/run-container-install.sh` | real ArtCraft install + menu checks |
| `README.md`, `docs/superpowers/specs/2026-10-27-nusku-design.md` | docs; drop the three cancelled Stage 3 items |

---

### Task 1: ArtCraft in the catalogue and the installer

**Files:**
- Modify: `packages/apps.list`, `lib/apps.sh` (`apps_batches`), `install.sh` (source + `step_packages`)
- Create: `lib/artcraft.sh`, `test/unit/artcraft.bats`
- Test: `test/unit/apps.bats`, `test/unit/artcraft.bats`

**Interfaces:**
- Consumes: `apps_batches`, `apps_label`, `run_soft`, `log_info`, `NUSKU_APP_FAILURES`, `NUSKU_APP_NOTES`.
- Produces:
  - Catalogue ids/labels/repos (group after `creative`, before `gaming`, none starred): `photocraft` PhotoCraft, `vectorcraft` VectorCraft, `filmcraft` FilmCraft, `lightcraft` LightCraft, `pdfcraft` PdfCraft, `effectcraft` EffectCraft, `designcraft` DesignCraft, `figcraft` FigCraft, `wordcraft` WordCraft, `soundcraft` SoundCraft, `deckcraft` DeckCraft, `cadcraft` CADCraft, `gridcraft` GridCraft; token `artcraft:<id>` (repo = id).
  - `apps_batches` lines `artcraft <APP_ID> <REPO>`; when there is at least one, a first line `artcraft launcher craft-launcher`.
  - `artcraft_stem REPO` → `artcraft-launcher` for `craft-launcher`, else REPO.
  - `artcraft_installed STEM` → 0 when `ai.storyteller.<stem>` is installed (`pacman -Q`).
  - `artcraft_foreign STEM` → prints the name of an installed `<stem>`, `<stem>-bin` or `<stem>-git` (exact installed names from `pacman -Qq`, not `provides`), status 0 if any.
  - `artcraft_fetch REPO DIR` → downloads to DIR and prints the verified `.pkg.tar.zst` path; non-zero with a one-line reason on stderr (`no x86_64 Arch package in the latest release`, `checksum mismatch`, `download failed`).
  - `artcraft_install_soft BATCHES` → for each `artcraft` line, launcher first.
  - Base URL overridable for tests: `NUSKU_ARTCRAFT_BASE` (default `https://github.com/storytold`).

- [ ] **Step 1: Write failing tests.** Stub `curl` and `pacman`/`sudo` on `PATH` (pattern: `test/unit/menus.bats` stub rofi); stub curl serves files from a fixture dir keyed by URL path.
  - `apps.bats`: `artcraft group lists 13 apps in order` — `apps_in_group artcraft` equals the 13 ids above; `apps_starred` contains none of them.
  - `apps.bats`: `artcraft picks add the launcher once, first` — `APPS='photocraft pdfcraft'` → `apps_batches` artcraft lines are exactly `artcraft launcher craft-launcher`, `artcraft photocraft photocraft`, `artcraft pdfcraft pdfcraft`; no `repo`/`aur` lines from them.
  - `apps.bats`: `no artcraft picks, no launcher` — `APPS=firefox` → no `artcraft` line.
  - `artcraft.bats`: `fetch picks the x86_64 Arch package from SHA256SUMS and verifies it` — fixture SUMS lists aarch64 + x86_64 pkg + AppImage; prints path ending `photocraft-0.17.0-linux-x86_64.pkg.tar.zst`.
  - `artcraft.bats`: `fetch fails on a checksum mismatch` — status ≠ 0, stderr has `checksum mismatch`, no `pacman -U` recorded.
  - `artcraft.bats`: `fetch fails when the release has no x86_64 Arch package`.
  - `artcraft.bats`: `install_soft records a failure and continues` — curl fails for photocraft, succeeds for pdfcraft → `NUSKU_APP_FAILURES` has `PhotoCraft: download failed` (label + reason), pdfcraft installed via `sudo pacman -U --noconfirm --needed <path>`.
  - `artcraft.bats`: `install_soft skips an installed release package` — pacman stub reports `ai.storyteller.photocraft` → no curl call for photocraft.
  - `artcraft.bats`: `install_soft skips an AUR copy with a note` — pacman stub has `photocraft-bin` → no curl, `NUSKU_APP_NOTES` has `PhotoCraft is installed from the AUR (photocraft-bin); the ArtCraft Launcher won't update it.`
  - `artcraft.bats`: `launcher failure adds a note and still installs apps` — note `The ArtCraft Launcher was not installed, so ArtCraft apps won't update until it is.` plus the failure line.
- [ ] **Step 2:** `bash test/run-unit.sh apps` and `bash test/run-unit.sh artcraft` → FAIL.
- [ ] **Step 3:** Implement. Catalogue lines; `apps_batches` `artcraft:*` case. `lib/artcraft.sh`: `artcraft_fetch` downloads `$BASE/<repo>/releases/latest/download/SHA256SUMS.txt`, takes the single line ending `-linux-x86_64.pkg.tar.zst`, downloads `…/releases/latest/download/<file>`, checks with `sha256sum -c` on that one line. Download as the user into `mktemp -d` (removed on exit of the function); curl with `-fsSL --retry 2`. Install via `run_soft sudo pacman -U --noconfirm --needed`. Failure line format: `<Label>: <reason>` (launcher label `ArtCraft Launcher`). Source the lib in `install.sh` next to `lib/apps.sh`; call `artcraft_install_soft "$batches"` after `apps_install_flatpak_soft`.
- [ ] **Step 4:** Both suites PASS; full `bash test/run-unit.sh` PASS (shellcheck clean).
- [ ] **Step 5:** Commit `feat(apps): ArtCraft group installed from the official Arch packages`.

---

### Task 2: Start the ArtCraft Launcher at login

**Files:**
- Modify: `lib/artcraft.sh`, `config/hypr/autostart.lua`, `test/unit/artcraft.bats`, `test/unit/hypr.bats` (or a new Lua check in `keybinds.bats` style)

**Interfaces:**
- Consumes: Task 1 `artcraft_install_soft`, `artcraft_installed`.
- Produces: `artcraft_autostart_entry FILE` — writes, only if FILE does not exist **and** the launcher was installed by this run (first install), the launcher's own entry:
  ```
  [Desktop Entry]
  Type=Application
  Name=ArtCraft Launcher
  Comment=Install and update the Craft App Suite
  Exec=/usr/bin/artcraft-launcher --hidden
  Icon=ai.storyteller.artcraft-launcher
  Terminal=false
  X-GNOME-Autostart-enabled=true
  ```
  Called from `artcraft_install_soft` with `${XDG_CONFIG_HOME:-$HOME/.config}/autostart/ai.storyteller.artcraft-launcher.desktop`. Not written when the launcher was already installed before the run (so an owner who unticked "start at login" isn't overridden on re-runs).
- `autostart.lua`: inside the existing `hyprland.start` handler, if `~/.config/autostart/ai.storyteller.artcraft-launcher.desktop` is readable, read its `Exec=` line and `hl.exec_cmd` it. Nothing else from the file is used.

- [ ] **Step 1: Failing tests:** `writes the autostart entry on first launcher install` (content as above); `does not recreate a deleted entry when the launcher was already installed`; `does not overwrite an existing entry`; a Lua check run with `nvim -l` and a stub `hl` (records `exec_cmd` calls, fires the `hyprland.start` handler): with the entry present → one call `/usr/bin/artcraft-launcher --hidden`; without it → none.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → PASS; full suite PASS.
- [ ] **Step 5:** Commit `feat(apps): start the ArtCraft Launcher hidden at login while its setting is on`.

---

### Task 3: Keybinds registered with descriptions

**Files:**
- Create: `config/hypr/bindlib.lua`, `test/unit/keybinds.bats`, `test/fixtures/hypr-stub.lua` (stub `hl` for `nvim -l`)
- Modify: `config/hypr/keybinds.lua` (starts with `local B = require("bindlib")`; `hyprland.lua` already does `require("keybinds")`, so modules resolve from `config/hypr/`)

**Interfaces:**
- Produces (Lua, `bindlib.lua`, returns a module `B`):
  - `B.reset()` — truncates the manifest; called once at the top of `keybinds.lua` so a reload rewrites it.
  - `B.bind(keys, desc, expr, opts)` — `keys` as today (`"SUPER + SHIFT + E"`), `desc` required (error if empty), `expr` a Lua expression string for the dispatcher (e.g. `'hl.dsp.exec_cmd("kitty")'`, `'hl.dsp.window.close()'`), `opts` the existing `hl.bind` opts plus optional `group = "<id>"`. Calls `hl.bind(keys, load("return " .. expr)(), opts_with_description)` (`description = desc`; `group` stripped) and appends one manifest record.
  - `B.group(id, desc, keys_summary, prompt)` — declares a collapsed summary line (e.g. `"ws-go", "Go to workspace", "SUPER + 1…0", "Workspace"`).
  - Manifest: `${XDG_RUNTIME_DIR}/nusku/keybinds.tsv`, one record per line, tab-separated: `kind<TAB>group<TAB>keys<TAB>desc<TAB>runnable<TAB>expr` where `kind` is `bind` or `group`; tabs/newlines in fields replaced by spaces. `runnable` is `0` when `opts.mouse` or `opts.repeating` is set or keys contain `mouse`, else `1`. Group records carry `desc`, `keys_summary` and the prompt in the `expr` column.
- `keybinds.lua`: every existing bind goes through `B.bind` with a plain-words description (e.g. `Open terminal`, `App launcher`, `Screenshot a region`, `Screenshot a window`, `Screenshot a monitor`, `Volume up`). Workspace loops use groups `ws-go` ("Go to workspace", "SUPER + 1…0") and `ws-move` ("Move window to workspace", "SUPER + SHIFT + 1…0") with prompt `Workspace`; each member's `desc` is its number (`1`…`10`). Direction focus/move may use groups too (implementer's call). The Yazi bind stays conditional. Add `B.bind("SUPER + slash", "Search keybinds", 'hl.dsp.exec_cmd("~/.local/bin/nusku-menu-keybinds")')` — confirm the keysym name `slash` works with Hyprland 0.57.
- Before writing the helper, confirm on the VM (or Hyprland source) that `hl.bind` accepts `description` in opts and that `hyprctl dispatch '<expr>'` works for a non-exec dispatcher such as `hl.dsp.window.float({ action = "toggle" })`. If `description` is rejected, drop it from opts (the manifest alone is the source); if dispatch can't run non-exec dispatchers, mark those binds `runnable = 0` and note it in the commit.

- [ ] **Step 1: Failing tests** (`keybinds.bats`, run via `nvim -l` with `test/fixtures/hypr-stub.lua` providing `hl.bind`, `hl.dsp.*` recorders and `XDG_RUNTIME_DIR=$BATS_TEST_TMPDIR`):
  - `every bind has a description` — loading `keybinds.lua` produces manifest records whose `desc` is non-empty, and the number of `hl.bind` calls equals the number of `bind` records.
  - `no raw hl.bind outside bindlib` — `grep -n 'hl.bind(' config/hypr/keybinds.lua` finds nothing.
  - `manifest is rewritten on reload` — load twice → record count unchanged.
  - `screenshot binds are listed and runnable` — 3 records with `Screenshot` in desc, runnable `1`, keys `Print`, `SHIFT + Print`, `CTRL + Print`.
  - `mouse and held binds are not runnable` — `SUPER + mouse:272` and `SUPER + CTRL + left` records have runnable `0`.
  - `workspace binds collapse into groups` — `group` records `ws-go` and `ws-move`; 10 `bind` records in each.
  - `Yazi bind only when yazi exists` — stub `io.open` (or `NUSKU_YAZI_PATH`-style override already used, if any) both ways.
  - `fields with tabs are sanitised` — `B.bind("X", "a\tb", 'hl.dsp.exec_cmd("x")')` → desc `a b`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement `bindlib.lua`, convert `keybinds.lua`.
- [ ] **Step 4:** Run → PASS; full suite PASS; `bash test/run-container-install.sh` (its `Hyprland --verify-config` check) PASS.
- [ ] **Step 5:** Commit `feat(hypr): describe every keybind and record them for the keybind menu`.

---

### Task 4: The keybind menu

**Files:**
- Create: `scripts/nusku-menu-keybinds`
- Modify: `test/unit/menus.bats`

**Interfaces:**
- Consumes: Task 3 manifest at `${XDG_RUNTIME_DIR}/nusku/keybinds.tsv`.
- Produces: `nusku-menu-keybinds` — builds lines `"<desc padded>  <keys>"` in manifest order; group members are hidden and their `group` record shown once in the members' position (`Go to workspace 1–10   SUPER + 1…0`); `rofi -dmenu -i -p Keybinds -theme nusku` (with `-format i` to get the picked index, so matching on text never matters). On a pick:
  - runnable bind → `hyprctl dispatch "<expr>"`;
  - non-runnable → exit 0, nothing run;
  - group → second rofi (`-p <prompt>`) listing member descs (`1`…`10`), then dispatch the chosen member's expr;
  - Esc / no pick → exit 0. Missing manifest → `notify-send "Keybinds" "Keybind list not ready; reload Hyprland"` and exit 0.

- [ ] **Step 1: Failing tests** (`menus.bats`, existing rofi stub extended with `ROFI_PICK` as an index, plus a `hyprctl` stub recording args, fixture manifest):
  - `keybind menu lists description and keys` — rofi stdin contains a line with `Screenshot a region` and `Print`.
  - `keybind menu runs the picked bind` — pick screenshot index → hyprctl args `dispatch hl.dsp.exec_cmd("hyprshot -m region -o ~/Pictures/Screenshots")` exactly (quotes intact).
  - `keybind menu does not run a mouse bind`.
  - `keybind menu collapses workspace binds` — exactly one line containing `Go to workspace`; picking it then `3` dispatches the member `3` expr.
  - `keybind menu Esc runs nothing`.
- [ ] **Step 2:** Run → FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run → PASS; full suite PASS.
- [ ] **Step 5:** Commit `feat(menus): searchable keybind menu on SUPER + /`.

---

### Task 5: End-to-end checks and docs

**Files:**
- Modify: `test/answers/vm-full.answers` (add `photocraft` to `APPS`), `test/hyperv/Invoke-NuskuTest.ps1`, `test/run-container-install.sh` (if it covers app installs), `README.md`, `docs/superpowers/specs/2026-10-27-nusku-design.md`

- [ ] **Step 1:** VM checks added to `Invoke-NuskuTest.ps1` for the full-answers run: `pacman -Q ai.storyteller.artcraft-launcher ai.storyteller.photocraft`; autostart entry exists; after login `pgrep -f artcraft-launcher` finds it; `~/.local/bin/nusku-menu-keybinds` exists; `$XDG_RUNTIME_DIR/nusku/keybinds.tsv` (in the Hyprland session) has a `Screenshot a region` record; `hyprctl dispatch` of a manifest expr (e.g. the workspace-2 one) exits 0. Re-run the installer once in the VM: no ArtCraft download in the log (`releases/latest/download` absent from the second run's log section).
- [ ] **Step 2:** README: ArtCraft group (launcher installed automatically, starts hidden in the tray, untick "Start when I log in" in the launcher to stop it; Nusku never updates ArtCraft itself; AUR copies are left alone), keybind menu (`SUPER + /`, type to search, Enter runs it). Stage 1 design §4/§10/layout: remove generated wallpapers, wallpaper pack, Oh My Posh; point Stage 3 at the new spec.
- [ ] **Step 3:** Run `bash test/run-unit.sh`, `bash test/run-container-install.sh`, and the VM with `-Answers test/answers/vm-full.answers` → all PASS. Record a screenshot of the keybind menu in `test/screenshots/` if the harness supports it.
- [ ] **Step 4:** Commit `test: ArtCraft and keybind menu in the VM run; docs`.
