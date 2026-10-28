#!/usr/bin/env bash
# Optional app and language catalogue (packages/apps.list), parsed with awk, never sourced. Sourced, not executed.
# Needs lib/log.sh (die) and lib/answers.sh (answers_get).

: "${NUSKU_APPS_LIST:=${NUSKU_ROOT:-.}/packages/apps.list}"

# apps_groups: group ids in file order.
apps_groups() {
    awk -F'|' '$1 == "group" { print $2 }' "$NUSKU_APPS_LIST"
}

# apps_group_label GROUP
apps_group_label() {
    awk -F'|' -v id="$1" '$1 == "group" && $2 == id { print $3; exit }' "$NUSKU_APPS_LIST"
}

# apps_root_is_btrfs: status 0 when / is btrfs (NUSKU_ROOT_FSTYPE overrides the probe, for tests).
apps_root_is_btrfs() {
    [ "${NUSKU_ROOT_FSTYPE:-$(findmnt -no FSTYPE / 2>/dev/null)}" = btrfs ]
}

# apps_in_group GROUP: app ids in file order; btrfs-only apps appear only on a btrfs root.
apps_in_group() {
    local skip=1
    ! apps_root_is_btrfs || skip=0
    awk -F'|' -v g="$1" -v skip="$skip" '
        $1 == "app" && $2 == g {
            if (skip && (","$7",") ~ /,btrfs,/) next
            print $3
        }' "$NUSKU_APPS_LIST"
}

# apps_label ID: label of an app or a language.
apps_label() {
    awk -F'|' -v id="$1" '
        $1 == "app" && $3 == id { print $5; exit }
        $1 == "lang" && $2 == id { print $3; exit }' "$NUSKU_APPS_LIST"
}

# apps_starred: space-separated ids of the pre-selected favourites.
apps_starred() {
    awk -F'|' '$1 == "app" && $4 == "*" { printf "%s%s", sep, $3; sep = " " } END { print "" }' "$NUSKU_APPS_LIST"
}

# apps_langs: language ids in file order.
apps_langs() {
    awk -F'|' '$1 == "lang" { print $2 }' "$NUSKU_APPS_LIST"
}

# apps_packages ID: package tokens of an app or language, one per line.
apps_packages() {
    awk -F'|' -v id="$1" '
        $1 == "app" && $3 == id { n = split($6, t, " "); for (i = 1; i <= n; i++) print t[i]; exit }
        $1 == "lang" && $2 == id { n = split($4, t, " "); for (i = 1; i <= n; i++) print t[i]; exit }' "$NUSKU_APPS_LIST"
}

# apps_has_flag ID FLAG: status 0 when the app/language carries FLAG.
apps_has_flag() {
    awk -F'|' -v id="$1" -v flag="$2" '
        $1 == "app" && $3 == id { found = 1; f = $7 }
        $1 == "lang" && $2 == id { found = 1; f = $5 }
        found { exit ((","f",") ~ ("," flag ",") ? 0 : 1) }
        END { if (!found) exit 1 }' "$NUSKU_APPS_LIST"
}

# apps_validate_answers: every id in APPS and LANGS must exist in the catalogue.
apps_validate_answers() {
    local id
    for id in $(answers_get APPS); do
        awk -F'|' -v id="$id" '$1 == "app" && $3 == id { f = 1 } END { exit !f }' "$NUSKU_APPS_LIST" ||
            die "answers: unknown app '$id' in APPS; see packages/apps.list"
    done
    for id in $(answers_get LANGS); do
        awk -F'|' -v id="$id" '$1 == "lang" && $2 == id { f = 1 } END { exit !f }' "$NUSKU_APPS_LIST" ||
            die "answers: unknown language '$id' in LANGS; see packages/apps.list"
    done
}
