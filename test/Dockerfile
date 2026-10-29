FROM archlinux:latest
RUN pacman -Syu --noconfirm bats shellcheck gum jq sudo git base-devel neovim \
    && pacman -Scc --noconfirm
RUN useradd -m -G wheel tester \
    && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester \
    && chmod 0440 /etc/sudoers.d/tester
USER tester
WORKDIR /nusku
