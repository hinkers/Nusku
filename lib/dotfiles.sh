#!/usr/bin/env bash
# Manifest-driven dotfile symlinks with backups. Sourced, not executed.
# Needs lib/log.sh and lib/backup.sh.

# _dotfiles_rel SRC_ABS: SRC relative to the repo root (for recognising our own old links).
_dotfiles_rel() {
    local src="$1" root
    root="${_DOTFILES_ROOT:-}"
    if [ -n "$root" ] && [ "${src#"$root"/}" != "$src" ]; then
        printf '%s\n' "${src#"$root"/}"
    else
        # Unknown root: fall back to the last two path components (e.g. config/hypr).
        printf '%s/%s\n' "$(basename "$(dirname "$src")")" "$(basename "$src")"
    fi
}

# link_file SRC_ABS DEST_ABS: symlink DEST -> SRC, backing up whatever was in the way.
link_file() {
    local src="${1:?link_file needs a source}" dest="${2:?link_file needs a dest}" rel target
    if [ -L "$dest" ]; then
        target="$(readlink "$dest")"
        if [ "$target" = "$src" ]; then
            return 0
        fi
        rel="$(_dotfiles_rel "$src")"
        case "$target" in
            */"$rel")
                log_info "Replacing old Nusku link $dest -> $target"
                rm -f "$dest" || die "Could not remove $dest"
                ;;
            *)
                backup_file "$dest"
                rm -f "$dest" || die "Could not remove $dest"
                ;;
        esac
    elif [ -e "$dest" ]; then
        backup_file "$dest"
        rm -rf "$dest" || die "Could not remove $dest"
    fi
    mkdir -p "$(dirname "$dest")" || die "Could not create $(dirname "$dest")"
    ln -s "$src" "$dest" || die "Could not link $dest"
    log_info "Linked $dest -> $src"
}

# deploy_dotfiles REPO_ROOT [MANIFEST]: link everything listed in the manifest.
deploy_dotfiles() {
    local root="${1:?deploy_dotfiles needs the repo root}"
    local manifest="${2:-$root/config/links.txt}"
    local src dest extra m
    [ -f "$manifest" ] || die "Dotfile manifest not found: $manifest"
    _DOTFILES_ROOT="$root"
    while read -r src dest extra || [ -n "$src" ]; do
        case "$src" in '' | '#'*) continue ;; esac
        [ -n "$dest" ] && [ -z "$extra" ] || die "Bad manifest line: $src $dest $extra"
        case "$dest" in
            /* | ../* | */../* | */.. | ..) die "Manifest dest must be relative to \$HOME without '..': $dest" ;;
        esac
        case "$src" in
            *[\*\?\[]*)
                # Glob: dest is a directory; no matches is fine (scripts may not exist yet).
                while IFS= read -r m; do
                    [ -n "$m" ] || continue
                    link_file "$root/$m" "$HOME/$dest/$(basename "$m")"
                done < <(cd "$root" && compgen -G "$src" | sort)
                ;;
            *)
                if [ ! -e "$root/$src" ]; then
                    log_warn "Skipping $src: not in the repo yet"
                    continue
                fi
                link_file "$root/$src" "$HOME/$dest"
                ;;
        esac
    done <"$manifest"
    unset _DOTFILES_ROOT
}
