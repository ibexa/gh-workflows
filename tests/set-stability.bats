#!/usr/bin/env bats

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../actions/create-metapackage-tag/set-stability.bash"

setup() {
    setup_stub_path

    export COMPOSER_LOG="$BATS_TEST_TMPDIR/composer.log"
    touch "$COMPOSER_LOG"
    stub_command composer 'echo "composer $*" >> "$COMPOSER_LOG"'
}

@test "unsets minimum-stability and prefer-stable for a stable version" {
    VERSION='4.6.30' run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(cat "$COMPOSER_LOG")" = 'composer config minimum-stability --unset
composer config prefer-stable --unset' ]
}

@test "sets alpha stability for an alpha version" {
    VERSION='4.6.30-alpha2' run "$SCRIPT"

    [ "$status" -eq 0 ]
    grep -q '^composer config prefer-stable true$' "$COMPOSER_LOG"
    grep -q '^composer config minimum-stability alpha$' "$COMPOSER_LOG"
}

@test "sets beta stability for a beta version" {
    VERSION='4.6.30-beta1' run "$SCRIPT"

    [ "$status" -eq 0 ]
    grep -q '^composer config prefer-stable true$' "$COMPOSER_LOG"
    grep -q '^composer config minimum-stability beta$' "$COMPOSER_LOG"
}

@test "sets rc stability for a release candidate version" {
    VERSION='4.6.30-rc1' run "$SCRIPT"

    [ "$status" -eq 0 ]
    grep -q '^composer config prefer-stable true$' "$COMPOSER_LOG"
    grep -q '^composer config minimum-stability rc$' "$COMPOSER_LOG"
}

@test "leaves stability unset for an unrecognized suffix" {
    VERSION='4.6.30-dev1' run "$SCRIPT"

    [ "$status" -eq 0 ]
    ! grep -q 'prefer-stable true' "$COMPOSER_LOG"
    ! grep -qE 'minimum-stability (alpha|beta|rc)' "$COMPOSER_LOG"
}
