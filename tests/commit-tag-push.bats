#!/usr/bin/env bats

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../actions/create-metapackage-tag/commit-tag-push.bash"

setup() {
    setup_stub_path

    cd "$BATS_TEST_TMPDIR"
    touch composer.json composer.lock

    export CMD_LOG="$BATS_TEST_TMPDIR/cmd.log"
    touch "$CMD_LOG"
    stub_command git 'echo "git $*" >> "$CMD_LOG"'
    stub_command gh 'echo "gh $*" >> "$CMD_LOG"'

    export VERSION='4.6.30'
    export GIT_PUSH_ARGS=''
}

@test "authenticates, commits, tags and pushes in order" {
    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(cat "$CMD_LOG")" = 'gh auth setup-git
git config --local user.name github-actions[bot]
git config --local user.email 41898282+github-actions[bot]@users.noreply.github.com
git add composer.json composer.lock
git commit -m [composer] Set dependencies for 4.6.30 release + .lock
git tag v4.6.30
git push origin v4.6.30' ]
}

@test "appends extra git push arguments when provided" {
    GIT_PUSH_ARGS='--force-with-lease' run "$SCRIPT"

    [ "$status" -eq 0 ]
    grep -q '^git push origin v4.6.30 --force-with-lease$' "$CMD_LOG"
}

@test "fails when the commit fails" {
    stub_command git '
echo "git $*" >> "$CMD_LOG"
if [[ "$1" == "commit" ]]; then
    exit 1
fi'

    run "$SCRIPT"

    [ "$status" -ne 0 ]
    ! grep -q '^git tag' "$CMD_LOG"
}
