@test "bats runs" { run true; [ "$status" -eq 0 ]; }

# Scripts are linked into ~/.local/bin and run by name, so git must carry the exec bit
# (a checkout on Linux takes the mode from git, not from this working copy).
@test "every script in scripts/ is executable in git" {
    git config --global --add safe.directory "$PWD" 2>/dev/null || true
    run git ls-files -s scripts/
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    ! grep -v '^100755 ' <<<"$output" || false
}
