# Nusku

Nusku is a Bash installer that turns a fresh Arch Linux install into a themed Hyprland desktop.

## Install

```bash
git clone https://github.com/hinkers/Nusku.git && cd Nusku && ./install.sh
```

## Updating

```bash
nusku-update               # git pull --ff-only, then ./install.sh --update
./install.sh --update      # re-apply every step with your saved answers, no questions
./install.sh --reconfigure # open the settings menu again (GPU, driver, AUR helper, accent, apps)
```

Your answers are saved in `~/.config/nusku/answers`.

On a fresh install the questions are one menu, like archinstall's: each setting is listed with its current value (the graphics are detected for you). Use the arrow keys to move, Enter to change a setting, Esc to go back, and pick **Install** when it looks right. Try the menus without installing anything with `test/tui-demo.sh` (or `test/tui-demo.sh apps`).

## Optional apps and languages

Apps are one list: each group is a header with its apps indented underneath, folded until you open it. The ★ items are pre-selected on a fresh install.

- ↑/↓ move, Space ticks an app (on a group header, it ticks or clears the whole group).
- Enter or → opens a group, ← closes it (from an app, ← jumps back to its group).
- **Done** at the bottom saves; Esc leaves without changes; Ctrl+C cancels the install.

| Group | Apps |
| --- | --- |
| Dev | Neovim (LazyVim) ★, GitHub CLI ★, Claude Code ★, lazygit, Docker + Compose, VS Code |
| Everyday | Firefox ★, Chromium, Brave, Zen Browser, LibreWolf (Flatpak), Discord ★, Obsidian ★, LibreOffice, Thunderbird, GNOME Calendar, Bitwarden (Flatpak), Zathura, LocalSend |
| Media | Spotify ★, VLC ★, OBS Studio, Audacity |
| Creative | GIMP, Krita, Inkscape, Kdenlive, Blender |
| ArtCraft | PhotoCraft, VectorCraft, FilmCraft, LightCraft, PdfCraft, EffectCraft, DesignCraft, FigCraft, WordCraft, SoundCraft, DeckCraft, CADCraft, GridCraft |
| Gaming | Steam, Lutris, Heroic, Parsec (client), Sunshine and Moonlight, GameMode, MangoHud, ProtonUp-Qt, Wine (multilib is enabled when needed) |
| System tools | Yazi, Flatpak, Snapper (btrfs roots only), Remmina (VNC and RDP viewer), wayvnc (VNC server), GParted, UFW firewall, Pokémon in fastfetch |

Pick at least one browser from Everyday. If web links have no default yet, the first browser you picked becomes the default, and `Super + B` opens it. With no browser picked, the summary warns that links won't open.

Every new terminal greets you with fastfetch (Arch logo, Nerd Font icons, Catppuccin colours). Tick **Pokémon in fastfetch** (System tools) to swap the logo for a random Gen 1-3 Pokémon from [krabby](https://github.com/yannjor/krabby); shinies show up at krabby's default 1/128. Turn it on later with `./install.sh --apps`. Unticking it later does not uninstall krabby, so the Pokémon stays until you remove the `krabby-bin` package. Nusku ships no Pokémon art.

Remote desktop: **Remmina** connects to other machines over VNC or RDP (Windows Remote Desktop); **Parsec** (Gaming) connects to Parsec hosts. **Sunshine** (Gaming) hosts: it streams this PC to Moonlight on another computer, phone or TV, like a Parsec host, which Parsec does not offer on Linux. It starts at login, and Avahi is turned on so Moonlight can find it; open `https://localhost:47990` on this PC once to create its login, then pick this PC in Moonlight and type the PIN it shows into that page. It works on your home network, or from outside through a VPN such as Tailscale. If Moonlight cannot find or connect to this PC, check that the other device has no VPN running and that the router is not isolating Wi-Fi clients (guest network or "AP isolation"). With UFW picked as well, the streaming ports are opened; the settings page stays local. **Moonlight** (Gaming) is the viewer, for playing another Sunshine PC from this one. **wayvnc** shares this screen. Run `wayvnc` when you want it; it listens on this machine only (`127.0.0.1:5900`), so connect through an SSH tunnel (`ssh -L 5900:localhost:5900 you@this-pc`, then point the viewer at `localhost`). Before letting it listen on your network (`wayvnc 0.0.0.0`), turn on a password and TLS in `~/.config/wayvnc/config` (see `man wayvnc`), because plain VNC is unencrypted.

**Languages** is a group in the same list, right under Dev: Python, PHP, GDScript, JavaScript/TypeScript, Rust, Go, C/C++, C#, Java, Lua. Each installs its runtime and package manager; the Neovim language server, formatter and parser come from LazyVim.

```bash
./install.sh --apps        # re-open only the app list, starting from your saved picks
./install.sh --reconfigure # open the settings menu again, starting from your saved answers
```

Unticking an app later does not uninstall it; remove it with `pacman -Rns` (or `flatpak uninstall`) yourself.

In an answers file (`--answers FILE`, or the saved `~/.config/nusku/answers`), `APPS=` and `LANGS=` hold space-separated ids from `packages/apps.list`, for example `APPS=neovim gh docker` and `LANGS=python go`. Leave them empty to install no optional apps or languages.

Apps from the AUR or Flathub are optional: if one fails to install, the rest carry on and the summary lists it under "Not installed (see the log)". Setup notes appear under "Notes".

### Neovim

When Neovim (LazyVim) is picked, `~/.config/nvim` becomes a link to the repo's [LazyVim](https://www.lazyvim.org/) config in Catppuccin Mocha with your accent colour (an existing `~/.config/nvim` is backed up first). Without it, `~/.config/nvim` is left alone. The installer syncs plugins, Mason tools and Treesitter parsers headless, so the first launch has nothing to download. Language extras follow the languages you picked; Python uses basedpyright.

- Plugin versions are pinned in `config/nvim/lazy-lock.json`, and every `install.sh` or `--update` resets your plugins to those versions. lazy.nvim only records the plugins in use, so to bump them: run `./install.sh --apps`, tick every language and let it finish; open Neovim and run `:Lazy update`; then copy `~/.local/share/nvim/lazy-lock.json` over `config/nvim/lazy-lock.json` in the repo and commit it.
- Extras you add by hand with `:LazyExtras` stay local (`config/nvim/lazyvim.json` is gitignored).
- GDScript's language server only works while the Godot editor is open.
- `Super + Shift + E` opens Yazi when it is installed.

### ArtCraft

[ArtCraft](https://getartcraft.com/apps) apps are early releases. Each picked app is installed from its latest GitHub release's Arch package (`ai.storyteller.<app>`), checked against the release's `SHA256SUMS.txt`.

- The ArtCraft Launcher is installed automatically when you pick any ArtCraft app. It keeps the apps (and itself) up to date; Nusku never updates ArtCraft itself, and an app that is already installed is skipped on later runs.
- The launcher starts hidden in the tray when you log in, so it can check for updates. To stop that, untick "Start when I log in" in the launcher.
- An app already installed from the AUR (`<app>`, `<app>-bin` or `<app>-git`) is left alone; the summary notes that the launcher won't update it.

### Docker and the firewall

- Docker adds you to the `docker` group, which is root-equivalent. Log out and back in to use `docker` without `sudo`.
- UFW denies incoming traffic by default. When LocalSend is also picked, port 53317 (TCP and UDP) is opened for it. SSH (22/tcp) is allowed automatically if the SSH server (or its socket) is enabled.
- Ports published by Docker containers (`docker run -p`) bypass UFW: Docker writes its own firewall rules. Bind them to `127.0.0.1` if they should stay local.

## Changing the accent

```bash
nusku-theme mauve
```

Any of the 14 Catppuccin accents works: rosewater flamingo pink mauve red maroon peach yellow green teal sky sapphire blue lavender. Hyprland, Waybar, SwayNC, rofi and kitty update straight away; the login screen, the GTK cursor and the folder colour (the nearest Papirus folder colour) follow after `nusku-update` (or `./install.sh --update`).

## Top bar and app launcher

- The right of the bar is the tray, the battery and one pill with the network, Bluetooth and notification icons. Click the pill (or press Super + N) for quick settings. Right-click the network icon to pick a Wi-Fi network, the Bluetooth icon to connect a device, or the bell to toggle Do Not Disturb. Hover them for the network name and connected devices.
- Click the clock for the drop-down calendar: a month you can page through (arrows, scroll or PgUp/PgDn; Today jumps back), with a dot on days that have events. Pick a day to list its events; pick an event or **Open Calendar** to see it in GNOME Calendar. Click the clock again, click elsewhere or press Esc to close it. Events come from GNOME's calendar service, so pick **GNOME Calendar** (Everyday) to have any: after installing it, log out and back in once (so the GNOME keyring is unlocked with your login), then open **Online Accounts** from the launcher to add Google or Nextcloud.
- Quick settings: Wi-Fi and Bluetooth (split buttons: the left part turns it on or off; the plug opens a picker to join a network, or to connect, disconnect and pair Bluetooth devices, with "Scan" to find new ones), then Do Not Disturb, night light, airplane mode, keep awake (pauses screen lock and sleep until the next login) sound mute and mic mute; then screenshot and power menu. The volume slider follows the default output: while a Moonlight stream is open, Sunshine moves sound to its own virtual output, and the slider will not track your speakers until the stream ends (in Moonlight, quit the session rather than just closing the window). Below them: brightness (laptops), volume (the arrow opens per-app volume), power mode, the media player and your notifications. The panel layout is `config/swaync/config.template.json`; the installer writes `~/.config/swaync/config.json` from it on every install and update, leaving out the brightness slider on machines without a backlight and power modes the machine does not offer.
- The app launcher hides developer and system tools (Qt tools, xgps, Rofi, theme tools) and gives a few apps a Papirus icon so they match. The list is `config/applications/overrides.list`; the tweaks live in `~/.local/share/applications` and are refreshed on every update. A `.desktop` file you put there yourself always wins.

## Per-machine overrides

Nusku never overwrites these files:

- `~/.config/nusku/local.lua` — Hyprland settings (monitors, input, extra binds). Loaded last, so it wins.
- `~/.config/nusku/local.zsh` — your own zsh additions, sourced at the end of `~/.zshrc`.

Built-in 1920×1200 and 1920×1080 laptop screens start at 1.25× scale (Hyprland's auto scale would pick 1.5×); every other screen uses auto. The installer writes that rule to `~/.config/nusku/gpu.lua`; a `hl.monitor` line in `local.lua` overrides it.

Hyprland's config is [Lua](https://wiki.hypr.land/Configuring/) (`~/.config/hypr/hyprland.lua` and the modules next to it). A `local.lua` override looks like this:

```lua
hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = 1 })
hl.config({ input = { kb_layout = "us,de", kb_options = "grp:alt_shift_toggle" } })
local B = require("bindlib")
B.bind("SUPER + D", "Discord", 'hl.dsp.exec_cmd("discord")')
```

Binds made with plain `hl.bind` work but don't show in the keybind menu (SUPER + /).

Upgrading from an older Nusku that used `local.conf`: that file is kept but no longer read. The installer warns if it holds settings; move them into `local.lua` in the syntax above. Log out and back in (or reboot) after updating: the running session still uses the old config.

With a Lua config, `hyprctl dispatch` takes `hl.dsp.*` expressions (e.g. `hyprctl dispatch 'hl.dsp.exit()'`), so personal scripts using the old form (`hyprctl dispatch exit`) need updating.

## Keybinds

`Super` is the main modifier. Press `Super + /` to search every keybind: type what you want (for example "screenshot"), and Enter runs it.

| Keys | Action |
| --- | --- |
| Super + Return | Terminal (kitty) |
| Super + Space | App launcher (rofi) |
| Super + E | File manager (Thunar) |
| Super + B | Web browser (your default) |
| Super + V | Clipboard history |
| Super + W | Wallpaper picker |
| Super + Escape | Power menu |
| Super + / | Search keybinds |
| Super + N | Quick settings and notifications |
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
