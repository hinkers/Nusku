# Nusku Stage 3 — design

Date: 2026-10-29. Builds on the Stage 1 design (`2026-10-27-nusku-design.md`) and the
Stage 2 work merged to `main` (app picker, `packages/apps.list`, `lib/apps.sh`).

## 1. Intent

Stage 3 is the last feature stage before the one real-hardware run. It adds two things the
owner asked for:

1. **ArtCraft** as an app group in the installer's picker.
2. **A searchable keybind menu**: a Rofi menu where you type what you want ("screenshot"),
   see which key does it, and can run it from the menu.

### Dropped from the original Stage 3 list

The Stage 1 design listed five Stage 3 items. Three were never asked for by the owner and are
removed (update §4 and §10 of the Stage 1 design to match):

- Generated wallpapers (ImageMagick from the palette) — not wanted.
- Optional larger wallpaper pack download — not wanted; the curated set in the repo is enough.
- Oh My Posh as an alternative prompt — not wanted; Starship stays the only prompt.

The `wallpapers/` line in the Stage 1 layout ("+ generator script in Stage 3") loses its
generator note.

## 2. Goals, non-goals, anti-goals

**Goals**
- Pick any of the 13 ArtCraft apps in the existing app picker; they are installed and then kept
  up to date by the ArtCraft Launcher.
- Find any keybind by searching in plain words, and trigger it from the menu where that makes
  sense.

**Non-goals**
- Nusku updating ArtCraft apps itself. Updating is the launcher's job.
- SolidCraft (a community app the launcher also offers). Not in the owner's list.
- Editing or remapping keybinds from the menu.

**Anti-goals** (would count as failure even if it technically works)
- A keybind menu that lists keys which don't exist, or misses keys that do (drift from the real
  config).
- An ArtCraft app installed in a way the launcher won't update.
- An ArtCraft download installed without its checksum being verified.

## 3. ArtCraft

### Findings (checked 2026-10-29)

- Each app is a repo under `github.com/storytold/<repo>`; the launcher is `storytold/craft-launcher`
  (MIT OR Apache-2.0). Every latest release has `SHA256SUMS.txt` and
  `<stem>-<version>-linux-x86_64.pkg.tar.zst` (also AppImage, Flatpak bundle, deb, rpm, tarball).
  Launcher asset stem is `artcraft-launcher`; app stems equal the repo name.
- All are early (0.1x versions, "early alpha" / "in development").
- The launcher has no command-line install. It does detect Arch, and it treats an installed
  pacman package as its own (and updates it) when it is the **release's** Arch package, which is
  named by bundle id `ai.storyteller.<app>`. AUR packages (`<app>`, `<app>-bin`, `<app>-git`) are
  left alone and never updated by the launcher. (`crates/native/src/install.rs`,
  `is_release_arch_package`.) Its README still only mentions deb/rpm for Linux; the code is newer.
- AUR coverage is partial (about 6 of 13 apps, mixed maintainers, some lagging) — not used.

### Behaviour (agreed with the owner)

- **Picker:** new group `ArtCraft` in `packages/apps.list`, after `creative`, with the 13 apps:
  PhotoCraft, VectorCraft, FilmCraft, LightCraft, PdfCraft, EffectCraft, DesignCraft, FigCraft,
  WordCraft, SoundCraft, DeckCraft, CADCraft, GridCraft. None starred. It works like every other
  group (checklist, None item, `APPS` answers key, `--apps`).
- **Launcher always:** if any ArtCraft app is picked, the ArtCraft Launcher is installed too. The
  launcher is not its own picker item.
- **Install:** for the launcher and each picked app, download the latest release's x86_64
  `.pkg.tar.zst` and `SHA256SUMS.txt` from GitHub, verify the checksum, install with `pacman -U`.
  After that the launcher keeps them (and itself) up to date.
- **Starts at login, hidden in the tray** (owner agreed): the launcher only checks for updates
  while running. Its own "Start ArtCraft Launcher when I log in" setting writes the XDG
  autostart entry `~/.config/autostart/ai.storyteller.artcraft-launcher.desktop` (Exec ends in
  `--hidden`; see `crates/native/src/login.rs`). Hyprland doesn't run XDG autostart entries, so:
  - the installer turns that setting on by writing the entry in the launcher's own format (only
    if it doesn't exist yet), and
  - `config/hypr/autostart.lua` runs the entry's command at login **only while that file
    exists**, so unticking the setting in the launcher stops it with no Nusku change.
  The VM run checks the launcher process is running after login.
- **Failures** *(builder's call)*: soft, per app, like optional AUR installs — a failed download,
  missing asset or checksum mismatch goes into `NUSKU_APP_FAILURES` ("Not installed (see the
  log):") and the install carries on. If the launcher itself fails, the apps are still attempted
  and a note says updates won't happen until the launcher is installed.
- **Re-runs** *(builder's call)*: an app whose release package is already installed is skipped
  (no reinstall, no update). Updating is the launcher's job.
- **Versions** *(builder's call)*: always the latest release; nothing pinned in Nusku.
- **Checksum scope** *(builder's call)*: `SHA256SUMS.txt` from the same release catches corrupt
  or truncated downloads, not a tampered release. The releases publish no signatures or GitHub
  attestations (checked 2026-10-29), so that is the strongest check available; the launcher
  itself does the same.
- **Installed some other way** *(builder's call)*: if an AUR copy (`<app>`, `<app>-bin`,
  `<app>-git`) is installed, Nusku skips that app and adds a note that the launcher won't update
  it — Nusku never removes a package it didn't install. AppImage/Flatpak copies elsewhere are not
  looked for.
- Unticking does not uninstall (same as every other group).

### Left to the builder

- How ArtCraft entries are expressed in the catalogue (a new token type such as
  `artcraft:<repo>` is the obvious fit) and where the download/verify code lives.
- How to query the latest release (GitHub API or the `releases/latest/download/` redirect) and
  how to detect "already installed" (the package name is `ai.storyteller.<app>`; confirm against
  a real package's `.PKGINFO`).
- Whether downloads run as the user or root, and where they are cached.
- Tests: unit tests for catalogue parsing, the launcher-always rule and checksum handling (with
  stubbed downloads); the container/VM runs should include at least one real ArtCraft app.

## 4. Keybind menu

### Behaviour (agreed with the owner)

- Opened with **SUPER + /** *(builder's guess, owner didn't object)*.
- A Rofi dmenu in the Nusku theme and accent (same look as the clipboard, wallpaper and power
  menus; script `scripts/nusku-menu-keybinds`, linked to `~/.local/bin` like the others).
- Each line: a plain-words description and the key, e.g. `Screenshot a region      Print`.
  Typing filters the list (case-insensitive, matching description or key).
- Selecting a line runs that action, the same as pressing the key.
- Binds that can't sensibly run from a menu (mouse drags, held-to-repeat resize, scroll-wheel
  workspace switching) are still listed for reference; selecting one just closes the menu.
- Repeated binds collapse into summary lines: "Go to workspace 1–10 · SUPER + 1…0" and
  "Move window to workspace 1–10 · SUPER + SHIFT + 1…0". Selecting one opens a second Rofi
  prompt asking which workspace, then runs it. The four focus/move directions may also collapse
  (builder's call).

### Source of truth

- Every bind in `config/hypr/keybinds.lua` gets a short plain-words description, written next to
  the bind.
- The menu lists what Hyprland **has actually loaded**, so conditional binds (Yazi on
  SUPER + SHIFT + E only when installed) appear only when live, and the menu can't drift from
  the config.

### Left to the builder

- The mechanism. Hyprland is 0.57 with the Lua config; check what `hl.bind` accepts for a
  description and whether `hyprctl binds -j` exposes it and the action. The existing power menu
  already runs Lua dispatchers via `hyprctl dispatch 'hl.dsp.exit()'`, which suggests a selected
  bind can be run the same way. If Hyprland doesn't expose enough, an acceptable fallback is for
  `keybinds.lua` to register binds through a small helper that also records description + action
  somewhere the menu reads at runtime — as long as there is still one place where a bind and its
  description are written, and only binds that were really registered show up.
- Key display format (e.g. `SUPER + SHIFT + E`), column alignment, sort order (the order binds
  appear in `keybinds.lua`, grouped by its section headers, is a reasonable default).
- Tests: a unit test that every bind in `keybinds.lua` has a description; the VM run checks the
  menu script lists binds (e.g. by running it with Rofi stubbed).

## 5. Constraints (unchanged from earlier stages)

- Written from scratch; nothing copied from Omarchy. ArtCraft code is not vendored.
- Bash installer + gum; bats + shellcheck in Docker (`bash test/run-unit.sh`); container full
  install; Hyper-V VM loop (`test/hyperv/Invoke-NuskuTest.ps1`). Same subagent-driven execution
  as Stages 1–2.
- README updated: ArtCraft group (launcher installed automatically, launcher does updates) and the
  keybind menu key.
- Real-hardware testing stays last, after Stage 3 is merged.
