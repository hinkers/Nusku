# Nusku

Nusku is a Bash installer that turns a fresh Arch Linux install into a themed Hyprland desktop.

## Install

```bash
git clone https://github.com/<user>/nusku.git && cd nusku && ./install.sh
```

## Updating

```bash
nusku-update               # git pull --ff-only, then ./install.sh --update
./install.sh --update      # re-apply every step with your saved answers, no questions
./install.sh --reconfigure # ask the questions again (GPU, driver, AUR helper, accent, apps)
```

Your answers are saved in `~/.config/nusku/answers`.

## Optional apps and languages

The installer asks which extra apps to install, group by group (a `None` item clears a group). The ★ items are pre-selected on a fresh install.

| Group | Apps |
| --- | --- |
| Dev | Neovim (LazyVim) ★, GitHub CLI ★, Claude Code ★, lazygit, Docker + Compose, VS Code |
| Everyday | Firefox ★, Discord ★, Obsidian ★, LibreOffice, Thunderbird, Bitwarden (Flatpak), Zathura, LocalSend |
| Media | Spotify ★, VLC ★, OBS Studio, Audacity |
| Creative | GIMP, Krita, Inkscape, Kdenlive, Blender |
| Gaming | Steam, Lutris, Heroic, GameMode, MangoHud, ProtonUp-Qt, Wine (multilib is enabled when needed) |
| System tools | Yazi, Flatpak, Snapper (btrfs roots only), GParted, UFW firewall |

Then pick programming languages: Python, PHP, GDScript, JavaScript/TypeScript, Rust, Go, C/C++, C#, Java, Lua. Each installs its runtime and package manager; the Neovim language server, formatter and parser come from LazyVim.

```bash
./install.sh --apps        # re-open only the app and language picker, starting from your saved picks
./install.sh --reconfigure # ask everything again, with the picker starting from the ★ defaults
```

Apps from the AUR or Flathub are optional: if one fails to install, the rest carry on and the summary lists it under "Not installed (see the log)". Setup notes appear under "Notes".

### Neovim

`~/.config/nvim` is [LazyVim](https://www.lazyvim.org/) in Catppuccin Mocha with your accent colour. The installer syncs plugins, Mason tools and Treesitter parsers headless, so the first launch has nothing to download. Language extras follow the languages you picked.

- Plugin versions are pinned in `config/nvim/lazy-lock.json`, and every `install.sh` or `--update` resets your plugins to those versions. To bump them, run `:Lazy update`, copy `~/.local/share/nvim/lazy-lock.json` over `config/nvim/lazy-lock.json` in the repo, and commit it.
- Extras you add by hand with `:LazyExtras` stay local (`config/nvim/lazyvim.json` is gitignored).
- GDScript's language server only works while the Godot editor is open.
- `Super + Shift + E` opens Yazi when it is installed.

### Docker and the firewall

- Docker adds you to the `docker` group, which is root-equivalent. Log out and back in to use `docker` without `sudo`.
- UFW denies incoming traffic by default. When LocalSend is also picked, port 53317 (TCP and UDP) is opened for it.

## Changing the accent

```bash
nusku-theme mauve
```

Any of the 14 Catppuccin accents works: rosewater flamingo pink mauve red maroon peach yellow green teal sky sapphire blue lavender. Hyprland, Waybar, SwayNC, rofi and kitty update straight away; the login screen and the GTK cursor follow after `nusku-update` (or `./install.sh --update`).

## Per-machine overrides

Nusku never overwrites these files:

- `~/.config/nusku/local.lua` — Hyprland settings (monitors, input, extra binds). Loaded last, so it wins.
- `~/.config/nusku/local.zsh` — your own zsh additions, sourced at the end of `~/.zshrc`.

Hyprland's config is [Lua](https://wiki.hypr.land/Configuring/) (`~/.config/hypr/hyprland.lua` and the modules next to it). A `local.lua` override looks like this:

```lua
hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = 1 })
hl.config({ input = { kb_layout = "us,de", kb_options = "grp:alt_shift_toggle" } })
hl.bind("SUPER + B", hl.dsp.exec_cmd("firefox"))
```

Upgrading from an older Nusku that used `local.conf`: that file is kept but no longer read. The installer warns if it holds settings; move them into `local.lua` in the syntax above. Log out and back in (or reboot) after updating: the running session still uses the old config.

With a Lua config, `hyprctl dispatch` takes `hl.dsp.*` expressions (e.g. `hyprctl dispatch 'hl.dsp.exit()'`), so personal scripts using the old form (`hyprctl dispatch exit`) need updating.

## Keybinds

`Super` is the main modifier.

| Keys | Action |
| --- | --- |
| Super + Return | Terminal (kitty) |
| Super + Space | App launcher (rofi) |
| Super + E | File manager (Thunar) |
| Super + V | Clipboard history |
| Super + W | Wallpaper picker |
| Super + Escape | Power menu |
| Super + N | Notification centre |
| Super + L | Lock screen |
| Super + Q | Close window |
| Super + F | Fullscreen |
| Super + T | Toggle floating |
| Super + P | Pseudo-tile |
| Super + J | Toggle split |
| Super + Arrows | Move focus |
| Super + Shift + Arrows | Move window |
| Super + Ctrl + Arrows | Resize window |
| Super + left / right mouse drag | Move / resize window |
| Super + 1…0 | Go to workspace 1–10 |
| Super + Shift + 1…0 | Move window to workspace 1–10 |
| Super + mouse wheel | Next / previous workspace |
| Print | Screenshot a region |
| Shift + Print | Screenshot a window |
| Ctrl + Print | Screenshot a monitor |

Media, volume and brightness keys work as expected (also on the lock screen). The full list is in `config/hypr/keybinds.lua`.

## Logs and backups

- Each run logs to `~/.local/state/nusku/install-<timestamp>.log`; on failure the installer prints the failed step and the log path.
- Before replacing any of your files, Nusku copies it to `~/.local/state/nusku/backup-<timestamp>/`. The summary at the end shows the backup folder when one was made.

## Tests

Requires Docker. Runs shellcheck and the bats unit tests inside an Arch container:

```bash
bash test/run-unit.sh          # everything
bash test/run-unit.sh smoke    # only test/unit/smoke.bats
```
