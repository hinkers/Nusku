# Nusku

Nusku is a Bash installer that turns a fresh Arch Linux install into a themed Hyprland desktop.

## Install

```bash
git clone https://github.com/<user>/nusku.git && cd nusku && ./install.sh
```

## Tests

Requires Docker. Runs shellcheck and the bats unit tests inside an Arch container:

```bash
bash test/run-unit.sh          # everything
bash test/run-unit.sh smoke    # only test/unit/smoke.bats
```
