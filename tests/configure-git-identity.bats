#!/usr/bin/env bats

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../actions/setup-app-git-identity/configure-git-identity.bash"

setup() {
    setup_stub_path

    export CMD_LOG="$BATS_TEST_TMPDIR/cmd.log"
    export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output.txt"
    touch "$CMD_LOG" "$GITHUB_OUTPUT"
    stub_command git 'echo "git $*" >> "$CMD_LOG"'
    stub_command gh 'echo "gh $*" >> "$CMD_LOG"; echo 123456'

    export APP_SLUG='ibexa-workflow-automation-1'
    export GH_TOKEN='token'
}

@test "resolves the bot user id and configures the global git identity" {
    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(cat "$CMD_LOG")" = 'gh api /users/ibexa-workflow-automation-1[bot] --jq .id
git config --global user.name ibexa-workflow-automation-1[bot]
git config --global user.email 123456+ibexa-workflow-automation-1[bot]@users.noreply.github.com' ]
}

@test "exposes the identity as step outputs" {
    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(cat "$GITHUB_OUTPUT")" = 'user-id=123456
user-name=ibexa-workflow-automation-1[bot]
user-email=123456+ibexa-workflow-automation-1[bot]@users.noreply.github.com' ]
}

@test "fails when the bot user cannot be resolved" {
    stub_command gh 'exit 1'

    run "$SCRIPT"

    [ "$status" -ne 0 ]
    ! grep -q '^git config' "$CMD_LOG"
    [ ! -s "$GITHUB_OUTPUT" ]
}
